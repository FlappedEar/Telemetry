import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The repository whose GitHub Releases the app checks for a newer version.
const updateRepository = 'FlappedEar/Telemetry';

/// The releases page, for a platform the app cannot download an update for.
final releasesPage = Uri.https('github.com', '/$updateRepository/releases');

/// The releases the check reads, newest first; pre-releases included (every
/// release below 1.0.0 is one).
final releasesApi = Uri.https(
  'api.github.com',
  '/repos/$updateRepository/releases',
  {'per_page': '20'},
);

/// The most characters read from the releases API's answer.
const maximumReleasesCharacters = 4 * 1024 * 1024;

/// The most characters read from a release's SHA256SUMS.txt.
const maximumChecksumCharacters = 64 * 1024;

/// The largest update file downloaded.
const maximumUpdateBytes = 512 * 1024 * 1024;

/// A version as releases are tagged: three numbers, major.minor.patch.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');

  /// "0.2.5" or a tag "v0.2.5"; null for anything else, such as a build
  /// suffix or a pre-release label.
  static AppVersion? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    return AppVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  @override
  int compareTo(AppVersion other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// A file attached to a release.
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;

  /// Where the file downloads from (HTTPS).
  final Uri url;

  /// Its size in bytes, as GitHub reports it.
  final int size;
}

/// A published release on GitHub.
@immutable
class AppRelease {
  const AppRelease({
    required this.version,
    required this.page,
    required this.assets,
    this.publishedAt,
  });

  final AppVersion version;

  /// The release's page on GitHub, with its notes.
  final Uri page;

  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;

  /// The update file for [platform]: the APK on Android, the zipped app on
  /// macOS; null where the releases carry none.
  ReleaseAsset? assetFor(TargetPlatform platform) {
    final suffix = switch (platform) {
      TargetPlatform.android => '-android.apk',
      TargetPlatform.macOS => '-macos.zip',
      _ => null,
    };
    if (suffix == null) return null;
    for (final asset in assets) {
      if (asset.name.startsWith('FlappedEar-Telemetry-') &&
          asset.name.endsWith(suffix)) {
        return asset;
      }
    }
    return null;
  }

  /// The release's SHA256SUMS.txt, which every release carries.
  ReleaseAsset? get checksums {
    for (final asset in assets) {
      if (asset.name == 'SHA256SUMS.txt') return asset;
    }
    return null;
  }
}

/// The newest published release in the releases API's answer [json]:
/// drafts and tags that are not a plain version are left out. Null when
/// there is none.
AppRelease? newestRelease(Object? json) {
  if (json is! List) return null;
  AppRelease? newest;
  for (final entry in json) {
    if (entry is! Map || entry['draft'] == true) continue;
    final tag = entry['tag_name'];
    final version = tag is String ? AppVersion.tryParse(tag) : null;
    final page = _httpsUri(entry['html_url']);
    if (version == null || page == null) continue;
    if (newest != null && !(version > newest.version)) continue;
    final assets = <ReleaseAsset>[];
    final listed = entry['assets'];
    if (listed is List) {
      for (final asset in listed) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = _httpsUri(asset['browser_download_url']);
        final size = asset['size'];
        if (name is String && url != null && size is int && size >= 0) {
          assets.add(ReleaseAsset(name: name, url: url, size: size));
        }
      }
    }
    final published = entry['published_at'];
    newest = AppRelease(
      version: version,
      page: page,
      assets: List.unmodifiable(assets),
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }
  return newest;
}

Uri? _httpsUri(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  return uri != null && uri.isScheme('https') && uri.host.isNotEmpty
      ? uri
      : null;
}

/// The SHA-256 (lower-case hex) that SHA256SUMS.txt [text] lists for
/// [name], in `shasum -a 256` format ("hash  name" or "hash *name"); null
/// when the file does not list it.
String? checksumFor(String text, String name) {
  final line = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$');
  for (final raw in const LineSplitter().convert(text)) {
    final match = line.firstMatch(raw.trimRight());
    if (match != null && match[2] == name) return match[1]!.toLowerCase();
  }
  return null;
}

