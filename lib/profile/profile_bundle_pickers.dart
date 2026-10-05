import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';

/// Where a profile bundle goes and comes from. Replaced by a fake in widget
/// tests.
abstract interface class ProfileBundlePickers {
  /// Whether an export is handed to the share sheet (phones) rather than
  /// saved where the user chooses (desktop).
  bool get shares;

  /// Where the user saves the bundle [fileName]; null when cancelled.
  Future<String?> saveLocation(String fileName);

  /// A file in the app's own temporary folder an export is written to
  /// first, the last export's left there removed.
  Future<String> workFile(String fileName);

  /// Opens the share sheet with the bundle at [path], from [origin] (the
  /// iPad shows it there); false when the user closed it without sharing.
  Future<bool> share(String path, Rect origin);

  /// A bundle to import; null when the user cancelled.
  Future<String?> pickBundle();

  /// Done with the bundle [pickBundle] gave: the copy a phone's picker made
  /// of it in the app's temporary folder is removed.
  Future<void> release(String path);
}

bool get _desktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// [path] with the bundle's extension once.
String withBundleExtension(String path) =>
    p.extension(path).toLowerCase() == profileBundleExtension
    ? path
    : '$path$profileBundleExtension';

/// The system save and open dialogs on desktop; the share sheet and the
/// system file picker on phones.
final class PlatformProfileBundlePickers implements ProfileBundlePickers {
  const PlatformProfileBundlePickers();

  static XTypeGroup get _bundles => XTypeGroup(
    label: deviceL10n().profileBundleType,
    extensions: const ['feprofile'],
  );

  @override
  bool get shares => !_desktop;

  @override
  Future<String?> saveLocation(String fileName) async {
    final location = await getSaveLocation(
      // The macOS panel adds the extension itself.
      suggestedName: Platform.isMacOS
          ? p.basenameWithoutExtension(fileName)
          : fileName,
      acceptedTypeGroups: [_bundles],
    );
    if (location == null) return null;
    final path = withBundleExtension(location.path);
    // A file the dialog did not ask about replacing (the extension was
    // added, or the Linux dialog, which never asks) is kept.
    if (path == location.path && !Platform.isLinux) return path;
    var free = path;
    for (var copy = 2; File(free).existsSync(); copy++) {
      free = p.join(
        p.dirname(path),
        '${p.basenameWithoutExtension(path)} ($copy)$profileBundleExtension',
      );
    }
    return free;
  }

  @override
  Future<String> workFile(String fileName) async {
    final folder = Directory(
      p.join((await getTemporaryDirectory()).path, 'profile-export'),
    );
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    return p.join(folder.path, fileName);
  }

  @override
  Future<bool> share(String path, Rect origin) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], sharePositionOrigin: origin),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  @override
  Future<String?> pickBundle() async =>
      (await openFile(acceptedTypeGroups: _desktop ? [_bundles] : const []))
          ?.path;

  @override
  Future<void> release(String path) async {
    if (_desktop) return;
    try {
      final temporary = (await getTemporaryDirectory()).path;
      // Android's picker copies into the cache folder; iOS's into the app's
      // tmp folder, beside Library/Caches.
      final copies = [
        temporary,
        if (Platform.isIOS) p.join(p.dirname(p.dirname(temporary)), 'tmp'),
      ];
      if (copies.any((folder) => p.isWithin(folder, path))) {
        await File(path).delete();
      }
    } on Object catch (error) {
      debugPrint('Picked profile copy not removed: $error');
    }
  }
}
