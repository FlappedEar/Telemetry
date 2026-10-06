// The open day's context (FET-209): built whole by its day, replaced or
// cleared only by the day that published it.
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_context.dart';

void main() {
  tearDown(() => debugSetOpenDayContext(DayContext.none));

  test('only the day that published the context replaces or clears it', () {
    final first = DayContextOwner();
    final second = DayContextOwner();
    const a = DayContext(speedUnits: ['km/h']);
    const b = DayContext(speedUnits: ['mph']);
    first.open(a);
    expect(openDayContext, same(a));
    second.open(b);
    expect(openDayContext, same(b));
    // The first day changing or closing leaves the second's.
    first.update(const DayContext(speedUnits: ['m/s']));
    expect(openDayContext, same(b));
    first.close();
    expect(openDayContext, same(b));
    const c = DayContext(speedUnits: ['mph', 'mph']);
    second.update(c);
    expect(openDayContext, same(c));
    second.close();
    expect(openDayContext, same(DayContext.none));
    // A closed day publishes nothing more.
    second.update(a);
    expect(openDayContext, same(DayContext.none));
  });

  test('a day that never opened changes nothing', () {
    const a = DayContext(recordedChannels: ['rpm']);
    DayContextOwner().open(a);
    final idle = DayContextOwner()
      ..update(DayContext.none)
      ..close();
    expect(idle, isNotNull);
    expect(openDayContext, same(a));
  });

  test('a context cannot be changed once built', () {
    final context = DayContext.of(const [], channelSources: {'rpm': 'RCZ'});
    expect(context.recordedChannels, ['rpm']);
    expect(() => context.channelSources['x'] = 'RCZ', throwsUnsupportedError);
    expect(() => context.recordedChannels.add('x'), throwsUnsupportedError);
    expect(() => context.speedUnits.add('x'), throwsUnsupportedError);
    expect(
      () => context.channelSpeedUnits['speed'] = const [],
      throwsUnsupportedError,
    );
  });
}
