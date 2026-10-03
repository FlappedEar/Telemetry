import 'package:flutter/material.dart';

import 'import/day_import_page.dart';
import 'l10n.dart';
import 'units.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSettings();
  runApp(const TelemetryApp());
}

class TelemetryApp extends StatelessWidget {
  const TelemetryApp({
    super.key,
    this.home = const DayImportPage(),
    this.locale,
  });

  final Widget home;

  /// The app's language; null follows the device (see [resolveAppLocale]).
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Every speed label follows the setting at once. Numbers and dates
      // formatted without a context follow the app's language.
      builder: (context, child) {
        useFormattingLocale(Localizations.localeOf(context));
        return SpeedUnitScope(child: child ?? const SizedBox.shrink());
      },
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: locale,
      supportedLocales: supportedLocales,
      localeListResolutionCallback: (preferred, _) =>
          resolveAppLocale(preferred),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff55e6a5)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff55e6a5),
          brightness: Brightness.dark,
        ),
      ),
      home: home,
    );
  }
}
