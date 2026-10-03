import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/entities/mind_item.dart';
import '../controllers/mind_feed_controller.dart';
import '../controllers/navigation_controller.dart';
import 'clipboard_prompt_banner.dart';

enum ShareCapturePhase {
  idle,
  saving,
  saved,
  duplicate,
  failed,
}

@immutable
class ShareCaptureState {
  const ShareCaptureState({
    this.phase = ShareCapturePhase.idle,
    this.rawShared,
    this.sourceLabel = 'KeepIt',
    this.sourceIcon = LucideIcons.sparkles,
    this.savedItem,
    this.errorMessage,
  });

  final ShareCapturePhase phase;
  final String? rawShared;
  final String sourceLabel;
  final IconData sourceIcon;
  final MindItem? savedItem;
  final String? errorMessage;

  bool get isVisible => phase != ShareCapturePhase.idle;
}

class ShareCaptureController extends StateNotifier<ShareCaptureState> {
  ShareCaptureController(this._ref) : super(const ShareCaptureState());

  final Ref _ref;
  Timer? _hideTimer;
  String? _lastRaw;
  DateTime? _lastStartedAt;

  static bool looksLikeImagePath(String value) => RegExp(
        r'\.(?:jpe?g|png|webp|gif|heic|heif)(?:[?#].*)?$',
        caseSensitive: false,
      ).hasMatch(value.trim());

  static (String, IconData) _describeSource(String raw) {
    final trimmed = raw.trim();
    if (looksLikeImagePath(trimmed)) {
      return ('Image', LucideIcons.image);
    }
    final urlMatch = RegExp(r'(https?://[^\s]+)').firstMatch(trimmed);
    final url = urlMatch?.group(0) ?? trimmed;
    final uri = Uri.tryParse(url);
    final host =
        uri?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '') ?? '';

