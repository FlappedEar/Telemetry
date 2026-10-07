import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  test('a spread falls in the band whose upper edge it does not pass', () {
    expect(segmentSpreadBand(0), 0);
    expect(segmentSpreadBand(0.10), 0);
    expect(segmentSpreadBand(0.1001), 1);
    expect(segmentSpreadBand(0.25), 1);
    expect(segmentSpreadBand(0.26), 2);
    expect(segmentSpreadBand(0.50), 2);
    expect(segmentSpreadBand(0.99), 3);
    expect(segmentSpreadBand(1.00), 3);
    expect(segmentSpreadBand(1.66), segmentSpreadBandsSeconds.length);
  });
}
