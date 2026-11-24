import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'cast_diagnostics.dart';
import 'diagnostic_log.dart';

enum PhonePasteResult { pasted, copied, noField, empty, tooLong, unavailable, unconfirmed }

enum RemoteNavigation { back, home, recents }

class CastMedia {
  CastMedia({required this.send, required this.onStopped, required this.onConnected, required this.log});
  final DiagnosticLog log;
  final void Function(Map<String, dynamic>) send;
  final void Function() onStopped;
  final void Function() onConnected;
  final renderer = RTCVideoRenderer();
  static const _native = MethodChannel('app.twist.cast/capture');
  static const _desktopInput = MethodChannel('app.twist.cast/desktop-input');
  static bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static const desktopKeys = {'Enter', 'Backspace', 'Tab', 'Escape', 'Left', 'Right', 'Up', 'Down'};
  bool _desktopControlOffered = false;
  bool _peerDesktopInput = false;
  bool get canUseDesktopInput => canSendPointer && _peerDesktopInput;
  bool get _supportsInput => _peerSupportsTouch || _peerDesktopInput;
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
  bool _peerSupportsNavigation = false;
  bool _peerSupportsPaste = false;
  int _pasteId = 0;
  Completer<PhonePasteResult>? _pendingPaste;
  // Even after JSON escaping, this fits the secure session's frame limit.
  static const _maxPasteLength = 16384;
  bool get canPaste => _desktop && canSendPointer && _peerSupportsPaste;
  bool remoteTouchEnabled = false;
  bool get canSendPointer => !_closed && !_sending && _reportedPlaying && remoteTouchEnabled;
  bool get canEnableRemoteTouch => _sending && ((Platform.isAndroid && _peerSupportsTouch) || (_desktop && _peerDesktopInput)) && _reportedPlaying && !_closed;

