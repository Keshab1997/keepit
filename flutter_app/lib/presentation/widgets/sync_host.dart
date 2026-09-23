import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/cloud_sync_controller.dart';
import '../controllers/mind_feed_controller.dart';

/// Connects the feed to Cloud Sync: every local change schedules a debounced
/// auto-sync, and the app syncs again whenever it returns to the foreground.
class SyncHost extends ConsumerStatefulWidget {
  final Widget child;
  const SyncHost({super.key, required this.child});

  @override
  ConsumerState<SyncHost> createState() => _SyncHostState();
}

class _SyncHostState extends ConsumerState<SyncHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Create the controller eagerly so it starts listening to auth state.
    final sync = ref.read(cloudSyncProvider.notifier);
    ref.read(mindFeedProvider.notifier).onLocalChange = sync.notifyLocalChange;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(cloudSyncProvider.notifier).onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