    if (host.contains('instagram.com')) {
      return ('Instagram', LucideIcons.instagram);
    }
    if (host.contains('youtube.com') || host == 'youtu.be') {
      return ('YouTube', LucideIcons.youtube);
    }
    if (host == 'x.com' || host.contains('twitter.com')) {
      return ('X', LucideIcons.twitter);
    }
    if (host.contains('github.com')) {
      return ('GitHub', LucideIcons.github);
    }
    if (host.contains('linkedin.com')) {
      return ('LinkedIn', LucideIcons.linkedin);
    }
    if (host.isNotEmpty) {
      return (host, LucideIcons.link2);
    }
    return ('Note', LucideIcons.sparkles);
  }

  /// Processes a link or image shared from another app.
  ///
  /// Deduplicates identical intents delivered back-to-back (Android can emit
  /// both `getInitialMedia` and `getMediaStream` on a cold launch).
  Future<void> capture(
    String rawShared, {
    Duration savedDisplayDuration = const Duration(milliseconds: 2800),
    bool force = false,
  }) async {
    final clean = rawShared.trim();
    if (clean.isEmpty) return;

    final now = DateTime.now();
    if (!force &&
        _lastRaw == clean &&
        _lastStartedAt != null &&
        now.difference(_lastStartedAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastRaw = clean;
    _lastStartedAt = now;
    _hideTimer?.cancel();

    final (sourceLabel, sourceIcon) = _describeSource(clean);

    // Bring the user to the Everything feed so they see their new card arrive.
    _ref.read(homeTabProvider.notifier).state = HomeTab.everything;

    state = ShareCaptureState(
      phase: ShareCapturePhase.saving,
      rawShared: clean,
      sourceLabel: sourceLabel,
      sourceIcon: sourceIcon,
    );

    try {
      final notifier = _ref.read(mindFeedProvider.notifier);
      // Also mark the shared URL as seen by the clipboard prompt so it does
      // not nag if the user also copied the same link.
      if (!looksLikeImagePath(clean)) {
        final normalized = notifier.normalizeUrl(clean);
        try {
          await _ref.read(localDataSourceProvider).putMeta(
                ClipboardPromptBanner.lastPromptedMetaKey,
                normalized,
              );
        } catch (_) {}
      }

      final result = looksLikeImagePath(clean)
          ? await notifier.addImagePath(clean)
          : await notifier.addUrl(clean);
      if (!mounted) return;

      if (result == SaveResult.success) {
        HapticFeedback.mediumImpact();
        final saved = _ref.read(mindFeedProvider).lastSavedItem;
        state = ShareCaptureState(
          phase: ShareCapturePhase.saved,
          rawShared: clean,
          sourceLabel: sourceLabel,
          sourceIcon: sourceIcon,
          savedItem: saved,
        );
        _scheduleHide(savedDisplayDuration);
      } else if (result == SaveResult.duplicate) {
        HapticFeedback.selectionClick();
        state = ShareCaptureState(
          phase: ShareCapturePhase.duplicate,
          rawShared: clean,
          sourceLabel: sourceLabel,
          sourceIcon: sourceIcon,
        );
        _scheduleHide(const Duration(milliseconds: 2200));
      } else {
        dismiss();
      }
    } catch (e) {
      if (!mounted) return;
      state = ShareCaptureState(
        phase: ShareCapturePhase.failed,
        rawShared: clean,
        sourceLabel: sourceLabel,
        sourceIcon: sourceIcon,
        errorMessage: 'Could not save right now. Check connection & retry.',
      );
      _scheduleHide(const Duration(seconds: 6));
    }
  }

  /// Retries the last failed share intent.
  Future<void> retry() async {
    final raw = state.rawShared;
    if (raw == null) return;
    await capture(raw, force: true);
  }

  void dismiss() {
    _hideTimer?.cancel();
    if (!mounted) return;
    state = const ShareCaptureState();
  }

  void _scheduleHide(Duration duration) {
    _hideTimer?.cancel();
    _hideTimer = Timer(duration, () {
      if (mounted) {
        state = const ShareCaptureState();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}

final shareCaptureProvider =
    StateNotifierProvider<ShareCaptureController, ShareCaptureState>(
  (ref) => ShareCaptureController(ref),
);

/// Animated capture card shown when a link or image is shared into KeepIt from
/// Instagram, YouTube, Chrome or the system share sheet.
class ShareCaptureOverlay extends ConsumerWidget {
  const ShareCaptureOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capture = ref.watch(shareCaptureProvider);
    final palette = context.palette;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: !capture.isVisible
          ? const SizedBox.shrink(key: ValueKey('share_idle'))
          : _ShareCaptureCard(
              key: ValueKey('share_${capture.phase.name}'),
              capture: capture,
              palette: palette,
              onDismiss: () =>
                  ref.read(shareCaptureProvider.notifier).dismiss(),
              onRetry: () => ref.read(shareCaptureProvider.notifier).retry(),
            ),
    );
  }
}

class _ShareCaptureCard extends StatelessWidget {
  const _ShareCaptureCard({
    super.key,
    required this.capture,
    required this.palette,
    required this.onDismiss,
    required this.onRetry,
  });

  final ShareCaptureState capture;
  final AppPalette palette;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isSaving = capture.phase == ShareCapturePhase.saving;
    final isSaved = capture.phase == ShareCapturePhase.saved;
    final isDuplicate = capture.phase == ShareCapturePhase.duplicate;
    final isFailed = capture.phase == ShareCapturePhase.failed;

    final accentColor = isSaved
        ? palette.success
        : isFailed
            ? palette.danger
            : palette.primary;

    final headline = switch (capture.phase) {
      ShareCapturePhase.saving => 'Saving from ${capture.sourceLabel}…',
      ShareCapturePhase.saved => 'Saved to your Mind ✨',
      ShareCapturePhase.duplicate => 'Already in your Mind',
      ShareCapturePhase.failed => 'Could not capture link',
      ShareCapturePhase.idle => '',
    };

    final subtitle = switch (capture.phase) {
      ShareCapturePhase.saving =>
        'Extracting preview & smart tags automatically…',
      ShareCapturePhase.saved =>
        capture.savedItem?.title ?? 'Added to your Everything feed',
      ShareCapturePhase.duplicate =>
        'This ${capture.sourceLabel} link is already in your library.',
      ShareCapturePhase.failed =>
        capture.errorMessage ?? 'Tap Retry to try saving again.',
      ShareCapturePhase.idle => '',
    };

    final tags = isSaved
        ? (capture.savedItem?.tags.take(3).toList() ?? const <String>[])
        : const <String>[];

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: isSaving ? null : onDismiss,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.45),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              const BoxShadow(
                color: Color(0x29000000),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _LeadingBadge(
                      isSaving: isSaving,
                      isSaved: isSaved,
                      isDuplicate: isDuplicate,
                      isFailed: isFailed,
                      sourceIcon: capture.sourceIcon,
                      accentColor: accentColor,
                      palette: palette,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  isSaved ? FontWeight.w600 : FontWeight.w500,
                              color: palette.textSecondary,
                            ),
                          ),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final tag in tags)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.tagBg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '#$tag',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: palette.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isFailed) ...[
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: const Size(60, 34),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ] else if (!isSaving)
                      IconButton(
                        onPressed: onDismiss,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          LucideIcons.x,
                          size: 16,
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (isSaving)
                LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: palette.primaryLight,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingBadge extends StatelessWidget {
  const _LeadingBadge({
    required this.isSaving,
    required this.isSaved,
    required this.isDuplicate,
    required this.isFailed,
    required this.sourceIcon,
    required this.accentColor,
    required this.palette,
  });

  final bool isSaving;
  final bool isSaved;
  final bool isDuplicate;
  final bool isFailed;
  final IconData sourceIcon;
  final Color accentColor;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final icon = isSaved
        ? LucideIcons.checkCircle2
        : isDuplicate
            ? LucideIcons.bookmark
            : isFailed
                ? LucideIcons.alertCircle
                : sourceIcon;

    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          if (isSaving)
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: accentColor,
              ),
            ),
        ],
      ),
    );
  }
}
