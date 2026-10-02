import 'package:flutter/material.dart';

import 'import/day_import_page.dart';

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
