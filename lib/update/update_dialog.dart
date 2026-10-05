import 'package:flutter/material.dart';

import '../app/app_navigation.dart';
import '../diagnostics/app_errors.dart';
import '../l10n.dart';
import '../units.dart';
import 'app_update.dart';
import 'app_updater.dart';

/// The app's updater, shared by the check on launch and settings.
AppUpdater appUpdater = AppUpdater();

/// Looks for a newer release when the app starts, at most once a day and
/// only when [updateCheckSetting] is on. A newer release is announced with
/// a message that opens [UpdateDialog]; anything else (offline, GitHub's
/// rate limit) stays quiet.
Future<void> checkForUpdateOnLaunch({DateTime? now}) async {
  final updater = appUpdater;
  final time = now ?? DateTime.now();
  if (!updateCheckSetting.value ||
      !updater.checker.enabled ||
      !updateCheckDue(lastUpdateCheck.value, time)) {
    return;
  }
  if (!await updater.check()) return;
  lastUpdateCheck.value = time;
  final release = updater.release;
  final messenger = appMessengerKey.currentState;
  if (release == null || messenger == null) return;
  final l10n = deviceL10n();
  messenger.showSnackBar(
    SnackBar(
      key: const ValueKey('updateAvailableMessage'),
      content: Text(l10n.updateAvailableMessage('${release.version}')),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: l10n.updateDetails,
        onPressed: () {
          final context = appNavigatorKey.currentContext;
          if (context != null) showUpdateDialog(context, check: false);
        },
      ),
    ),
  );
}

/// Opens [UpdateDialog]; with [check], it asks GitHub again first.
Future<void> showUpdateDialog(BuildContext context, {bool check = true}) {
  final updater = appUpdater;
  if (check) updater.check();
  return showDialog<void>(
    context: context,
    builder: (_) => UpdateDialog(updater: updater),
  );
}

/// What [updater] found and what can be done about it on this device.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.updater});

  final AppUpdater updater;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) => AlertDialog(
        title: Text(l10n.updateTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _content(context),
            ),
          ),
        ),
        actions: _actions(context),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final release = updater.release;
    final installed = updater.installedLabel;
    final installedLine = installed == null
        ? null
        : Text(
            l10n.updateInstalledVersion(installed),
            key: const ValueKey('updateInstalled'),
            style: theme.textTheme.bodySmall,
          );
    Text body(String text) => Text(text, key: const ValueKey('updateBody'));
    return switch (updater.status) {
      UpdateStatus.idle || UpdateStatus.checking => [
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        body(l10n.updateChecking),
      ],
      UpdateStatus.upToDate => [
        body(l10n.updateUpToDate),
        if (installedLine != null) ...[
          const SizedBox(height: 8),
          installedLine,
        ],
      ],
      UpdateStatus.available => [
        body(
          l10n.updateAvailable(
            '${release?.version}',
            installed ?? l10n.updateVersionUnknown,
          ),
        ),
        const SizedBox(height: 8),
        Text(switch (updater.platform.platform) {
          _ when updater.asset == null => l10n.updateNoDownloadHere,
          TargetPlatform.android => l10n.updateAndroidHelp,
          _ => l10n.updateMacHelp,
        }, style: theme.textTheme.bodySmall),
      ],
      UpdateStatus.downloading => [
        LinearProgressIndicator(
          key: const ValueKey('updateProgress'),
          value: updater.progress,
        ),
        const SizedBox(height: 12),
        body(
          l10n.updateDownloading(
            '${release?.version}',
            (updater.progress * 100).round(),
          ),
        ),
      ],
      UpdateStatus.needsPermission => [body(l10n.updateNeedsPermission)],
      UpdateStatus.installing => [body(l10n.updateInstalling)],
      UpdateStatus.saved => [body(l10n.updateSaved(updater.savedPath ?? ''))],
      UpdateStatus.failed => [
        body(switch (updater.failure) {
          UpdateFailure.offline => l10n.updateFailedOffline,
          UpdateFailure.rateLimited => l10n.updateFailedRateLimited,
          UpdateFailure.notVerifiable => l10n.updateFailedNotVerifiable,
          UpdateFailure.checksumMismatch => l10n.updateFailedChecksum,
          UpdateFailure.notSaved => l10n.updateFailedNotSaved,
          UpdateFailure.unexpected || null => l10n.updateFailedUnexpected,
        }),
        if (installedLine != null) ...[
          const SizedBox(height: 8),
          installedLine,
        ],
      ],
    };
  }

  List<Widget> _actions(BuildContext context) {
    final l10n = context.l10n;
    final close = TextButton(
      key: const ValueKey('updateClose'),
      onPressed: () => Navigator.pop(context),
      child: Text(l10n.close),
    );
    final page = TextButton(
      key: const ValueKey('updateOpenPage'),
      onPressed: updater.openReleasePage,
      child: Text(
        updater.release == null ? l10n.updateOpenReleases : l10n.updateWhatsNew,
      ),
    );
    return switch (updater.status) {
      UpdateStatus.available => [
        close,
        page,
        if (updater.asset != null)
          FilledButton(
            key: const ValueKey('updateDownload'),
            onPressed: updater.download,
            child: Text(
              updater.platform.platform == TargetPlatform.android
                  ? l10n.updateDownloadInstall
                  : l10n.updateDownload,
            ),
          ),
      ],
      UpdateStatus.needsPermission => [
        close,
        FilledButton(
          key: const ValueKey('updateInstall'),
          onPressed: updater.continueAfterPermission,
          child: Text(l10n.updateContinue),
        ),
      ],
      UpdateStatus.installing => [
        close,
        TextButton(
          key: const ValueKey('updateInstall'),
          onPressed: updater.install,
          child: Text(l10n.updateInstallAgain),
        ),
      ],
      UpdateStatus.saved => [
        close,
        FilledButton(
          key: const ValueKey('updateReveal'),
          onPressed: updater.revealSaved,
          child: Text(l10n.updateShowInFinder),
        ),
      ],
      UpdateStatus.failed => [
        close,
        page,
        FilledButton(
          key: const ValueKey('updateRetry'),
          onPressed: updater.check,
          child: Text(l10n.updateTryAgain),
        ),
      ],
      _ => [close],
    };
  }
}
