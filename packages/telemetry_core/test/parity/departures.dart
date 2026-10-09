// Recordings Overlays reads and Telemetry deliberately refuses, and why.
// Each has truth tests of its own; the Overlays ticket ports the change.

/// VBOs with no time column: Overlays times their rows one second apart;
/// Telemetry refuses them, since a made-up clock gives believable but wrong
/// times (FET-203, KAN-226; test/vbo_time_column_test.dart).
const vboRefusedByTelemetry = {
  'no_time_column.vbo': 'FET-203',
  'error_empty_column_names.vbo': 'FET-203',
};

/// Whether [path] names a recording in [vboRefusedByTelemetry].
bool refusedByTelemetry(String path) => vboRefusedByTelemetry.containsKey(path.split('/').last);

/// Departures no corpus file reaches, so every parity case still compares;
/// listed so they are not lost. Each has truth tests of its own.
const readingDepartures = {
  // A backward time of day is a midnight rollover when it implies a gap of
  // at most 3 h, confirmed by the next clock row; Overlays needs 23:00 to
  // 01:00 (FET-211, KAN-233; test/vbo_parser_test.dart).
  'midnight rollover': 'FET-211',
};

const lapDepartures = {
  // Pass detection and lap validation share one GPS gap rule, the smaller
  // of the latitude's and longitude's; Overlays detects passes with the
  // larger (FET-212, KAN-234; test/lap_detection_test.dart).
  'GPS gap rule': 'FET-212',
};

/// A unit Telemetry reads from the VBO's `[header]` line where Overlays
/// reports the parsed channel's own unit, empty for a VBO (FET-288): a
/// recording that declares `velocity kmh` has a speed in "km/h" here, however
/// the session reaches the analysis. [overlays] is the reference's unit and
/// [telemetry] ours; the reference counts as met only for that case.
Object? unitAsTelemetryReadsIt(Object? overlays, Object? telemetry) =>
    overlays == '' && telemetry == 'km/h' ? telemetry : overlays;
