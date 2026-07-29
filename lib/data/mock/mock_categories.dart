import '../../models/legal_category.dart';

/// Espelho do conjunto canônico de legal_categories (migration
/// 20260726120000) — usado no modo demo e como placeholder instantâneo
/// enquanto o fetch real não chega.
const mockCategories = [
  LegalCategory(
    id: 'divorcio-familia',
    title: 'Divórcio e Família',
    iconName: 'family_restroom',
    practiceArea: 'Direito de Família',
  ),
  LegalCategory(
    id: 'trabalhista',
    title: 'Trabalhista',
    iconName: 'work_outline',
    practiceArea: 'Direito Trabalhista',
  ),
  LegalCategory(
    id: 'consumidor',
    title: 'Consumidor',
    iconName: 'shopping_bag_outlined',
    practiceArea: 'Direito do Consumidor',
  ),
  LegalCategory(
    id: 'imobiliario',
    title: 'Imobiliário',
    iconName: 'home_outlined',
    practiceArea: 'Direito Imobiliário',
  ),
  LegalCategory(
    id: 'previdenciario',
    title: 'Previdenciário',
    iconName: 'elderly_outlined',
    practiceArea: 'Direito Previdenciário',
  ),
  LegalCategory(
    id: 'acidente-transito',
    title: 'Acidente de Trânsito',
    iconName: 'directions_car_outlined',
    practiceArea: 'Direito Cível',
  ),
];
