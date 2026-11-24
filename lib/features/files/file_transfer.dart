import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum FilePhase { idle, offered, transferring, received, saved, declined }

class TransferFile {
  const TransferFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  static const maxBytes = 32 * 1024 * 1024;

  // Treat the peer's filename as a suggested leaf name on every platform.
  static String safeName(String value) {
    var name = value
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(
          RegExp(r'[<>:"|?*\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]'),
          '_',
        )
        .trim();
    var byteCount = 0;
    name = String.fromCharCodes(
      name.runes.takeWhile((rune) {
        byteCount += rune < 128
            ? 1
            : rune < 2048
            ? 2
            : rune < 65536
            ? 3
            : 4;
        return byteCount <= 220;
      }),
    ).replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) return 'file';
    if (RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      return '_$name';
    }
    return name;
  }
}

/// One outstanding offer per session. A receiver acknowledges each bounded
/// chunk after consuming it, so a fast sender cannot fill the signaling queue.
class FileTransfer extends ChangeNotifier {
  FileTransfer({required this.sender, required this.send});
  final bool sender;
  final void Function(Map<String, dynamic>) send;
  static const chunkSize = 64 * 1024;
  FilePhase phase = FilePhase.idle;
  String name = '';
  int size = 0;
  int transferred = 0;
  Uint8List? _bytes;
  BytesBuilder? _incoming;
  String? _digest;
  bool _finishedSending = false;
  bool _closed = false;
  bool _peerConnected = true;

  bool retainOnDisconnect() {
    _peerConnected = false;
    return received != null;
  }
  Uint8List? get received =>
      !sender && phase == FilePhase.received ? _bytes : null;
  bool get canOffer =>
      !_closed &&
      sender &&
      [FilePhase.idle, FilePhase.saved, FilePhase.declined].contains(phase);

  void offer(TransferFile file) {
    if (!canOffer || file.bytes.length > TransferFile.maxBytes) {
      throw StateError('Invalid file offer');
    }
    name = TransferFile.safeName(file.name);
    size = file.bytes.length;
    transferred = 0;
    _finishedSending = false;
    _bytes = file.bytes;
    _digest = sha256.convert(file.bytes).toString();
    phase = FilePhase.offered;
    send({'type': 'file-offer', 'name': name, 'size': size, 'digest': _digest});
    notifyListeners();
  }

  void accept() {
    if (sender || phase != FilePhase.offered) return;
    _incoming = BytesBuilder(copy: false);
    phase = FilePhase.transferring;
    send({'type': 'file-accept'});
    notifyListeners();
  }

  void decline() {
    if (sender || phase != FilePhase.offered) return;
    phase = FilePhase.declined;
    send({'type': 'file-decline'});
    notifyListeners();
  }

  void saved() {
    if (received == null) return;
    _bytes = null;
    phase = FilePhase.saved;
    if (_peerConnected) send({'type': 'file-saved'});
    notifyListeners();
  }

  void handle(Map<String, dynamic> message) {
    final type = message['type'];
    if (!sender &&
        type == 'file-offer' &&
        [FilePhase.idle, FilePhase.saved, FilePhase.declined].contains(phase)) {
      final length = message['size'],
          label = message['name'],
          hash = message['digest'];
      if (length is! int ||
          length < 0 ||
          length > TransferFile.maxBytes ||
          label is! String ||
          label.length > 255 ||
          hash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        throw const FormatException('Invalid file offer');
      }
      name = TransferFile.safeName(label);
      size = length;
      transferred = 0;
      _digest = hash;
      phase = FilePhase.offered;
    } else if (sender && phase == FilePhase.offered && type == 'file-decline') {
      _bytes = null;
      phase = FilePhase.declined;
    } else if (sender && phase == FilePhase.offered && type == 'file-accept') {
      phase = FilePhase.transferring;
      _sendNext();
    } else if (sender &&
        phase == FilePhase.transferring &&
        !_finishedSending &&
        type == 'file-ack' &&
        message['offset'] == transferred) {
      _sendNext();
    } else if (!sender &&
        phase == FilePhase.transferring &&
        type == 'file-data') {
      final data = message['data'];
      final remaining = size - transferred;
      final expected = remaining.clamp(0, chunkSize);
      if (expected == 0 ||
          data is! String ||
          data.length != (expected + 2) ~/ 3 * 4 ||
          message['offset'] != transferred) {
        throw const FormatException('Invalid file chunk');
      }
      final bytes = base64Decode(data);
      if (bytes.length != expected) {
        throw const FormatException('Invalid chunk length');
      }
      _incoming!.add(bytes);
      transferred += bytes.length;
      send({'type': 'file-ack', 'offset': transferred});
    } else if (!sender &&
        phase == FilePhase.transferring &&
        type == 'file-end' &&
        transferred == size) {
      final result = _incoming!.takeBytes();
      _incoming = null;
      if (sha256.convert(result).toString() != _digest) {
        throw const FormatException('File checksum mismatch');
      }
      _bytes = result;
      phase = FilePhase.received;
      send({'type': 'file-received'});
    } else if (sender &&
        _finishedSending &&
        phase == FilePhase.transferring &&
        type == 'file-received') {
      _bytes = null;
      phase = FilePhase.received;
    } else if (sender && phase == FilePhase.received && type == 'file-saved') {
      phase = FilePhase.saved;
    } else {
      throw const FormatException('Unexpected file message');
    }
    notifyListeners();
  }

  void _sendNext() {
    if (transferred == size) {
      _finishedSending = true;
      send({'type': 'file-end'});
      return;
    }
    final start = transferred;
    transferred = (start + chunkSize).clamp(0, size);
    send({
      'type': 'file-data',
      'offset': start,
      'data': base64Encode(Uint8List.sublistView(_bytes!, start, transferred)),
    });
  }

  @override
  void dispose() {
    _bytes = null;
    _incoming = null;
    _closed = true;
    super.dispose();
  }
}
