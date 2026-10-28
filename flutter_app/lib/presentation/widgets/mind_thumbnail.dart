import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/thumbnail_store.dart';
import '../controllers/mind_feed_controller.dart';

/// Builds the loading placeholder for a thumbnail URL.
typedef ThumbnailPlaceholderBuilder = Widget Function(
  BuildContext context,
  String url,
);

/// Builds the fallback shown when a thumbnail cannot be displayed.
typedef ThumbnailErrorBuilder = Widget Function(
  BuildContext context,
  String url,
  Object error,
);

const _thumbnailLoadError = FormatException('Thumbnail unavailable');

/// Single image widget for saved-item thumbnails.
///
/// Prefers the permanent copy kept by [ThumbnailStore] so cards keep their
/// picture after the remote URL expires; falls back to plain network
/// loading where no store exists (the web build). When neither works, it
/// asks the feed controller to re-scrape a fresh thumbnail URL once per
/// item, which heals cards whose original CDN link has died.
class MindThumbnail extends ConsumerStatefulWidget {
  final String url;
  final String? itemId;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final FilterQuality filterQuality;
  final ThumbnailPlaceholderBuilder? placeholderBuilder;
  final ThumbnailErrorBuilder? errorBuilder;

  const MindThumbnail({
    super.key,
    required this.url,
    this.itemId,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
    this.filterQuality = FilterQuality.low,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  @override
  ConsumerState<MindThumbnail> createState() => _MindThumbnailState();
}

class _MindThumbnailState extends ConsumerState<MindThumbnail> {
  File? _file;
  bool _failed = false;
  bool _useNetwork = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MindThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      // Fields only: the async reload below reports its result later.
      _file = null;
      _failed = false;
      _useNetwork = false;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    File? file;
    var useNetwork = false;
    try {
      final canStore = await ThumbnailStore.available();
      if (canStore) {
        file = await ThumbnailStore.fileFor(url) ??
            await ThumbnailStore.fetch(url);
      } else {
        useNetwork = true;
      }
    } catch (_) {
      useNetwork = true;
    }
    if (!mounted || url != widget.url) return;
    setState(() {
      _useNetwork = useNetwork;
      _file = file;
      _failed = !useNetwork && file == null;
    });
    if (_failed) _refreshSource();
  }

  /// One refresh attempt per item per session lives in the controller, so
  /// a failing card may call this on every rebuild without hammering.
  void _refreshSource() {
    final id = widget.itemId;
    if (id == null) return;
    unawaited(ref.read(mindFeedProvider.notifier).refreshThumbnail(id));
  }

  /// A stored file that no longer decodes (disk corruption) is deleted and
  /// the card falls back to the error state instead of looping on it.
  void _handleBrokenFile() {
    final broken = _file;
    scheduleMicrotask(() async {
      try {
        if (broken != null && await broken.exists()) {
          await broken.delete();
        }
      } catch (_) {
        // Best-effort cleanup.
      }
      if (!mounted || _file != broken) return;
      setState(() {
        _file = null;
        _failed = true;
      });
      _refreshSource();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_useNetwork) return _buildNetwork(context);
    if (_file != null) {
      return Image.file(
        _file!,
        fit: widget.fit,
        cacheWidth: widget.memCacheWidth,
        cacheHeight: widget.memCacheHeight,
        filterQuality: widget.filterQuality,
        errorBuilder: (context, error, stackTrace) {
          _handleBrokenFile();
          return _buildError(context, error);
        },
      );
    }
    if (_failed) return _buildError(context, _thumbnailLoadError);
    return _buildPlaceholder(context);
  }

  /// Network-only mode: no permanent store (web), same behaviour the app
  /// always had, including the disk cache of [CachedNetworkImage].
  Widget _buildNetwork(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: widget.url,
      fit: widget.fit,
      memCacheWidth: widget.memCacheWidth,
      memCacheHeight: widget.memCacheHeight,
      filterQuality: widget.filterQuality,
      fadeInDuration: const Duration(milliseconds: 100),
      placeholder: (context, url) => _buildPlaceholder(context),
      errorWidget: (context, url, error) {
        _refreshSource();
        return _buildError(context, error);
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final custom = widget.placeholderBuilder;
    if (custom != null) return custom(context, widget.url);
    final palette = context.palette;
    return Container(
      color: palette.tagBg,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0x40FF5B37),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final custom = widget.errorBuilder;
    if (custom != null) return custom(context, widget.url, error);
    final palette = context.palette;
    return Container(
      color: palette.tagBg,
      child: Center(
        child: Icon(
          LucideIcons.image,
          color: palette.textMuted,
          size: 28,
        ),
      ),
    );
  }
}
