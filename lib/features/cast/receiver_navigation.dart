import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'cast_media.dart';

class ReceiverNavigation extends StatelessWidget {
  const ReceiverNavigation({required this.onNavigate, super.key});

  final ValueChanged<RemoteNavigation> onNavigate;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      IconButton(tooltip: text.remoteBack, icon: const Icon(Icons.arrow_back),
        onPressed: () => onNavigate(RemoteNavigation.back)),
      IconButton(tooltip: text.remoteHome, icon: const Icon(Icons.home_outlined),
        onPressed: () => onNavigate(RemoteNavigation.home)),
      IconButton(tooltip: text.remoteRecents, icon: const Icon(Icons.view_agenda_outlined),
        onPressed: () => onNavigate(RemoteNavigation.recents)),
    ]);
  }
}
