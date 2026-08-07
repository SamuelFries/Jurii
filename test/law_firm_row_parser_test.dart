import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/repositories/law_firm_repository.dart';

/// Uma linha de `law_firms` como o Supabase devolve — TODAS as colunas, que é
/// o que `select()` e `law_firms(*)` trazem.
Map<String, dynamic> _linhaCompleta() => {
  'id': 'f1',
  'name': 'Weber e Silva Advogados',
  'initials': 'WA',
  'specialty': 'Direito Trabalhista',
  'practice_areas': ['Direito Trabalhista', 'Direito Cível'],
  'description': 'Banca de família em Porto Alegre.',
  'rating': 4.8,
  'reviews_count': 12,
  'avatar_type': 'purple',
  'avatar_url': null,
  'phone': '5133334444',
  'email': 'contato@weber.com.br',
  'website_url': 'https://weber.com.br',
  'address': 'Av. Ipiranga, 100',
  'cep': '90160091',
  'latitude': -30.03,
  'longitude': -51.22,
  'is_active': true,
};

void main() {
  test('a linha de law_firms vira LawFirm SEM perder campo editável', () {
    // Existia um segundo parser em FirmWorkspaceRepality que lia só id, nome,
    // iniciais, rating, especialidade, áreas, reviews e avatar. Como é ele que
    // alimentava o formulário do lápis, o cadastro abria vazio nos campos
    // descartados — e ao salvar os vazios voltavam ao servidor como NULL:
    // corrigir o nome apagava telefone, endereço, CEP e a coordenada da
    // distância.
    final firma = LawFirmRepository.firmFromRow(_linhaCompleta());

    expect(firma.id, 'f1');
    expect(firma.name, 'Weber e Silva Advogados');
    expect(firma.initials, 'WA');
    expect(firma.specialty, 'Direito Trabalhista');
    expect(firma.practiceAreas, ['Direito Trabalhista', 'Direito Cível']);
    expect(firma.rating, 4.8);
    expect(firma.reviews, 12);
    expect(firma.avatarType, 'purple');

    // Os oito que o parser duplicado perdia:
    expect(firma.description, 'Banca de família em Porto Alegre.');
    expect(firma.phone, '5133334444');
    expect(firma.email, 'contato@weber.com.br');
    expect(firma.websiteUrl, 'https://weber.com.br');
    expect(firma.address, 'Av. Ipiranga, 100');
    expect(firma.cep, '90160091');
    expect(firma.latitude, -30.03);
    expect(firma.longitude, -51.22);
    expect(firma.hasCoordinates, isTrue);
  });

  test('nenhum outro repositório monta LawFirm a partir de uma linha', () {
    // Barreira estrutural, e não só de dado: o defeito não foi um campo
    // esquecido, foi um SEGUNDO parser da mesma tabela que divergiu do
    // primeiro. Enquanto houver um só, não há o que divergir.
    //
    // Se um dia fizer sentido montar LawFirm em outro lugar, o certo é
    // chamar LawFirmRepository.firmFromRow — não escrever outro construtor.
    final repositorios = Directory('lib/repositories')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('law_firm_repository.dart'));

    expect(repositorios, isNotEmpty, reason: 'não achei os repositórios');

    for (final arquivo in repositorios) {
      expect(
        arquivo.readAsStringSync(),
        isNot(contains('LawFirm(')),
        reason:
            '${arquivo.path} monta LawFirm à mão; use '
            'LawFirmRepository.firmFromRow para não perder campo de novo',
      );
    }
  });

  group('endereço montado para o cliente', () {
    LawFirm comEndereco({String? numero, String? complemento}) =>
        LawFirmRepository.firmFromRow({
          ..._linhaCompleta(),
          'address_number': numero,
          'address_complement': complemento,
        });

    test('número e complemento entram na mesma ordem, sempre', () {
      // O cliente precisa do número para CHEGAR. Cada escritório escrevia do
      // seu jeito dentro do texto livre — "70 - 1102", "n 70 sala 1102".
      expect(
        comEndereco(numero: '70', complemento: 'sala 1102').fullAddress,
        'Av. Ipiranga, 100, 70 - sala 1102',
      );
    });

    test('sem complemento, só o número', () {
      expect(comEndereco(numero: '70').fullAddress, 'Av. Ipiranga, 100, 70');
    });

    test('cadastro antigo não ganha vírgula pendurada', () {
      // Os 40 cadastros de produção já têm o número escrito dentro de
      // `address`. Compor de novo duplicaria; sem número, devolve intacto.
      expect(comEndereco().fullAddress, 'Av. Ipiranga, 100');
    });

    test('sem endereço nenhum devolve null, não string vazia', () {
      // O perfil público faz `fullAddress ?? "Atendimento remoto"`: string
      // vazia passaria pelo `??` e o cliente leria um espaço em branco.
      final semNada = LawFirmRepository.firmFromRow({
        ..._linhaCompleta(),
        'address': null,
        'address_number': '70',
      });
      expect(semNada.fullAddress, isNull);
    });

    test('só complemento também aparece', () {
      // "s/n, fundos" é endereço de verdade.
      expect(
        comEndereco(complemento: 'fundos').fullAddress,
        'Av. Ipiranga, 100, fundos',
      );
    });
  });
}
