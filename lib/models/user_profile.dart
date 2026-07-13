import 'lawyer_status.dart';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String initials;
  final String memberSince;
  final String? oabNumber;
  final LawyerStatus lawyerStatus;
  final String? avatarUrl;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.initials,
    required this.memberSince,
    required this.lawyerStatus,
    this.oabNumber,
    this.avatarUrl,
  });

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? initials,
    String? memberSince,
    String? oabNumber,
    LawyerStatus? lawyerStatus,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      initials: initials ?? this.initials,
      memberSince: memberSince ?? this.memberSince,
      oabNumber: oabNumber ?? this.oabNumber,
      lawyerStatus: lawyerStatus ?? this.lawyerStatus,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
