import '../../models/lawyer_profile_summary.dart';

const mockRecommendedLawyers = [
  LawyerProfileSummary(
    id: 'lawyer_marina',
    name: 'Dra. Marina Jardim',
    initials: 'MJ',
    oabNumber: '123456',
    oabState: 'SP',
    primaryArea: 'Direito de Família',
    practiceAreas: [
      'Direito de Família',
      'Direito Cível',
    ],
    bio:
        'Atuação consultiva e contenciosa em divórcios, guarda, alimentos e acordos familiares.',
    rating: 4.9,
    reviews: 86,
    avatarType: 'gold',
  ),
  LawyerProfileSummary(
    id: 'lawyer_rafael',
    name: 'Dr. Rafael Lima',
    initials: 'RL',
    oabNumber: '654321',
    oabState: 'SP',
    primaryArea: 'Direito Trabalhista',
    practiceAreas: [
      'Direito Trabalhista',
      'Direito Empresarial',
    ],
    bio:
        'Especialista em rescisões, verbas trabalhistas, acordos e defesa em reclamações.',
    rating: 4.8,
    reviews: 74,
    avatarType: 'navy',
  ),
  LawyerProfileSummary(
    id: 'lawyer_luiza',
    name: 'Dra. Luiza Moura',
    initials: 'LM',
    oabNumber: '884422',
    oabState: 'RJ',
    primaryArea: 'Direito do Consumidor',
    practiceAreas: [
      'Direito do Consumidor',
      'Direito Digital',
    ],
    bio:
        'Atendimento focado em cobranças indevidas, contratos, garantias e conflitos com empresas.',
    rating: 4.7,
    reviews: 63,
    avatarType: 'blue',
  ),
];
