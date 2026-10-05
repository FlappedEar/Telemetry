import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_navigation.dart';
import 'channel_names.dart';
import 'diagnostics/app_errors.dart';
import 'import/day_import_page.dart';
import 'l10n.dart';
import 'profile/profile_library.dart';
import 'ui/theme.dart';
import 'units.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  await loadSettings();
  LicenseRegistry.addLicense(_fontLicenses);
  final l10n = deviceL10n();
  runApp(
    TelemetryApp(
      home: DayImportPage(
        library: ProfileLibrary(
          defaultCarName: l10n.libraryDefaultCar,
          defaultTrackName: l10n.libraryDefaultTrack,
        ),
      ),
    ),
  );
}

/// The bundled fonts' SIL Open Font License texts, which must ship with them.
Stream<LicenseEntry> _fontLicenses() async* {
  for (final (font, file) in [
    ('Sora', 'OFL-Sora.txt'),
    ('JetBrains Mono', 'OFL-JetBrainsMono.txt'),
  ]) {
    final text = await rootBundle.loadString('assets/fonts/$file');
    yield LicenseEntryWithLineBreaks([font], text);
  }
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
      // Unexpected errors say so from any page (installErrorHandlers).
      scaffoldMessengerKey: appMessengerKey,
      // The places (Home, Library, Day) are drawn around every page.
      navigatorKey: appNavigatorKey,
      navigatorObservers: [appNavigation.observer],
      // Every speed label and channel name follows the settings at once. Dates
      // formatted without a context follow the app's language.
      builder: (context, child) {
        useFormattingLocale(Localizations.localeOf(context));
        return SpeedUnitScope(
          child: ChannelNamesScope(
            child: AppFrame(
              navigation: appNavigation,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      // The name is the same in every language.
      title: 'FlappedEar Telemetry',
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: locale,
      supportedLocales: supportedLocales,
      localeListResolutionCallback: (preferred, _) =>
          resolveAppLocale(preferred),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: FetTheme.dark(),
      home: home,
    );
  }
}
