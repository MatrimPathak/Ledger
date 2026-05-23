import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final String currency;
  final bool onboardingComplete;
  final DateTime createdAt;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.currency = 'INR',
    this.onboardingComplete = false,
    required this.createdAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      currency: data['currency'] ?? 'INR',
      onboardingComplete: data['onboardingComplete'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'currency': currency,
        'onboardingComplete': onboardingComplete,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  UserProfile copyWith({
    String? name,
    String? email,
    String? photoUrl,
    String? currency,
    bool? onboardingComplete,
  }) =>
      UserProfile(
        uid: uid,
        name: name ?? this.name,
        email: email ?? this.email,
        photoUrl: photoUrl ?? this.photoUrl,
        currency: currency ?? this.currency,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        createdAt: createdAt,
      );
}
