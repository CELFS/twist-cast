import 'dart:convert';
import 'dart:io';

/// QR payloads carry a certificate pin and a short-lived, single-use secret.
class PairingInvitation {
  const PairingInvitation({required this.host, required this.port,
    required this.fingerprint, required this.token, required this.expires});
  final String host;
  final int port;
  final String fingerprint;
  final String token;
  final DateTime expires;

  String encode() => 'twistcast://pair?data=${Uri.encodeComponent(base64Url.encode(utf8.encode(jsonEncode({
    'v': 1, 'host': host, 'port': port, 'pin': fingerprint, 'token': token,
    'expires': expires.millisecondsSinceEpoch,
  }))))}';

  static PairingInvitation parse(String value) {
    if (value.length > 4096) throw const FormatException('Invalid invitation');
    final uri = Uri.parse(value);
    if (uri.scheme != 'twistcast' || uri.host != 'pair') {
      throw const FormatException('Invalid invitation');
    }
    final data = jsonDecode(utf8.decode(base64Url.decode(uri.queryParameters['data']!))) as Map<String, dynamic>;
    final result = PairingInvitation(host: data['host'] as String,
      port: data['port'] as int, fingerprint: data['pin'] as String,
      token: data['token'] as String,
      expires: DateTime.fromMillisecondsSinceEpoch(data['expires'] as int));
    if (data['v'] != 1 || !isLanAddress(result.host) || result.port < 1 ||
        result.port > 65535 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(result.fingerprint) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(result.token) ||
        !result.expires.isAfter(DateTime.now())) {
      throw const FormatException('Invalid invitation');
    }
    return result;
  }

  static bool isLanAddress(String value) {
    final address = InternetAddress.tryParse(value);
    if (address == null || address.isLoopback || address.isMulticast) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 || (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254);
    }
    return (bytes[0] & 0xfe) == 0xfc || (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }
}
