/// Size limits for untrusted VBO input. Each is checked before the data it
/// guards is allocated. Values match FlappedEar Overlays (handover, "VBO").
abstract final class VboLimits {
  static const int maximumFileBytes = 128 * 1024 * 1024;
  static const int maximumLines = 1000000;
  static const int maximumDataRows = 500000;
  static const int maximumColumns = 512;
  static const int maximumLineCharacters = 1048576;
  static const int maximumFieldCharacters = 65536;
  static const int maximumSectionNameCharacters = 256;
  static const int maximumMetadataEntries = 10000;
  static const int maximumMetadataCharacters = 1048576;

  /// Rows × columns.
  static const int maximumDecodedValues = 40000000;
  static const int maximumWarnings = 200;
  static const int maximumTimingGates = 128;
  static const int maximumGateDescriptionCharacters = 4096;
}
