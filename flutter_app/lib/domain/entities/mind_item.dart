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
      title: map['title'] as String? ?? 'Untitled',
      url: map['url'] as String?,
      content: map['content'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      authorName: map['authorName'] as String?,
      authorAvatar: map['authorAvatar'] as String?,
      type: ItemType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ItemType.webArticle,
      ),
      tags: List<String>.from(map['tags'] ?? []),
      spaceId: map['spaceId'] as String?,
      isWatched: map['isWatched'] as bool? ?? false,
      isTopMind: map['isTopMind'] as bool? ?? false,
      dominantColorHex: map['dominantColorHex'] as String?,
      createdAt: _parseTimestamp(map['createdAt']) ?? _fallbackCreatedAt,
      updatedAt: _parseTimestamp(map['updatedAt']) ??
          _parseTimestamp(map['createdAt']) ??
          _fallbackCreatedAt,
      isSynced: map['isSynced'] as bool? ?? false,
    );
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
