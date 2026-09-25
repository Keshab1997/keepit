import 'package:flutter/material.dart';

/// A user-created Space. The icon is stored by a stable name instead of an
/// IconData object so it survives Hive/Firestore/export round trips.
class CustomSpace {
  final String id;
  final String name;
  final int colorValue;
  final String iconName;

  const CustomSpace({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconName,
  });

  Color get color => Color(colorValue);

  CustomSpace copyWith({
    String? name,
    int? colorValue,
    String? iconName,
  }) {
    return CustomSpace(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconName: iconName ?? this.iconName,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconName': iconName,
      };

  factory CustomSpace.fromMap(Map<dynamic, dynamic> map) {
    final name = (map['name'] as String? ?? '').trim();
    if (name.isEmpty) throw const FormatException('Space name is empty');
    return CustomSpace(
      id: map['id'] as String? ?? name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      colorValue: (map['colorValue'] as num?)?.toInt() ?? 0xFFFF5B37,
      iconName: map['iconName'] as String? ?? 'folder',
    );
  }
}
