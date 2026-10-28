import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Permanent on-disk copy of the thumbnails KeepIt draws on its cards.
///
/// Card images used to live only in `CachedNetworkImage`'s cache plus the
/// remote URL itself. That cache is evicted (by age and by item count) and
/// remote thumbnail URLs expire — Instagram's signed CDN links and many
/// `og:image` URLs stop serving after a few months — so over time older
/// cards silently lost their pictures. Every thumbnail that ever loads is
/// therefore copied into this store and preferred over the network on
/// later builds.
class ThumbnailStore {
  ThumbnailStore._();

  /// Test seam: client used for downloads. Null restores a fresh default.
  @visibleForTesting
  static set debugClient(http.Client? client) =>
      _client = client ?? http.Client();

  /// Test seam: directory used instead of the app documents folder.
  @visibleForTesting
  static Directory? debugDirectory;

  static http.Client _client = http.Client();
  static Directory? _cachedDir;
  static final Map<String, Future<File?>> _inFlight = {};

  static const Duration fetchTimeout = Duration(seconds: 15);

  // Safety valve so years of thumbnails cannot grow without bound. The
  // oldest copies go first — their URLs are the most likely to be dead —
  // but realistic libraries never reach this limit.
  static const int _maxFiles = 3000;
  static const int _maxBytes = 200 * 1024 * 1024;

  /// Whether the permanent store works on this platform. Path provider is
  /// unimplemented on the web, where thumbnails keep their old
  /// network-only behaviour.
  static Future<bool> available() async {
    try {
      await _directory();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the permanent copy of [url], or null when nothing was saved yet.
  static Future<File?> fileFor(String url) async {
    final file = File('${(await _directory()).path}/${_key(url)}.img');
    return await file.exists() ? file : null;
  }

  /// Returns the permanent copy of [url], downloading it once if needed.
  ///
  /// Concurrent calls for the same URL share a single request. Returns null
  /// when the download fails or the payload is not an image.
  static Future<File?> fetch(String url) {
    final pending = _inFlight[url];
    if (pending != null) return pending;
    final future = _fetchAndStore(url);
    _inFlight[url] = future;
    future.whenComplete(() => _inFlight.remove(url));
    return future;
  }

  /// Writes [bytes] as the permanent copy of [url] (tmp file + rename, so a
  /// crash mid-write can never leave a half-image behind).
  static Future<File> save(String url, List<int> bytes) async {
    final dir = await _directory();
    final file = File('${dir.path}/${_key(url)}.img');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      // Windows refuses to rename over an existing file.
      await file.delete();
    }
    await tmp.rename(file.path);
    // Stat-ing the whole library must not delay the image being saved.
    unawaited(_prune(dir));
    return file;
  }

  static Future<File?> _fetchAndStore(String url) async {
    try {
      final file = File('${(await _directory()).path}/${_key(url)}.img');
      if (await file.exists()) return file;

      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return null;
      }
      final response = await _client.get(uri).timeout(fetchTimeout);
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty || !_looksLikeImage(bytes)) return null;
      return await save(url, bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _directory() async {
    final override = debugDirectory;
    if (override != null) return override;
    final cached = _cachedDir;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = await Directory('${base.path}/thumbnails').create(
      recursive: true,
    );
    _cachedDir = dir;
    return dir;
  }

  /// Stable per-platform filename key (FNV-1a over the URL plus a base64
  /// prefix). Unlike `String.hashCode` it survives app updates, so old
  /// files keep resolving after an upgrade.
  static String _key(String url) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < url.length; i++) {
      hash ^= url.codeUnitAt(i);
      hash = (hash * 16777619) & 0xffffffff;
    }
    final suffix = hash.toRadixString(16).padLeft(8, '0');
    final encoded = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    final prefix = encoded.length > 180 ? encoded.substring(0, 180) : encoded;
    return '$prefix-$suffix';
  }

  /// Rejects HTML error pages (and similar non-images) before they are
  /// persisted; otherwise a dead URL could cache a broken file forever.
  static bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    // Fixed signatures: JPEG, PNG, GIF8, BMP, ICO.
    if (_matchesAt(bytes, 0, const [0xFF, 0xD8, 0xFF])) return true;
    if (_matchesAt(bytes, 0, const [0x89, 0x50, 0x4E, 0x47])) return true;
    if (_matchesAt(bytes, 0, const [0x47, 0x49, 0x46, 0x38])) return true;
    if (_matchesAt(bytes, 0, const [0x42, 0x4D])) return true;
    if (_matchesAt(bytes, 0, const [0x00, 0x00, 0x01, 0x00])) return true;
    final riff = _matchesAt(bytes, 0, const [0x52, 0x49, 0x46, 0x46]);
    final webp = _matchesAt(bytes, 8, const [0x57, 0x45, 0x42, 0x50]);
    if (riff && webp) return true;
    // ISO BMFF stills (AVIF / HEIC) carry an ftyp box.
    return _matchesAt(bytes, 4, const [0x66, 0x74, 0x79, 0x70]);
  }

  static bool _matchesAt(List<int> bytes, int offset, List<int> signature) {
    if (offset + signature.length > bytes.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  static Future<void> _prune(Directory dir) async {
    try {
      final entries = <_ThumbFile>[];
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.img')) continue;
        try {
          final stat = await entity.stat();
          final modifiedMs = stat.modified.millisecondsSinceEpoch;
          entries.add(_ThumbFile(entity, modifiedMs, stat.size));
        } catch (_) {
          // A file vanishing mid-scan is fine.
        }
      }
      var count = entries.length;
      var bytes = entries.fold<int>(0, (sum, e) => sum + e.size);
      if (count <= _maxFiles && bytes <= _maxBytes) return;
      entries.sort((a, b) => a.modifiedMs.compareTo(b.modifiedMs));
      for (final entry in entries) {
        if (count <= _maxFiles && bytes <= _maxBytes) break;
        try {
          await entry.file.delete();
        } catch (_) {
          // Already gone — keep pruning.
        }
        count -= 1;
        bytes -= entry.size;
      }
    } catch (_) {
      // Pruning is a safety valve; never fail a save because of it.
    }
  }
}

class _ThumbFile {
  const _ThumbFile(this.file, this.modifiedMs, this.size);

  final File file;
  final int modifiedMs;
  final int size;
}
