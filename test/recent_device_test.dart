import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:twist_cast/features/cast/cast_controller.dart';
import 'package:twist_cast/features/home/recent_devices_card.dart';
import 'package:twist_cast/l10n/generated/app_localizations.dart';
import 'package:twist_cast/core/recent_device.dart';

RecentDevice device(int number, [String name = 'Computer']) => RecentDevice(
  id: base64Encode(List.filled(32, number)),
  name: name,
  discoveryKey: base64Encode(List.filled(32, 255 - number)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rotating receiver tags identify the saved peer even for identical names',
    () {
      final saved = device(0);
      final first = saved.advertisement();
      final next = saved.advertisement();
      expect(first, isNot(next));
      expect(saved.matches(first), isTrue);
      expect(saved.matches(next), isTrue);
      expect(device(1).matches(first), isFalse);
      expect(saved.matches(null), isFalse);
      expect(saved.matches(saved.id), isFalse);
      expect(first, isNot(contains(saved.discoveryKey)));
      final profile = RecentDevice.parse(saved.id, {
        'name': ' \nDesk\u202e ',
        'lookup': saved.discoveryKey,
      });
      expect(profile?.name, 'Desk');
      expect(
        RecentDevice.parse(saved.id, {'name': 'Desk', 'lookup': 'bad'}),
        isNull,
      );
    },
  );

  test(
    'secure recent history caps, reorders, removes and survives a restart',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      final history = RecentDeviceStore(storage);
      await Future.wait(List.generate(11, (n) => history.remember(device(n))));
      expect(
        history.devices.map((it) => it.id),
        List.generate(10, (i) => device(10 - i).id),
      );
      await history.remember(device(2, 'Renamed computer'));
      expect(history.devices.first.name, 'Renamed computer');
      expect(history.devices.length, 10);
      await history.remove(device(8).id);
      final loaded = RecentDeviceStore(storage);
      await loaded.load();
      expect(
        loaded.devices.map((it) => it.id),
        history.devices.map((it) => it.id),
      );
      expect(loaded.devices.first.matches(device(2).advertisement()), isTrue);
      expect(loaded.devices.length, 9);
    },
  );

  test('invalid local history can be replaced by a fresh pairing', () async {
    FlutterSecureStorage.setMockInitialValues({'recent.devices.v1': 'broken'});
    final history = RecentDeviceStore(const FlutterSecureStorage());
    await history.load();
    expect(history.devices, isEmpty);
    await history.remember(device(1));
    expect(history.devices.single.id, device(1).id);
  });

  testWidgets('recent shortcuts can be removed without opening discovery', (
    tester,
  ) async {
    final saved = device(7, 'Office computer');
    FlutterSecureStorage.setMockInitialValues({
      'recent.devices.v1': jsonEncode([
        {'id': saved.id, ...saved.profile},
      ]),
    });
    final cast = CastController();
    addTearDown(cast.dispose);
    await cast.loadRecent();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: cast,
            builder: (_, _) => RecentDevicesCard(cast: cast, enabled: true),
          ),
        ),
      ),
    );
    expect(find.text('Office computer'), findsOneWidget);
    expect(find.text('Ready to receive'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<bool>));
    await tester.pumpAndSettle();
    expect(find.text('Receive from this device'), findsOneWidget);
    await tester.tap(find.text('Remove from recent devices'));
    await tester.pumpAndSettle();
    expect(find.text('Office computer'), findsNothing);
    expect(cast.phase, CastPhase.idle);
  });
}
