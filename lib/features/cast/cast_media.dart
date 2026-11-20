import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'cast_diagnostics.dart';
import 'diagnostic_log.dart';

class CastMedia {
  CastMedia({required this.send, required this.onStopped, required this.onConnected, required this.log});
  final DiagnosticLog log;
  final void Function(Map<String, dynamic>) send;
  final void Function() onStopped;
  final void Function() onConnected;
  final renderer = RTCVideoRenderer();
  static const _native = MethodChannel('app.twist.cast/capture');
  RTCPeerConnection? _peer;
  CastDiagnostics? _diagnostics;
  MediaStream? _stream;
  RTCRtpSender? _androidAudioSender;
  StreamSubscription<dynamic>? _events;
  final _pendingIce = <RTCIceCandidate>[];
  bool _remoteDescription = false;
  bool _closed = false;
  bool _initialized = false;
  bool _sending = false;
  bool _reportedPlaying = false;
  bool _peerSupportsTouch = false;
  bool remoteTouchEnabled = false;
  bool get canSendPointer => !_closed && !_sending && _reportedPlaying && remoteTouchEnabled;
  bool get canEnableRemoteTouch => Platform.isAndroid && _sending && _peerSupportsTouch && _reportedPlaying && !_closed;

  Future<bool> setRemoteTouch(bool enabled) async {
    if (!canEnableRemoteTouch) return false;
    if (enabled && await _native.invokeMethod<bool>('remoteTouchAvailable') != true) {
      if (!_closed) await _native.invokeMethod<void>('remoteTouchSettings');
      return false;
    }
    if (_closed) return false;
    remoteTouchEnabled = enabled;
    if (!enabled) await _native.invokeMethod<void>('remoteTouchCancel');
    if (!_closed) send({'type': 'touch-state', 'enabled': enabled});
    return enabled;
  }

  void sendPointer(String action, Offset point, Offset scroll, bool landscape) {
    if (!canSendPointer) return;
    send({'type': 'pointer', 'action': action, 'x': point.dx, 'y': point.dy,
      'dx': scroll.dx.clamp(-0.35, 0.35), 'dy': scroll.dy.clamp(-0.35, 0.35),
      'landscape': landscape});
  }

  Future<void> _receivePointer(Map<String, dynamic> message) async {
    if (!canEnableRemoteTouch || !remoteTouchEnabled) return;
    final action = message['action'];
    if (!const {'down', 'move', 'up', 'cancel', 'scroll'}.contains(action)) return;
    final args = <String, dynamic>{'action': action, 'landscape': message['landscape'] == true};
    for (final field in ['x', 'y', 'dx', 'dy']) {
      final value = message[field];
      if (value is! num || !value.isFinite) return;
      final axis = field == 'x' || field == 'y';
      if (value < (axis ? 0 : -0.35) || value > (axis ? 1 : 0.35)) return;
      args[field] = value.toDouble();
    }
    await _native.invokeMethod<void>('remotePointer', args);
  }

