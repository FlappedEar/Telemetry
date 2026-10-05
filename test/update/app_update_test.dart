import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/update/app_update.dart';

Map<String, Object?> release(
  String tag, {
  bool draft = false,
  bool prerelease = true,
  List<Map<String, Object?>> assets = const [],
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'html_url': 'https://github.com/FlappedEar/Telemetry/releases/tag/$tag',
  'published_at': '2026-10-05T07:30:00Z',
  'assets': assets,
};

Map<String, Object?> asset(String name, {int size = 10}) => {
  'name': name,
  'size': size,
  'browser_download_url':
      'https://github.com/FlappedEar/Telemetry/releases/download/v0.2.6/$name',
};

void main() {
  group('versions', () {
    test('read plain versions and tags only', () {
      expect(AppVersion.tryParse('0.2.5'), const AppVersion(0, 2, 5));
      expect(AppVersion.tryParse('v1.10.0'), const AppVersion(1, 10, 0));
      expect(AppVersion.tryParse('0.2.5+6'), isNull);
      expect(AppVersion.tryParse('v0.3.0-beta'), isNull);
      expect(AppVersion.tryParse(''), isNull);
    });

    test('compare by number, not text', () {
      expect(const AppVersion(0, 10, 0) > const AppVersion(0, 9, 9), isTrue);
      expect(const AppVersion(1, 0, 0) > const AppVersion(0, 99, 99), isTrue);
      expect(const AppVersion(0, 2, 5) > const AppVersion(0, 2, 5), isFalse);
    });
  });

  group('newest release', () {
    test('is the highest version, pre-releases included, drafts not', () {
      final newest = newestRelease([
        release('v0.2.4'),
        release('v0.3.0', draft: true),
        release('v0.2.10', assets: [asset('SHA256SUMS.txt')]),
        release('nightly'),
        release('v0.2.9'),
      ]);
      expect(newest?.version, const AppVersion(0, 2, 10));
      expect(newest?.checksums?.name, 'SHA256SUMS.txt');
      expect(newest?.page.host, 'github.com');
    });

    test('is null for an empty or malformed answer', () {
      expect(newestRelease(const []), isNull);
      expect(newestRelease({'message': 'Not Found'}), isNull);
      expect(newestRelease([42, 'x', null]), isNull);
    });

    test('keeps only HTTPS assets', () {
      final newest = newestRelease([
        release(
          'v0.2.6',
          assets: [
            {'name': 'a', 'size': 1, 'browser_download_url': 'http://x/a'},
            {'name': 'b', 'size': -1, 'browser_download_url': 'https://x/b'},
            asset('FlappedEar-Telemetry-0.2.6-android.apk'),
          ],
        ),
      ]);
      expect(newest!.assets.map((a) => a.name), [
        'FlappedEar-Telemetry-0.2.6-android.apk',
      ]);
    });

    test('offers the APK on Android and the zip on a Mac only', () {
      final newest = newestRelease([
        release(
          'v0.2.6',
          assets: [
            asset('FlappedEar-Telemetry-0.2.6-android.apk'),
            asset('FlappedEar-Telemetry-0.2.6-macos.zip'),
            asset('SHA256SUMS.txt'),
          ],
        ),
      ])!;
      expect(
        newest.assetFor(TargetPlatform.android)?.name,
        'FlappedEar-Telemetry-0.2.6-android.apk',
      );
      expect(
        newest.assetFor(TargetPlatform.macOS)?.name,
        'FlappedEar-Telemetry-0.2.6-macos.zip',
      );
      expect(newest.assetFor(TargetPlatform.iOS), isNull);
      expect(newest.assetFor(TargetPlatform.windows), isNull);
      expect(newest.assetFor(TargetPlatform.linux), isNull);
    });
  });

  test('an update is offered only for a newer version', () {
    final newest = newestRelease([release('v0.2.6')]);
    expect(UpdateCheck(const AppVersion(0, 2, 5), newest).available, newest);
    expect(UpdateCheck(const AppVersion(0, 2, 6), newest).available, isNull);
    expect(UpdateCheck(const AppVersion(0, 3, 0), newest).available, isNull);
    expect(UpdateCheck(null, newest).available, isNull);
  });

  test('checksums are read in shasum format', () {
    final sums =
        '${'a' * 64}  FlappedEar-Telemetry-0.2.6-android.apk\n'
        '${'B' * 64} *FlappedEar-Telemetry-0.2.6-macos.zip\r\n'
        'garbage line\n';
    expect(
      checksumFor(sums, 'FlappedEar-Telemetry-0.2.6-android.apk'),
      'a' * 64,
    );
    expect(checksumFor(sums, 'FlappedEar-Telemetry-0.2.6-macos.zip'), 'b' * 64);
    expect(checksumFor(sums, 'FlappedEar-Telemetry-0.2.6'), isNull);
  });

  test('the check on launch runs at most once a day', () {
    final now = DateTime.utc(2026, 10, 5, 12);
    expect(updateCheckDue(null, now), isTrue);
    expect(updateCheckDue(now.subtract(const Duration(hours: 23)), now), false);
    expect(updateCheckDue(now.subtract(const Duration(hours: 24)), now), true);
    expect(updateCheckDue(now.add(const Duration(hours: 1)), now), isTrue);
  });

  group('checker', () {
    final apk = utf8.encode('the new app');
    final apkSum = sha256.convert(apk).toString();
    final answer = jsonEncode([
      release(
        'v0.2.6',
        assets: [
          asset('FlappedEar-Telemetry-0.2.6-android.apk', size: apk.length),
          asset('SHA256SUMS.txt'),
        ],
      ),
    ]);

    test('reads the releases and finds the newer one', () async {
      final asked = <Uri>[];
      final checker = UpdateChecker(
        fetch: (uri, _) async {
          asked.add(uri);
          return answer;
        },
      );
      final check = await checker.check(const AppVersion(0, 2, 5));
      expect(asked.single, releasesApi);
      expect(check.available?.version, const AppVersion(0, 2, 6));
    });

    test('a malformed answer is a failure, not "up to date"', () async {
      final checker = UpdateChecker(fetch: (_, _) async => '{"x": 1}');
      await expectLater(
        checker.check(const AppVersion(0, 2, 5)),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.unexpected,
          ),
        ),
      );
    });

    test('downloads only with the release checksum of that file', () async {
      final newest = newestRelease(jsonDecode(answer))!;
      final file = File('unused');
      String? passed;
      final checker = UpdateChecker(
        fetch: (uri, _) async =>
            '$apkSum  FlappedEar-Telemetry-0.2.6-android.apk\n',
        download: (asset, file, sha, progress) async => passed = sha,
      );
      await checker.download(
        newest,
        newest.assetFor(TargetPlatform.android)!,
        file,
        (_) {},
      );
      expect(passed, apkSum);

      final unlisted = UpdateChecker(
        fetch: (uri, _) async => '$apkSum  something-else.apk\n',
        download: (asset, file, sha, progress) async => fail('downloaded'),
      );
      await expectLater(
        unlisted.download(
          newest,
          newest.assetFor(TargetPlatform.android)!,
          file,
          (_) {},
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.notVerifiable,
          ),
        ),
      );
    });
  });

  group('over HTTP', () {
    late HttpServer server;
    late Directory folder;
    final body = utf8.encode('APK bytes ' * 1000);

    setUp(() async {
      folder = Directory.systemTemp.createTempSync('fet_update_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        switch (request.uri.path) {
          case '/limited':
            request.response
              ..statusCode = HttpStatus.forbidden
              ..headers.set('x-ratelimit-remaining', '0');
          case '/missing':
            request.response.statusCode = HttpStatus.notFound;
          case '/apk':
            request.response.add(body);
          case '/releases':
            request.response.write('[]');
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      folder.deleteSync(recursive: true);
    });

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    ReleaseAsset apkAsset({int? size}) =>
        ReleaseAsset(name: 'x.apk', url: at('/apk'), size: size ?? body.length);

    Matcher failsWith(UpdateFailure failure) => throwsA(
      isA<UpdateException>().having((e) => e.failure, 'failure', failure),
    );

    test('reads text and tells the rate limit apart', () async {
      expect(await fetchUpdateText(at('/releases'), 100), '[]');
      await expectLater(
        fetchUpdateText(at('/limited'), 100),
        failsWith(UpdateFailure.rateLimited),
      );
      await expectLater(
        fetchUpdateText(at('/missing'), 100),
        failsWith(UpdateFailure.unexpected),
      );
    });

    test('no connection is "offline"', () async {
      final closed = at('/releases');
      await server.close(force: true);
      await expectLater(
        fetchUpdateText(closed, 100),
        failsWith(UpdateFailure.offline),
      );
    });

    test('keeps a download whose SHA-256 and size match', () async {
      final file = File(p.join(folder.path, 'x.apk'));
      final shares = <double>[];
      await downloadVerified(
        apkAsset(),
        file,
        sha256.convert(body).toString(),
        shares.add,
      );
      expect(file.readAsBytesSync(), body);
      expect(shares.last, 1.0);
      expect(File('${file.path}.part').existsSync(), isFalse);
    });

    test('deletes a download that does not match', () async {
      final file = File(p.join(folder.path, 'x.apk'));
      await expectLater(
        downloadVerified(apkAsset(), file, '0' * 64, (_) {}),
        failsWith(UpdateFailure.checksumMismatch),
      );
      await expectLater(
        downloadVerified(
          apkAsset(size: body.length - 1),
          file,
          sha256.convert(body).toString(),
          (_) {},
        ),
        failsWith(UpdateFailure.checksumMismatch),
      );
      expect(folder.listSync(), isEmpty);
    });

    test('a download cut off midway leaves no file', () async {
      // A server that promises the whole file and hangs up after 100 bytes.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      raw.listen((socket) async {
        await socket.first;
        socket
          ..write('HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n\r\n')
          ..add(body.sublist(0, 100));
        await socket.flush();
        socket.destroy();
      });
      final file = File(p.join(folder.path, 'x.apk'));
      await expectLater(
        downloadVerified(
          ReleaseAsset(
            name: 'x.apk',
            url: Uri.parse('http://127.0.0.1:${raw.port}/apk'),
            size: body.length,
          ),
          file,
          sha256.convert(body).toString(),
          (_) {},
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(folder.listSync(), isEmpty);
    });
  });
}
