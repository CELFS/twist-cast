import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppRelease {
  const AppRelease(this.version, this.url, this.sha256);
  final String version;
  final String url;
  final String sha256;
}

class UpdateController extends ChangeNotifier {
  static const _channel = MethodChannel('app.twist.cast/updates');
  static const _repository = 'CELFS/twist-cast';
  static bool get supported => Platform.isAndroid || Platform.isMacOS;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  Timer? _timer;
  bool _disposed = false;
  bool checking = false;
  bool working = false;
  String? error;
  Map<String, dynamic> state = {};
  AppRelease? release;

  String get installed => state['version'] as String? ?? '';
  String get phase => state['phase'] as String? ?? 'idle';
  bool get busy => working || phase == 'downloading' || phase == 'updating';
  bool get available => release != null && installed.isNotEmpty && compareVersions(release!.version, installed) > 0;
  double? get progress {
    final total = (state['total'] as num?)?.toDouble() ?? 0;
    return total > 0 ? (((state['received'] as num?)?.toDouble() ?? 0) / total).clamp(0, 1) : null;
  }

  static int compareVersions(String left, String right) {
    final a = left.split('.').map(int.parse).toList();
    final b = right.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final result = a[i].compareTo(b[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  void _changed() { if (!_disposed) notifyListeners(); }

  Future<String> _get(Uri uri) async {
    final request = await _http.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.userAgentHeader, 'TwistCast');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw HttpException('Update HTTP ${response.statusCode}');
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) throw const FormatException('Update metadata too large');
    }
    return utf8.decode(bytes);
  }

  String _assetUrl(Map<String, dynamic> asset, String tag, String filename) {
    final expected = 'https://github.com/$_repository/releases/download/$tag/$filename';
    if (asset['browser_download_url'] != expected) throw const FormatException('Unexpected update source');
    return expected;
  }

  Future<void> check() async {
    if (checking || busy || _disposed) return;
    checking = true;
    error = null;
    _changed();
    try {
      await _status();
      final data = jsonDecode(await _get(Uri.https('api.github.com', '/repos/$_repository/releases/latest'))) as Map<String, dynamic>;
      final tag = data['tag_name'] as String;
      if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag) || data['draft'] != false || data['prerelease'] != false) {
        throw const FormatException('Not a stable release');
      }
      final version = tag.substring(1);
      final platform = state['platform'] as String;
      final extension = Platform.isAndroid ? 'apk' : 'dmg';
      final filename = 'twist-cast-$version-$platform.$extension';
      final assets = (data['assets'] as List).cast<Map<String, dynamic>>();
      final asset = assets.singleWhere((entry) => entry['name'] == filename);
      final url = _assetUrl(asset, tag, filename);
      final checksums = assets.singleWhere((entry) => entry['name'] == 'SHA256SUMS.txt');
      final sums = await _get(Uri.parse(_assetUrl(checksums, tag, 'SHA256SUMS.txt')));
      final lines = sums.split('\n').map((line) => RegExp(r'^([a-f0-9]{64})  (.+)$').firstMatch(line)).whereType<RegExpMatch>();
      final hash = lines.singleWhere((entry) => entry.group(2) == filename).group(1)!;
      if (!_disposed) release = AppRelease(version, url, hash);
    } catch (_) {
      if (!_disposed) { error = 'check'; release = null; }
    } finally {
      checking = false;
      _changed();
    }
  }

  Future<void> _status() async {
    final next = await _channel.invokeMapMethod<String, dynamic>('status').timeout(const Duration(seconds: 15));
    if (_disposed) return;
    state = next ?? {};
    _timer?.cancel();
    if (phase == 'downloading' || phase == 'updating') {
      _timer = Timer(const Duration(seconds: 1), _poll);
    }
  }

  Future<void> _poll() async {
    try {
      await _status();
      if (error == 'download') error = null;
    }
    catch (_) {
      if (!_disposed) {
        error = 'download';
        _timer = Timer(const Duration(seconds: 3), _poll);
      }
    }
    _changed();
  }

  Future<void> download() async {
    if (!available || busy || checking) return;
    await _operate('download', {
      'version': release!.version, 'url': release!.url, 'sha256': release!.sha256,
    });
  }

  Future<void> install(String failureMessage) async {
    if (busy || phase != 'ready') return;
    await _operate('install', {'failureMessage': failureMessage});
  }

  Future<void> _operate(String method, Map<String, dynamic> arguments) async {
    working = true;
    error = null;
    _changed();
    try {
      await _channel.invokeMethod<void>(method, arguments).timeout(const Duration(seconds: 15));
      await _status();
    } catch (_) { error = method; }
    finally { working = false; _changed(); }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _http.close(force: true);
    super.dispose();
  }
}
