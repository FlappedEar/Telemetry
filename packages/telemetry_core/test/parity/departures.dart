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
