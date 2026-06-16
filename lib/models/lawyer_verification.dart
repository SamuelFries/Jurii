import 'lawyer_status.dart';
import 'verification_document.dart';

class LawyerVerification {
  final String userId;
  final String oabNumber;
  final String oabState;
  final String practiceArea;
  final List<String> practiceAreas;
  final List<VerificationDocument> documents;
  final LawyerStatus status;

  const LawyerVerification({
    required this.userId,
    required this.oabNumber,
    required this.oabState,
    required this.practiceArea,
    required this.practiceAreas,
    required this.documents,
    required this.status,
  });
}
