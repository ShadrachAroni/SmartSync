import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? profileImageUrl;
  final List<String> deviceIds;
  final DateTime createdAt;
  final Map<String, dynamic> preferences;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phoneNumber,
    this.profileImageUrl,
    this.deviceIds = const [],
    required this.createdAt,
    this.preferences = const {},
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'],
      profileImageUrl: data['profileImageUrl'],
      deviceIds: List<String>.from(data['deviceIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      preferences: data['preferences'] ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'profileImageUrl': profileImageUrl,
      'deviceIds': deviceIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'preferences': preferences,
    };
  }
}
