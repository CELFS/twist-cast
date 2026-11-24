import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:twist_cast/features/cast/cast_media.dart';
import 'package:twist_cast/features/cast/diagnostic_log.dart';
import 'package:twist_cast/features/cast/receiver_page.dart';
import 'package:twist_cast/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('paste needs a compatible Android offer and an active control grant', () async {
    for (final name in ['FlutterWebRTC.Event', 'FlutterWebRTC/Texture7', 'FlutterWebRTC/peerConnectionEventphone']) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    const rtc = MethodChannel('FlutterWebRTC.Method');
    messenger.setMockMethodCallHandler(rtc, (call) async => switch (call.method) {
      'createVideoRenderer' => {'textureId': 7},
      'createPeerConnection' => {'peerConnectionId': 'phone'},
      'createAnswer' => {'sdp': 'answer', 'type': 'answer'},
      _ => null,
    });
    addTearDown(() => messenger.setMockMethodCallHandler(rtc, null));
    var reads = 0;
    const sample = '  中文🙂\nhttps://example.com/a?b=1  ';
    var clipboard = sample;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      expect(call.method, 'Clipboard.getData');
      reads++;
      return {'text': clipboard};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    for (final supportsPaste in [false, true]) {
      final sent = <Map<String, dynamic>>[];
      final request = Completer<Map<String, dynamic>>();
      final media = CastMedia(send: (message) {
        sent.add(message);
        if (message['type'] == 'paste') request.complete(message);
      }, onConnected: () {}, onStopped: () {}, log: DiagnosticLog('receiver'));
      addTearDown(media.close);
      await media.prepare();
      await media.handle({'type': 'offer', 'sdp': 'offer', 'touch': true, if (supportsPaste) 'paste': true});
      expect(sent.single['paste'] == true, supportsPaste);
      media.renderer.onFirstFrameRendered!();
      expect(await media.pasteFromClipboard(), PhonePasteResult.unavailable);
      expect(reads, 0);
      await media.handle({'type': 'touch-state', 'enabled': true});
      if (!supportsPaste) {
        expect(await media.pasteFromClipboard(), PhonePasteResult.unavailable);
        expect(reads, 0);
      } else {
        final result = media.pasteFromClipboard();
        final paste = await request.future;
        expect(paste['text'], sample);
        expect(reads, 1);
        await media.handle({'type': 'paste-result', 'id': -1, 'status': 'noField'});
        await media.handle({'type': 'paste-result', 'id': paste['id'], 'status': 'pasted'});
        expect(await result, PhonePasteResult.pasted);
        clipboard = '';
        expect(await media.pasteFromClipboard(), PhonePasteResult.empty);
        clipboard = 'x' * 16385;
        expect(await media.pasteFromClipboard(), PhonePasteResult.tooLong);
        await media.handle({'type': 'touch-state', 'enabled': false});
        expect(await media.pasteFromClipboard(), PhonePasteResult.unavailable);
        expect(sent.where((m) => m['type'] == 'paste'), hasLength(1));
        expect(reads, 3);
      }
      await media.close();
    }
  });

  testWidgets('desktop paste shortcut acts on the focused cast picture', (tester) async {
    const window = MethodChannel('app.twist.cast/window');
    messenger.setMockMethodCallHandler(window, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(window, null));
    final renderer = RTCVideoRenderer();
    var calls = 0;
    Widget page(bool allowed) => MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReceiverPage(renderer: renderer, onStop: () {}, header: AppBar(),
        onPaste: allowed ? () async { calls++; return PhonePasteResult.noField; } : null));
    Future<void> shortcut() async {
      final modifier = Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    await tester.pumpWidget(page(true));
    await tester.tapAt(tester.getCenter(find.byType(RTCVideoView)));
    await tester.pump();
    await shortcut();
    expect(calls, 1);
    expect(find.text('Click an editable field on the phone first.'), findsOneWidget);
    await tester.pumpWidget(page(false));
    await shortcut();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await renderer.dispose();
  });
}
