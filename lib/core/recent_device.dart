import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Only approved peers get this discovery key. Every advertisement uses a
/// fresh nonce, and its tag is only a routing hint for the signed handshake.
class RecentDevice {
  const RecentDevice({
    required this.id,
    required this.name,
    required this.discoveryKey,
  });
  final String id;
  final String name;
  final String discoveryKey;

  static String cleanName(String value) => String.fromCharCodes(
    value.runes
        .where(
          (c) =>
              c >= 32 &&
              (c < 127 || c > 159) &&
              !(c >= 0x202a && c <= 0x202e) &&
              !(c >= 0x2066 && c <= 0x2069),
        )
        .take(64),
  ).trim();

  static RecentDevice? parse(String id, Map<dynamic, dynamic> profile) {
    final key = profile['lookup'], label = profile['name'];
    if (label is! String ||
        key is! String ||
        !_keyFormat.hasMatch(id) ||
        !_keyFormat.hasMatch(key)) {
      return null;
    }
    final name = cleanName(label);
    return name.isEmpty
        ? null
        : RecentDevice(id: id, name: name, discoveryKey: key);
  }

  static final _keyFormat = RegExp(r'^[A-Za-z0-9+/]{43}=$');
  static final _tagFormat = RegExp(r'^([a-f0-9]{24})\.([a-f0-9]{32})$');
  Map<String, String> get profile => {'name': name, 'lookup': discoveryKey};

  String _tag(String nonce) => Hmac(sha256, base64.decode(discoveryKey))
      .convert(utf8.encode('twistcast.discovery.v1/$nonce'))
      .toString()
      .substring(0, 32);

  String advertisement() {
    final random = Random.secure();
    final nonce = List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$nonce.${_tag(nonce)}';
  }

  bool matches(String? advertisement) {
    if (advertisement == null || advertisement.length != 57) return false;
    final match = _tagFormat.firstMatch(advertisement);
    return match != null && _tag(match[1]!) == match[2];
  }
}

class RecentDeviceStore {
  RecentDeviceStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'recent.devices.v1';
  List<RecentDevice> devices = const [];
  bool _loaded = false;
  Future<void> _queue = Future.value();

  Future<void> _run([List<RecentDevice> Function(List<RecentDevice>)? change]) {
    final operation = _queue.then((_) async {
      if (!_loaded) {
        final raw = await _storage.read(key: _key);
        if (raw != null) {
          try {
            final rows = jsonDecode(raw);
            if (rows is List) {
              devices = [
                for (final row in rows.whereType<Map>())
                  if (row['id'] is String)
                    ?RecentDevice.parse(row['id'] as String, row),
              ].take(10).toList();
            }
          } on FormatException {
            /* An unreadable history is replaced on the next pairing. */
          }
        }
        _loaded = true;
      }
      if (change == null) return;
      final next = change(devices);
      await _storage.write(
        key: _key,
        value: jsonEncode([
          for (final device in next) {'id': device.id, ...device.profile},
        ]),
      );
      devices = next;
    });
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> load() => _run();
  Future<void> remember(RecentDevice device) => _run(
    (list) => [device, ...list.where((item) => item.id != device.id).take(9)],
  );
  Future<void> remove(String id) =>
      _run((list) => list.where((item) => item.id != id).toList());
}
