import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

class ReceiverToolbar extends StatelessWidget {
  const ReceiverToolbar({required this.onStop, required this.onToggleHeader,
    required this.headerVisible, this.resizeFailed = false, this.extraControl, super.key});
  final VoidCallback onStop;
  final VoidCallback onToggleHeader;
  final bool headerVisible;
  final bool resizeFailed;
  final Widget? extraControl;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    return SizedBox(height: 48, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Tooltip(message: text.secureSession, child: const Icon(Icons.lock_outline, size: 18)),
          if (resizeFailed) ...[
            const SizedBox(width: 8),
            Tooltip(message: text.resizeWindowFailed, child: Icon(Icons.warning_amber,
              size: 18, color: Theme.of(context).colorScheme.error)),
          ],
          const Spacer(),
          ?extraControl,
          IconButton(onPressed: onToggleHeader,
            tooltip: headerVisible ? text.hideHeader : text.showHeader,
            icon: Icon(headerVisible ? Icons.expand_less : Icons.expand_more)),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: onStop, icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: Text(text.stop)),
        ]),
      ));
  }
}
