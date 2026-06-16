class LawyerProfileSummary {
  final String id;
  final String name;
  final String initials;
  final String oabNumber;
  final String oabState;
  final String primaryArea;
  final List<String> practiceAreas;
  final String bio;
  final double rating;
  final int reviews;
  final String avatarType;

  const LawyerProfileSummary({
    required this.id,
    required this.name,
    required this.initials,
    required this.oabNumber,
    required this.oabState,
    required this.primaryArea,
    required this.practiceAreas,
    required this.bio,
    required this.rating,
    required this.reviews,
    required this.avatarType,
  });

  String get oabLabel => 'OAB/$oabState $oabNumber';
}
