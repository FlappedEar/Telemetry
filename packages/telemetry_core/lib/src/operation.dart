/// Cooperative cancellation and resource-limit errors shared by every parser
/// and analysis step.
library;

/// Returns true when the caller wants the running operation to stop.
typedef CancellationCheck = bool Function();

/// Thrown when a [CancellationCheck] asks a running operation to stop.
final class OperationCancelled implements Exception {
  const OperationCancelled([this.message = 'Source operation cancelled.']);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when untrusted input exceeds a supported size before it is decoded.
final class ResourceLimitError implements Exception {
  const ResourceLimitError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Throws [OperationCancelled] when [cancelled] reports cancellation.
void throwIfCancelled(CancellationCheck? cancelled) {
  if (cancelled != null && cancelled()) throw const OperationCancelled();
}
