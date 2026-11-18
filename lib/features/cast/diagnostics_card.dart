import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'diagnostic_log.dart';

class DiagnosticsCard extends StatefulWidget {
  const DiagnosticsCard({required this.log, super.key});
  final DiagnosticLog log;
  @override
  State<DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends State<DiagnosticsCard> {
  bool _saving = false;

  Future<void> _export() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.log.export();
      if (mounted && saved) _notice(AppLocalizations.of(context).diagnosticsSaved);
    } catch (_) {
      if (mounted) _notice(AppLocalizations.of(context).diagnosticsFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isMacOS) return const SizedBox.shrink();
    final text = AppLocalizations.of(context);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(text.diagnosticsTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(text.diagnosticsHint),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: () {
            widget.log.event('user-marker');
            _notice(text.diagnosticsMarked);
          }, child: Text(text.diagnosticsMark)),
          TextButton(onPressed: _saving ? null : _export, child: Text(text.diagnosticsExport)),
        ]),
      ],
    )));
  }
}
