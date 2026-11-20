import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

class AppFooter extends StatelessWidget {
  const AppFooter({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: SizedBox(
    height: compact ? 20 : 36,
    child: Center(child: Text(AppLocalizations.of(context).footerLabel,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1.2,
      ),
    )),
  ));
}
