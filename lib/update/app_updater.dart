import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';

/// What the system installer did with a downloaded APK.
enum InstallResult {
  /// The system installer is open.
  started,

  /// The app may not install apps yet; the system setting that allows it is
  /// open.
  needsPermission,

  /// The installer could not be opened.
  failed,
}

/// What the updater needs from the device. Replaced by a fake in tests.
abstract interface class UpdatePlatform {
  TargetPlatform get platform;

  /// The running app's version, such as "0.2.5", and its build number.
  Future<(String version, String build)> installedVersion();

  /// A file named [name] in the app's own temporary updates folder; the
  /// folder's older downloads are removed.
  Future<File> temporaryFile(String name);

  /// Asks where to keep [name]; null when the user cancels.
  Future<String?> chooseSaveLocation(String name);

  /// Whether Android lets the app install apps; when not, opens the system
  /// setting that allows it and answers false.
  Future<bool> allowInstall();

  /// Hands the APK at [file] to Android's installer.
  Future<InstallResult> install(File file);

  /// Shows [path] in Finder.
  Future<bool> reveal(String path);

  /// Opens [page] in the browser.
  Future<bool> open(Uri page);
}

/// The channel to the Android and macOS hosts (MainActivity.kt,
/// MainFlutterWindow.swift).
const appUpdateChannelName = 'com.flappedear.telemetry/app_update';

/// The device's [UpdatePlatform].
final class DeviceUpdatePlatform implements UpdatePlatform {
  const DeviceUpdatePlatform();

  static const _channel = MethodChannel(appUpdateChannelName);

  /// The folder (in the app's cache) the Android host serves APKs from
  /// (UpdateApkProvider.kt).
  static const updatesFolder = 'updates';

  @override
  TargetPlatform get platform => defaultTargetPlatform;

  @override
  Future<(String, String)> installedVersion() async {
    final info = await PackageInfo.fromPlatform();
    return (info.version, info.buildNumber);
  }

  @override
  Future<File> temporaryFile(String name) async {
    final folder = Directory(
      p.join((await getTemporaryDirectory()).path, updatesFolder),
    );
    try {
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      debugPrint('Old updates not removed: $error');
    }
    return File(p.join(folder.path, name));
  }

