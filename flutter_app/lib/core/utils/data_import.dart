import 'dart:convert';

import '../../domain/entities/mind_item.dart';
import 'url_normalization.dart';

/// Thrown when the clipboard text is not a KeepIt backup at all.
///
/// Only the *file's* shape raises this; a single unreadable entry inside an
/// otherwise valid backup is counted in [ImportPlan.malformed] instead. One bad
/// record must cost that record, not the whole restore - the same reasoning
/// `MindItem.fromMap` uses for its own fields.
class ImportFormatException implements Exception {
  const ImportFormatException(this.message);

  final String message;

  @override
  String toString() => 'ImportFormatException: $message';
}

/// What a backup file would change, decided before anything is written.
///
/// Keeping this separate from the write is what makes restore testable without
/// Hive and what lets the UI say "12 restored, 3 already here" *before* the
/// user's library changes.
class ImportPlan {
  const ImportPlan({
    required this.items,
    required this.total,
    required this.duplicates,
    required this.malformed,
  });

  /// New items, in file order. Nothing here is on disk yet.
  final List<MindItem> items;

  /// Entries the file contained (`count` when present, otherwise the length of
  /// the list actually parsed).
  final int total;

  /// Entries whose id or link already exists on this device.
  final int duplicates;

  /// Entries that could not be read as an item.
  final int malformed;

  int get kept => items.length;

  bool get isEmpty => items.isEmpty;
}

/// "Restore my data" - the other half of `DataExport`.
class DataImport {
  DataImport._();

  /// The `format` marker `DataExport.buildJson` writes.
  static const supportedFormat = 'keepit-export';

  /// Reads [jsonText] and decides what a restore would add.
  ///
  /// [existing] is the current library: an entry is a duplicate when its id is
  /// already saved, or when its link points at a page that is already saved
  /// (`UrlNormalization`, so `https://www.x.com/a/?utm_source=ig` does not come
  /// back as a second card). Duplicates and malformed entries are counted, not
  /// thrown - a restore of 300 items should not fail because one of them was
  /// hand-edited into nonsense.
  static ImportPlan plan(String jsonText,
      {List<MindItem> existing = const []}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw ImportFormatException('not valid JSON (${e.message})');
    }

    if (decoded is! Map) {
      throw const ImportFormatException('the file is not a KeepIt backup');
    }

    // A hand-edited or older file may omit `format`; a *different* marker is a
    // different app's backup, and guessing at it would corrupt the library.
    final format = decoded['format'];
    if (format != null && format != supportedFormat) {
      throw ImportFormatException('unexpected format "$format"');
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw const ImportFormatException('the backup has no items list');
    }

    final seenIds = <String>{
      for (final item in existing) item.id,
    };
    final seenUrls = <String>{
      for (final item in existing)
        if (item.url != null && item.url!.trim().isNotEmpty)
          UrlNormalization.key(item.url!),
    };

    final kept = <MindItem>[];
    var duplicates = 0;
    var malformed = 0;

    for (final raw in rawItems) {
      if (raw is! Map) {
        malformed++;
        continue;
      }

      // `MindItem.fromMap` requires a real id; anything else is not an item.
      final id = raw['id'];
      if (id is! String || id.trim().isEmpty) {
        malformed++;
        continue;
      }

      final MindItem item;
      try {
        item = MindItem.fromMap(raw);
      } catch (_) {
        malformed++;
        continue;
      }

      final url = item.url;
      final urlKey =
          url == null || url.trim().isEmpty ? null : UrlNormalization.key(url);

      if (seenIds.contains(item.id) ||
          (urlKey != null && seenUrls.contains(urlKey))) {
        duplicates++;
        continue;
      }

      seenIds.add(item.id);
      if (urlKey != null) seenUrls.add(urlKey);

      // A restored item has never been uploaded from *this* device, whatever
      // the file says, so cloud sync has to pick it up. `DataExport` already
      // strips `isSynced`; this also covers older and hand-edited files.
      kept.add(item.copyWith(isSynced: false));
    }

    final claimed = decoded['count'];
    final total = claimed is int && claimed >= 0 ? claimed : rawItems.length;

    return ImportPlan(
      items: List<MindItem>.unmodifiable(kept),
      total: total,
      duplicates: duplicates,
      malformed: malformed,
    );
  }
}
