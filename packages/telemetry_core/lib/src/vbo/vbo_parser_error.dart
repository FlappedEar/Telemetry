/// A VBO file that cannot be read as a recording.
final class VboParseError implements Exception {
  const VboParseError(this.message);

  final String message;

  @override
  String toString() => message;
}
