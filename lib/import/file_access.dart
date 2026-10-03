import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the app allowed to read the recordings and folders the user chose,
/// after the app quits. Replaced by a fake in widget tests.
abstract interface class FileAccess {
  /// Remembers [paths] (files or folders) the user just picked, dropped or
  /// shared, while the app may still read them.
  Future<void> remember(List<String> paths);

  /// Reads again what was remembered before, for example before a saved day
  /// opens its recordings.
  Future<void> restore();
}

/// On macOS the sandbox lets the app read a picked or dropped file only
/// until it quits, so a saved day could not read its recordings after a
/// restart ("Cannot read telemetry source") although they had not moved. The
/// macOS host keeps a security-scoped bookmark of each (see
/// `FileAccess` in `macos/Runner/MainFlutterWindow.swift`) and starts accessing them again on
/// [restore]. Other platforms need nothing: their pickers copy the files into
/// the app's storage, or have no sandbox.
final class PlatformFileAccess implements FileAccess {
  const PlatformFileAccess();

  static const channelName = 'com.flappedear.telemetry/file_access';
  static const _channel = MethodChannel(channelName);

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<void> remember(List<String> paths) =>
      _call('remember', [for (final path in paths) path]);

  @override
  Future<void> restore() => _call('restore');

  static Future<void> _call(String method, [Object? arguments]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('File access ($method) failed: ${error.message}');
    } on MissingPluginException {
      // A host without the channel, such as a test or an older build.
    }
  }
}
