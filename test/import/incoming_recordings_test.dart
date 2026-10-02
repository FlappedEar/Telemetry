import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/import/incoming_recordings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('held and later shared recordings both arrive', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel(PlatformIncomingRecordings.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      // The app was started by a share: the host held this file.
      return call.method == 'ready' ? ['/inbox/held.vbo'] : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final batches = <List<String>>[];
    final subscription = PlatformIncomingRecordings.instance.received.listen(
      batches.add,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(calls, ['ready']);
    expect(batches, [
      ['/inbox/held.vbo'],
    ]);

    // A share while the app runs; empty and non-string entries are ignored.
    await messenger.handlePlatformMessage(
      PlatformIncomingRecordings.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('received', ['/inbox/a.vbo', '', 3, '/inbox/b.rcz']),
      ),
      (_) {},
    );
    await pumpEventQueue();
    expect(batches.last, ['/inbox/a.vbo', '/inbox/b.rcz']);
  });
}
