import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Recordings that another app sends to this one, such as a VBO or RCZ export
/// shared from RaceChrono. Replaced by a fake in widget tests.
abstract interface class IncomingRecordings {
  /// Each event is one batch of readable file paths, in the order received.
  Stream<List<String>> get received;
}

/// Receives shared files from the iOS and Android hosts.
///
/// The host copies each shared file into the app's own storage and sends the
/// copies' paths on [channelName]. Files that arrive before Flutter listens
/// (the app was started by the share) are held by the host until the first
/// listener asks for them with `ready`.
final class PlatformIncomingRecordings implements IncomingRecordings {
  PlatformIncomingRecordings._();

  static final PlatformIncomingRecordings instance =
      PlatformIncomingRecordings._();

  static const channelName = 'com.flappedear.telemetry/incoming_recordings';
  static const _channel = MethodChannel(channelName);

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  late final StreamController<List<String>> _controller =
      StreamController.broadcast(onListen: _connect);
  bool _connected = false;

  @override
  Stream<List<String>> get received =>
      _supported ? _controller.stream : const Stream.empty();

  Future<void> _connect() async {
    if (_connected) return;
    _connected = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'received') _deliver(call.arguments);
    });
    try {
      _deliver(await _channel.invokeMethod<Object?>('ready'));
    } on PlatformException catch (error) {
      debugPrint('Shared recordings are unavailable: ${error.message}');
    } on MissingPluginException {
      // A host without the channel, such as a test or an older build.
    }
  }

  void _deliver(Object? arguments) {
    final paths = [
      if (arguments is List)
        for (final path in arguments)
          if (path is String && path.isNotEmpty) path,
    ];
    if (paths.isNotEmpty) _controller.add(paths);
  }
}
