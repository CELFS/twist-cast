import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:nanoid/nanoid.dart';

import '../../core/device_identity.dart';
import '../../core/pairing_invitation.dart';
import '../../core/secure_session.dart';
import 'cast_media.dart';

enum CastPhase { idle, preparing, receiving, searching, pairing, connecting, casting, ended, failed }

class CastController extends ChangeNotifier {
  static const serviceType = '_twistcast._tcp';
  CastPhase phase = CastPhase.idle;
  String? comparison;
  bool knownPeer = false;
  bool approved = false;
  bool audio = false;
  bool sending = false;
  bool audioBusy = false;
  String notificationTitle = '';
  String notificationBody = '';
  List<String> addresses = [];
  String? selectedAddress;
  final devices = <String, BonsoirService>{};
  DeviceIdentity? _identity;
  SecureSession? _session;
  CastMedia? media;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoveryEvents;
  Timer? _searchDeadline;
  Timer? _connectionDeadline;
  bool _disposed = false;
  int _generation = 0;

  bool get isMobile => Platform.isAndroid || Platform.isIOS;
  bool get busy => phase == CastPhase.preparing || phase == CastPhase.connecting;
  String? get qr => selectedAddress == null || phase != CastPhase.receiving
      ? null : _session?.invitation(selectedAddress!).encode();

  void _update(CastPhase value) { phase = value; if (!_disposed) notifyListeners(); }
  void selectAddress(String address) { selectedAddress = address; notifyListeners(); }

  Future<SecureSession> _newSession(int generation) async {
    _identity ??= await DeviceIdentity.load();
    if (generation != _generation) throw StateError('Cancelled');
    late SecureSession session;
    session = SecureSession(identity: _identity!, onPairing: (code, known) {
      if (generation != _generation) return;
      comparison = code;
      knownPeer = known;
      _stopDiscovery();
      _update(CastPhase.pairing);
    }, onAuthorized: () async {
      if (generation != _generation) return;
      _update(CastPhase.connecting);
      _connectionDeadline = Timer(const Duration(seconds: 90), () => stop(failed: true));
      final transport = CastMedia(send: session.send,
        onStopped: () { if (generation == _generation) stop(); },
        onConnected: () {
          if (generation != _generation) return;
          _connectionDeadline?.cancel();
          _update(CastPhase.casting);
        });
      media = transport;
      await transport.prepare();
      if (generation != _generation) { await transport.close(); return; }
      if (sending) await transport.share(audio: audio, title: notificationTitle, body: notificationBody);
      if (!_disposed) notifyListeners();
    }, onMessage: (message) async { await media?.handle(message); }, onClosed: () {
      if (generation == _generation) stop();
    });
    return session;
  }

  Future<void> receive() async {
    await stop();
    final generation = ++_generation;
    sending = false;
    _update(CastPhase.preparing);
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      addresses = interfaces.expand((entry) => entry.addresses).map((address) => address.address)
          .where(PairingInvitation.isLanAddress).toSet().toList();
      if (addresses.isEmpty) throw StateError('No LAN interface');
      selectedAddress = addresses.first;
      final session = await _newSession(generation);
      _session = session;
      final port = await session.listen();
      if (generation != _generation) { await session.close(); return; }
      final broadcast = BonsoirBroadcast(service: BonsoirService(
        name: 'TwistCast ${nanoid(6)}', type: serviceType, port: port,
        attributes: const {'v': '1'},
      ));
      _broadcast = broadcast;
      await broadcast.initialize();
      if (generation != _generation) { await broadcast.stop(); return; }
      await broadcast.start();
      if (generation != _generation) { await broadcast.stop(); return; }
      _update(CastPhase.receiving);
    } catch (_) { if (generation == _generation) await stop(failed: true); }
  }

  Future<void> search() async {
    await stop();
    final generation = ++_generation;
    sending = true;
    devices.clear();
    _update(CastPhase.searching);
    try {
      final discovery = BonsoirDiscovery(type: serviceType);
      _discovery = discovery;
      await discovery.initialize();
      if (generation != _generation) { await discovery.stop(); return; }
      _discoveryEvents = discovery.eventStream!.listen((event) {
        if (generation != _generation) return;
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            event.service.resolve(discovery.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent():
            if (event.service.attributes['v'] == '1' &&
                event.service.hostAddresses.any((address) => PairingInvitation.isLanAddress(address) &&
                    InternetAddress.tryParse(address)?.type == InternetAddressType.IPv4)) {
              devices[event.service.name] = event.service;
              notifyListeners();
            }
          case BonsoirDiscoveryServiceLostEvent():
            devices.remove(event.service.name);
            notifyListeners();
          default: break;
        }
      }, onError: (_) => stop(failed: true));
      await discovery.start();
      if (generation != _generation) { await discovery.stop(); return; }
      _searchDeadline = Timer(const Duration(minutes: 2), stop);
    } catch (_) { if (generation == _generation) await stop(failed: true); }
  }

  Future<void> connectDevice(BonsoirService device) => _connect(
    device.hostAddresses.firstWhere((address) => PairingInvitation.isLanAddress(address) &&
        InternetAddress.tryParse(address)?.type == InternetAddressType.IPv4), device.port,
  );

  Future<void> scanResult(String value) async {
    try {
      final invitation = PairingInvitation.parse(value);
      await _connect(invitation.host, invitation.port, invitation: invitation);
    } catch (_) { await stop(failed: true); }
  }

  Future<void> _connect(String host, int port, {PairingInvitation? invitation}) async {
    await stop();
    final generation = ++_generation;
    sending = true;
    _update(CastPhase.preparing);
    try {
      final session = await _newSession(generation);
      _session = session;
      await session.connect(host, port, invitation: invitation);
      if (generation != _generation) { await session.close(); return; }
    } catch (_) { if (generation == _generation) await stop(failed: true); }
  }

  Future<void> approve() async {
    approved = true;
    notifyListeners();
    try { await _session?.approve(); } catch (_) { await stop(failed: true); }
  }

  Future<void> setAudio(bool value) async {
    if (audioBusy) return;
    audioBusy = true;
    notifyListeners();
    try {
      if (media != null) await media!.setAudio(value);
      audio = value;
    } catch (_) { await stop(failed: true); }
    audioBusy = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> _stopDiscovery() async {
    _searchDeadline?.cancel();
    final broadcast = _broadcast;
    final discovery = _discovery;
    final events = _discoveryEvents;
    _broadcast = null;
    _discovery = null;
    _discoveryEvents = null;
    await events?.cancel();
    if (broadcast != null) { try { await broadcast.stop(); } catch (_) { /* Already stopped. */ } }
    if (discovery != null) { try { await discovery.stop(); } catch (_) { /* Already stopped. */ } }
  }

  Future<void> stop({bool failed = false}) async {
    ++_generation;
    _connectionDeadline?.cancel();
    final session = _session;
    final transport = media;
    _session = null;
    media = null;
    comparison = null;
    approved = false;
    // Stop capture before waiting for network/discovery shutdown.
    try { await transport?.close(); } catch (_) { failed = true; }
    await Future.wait([_stopDiscovery(), if (session != null) session.close()]);
    _update(failed ? CastPhase.failed : CastPhase.ended);
  }

  @override
  void dispose() { _disposed = true; unawaited(stop()); super.dispose(); }
}
