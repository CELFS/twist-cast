import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

// Local monotonic time measures intervals only; clocks on separate devices are
// not synchronized. No media, peer addresses, SDP or credentials are collected.
class DiagnosticLog {
  static const capacity = 1800;
  final _records = Queue<Map<String, Object>>();
  final _clock = Stopwatch()..start();
  final started = DateTime.now().toUtc();
  final String role;
  int discarded = 0;
  DiagnosticLog(this.role) { event('session-start'); }

  void event(String name) => add({'event': name});
  void add(Map<String, Object> metrics) {
    if (_records.length == capacity) { _records.removeFirst(); discarded++; }
    _records.add({'elapsedMs': _clock.elapsedMilliseconds, ...metrics});
  }

  String encode() => jsonEncode({
    'schema': 1, 'version': '0.1.10',
    'commit': const String.fromEnvironment('TWISTCAST_COMMIT'),
    'role': role, 'platform': Platform.operatingSystem,
    'startedUtc': started.toIso8601String(), 'discardedRecords': discarded,
    'clock': 'local monotonic milliseconds; not synchronized between devices',
    'records': _records.toList(),
  });

  Future<bool> export() async {
    try {
      final status = await const MethodChannel('app.twist.cast/updates')
          .invokeMapMethod<String, dynamic>('status').timeout(const Duration(seconds: 3));
      add({'event': 'build-identity',
        if (status?['version'] is String) 'installedVersion': status!['version'] as String,
        if (status?['buildNumber'] is num) 'installedBuild': status!['buildNumber'] as num});
    } catch (_) { event('build-identity-unavailable'); }
    return await const MethodChannel('app.twist.cast/diagnostics')
        .invokeMethod<bool>('export', {'json': encode()}) ?? false;
  }
}
