import 'package:material_ui/material_ui.dart';

import 'features/home/home_page.dart';
import 'l10n/generated/app_localizations.dart';

class TwistCastApp extends StatefulWidget {
  const TwistCastApp({super.key});

  @override
  State<TwistCastApp> createState() => _TwistCastAppState();
}

class _TwistCastAppState extends State<TwistCastApp> {
  Locale _locale = const Locale('en');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      home: HomePage(
        locale: _locale,
        onLocaleChanged: (locale) {
          setState(() => _locale = locale);
        },
      ),
    );
  }
}
