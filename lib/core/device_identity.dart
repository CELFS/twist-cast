import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart' hide Signature;
import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'recent_device.dart';

/// Device secrets stay in the operating system's secure storage.
class DeviceIdentity {
  DeviceIdentity._(this.keyPair, this.certificate, this.privateKey);

  static final _storage = Platform.isMacOS
      ? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false))
      : const FlutterSecureStorage();
  final SimpleKeyPair keyPair;
  final String certificate;
  final String privateKey;

  static Future<DeviceIdentity> load() async {
    final stored = await _storage.read(key: 'identity.v1');
    if (stored != null) {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      return DeviceIdentity._(
        await Ed25519().newKeyPairFromSeed(base64Decode(data['seed'] as String)),
        data['certificate'] as String,
        data['privateKey'] as String,
      );
    }
    final pair = await Ed25519().newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    final tls = await Isolate.run(() {
      final keys = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final private = keys.privateKey as RSAPrivateKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'TwistCast'}, private, keys.publicKey as RSAPublicKey,
      );
      return (
        X509Utils.generateSelfSignedCertificate(private, csr, 3650),
        CryptoUtils.encodeRSAPrivateKeyToPem(private),
      );
    });
    await _storage.write(key: 'identity.v1', value: jsonEncode({
      'seed': base64Encode(seed),
      'certificate': tls.$1,
      'privateKey': tls.$2,
    }));
    return DeviceIdentity._(pair, tls.$1, tls.$2);
  }

  String get fingerprint => digest(base64Decode(certificate.split('-----')[2].replaceAll(RegExp(r'\s'), '')));
  Future<String> get publicKey async =>
      base64Encode((await keyPair.extractPublicKey()).bytes);

  static RecentDeviceStore recentStore() => RecentDeviceStore(_storage);

  Future<RecentDevice> localProfile() async {
    final seed = await keyPair.extractPrivateKeyBytes();
    final key = hashing.Hmac(hashing.sha256, seed).convert(utf8.encode('twistcast.recent-key.v1'));
    final id = await publicKey;
    var host = '';
    try {
      host = RecentDevice.cleanName(Platform.localHostname);
    } on OSError { /* Use the device label below. */ }
    final fallback = '${Platform.operatingSystem} · ${digest(utf8.encode(id)).substring(0, 6)}';
    return RecentDevice(id: id, discoveryKey: base64.encode(key.bytes),
      name: host.isEmpty || host.toLowerCase().startsWith('localhost') ? fallback : host);
  }

  SecurityContext serverContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificate))
    ..usePrivateKeyBytes(utf8.encode(privateKey));

  Future<String> sign(String message) async => base64Encode(
    (await Ed25519().sign(utf8.encode(message), keyPair: keyPair)).bytes,
  );

  static Future<bool> verify(String key, String message, String signature) {
    return Ed25519().verify(utf8.encode(message), signature: Signature(
      base64Decode(signature),
      publicKey: SimplePublicKey(base64Decode(key), type: KeyPairType.ed25519),
    ));
  }

  static String digest(List<int> bytes) => hashing.sha256.convert(bytes).toString();

  Future<void> remember(String peerKey) =>
      _storage.write(key: 'peer.${digest(utf8.encode(peerKey))}', value: peerKey);

  Future<bool> knows(String peerKey) async =>
      await _storage.read(key: 'peer.${digest(utf8.encode(peerKey))}') == peerKey;
}
