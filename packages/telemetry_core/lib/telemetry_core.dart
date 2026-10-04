/// Recording model, VBO parser and lap timing for FlappedEar Telemetry.
library;

export 'src/analysis/automatic_segments.dart';
export 'src/analysis/braking_metrics.dart';
export 'src/analysis/braking_onset.dart';
export 'src/analysis/channel_summary.dart';
export 'src/analysis/coasting_analysis.dart';
export 'src/analysis/comparison_driving.dart';
export 'src/analysis/consistency.dart';
export 'src/analysis/corner_analyzer.dart';
export 'src/analysis/corner_phases.dart';
export 'src/analysis/corner_speeds.dart';
export 'src/analysis/day_report.dart';
export 'src/analysis/driving_states.dart';
export 'src/analysis/driving_variability.dart';
export 'src/analysis/exit_metrics.dart';
export 'src/analysis/focus_areas.dart';
export 'src/analysis/gg_pairs.dart';
export 'src/analysis/lap_charts.dart';
export 'src/analysis/lap_comparison.dart';
export 'src/analysis/map_layers.dart';
export 'src/analysis/outing_results.dart';
export 'src/analysis/outing_theoretical_best.dart';
export 'src/analysis/sector_timing.dart';
export 'src/analysis/temperature_association.dart';
export 'src/analysis/theoretical_best.dart';
export 'src/analysis/time_loss.dart';
export 'src/analysis/track_progress.dart';
export 'src/analysis/track_segment_editing.dart';
export 'src/analysis/track_segment_proposals.dart';
export 'src/analysis/track_segment_review.dart';
export 'src/day/compatibility.dart';
export 'src/day/day_analysis.dart';
export 'src/day/day_channel_summaries.dart';
export 'src/day/day_coach.dart';
export 'src/day/day_comparison.dart';
export 'src/day/day_corner_analyzer.dart';
export 'src/day/day_corners.dart';
export 'src/day/day_document.dart';
export 'src/day/day_fusion.dart';
export 'src/day/run_primary.dart';
export 'src/day/day_recovery.dart';
export 'src/day/day_relink.dart';
export 'src/day/day_report.dart';
export 'src/day/day_segment_review.dart';
export 'src/day/day_segments.dart';
export 'src/day/day_theoretical_best.dart';
export 'src/day/run_metadata.dart';
export 'src/day/session_weather.dart';

export 'package:fetproject/fetproject.dart'
    show FetprojectError, InterruptedSave, completeInterruptedSave;

export 'src/day/day_laps.dart';
export 'src/day/day_progression.dart';
export 'src/day/day_ranking.dart';
export 'src/day/lap_path.dart';
export 'src/day/track_inference.dart';
export 'src/fusion/channel_fusion.dart';
export 'src/fusion/recording_alignment.dart';
export 'src/fusion/telemetry_sync_engine.dart';
export 'src/geometry.dart'
    show
        CoordinateAxis,
        CoordinateUnit,
        GeoCoordinate,
        MetricPoint,
        isValidCoordinate,
        normalizeCoordinateDegrees,
        projectCoordinate,
        unprojectCoordinate;
export 'src/intake/folder_scan.dart';
export 'src/intake/import_plan.dart';
export 'src/intake/import_review.dart';
export 'src/intake/recording_source.dart';
export 'src/laps/lap_detection.dart' show deriveSourceLapSession, detectLaps;
export 'src/laps/lap_ranking.dart' show eligibleLapIndices, rankLaps, recomputeLapRanking;
export 'src/laps/lap_session.dart';
export 'src/laps/lap_time_format.dart';
export 'src/operation.dart';
export 'src/profile/driver_profile.dart';
export 'src/profile/profile_tree.dart';
export 'src/rcz/rcz_archive.dart' show RczFormatError;
export 'src/source_fingerprint.dart';
export 'src/speed_units.dart';
export 'src/rcz/rcz_parser.dart' show RczParser, rczAccelerationNote;
export 'src/telemetry_session.dart'
    show InterpolationMode, SamplePoint, TelemetryChannel, TelemetrySession, telemetryGapThreshold;
export 'src/timing_gate.dart';
export 'src/vbo/vbo_file.dart';
export 'src/vbo/vbo_limits.dart';
export 'src/vbo/vbo_parser.dart' show VboParseError, VboParser;
