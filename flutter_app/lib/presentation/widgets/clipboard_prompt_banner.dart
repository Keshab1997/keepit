import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/mind_toast.dart';
import '../controllers/mind_feed_controller.dart';

/// Reads the current plain-text clipboard content.
///
/// Overridable in tests so widget tests can exercise the prompt without
/// platform channels.
typedef ClipboardReader = Future<String?> Function();

final clipboardReaderProvider = Provider<ClipboardReader>((ref) {
  return () async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (_) {
      return null;
    }
  };
});

/// Metadata about a copied URL so the prompt can name the source naturally.
@immutable
class ClipboardLinkCandidate {
  const ClipboardLinkCandidate({
    required this.url,
    required this.headline,
    required this.displayUrl,
    required this.icon,
  });

  final String url;
  final String headline;
  final String displayUrl;
  final IconData icon;

  /// Parses [raw] if and only if it is a standalone `http(s)` URL.
  ///
  /// Plain text, OTP codes, multi-line notes and malformed strings return
  /// `null` so KeepIt never nags about non-link clipboard content.
  static ClipboardLinkCandidate? tryParse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        !uri.host.contains('.')) {
      return null;
    }

    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final pathPreview = uri.path.isEmpty || uri.path == '/' ? '' : uri.path;
    final display = '$host$pathPreview';

    if (host == 'instagram.com' || host.endsWith('.instagram.com')) {
      final isReel = uri.path.contains('/reel');
      return ClipboardLinkCandidate(
        url: trimmed,
        headline: isReel ? 'Save Instagram Reel?' : 'Save Instagram link?',
        displayUrl: display,
        icon: LucideIcons.instagram,
      );
    }
    if (host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be') {
      return ClipboardLinkCandidate(
        url: trimmed,
        headline: 'Save YouTube video?',
        displayUrl: display,
        icon: LucideIcons.youtube,
      );
    }
    if (host == 'x.com' ||
        host == 'twitter.com' ||
        host.endsWith('.twitter.com')) {
      return ClipboardLinkCandidate(
        url: trimmed,
        headline: 'Save X post?',
        displayUrl: display,
        icon: LucideIcons.twitter,
      );
    }
    if (host == 'github.com' || host.endsWith('.github.com')) {
      return ClipboardLinkCandidate(
        url: trimmed,
        headline: 'Save GitHub link?',
        displayUrl: display,
        icon: LucideIcons.github,
      );
    }
    if (host == 'linkedin.com' || host.endsWith('.linkedin.com')) {
      return ClipboardLinkCandidate(
        url: trimmed,
        headline: 'Save LinkedIn post?',
        displayUrl: display,
        icon: LucideIcons.linkedin,
      );
    }

    return ClipboardLinkCandidate(
      url: trimmed,
      headline: 'Save copied link from $host?',
      displayUrl: display,
      icon: LucideIcons.link2,
    );
  }
}

/// Persistent 1-tap card shown when KeepIt opens or resumes with a fresh,
/// unsaved URL on the system clipboard. It stays until the user saves or
/// dismisses it so the prompt cannot disappear unnoticed.
class ClipboardPromptBanner extends ConsumerStatefulWidget {
  const ClipboardPromptBanner({super.key});

  /// Hive meta key storing the last clipboard URL the user explicitly handled.
  static const String handledUrlMetaKey = 'handled_clipboard_url';

  @override
  ConsumerState<ClipboardPromptBanner> createState() =>
      _ClipboardPromptBannerState();
}

class _ClipboardPromptBannerState extends ConsumerState<ClipboardPromptBanner>
    with WidgetsBindingObserver {
  ClipboardLinkCandidate? _candidate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkClipboard());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_checkClipboard());
    }
  }

  Future<void> _checkClipboard() async {
    if (!mounted || _saving) return;
    final notifier = ref.read(mindFeedProvider.notifier);
    await notifier.ready;
    if (!mounted) return;

    final raw = await ref.read(clipboardReaderProvider)();
    if (!mounted) return;

    final candidate = ClipboardLinkCandidate.tryParse(raw);
    if (candidate == null) {
      if (_candidate != null) setState(() => _candidate = null);
      return;
    }

    final normalized = notifier.normalizeUrl(candidate.url);

    // Never offer a link that is already in the user's library.
    if (notifier.hasUrl(candidate.url)) {
      if (_candidate != null) setState(() => _candidate = null);
      return;
    }

    // A clipboard prompt is considered handled only after an explicit
    // dismissal (or a successful/duplicate save), not merely because it was
    // shown. This lets an unanswered prompt return after an app restart.
    final local = ref.read(localDataSourceProvider);
    final handledUrl =
        local.getMeta<String>(ClipboardPromptBanner.handledUrlMetaKey);
    if (handledUrl == normalized) {
      if (_candidate != null) setState(() => _candidate = null);
      return;
    }

    // Resuming with the same pending URL should not replace or flash the card.
    if (_candidate != null &&
        notifier.normalizeUrl(_candidate!.url) == normalized) {
      return;
    }

    setState(() => _candidate = candidate);
  }

  Future<void> _markHandled(String url) async {
    final notifier = ref.read(mindFeedProvider.notifier);
    try {
      await ref.read(localDataSourceProvider).putMeta(
            ClipboardPromptBanner.handledUrlMetaKey,
            notifier.normalizeUrl(url),
          );
    } catch (_) {
      // Best-effort persistence; saved URLs are also filtered by hasUrl().
    }
  }

  Future<void> _saveCandidate() async {
    final candidate = _candidate;
    if (candidate == null || _saving) return;

    HapticFeedback.mediumImpact();
    setState(() => _saving = true);

    try {
      final result =
          await ref.read(mindFeedProvider.notifier).addUrl(candidate.url);
      if (!mounted) return;

      if (result == SaveResult.success || result == SaveResult.duplicate) {
        await _markHandled(candidate.url);
        if (!mounted) return;
        setState(() {
          _saving = false;
          _candidate = null;
        });
        if (result == SaveResult.success) {
          MindToast.showSuccessToast(context);
        } else {
          MindToast.showDuplicateToast(context);
        }
      } else {
        // Keep the card available if an attempted save did not complete.
        setState(() => _saving = false);
      }
    } catch (_) {
      if (!mounted) return;
      // Keep the prompt visible so the user can retry after the error toast.
      setState(() => _saving = false);
      MindToast.showDeleteToast(context, title: 'Could not save link');
    }
  }

  Future<void> _dismiss() async {
    final candidate = _candidate;
    if (candidate == null || _saving) return;

    HapticFeedback.selectionClick();
    setState(() => _candidate = null);
    await _markHandled(candidate.url);
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    if (candidate == null) return const SizedBox.shrink();

    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: palette.primaryLight,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                candidate.icon,
                size: 18,
                color: palette.primary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    candidate.displayUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _saveCandidate,
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                minimumSize: const Size(64, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            IconButton(
              onPressed: _saving ? null : _dismiss,
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              icon: Icon(
                LucideIcons.x,
                size: 16,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
