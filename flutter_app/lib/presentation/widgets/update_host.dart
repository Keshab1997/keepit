import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/updates/update_config.dart';
import '../controllers/app_update_controller.dart';
import 'update_prompt_sheet.dart';
import 'update_required_screen.dart';

/// Wraps the app and owns the update flow.
///
/// * asks Play once per cold start whether a newer KeepIt exists,
/// * shows KeepIt's own update screen when there is one,
/// * replaces the app with [UpdateRequiredScreen] for a mandatory release.
///
/// The check is silent: Play is never asked to show anything until the user
/// taps "Update", so a cold start stays clean.
class UpdateHost extends ConsumerStatefulWidget {
  const UpdateHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends ConsumerState<UpdateHost> {
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let the first frame, Hive and Firebase settle before touching Play.
      await Future<void>.delayed(UpdateConfig.startupDelay);
      if (!mounted) return;
      await ref.read(appUpdateProvider.notifier).check();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppUpdateState>(appUpdateProvider, (previous, next) {
      final changed = previous?.phase != next.phase;
      if (!changed || !next.hasPrompt || _sheetOpen) return;
      unawaited(
        next.phase == AppUpdatePhase.readyToInstall
            ? _showSheet(UpdatePromptSheet.showReadyToInstall)
            : _showSheet(UpdatePromptSheet.showUpdateAvailable),
      );
    });

    final state = ref.watch(appUpdateProvider);
    if (state.phase == AppUpdatePhase.blocked) {
      return const UpdateRequiredScreen();
    }

    return Stack(
      children: [
        widget.child,
        if (state.phase == AppUpdatePhase.downloading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _DownloadingBanner(),
          ),
      ],
    );
  }

  /// Opens the sheet and, if the user backs out of it without installing,
  /// treats that as "Later" so we do not ask again on the next rebuild.
  Future<void> _showSheet(
    Future<void> Function(BuildContext context) show,
  ) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    final phase = ref.read(appUpdateProvider).phase;
    try {
      await show(context);
    } finally {
      _sheetOpen = false;
    }
    if (!mounted) return;
    final current = ref.read(appUpdateProvider);
    if (current.phase == AppUpdatePhase.updateAvailable &&
        phase == AppUpdatePhase.updateAvailable) {
      await ref.read(appUpdateProvider.notifier).snooze();
    }
  }
}

/// Quiet, dismissible-by-ignoring progress pill for a background download.
class _DownloadingBanner extends StatelessWidget {
  const _DownloadingBanner();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Downloading update…',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                LucideIcons.download,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
