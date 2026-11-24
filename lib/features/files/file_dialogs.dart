import 'dart:io';

import 'package:flutter/services.dart';

import 'file_transfer.dart';

class FileDialogs {
  static const _channel = MethodChannel('app.twist.cast/files');
  static Future<TransferFile?> pick() async {
    final value = await _channel.invokeMethod<Object>('pick', {
      'limit': TransferFile.maxBytes,
    });
    if (value == null) return null;
    if (value is String) {
      final file = File(value);
      final handle = await file.open();
      try {
        final length = await handle.length();
        if (length > TransferFile.maxBytes) {
          throw PlatformException(code: 'size');
        }
        final bytes = await handle.read(length + 1);
        if (bytes.length != length) throw PlatformException(code: 'changed');
        return TransferFile(file.uri.pathSegments.last, bytes);
      } finally {
        await handle.close();
      }
    }
    final item = value as Map;
    return TransferFile(item['name'] as String, item['bytes'] as Uint8List);
  }

  static Future<bool> save(String name, Uint8List bytes) async {
    final selected = await _channel.invokeMethod<Object>('save', {
      'name': name,
      if (!Platform.isWindows && !Platform.isLinux) 'bytes': bytes,
    });
    if (selected == null || selected == false) return false;
    if (selected == true) return true;
    final target = File(selected as String);
    final temp = await target.parent.createTemp('.twistcast-');
    try {
      final staged = File.fromUri(temp.uri.resolve('received'));
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(target.path);
    } finally {
      await temp.delete(recursive: true);
    }
    return true;
  }
}
