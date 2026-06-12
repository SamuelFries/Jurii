import '../../models/law_firm_verification_document.dart';

const mockRequiredLawFirmVerificationDocuments = [
  LawFirmVerificationDocument(
    id: 'cnpj_registration',
    type: LawFirmVerificationDocumentType.cnpjRegistration,
    title: 'Cartão CNPJ',
    subtitle: 'Comprovante de inscrição da pessoa jurídica',
  ),
  LawFirmVerificationDocument(
    id: 'articles_of_association',
    type: LawFirmVerificationDocumentType.articlesOfAssociation,
    title: 'Contrato social',
    subtitle: 'Documento de constituição ou alteração vigente',
  ),
  LawFirmVerificationDocument(
    id: 'address_proof',
    type: LawFirmVerificationDocumentType.addressProof,
    title: 'Comprovante de endereço',
    subtitle: 'Documento recente do endereço do escritório',
  ),
  LawFirmVerificationDocument(
    id: 'owner_identity',
    type: LawFirmVerificationDocumentType.ownerIdentity,
    title: 'Documento do responsável',
    subtitle: 'RG, CNH ou documento oficial do titular',
  ),
];
