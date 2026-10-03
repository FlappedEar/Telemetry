import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/ui/headline_bar.dart';

void main() {
  Widget bar(double width, {double textScale = 1}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const HeadlineBar(
              key: ValueKey('bar'),
              label: 'Best day',
              title: 'Session 5 · LAP 2',
              time: '1:49.898',
              color: Color(0xFFFCB203),
              onColor: Color(0xFF111214),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('the time sits flush right in a wide bar', (tester) async {
    await tester.pumpWidget(bar(700));
    final barRight = tester.getTopRight(find.byKey(const ValueKey('bar'))).dx;
    final timeRight = tester.getTopRight(find.text('1:49.898')).dx;
    expect(timeRight, moreOrLessEquals(barRight - 14, epsilon: 0.5));
  });

  testWidgets('with large text on a narrow bar the time stays in half the '
      'bar, flush right', (tester) async {
    await tester.pumpWidget(bar(320, textScale: 2));
    expect(tester.takeException(), isNull);
    final barBox = tester.getRect(find.byKey(const ValueKey('bar')));
    final time = tester.getRect(find.byType(FittedBox));
    expect(time.width, lessThanOrEqualTo((barBox.width - 28) / 2 + 0.5));
    expect(time.right, moreOrLessEquals(barBox.right - 14, epsilon: 0.5));
  });
}
