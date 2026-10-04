// revealSettled (lib/day/reveal.dart): the Next session card is scrolled to
// the top, again once the scroll ends when something above it moved, and
// never back after the person took the scroll over.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/reveal.dart';

void main() {
  final above = ValueNotifier<double>(100);
  final target = GlobalKey();
  final controller = ScrollController();

  Future<void> build(WidgetTester tester) async {
    above.value = 100;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: above,
                  builder: (context, height, _) => SizedBox(height: height),
                ),
                for (var i = 0; i < 20; ++i) const SizedBox(height: 200),
                SizedBox(key: target, height: 300),
                for (var i = 0; i < 20; ++i) const SizedBox(height: 200),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double top(WidgetTester tester) => tester.getTopLeft(find.byKey(target)).dy;

  Future<void> start(WidgetTester tester) async {
    revealSettled(target.currentContext!, current: () => target.currentContext);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('something above moving while it scrolls is made up for', (
    tester,
  ) async {
    await build(tester);
    await start(tester);
    above.value = 106;
    await tester.pumpAndSettle();
    expect(top(tester), closeTo(0, 0.5));
  });

  testWidgets('a drag taking over the scroll is not undone', (tester) async {
    await build(tester);
    await start(tester);
    final before = controller.offset;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    final left = controller.offset;
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(left, 0.5));
    expect(left, lessThan(before - 300));
    expect(top(tester), greaterThan(100));
  });

  testWidgets('a wheel taking over the scroll is not undone', (tester) async {
    await build(tester);
    await start(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(SingleChildScrollView)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -600)));
    await tester.pump();
    final left = controller.offset;
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(left, 0.5));
    expect(top(tester), greaterThan(100));
  });

  testWidgets('a scroll moved elsewhere during the reveal is left there', (
    tester,
  ) async {
    await build(tester);
    await start(tester);
    controller.jumpTo(500);
    above.value = 106;
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(500, 0.5));
  });

  testWidgets('a drag after the reveal is not undone', (tester) async {
    await build(tester);
    await start(tester);
    await tester.pumpAndSettle();
    expect(top(tester), closeTo(0, 0.5));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(top(tester), greaterThan(100));
  });
}
