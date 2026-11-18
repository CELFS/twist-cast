import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'update_controller.dart';

class UpdateCard extends StatefulWidget {
  const UpdateCard({required this.sessionActive, required this.onInstallingChanged, super.key});
  final bool sessionActive;
  final ValueChanged<bool> onInstallingChanged;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  final _updates = UpdateController();
  bool _installing = false;

  void _onChanged() {
    final installing = Platform.isMacOS && _updates.busy;
    if (installing != _installing) {
      _installing = installing;
      widget.onInstallingChanged(installing);
    }
  }

  @override
  void initState() { super.initState(); _updates.addListener(_onChanged); _updates.check(); }

  @override
  void dispose() { _updates.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _updates, builder: (context, _) {
    final text = AppLocalizations.of(context);
    final locked = widget.sessionActive || _updates.busy || _updates.checking;
    return Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(text.updateCheck, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: locked ? null : _updates.check,
            tooltip: text.updateCheck, icon: const Icon(Icons.refresh)),
        ]),
        Text('${text.updateInstalled} · ${_updates.installed.isEmpty ? text.versionLabel : 'v${_updates.installed}'}'),
        if (_updates.release != null) Text('${text.updateLatest} · v${_updates.release!.version}'),
        if (_updates.checking || _updates.busy) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _updates.phase == 'downloading' ? _updates.progress : null),
          const SizedBox(height: 8),
          Text(_updates.checking ? text.updateChecking : _updates.phase == 'updating'
            ? text.updateMacProgress : '${text.updateDownloading}${_updates.progress == null ? '' : ' · ${(_updates.progress! * 100).floor()}%'}'),
        ],
        if (_updates.phase == 'ready') ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: locked ? null : () => _updates.install(text.updateInstallFailed),
            icon: const Icon(Icons.install_mobile), label: Text('${text.updateInstall} · v${_updates.state['targetVersion']}')),
        ] else if (_updates.available) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: locked ? null : _updates.download,
            icon: const Icon(Icons.download), label: Text(Platform.isMacOS ? text.updateMacInstall : text.updateDownload)),
        ] else if (!_updates.checking && _updates.error == null && _updates.release != null)
          Text(text.updateCurrent),
        if (widget.sessionActive) Text(text.updateStopSession),
        if (_updates.error != null || _updates.phase == 'failed') ...[
          const SizedBox(height: 8),
          Text(_updates.error == 'check' ? text.updateCheckFailed : _updates.error == 'install'
            ? text.updateInstallFailed : text.updateDownloadFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    )));
  });
}
