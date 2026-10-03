import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// Keeps the unsaved day so a crash or a closed app loses nothing. Replaced
/// by a fake in widget tests.
abstract interface class RecoveryStore {
  /// The recovery file; null when there is nowhere to keep it.
  Future<String?> path();

  /// The unsaved day kept, or null when there is none or it cannot be read.
  Future<DayRecovery?> load();
  Future<void> write(DayRecovery recovery);
  Future<void> clear();
}

/// `day-recovery.json` in the app's support folder. Off in `flutter test`.
final class PlatformRecoveryStore implements RecoveryStore {
  const PlatformRecoveryStore();

  static bool get _enabled =>
      !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Future<String?> path() async {
    if (!_enabled) return null;
    try {
      return p.join(
        (await getApplicationSupportDirectory()).path,
        'day-recovery.json',
      );
    } on Exception {
      return null;
    }
  }

  @override
  Future<DayRecovery?> load() async {
    final file = await path();
    if (file == null) return null;
    try {
      return readDayRecovery(file);
    } on FetprojectError catch (error) {
      debugPrint('Recovery snapshot ignored: $error');
      return null;
    }
  }

  @override
  Future<void> write(DayRecovery recovery) async {
    final file = await path();
    if (file != null) await writeDayRecovery(file, recovery);
  }

  @override
  Future<void> clear() async {
    final file = await path();
    if (file != null) await clearDayRecovery(file);
  }
}

Future<void> _queue = Future.value();
int _queued = 0;

/// Runs [operation] after every recovery operation queued before it, so a
/// write and a later clear or load always happen in that order. With none
/// waiting it starts at once, never waiting on an earlier, finished one.
Future<T> queueRecovery<T>(Future<T> Function() operation) {
  final result = _queued == 0
      ? Future.sync(operation)
      : _queue.then((_) => operation());
  ++_queued;
  _queue = result
      .then((_) {}, onError: (Object _) {})
      .whenComplete(() => --_queued);
  return result;
}
