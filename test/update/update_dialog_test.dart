import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/diagnostics/diagnostics_page.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/settings_dialog.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry/update/app_update.dart';
import 'package:telemetry/update/app_updater.dart';
import 'package:telemetry/update/update_dialog.dart';

class _Platform implements UpdatePlatform {
  _Platform(this.platform);

  @override
  final TargetPlatform platform;

  var installs = <InstallResult>[InstallResult.started];
  var allowed = <bool>[true];
  Object? temporaryError;
  final installed = <String>[];
  final revealed = <String>[];
  final opened = <Uri>[];
  String? saveTo;
  String temporaryFolder = '/tmp/updates';

  @override
  Future<(String, String)> installedVersion() async => ('0.2.5', '6');

  @override
  Future<bool> allowInstall() async => allowed.removeAt(0);

  @override
  Future<File> temporaryFile(String name) async => temporaryError != null
      ? throw temporaryError!
      : File('$temporaryFolder/$name');

  @override
  Future<String?> chooseSaveLocation(String name) async => saveTo;

  @override
  Future<InstallResult> install(File file) async {
    installed.add(file.path);
    return installs.removeAt(0);
  }

  @override
  Future<bool> reveal(String path) async {
    revealed.add(path);
    return true;
  }

  @override
  Future<bool> open(Uri page) async {
    opened.add(page);
    return true;
  }
}

String _answer(String tag) => jsonEncode([
  {
    'tag_name': tag,
    'draft': false,
    'html_url': 'https://github.com/FlappedEar/Telemetry/releases/tag/$tag',
    'assets': [
      for (final name in [
        'FlappedEar-Telemetry-0.2.6-android.apk',
        'FlappedEar-Telemetry-0.2.6-macos.zip',
        'SHA256SUMS.txt',
      ])
        {
          'name': name,
          'size': 10,
          'browser_download_url': 'https://github.com/x/$name',
        },
    ],
  },
]);

AppUpdater _updater(
  _Platform platform, {
  String tag = 'v0.2.6',
  UpdateFailure? failure,
  List<String>? downloads,
}) => AppUpdater(
  platform: platform,
  checker: UpdateChecker(
    fetch: (uri, _) async {
      if (failure != null) throw UpdateException(failure);
      return uri == releasesApi
          ? _answer(tag)
          : '${'a' * 64}  FlappedEar-Telemetry-0.2.6-android.apk\n'
                '${'a' * 64}  FlappedEar-Telemetry-0.2.6-macos.zip\n';
    },
    download: (asset, file, sha, progress) async {
      downloads?.add(file.path);
      progress(1);
    },
  ),
);

