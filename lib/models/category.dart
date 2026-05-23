import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Category {
  final String id;
  final String userId;
  final String title;
  final int iconCodePoint;
  final int colorValue;
  final bool isDefault;
  final DateTime createdAt;

  const Category({
    required this.id,
    required this.userId,
    required this.title,
    required this.iconCodePoint,
    required this.colorValue,
    this.isDefault = false,
    required this.createdAt,
  });

  Color get color => Color(colorValue);
  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  factory Category.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Category(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      iconCodePoint: (data['iconCodePoint'] as num?)?.toInt() ?? Icons.more_horiz.codePoint,
      colorValue: (data['colorValue'] as num?)?.toInt() ?? 0xFF64748B,
      isDefault: data['isDefault'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'iconCodePoint': iconCodePoint,
        'colorValue': colorValue,
        'isDefault': isDefault,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  Category copyWith({
    String? title,
    int? iconCodePoint,
    int? colorValue,
  }) =>
      Category(
        id: id,
        userId: userId,
        title: title ?? this.title,
        iconCodePoint: iconCodePoint ?? this.iconCodePoint,
        colorValue: colorValue ?? this.colorValue,
        isDefault: isDefault,
        createdAt: createdAt,
      );
}
