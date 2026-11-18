import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:twist_cast/features/cast/receiver_page.dart';
import 'package:twist_cast/features/cast/cast_diagnostics.dart';
import 'package:twist_cast/features/home/app_brand.dart';
import 'package:twist_cast/features/home/app_footer.dart';
import 'package:twist_cast/features/updates/update_controller.dart';
import 'package:twist_cast/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:twist_cast/app.dart';
import 'package:twist_cast/core/device_identity.dart';
import 'package:twist_cast/core/pairing_invitation.dart';
import 'package:twist_cast/core/secure_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This suite exercises real LAN sockets, not Flutter's default HTTP stub.
  HttpOverrides.global = null;

  test('updates recognize newer same-version builds and reject older builds', () {
    expect(UpdateController.isNewerBuild('0.1.5', 10016, '0.1.5', 10015), isTrue);
    expect(UpdateController.isNewerBuild('0.1.5', 10015, '0.1.5', 10015), isFalse);
    expect(UpdateController.isNewerBuild('0.1.5', 10014, '0.1.5', 10015), isFalse);
    expect(UpdateController.isNewerBuild('0.1.4', 10016, '0.1.5', 10015), isFalse);
    expect(UpdateController.isNewerBuild('0.1.6', 10014, '0.1.5', 10015), isFalse);
    expect(UpdateController.isNewerBuild('0.1.6', 10016, '0.1.5', 10015), isTrue);
    expect(UpdateController.isNewerBuild('0.1.6', 0, '0.1.5', 6), isTrue);
    expect(UpdateController.isNewerBuild('0.1.5', 10015, '0.1.5', 6), isTrue);
    const release = AppRelease('0.1.5', '', '', build: 10015);
    expect(release.label, 'v0.1.5+10015');
  });

  testWidgets('desktop starts offline, fits a compact window and switches language', (tester) async {
    const updates = MethodChannel('app.twist.cast/updates');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(updates, (_) async => throw PlatformException(code: 'offline'));
    addTearDown(() => messenger.setMockMethodCallHandler(updates, null));
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const TwistCastApp());
    expect(find.text('Start receiving'), findsOneWidget);
    expect(find.byType(AppBrand), findsOneWidget);
    expect(find.text('© · 2026 · CELFS · v0.1.5'), findsOneWidget);
    expect(tester.getBottomRight(find.byType(AppFooter)).dy, 600);
    expect(tester.getTopLeft(find.byType(AppBrand)).dx, 16);
    expect(find.text('Connected · encrypted screen sharing'), findsNothing);
    await tester.tap(find.byType(DropdownButton<Locale>));
    await tester.pumpAndSettle();
    if (Platform.isMacOS || Platform.isAndroid) {
      expect(find.text('Could not check for updates. Check your connection to GitHub and try again.'), findsOneWidget);
    }
    await tester.tap(find.text('简体中文').last);
    await tester.pumpAndSettle();
    expect(find.text('开始接收'), findsOneWidget);
    tester.view.physicalSize = const Size(320, 600);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.byType(AppFooter)).dy, 600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('receiver resizes once per settled screen ratio and keeps controls above video', (tester) async {
    const window = MethodChannel('app.twist.cast/window');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(window, (call) async { calls.add(call); return null; });
    addTearDown(() => messenger.setMockMethodCallHandler(window, null));
    final renderer = RTCVideoRenderer();
    renderer.value = renderer.value.copyWith(width: 1080, height: 2400);
    bool stopped = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReceiverPage(renderer: renderer, onStop: () { stopped = true; },
        header: AppBar(title: const AppBrand())),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(1));
    expect(calls.single.arguments['aspectRatio'], closeTo(0.45, 0.001));
    expect(calls.single.arguments['chromeHeight'], 48);
    expect(find.byType(AppBrand), findsNothing);
    expect(find.byType(AppFooter), findsNothing);
    await tester.tap(find.byTooltip('Show title and language'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(2));
    expect(calls.last.arguments['chromeHeight'], 104);
    expect(find.byType(AppBrand), findsOneWidget);
    expect(find.byType(AppFooter), findsNothing);
    await tester.tap(find.byTooltip('Hide title and language'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(3));
    expect(calls.last.arguments['chromeHeight'], 48);
    expect(find.byType(AppBrand), findsNothing);
    expect(tester.getBottomRight(find.text('Stop')).dy,
      lessThan(tester.getTopLeft(find.byType(RTCVideoView)).dy));
    renderer.value = renderer.value.copyWith(rotation: 90);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(4));
    expect(calls.last.arguments['aspectRatio'], closeTo(2400 / 1080, 0.001));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(4));
    await tester.tap(find.byType(OutlinedButton));
    expect(stopped, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await renderer.dispose();
  });

  test('media diagnostics measure interval delay and discard reset counters', () {
    final samples = CastStatsSamples();
    StatsReport video(double delay, int count) => StatsReport('video', 'inbound-rtp', 0, {
      'kind': 'video', 'jitterBufferDelay': delay, 'jitterBufferEmittedCount': count,
      'codecId': 'codec', 'privateValue': 'must not be logged',
    });
    expect(samples.add([video(100, 1000)]).single.containsKey('jitterBufferMs'), isFalse);
    final metrics = samples.add([video(120, 1010),
      StatsReport('codec', 'codec', 0, {'mimeType': 'video/H264'}),
      StatsReport('transport', 'transport', 0, {'selectedCandidatePairId': 'selected'}),
      StatsReport('selected', 'candidate-pair', 0, {'currentRoundTripTime': 0.025}),
      StatsReport('unused', 'candidate-pair', 0, {'currentRoundTripTime': 9}),
    ]);
    expect(metrics.first['jitterBufferMs'], 2000);
    expect(metrics.first['codec'], 'video/H264');
    expect(metrics.last, {'networkRttMs': 25});
    expect(metrics.toString(), isNot(contains('privateValue')));
    expect(samples.add([video(1, 10)]).single.containsKey('jitterBufferMs'), isFalse);
  });

  test('rejects public, loopback, expired and malformed QR invitations', () {
    for (final address in ['8.8.8.8', '127.0.0.1', '::1', 'example.com', '0.0.0.0']) {
      expect(PairingInvitation.isLanAddress(address), isFalse);
    }
    expect(PairingInvitation.isLanAddress('192.168.1.2'), isTrue);
    expect(() => PairingInvitation.parse('https://example.com'), throwsA(isA<FormatException>()));
    final expired = PairingInvitation(host: '192.168.1.2', port: 1234,
      fingerprint: 'a' * 64, token: 'b' * 43,
      expires: DateTime.now().subtract(const Duration(seconds: 1)));
    expect(() => PairingInvitation.parse(expired.encode()), throwsA(isA<FormatException>()));
  });

  test('real TLS pairing requires BOTH approvals and rejects a changed certificate pin', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final receiverIdentity = await DeviceIdentity.load();
    FlutterSecureStorage.setMockInitialValues({});
    final senderIdentity = await DeviceIdentity.load();
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final host = interfaces.expand((item) => item.addresses).map((item) => item.address)
        .firstWhere(PairingInvitation.isLanAddress);
    final receiverCode = Completer<String>();
    final senderCode = Completer<String>();
    final receiverReady = Completer<void>();
    final senderReady = Completer<void>();
    final received = Completer<Map<String, dynamic>>();
    final receiver = SecureSession(identity: receiverIdentity,
      onPairing: (code, _) => receiverCode.complete(code),
      onAuthorized: () async => receiverReady.complete(),
      onMessage: (message) async => received.complete(message), onClosed: () {});
    final sender = SecureSession(identity: senderIdentity,
      onPairing: (code, _) => senderCode.complete(code),
      onAuthorized: () async => senderReady.complete(),
      onMessage: (_) async {}, onClosed: () {});
    addTearDown(receiver.close);
    addTearDown(sender.close);
    final port = await receiver.listen();
    expect(() => sender.send({'type': 'offer', 'sdp': 'unauthorized'}), throwsStateError);
    final invitation = receiver.invitation(host);
    final wrongPin = SecureSession(identity: senderIdentity, onPairing: (_, _) {},
      onAuthorized: () async {}, onMessage: (_) async {}, onClosed: () {});
    addTearDown(wrongPin.close);
    await expectLater(wrongPin.connect(host, port, invitation: PairingInvitation(
      host: host, port: port, fingerprint: '0' * 64, token: invitation.token,
      expires: invitation.expires)), throwsA(anything));
    await sender.connect(host, port, invitation: invitation);
    expect(await receiverCode.future.timeout(const Duration(seconds: 10)),
      await senderCode.future.timeout(const Duration(seconds: 10)));
    await sender.approve();
    expect(senderReady.isCompleted, isFalse);
    expect(receiverReady.isCompleted, isFalse);
    expect(() => sender.send({'type': 'offer', 'sdp': 'unauthorized'}), throwsStateError);
    await receiver.approve();
    await Future.wait([receiverReady.future, senderReady.future]).timeout(const Duration(seconds: 10));
    sender.send({'type': 'offer', 'sdp': 'authorized-payload'});
    expect((await received.future.timeout(const Duration(seconds: 10)))['sdp'], 'authorized-payload');
    await sender.close();
    expect(() => sender.send({'type': 'offer'}), throwsStateError);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