/// Why a check or a download did not work.
enum UpdateFailure {
  /// No connection, or the server did not answer in time.
  offline,

  /// GitHub limits how often a device may ask (60 times an hour).
  rateLimited,

  /// Any other answer the app could not use.
  unexpected,

  /// The release has no checksum for the file, so it was not kept.
  notVerifiable,

  /// The file differs from the release's checksum or size.
  checksumMismatch,

  /// The file could not be written.
  notSaved,
}

/// An [UpdateFailure] as an exception.
class UpdateException implements Exception {
  const UpdateException(this.failure, [this.detail]);

  final UpdateFailure failure;
  final String? detail;

  @override
  String toString() =>
      'UpdateException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// What a check found.
@immutable
class UpdateCheck {
  const UpdateCheck(this.installed, this.newest);

  /// The running app's version; null when it could not be read.
  final AppVersion? installed;

  /// The newest release; null when there is none.
  final AppRelease? newest;

  /// The newest release when it is newer than the running app.
  AppRelease? get available {
    final release = newest;
    final own = installed;
    if (release == null || own == null) return null;
    return release.version > own ? release : null;
  }
}

/// GETs [uri] and returns its body as text of at most [maximumCharacters];
/// throws [UpdateException].
typedef UpdateTextFetcher = Future<String> Function(
  Uri uri,
  int maximumCharacters,
);

/// Downloads [asset] into [file], checking its size and SHA-256 against
/// [sha256]; [progress] gets the share done (0 to 1). Throws
/// [UpdateException].
typedef UpdateDownloader = Future<void> Function(
  ReleaseAsset asset,
  File file,
  String sha256,
  void Function(double progress) progress,
);

/// Reads releases over HTTPS; off in `flutter test`, where tests set their
/// own.
UpdateTextFetcher? defaultUpdateFetcher =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? null
    : fetchUpdateText;

/// Downloads updates over HTTPS; off in `flutter test`.
UpdateDownloader? defaultUpdateDownloader =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? null
    : downloadVerified;

HttpClient _client() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..userAgent = 'FlappedEar-Telemetry';

UpdateException _failureOf(Object error) => switch (error) {
  UpdateException() => error,
  SocketException() ||
  TimeoutException() ||
  HandshakeException() ||
  HttpException() => UpdateException(UpdateFailure.offline, '$error'),
  _ => UpdateException(UpdateFailure.unexpected, '$error'),
};

/// Asks GitHub without signing in (no token in the app). A 403 or 429 with
/// no requests left is [UpdateFailure.rateLimited].
Future<String> fetchUpdateText(Uri uri, int maximumCharacters) async {
  final client = _client();
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    if (uri.host == 'api.github.com') {
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set('X-GitHub-Api-Version', '2022-11-28');
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode == HttpStatus.tooManyRequests ||
        (response.statusCode == HttpStatus.forbidden &&
            response.headers.value('x-ratelimit-remaining') == '0')) {
      await response.drain<void>();
      throw const UpdateException(UpdateFailure.rateLimited);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw UpdateException(
        UpdateFailure.unexpected,
        'GitHub answered ${response.statusCode}.',
      );
    }
    final text = StringBuffer();
    await for (final chunk
        in response
            .transform(utf8.decoder)
            .timeout(const Duration(seconds: 30))) {
      if (text.length + chunk.length > maximumCharacters) {
        throw const UpdateException(
          UpdateFailure.unexpected,
          'The answer is too long.',
        );
      }
      text.write(chunk);
    }
    return text.toString();
  } on Object catch (error) {
    throw _failureOf(error);
  } finally {
    client.close(force: true);
  }
}

