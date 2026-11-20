import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:twist_cast/features/cast/diagnostic_log.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:twist_cast/features/cast/receiver_page.dart';
import 'package:twist_cast/features/cast/receiver_pointer.dart';
import 'package:twist_cast/features/cast/cast_diagnostics.dart';
import 'package:twist_cast/features/home/app_brand.dart';
import 'package:twist_cast/features/home/app_footer.dart';
import 'package:twist_cast/features/updates/update_controller.dart';
import 'package:twist_cast/features/updates/update_card.dart';
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

  test('a newer Android release replaces a downloaded update without installing it first', () {
    final controller = UpdateController();
    addTearDown(controller.dispose);
    controller.state = {
      'version': '0.1.8', 'buildNumber': 10018, 'phase': 'ready',
      'targetVersion': '0.1.9', 'targetBuild': 10019,
    };
    controller.release = const AppRelease('0.1.10', '', '', build: 10020);
    expect(controller.hasNewerDownload, isTrue);
    expect(controller.canInstallDownloaded, isFalse);

    controller.release = const AppRelease('0.1.9', '', '', build: 10020);
    expect(controller.hasNewerDownload, isTrue);
    expect(controller.canInstallDownloaded, isFalse);

    controller.release = const AppRelease('0.1.9', '', '', build: 10019);
    expect(controller.hasNewerDownload, isFalse);
    expect(controller.canInstallDownloaded, isTrue);

    controller.release = null;
    expect(controller.canInstallDownloaded, isTrue);
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
    expect(find.byType(AppBrand), Platform.isMacOS ? findsNothing : findsOneWidget);
    expect(find.text('© · 2026 · CELFS · v0.1.13'), findsOneWidget);
    if (Platform.isMacOS) {
      expect(tester.getSize(find.byType(AppFooter)).height, 20);
    } else {
      expect(tester.getBottomRight(find.byType(AppFooter)).dy, 600);
      expect(tester.getTopLeft(find.byType(AppBrand)).dx, 16);
    }
    expect(find.text('Connected · encrypted screen sharing'), findsNothing);
    await tester.tap(Platform.isMacOS
      ? find.byType(PopupMenuButton<Locale>)
      : find.byType(DropdownButton<Locale>));
    await tester.pumpAndSettle();
    if (Platform.isMacOS || Platform.isAndroid) {
      expect(find.text('Check failed. Try again.'), findsOneWidget);
    }
    await tester.tap(find.text('简体中文').last);
    await tester.pumpAndSettle();
    expect(find.text('开始接收'), findsOneWidget);
    tester.view.physicalSize = const Size(320, 360);
    await tester.pumpAndSettle();
    final footer = find.byType(AppFooter);
    if (Platform.isMacOS) {
      expect(tester.getTopLeft(footer).dy, greaterThan(360));
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(footer).dy, lessThanOrEqualTo(360));
    } else {
      expect(tester.getBottomRight(footer).dy, 360);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('trackpad pans send one continuous swipe from the shared image', (tester) async {
    final events = <(String, Offset)>[];
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
      width: 300,
      height: 200,
      child: ReceiverPointer(videoSize: const Size(1, 1),
        onPointer: (action, point, _, _) => events.add((action, point)),
        child: const SizedBox.expand()),
    ))));
    final center = tester.getCenter(find.byType(ReceiverPointer));
    final outside = center - const Offset(125, 0);
    final ignored = await tester.startGesture(outside, kind: PointerDeviceKind.trackpad);
    await ignored.panZoomUpdate(outside, pan: const Offset(0, -40));
    await ignored.panZoomEnd();
    expect(events, isEmpty);

    final swipe = await tester.startGesture(center, kind: PointerDeviceKind.trackpad);
    await swipe.panZoomUpdate(center, pan: const Offset(0, -1));
    expect(events, isEmpty);
    await swipe.panZoomUpdate(center, pan: const Offset(0, -20),
      timeStamp: const Duration(milliseconds: 40));
    await swipe.panZoomUpdate(center, pan: const Offset(0, -40),
      timeStamp: const Duration(milliseconds: 50));
    await swipe.panZoomEnd();
    expect(events, [
      ('down', const Offset(0.5, 0.5)),
      ('move', const Offset(0.5, 0.4)),
      ('up', const Offset(0.5, 0.3)),
    ]);
  });

  testWidgets('receiver resizes once per settled screen ratio and keeps controls above video', (tester) async {
    const window = MethodChannel('app.twist.cast/window');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(window, (call) async {
      if (call.method == 'fitVideo') calls.add(call);
      return null;
    });
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
    final mac = Platform.isMacOS;
    expect(calls.single.arguments['chromeHeight'], mac ? 82 : 48);
    expect(find.byType(AppBrand), findsNothing);
    expect(find.byType(AppFooter), findsNothing);
    await tester.tap(find.byTooltip('Show title and language'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(mac ? 1 : 2));
    expect(calls.last.arguments['chromeHeight'], mac ? 82 : 104);
    expect(find.byType(AppBrand), findsOneWidget);
    expect(find.byType(AppFooter), findsNothing);
    await tester.tap(find.byTooltip('Hide title and language').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(mac ? 1 : 3));
    expect(calls.last.arguments['chromeHeight'], mac ? 82 : 48);
    expect(find.byType(AppBrand), findsNothing);
    expect(tester.getBottomRight(find.text('Stop')).dy,
      lessThan(tester.getTopLeft(find.byType(RTCVideoView)).dy));
    renderer.value = renderer.value.copyWith(rotation: 90);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(mac ? 2 : 4));
    expect(calls.last.arguments['aspectRatio'], closeTo(2400 / 1080, 0.001));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(mac ? 2 : 4));
    await tester.tap(find.byType(OutlinedButton));
    expect(stopped, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await renderer.dispose();
  });

  testWidgets('native receiver controls overlay video without resizing it', (tester) async {
    if (!Platform.isMacOS) return;
    const window = MethodChannel('app.twist.cast/window');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(window, (call) async {
      calls.add(call);
      return call.method == 'receiverControls' ? call.arguments['enabled'] : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(window, null));
    final renderer = RTCVideoRenderer();
    renderer.value = renderer.value.copyWith(width: 1080, height: 2400);
    var stopped = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReceiverPage(renderer: renderer, onStop: () { stopped = true; },
        header: AppBar(title: const AppBrand())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final fits = calls.where((call) => call.method == 'fitVideo').toList();
    expect(fits.last.arguments['chromeHeight'], 34);
    expect(fits.last.arguments['horizontalInset'], 12);
    expect(find.text('Stop'), findsNothing);
    expect(find.byType(AppBrand), findsNothing);
    expect(find.byType(AppFooter), findsNothing);
    await messenger.handlePlatformMessage(window.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('toggleReceiverControls')), (_) {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Stop'), findsOneWidget);
    expect(find.byType(AppBrand), findsOneWidget);
    expect(calls.where((call) => call.method == 'fitVideo').length, fits.length);
    await tester.tap(find.byType(OutlinedButton));
    expect(stopped, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Stop'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(calls.last.method, 'receiverControls');
    expect(calls.last.arguments['enabled'], isFalse);
    await renderer.dispose();
  });

  testWidgets('update checks can be retried while screen sharing is active', (tester) async {
    const updates = MethodChannel('app.twist.cast/updates');
    var checks = 0;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(updates, (_) async {
      checks++;
      throw PlatformException(code: 'offline');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(updates, null));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: UpdateCard(sessionActive: true, onInstallingChanged: (_) {})),
    ));
    await tester.pumpAndSettle();
    expect(checks, 1);
    await tester.tap(find.byTooltip('Check for updates'));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(tester.takeException(), isNull);
  });

  test('update failures distinguish network, rate limits, and invalid release metadata', () {
    expect(UpdateController.checkError(const SocketException('offline')), 'checkNetwork');
    expect(UpdateController.checkError(TimeoutException('timeout')), 'checkNetwork');
    expect(UpdateController.checkError(const UpdateHttpException(403, true)), 'checkRateLimit');
    expect(UpdateController.checkError(const UpdateHttpException(404, false)), 'checkService');
    expect(UpdateController.checkError(const FormatException('manifest')), 'checkMetadata');
  });

  test('diagnostic export retains native build identity and surfaces save failures', () async {
    const updates = MethodChannel('app.twist.cast/updates');
    const export = MethodChannel('app.twist.cast/diagnostics');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(updates, (_) async => {
      'version': '0.1.8', 'buildNumber': 10020, 'commit': 'abcdef0123456789', 'targetUrl': 'private-value',
    });
    messenger.setMockMethodCallHandler(export, (call) async {
      final report = jsonDecode((call.arguments as Map)['json'] as String) as Map;
      expect(report.toString(), isNot(contains('private-value')));
      expect(report['commit'], 'abcdef0123456789');
      expect((report['records'] as List).last['installedBuild'], 10020);
      return false;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(updates, null);
      messenger.setMockMethodCallHandler(export, null);
    });
    final log = DiagnosticLog('receiver');
    expect(await log.export(), isFalse);
    messenger.setMockMethodCallHandler(export, (_) async => throw PlatformException(code: 'export'));
    await expectLater(log.export(), throwsA(isA<PlatformException>()));
  });

  test('diagnostics bound retained records and measure interval audio throughput', () {
    final log = DiagnosticLog('sender');
    for (var i = 0; i < DiagnosticLog.capacity + 3; i++) {
      log.add({'index': i});
    }
    final decoded = jsonDecode(log.encode()) as Map;
    expect((decoded['records'] as List).length, DiagnosticLog.capacity);
    expect(decoded['discardedRecords'], 4);
    final samples = CastStatsSamples();
    StatsReport audio(int bytes, int concealed) => StatsReport('audio', 'inbound-rtp', 0, {
      'kind': 'audio', 'bytesReceived': bytes, 'concealedSamples': concealed,
      'address': 'must-not-export',
    });
    samples.add([audio(1000, 10)]);
    final metrics = samples.add([audio(3000, 20)], intervalMs: 1000).single;
    expect(metrics['bytesReceivedKbps'], 16);
    expect(metrics['concealedSamplesDelta'], 10);
    expect(metrics.containsKey('address'), isFalse);
    expect(samples.add([audio(0, 0)], intervalMs: 1000).single.containsKey('bytesReceivedKbps'), isFalse);
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
