import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/notifications/serendipity_planner.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/mind_toast.dart';
import '../../core/utils/notification_service.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/mind_feed_controller.dart';

/// Bottom sheet to configure Serendipity reminders and preview what is
/// scheduled.
class ReminderSettingsSheet extends ConsumerStatefulWidget {
  const ReminderSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const ReminderSettingsSheet(),
    );
  }

  @override
  ConsumerState<ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends ConsumerState<ReminderSettingsSheet> {
  final NotificationService _service = NotificationService();
  late ReminderSettings _settings;
  bool? _permissionGranted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _settings = _service.settings;
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final enabled = await _service.areNotificationsEnabled();
    if (mounted) setState(() => _permissionGranted = enabled);
  }

  Future<void> _apply(ReminderSettings next) async {
    HapticFeedback.selectionClick();
    setState(() {
      _settings = next;
      _busy = true;
    });
    if (next.enabled && _permissionGranted == false) {
      await _service.requestPermission();
      await _refreshPermission();
    }
    await _service.updateSettings(next, ref.read(mindFeedProvider).items);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.hour, minute: _settings.minute),
      helpText: 'Daily Spark time',
    );
    if (picked != null) {
      await _apply(_settings.copyWith(hour: picked.hour, minute: picked.minute));
    }
  }

  Future<void> _sendTest(List<MindItem> items) async {
    final candidates = items.where((i) => !i.isWatched).toList();
    if (candidates.isEmpty) {
      MindToast.showDuplicateToast(context, title: 'Nothing unwatched to remind you about');
      return;
    }
    final ok = await _service.showTestNotification((candidates..shuffle()).first);
    await _refreshPermission();
    if (!mounted) return;
    if (ok) {
      MindToast.showSuccessToast(context, title: 'Test notification sent!');
    } else {
      MindToast.showDeleteToast(context, title: 'Notifications are blocked in system settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(mindFeedProvider).items;
    final byId = {for (final i in items) i.id: i};
    final upcoming = _service.upcoming.where((p) => p.fireAt.isAfter(DateTime.now())).take(5).toList();
    final timeLabel = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: _settings.hour, minute: _settings.minute),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFDFDFE),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E4E9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(LucideIcons.bellRing, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Serendipity Reminders',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Resurface forgotten saves on day 3, 14, 45 & 90',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              if (_permissionGranted == false && _settings.enabled) _permissionBanner(),

              _card(
                children: [
                  _switchRow(
                    icon: LucideIcons.bell,
                    title: 'Daily Spark',
                    subtitle: 'Max 1 gentle reminder per day',
                    value: _settings.enabled,
                    onChanged: (v) => _apply(_settings.copyWith(enabled: v)),
                  ),
                  _divider(),
                  _tapRow(
                    icon: LucideIcons.clock,
                    title: 'Reminder time',
                    subtitle: 'When your daily Spark arrives',
                    trailing: timeLabel,
                    enabled: _settings.enabled,
                    onTap: _pickTime,
                  ),
                  _divider(),
                  _switchRow(
                    icon: LucideIcons.sun,
                    title: 'Sunday Mind Digest',
                    subtitle: 'Top 3 unwatched items • Sundays 10:00 AM',
                    value: _settings.weeklyDigest,
                    enabled: _settings.enabled,
                    onChanged: (v) => _apply(_settings.copyWith(weeklyDigest: v)),
                  ),
                ],
              ),

              const SizedBox(height: 22),
              const Text(
                'COMING UP',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (!_settings.enabled)
                _emptyUpcoming('Reminders are turned off.')
              else if (upcoming.isEmpty)
                _emptyUpcoming('Nothing due in the next 2 weeks. Items are first resurfaced 3 days after saving.')
              else
                _card(
                  children: [
                    for (var i = 0; i < upcoming.length; i++) ...[
                      if (i > 0) _divider(),
                      _upcomingRow(upcoming[i], byId),
                    ],
                  ],
                ),

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _sendTest(items),
                  icon: const Icon(LucideIcons.send, size: 16, color: AppColors.primary),
                  label: const Text(
                    'Send a test notification',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0x66FF5B37)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tip: use “Mark Watched” or “In 1 Week” right on the notification — no need to open the app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _permissionBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x14FF3B30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x40FF3B30)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.bellOff, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Notifications are off for KeepIt. Allow them so reminders can reach you.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: () async {
              await _service.requestPermission();
              await _refreshPermission();
            },
            child: const Text('Allow', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    // Material (not a coloured Container) so ListTile ink splashes show.
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFEDEEF2)),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 56, color: Color(0xFFF0F1F4));

  Widget _leadingIcon(IconData icon, bool enabled) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: enabled ? AppColors.tagBg : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 17, color: enabled ? AppColors.textPrimary : AppColors.textMuted),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: _leadingIcon(icon, enabled),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: enabled ? AppColors.textPrimary : AppColors.textMuted)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Switch.adaptive(
        value: value && enabled,
        activeTrackColor: AppColors.primary,
        onChanged: enabled ? onChanged : null,
      ),
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }

  Widget _tapRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailing,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: _leadingIcon(icon, enabled),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: enabled ? AppColors.textPrimary : AppColors.textMuted)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: enabled ? AppColors.primaryLight : AppColors.tagBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          trailing,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: enabled ? AppColors.primary : AppColors.textMuted),
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }

  Widget _upcomingRow(PlannedReminder reminder, Map<String, MindItem> byId) {
    final isDigest = reminder.kind == ReminderKind.digest;
    final item = reminder.itemId == null ? null : byId[reminder.itemId!];
    final when = _whenLabel(reminder.fireAt);
    final subtitle = isDigest
        ? '${reminder.itemIds.length} items • $when'
        : '${_stageLabel(reminder)} • $when';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: _leadingIcon(isDigest ? LucideIcons.sun : (reminder.snoozed ? LucideIcons.alarmClock : LucideIcons.sparkles), true),
      title: Text(
        isDigest ? 'Sunday Mind Digest' : (item?.title ?? 'Saved item'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }

  String _stageLabel(PlannedReminder r) {
    if (r.snoozed) return 'Snoozed';
    switch (r.stage) {
      case 0:
        return 'First spark';
      case 1:
        return 'Reinforcement';
      default:
        return 'Deep rediscovery';
    }
  }

  String _whenLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = day.difference(today).inDays;
    final time = DateFormat.jm().format(at);
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Tomorrow, $time';
    return '${DateFormat('EEE, MMM d').format(at)}, $time';
  }

  Widget _emptyUpcoming(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.tagBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
    );
  }
}
