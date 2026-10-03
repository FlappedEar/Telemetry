import 'package:flutter/material.dart';

import 'import/day_import_page.dart';
import 'ui/theme.dart';
import 'units.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSettings();
  runApp(const TelemetryApp());
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
