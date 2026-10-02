import 'geometry.dart';

/// What a timing line in a recording is for.
enum TimingGateType { start, split, unknown }

/// A timing line between two endpoints, as declared by the recording.
final class TimingGate {
  const TimingGate({
    required this.type,
    required this.sourceName,
    required this.endpointA,
    required this.endpointB,
    this.sourceDescription = '',
  });

  final TimingGateType type;
  final String sourceName;
  final GeoCoordinate endpointA;
  final GeoCoordinate endpointB;
  final String sourceDescription;
}
