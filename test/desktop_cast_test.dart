import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twist_cast/features/cast/cast_media.dart';
import 'package:twist_cast/features/cast/diagnostic_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop capture sends video only and enforces the local input grant', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    void mock(String name, Future<dynamic> Function(MethodCall) handler) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, handler);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    for (final name in ['FlutterWebRTC.Event', 'FlutterWebRTC/Texture1', 'FlutterWebRTC/peerConnectionEventpc']) {
      mock(name, (_) async => null);
    }
    const track = {'id': 'video', 'label': 'Screen', 'kind': 'video', 'enabled': true};
    mock('FlutterWebRTC.Method', (call) async {
      switch (call.method) {
        case 'createPeerConnection': return {'peerConnectionId': 'pc'};
        case 'createVideoRenderer': return {'textureId': 1};
        case 'getDesktopSources':
          return {'sources': [{'id': '1', 'name': 'Screen', 'type': 'screen',
            'thumbnailSize': {'width': 0, 'height': 0}}]};
        case 'getDisplayMedia':
          expect(call.arguments['constraints']['audio'], isFalse);
          return {'streamId': 'stream', 'audioTracks': [], 'videoTracks': [track]};
        case 'addTrack':
          return {'senderId': 'sender', 'track': track, 'ownsTrack': true,
            'rtpParameters': {'encodings': [], 'headerExtensions': [], 'codecs': [],
              'transactionId': '', 'rtcp': {'reducedSize': false}}};
        case 'createOffer': return {'sdp': 'offer', 'type': 'offer'};
        default: return null;
      }
    });

    final inputs = <String>[];
    mock('app.twist.cast/desktop-input', (call) async {
      if (call.method == 'captureAvailable' || call.method == 'enable') return true;
      inputs.add(call.method);
      return null;
    });
    final sent = <Map<String, dynamic>>[];
    final media = CastMedia(send: sent.add, onConnected: () {}, onStopped: () {}, log: DiagnosticLog('sender'));
    addTearDown(media.close);
    await media.prepare();
    await media.share(audio: false, title: '', body: '');
    expect(sent.single['desktopInput'], isTrue);
    await media.handle({'type': 'answer', 'sdp': 'answer', 'desktopInput': true});
    await media.handle({'type': 'playing'});
    const pointer = {'type': 'pointer', 'action': 'down', 'x': .4, 'y': .5, 'dx': 0, 'dy': 0};
    const key = {'type': 'pointer', 'action': 'key', 'key': 'Enter'};

    // The receiver cannot self-authorize by sending the sender's state message.
    await media.handle({'type': 'touch-state', 'enabled': true});
    await media.handle(pointer);
    await media.handle(key);
    expect(inputs, isEmpty);
    expect(await media.setRemoteTouch(true), isTrue);
    await media.handle({...pointer, 'x': 1.1});
    await media.handle({...key, 'key': 'unknown'});
    expect(inputs, isEmpty);
    await media.handle(pointer);
    await media.handle(key);
    expect(inputs, ['pointer', 'key']);
    await media.setRemoteTouch(false);
    await media.handle(pointer);
    expect(inputs, ['pointer', 'key', 'disable']);
    expect(sent.last, {'type': 'touch-state', 'enabled': false});
    await media.setRemoteTouch(true);
    await media.close();
    await media.handle(key);
    expect(inputs.last, 'disable');
  }, skip: Platform.isAndroid || Platform.isIOS);
}
