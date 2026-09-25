import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cloud/auth_service.dart';
import '../../core/ads/ad_service.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/mind_toast.dart';
import '../../core/utils/data_export.dart';
import '../../core/utils/notification_service.dart';
import '../controllers/cloud_sync_controller.dart';
import '../controllers/mind_feed_controller.dart';
import '../widgets/reminder_settings_sheet.dart';

final packageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return null;
  }
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(cloudSyncProvider);
    final items = ref.watch(mindFeedProvider).items;
    final watched = items.where((i) => i.isWatched).length;
    final pinned = items.where((i) => i.isTopMind).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          _AccountCard(state: sync),
          const SizedBox(height: 14),
          _StatsRow(total: items.length, watched: watched, pinned: pinned),
          const SizedBox(height: 22),
          const _SectionLabel('CLOUD SYNC'),
          _CloudSyncCard(state: sync),
          const SizedBox(height: 22),
          const _SectionLabel('PREFERENCES'),
          _Group(
            children: [
              _Tile(
                icon: LucideIcons.bellRing,
                title: 'Serendipity reminders',
                subtitle: NotificationService().settings.enabled
                    ? 'On • daily at ${_fmtTime(context, NotificationService().settings.hour, NotificationService().settings.minute)}'
                    : 'Off',
                onTap: () => ReminderSettingsSheet.show(context),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionLabel('YOUR DATA'),
          _Group(
            children: [
              _Tile(
                icon: LucideIcons.download,
                title: 'Export my data',
                subtitle: 'Download all ${items.length} items as JSON',
                onTap: () => _export(context, ref),
              ),
              if (!sync.signedIn)
                _Tile(
                  icon: LucideIcons.trash2,
                  title: 'Delete all local data',
                  subtitle: 'Removes every item from this device',
                  destructive: true,
                  onTap: () => _confirmClearLocal(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionLabel('SUPPORT & LEGAL'),
          _Group(
            children: [
              _Tile(
                icon: LucideIcons.star,
                title: 'Rate KeepIt',
                subtitle: 'Enjoying the app? Leave a review',
                onTap: () => _open(context, AppConfig.playStoreUrl),
              ),
              _Tile(
                icon: LucideIcons.heart,
                title: 'Support KeepIt',
                subtitle: 'Watch a short, optional ad — free for you',
                onTap: () => _showRewardedAd(context),
              ),
              _Tile(
                icon: LucideIcons.mail,
                title: 'Contact support',
                subtitle: AppConfig.supportEmail,
                onTap: () => _emailSupport(context, ref),
              ),
              _Tile(
                icon: LucideIcons.shield,
                title: 'Privacy policy',
                onTap: () => _open(context, AppConfig.privacyPolicyUrl),
              ),
              _Tile(
                icon: LucideIcons.fileText,
                title: 'Terms of service',
                onTap: () => _open(context, AppConfig.termsUrl),
              ),
              _Tile(
                icon: LucideIcons.scale,
                title: 'Open-source licenses',
                onTap: () => _showLicenses(context, ref),
              ),
            ],
          ),
          if (sync.signedIn) ...[
            const SizedBox(height: 22),
            const _SectionLabel('ACCOUNT'),
            _Group(
              children: [
                _Tile(
                  icon: LucideIcons.logOut,
                  title: 'Sign out',
                  onTap: sync.busy ? null : () => _confirmSignOut(context, ref),
                ),
                _Tile(
                  icon: LucideIcons.userX,
                  title: 'Delete account',
                  subtitle: 'Permanently delete your account and cloud data',
                  destructive: true,
                  onTap: sync.busy
                      ? null
                      : () => _confirmDeleteAccount(context, ref),
                ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          const _VersionFooter(),
        ],
      ),
    );
  }

  static String _fmtTime(BuildContext context, int h, int m) =>
      MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay(hour: h, minute: m));

  static Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        MindToast.showDuplicateToast(
          context,
          title: 'Link copied to clipboard',
        );
      }
    }
  }

  /// Opt-in rewarded ad: the user chooses to watch a short video to support
  /// development. Never shown automatically.
  static Future<void> _showRewardedAd(BuildContext context) async {
    final earned = await AdService.instance.showRewarded();
    if (!context.mounted) return;
    if (earned) {
      MindToast.showSuccessToast(
        context,
        title: 'Thank you for supporting KeepIt! ❤️',
      );
    } else {
      MindToast.showDuplicateToast(
        context,
        title: 'Ad not ready — try again in a moment',
      );
    }
  }

  static Future<void> _emailSupport(BuildContext context, WidgetRef ref) async {
    final info = ref.read(packageInfoProvider).valueOrNull;
    final version = info == null
        ? ''
        : ' v${info.version} (${info.buildNumber})';
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.supportEmail,
      query: 'subject=${Uri.encodeComponent('KeepIt support$version')}',
    );
    final ok = await launchUrl(uri).catchError((_) => false);
    if (!ok && context.mounted) {
      await Clipboard.setData(
        const ClipboardData(text: AppConfig.supportEmail),
      );
      if (context.mounted) {
        MindToast.showDuplicateToast(
          context,
          title: 'Email copied to clipboard',
        );
      }
    }
  }

  static Future<void> _export(BuildContext context, WidgetRef ref) async {
    final items = ref.read(mindFeedProvider).items;
    if (items.isEmpty) {
      MindToast.showDuplicateToast(context, title: 'Nothing to export yet');
      return;
    }
    try {
      await DataExport.shareExport(items);
    } catch (e) {
      if (context.mounted) {
        MindToast.showDeleteToast(context, title: 'Export failed');
      }
    }
  }

  static void _showLicenses(BuildContext context, WidgetRef ref) {
    final info = ref.read(packageInfoProvider).valueOrNull;
    showLicensePage(
      context: context,
      applicationName: AppConfig.appName,
      applicationVersion: info == null
          ? null
          : '${info.version} (${info.buildNumber})',
      applicationLegalese: '© ${DateTime.now().year} Keshab Sarkar',
    );
  }

  static Future<void> _confirmClearLocal(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await _confirm(
      context,
      title: 'Delete all local data?',
      message: 'Every saved item on this device will be permanently removed. This cannot be undone.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (ok != true) return;
    await ref.read(cloudSyncProvider.notifier).clearLocalData();
    if (context.mounted) {
      MindToast.showDeleteToast(context, title: 'Local data deleted');
    }
  }

  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sign out?',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your items are safely stored in the cloud. What should happen to the copy on this phone?',
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              _SheetButton(
                label: 'Keep items on this device',
                icon: LucideIcons.smartphone,
                onTap: () => Navigator.pop(ctx, 'keep'),
              ),
              const SizedBox(height: 8),
              _SheetButton(
                label: 'Remove items from this device',
                icon: LucideIcons.trash2,
                destructive: true,
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    try {
      await ref
          .read(cloudSyncProvider.notifier)
          .signOut(removeLocalData: choice == 'remove');
      if (context.mounted) {
        MindToast.showSuccessToast(context, title: 'Signed out');
      }
    } catch (e) {
      if (context.mounted) {
        MindToast.showDeleteToast(context, title: 'Sign out failed');
      }
    }
  }

  static Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await _confirm(
      context,
      title: 'Delete your account?',
      message:
          'This permanently deletes your KeepIt account and all items stored in the cloud. '
          'Items on this phone will also be removed. This cannot be undone.',
      confirmLabel: 'Delete account',
      destructive: true,
      requireTyping: 'DELETE',
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(cloudSyncProvider.notifier)
          .deleteAccount(removeLocalData: true);
      if (context.mounted) {
        MindToast.showDeleteToast(context, title: 'Account deleted');
      }
    } on AuthFailure catch (e) {
      if (context.mounted && !e.cancelled) {
        MindToast.showDeleteToast(context, title: e.message);
      }
    } catch (e) {
      if (context.mounted) {
        MindToast.showDeleteToast(
          context,
          title: 'Could not delete account. Try again.',
        );
      }
    }
  }

  static Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
    String? requireTyping,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        destructive: destructive,
        requireTyping: requireTyping,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Account header
// -----------------------------------------------------------------------------

class _AccountCard extends ConsumerWidget {
  final CloudSyncState state;
  const _AccountCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = state.user;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7A59), AppColors.primary, Color(0xFFE04420)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33FF5B37),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _Avatar(user: user),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName?.trim().isNotEmpty == true
                      ? user!.displayName!
                      : (user == null ? 'Guest' : 'KeepIt user'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user?.email ?? 'Saved only on this device',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (user == null && state.available)
            _SignInButton(busy: state.busy)
          else if (user != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.cloud, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    'Synced',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SignInButton extends ConsumerWidget {
  final bool busy;
  const _SignInButton({required this.busy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy
            ? null
            : () async {
                HapticFeedback.mediumImpact();
                try {
                  await ref.read(cloudSyncProvider.notifier).signIn();
                  if (context.mounted) {
                    MindToast.showSuccessToast(
                      context,
                      title: 'Signed in — syncing your mind',
                    );
                  }
                } on AuthFailure catch (e) {
                  if (context.mounted && !e.cancelled) {
                    MindToast.showDeleteToast(context, title: e.message);
                  }
                } catch (_) {
                  if (context.mounted) {
                    MindToast.showDeleteToast(
                      context,
                      title: 'Sign-in failed. Try again.',
                    );
                  }
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GoogleG(size: 16),
                    SizedBox(width: 7),
                    Text(
                      'Sign in',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AppUser? user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final photo = user?.photoUrl;
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.7),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: photo != null
          ? CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              memCacheWidth: 116,
              memCacheHeight: 116,
              filterQuality: FilterQuality.low,
              errorWidget: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() {
    return Center(
      child: user == null
          ? const Icon(LucideIcons.user, color: Colors.white, size: 26)
          : Text(
              user!.initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

/// Simple multi-colour "G" mark (no external assets needed).
class _GoogleG extends StatelessWidget {
  final double size;
  const _GoogleG({required this.size});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const SweepGradient(
        colors: [
          Color(0xFF4285F4),
          Color(0xFF34A853),
          Color(0xFFFBBC05),
          Color(0xFFEA4335),
          Color(0xFF4285F4),
        ],
      ).createShader(rect),
      child: Text(
        'G',
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int total;
  final int watched;
  final int pinned;
  const _StatsRow({
    required this.total,
    required this.watched,
    required this.pinned,
  });

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDEEF2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        stat('$total', 'Saved', LucideIcons.bookmark),
        const SizedBox(width: 10),
        stat('$watched', 'Watched', LucideIcons.checkCheck),
        const SizedBox(width: 10),
        stat('$pinned', 'Top of Mind', LucideIcons.star),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Cloud sync
// -----------------------------------------------------------------------------

class _CloudSyncCard extends ConsumerWidget {
  final CloudSyncState state;
  const _CloudSyncCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!state.available) {
      return const _InfoCard(
        icon: LucideIcons.cloudOff,
        title: 'Cloud sync not set up yet',
        message: 'KeepIt works fully offline. Cloud backup & multi-device sync will be available once this build is connected to Firebase.',
      );
    }
    if (!state.signedIn) {
      return const _InfoCard(
        icon: LucideIcons.uploadCloud,
        title: 'Back up & sync your mind',
        message: 'Sign in with Google to back up your saves and keep them in sync across devices. Your data stays private to your account.',
      );
    }

    final controller = ref.read(cloudSyncProvider.notifier);
    final syncing = state.status == SyncStatus.syncing;
    final (
      IconData icon,
      Color color,
      String headline,
    ) = switch (state.status) {
      SyncStatus.syncing => (
        LucideIcons.refreshCw,
        AppColors.primary,
        'Syncing…',
      ),
      SyncStatus.error => (
        LucideIcons.alertCircle,
        AppColors.danger,
        'Sync problem',
      ),
      _ => (LucideIcons.checkCircle2, AppColors.success, 'Up to date'),
    };

    return _Group(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: syncing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: state.status == SyncStatus.error
                            ? AppColors.danger
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: syncing
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        final report = await controller.syncNow();
                        if (!context.mounted) return;
                        if (report != null) {
                          MindToast.showSuccessToast(
                            context,
                            title: report.summary,
                          );
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text(
                  'Sync now',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const Divider(
          height: 1,
          indent: 14,
          endIndent: 14,
          color: Color(0xFFF0F1F4),
        ),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          value: state.autoSync,
          activeTrackColor: AppColors.primary,
          onChanged: controller.setAutoSync,
          title: const Text(
            'Auto sync',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Sync automatically after changes and when you open the app',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  String _subtitle() {
    if (state.status == SyncStatus.error && state.message != null) {
      return state.message!;
    }
    final last = state.lastSyncAt;
    final pending = state.pendingChanges;
    final lastLabel = last == null
        ? 'Never synced'
        : 'Last synced ${_relative(last)}';
    return pending > 0 ? '$lastLabel • $pending pending' : lastLabel;
  }

  static String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return DateFormat('MMM d, h:mm a').format(t);
  }
}

// -----------------------------------------------------------------------------
// Building blocks
// -----------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && children[i] is _Tile && children[i - 1] is _Tile) {
        spaced.add(
          const Divider(height: 1, indent: 58, color: Color(0xFFF0F1F4)),
        );
      }
      spaced.add(children[i]);
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFEDEEF2)),
      ),
      child: Column(children: spaced),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.textPrimary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: destructive ? const Color(0x14FF3B30) : AppColors.tagBg,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
      trailing: const Icon(
        LucideIcons.chevronRight,
        size: 17,
        color: AppColors.textMuted,
      ),
      onTap: onTap,
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDEEF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
  const _SheetButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.textPrimary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: color),
        label: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          side: BorderSide(
            color: destructive
                ? const Color(0x55FF3B30)
                : const Color(0xFFE5E7EB),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final String? requireTyping;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    this.requireTyping,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needs = widget.requireTyping;
    final enabled =
        needs == null || _controller.text.trim().toUpperCase() == needs;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if (needs != null) ...[
            const SizedBox(height: 14),
            Text(
              'Type $needs to confirm',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: needs,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: enabled ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: widget.destructive
                ? AppColors.danger
                : AppColors.primary,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _VersionFooter extends ConsumerWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(packageInfoProvider).valueOrNull;
    return Column(
      children: [
        const Icon(LucideIcons.sparkles, size: 18, color: AppColors.primary),
        const SizedBox(height: 6),
        Text(
          info == null
              ? AppConfig.appName
              : '${AppConfig.appName} v${info.version} (${info.buildNumber})',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Made with ❤️ by Keshab Studios',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
