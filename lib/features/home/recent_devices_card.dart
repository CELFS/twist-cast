import 'package:material_ui/material_ui.dart';

import '../../core/recent_device.dart';
import '../../l10n/generated/app_localizations.dart';
import '../cast/cast_controller.dart';

class RecentDevicesCard extends StatelessWidget {
  const RecentDevicesCard({
    required this.cast,
    required this.enabled,
    super.key,
  });
  final CastController cast;
  final bool enabled;

  String _status(RecentDevice device, AppLocalizations text) {
    if (cast.phase != CastPhase.recent) return text.recentShare;
    if (cast.receiverFor(device) != null) return text.recentReady;
    return cast.reconnecting?.id == device.id
        ? text.recentWaiting
        : text.recentChecking;
  }

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final checking = cast.phase == CastPhase.recent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    text.recentDevices,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: text.recentCheck,
                  icon: const Icon(Icons.refresh),
                  onPressed: enabled && !checking ? cast.refreshRecent : null,
                ),
              ],
            ),
            Text(text.recentHint),
            if (checking)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            for (final device in cast.recentDevices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  cast.isMobile ? Icons.computer : Icons.smartphone,
                ),
                title: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_status(device, text)),
                onTap: enabled && cast.reconnecting?.id != device.id
                    ? () => cast.connectRecent(device)
                    : null,
                trailing: PopupMenuButton<bool>(
                  enabled: enabled,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: true, child: Text(text.recentReceive)),
                    PopupMenuItem(value: false, child: Text(text.recentRemove)),
                  ],
                  onSelected: (receive) async {
                    if (receive) {
                      await cast.receive(from: device);
                    } else {
                      try {
                        await cast.removeRecent(device);
                      } on Exception {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(text.recentRemoveFailed)),
                          );
                        }
                      }
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
