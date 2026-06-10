import '../../models/legal_category.dart';

const mockCategories = [
  LegalCategory(
    id: 'divorcio',
    emoji: '👨‍👩‍👧',
    title: 'Divórcio',
    isGold: false,
  ),
  LegalCategory(
    id: 'pensao',
    emoji: '👶',
    title: 'Pensão\nAlimentícia',
    isGold: true,
  ),
  LegalCategory(
    id: 'trabalhista',
    emoji: '💼',
    title: 'Trabalhista',
    isGold: false,
  ),
  LegalCategory(
    id: 'imobiliario',
    emoji: '🏠',
    title: 'Imobiliário',
    isGold: true,
  ),
  LegalCategory(
    id: 'acidente',
    emoji: '🚗',
    title: 'Acidente de\nTrânsito',
    isGold: false,
  ),
  LegalCategory(
    id: 'consumidor',
    emoji: '🛒',
    title: 'Direito do\nConsumidor',
    isGold: true,
  ),
];
