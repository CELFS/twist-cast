import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'device_identity.dart';
import 'pairing_invitation.dart';

/// TLS protects signaling. Explicit comparison authenticates discovery pairing;
/// QR pairing additionally pins the receiver's TLS certificate out of band.
class SecureSession {
  SecureSession({required this.identity, required this.onPairing,
    required this.onAuthorized, required this.onMessage, required this.onClosed});
  final DeviceIdentity identity;
  final void Function(String code, bool known) onPairing;
  final Future<void> Function() onAuthorized;
  final Future<void> Function(Map<String, dynamic>) onMessage;
  final void Function() onClosed;
  HttpServer? _server;
  HttpClient? _client;
  WebSocket? _socket;
  Timer? _deadline;
  StreamSubscription<dynamic>? _subscription;
  bool _receiver = false;
  bool _localApproved = false;
  bool _remoteApproved = false;
  bool _authorized = false;
  bool _authorizing = false;
  int _queued = 0;
  bool _closed = false;
  bool _reserved = false;
  String? _transcript;
  String? _peer;
  String? _challenge;
  String? _serverPin;
  String? _token;
  DateTime? _expires;
  Future<void> _queue = Future.value();

  static String _secret() => base64Url.encode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  Future<int> listen() async {
    _receiver = true;
    _token = _secret();
    _expires = DateTime.now().add(const Duration(minutes: 2));
    _server = await HttpServer.bindSecure(InternetAddress.anyIPv4, 0, identity.serverContext());
    _server!.idleTimeout = const Duration(seconds: 10);
    _server!.listen(_accept, onError: (_) => close());
    _deadline = Timer(const Duration(minutes: 2), close);
    return _server!.port;
  }

  PairingInvitation invitation(String host) => PairingInvitation(
    host: host, port: _server!.port, fingerprint: identity.fingerprint,
    token: _token!, expires: _expires!,
  );

  Future<void> _accept(HttpRequest request) async {
    if (_closed || _reserved || request.uri.path != '/pair' ||
        !WebSocketTransformer.isUpgradeRequest(request) ||
        !PairingInvitation.isLanAddress(request.connectionInfo?.remoteAddress.address ?? '')) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    _reserved = true;
    try {
      _socket = await WebSocketTransformer.upgrade(request);
      _challenge = _secret();
      _serverPin = identity.fingerprint;
      _attach();
      _send({'type': 'challenge', 'v': 1, 'nonce': _challenge});
    } catch (_) {
      await close();
    }
  }

  Future<void> connect(String host, int port, {PairingInvitation? invitation}) async {
    if (!PairingInvitation.isLanAddress(host) || port < 1 || port > 65535) {
      throw const FormatException('Invalid LAN endpoint');
    }
    _token = invitation?.token;
    _client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (certificate, _, _) {
        final pin = DeviceIdentity.digest(certificate.der);
        if (invitation != null && pin != invitation.fingerprint) return false;
        if (_serverPin != null && _serverPin != pin) return false;
        // Discovery remains untrusted until BOTH users compare the transcript.
        _serverPin = pin;
        return true;
      };
    _socket = await WebSocket.connect(
      Uri(scheme: 'wss', host: host, port: port, path: '/pair').toString(),
      customClient: _client,
    ).timeout(const Duration(seconds: 15));
    if (_serverPin == null || _closed) {
      await close();
      throw const FormatException('Missing certificate pin');
    }
    _deadline = Timer(const Duration(minutes: 2), close);
    _attach();
  }

  void _attach() {
    _socket!.pingInterval = const Duration(seconds: 10);
    _subscription = _socket!.listen((dynamic frame) {
      if (frame is! String || frame.length > 131072 || ++_queued > 32) {
        unawaited(close());
        return;
      }
      _queue = _queue.then((_) async {
        --_queued;
        if (_closed) return;
        final message = jsonDecode(frame) as Map<String, dynamic>;
        await _handle(message);
      }).catchError((Object _) async { await close(); });
    }, onDone: close, onError: (_) => close());
  }

  static String _field(Map<String, dynamic> data, String key, int max) {
    final value = data[key];
    if (value is! String || value.isEmpty || value.length > max) {
      throw const FormatException('Invalid handshake');
    }
    return value;
  }

  Future<void> _handle(Map<String, dynamic> data) async {
    final type = data['type'];
    if (type == 'challenge' && !_receiver && _transcript == null) {
      if (data['v'] != 1) throw const FormatException('Version mismatch');
      final challenge = _field(data, 'nonce', 64);
      final nonce = _secret();
      final key = await identity.publicKey;
      _transcript = jsonEncode(['twistcast.v1', _serverPin, challenge, nonce, key]);
      _peer = _serverPin;
      _send({'type': 'hello', 'nonce': nonce, 'key': key,
        'signature': await identity.sign(_transcript!), 'token': _token});
    } else if (type == 'hello' && _receiver && _transcript == null) {
      final nonce = _field(data, 'nonce', 64);
      final key = _field(data, 'key', 64);
      if (base64Decode(key).length != 32) throw const FormatException('Invalid key');
      _transcript = jsonEncode(['twistcast.v1', _serverPin, _challenge, nonce, key]);
      if (!await DeviceIdentity.verify(key, _transcript!, _field(data, 'signature', 128))) {
        throw const FormatException('Invalid signature');
      }
      if (data['token'] != null && data['token'] != _token) {
        throw const FormatException('Invalid invitation secret');
      }
      _peer = key;
      _send({'type': 'compare'});
      await _showComparison();
    } else if (type == 'compare' && !_receiver && _transcript != null && !_localApproved) {
      await _showComparison();
    } else if (type == 'approve' && _transcript != null && !_remoteApproved) {
      _remoteApproved = true;
      await _authorize();
    } else if (_authorized && (type == 'offer' || type == 'answer' || type == 'ice' || type == 'playing' ||
        type == 'touch-state' || type == 'pointer' || type == 'stop')) {
      if (type == 'stop') { await close(); } else { await onMessage(data); }
    } else {
      throw const FormatException('Unexpected message');
    }
  }

  Future<void> _showComparison() async {
    final hash = DeviceIdentity.digest(utf8.encode(_transcript!)).substring(0, 16).toUpperCase();
    // 64-bit comparison resists adaptive guessing against discovery handshakes.
    final code = List.generate(4, (i) => hash.substring(i * 4, i * 4 + 4)).join(' ');
    onPairing(code, await identity.knows(_peer!));
  }

  Future<void> approve() async {
    if (_transcript == null || _localApproved || _closed) return;
    _localApproved = true;
    _send({'type': 'approve'});
    await _authorize();
  }

  Future<void> _authorize() async {
    if (!_localApproved || !_remoteApproved || _authorized || _authorizing || _closed) return;
    _authorizing = true;
    await identity.remember(_peer!);
    if (_closed) return;
    _authorized = true;
    _deadline?.cancel();
    await onAuthorized();
  }

  void send(Map<String, dynamic> message) {
    if (!_authorized || _closed) throw StateError('Session is not authorized');
    _send(message);
  }

  void _send(Map<String, dynamic> message) => _socket?.add(jsonEncode(message));

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _authorized = false;
    _deadline?.cancel();
    await _subscription?.cancel();
    final socket = _socket;
    if (socket != null) {
      await socket.close().timeout(const Duration(seconds: 2), onTimeout: () => null);
    }
    await _server?.close(force: true);
    _client?.close(force: true);
    onClosed();
  }
}
