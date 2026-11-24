import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'file_dialogs.dart';
import 'file_transfer.dart';

class FileTransferCard extends StatefulWidget {
  const FileTransferCard({required this.transfer, super.key});
  final FileTransfer transfer;
  @override
  State<FileTransferCard> createState() => _FileTransferCardState();
}

class _FileTransferCardState extends State<FileTransferCard> {
  bool _busy = false;

  Future<void> _dialog({required bool pick}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final transfer = widget.transfer;
    try {
      if (pick) {
        final file = await FileDialogs.pick();
        if (mounted && transfer.canOffer && file != null) transfer.offer(file);
      } else {
        final saved = await FileDialogs.save(transfer.name, transfer.received!);
        if (mounted && saved) transfer.saved();
      }
    } on Exception catch (error) {
      if (mounted) {
        final text = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PlatformException && error.code == 'size'
                  ? text.fileLimit
                  : text.fileDialogError,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MiB';

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final file = widget.transfer;
    return ListenableBuilder(
      listenable: file,
      builder: (context, _) {
        final status = switch (file.phase) {
          FilePhase.idle => file.sender ? text.fileLimit : text.fileWait,
          FilePhase.offered =>
            file.sender ? text.fileWaitAccept : text.fileIncoming,
          FilePhase.transferring =>
            '${_size(file.transferred)} / ${_size(file.size)}',
          FilePhase.received =>
            file.sender ? text.fileWaitSave : text.fileReadySave,
          FilePhase.saved => text.fileSaved,
          FilePhase.declined => text.fileDeclined,
        };
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.sender ? text.sendFile : text.receiveFile,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (file.name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('${file.name} · ${_size(file.size)}'),
                  ),
                const SizedBox(height: 8),
                Text(status),
                if (file.phase == FilePhase.transferring)
                  LinearProgressIndicator(
                    value: file.size == 0 ? 1 : file.transferred / file.size,
                  ),
                const SizedBox(height: 12),
                if (file.canOffer)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _dialog(pick: true),
                    icon: const Icon(Icons.attach_file),
                    label: Text(text.fileChoose),
                  ),
                if (!file.sender && file.phase == FilePhase.offered)
                  Wrap(
                    spacing: 10,
                    children: [
                      FilledButton(
                        onPressed: file.accept,
                        child: Text(text.fileAccept),
                      ),
                      TextButton(
                        onPressed: file.decline,
                        child: Text(text.fileDecline),
                      ),
                    ],
                  ),
                if (file.received != null)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _dialog(pick: false),
                    icon: const Icon(Icons.save_alt),
                    label: Text(text.fileSave),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
