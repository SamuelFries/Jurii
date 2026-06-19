import 'law_firm_verification_document.dart';
import 'law_firm_verification_status.dart';

class LawFirmVerification {
  final String? id;
  final String ownerProfileId;
  final String? lawFirmId;
  final String firmName;
  final String cnpj;
  final String phone;
  final String email;
  final String address;
  final List<String> practiceAreas;
  final List<LawFirmVerificationDocument> documents;
  final LawFirmVerificationStatus status;
  final DateTime? reviewedAt;
  final String? reviewerId;
  final String? rejectionReason;

  const LawFirmVerification({
    this.id,
    required this.ownerProfileId,
    this.lawFirmId,
    required this.firmName,
    required this.cnpj,
    required this.phone,
    required this.email,
    required this.address,
    required this.practiceAreas,
    required this.documents,
    required this.status,
    this.reviewedAt,
    this.reviewerId,
    this.rejectionReason,
  });

  LawFirmVerification copyWith({
    String? id,
    String? ownerProfileId,
    String? lawFirmId,
    String? firmName,
    String? cnpj,
    String? phone,
    String? email,
    String? address,
    List<String>? practiceAreas,
    List<LawFirmVerificationDocument>? documents,
    LawFirmVerificationStatus? status,
    DateTime? reviewedAt,
    String? reviewerId,
    String? rejectionReason,
  }) {
    return LawFirmVerification(
      id: id ?? this.id,
      ownerProfileId: ownerProfileId ?? this.ownerProfileId,
      lawFirmId: lawFirmId ?? this.lawFirmId,
      firmName: firmName ?? this.firmName,
      cnpj: cnpj ?? this.cnpj,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      practiceAreas: practiceAreas ?? this.practiceAreas,
      documents: documents ?? this.documents,
      status: status ?? this.status,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewerId: reviewerId ?? this.reviewerId,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}
