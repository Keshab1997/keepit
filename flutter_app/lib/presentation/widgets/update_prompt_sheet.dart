import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../controllers/app_update_controller.dart';

/// KeepIt's own update screen.
///
/// Two states, one look:
/// * **update available** → download in the background, keep using the app.
/// * **update downloaded** → restart to install.
///
/// Play's own consent dialog is only reached once the user taps the primary
/// button, so a cold start never surprises anyone with a system dialog.
class UpdatePromptSheet {
  const UpdatePromptSheet._();

  static Future<void> showUpdateAvailable(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const _UpdateSheet(ready: false),
    );
  }

  static Future<void> showReadyToInstall(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const _UpdateSheet(ready: true),
    );
  }
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet({required this.ready});

  /// `false` → new build on Play, `true` → downloaded and waiting to install.
  final bool ready;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final navigator = Navigator.of(context);
    final buildLabel = state.availableVersionCode == null
        ? ''
        : ' (build ${state.availableVersionCode})';

    // Close the "A new version is ready" sheet as soon as the download starts,
    // finishes, or is dismissed in Play's dialog (on Android, startFlexibleUpdate
    // only resolves its Future once the entire download completes).
    ref.listen<AppUpdateState>(appUpdateProvider, (previous, next) {
      if (!ready &&
          (next.phase == AppUpdatePhase.downloading ||
              next.phase == AppUpdatePhase.readyToInstall ||
              next.phase == AppUpdatePhase.idle)) {
        if (navigator.canPop()) {
          navigator.pop();
        }
      }
    });

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: palette.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ready ? LucideIcons.refreshCw : LucideIcons.download,
                    color: palette.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    ready ? 'Update downloaded' : 'A new version is ready',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              ready
                  ? 'KeepIt needs to restart to finish installing. Everything you saved stays on this device.'
                  : 'A newer build$buildLabel is on Google Play. It downloads in the background while you keep using KeepIt.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: palette.textSecondary,
              ),
            ),
            if (state.message != null) ...[
              const SizedBox(height: 10),
              Text(
                state.message!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: palette.danger,
                ),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        if (ready) {
                          await controller.installDownloadedUpdate();
                        } else {
                          unawaited(controller.startFlexibleDownload());
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primary,
                  disabledBackgroundColor:
                      palette.primary.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: state.busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        ready ? 'Restart & install' : 'Update now',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            if (state.message != null && !ready) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          await controller.openPlayStore();
                          if (context.mounted) navigator.pop();
                        },
                  child: Text(
                    'Open in Play Store',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        // A downloaded update stays available; only an
                        // un-started download is postponed.
                        if (!ready) await controller.snooze();
                        if (context.mounted) navigator.pop();
                      },
                child: Text(
                  'Later',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
