import '../../models/legal_category.dart';

/// Espelho do conjunto canônico de legal_categories (migration
/// 20260825120000), usado no modo demo e como placeholder instantâneo
/// enquanto o fetch real não chega. Divergir daqui troca o cartão debaixo do
/// dedo da pessoa quando o fetch chega; a ordem e os títulos têm que bater.
///
/// Rótulo fala a língua de quem tem o problema, não a do jurista, porque o
/// toque manda o TÍTULO para a caixa de busca. Todo título tem que pescar a
/// própria practice_area pelas regras de intenção; a barreira é
/// test/categorias_populares_test.dart.
const mockCategories = [
  LegalCategory(
    id: 'trabalhista',
    title: 'Trabalhista',
    iconName: 'work_outline',
    practiceArea: 'Direito Trabalhista',
  ),
  LegalCategory(
    id: 'previdenciario',
    title: 'INSS e Aposentadoria',
    iconName: 'elderly_outlined',
    practiceArea: 'Direito Previdenciário',
  ),
  LegalCategory(
    id: 'divorcio-familia',
    title: 'Divórcio e Pensão',
    iconName: 'family_restroom',
    practiceArea: 'Direito de Família',
  ),
  LegalCategory(
    id: 'acidente-transito',
    title: 'Acidente e Indenização',
    iconName: 'directions_car_outlined',
    practiceArea: 'Direito Cível',
  ),
  LegalCategory(
    id: 'consumidor',
    title: 'Consumidor',
    iconName: 'shopping_bag_outlined',
    practiceArea: 'Direito do Consumidor',
  ),
  LegalCategory(
    id: 'dividas-e-banco',
    title: 'Dívidas e Banco',
    iconName: 'account_balance_outlined',
    practiceArea: 'Direito Bancário',
  ),
  LegalCategory(
    id: 'imobiliario',
    title: 'Aluguel e Imóvel',
    iconName: 'home_outlined',
    practiceArea: 'Direito Imobiliário',
  ),
  LegalCategory(
    id: 'inventario-heranca',
    title: 'Inventário e Herança',
    iconName: 'balance_outlined',
    practiceArea: 'Direito das Sucessões',
  ),
  // Direito Criminal tinha 12 de oferta cadastrada e porta nenhuma: é a
  // urgência mais alta que o app recebe (flagrante, medida protetiva).
  // Entrou no lugar de Plano de Saúde, a prateleira mais rala do app
  // (1 advogado, 2 escritórios), que continua alcançável pela busca livre.
  LegalCategory(
    id: 'crime-agressao',
    title: 'Crime ou Agressão',
    iconName: 'shield_outlined',
    practiceArea: 'Direito Criminal',
  ),
];
