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
      spaceId: spaceId ?? this.spaceId,
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
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isSynced: map['isSynced'] as bool? ?? false,
    );
  }
}
