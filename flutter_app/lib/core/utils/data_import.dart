import 'dart:convert';

import '../../domain/entities/custom_space.dart';
import '../../domain/entities/mind_item.dart';
import 'url_normalization.dart';

/// Thrown when the clipboard text is not a KeepIt backup at all.
///
/// Only the *file's* shape raises this; a single unreadable entry inside an
/// otherwise valid backup is counted in [ImportPlan.malformed] instead. One bad
/// record must cost that record, not the whole restore — the same reasoning
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
    required this.spaces,
    required this.total,
    required this.duplicates,
    required this.malformed,
    required this.spaceTotal,
    required this.spaceDuplicates,
    required this.spaceMalformed,
    required this.orphanedSpaces,
  });

  /// New items, in file order. Nothing here is on disk yet.
  final List<MindItem> items;

  /// New Spaces, in file order. Their `id` is unique against the device too.
  final List<CustomSpace> spaces;

  /// Entries the file contained (`count` when present, otherwise the length of
  /// the list actually parsed).
  final int total;

  /// Items whose id or link already exists on this device.
  final int duplicates;

  /// Items that could not be read as an item.
  final int malformed;

  /// Spaces the file contained (`spaceCount`, or the parsed length).
  final int spaceTotal;

  /// Spaces already on this device — same id, or the same name.
  final int spaceDuplicates;

  /// Spaces that could not be read.
  final int spaceMalformed;

  /// Items whose `spaceId` named a Space that is neither on the device nor in
  /// the backup. Their assignment is dropped rather than left dangling, which
  /// is the same invariant `LocalMindDataSource.deleteCustomSpace` keeps.
  final int orphanedSpaces;

  int get kept => items.length;

  int get spacesKept => spaces.length;

  bool get isEmpty => items.isEmpty && spaces.isEmpty;
}

/// "Restore my data" - the other half of `DataExport`.
class DataImport {
  DataImport._();

  /// The `format` marker `DataExport.buildJson` writes.
  static const supportedFormat = 'keepit-export';

  /// Reads [jsonText] and decides what a restore would add.
  ///
  /// [existing] is the current library: an item is a duplicate when its id is
  /// already saved, or when its link points at a page that is already saved
  /// (`UrlNormalization`, so `https://www.x.com/a/?utm_source=ig` does not come
  /// back as a second card). Duplicates and malformed entries are counted, not
  /// thrown - a restore of 300 items should not fail because one of them was
  /// hand-edited into nonsense.
  ///
  /// [existingSpaces] are the Spaces already on the device. A Space arriving
  /// with a familiar *name* counts as the same Space even when its id differs,
  /// and the imported items are re-pointed at the local id: two devices that
  /// each created "Startup ideas" restore into one Space, not two.
  static ImportPlan plan(
    String jsonText, {
    List<MindItem> existing = const [],
    List<CustomSpace> existingSpaces = const [],
  }) {
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

    final spaces = _planSpaces(decoded['spaces'], existingSpaces);

    final localSpaceIds = <String>{
      for (final space in existingSpaces) space.id,
    };
    final importingSpaceIds = <String>{
      for (final space in spaces.kept) space.id,
    };

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
    var orphanedSpaces = 0;

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

      final fileSpaceId = item.spaceId;
      final resolvedSpaceId = fileSpaceId == null || fileSpaceId.trim().isEmpty
          ? null
          : (spaces.idRemap[fileSpaceId] ??
              (localSpaceIds.contains(fileSpaceId) ||
                      importingSpaceIds.contains(fileSpaceId)
                  ? fileSpaceId
                  : null));
      if (fileSpaceId != null &&
          fileSpaceId.trim().isNotEmpty &&
          resolvedSpaceId == null) {
        orphanedSpaces++;
      }

      // A restored item has never been uploaded from *this* device, whatever
      // the file says, so cloud sync has to pick it up. `DataExport` already
      // strips `isSynced`; this also covers older and hand-edited files.
      kept.add(
        item.copyWith(
          isSynced: false,
          spaceId: resolvedSpaceId,
          clearSpaceId: resolvedSpaceId == null,
        ),
      );
    }

    final claimed = decoded['count'];
    final total = claimed is int && claimed >= 0 ? claimed : rawItems.length;

    return ImportPlan(
      items: List<MindItem>.unmodifiable(kept),
      spaces: List<CustomSpace>.unmodifiable(spaces.kept),
      total: total,
      duplicates: duplicates,
      malformed: malformed,
      spaceTotal: spaces.total,
      spaceDuplicates: spaces.duplicates,
      spaceMalformed: spaces.malformed,
      orphanedSpaces: orphanedSpaces,
    );
  }

  static _SpacePlan _planSpaces(
    Object? rawSpaces,
    List<CustomSpace> existingSpaces,
  ) {
    // A v1 backup has no `spaces` key at all: not an error, just an older file.
    if (rawSpaces is! List) {
      final malformed = rawSpaces == null ? 0 : 1;
      return _SpacePlan(
        kept: const [],
        idRemap: const {},
        total: 0,
        duplicates: 0,
        malformed: malformed,
      );
    }

    final localIds = <String>{
      for (final space in existingSpaces) space.id,
    };
    final localByName = <String, String>{
      for (final space in existingSpaces)
        space.name.trim().toLowerCase(): space.id,
    };

    final kept = <CustomSpace>[];
    final importing = <String>{};
    final idRemap = <String, String>{};
    var duplicates = 0;
    var malformed = 0;

    for (final raw in rawSpaces) {
      if (raw is! Map) {
        malformed++;
        continue;
      }
      final CustomSpace space;
      try {
        // Also derives an id when the file omitted one, and throws on a
        // nameless Space — the same rule the Hive reader applies.
        space = CustomSpace.fromMap(raw);
      } catch (_) {
        malformed++;
        continue;
      }

      final existingId = localByName[space.name.trim().toLowerCase()];
      if (existingId != null) {
        // Same Space, different id: keep the local one and point the file's
        // items at it, so a restore does not fork "Startup ideas" in two.
        final fileId = raw['id'];
        if (fileId is String && fileId.trim().isNotEmpty) {
          idRemap[fileId] = existingId;
        }
        duplicates++;
        continue;
      }

      if (localIds.contains(space.id) || importing.contains(space.id)) {
        duplicates++;
        continue;
      }

      importing.add(space.id);
      kept.add(space);
    }

    return _SpacePlan(
      kept: kept,
      idRemap: idRemap,
      total: rawSpaces.length,
      duplicates: duplicates,
      malformed: malformed,
    );
  }
}

class _SpacePlan {
  const _SpacePlan({
    required this.kept,
    required this.idRemap,
    required this.total,
    required this.duplicates,
    required this.malformed,
  });

  final List<CustomSpace> kept;

  /// file space id → local space id, for Spaces that already exist by name.
  final Map<String, String> idRemap;

  final int total;
  final int duplicates;
  final int malformed;
}
