import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:telemetry/main.dart' as app;

// Runs on a real iOS simulator and Android emulator in CI: the app starts on
// the device and shows its first screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A first frame that never comes fails the test with a result after three
  // minutes, instead of leaving the tool waiting until CI stops it.
  testWidgets('the app starts and shows its first screen', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'FlappedEar Telemetry');
    expect(find.byType(Scaffold), findsWidgets);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
