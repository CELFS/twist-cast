import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// Interval statistics, not an end-to-end latency measurement. Only aggregate
// media metrics are logged; SDP, addresses and screen content are excluded.
class CastDiagnostics {
  CastDiagnostics(this._peer);
  final RTCPeerConnection _peer;
  Timer? _timer;
  bool _reading = false;
  bool _closed = false;
  final _samples = CastStatsSamples();

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) => _read());
  }

  Future<void> _read() async {
    if (_closed || _reading) return;
    _reading = true;
    try {
      final reports = await _peer.getStats();
      if (_closed) return;
      for (final metrics in _samples.add(reports)) {
        debugPrint('[TwistCast media] ${jsonEncode(metrics)}');
      }
    } catch (_) {
      // A disconnected peer may stop responding before session disposal.
    } finally {
      _reading = false;
    }
  }

  void dispose() { _closed = true; _timer?.cancel(); }
}

class CastStatsSamples {
  Map<String, Map<dynamic, dynamic>> _previous = {};

  List<Map<String, Object>> add(List<StatsReport> reports) {
    final result = <Map<String, Object>>[];
    final next = <String, Map<dynamic, dynamic>>{};
    for (final report in reports) {
      final values = report.values;
      if (!['inbound-rtp', 'outbound-rtp'].contains(report.type) ||
          (values['kind'] ?? values['mediaType']) != 'video') {
        continue;
      }
      final previous = _previous[report.id];
      next[report.id] = Map.of(values);
      final metrics = <String, Object>{'direction': report.type};
      for (final key in ['framesPerSecond', 'frameWidth', 'frameHeight',
          'qualityLimitationReason', 'encoderImplementation', 'decoderImplementation']) {
        final value = values[key];
        if (value is num || value is String) metrics[key] = value as Object;
      }
      if (previous != null) {
        void average(String output, String total, String count) {
          final nowTotal = values[total], oldTotal = previous[total];
          final nowCount = values[count], oldCount = previous[count];
          if (nowTotal is! num || oldTotal is! num || nowCount is! num || oldCount is! num) return;
          final delta = nowCount - oldCount;
          if (delta > 0 && nowTotal >= oldTotal) {
            metrics[output] = ((nowTotal - oldTotal) * 1000 / delta).round();
          }
        }
        average('encodeMs', 'totalEncodeTime', 'framesEncoded');
        average('sendQueueMs', 'totalPacketSendDelay', 'packetsSent');
        average('decodeMs', 'totalDecodeTime', 'framesDecoded');
        average('jitterBufferMs', 'jitterBufferDelay', 'jitterBufferEmittedCount');
        average('jitterTargetMs', 'jitterBufferTargetDelay', 'jitterBufferEmittedCount');
      }
      final codec = reports.where((item) => item.type == 'codec' && item.id == values['codecId']);
      if (codec.isNotEmpty && codec.first.values['mimeType'] is String) {
        metrics['codec'] = codec.first.values['mimeType'] as String;
      }
      result.add(metrics);
    }
    // Use the selected pair, never log candidate IP addresses or identifiers.
    for (final transport in reports.where((item) => item.type == 'transport')) {
      for (final pair in reports.where((item) => item.type == 'candidate-pair' &&
          item.id == transport.values['selectedCandidatePairId'])) {
        final rtt = pair.values['currentRoundTripTime'];
        if (rtt is num) result.add({'networkRttMs': (rtt * 1000).round()});
      }
    }
    _previous = next;
    return result;
  }
}
