import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppRelease {
  const AppRelease(this.version, this.url, this.sha256, {this.build = 0, this.commit = ''});
  final String version;
  final String url;
  final String sha256;
  final int build;
  final String commit;
  String get numberLabel => UpdateController.versionLabel(version, build);
  String get label => '$numberLabel${commit.length >= 7 ? " (${commit.substring(0, 7)})" : ""}';
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
  int get installedBuild => (state['buildNumber'] as num?)?.toInt() ?? 0;
  String get installedNumberLabel => versionLabel(installed, installedBuild);
  String get _targetVersion => state['targetVersion'] as String? ?? '';
  int get _targetBuild => (state['targetBuild'] as num?)?.toInt() ?? 0;
  String get downloadedNumberLabel => versionLabel(_targetVersion, _targetBuild);

  static String versionLabel(String version, int build) => 'v$version${build > 0 ? "+$build" : ""}';
  static const _compiledCommit = String.fromEnvironment('TWISTCAST_COMMIT');
  String get installedCommit {
    final commit = state['commit'];
    return commit is String && commit.length >= 7 ? commit : _compiledCommit;
  }
  bool get available => release != null && installed.isNotEmpty &&
    isNewerBuild(release!.version, release!.build, installed, installedBuild);

  bool get canInstallDownloaded => phase == 'ready' && !hasNewerDownload;
  bool get hasNewerDownload {
    final latest = release;
    return phase == 'ready' && _targetVersion.isNotEmpty && latest != null && available &&
      isNewerBuild(latest.version, latest.build, _targetVersion, _targetBuild);
  }

  static bool isNewerBuild(String version, int build, String installed, int installedBuild) {
    final comparison = compareVersions(version, installed);
    // A hash identifies source content; monotonic build numbers determine update order.
    return comparison >= 0 && (build > 0 ? build > installedBuild : comparison > 0);
  }
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
    HttpClientRequest? request;
    Future<String> read() async {
      request = await _http.getUrl(uri);
      request!.headers.set(HttpHeaders.userAgentHeader, 'TwistCast');
      final response = await request!.close();
      if (response.statusCode != 200) {
        final rateLimited = response.statusCode == 429 ||
          (response.statusCode == 403 && response.headers.value('x-ratelimit-remaining') == '0');
        throw UpdateHttpException(response.statusCode, rateLimited);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) throw const FormatException('Update metadata too large');
      }
      return utf8.decode(bytes);
    }
    try {
      return await read().timeout(const Duration(seconds: 20));
    } catch (_) {
      request?.abort();
      rethrow;
    }
  }

  static String checkError(Object error) {
    if (error is SocketException || error is TimeoutException || error is HandshakeException) return 'checkNetwork';
    if (error is UpdateHttpException) return error.rateLimited ? 'checkRateLimit' : 'checkService';
    if (error is FormatException || error is StateError || error is TypeError) return 'checkMetadata';
    return 'check';
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
      final match = RegExp(r'^v(\d+\.\d+\.\d+)(?:-build\.([1-9]\d*))?$').firstMatch(tag);
      if (match == null || data['draft'] != false || data['prerelease'] != false) {
        throw const FormatException('Not a stable release');
      }
      final version = match.group(1)!;
      final build = int.tryParse(match.group(2) ?? '') ?? 0;
      final platform = state['platform'] as String;
      final extension = Platform.isAndroid ? 'apk' : 'dmg';
      final filename = 'twist-cast-$version-$platform.$extension';
      final assets = (data['assets'] as List).cast<Map<String, dynamic>>();
      var commit = '';
      if (build > 0) {
        final manifest = assets.singleWhere((entry) => entry['name'] == 'update.json');
        final identity = jsonDecode(await _get(Uri.parse(_assetUrl(manifest, tag, 'update.json')))) as Map<String, dynamic>;
        if (identity['schema'] != 1 || identity['version'] != version || identity['build'] != build ||
            identity['tag'] != tag || identity['commit'] is! String ||
            !RegExp(r'^[a-f0-9]{40}$').hasMatch(identity['commit'] as String)) {
          throw const FormatException('Invalid build identity');
        }
        commit = identity['commit'] as String;
      }
      final asset = assets.singleWhere((entry) => entry['name'] == filename);
      final url = _assetUrl(asset, tag, filename);
      final checksums = assets.singleWhere((entry) => entry['name'] == 'SHA256SUMS.txt');
      final sums = await _get(Uri.parse(_assetUrl(checksums, tag, 'SHA256SUMS.txt')));
      final lines = sums.split('\n').map((line) => RegExp(r'^([a-f0-9]{64})  (.+)$').firstMatch(line)).whereType<RegExpMatch>();
      final hash = lines.singleWhere((entry) => entry.group(2) == filename).group(1)!;
      if (!_disposed) release = AppRelease(version, url, hash, build: build, commit: commit);
    } catch (failure) {
      if (!_disposed) { error = checkError(failure); release = null; }
      debugPrint('[TwistCast update] ${checkError(failure)} (${failure.runtimeType})');
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
      'version': release!.version, 'buildNumber': release!.build,
      'url': release!.url, 'sha256': release!.sha256,
    });
  }

  Future<void> install(String failureMessage) async {
    if (busy || checking || !canInstallDownloaded) return;
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

class UpdateHttpException implements Exception {
  const UpdateHttpException(this.statusCode, this.rateLimited);
  final int statusCode;
  final bool rateLimited;
}
