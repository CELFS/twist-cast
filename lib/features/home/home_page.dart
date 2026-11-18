import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    required this.locale,
    required this.onLocaleChanged,
    super.key,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(text.appName, style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 12),
                  Text(text.tagline, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 32),
                  Text(text.language, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButton<Locale>(
                    value: locale,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: const Locale('en'),
                        child: Text(text.english),
                      ),
                      DropdownMenuItem(
                        value: const Locale('zh'),
                        child: Text(text.chinese),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onLocaleChanged(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
