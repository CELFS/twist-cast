import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:twist_cast/features/files/file_transfer.dart';
import 'package:twist_cast/features/files/file_transfer_card.dart';
import 'package:twist_cast/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FileTransfer sender, receiver;
  late Queue<Map<String, dynamic>> toSender, toReceiver;
  void drain() {
    while (toSender.isNotEmpty || toReceiver.isNotEmpty) {
      if (toReceiver.isNotEmpty) receiver.handle(toReceiver.removeFirst());
      if (toSender.isNotEmpty) sender.handle(toSender.removeFirst());
    }
  }

  setUp(() {
    toSender = Queue();
    toReceiver = Queue();
    sender = FileTransfer(sender: true, send: toReceiver.add);
    receiver = FileTransfer(sender: false, send: toSender.add);
  });
  tearDown(() {
    sender.dispose();
    receiver.dispose();
  });

  for (final size in [
    0,
    FileTransfer.chunkSize,
    FileTransfer.chunkSize * 2 + 7,
  ]) {
    test(
      'transfers $size bytes after acceptance and confirms saving separately',
      () {
        final bytes = Uint8List.fromList(List.generate(size, (i) => i % 251));
        sender.offer(TransferFile('folder/file.bin', bytes));
        drain();
        expect(receiver.name, 'file.bin');
        expect(receiver.received, isNull);
        expect(sender.transferred, 0);
        receiver.accept();
        drain();
        expect(receiver.received, orderedEquals(bytes));
        expect(sender.phase, FilePhase.received);
        expect(sender.canOffer, isFalse);
        receiver.saved();
        drain();
        expect(sender.phase, FilePhase.saved);
        expect(sender.canOffer, isTrue);
        expect(receiver.received, isNull);
      },
    );
  }

  test('declining allows a different offer in the same session', () {
    sender.offer(TransferFile('a', Uint8List(10)));
    drain();
    receiver.decline();
    drain();
    expect(sender.phase, FilePhase.declined);
    sender.offer(TransferFile('b', Uint8List(0)));
    drain();
    expect(receiver.name, 'b');
    expect(receiver.phase, FilePhase.offered);
  });

  test(
    'rejects early data, excessive sizes, bad offsets and checksum mismatches',
    () {
      final offer = {
        'type': 'file-offer',
        'name': 'a',
        'size': 1,
        'digest': sha256.convert([0]).toString(),
      };
      final chunk = {
        'type': 'file-data',
        'offset': 0,
        'data': base64Encode([1]),
      };
      expect(
        () => receiver.handle({...offer, 'size': TransferFile.maxBytes + 1}),
        throwsFormatException,
      );
      receiver.handle(offer);
      expect(() => receiver.handle(chunk), throwsFormatException);
      receiver.accept();
      expect(
        () => receiver.handle({...chunk, 'offset': 1}),
        throwsFormatException,
      );
      receiver.handle(chunk);
      expect(
        () => receiver.handle({'type': 'file-end'}),
        throwsFormatException,
      );
      expect(receiver.received, isNull);
    },
  );

  test('disconnecting after delivery preserves the verified file for saving', () {
    sender.offer(TransferFile('document', Uint8List.fromList([42])));
    drain();
    receiver.accept();
    drain();
    expect(receiver.retainOnDisconnect(), isTrue);
    expect(receiver.received, [42]);
    receiver.saved();
    expect(receiver.phase, FilePhase.saved);
    expect(toSender, isEmpty);
  });

  test('suggested names are bounded portable leaf names', () {
    expect(TransferFile.safeName(r'..\dir/CON.txt'), '_CON.txt');
    expect(TransferFile.safeName('../..'), 'file');
    expect(
      utf8.encode(TransferFile.safeName('🌈' * 100)).length,
      lessThanOrEqualTo(220),
    );
  });

  testWidgets('canceling save keeps the received file available for retry', (
    tester,
  ) async {
    const channel = MethodChannel('app.twist.cast/files');
    var attempts = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'save');
      return ++attempts > 1;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    sender.offer(TransferFile('test.txt', Uint8List(2)));
    drain();
    receiver.accept();
    drain();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FileTransferCard(transfer: receiver)),
      ),
    );
    await tester.tap(find.text('Save file'));
    await tester.pumpAndSettle();
    expect(receiver.phase, FilePhase.received);
    await tester.tap(find.text('Save file'));
    await tester.pumpAndSettle();
    drain();
    expect(sender.phase, FilePhase.saved);
  });
}
