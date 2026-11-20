import 'package:material_ui/material_ui.dart';

enum UpdateStatusTone { info, success, error }

class UpdateStatus extends StatelessWidget {
  const UpdateStatus(this.message, {
    required this.icon, this.tone = UpdateStatusTone.info,
    this.showProgress = false, this.progress, super.key,
  });

  final String message;
  final IconData icon;
  final UpdateStatusTone tone;
  final bool showProgress;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      UpdateStatusTone.info => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
      UpdateStatusTone.success => (colors.tertiaryContainer, colors.onTertiaryContainer),
      UpdateStatusTone.error => (colors.errorContainer, colors.onErrorContainer),
    };
    return Semantics(liveRegion: !showProgress, child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground))),
        ]),
        if (showProgress) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
        ],
      ]),
    ));
  }
}
