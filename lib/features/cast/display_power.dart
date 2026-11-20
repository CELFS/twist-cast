import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'adb_display.dart';

class DisplayPower extends ChangeNotifier {
  AdbDisplay? _device;
  String? _restoreCommand;
  Future<void>? _operation;
  bool _closed = false;

  bool get screenOff => _device != null;
  bool get busy => _operation != null;

  Future<void> toggle(BuildContext context) async {
    if (_closed || busy) return;
    final text = AppLocalizations.of(context);
    final operation = _toggle(context, text);
    _operation = operation;
    notifyListeners();
    try {
      await operation;
    } catch (_) {
      if (!_closed && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text.displayPowerFailed)));
      }
    } finally {
      _operation = null;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _toggle(BuildContext context, AppLocalizations text) async {
    if (screenOff) {
      await _restore();
      return;
    }
    final devices = await AdbDisplay.devices();
    if (devices.isEmpty) throw StateError('No authorized ADB devices');
    if (_closed || !context.mounted) return;
    final device = await showDialog<AdbDisplay>(context: context, builder: (context) =>
      SimpleDialog(title: Text(text.displayPowerDevice), children: [
        for (final device in devices) SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(device),
          child: Text(device.description)),
      ]));
    if (device == null || _closed) return;
    final restore = await device.restoreCommand();
    if (_closed) return;
    _device = device;
    _restoreCommand = restore;
    try {
      await device.turnOff();
    } catch (_) {
      // A timed-out command might already have reached the phone.
      await _restore();
      rethrow;
    }
  }

  Future<void> _restore() async {
    final device = _device;
    if (device == null) return;
    await device.restore(_restoreCommand!);
    _device = null;
    _restoreCommand = null;
  }

  Future<void> _restoreOnClose() async {
    try { await _operation; } catch (_) { /* Try restoration again below. */ }
    try { await _restore(); } catch (_) { /* ADB may be disconnected. */ }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_restoreOnClose());
    super.dispose();
  }
}

class DisplayPowerButton extends StatelessWidget {
  const DisplayPowerButton({required this.power, super.key});
  final DisplayPower power;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    return ListenableBuilder(listenable: power, builder: (context, _) => IconButton(
      onPressed: power.busy ? null : () => power.toggle(context),
      tooltip: power.screenOff ? text.displayPowerOn : text.displayPowerOff,
      icon: Icon(power.screenOff ? Icons.smartphone : Icons.screen_lock_portrait_outlined),
    ));
  }
}
