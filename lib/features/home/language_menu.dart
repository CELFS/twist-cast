import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

class LanguageMenu extends StatelessWidget {
  const LanguageMenu({required this.locale, required this.onChanged, super.key});

  final Locale locale;
  final ValueChanged<Locale> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final languages = {const Locale('en'): text.english, const Locale('zh'): text.chinese};
    final radius = BorderRadius.circular(8);
    return PopupMenuButton<Locale>(
      tooltip: text.language,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 5),
      padding: EdgeInsets.zero,
      menuPadding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 176),
      borderRadius: radius,
      shape: RoundedRectangleBorder(borderRadius: radius,
        side: BorderSide(color: colors.outlineVariant)),
      color: colors.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final language in languages.entries)
          PopupMenuItem<Locale>(
            value: language.key,
            height: 34,
            padding: EdgeInsets.zero,
            child: Semantics(selected: locale == language.key, child: DecoratedBox(
              decoration: BoxDecoration(
                color: locale == language.key ? colors.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(language.value, style: theme.textTheme.labelLarge)),
                  if (locale == language.key) Icon(Icons.check, size: 14, color: colors.onSecondaryContainer),
                ]),
              ),
            )),
          ),
      ],
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.42),
          borderRadius: radius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(languages[locale] ?? text.english,
            style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 15, color: colors.onSurfaceVariant),
        ]),
      ),
    );
  }
}