  Future<bool> setRemoteTouch(bool enabled) async {
    if (!canEnableRemoteTouch) return false;
    if (_desktop) {
      if (enabled && await _desktopInput.invokeMethod<bool>('enable') != true) return false;
      if (_closed) return false;
      remoteTouchEnabled = enabled;
      if (!enabled) await _desktopInput.invokeMethod<void>('disable');
      if (!_closed) send({'type': 'touch-state', 'enabled': enabled});
      return enabled;
    }
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

  Future<PhonePasteResult> pasteFromClipboard() async {
    if (!canPaste) return PhonePasteResult.unavailable;
    if (_pendingPaste != null) return PhonePasteResult.unavailable;
    final reply = Completer<PhonePasteResult>();
    _pendingPaste = reply;
    final id = ++_pasteId;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!canPaste || reply.isCompleted) return PhonePasteResult.unavailable;
      final text = data?.text;
      if (text == null || text.isEmpty) return PhonePasteResult.empty;
      if (text.length > _maxPasteLength) return PhonePasteResult.tooLong;
      send({'type': 'paste', 'id': id, 'text': text});
      return await reply.future.timeout(const Duration(seconds: 5),
        onTimeout: () => PhonePasteResult.unconfirmed);
    } on PlatformException {
      return PhonePasteResult.unavailable;
    } on StateError {
      return PhonePasteResult.unavailable;
    } finally {
      _pendingPaste = null;
    }
  }

  Future<void> _receivePaste(Map<String, dynamic> message) async {
    if (!Platform.isAndroid || !_sending || !_peerSupportsPaste || message['id'] is! int) return;
    final text = message['text'];
    var status = 'unavailable';
    if (canEnableRemoteTouch && remoteTouchEnabled && text is String &&
        text.isNotEmpty && text.length <= _maxPasteLength) {
      try {
        status = await _native.invokeMethod<String>('pasteText', {'text': text}) ?? status;
      } on PlatformException {
        // An unavailable accessibility service should not interrupt the video.
      }
    }
    if (!_closed) send({'type': 'paste-result', 'id': message['id'], 'status': status});
  }

  void sendDesktopKey(String key, [String? text]) {
    if (!canUseDesktopInput) return;
    if (key == 'text' ? text == null || text.isEmpty || text.length > 256 : !desktopKeys.contains(key)) return;
    send({'type': 'pointer', 'action': 'key', 'key': key, if (key == 'text') 'text': text});
  }

  bool get canSendNavigation => canSendPointer && _peerSupportsNavigation;

  void sendNavigation(RemoteNavigation action) {
    if (!canSendNavigation) return;
    send({'type': 'pointer', 'action': action.name});
  }

  Future<void> _receivePointer(Map<String, dynamic> message) async {
    if (!canEnableRemoteTouch || !remoteTouchEnabled) return;
    final action = message['action'];
    if (_desktop && action == 'key') {
      final key = message['key'], text = message['text'];
      if (key is! String || (key == 'text'
          ? text is! String || text.isEmpty || text.length > 256
          : !desktopKeys.contains(key))) {
        return;
      }
      await _desktopInput.invokeMethod<void>('key', {'key': key, if (key == 'text') 'text': text});
      return;
    }
    if (Platform.isAndroid && RemoteNavigation.values.any((entry) => entry.name == action)) {
      await _native.invokeMethod<void>('remotePointer', {'action': action});
      return;
    }
    if (!const {'down', 'move', 'up', 'cancel', 'scroll'}.contains(action) &&
        !(_desktop && action == 'secondary')) {
      return;
    }
    final args = <String, dynamic>{'action': action, 'landscape': message['landscape'] == true};
    for (final field in ['x', 'y', 'dx', 'dy']) {
      final value = message[field];
      if (value is! num || !value.isFinite) return;
      final axis = field == 'x' || field == 'y';
      if (value < (axis ? 0 : -0.35) || value > (axis ? 1 : 0.35)) return;
      args[field] = value.toDouble();
    }
    if (_desktop) {
      await _desktopInput.invokeMethod<void>('pointer', args);
    } else {
      await _native.invokeMethod<void>('remotePointer', args);
    }
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
      if (_sending) return <String, num>{};
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
    Object video = Platform.isIOS ? {'deviceId': 'broadcast'} : true;
    if (_desktop) {
      if (await _desktopInput.invokeMethod<bool>('captureAvailable') != true) {
        throw StateError('Desktop capture unavailable');
      }
      if (_closed) return;
      if (Platform.isMacOS) {
        // The native capturer uses the main display, including on macOS 12.
        _desktopControlOffered = true;
      } else {
        final screens = await desktopCapturer.getSources(types: [SourceType.Screen]);
        if (_closed) return;
        if (screens.isEmpty) throw StateError('No desktop screen');
        video = {'deviceId': {'exact': screens.first.id}};
        _desktopControlOffered = screens.length == 1;
      }
    }
    final stream = await navigator.mediaDevices.getDisplayMedia({'video': video, 'audio': !_desktop});
    if (_closed) {
      for (final track in stream.getTracks()) { await track.stop(); }
      await stream.dispose();
      if (Platform.isAndroid) await _native.invokeMethod<void>('stop');
      return;
    }
    _stream = stream;
    if (stream.getVideoTracks().isEmpty) throw StateError('No screen video track');
    for (final track in stream.getVideoTracks()) { track.onEnded = onStopped; }
    if (!_desktop) await setAudio(audio);
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
    if (!_closed) {
      send({'type': 'offer', 'sdp': offer.sdp,
        if (_desktopControlOffered) 'desktopInput': true,
        if (Platform.isAndroid) ...{'touch': true, 'navigation': true, 'paste': true}});
    }
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
      case 'paste':
        await _receivePaste(message);
      case 'paste-result':
        final pending = _pendingPaste;
        if (!canPaste || pending == null || pending.isCompleted || message['id'] != _pasteId) return;
        pending.complete(switch (message['status']) {
          'pasted' => PhonePasteResult.pasted,
          'copied' => PhonePasteResult.copied,
          'noField' => PhonePasteResult.noField,
          _ => PhonePasteResult.unavailable,
        });
      case 'touch-state':
        if (_sending || !_supportsInput || !_reportedPlaying) return;
        remoteTouchEnabled = message['enabled'] == true;
        if (!remoteTouchEnabled) _cancelPaste();
        onConnected();
      case 'pointer':
        try {
          await _receivePointer(message);
        } on PlatformException {
          if (!_desktop || _closed) rethrow;
          // Permission or display topology can change while the stream continues.
          remoteTouchEnabled = false;
          await _desktopInput.invokeMethod<void>('disable');
          if (!_closed) {
            send({'type': 'touch-state', 'enabled': false});
            onConnected();
          }
        }
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
        _peerSupportsTouch = message['touch'] == true && (!_sending || Platform.isAndroid);
        _peerDesktopInput = message['desktopInput'] == true &&
            (_sending ? _desktopControlOffered : Platform.isAndroid || Platform.isIOS);
        _peerSupportsPaste = _peerSupportsTouch && message['paste'] == true &&
            (_sending ? Platform.isAndroid : _desktop);
        _peerSupportsNavigation = !_sending && message['navigation'] == true;
        for (final candidate in _pendingIce) { await _peer!.addCandidate(candidate); }
        _pendingIce.clear();
        if (!_sending) {
          final answer = await _peer!.createAnswer();
          await _peer!.setLocalDescription(answer);
          send({'type': 'answer', 'sdp': answer.sdp, if (_peerDesktopInput) 'desktopInput': true, if (_peerSupportsTouch) 'touch': true,
            if (_peerSupportsPaste) 'paste': true});
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

  void _cancelPaste() {
    final pending = _pendingPaste;
    if (pending != null && !pending.isCompleted) pending.complete(PhonePasteResult.unavailable);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancelPaste();
    _diagnostics?.dispose();
    Object? failure;
    Future<void> release(Future<void> Function() action) async {
      try { await action(); } catch (error) { failure ??= error; }
    }
    if (_desktop && _sending) {
      remoteTouchEnabled = false;
      await release(() => _desktopInput.invokeMethod<void>('disable'));
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
