import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/firm_profile_form.dart';

FirmProfileDraft _draft({
  String name = 'Firma',
  String phone = '5133334444',
  String email = 'c@x.com',
  String websiteUrl = '',
  String address = 'Rua 1',
  String cep = '90000000',
  String primaryArea = 'Direito Cível',
  List<String> practiceAreas = const ['Direito Cível'],
  bool hasNewLogo = false,
  bool removeLogo = false,
}) => FirmProfileDraft(
  name: name,
  phone: phone,
  email: email,
  websiteUrl: websiteUrl,
  address: address,
  cep: cep,
  primaryArea: primaryArea,
  practiceAreas: practiceAreas,
  hasNewLogo: hasNewLogo,
  removeLogo: removeLogo,
);

void main() {
  group('endereço do site', () {
    test('ganha esquema quando falta', () {
      // Sem esquema a URL não abre: vira busca no navegador, ou nada.
      expect(normalizeWebsiteUrl('weber.com.br'), 'https://weber.com.br');
    });

    test('não mexe no que já tem esquema', () {
      expect(normalizeWebsiteUrl('http://a.com'), 'http://a.com');
      expect(normalizeWebsiteUrl('https://a.com'), 'https://a.com');
    });

    test('vazio vira nulo, e não "https://"', () {
      expect(normalizeWebsiteUrl(''), isNull);
      expect(normalizeWebsiteUrl('   '), isNull);
      expect(normalizeWebsiteUrl(null), isNull);
    });
  });

  group('o que conta como alteração', () {
    test('nada mudou', () {
      expect(_draft().matches(_draft()), isTrue);
    });

    test('só espaço em volta não é alteração', () {
      // Salvar por causa de um espaço reescreveria o cartão da descoberta à
      // toa.
      expect(_draft(name: '  Firma  ').matches(_draft()), isTrue);
    });

    test('máscara do telefone não é alteração', () {
      expect(
        _draft(phone: '(51) 3333-4444').matches(_draft()),
        isTrue,
        reason: 'o campo é mascarado, mas o valor é o mesmo',
      );
    });

    test('maiúscula no e-mail não é alteração', () {
      expect(_draft(email: 'C@X.COM').matches(_draft()), isTrue);
    });

    test('site sem esquema é o mesmo do site com esquema', () {
      final original = _draft(websiteUrl: 'https://a.com');
      expect(_draft(websiteUrl: 'a.com').matches(original), isTrue);
    });

    test('ordem das áreas não é alteração', () {
      final original = _draft(practiceAreas: const ['A', 'B']);
      expect(_draft(practiceAreas: const ['B', 'A']).matches(original), isTrue);
    });

    test('área a mais É alteração', () {
      final original = _draft(practiceAreas: const ['A']);
      expect(
        _draft(practiceAreas: const ['A', 'B']).matches(original),
        isFalse,
      );
    });

    test('logo novo é alteração mesmo com todo o resto igual', () {
      expect(_draft(hasNewLogo: true).matches(_draft()), isFalse);
    });

    test('remover o logo é alteração', () {
      expect(_draft(removeLogo: true).matches(_draft()), isFalse);
    });

    test('nome diferente é alteração', () {
      expect(_draft(name: 'Outra').matches(_draft()), isFalse);
    });
  });
}
