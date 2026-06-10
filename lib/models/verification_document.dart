enum VerificationDocumentType { identity, oabCard, professionalPhoto }

class VerificationDocument {
  final String id;
  final VerificationDocumentType type;
  final String title;
  final String subtitle;
  final bool uploaded;

  const VerificationDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.uploaded = false,
  });

  VerificationDocument copyWith({
    String? id,
    VerificationDocumentType? type,
    String? title,
    String? subtitle,
    bool? uploaded,
  }) {
    return VerificationDocument(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      uploaded: uploaded ?? this.uploaded,
    );
  }
}
