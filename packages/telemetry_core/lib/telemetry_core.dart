/// Recording model, VBO parser and lap timing for FlappedEar Telemetry.
library;

export 'src/geometry.dart'
    show
        CoordinateAxis,
        CoordinateUnit,
        GeoCoordinate,
        MetricPoint,
        isValidCoordinate,
        normalizeCoordinateDegrees,
        projectCoordinate;
export 'src/intake/folder_scan.dart';
export 'src/intake/import_plan.dart';
export 'src/intake/recording_source.dart';
export 'src/laps/lap_detection.dart' show deriveSourceLapSession, detectLaps;
export 'src/laps/lap_ranking.dart' show eligibleLapIndices, rankLaps, recomputeLapRanking;
export 'src/laps/lap_session.dart';
export 'src/laps/lap_time_format.dart';
export 'src/operation.dart';
export 'src/rcz/rcz_archive.dart' show RczFormatError;
export 'src/rcz/rcz_parser.dart' show RczParser, rczAccelerationNote;
export 'src/telemetry_session.dart'
    show InterpolationMode, TelemetryChannel, TelemetrySession, telemetryGapThreshold;
export 'src/timing_gate.dart';
export 'src/vbo/vbo_file.dart';
export 'src/vbo/vbo_limits.dart';
export 'src/vbo/vbo_parser.dart' show VboParseError, VboParser;
