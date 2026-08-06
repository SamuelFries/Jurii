import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/models/lawyer_profile_summary.dart';

void main() {
  test('selo e vaga paga sao campos DIFERENTES', () {
    // is_featured (selo) não tem teto: quem paga é identificado sempre.
    // is_sponsored_slot são no máximo 2 por lista. Confundir os dois faz a
    // medição atribuir à vaga uma impressão que ela não entregou — inflando o
    // número que justifica a renovação do patrocínio.
    const patrocinadoForaDaVaga = LawyerProfileSummary(
      id: 'l1',
      name: 'Advogada',
      initials: 'A',
      oabNumber: '123456',
      oabState: 'RS',
      primaryArea: 'Direito Tributário',
      practiceAreas: ['Direito Tributário'],
      bio: 'bio',
      rating: 5,
      reviews: 0,
      avatarType: 'navy',
      isFeatured: true,
    );

    expect(patrocinadoForaDaVaga.isFeatured, isTrue);
    expect(
      patrocinadoForaDaVaga.isSponsoredSlot,
      isFalse,
      reason: 'ter patrocínio ativo não é ter ocupado a vaga',
    );
  });

  test('escritorio tem os dois campos, com o mesmo default seguro', () {
    const firma = LawFirm(
      id: 'f1',
      name: 'Escritório',
      initials: 'E',
      rating: 5,
      distance: '1 km',
      specialty: 'Civil',
      practiceAreas: ['Civil'],
      reviews: 0,
      avatarType: 'navy',
      isFeatured: true,
    );

    expect(firma.isFeatured, isTrue);
    expect(firma.isSponsoredSlot, isFalse);
  });
}
