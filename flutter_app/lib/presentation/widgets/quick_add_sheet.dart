import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../controllers/mind_feed_controller.dart';
import 'clipboard_prompt_banner.dart';

typedef QuickAddImagePicker = Future<void> Function();
typedef QuickAddLinkSaved = void Function(SaveResult result);

/// Smart quick-add sheet for links and gallery images.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({
    super.key,
    required this.onPickImage,
    required this.onLinkSaved,
  });

  final QuickAddImagePicker onPickImage;
  final QuickAddLinkSaved onLinkSaved;

  static void show(
    BuildContext context, {
    required QuickAddImagePicker onPickImage,
    required QuickAddLinkSaved onLinkSaved,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (_) => QuickAddSheet(
        onPickImage: onPickImage,
        onLinkSaved: onLinkSaved,
      ),
    );
  }

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  static final RegExp _urlPattern =
      RegExp(r'https?://\S+', caseSensitive: false);
  static final RegExp _trailingUrlPunctuation = RegExp(r'[)\]}>.,!?;:]+$');

  final TextEditingController _linkController = TextEditingController();
  bool _saving = false;
  bool _fromClipboard = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _linkController.addListener(_onLinkChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prefillFromClipboard());
    });
  }

  @override
  void dispose() {
    _linkController.removeListener(_onLinkChanged);
    _linkController.dispose();
    super.dispose();
  }

  void _onLinkChanged() {
    if (!mounted) return;
    setState(() {
      _fromClipboard = false;
      _errorMessage = null;
    });
  }

  Future<void> _prefillFromClipboard() async {
    final raw = await ref.read(clipboardReaderProvider)();
    if (!mounted || _linkController.text.trim().isNotEmpty) return;

    final url = _extractWebUrl(raw ?? '');
    if (url != null) _setClipboardLink(url);
  }

  Future<void> _pasteFromClipboard() async {
    final raw = await ref.read(clipboardReaderProvider)();
    if (!mounted) return;

    final url = _extractWebUrl(raw ?? '');
    if (url == null) {
      setState(() {
        _fromClipboard = false;
        _errorMessage = 'No web link found in the clipboard.';
      });
      return;
    }

    _setClipboardLink(url);
  }

  void _setClipboardLink(String url) {
    _linkController.value = TextEditingValue(
      text: url,
      selection: TextSelection.collapsed(offset: url.length),
    );
    if (mounted) setState(() => _fromClipboard = true);
  }

  String? _extractWebUrl(String raw) {
    final match = _urlPattern.firstMatch(raw.trim());
    if (match == null) return null;

    final url = match.group(0)!.replaceFirst(_trailingUrlPunctuation, '');
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        (scheme != 'http' && scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return url;
  }

  String _cleanInputForSave(String rawInput) {
    final input = rawInput.trim();
    final match = _urlPattern.firstMatch(input);
    if (match == null) return input;
    final cleanUrl = match.group(0)!.replaceFirst(_trailingUrlPunctuation, '');
    return input.replaceRange(match.start, match.end, cleanUrl);
  }

  Future<void> _saveLink(String rawInput) async {
    if (_saving) return;
    final url = _extractWebUrl(rawInput);
    if (url == null) {
      setState(
          () => _errorMessage = 'Add a complete http(s) link to continue.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();

    try {
      final result = await ref
          .read(mindFeedProvider.notifier)
          .addUrl(_cleanInputForSave(rawInput));
      if (!mounted) return;

      if (result == SaveResult.success || result == SaveResult.duplicate) {
        final onLinkSaved = widget.onLinkSaved;
        Navigator.of(context).pop();
        onLinkSaved(result);
      } else {
        setState(() {
          _saving = false;
          _errorMessage = 'Paste a link before saving.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage =
            'Could not save the link. Check your connection and try again.';
      });
    }
  }

  void _chooseImage() {
    if (_saving) return;
    final onPickImage = widget.onPickImage;
    Navigator.of(context).pop();
    unawaited(onPickImage());
  }

  String _sourceTitle(ClipboardLinkCandidate? candidate, Uri? uri) {
    if (candidate == null) return uri?.host ?? 'Web link';
    final title = candidate.headline;
    if (title.startsWith('Save ') && title.endsWith('?')) {
      return title.substring(5, title.length - 1);
    }
    return title;
  }

  String _displayUrl(ClipboardLinkCandidate? candidate, Uri? uri, String url) {
    if (candidate != null) return candidate.displayUrl;
    if (uri == null) return url;
    final path = uri.path.isEmpty || uri.path == '/' ? '' : uri.path;
    return '${uri.host}$path';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final feed = ref.watch(mindFeedProvider);
    final notifier = ref.read(mindFeedProvider.notifier);
    final rawInput = _linkController.text.trim();
    final url = _extractWebUrl(rawInput);
    final uri = url == null ? null : Uri.tryParse(url);
    final candidate = url == null ? null : ClipboardLinkCandidate.tryParse(url);
    final normalizedUrl = url == null ? null : notifier.normalizeUrl(url);
    final isDuplicate = normalizedUrl != null &&
        feed.items.any((item) {
          final existingUrl = item.url;
          return existingUrl != null &&
              existingUrl.isNotEmpty &&
              notifier.normalizeUrl(existingUrl) == normalizedUrl;
        });
    final sourceTitle = _sourceTitle(candidate, uri);
    final displayUrl = url == null ? '' : _displayUrl(candidate, uri, url);
    final hasInvalidText = rawInput.isNotEmpty && url == null;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: palette.glassBorder, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 28,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.cardBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: palette.primaryLight,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        LucideIcons.sparkles,
                        color: palette.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick save',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Add a link or choose an image',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.x, color: palette.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      'LINK OR VIDEO',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.05,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _saving ? null : _pasteFromClipboard,
                      icon: Icon(LucideIcons.copy,
                          size: 15, color: palette.primary),
                      label: Text(
                        'Paste',
                        style: TextStyle(
                          color: palette.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: _linkController,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: 2,
                  minLines: 1,
                  enabled: !_saving,
                  onSubmitted: (_) {
                    if (url != null && !isDuplicate) {
                      unawaited(_saveLink(rawInput));
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Paste a link, reel, or video URL...',
                    hintStyle: TextStyle(
                      color: palette.textMuted,
                      fontSize: 13.5,
                    ),
                    prefixIcon: Icon(
                      LucideIcons.link2,
                      color: palette.textSecondary,
                      size: 19,
                    ),
                    filled: true,
                    fillColor: palette.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: BorderSide(color: palette.cardBorderSoft),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: BorderSide(color: palette.cardBorderSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide:
                          BorderSide(color: palette.primary, width: 1.4),
                    ),
                  ),
                ),
                if (_fromClipboard) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.check, size: 14, color: palette.success),
                      const SizedBox(width: 6),
                      Text(
                        'Link found in clipboard',
                        style: TextStyle(
                          color: palette.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
                if (url != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: isDuplicate
                          ? palette.success.withValues(alpha: 0.10)
                          : palette.glassWhite,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: isDuplicate
                            ? palette.success.withValues(alpha: 0.35)
                            : palette.glassBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDuplicate
                                ? palette.success.withValues(alpha: 0.14)
                                : palette.primaryLight,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            isDuplicate
                                ? LucideIcons.check
                                : candidate?.icon ?? LucideIcons.link2,
                            color:
                                isDuplicate ? palette.success : palette.primary,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isDuplicate
                                    ? 'Already in your Mind'
                                    : sourceTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                displayUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isDuplicate)
                          Icon(LucideIcons.checkCircle2,
                              color: palette.success, size: 19),
                      ],
                    ),
                  ),
                  if (!isDuplicate) ...[
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Icon(LucideIcons.sparkles,
                            size: 14, color: palette.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'KeepIt will find the title and preview for you.',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else if (hasInvalidText) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Add a complete link starting with http:// or https://.',
                    style: TextStyle(
                      color: palette.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: palette.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 19),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving || url == null || isDuplicate
                        ? null
                        : () => _saveLink(rawInput),
                    icon: _saving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isDuplicate
                                ? LucideIcons.check
                                : LucideIcons.bookmark,
                            size: 18,
                          ),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : isDuplicate
                              ? 'Already saved'
                              : url == null
                                  ? 'Paste a link to continue'
                                  : 'Save to Mind',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          palette.primary.withValues(alpha: 0.45),
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _chooseImage,
                    icon: Icon(LucideIcons.image,
                        color: palette.primary, size: 18),
                    label: Text(
                      'Choose an image from gallery',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide(color: palette.cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
