enum LawFirmVerificationDocumentType {
  cnpjRegistration,
  articlesOfAssociation,
  addressProof,
  ownerIdentity,
}

class LawFirmVerificationDocument {
  final String id;
  final LawFirmVerificationDocumentType type;
  final String title;
  final String subtitle;
  final bool uploaded;

  const LawFirmVerificationDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.uploaded = false,
  });

  LawFirmVerificationDocument copyWith({
    String? id,
    LawFirmVerificationDocumentType? type,
    String? title,
    String? subtitle,
    bool? uploaded,
  }) {
    return LawFirmVerificationDocument(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      uploaded: uploaded ?? this.uploaded,
    );
  }
}
