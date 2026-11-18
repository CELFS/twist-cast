import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

class AppBrand extends StatelessWidget {
  const AppBrand({super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.asset(
      'assets/branding/twistcast-icon.png', width: 32, height: 32, excludeFromSemantics: true,
    )),
    const SizedBox(width: 10),
    Flexible(child: Text(AppLocalizations.of(context).appName, maxLines: 1, overflow: TextOverflow.ellipsis)),
  ]);
}
