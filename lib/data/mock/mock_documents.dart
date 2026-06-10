import '../../models/verification_document.dart';

const mockRequiredVerificationDocuments = [
  VerificationDocument(
    id: 'identity',
    type: VerificationDocumentType.identity,
    title: 'Documento de identificação',
    subtitle: 'RG ou CNH',
  ),
  VerificationDocument(
    id: 'oab_card',
    type: VerificationDocumentType.oabCard,
    title: 'Carteira da OAB',
    subtitle: 'Documento profissional oficial',
  ),
  VerificationDocument(
    id: 'professional_photo',
    type: VerificationDocumentType.professionalPhoto,
    title: 'Foto profissional',
    subtitle: 'Imagem exibida no perfil',
  ),
];
