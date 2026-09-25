import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../controllers/app_update_controller.dart';

/// Full-screen barrier shown **instead of** the app when the installed build
/// is no longer accepted.
///
/// Reaching this screen means the release was marked mandatory — either
/// [UpdateConfig.mandatoryBelowBuildNumber] is above this build number, or the
/// release carries Play's highest in-app update priority. There is no "skip":
/// Google's own guidance for a cancelled mandatory update is to block usage
/// until it is installed, which is exactly what this does.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);

    final installed = state.installedBuildNumber;
    final available = state.availableVersionCode;
    final versionLine = installed == null
        ? null
        : 'Installed build $installed'
            '${available == null ? '' : '  •  latest $available'}';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          minimum: const EdgeInsets.fromLTRB(28, 24, 28, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF8A65),
                        Color(0xFFFF5B37),
                        Color(0xFFE03C1C),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4DFF5B37),
                        blurRadius: 26,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.download,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Update required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This version of KeepIt can no longer be used. Install the '
                'latest update from Google Play — it takes a few seconds and '
                'everything you saved stays on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (state.message != null) ...[
                const SizedBox(height: 14),
                Text(
                  state.message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.danger,
                  ),
                ),
              ],
              if (versionLine != null) ...[
                const SizedBox(height: 16),
                Text(
                  versionLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const Spacer(flex: 3),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: state.busy
                      ? null
                      : () => controller.startMandatoryUpdate(),
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
                      : const Text(
                          'Update now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 46,
                child: TextButton(
                  onPressed: () => controller.openPlayStore(),
                  child: const Text(
                    'Open in Play Store',
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
      ),
    );
  }
}
