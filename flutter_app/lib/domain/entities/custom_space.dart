import 'package:material_ui/material_ui.dart';

/// A user-created Space. The icon is stored by a stable name instead of an
/// IconData object so it survives Hive/Firestore/export round trips.
class CustomSpace {
  final String id;
  final String name;
  final int colorValue;
  final String iconName;

  /// When this Space was last changed on this device, in UTC.
  ///
  /// Cloud sync reconciles Spaces with last-write-wins on this value, exactly
  /// as it does items on `MindItem.updatedAt`. Spaces created before sync
  /// existed have no stored timestamp and read back as the epoch — which is
  /// the truth: nothing is known about when they were written, so any real
  /// timestamp from another device should win.
  final DateTime? updatedAt;

  /// False until the cloud has a copy of this Space.
  final bool isSynced;

  const CustomSpace({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconName,
    this.updatedAt,
    this.isSynced = false,
  });

  Color get color => Color(colorValue);

  /// The timestamp to reconcile with, defaulting to the epoch for Spaces saved
  /// before sync existed.
  DateTime get effectiveUpdatedAt =>
      updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  CustomSpace copyWith({
    String? id,
    String? name,
    int? colorValue,
    String? iconName,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return CustomSpace(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconName: iconName ?? this.iconName,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconName': iconName,
        'updatedAt': effectiveUpdatedAt.toIso8601String(),
        'isSynced': isSynced,
      };

  factory CustomSpace.fromMap(Map<dynamic, dynamic> map) {
    final name = (map['name'] as String? ?? '').trim();
    if (name.isEmpty) throw const FormatException('Space name is empty');
    return CustomSpace(
      id: map['id'] as String? ?? name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      colorValue: (map['colorValue'] as num?)?.toInt() ?? 0xFFFF5B37,
      iconName: map['iconName'] as String? ?? 'folder',
      updatedAt: _parseTimestamp(map['updatedAt']),
      isSynced: map['isSynced'] == true,
    );
  }

  /// Never throws. A Space with an unreadable date is still a Space; it just
  /// sorts as the oldest possible version instead of disappearing from the
  /// user's library.
  static DateTime? _parseTimestamp(Object? raw) {
    if (raw is DateTime) return raw.toUtc();
    final millis = raw is int ? raw : null;
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    if (raw is String) return DateTime.tryParse(raw)?.toUtc();
    return null;
  }
}
