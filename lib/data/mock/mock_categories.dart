import '../../models/legal_category.dart';

const mockCategories = [
  LegalCategory(id: 'divorcio', title: 'Divórcio', isGold: false),
  LegalCategory(id: 'pensao', title: 'Pensão\nAlimentícia', isGold: true),
  LegalCategory(id: 'trabalhista', title: 'Trabalhista', isGold: false),
  LegalCategory(id: 'imobiliario', title: 'Imobiliário', isGold: true),
  LegalCategory(id: 'acidente', title: 'Acidente de\nTrânsito', isGold: false),
  LegalCategory(
    id: 'consumidor',
    title: 'Direito do\nConsumidor',
    isGold: true,
  ),
];
