import 'package:flutter/material.dart';

import 'import/day_import_page.dart';
import 'ui/theme.dart';

void main() {
  runApp(const TelemetryApp());
}

class TelemetryApp extends StatelessWidget {
  const TelemetryApp({super.key, this.home = const DayImportPage()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlappedEar Telemetry',
      theme: FetTheme.dark(),
      home: home,
    );
  }
}
