import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AdbDisplay {
  const AdbDisplay(this.description, this.transport);

  final String description;
  final String transport;

  static Future<List<AdbDisplay>> devices() => _connection((reader) async {
    await reader.request('host:devices-l');
    final list = utf8.decode(await reader.readLengthPrefixed());
    final devices = <AdbDisplay>[];
    for (final line in const LineSplitter().convert(list)) {
      if (!RegExp(r'^\S+\s+device\s').hasMatch(line)) continue;
      final match = RegExp(r'\btransport_id:(\d+)\b').firstMatch(line);
      if (match != null) devices.add(AdbDisplay(line.split(RegExp(r'\s+')).first, match[1]!));
    }
    return devices;
  });

  Future<String> restoreCommand() async {
    final help = await _shell('help');
    if (!help.contains('power-off DISPLAY_ID')) throw const FormatException('Display power unavailable');
    if (help.contains('power-reset DISPLAY_ID')) return 'power-reset';
    if (help.contains('power-on DISPLAY_ID')) return 'power-on';
    throw const FormatException('Display power restoration unavailable');
  }

  Future<void> turnOff() async { await _shell('power-off 0'); }

  Future<void> restore(String command) async {
    if (command != 'power-reset' && command != 'power-on') {
      throw ArgumentError.value(command);
    }
    await _shell('$command 0');
  }

  Future<String> _shell(String arguments) => _connection((reader) async {
    await reader.request('host:transport-id:$transport');
    await reader.request('shell,v2,raw:cmd display $arguments');
    final output = BytesBuilder();
    while (true) {
      final header = await reader.read(5);
      final length = ByteData.sublistView(header).getUint32(1, Endian.little);
      final payload = await reader.read(length);
      switch (header[0]) {
        case 1:
          output.add(payload);
          if (output.length > 65536) throw const FormatException('ADB output too large');
        case 2:
          break;
        case 3:
          if (payload.length != 1 || payload.single != 0) {
            throw const FormatException('Display command failed');
          }
          return utf8.decode(output.takeBytes(), allowMalformed: true);
        default:
          throw const FormatException('Invalid ADB shell stream');
      }
    }
  });

  static Future<T> _connection<T>(Future<T> Function(_AdbReader) action) async {
    final timeout = const Duration(seconds: 3);
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, 5037, timeout: timeout);
    try {
      return await action(_AdbReader(socket)).timeout(timeout);
    } finally {
      socket.destroy();
    }
  }
}

class _AdbReader {
  _AdbReader(this.socket) : chunks = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<Uint8List> chunks;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  Future<void> request(String request) async {
    final bytes = utf8.encode(request);
    socket.add(ascii.encode(bytes.length.toRadixString(16).padLeft(4, '0')));
    socket.add(bytes);
    final status = ascii.decode(await read(4));
    if (status == 'FAIL') {
      throw FormatException(utf8.decode(await readLengthPrefixed(), allowMalformed: true));
    }
    if (status != 'OKAY') throw const FormatException('Invalid ADB response');
  }

  Future<Uint8List> readLengthPrefixed() async =>
      read(int.parse(ascii.decode(await read(4)), radix: 16));

  Future<Uint8List> read(int length) async {
    if (length > 65536) throw const FormatException('ADB packet too large');
    final result = Uint8List(length);
    var filled = 0;
    while (filled < length) {
      if (_offset == _chunk.length) {
        if (!await chunks.moveNext()) throw const FormatException('ADB disconnected');
        _chunk = chunks.current;
        _offset = 0;
      }
      final count = (_chunk.length - _offset).clamp(0, length - filled);
      result.setRange(filled, filled + count, _chunk, _offset);
      filled += count;
      _offset += count;
    }
    return result;
  }
}