Future<void> _open(WidgetTester tester, AppUpdater updater) async {
  appUpdater = updater;
  await tester.pumpWidget(
    TelemetryApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showUpdateDialog(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _body(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('updateBody'))).data!;

void main() {
  tearDown(() {
    appUpdater = AppUpdater();
    updateCheckSetting.value = true;
    lastUpdateCheck.value = null;
  });

  testWidgets('says when the app is the newest version', (tester) async {
    await _open(
      tester,
      _updater(_Platform(TargetPlatform.android), tag: 'v0.2.5'),
    );
    expect(_body(tester), 'You have the newest version.');
    expect(find.text('This app: version 0.2.5 (6)'), findsOneWidget);
    expect(find.byKey(const ValueKey('updateDownload')), findsNothing);
  });

  testWidgets('Android asks for the install permission first, then '
      'downloads, checks and opens the installer', (tester) async {
    final platform = _Platform(TargetPlatform.android)
      ..allowed = [false, true]
      ..installs = [InstallResult.started, InstallResult.started];
    final downloads = <String>[];
    await _open(tester, _updater(platform, downloads: downloads));
    expect(_body(tester), 'Version 0.2.6 is available. You have 0.2.5 (6).');

    await tester.tap(find.byKey(const ValueKey('updateDownload')));
    await tester.pumpAndSettle();
    expect(downloads, isEmpty);
    expect(_body(tester), contains('allow FlappedEar Telemetry to install'));

    await tester.tap(find.byKey(const ValueKey('updateInstall')));
    await tester.pumpAndSettle();
    expect(downloads, ['/tmp/updates/FlappedEar-Telemetry-0.2.6-android.apk']);
    expect(platform.installed, hasLength(1));
    expect(_body(tester), contains("Android's installer is open"));

    // Checking again keeps the downloaded update on offer.
    await tester.tap(find.byKey(const ValueKey('updateInstall')));
    await tester.pumpAndSettle();
    expect(platform.installed, hasLength(2));
    await appUpdater.check();
    await tester.pumpAndSettle();
    expect(appUpdater.status, UpdateStatus.installing);
  });

  testWidgets('Android without the checksum file downloads nothing', (
    tester,
  ) async {
    final downloads = <String>[];
    final platform = _Platform(TargetPlatform.android);
    await _open(
      tester,
      AppUpdater(
        platform: platform,
        checker: UpdateChecker(
          fetch: (uri, _) async =>
              _answer('v0.2.6').replaceAll('SHA256SUMS.txt', 'NOTES.txt'),
          download: (asset, file, sha, progress) async =>
              downloads.add(file.path),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('updateDownload')));
    await tester.pumpAndSettle();
    expect(downloads, isEmpty);
    expect(_body(tester), contains('lists no checksum'));
  });

  testWidgets('an unexpected error ends the download, not the updater', (
    tester,
  ) async {
    final platform = _Platform(TargetPlatform.android)
      ..temporaryError = const FileSystemException('no cache');
    final updater = _updater(platform);
    await _open(tester, updater);
    await tester.tap(find.byKey(const ValueKey('updateDownload')));
    await tester.pumpAndSettle();
    expect(updater.status, UpdateStatus.failed);
    expect(updater.busy, isFalse);
    expect(find.byKey(const ValueKey('updateRetry')), findsOneWidget);
  });

  testWidgets('a Mac saves the zip where the user chose and shows it', (
    tester,
  ) async {
    final platform = _Platform(TargetPlatform.macOS);
    final folder = Directory.systemTemp.createTempSync('fet_update_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final saved = '${folder.path}/FlappedEar-Telemetry-0.2.6-macos.zip';
    platform
      ..saveTo = saved
      ..temporaryFolder = '${folder.path}/updates';
    final updater = AppUpdater(
      platform: platform,
      checker: UpdateChecker(
        fetch: (uri, _) async => uri == releasesApi
            ? _answer('v0.2.6')
            : '${'a' * 64}  FlappedEar-Telemetry-0.2.6-macos.zip\n',
        download: (asset, file, sha, progress) async {
          file.parent.createSync(recursive: true);
          file.writeAsStringSync('zip');
        },
      ),
    );
    await _open(tester, updater);
    await tester.runAsync(() async {
      await updater.download();
    });
    await tester.pumpAndSettle();
    expect(File(saved).existsSync(), isTrue);
    expect(platform.revealed, [saved]);
    expect(_body(tester), contains(saved));
    expect(
      File('${folder.path}/updates/${p.basename(saved)}').existsSync(),
      isFalse,
    );
    expect(find.byKey(const ValueKey('updateReveal')), findsOneWidget);
  });

  testWidgets('a Mac downloads nothing when the save panel is cancelled', (
    tester,
  ) async {
    final platform = _Platform(TargetPlatform.macOS);
    final downloads = <String>[];
    await _open(tester, _updater(platform, downloads: downloads));
    await tester.tap(find.byKey(const ValueKey('updateDownload')));
    await tester.pumpAndSettle();
    expect(downloads, isEmpty);
    expect(_body(tester), startsWith('Version 0.2.6 is available.'));
  });

  testWidgets('iOS and Windows show the release page instead', (tester) async {
    for (final target in [TargetPlatform.iOS, TargetPlatform.windows]) {
      final platform = _Platform(target);
      await _open(tester, _updater(platform));
      expect(find.byKey(const ValueKey('updateDownload')), findsNothing);
      expect(
        find.textContaining('no download for this device'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('updateOpenPage')));
      expect(
        platform.opened.single.toString(),
        'https://github.com/FlappedEar/Telemetry/releases/tag/v0.2.6',
      );
      await tester.tap(find.byKey(const ValueKey('updateClose')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a failed check says why and can be tried again', (tester) async {
    await _open(
      tester,
      _updater(
        _Platform(TargetPlatform.android),
        failure: UpdateFailure.rateLimited,
      ),
    );
    expect(_body(tester), contains('only a few checks an hour'));
    expect(find.byKey(const ValueKey('updateRetry')), findsOneWidget);
  });

  testWidgets('settings has the switch and the check button', (tester) async {
    appUpdater = _updater(_Platform(TargetPlatform.android), tag: 'v0.2.5');
    await tester.pumpWidget(const TelemetryApp(home: SettingsButton()));
    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    // The first section: no scrolling, with the app's version.
    expect(
      find.byKey(const ValueKey('checkForUpdates')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('This app: version 0.2.5 (6)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('updateCheckSetting')));
    await tester.pump();
    expect(updateCheckSetting.value, isFalse);
    await tester.tap(find.byKey(const ValueKey('checkForUpdates')));
    await tester.pumpAndSettle();
    expect(_body(tester), 'You have the newest version.');
  });

  testWidgets('settings on a phone show that they scroll', (tester) async {
    appUpdater = _updater(_Platform(TargetPlatform.android), tag: 'v0.2.5');
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TelemetryApp(home: SettingsButton()));
    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    final bar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('settingsScrollbar')),
    );
    expect(bar.thumbVisibility, isTrue);
    final position = bar.controller!.position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(
      find.byKey(const ValueKey('checkForUpdates')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settingsAppVersion')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('This app: version 0.2.5 (6)'), findsOneWidget);
  });

  testWidgets('settings on a Mac show one scrollbar, not two', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(const TelemetryApp(home: SettingsButton()));
    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SettingsDialog),
        matching: find.byType(Scrollbar),
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Home\'s ⋮ menu checks for updates', (tester) async {
    appUpdater = _updater(_Platform(TargetPlatform.android), tag: 'v0.2.5');
    await tester.pumpWidget(
      const TelemetryApp(home: Scaffold(appBar: _MenuBar())),
    );
    await tester.tap(find.byKey(const ValueKey('moreMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkForUpdatesMenuItem')));
    await tester.pumpAndSettle();
    expect(_body(tester), 'You have the newest version.');
  });

  group('on launch', () {
    Future<void> launch(WidgetTester tester, DateTime now) async {
      await tester.pumpWidget(const TelemetryApp(home: Scaffold()));
      await checkForUpdateOnLaunch(now: now);
      await tester.pump();
    }

    testWidgets('announces a newer release once a day', (tester) async {
      appUpdater = _updater(_Platform(TargetPlatform.android));
      final now = DateTime(2026, 10, 5, 12);
      await launch(tester, now);
      expect(
        find.text('FlappedEar Telemetry 0.2.6 is available.'),
        findsOneWidget,
      );
      expect(lastUpdateCheck.value, now);

      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(_body(tester), startsWith('Version 0.2.6 is available.'));
    });

    testWidgets('stays quiet when GitHub limits the checks', (tester) async {
      appUpdater = _updater(
        _Platform(TargetPlatform.android),
        failure: UpdateFailure.rateLimited,
      );
      await launch(tester, DateTime(2026, 10, 5, 12));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(lastUpdateCheck.value, isNull);
    });

    testWidgets('stays quiet when off, already checked today or offline', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 5, 12);
      appUpdater = _updater(_Platform(TargetPlatform.android));
      updateCheckSetting.value = false;
      await launch(tester, now);
      expect(lastUpdateCheck.value, isNull);

      updateCheckSetting.value = true;
      lastUpdateCheck.value = now.subtract(const Duration(hours: 2));
      await launch(tester, now);
      expect(appUpdater.status, UpdateStatus.idle);

      lastUpdateCheck.value = null;
      appUpdater = _updater(
        _Platform(TargetPlatform.android),
        failure: UpdateFailure.offline,
      );
      await launch(tester, now);
      expect(find.byType(SnackBar), findsNothing);
      expect(lastUpdateCheck.value, isNull);
    });
  });
}

class _MenuBar extends StatelessWidget implements PreferredSizeWidget {
  const _MenuBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) =>
      AppBar(actions: const [DiagnosticsMenu()]);
}