/// Streams [asset] into a temporary file next to [file], hashing it on the
/// way, and moves it over [file] only when its size and SHA-256 match; a
/// file that does not match is deleted.
Future<void> downloadVerified(
  ReleaseAsset asset,
  File file,
  String sha256Hex,
  void Function(double progress) progress,
) async {
  if (asset.size <= 0 || asset.size > maximumUpdateBytes) {
    throw const UpdateException(UpdateFailure.unexpected, 'Unexpected size.');
  }
  final client = _client();
  final partial = File('${file.path}.part');
  IOSink? sink;
  try {
    final request = await client
        .getUrl(asset.url)
        .timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw UpdateException(
        UpdateFailure.unexpected,
        'The download answered ${response.statusCode}.',
      );
    }
    try {
      await file.parent.create(recursive: true);
      sink = partial.openWrite();
    } on FileSystemException catch (error) {
      throw UpdateException(UpdateFailure.notSaved, '$error');
    }
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var received = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      received += chunk.length;
      if (received > asset.size) {
        throw const UpdateException(UpdateFailure.checksumMismatch);
      }
      hasher.add(chunk);
      sink.add(chunk);
      progress(received / asset.size);
    }
    hasher.close();
    await sink.flush();
    await sink.close();
    sink = null;
    if (received != asset.size || digest.value.toString() != sha256Hex) {
      throw const UpdateException(UpdateFailure.checksumMismatch);
    }
    try {
      await partial.rename(file.path);
    } on FileSystemException catch (error) {
      throw UpdateException(UpdateFailure.notSaved, '$error');
    }
  } on Object catch (error) {
    try {
      await sink?.close();
    } on Object {
      // The sink is already broken; the partial file goes below.
    }
    try {
      if (partial.existsSync()) partial.deleteSync();
    } on FileSystemException {
      // Left in the app's temporary folder, which the next download empties.
    }
    throw _failureOf(error);
  } finally {
    client.close(force: true);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Checks GitHub Releases for a version newer than [installed].
class UpdateChecker {
  UpdateChecker({UpdateTextFetcher? fetch, UpdateDownloader? download})
    : _fetch = fetch ?? defaultUpdateFetcher,
      _download = download ?? defaultUpdateDownloader;

  /// A checker that never reaches GitHub, such as in integration tests.
  UpdateChecker.off() : _fetch = null, _download = null;

  final UpdateTextFetcher? _fetch;
  final UpdateDownloader? _download;

  /// Whether this checker can reach GitHub (not in widget tests).
  bool get enabled => _fetch != null;

  /// The newest release compared with [installed]. Throws [UpdateException].
  Future<UpdateCheck> check(AppVersion? installed) async {
    final fetch = _fetch;
    if (fetch == null) {
      throw const UpdateException(UpdateFailure.offline, 'Checks are off.');
    }
    final text = await fetch(releasesApi, maximumReleasesCharacters);
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      throw UpdateException(UpdateFailure.unexpected, '$error');
    }
    if (json is! List) {
      throw const UpdateException(
        UpdateFailure.unexpected,
        'The answer is not a list of releases.',
      );
    }
    return UpdateCheck(installed, newestRelease(json));
  }

  /// Downloads [asset] of [release] into [file] and keeps it only when it
  /// matches the release's SHA256SUMS.txt. Throws [UpdateException].
  Future<void> download(
    AppRelease release,
    ReleaseAsset asset,
    File file,
    void Function(double progress) progress,
  ) async {
    final fetch = _fetch;
    final download = _download;
    if (fetch == null || download == null) {
      throw const UpdateException(UpdateFailure.offline, 'Downloads are off.');
    }
    final sums = release.checksums;
    if (sums == null) throw const UpdateException(UpdateFailure.notVerifiable);
    final text = await fetch(sums.url, maximumChecksumCharacters);
    final expected = checksumFor(text, asset.name);
    if (expected == null) {
      throw const UpdateException(UpdateFailure.notVerifiable);
    }
    await download(asset, file, expected, progress);
  }
}

/// Whether the automatic check on launch is due: at most once a day, and
/// again at once if the clock went back.
bool updateCheckDue(DateTime? last, DateTime now) {
  if (last == null) return true;
  final since = now.difference(last);
  return since.isNegative || since >= const Duration(days: 1);
}
