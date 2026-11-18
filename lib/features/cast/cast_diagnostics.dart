import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'diagnostic_log.dart';

// Interval statistics, not an end-to-end latency measurement. Only aggregate
// media metrics are logged; SDP, addresses and screen content are excluded.
class CastDiagnostics {
  CastDiagnostics(this._peer, this.log, {this.renderSnapshot});
  final Future<Map<String, num>> Function()? renderSnapshot;
  final DiagnosticLog log;
  final _clock = Stopwatch()..start();
  int? _lastSample;
  final RTCPeerConnection _peer;
  Timer? _timer;
  bool _reading = false;
  bool _closed = false;
  final _samples = CastStatsSamples();

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  Future<void> _read() async {
    if (_closed || _reading) return;
    _reading = true;
    try {
      final reports = await _peer.getStats();
      if (_closed) return;
      final now = _clock.elapsedMilliseconds;
      final interval = _lastSample == null ? null : now - _lastSample!;
      _lastSample = now;
      log.add({'sampleMs': now, 'metrics': _samples.add(reports, intervalMs: interval)});
      if (renderSnapshot != null) {
        try {
          final snapshot = await renderSnapshot!();
          if (!_closed && snapshot.isNotEmpty) log.add({'nativeMediaCounters': snapshot});
        } catch (_) { if (!_closed) log.event('native-stats-unavailable'); }
      }
    } catch (_) {
      // A disconnected peer may stop responding before session disposal.
      if (!_closed) log.event('stats-unavailable');
    } finally {
      _reading = false;
    }
  }

  void dispose() { _closed = true; _timer?.cancel(); }
}

class CastStatsSamples {
  Map<String, Map<dynamic, dynamic>> _previous = {};

  List<Map<String, Object>> add(List<StatsReport> reports, {int? intervalMs}) {
    final result = <Map<String, Object>>[];
    final next = <String, Map<dynamic, dynamic>>{};
    for (final report in reports) {
      final values = report.values;
      if (!['inbound-rtp', 'outbound-rtp'].contains(report.type) ||
          !['video', 'audio'].contains(values['kind'] ?? values['mediaType'])) {
        continue;
      }
      final previous = _previous[report.id];
      next[report.id] = Map.of(values);
      final metrics = <String, Object>{'direction': report.type, 'kind': values['kind'] ?? values['mediaType']};
      for (final key in ['framesPerSecond', 'frameWidth', 'frameHeight',
          'qualityLimitationReason', 'encoderImplementation', 'decoderImplementation',
          'targetBitrate', 'jitter', 'audioLevel']) {
        final value = values[key];
        if (value is num || value is String) metrics[key] = value as Object;
      }
      if (previous != null) {
        for (final key in ['bytesSent', 'bytesReceived', 'packetsSent', 'packetsReceived',
            'packetsLost', 'framesEncoded', 'framesDecoded', 'framesDropped',
            'keyFramesEncoded', 'keyFramesDecoded', 'nackCount', 'pliCount', 'firCount',
            'freezeCount', 'concealedSamples', 'insertedSamplesForDeceleration',
            'removedSamplesForAcceleration']) {
          final current = values[key], old = previous[key];
          if (current is num && old is num && current >= old) {
            metrics['${key}Delta'] = current - old;
            if ((key == 'bytesSent' || key == 'bytesReceived') && intervalMs != null && intervalMs > 0) {
              metrics['${key}Kbps'] = (current - old) * 8 / intervalMs;
            }
          }
        }
        if (intervalMs != null && intervalMs > 0) metrics['intervalMs'] = intervalMs;
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
        average('jitterMinimumMs', 'jitterBufferMinimumDelay', 'jitterBufferEmittedCount');
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
        final network = <String, Object>{};
        if (rtt is num) network['networkRttMs'] = (rtt * 1000).round();
        for (final key in ['availableOutgoingBitrate', 'availableIncomingBitrate']) {
          if (pair.values[key] is num) network[key] = pair.values[key] as num;
        }
        if (network.isNotEmpty) result.add(network);
      }
    }
    _previous = next;
    return result;
  }
}
