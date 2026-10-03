import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/updates/update_config.dart';
import '../controllers/app_update_controller.dart';
import 'update_required_screen.dart';

/// Wraps the app and triggers Google Play's native in-app update flow.
///
/// * asks Play on cold start and when resuming from the background whether a
///   newer KeepIt exists,
/// * hands directly over to Google Play's own update UI (`InAppUpdate`),
/// * replaces the app with [UpdateRequiredScreen] if a mandatory update was
///   refused.
class UpdateHost extends ConsumerStatefulWidget {
  const UpdateHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends ConsumerState<UpdateHost>
    with WidgetsBindingObserver {
  Timer? _startupTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startupTimer = Timer(UpdateConfig.startupDelay, () {
        if (!mounted) return;
        unawaited(ref.read(appUpdateProvider.notifier).check());
      });
    });
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(ref.read(appUpdateProvider.notifier).onAppResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateProvider);
    if (state.phase == AppUpdatePhase.blocked) {
      return const UpdateRequiredScreen();
    }
    return widget.child;
  }
}
