import 'package:flutter/foundation.dart';

enum ItemType {
  instagramReel,
  youtubeVideo,
  webArticle,
  quote,
  image,
  quickNote,
}

class MindItem {
  final String id;
  final String title;
  final String? url;
  final String? content;
  final String? thumbnailUrl;
  final String? authorName;
  final String? authorAvatar;
  final ItemType type;
  final List<String> tags;
  final String? spaceId;
  final bool isWatched;
  final bool isTopMind;
  final String? dominantColorHex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;

  const MindItem({
    required this.id,
    required this.title,
    this.url,
    this.content,
    this.thumbnailUrl,
    this.authorName,
    this.authorAvatar,
    required this.type,
    this.tags = const [],
    this.spaceId,
    this.isWatched = false,
    this.isTopMind = false,
    this.dominantColorHex,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  MindItem copyWith({
    String? id,
    String? title,
    String? url,
    String? content,
    bool clearContent = false,
    String? thumbnailUrl,
    String? authorName,
    String? authorAvatar,
    ItemType? type,
    List<String>? tags,
    String? spaceId,
    bool clearSpaceId = false,
    bool? isWatched,
    bool? isTopMind,
    String? dominantColorHex,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return MindItem(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      content: clearContent ? null : (content ?? this.content),
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      authorName: authorName ?? this.authorName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      spaceId: clearSpaceId ? null : (spaceId ?? this.spaceId),
      isWatched: isWatched ?? this.isWatched,
      isTopMind: isTopMind ?? this.isTopMind,
      dominantColorHex: dominantColorHex ?? this.dominantColorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'content': content,
      'thumbnailUrl': thumbnailUrl,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'type': type.name,
      'tags': tags,
      'spaceId': spaceId,
      'isWatched': isWatched,
      'isTopMind': isTopMind,
      'dominantColorHex': dominantColorHex,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced,
    };
  }

  factory MindItem.fromMap(Map<dynamic, dynamic> map) {
    return MindItem(
      id: map['id'] as String,
      title: _asString(map['title']) ?? 'Untitled',
      url: _asString(map['url']),
      content: _asString(map['content']),
      thumbnailUrl: _asString(map['thumbnailUrl']),
      authorName: _asString(map['authorName']),
      authorAvatar: _asString(map['authorAvatar']),
      type: ItemType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ItemType.webArticle,
      ),
      tags: _asTags(map['tags']),
      spaceId: _asString(map['spaceId']),
      isWatched: _asBool(map['isWatched']),
      isTopMind: _asBool(map['isTopMind']),
      dominantColorHex: _asString(map['dominantColorHex']),
      createdAt: _parseTimestamp(map['createdAt']) ?? _fallbackCreatedAt,
      updatedAt: _parseTimestamp(map['updatedAt']) ??
          _parseTimestamp(map['createdAt']) ??
          _fallbackCreatedAt,
      isSynced: _asBool(map['isSynced']),
    );
  }

  /// Field readers that never throw.
  ///
  /// The same reasoning as [_parseTimestamp]: a cast failure on any one field
  /// used to take the whole item down, and every caller treats a failed
  /// [fromMap] as "this item does not exist". A single bad `tags` value - a
  /// String instead of a List, a null entry, a bool where a String was
  /// expected - therefore removed the card from the feed *and* from sync, and
  /// the corrupt record stayed on disk, so it never came back. One wrong field
  /// must cost that field, not the memory.
  static String? _asString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    if (value is num) return value != 0;
    return false;
  }

  static List<String> _asTags(Object? value) {
    if (value is Iterable) {
      return value
          .map(_asString)
          .whereType<String>()
          .where((tag) => tag.trim().isNotEmpty)
          .toList();
    }
    // A single tag stored as a bare string (an old export, or a hand-edited
    // backup) is still a tag.
    final single = _asString(value);
    if (single != null && single.trim().isNotEmpty) return [single];
    return const [];
  }

  /// Never throws. A single malformed timestamp used to make [fromMap] fail,
  /// and callers treat a failed parse as "this item does not exist": the card
  /// disappeared from the feed *and* from sync, and the next cloud pull happily
  /// overwrote the copy that was still on disk. Keeping the item with a
  /// best-effort date is always better than losing it.
  static DateTime? _parseTimestamp(Object? raw) {
    if (raw is DateTime) return raw;
    final text = raw is String ? raw : null;
    final millis =
        raw is int ? raw : (text == null ? null : int.tryParse(text.trim()));
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    final parsed = text == null ? null : DateTime.tryParse(text);
    if (parsed != null) return parsed;
    if (text != null) {
      debugPrint('KeepIt: unreadable timestamp "$text" — using epoch fallback');
    }
    return null;
  }

  static final DateTime _fallbackCreatedAt =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
