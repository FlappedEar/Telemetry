import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'import/day_import_page.dart';
import 'ui/theme.dart';
import 'units.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSettings();
  LicenseRegistry.addLicense(_fontLicenses);
  runApp(const TelemetryApp());
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
  const TelemetryApp({super.key, this.home = const DayImportPage()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Every speed label follows the setting at once.
      builder: (context, child) =>
          SpeedUnitScope(child: child ?? const SizedBox.shrink()),
      title: 'FlappedEar Telemetry',
      theme: FetTheme.dark(),
      home: home,
    );
  }
}
