import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const _UpdateSheet(ready: false),
    );
  }

  static Future<void> showReadyToInstall(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
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
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final navigator = Navigator.of(context);
    final buildLabel = state.availableVersionCode == null
        ? ''
        : ' (build ${state.availableVersionCode})';

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ready ? LucideIcons.refreshCw : LucideIcons.download,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    ready ? 'Update downloaded' : 'A new version is ready',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.textPrimary,
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
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
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
                          await controller.startFlexibleDownload();
                          if (context.mounted) navigator.pop();
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.45),
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
                child: const Text(
                  'Later',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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
