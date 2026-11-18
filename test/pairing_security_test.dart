import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:twist_cast/features/cast/receiver_view.dart';
import 'package:twist_cast/features/home/app_brand.dart';
import 'package:twist_cast/features/home/app_footer.dart';
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
      home: Scaffold(appBar: AppBar(title: const AppBrand()),
        bottomNavigationBar: const AppFooter(),
        body: ReceiverView(renderer: renderer, onStop: () { stopped = true; })),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(1));
    expect(calls.single.arguments['aspectRatio'], closeTo(0.45, 0.001));
    expect(calls.single.arguments['chromeHeight'], 140);
    expect(tester.getBottomRight(find.text('Stop')).dy,
      lessThan(tester.getTopLeft(find.byType(RTCVideoView)).dy));
    renderer.value = renderer.value.copyWith(rotation: 90);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(2));
    expect(calls.last.arguments['aspectRatio'], closeTo(2400 / 1080, 0.001));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(2));
    await tester.tap(find.byType(OutlinedButton));
    expect(stopped, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await renderer.dispose();
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
