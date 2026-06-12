class LawFirm {
  final String id;
  final String name;
  final String initials;
  final double rating;
  final String distance;
  final String specialty;
  final int reviews;
  final String avatarType;
  final String? description;
  final String? phone;
  final String? email;
  final String? websiteUrl;
  final String? address;

  const LawFirm({
    required this.id,
    required this.name,
    required this.initials,
    required this.rating,
    required this.distance,
    required this.specialty,
    required this.reviews,
    required this.avatarType,
    this.description,
    this.phone,
    this.email,
    this.websiteUrl,
    this.address,
  });
}