  Future<void> prepare() async {
    await WebRTC.initialize(options: {
      'bypassVoiceProcessing': true,
      // LAN screen interaction prioritizes freshness over playout smoothing.
      'zeroPlayoutDelay': Platform.isMacOS,
    });
    await renderer.initialize();
    _initialized = true;
    if (_closed) { await renderer.dispose(); return; }
    _peer = await createPeerConnection({'iceServers': <dynamic>[], 'sdpSemantics': 'unified-plan'});
    if (_closed) { await _peer?.dispose(); return; }
    _diagnostics = CastDiagnostics(_peer!, log, renderSnapshot: Platform.isMacOS ? () async {
      final raw = await const MethodChannel('FlutterWebRTC.Method')
          .invokeMapMethod<String, dynamic>('videoRendererDiagnostics', {'textureId': renderer.textureId});
      return {for (final entry in (raw ?? <String, dynamic>{}).entries)
        if (entry.value is num) entry.key: entry.value as num};
    } : Platform.isAndroid ? () async {
      final tracks = _stream?.getVideoTracks();
      if (tracks == null || tracks.isEmpty) return <String, num>{};
      final raw = await const MethodChannel('FlutterWebRTC.Method')
          .invokeMapMethod<String, dynamic>('screenCaptureDiagnostics', {'trackId': tracks.first.id});
      return {for (final entry in (raw ?? <String, dynamic>{}).entries)
        if (entry.value is num) entry.key: entry.value as num};
    } : null);
    _peer!.onIceCandidate = (candidate) {
      if (!_closed && candidate.candidate != null) {
        send({'type': 'ice', 'candidate': candidate.candidate,
          'mid': candidate.sdpMid, 'line': candidate.sdpMLineIndex});
      }
    };
    renderer.onFirstFrameRendered = () {
      if (_closed || _sending || _reportedPlaying) return;
      _reportedPlaying = true;
      log.event('first-frame');
      send({'type': 'playing'});
      onConnected();
    };
    _peer!.onTrack = (event) {
      if (!_closed && event.streams.isNotEmpty) renderer.srcObject = event.streams.first;
    };
    _peer!.onConnectionState = (state) {
      if (_closed) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        log.event('transport-connected');
        _diagnostics?.start();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) { onStopped(); }
    };
  }

  Future<void> share({required bool audio, required String title, required String body}) async {
    _sending = true;
    if (Platform.isAndroid || Platform.isIOS) {
      _events = const EventChannel('app.twist.cast/capture-events')
          .receiveBroadcastStream().listen((_) => onStopped(), onError: (_) => onStopped());
    }
    if (Platform.isAndroid) {
      if (audio && !await _audioPermission()) throw StateError('Audio permission denied');
      if (_closed) return;
      if (!await Helper.requestCapturePermission(fullScreenOnly: true)) {
        throw StateError('Screen permission denied');
      }
      if (_closed) return;
      await _native.invokeMethod<void>('start', {'title': title, 'body': body});
      if (_closed) { await _native.invokeMethod<void>('stop'); return; }
    }
    if (_closed) return;
    final stream = await navigator.mediaDevices.getDisplayMedia({
      'video': Platform.isIOS ? {'deviceId': 'broadcast'} : true,
      'audio': true,
    });
    if (_closed) {
      for (final track in stream.getTracks()) { await track.stop(); }
      await stream.dispose();
      if (Platform.isAndroid) await _native.invokeMethod<void>('stop');
      return;
    }
    _stream = stream;
    for (final track in stream.getVideoTracks()) { track.onEnded = onStopped; }
    await setAudio(audio);
    for (final track in stream.getTracks()) {
      final sender = await _peer!.addTrack(track, stream);
      if (Platform.isAndroid && track.kind == 'audio') {
        _androidAudioSender = sender;
        await _setAndroidAudioTransmission(audio);
      }
      if (Platform.isAndroid && track.kind == 'video') {
        // Adapt resolution under encoder pressure instead of sacrificing motion.
        final parameters = sender.parameters;
        parameters.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
        if (!await sender.setParameters(parameters)) {
          throw StateError('Could not configure screen video adaptation');
        }
      }
    }
    final offer = await _peer!.createOffer();
    await _peer!.setLocalDescription(offer);
    if (!_closed) send({'type': 'offer', 'sdp': offer.sdp, if (Platform.isAndroid) 'touch': true});
  }

  bool get canSetDisplayPower => !_closed && !_sending && _reportedPlaying && _peerSupportsTouch;

  Future<bool> _audioPermission() async =>
      await _native.invokeMethod<bool>('audioPermission') == true;

  Future<void> _setAndroidAudioTransmission(bool enabled) async {
    final sender = _androidAudioSender;
    if (sender == null) return;
    final parameters = sender.parameters;
    final encodings = parameters.encodings;
    if (encodings == null || encodings.isEmpty) {
      throw StateError('Audio sender has no RTP encoding');
    }
    if (encodings.every((encoding) => encoding.active == enabled)) return;
    // A disabled track still sends silence. Pause its RTP encoding while keeping
    // the audio sender negotiated so the user can enable audio mid-session.
    for (final encoding in encodings) {
      encoding.active = enabled;
    }
    if (!await sender.setParameters(parameters)) {
      throw StateError('Could not configure audio transmission');
    }
  }

  Future<void> setAudio(bool enabled) async {
    if (!_sending || _closed) return;
    if (enabled && _stream?.getAudioTracks().isEmpty == true) {
      throw StateError('Internal audio unavailable');
    }
    if (Platform.isAndroid) {
      if (enabled && !await _audioPermission()) throw StateError('Audio permission denied');
      await _native.invokeMethod<void>('audio', {'enabled': enabled});
      await _setAndroidAudioTransmission(enabled);
    }
    for (final track in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> handle(Map<String, dynamic> message) async {
    if (_closed || _peer == null) return;
    switch (message['type']) {
      case 'touch-state':
        if (_sending || !_peerSupportsTouch || !_reportedPlaying) return;
        remoteTouchEnabled = message['enabled'] == true;
        onConnected();
      case 'pointer':
        await _receivePointer(message);
      case 'playing':
        if (!_sending || _reportedPlaying) throw const FormatException('Unexpected playback acknowledgment');
        _reportedPlaying = true;
      log.event('first-frame');
        onConnected();
      case 'offer':
      case 'answer':
        if ((_sending && message['type'] != 'answer') || (!_sending && message['type'] != 'offer') || _remoteDescription) {
          throw const FormatException('Unexpected session description');
        }
        final sdp = message['sdp'];
        if (sdp is! String || sdp.length > 100000) throw const FormatException('Invalid SDP');
        await _peer!.setRemoteDescription(RTCSessionDescription(sdp, message['type'] as String));
        _remoteDescription = true;
        _peerSupportsTouch = message['touch'] == true;
        for (final candidate in _pendingIce) { await _peer!.addCandidate(candidate); }
        _pendingIce.clear();
        if (!_sending) {
          final answer = await _peer!.createAnswer();
          await _peer!.setLocalDescription(answer);
          send({'type': 'answer', 'sdp': answer.sdp, if (_peerSupportsTouch) 'touch': true});
        }
      case 'ice':
        final candidate = message['candidate'];
        if (candidate is! String || candidate.length > 4096 || _pendingIce.length >= 128) {
          throw const FormatException('Invalid ICE candidate');
        }
        final ice = RTCIceCandidate(candidate, message['mid'] as String?, message['line'] as int?);
        if (_remoteDescription) { await _peer!.addCandidate(ice); } else { _pendingIce.add(ice); }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _diagnostics?.dispose();
    Object? failure;
    Future<void> release(Future<void> Function() action) async {
      try { await action(); } catch (error) { failure ??= error; }
    }
    await release(() async { await _events?.cancel(); });
    if (Platform.isAndroid && _sending) {
      await release(() => _native.invokeMethod<void>('stop'));
    }
    for (final track in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.onEnded = null;
      await release(track.stop);
    }
    await release(() async { await _stream?.dispose(); });
    await release(() async { await _peer?.dispose(); });
    if (_initialized) {
      renderer.onFirstFrameRendered = null;
      renderer.srcObject = null;
      await release(renderer.dispose);
    }
    if (failure != null) throw StateError('Media cleanup failed');
  }
}
