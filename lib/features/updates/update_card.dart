import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'update_controller.dart';
import 'update_status.dart';

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
    final latest = _updates.release;
    final status = switch (_updates.error) {
      'checkNetwork' => text.updateNetworkFailed,
      'checkRateLimit' => text.updateRateLimited,
      'checkService' => text.updateServiceFailed,
      'checkMetadata' => text.updateMetadataFailed,
      'check' => text.updateCheckFailed,
      'install' => text.updateInstallFailed,
      'download' => text.updateDownloadFailed,
      _ => _updates.phase == 'failed' ? text.updateDownloadFailed : null,
    };
    final progress = _updates.phase == 'downloading' ? _updates.progress : null;

    Widget versionRow(String label, String version, String commit) {
      final theme = Theme.of(context);
      final value = Text(version, textAlign: TextAlign.end, style: theme.textTheme.labelLarge);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant))),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: commit.isEmpty ? value : Tooltip(message: commit, child: value)),
      ]);
    }

    return Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(text.updateCheck, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: _updates.busy || _updates.checking ? null : _updates.check,
            tooltip: text.updateCheck, icon: const Icon(Icons.refresh)),
        ]),
        versionRow(text.updateInstalled,
          _updates.installed.isEmpty ? text.versionLabel : _updates.installedNumberLabel,
          _updates.installedCommit),
        if (latest != null && _updates.available) ...[
          const SizedBox(height: 6),
          versionRow(text.updateLatest, latest.numberLabel, latest.commit),
        ],
        if (_updates.checking || _updates.busy) ...[
          const SizedBox(height: 12),
          UpdateStatus(
            _updates.checking ? text.updateChecking : _updates.phase == 'updating'
              ? text.updateMacProgress
              : '${text.updateDownloading}${progress == null ? '' : ' · ${(progress * 100).floor()}%'}',
            icon: _updates.checking ? Icons.sync : Icons.download,
            showProgress: true, progress: progress,
          ),
        ] else if (status != null) ...[
          const SizedBox(height: 12),
          UpdateStatus(status, icon: Icons.error_outline, tone: UpdateStatusTone.error),
        ] else if (latest != null && !_updates.available && !_updates.canInstallDownloaded) ...[
          const SizedBox(height: 12),
          UpdateStatus(text.updateCurrent, icon: Icons.check_circle_outline, tone: UpdateStatusTone.success),
        ],
        if (_updates.canInstallDownloaded) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: locked ? null : () => _updates.install(text.updateInstallFailed),
            icon: const Icon(Icons.install_mobile),
            label: Text('${text.updateInstall} · ${_updates.downloadedNumberLabel}')),
        ] else if (_updates.available) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: locked ? null : _updates.download,
            icon: const Icon(Icons.download), label: Text(Platform.isMacOS
              ? text.updateMacInstall : _updates.hasNewerDownload ? text.updateDownloadLatest : text.updateDownload)),
        ],
        if (widget.sessionActive) ...[
          const SizedBox(height: 12),
          UpdateStatus(text.updateStopSession, icon: Icons.info_outline),
        ],
      ],
    )));
  });
}
