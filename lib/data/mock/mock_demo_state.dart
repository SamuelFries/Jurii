import '../../models/law_firm_verification.dart';
import '../../models/law_firm_verification_status.dart';
import '../../models/lawyer_status.dart';
import '../../models/lawyer_verification.dart';
import 'mock_documents.dart';
import 'mock_law_firm_verification.dart';

final mockApprovedLawyerVerification = LawyerVerification(
  userId: 'user_joao_silva',
  oabNumber: '123456',
  oabState: 'SP',
  practiceArea: 'Direito Trabalhista',
  practiceAreas: const [
    'Direito Trabalhista',
    'Direito de Familia',
    'Direito do Consumidor',
    'Direito Digital',
  ],
  documents: mockRequiredVerificationDocuments
      .map((document) => document.copyWith(uploaded: true))
      .toList(),
  status: LawyerStatus.approved,
);

final mockApprovedLawFirmVerification = LawFirmVerification(
  id: 'firm_verification_demo',
  ownerProfileId: 'user_joao_silva',
  lawFirmId: 'fries',
  firmName: 'Fries Advogados',
  cnpj: '12.345.678/0001-90',
  phone: '(11) 4002-8922',
  email: 'contato@friesadvogados.com.br',
  address: 'Av. Paulista, 1374 - Sao Paulo, SP',
  practiceAreas: const [
    'Direito Trabalhista',
    'Direito de Familia',
    'Direito Imobiliário',
    'Direito Empresarial',
    'Direito Digital',
  ],
  documents: mockRequiredLawFirmVerificationDocuments
      .map((document) => document.copyWith(uploaded: true))
      .toList(),
  status: LawFirmVerificationStatus.approved,
  reviewedAt: DateTime(2026, 6, 20, 14, 30),
  reviewerId: 'admin_demo',
);
