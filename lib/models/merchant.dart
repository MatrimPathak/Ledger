import 'package:cloud_firestore/cloud_firestore.dart';

/// A normalized merchant (e.g. "Uber"), inferred from transactions but
/// always user-correctable. Deliberately thin: [aliasPatterns] is read-only
/// evidence used by the correlation engine's scoring, never a permanent
/// payee-to-merchant lookup table (a UPI counterparty like a driver's name
/// changes every ride, so no alias is ever auto-applied).
class Merchant {
  final String id;
  final String userId;
  final String displayName;
  final String normalizedKey;
  final String? defaultCategoryId;
  final List<String> aliasPatterns;
  final DateTime createdAt;

  static const int maxAliasPatterns = 20;

  const Merchant({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.normalizedKey,
    this.defaultCategoryId,
    this.aliasPatterns = const [],
    required this.createdAt,
  });

  /// Lowercased, punctuation-stripped key used for exact/near matching.
  static String normalize(String name) {
    final lower = name.toLowerCase().trim();
    final stripped = lower.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  factory Merchant.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Merchant(
      id: doc.id,
      userId: data['userId'] ?? '',
      displayName: data['displayName'] ?? '',
      normalizedKey: data['normalizedKey'] ?? '',
      defaultCategoryId: data['defaultCategoryId'],
      aliasPatterns: (data['aliasPatterns'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'displayName': displayName,
        'normalizedKey': normalizedKey,
        'defaultCategoryId': defaultCategoryId,
        'aliasPatterns': aliasPatterns,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  /// Appends [alias], evicting the oldest entry once [maxAliasPatterns] is
  /// exceeded so the list can never grow into a full payee history.
  Merchant withAlias(String alias) {
    if (aliasPatterns.contains(alias)) return this;
    final updated = [...aliasPatterns, alias];
    final bounded = updated.length > maxAliasPatterns
        ? updated.sublist(updated.length - maxAliasPatterns)
        : updated;
    return Merchant(
      id: id,
      userId: userId,
      displayName: displayName,
      normalizedKey: normalizedKey,
      defaultCategoryId: defaultCategoryId,
      aliasPatterns: bounded,
      createdAt: createdAt,
    );
  }

  Merchant copyWith({
    String? displayName,
    String? normalizedKey,
    String? Function()? defaultCategoryId,
  }) =>
      Merchant(
        id: id,
        userId: userId,
        displayName: displayName ?? this.displayName,
        normalizedKey: normalizedKey ?? this.normalizedKey,
        defaultCategoryId: defaultCategoryId != null
            ? defaultCategoryId()
            : this.defaultCategoryId,
        aliasPatterns: aliasPatterns,
        createdAt: createdAt,
      );
}