  @override
  Future<String?> chooseSaveLocation(String name) async {
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } on Object catch (error) {
      debugPrint('No downloads folder: $error');
    }
    final location = await getSaveLocation(
      suggestedName: name,
      initialDirectory: downloads?.path,
    );
    return location?.path;
  }

  @override
  Future<bool> allowInstall() async {
    try {
      return await _channel.invokeMethod<bool>('allowInstall') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Install permission not read: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<InstallResult> install(File file) async {
    try {
      final result = await _channel.invokeMethod<String>('install', {
        'name': p.basename(file.path),
      });
      return switch (result) {
        'started' => InstallResult.started,
        'permission' => InstallResult.needsPermission,
        _ => InstallResult.failed,
      };
    } on PlatformException catch (error) {
      debugPrint('Install failed: ${error.message}');
      return InstallResult.failed;
    } on MissingPluginException {
      return InstallResult.failed;
    }
  }

  @override
  Future<bool> reveal(String path) async {
    try {
      return await _channel.invokeMethod<bool>('reveal', {'path': path}) ??
          false;
    } on PlatformException catch (error) {
      debugPrint('Reveal failed: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> open(Uri page) async {
    try {
      return await launchUrl(page, mode: LaunchMode.externalApplication);
    } on PlatformException catch (error) {
      debugPrint('Opening $page failed: ${error.message}');
      return false;
    }
  }
}

/// Where the updater is.
enum UpdateStatus {
  /// Nothing checked yet.
  idle,
  checking,

  /// The app is the newest release (or newer).
  upToDate,

  /// A newer release is out.
  available,
  downloading,

  /// Android lets the app install apps only after the user allows it; the
  /// setting is open.
  needsPermission,

  /// Android's installer is open.
  installing,

  /// The Mac zip is downloaded, checked and saved ([AppUpdater.savedPath]).
  saved,

  /// The check or the download did not work ([AppUpdater.failure]).
  failed,
}

/// Looks for a newer release on GitHub and, where the release has a file for
/// this device, downloads it, checks it against the release's
/// SHA256SUMS.txt and hands it over: to Android's installer, or to a place
/// the user picks on a Mac. Elsewhere it opens the release's page.
///
/// It never replaces the running app itself.
class AppUpdater extends ChangeNotifier {
  AppUpdater({UpdateChecker? checker, UpdatePlatform? platform})
    : checker = checker ?? UpdateChecker(),
      platform = platform ?? const DeviceUpdatePlatform();

  final UpdateChecker checker;
  final UpdatePlatform platform;

  UpdateStatus get status => _status;
  UpdateStatus _status = UpdateStatus.idle;

  /// The running app's version as it reads it, such as "0.2.5 (6)".
  String? get installedLabel => _installedLabel;
  String? _installedLabel;

  /// What the last check found.
  UpdateCheck? get lastCheck => _check;
  UpdateCheck? _check;

  /// The newer release, when there is one.
  AppRelease? get release => _check?.available;

  /// The file this device downloads from [release]; null where there is
  /// none (iOS, Windows and Linux).
  ReleaseAsset? get asset => release?.assetFor(platform.platform);

  /// The share of the download done (0 to 1).
  double get progress => _progress;
  double _progress = 0;

  UpdateFailure? get failure => _failure;
  UpdateFailure? _failure;

  /// Where the Mac zip was saved.
  String? get savedPath => _savedPath;
  String? _savedPath;

  File? _apk;
  int _generation = 0;
  bool _disposed = false;

  bool get busy =>
      _status == UpdateStatus.checking || _status == UpdateStatus.downloading;

  void _set(UpdateStatus status, {UpdateFailure? failure}) {
    _status = status;
    _failure = failure;
    if (!_disposed) notifyListeners();
  }

  Future<AppVersion?> _installed() async {
    try {
      final (version, build) = await platform.installedVersion();
      _installedLabel = build.isEmpty ? version : '$version ($build)';
      return AppVersion.tryParse(version);
    } on Object catch (error) {
      debugPrint('App version not read: $error');
      return null;
    }
  }

  /// Asks GitHub for the newest release. Returns whether the check
  /// worked; a failure is in [failure].
  Future<bool> check() async {
    if (busy) return false;
    final generation = ++_generation;
    final before = _status;
    final pending = release?.version;
    _set(UpdateStatus.checking);
    try {
      final installed = await _installed();
      final check = await checker.check(installed);
      if (generation != _generation) return false;
      _check = check;
      if (installed == null) {
        _set(UpdateStatus.failed, failure: UpdateFailure.unexpected);
        return false;
      }
      final found = check.available;
      _set(
        found == null
            ? UpdateStatus.upToDate
            // A download already done for the same release stays offered.
            : found.version == pending &&
                  const {
                    UpdateStatus.needsPermission,
                    UpdateStatus.installing,
                    UpdateStatus.saved,
                  }.contains(before)
            ? before
            : UpdateStatus.available,
      );
      return true;
    } on Object catch (error) {
      debugPrint('Update check failed: $error');
      if (generation == _generation) {
        _set(
          UpdateStatus.failed,
          failure: error is UpdateException
              ? error.failure
              : UpdateFailure.unexpected,
        );
      }
      return false;
    }
  }

  /// Downloads and checks [asset]. On Android it first makes sure the app
  /// may install apps and then opens the installer; on a Mac it first asks
  /// where to keep the zip.
  Future<void> download() async {
    final release = this.release;
    final asset = this.asset;
    if (release == null || asset == null || busy) return;
    String? target;
    try {
      if (platform.platform == TargetPlatform.android) {
        if (!await platform.allowInstall()) {
          _set(UpdateStatus.needsPermission);
          return;
        }
      } else {
        target = await platform.chooseSaveLocation(asset.name);
        if (target == null) return;
      }
    } on Object catch (error) {
      debugPrint('Update not started: $error');
      _set(UpdateStatus.failed, failure: UpdateFailure.unexpected);
      return;
    }
    final generation = ++_generation;
    _progress = 0;
    _set(UpdateStatus.downloading);
    try {
      final file = await platform.temporaryFile(asset.name);
      await checker.download(release, asset, file, (share) {
        if (generation != _generation) return;
        _progress = share.clamp(0, 1).toDouble();
        if (!_disposed) notifyListeners();
      });
      if (generation != _generation) return;
      if (target == null) {
        _apk = file;
        await install();
        return;
      }
      try {
        await file.copy(target);
        await file.delete();
      } on FileSystemException catch (error) {
        throw UpdateException(UpdateFailure.notSaved, '$error');
      }
      _savedPath = target;
      _set(UpdateStatus.saved);
      await platform.reveal(target);
    } on Object catch (error) {
      debugPrint('Update download failed: $error');
      if (generation == _generation) {
        _set(
          UpdateStatus.failed,
          failure: error is UpdateException
              ? error.failure
              : UpdateFailure.unexpected,
        );
      }
    }
  }

  /// After the user allowed installs: installs the APK already downloaded,
  /// or downloads it.
  Future<void> continueAfterPermission() =>
      _apk != null ? install() : download();

  /// Hands the downloaded APK to Android's installer, again if the user
  /// closed it.
  Future<void> install() async {
    final apk = _apk;
    if (apk == null) return;
    switch (await platform.install(apk)) {
      case InstallResult.started:
        _set(UpdateStatus.installing);
      case InstallResult.needsPermission:
        _set(UpdateStatus.needsPermission);
      case InstallResult.failed:
        _set(UpdateStatus.failed, failure: UpdateFailure.unexpected);
    }
  }

  /// Opens the newer release's page, or the releases page.
  Future<bool> openReleasePage() =>
      platform.open(release?.page ?? releasesPage);

  /// Shows the saved Mac zip in Finder again.
  Future<bool> revealSaved() async {
    final path = _savedPath;
    return path != null && await platform.reveal(path);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
