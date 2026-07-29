import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/validators.dart';

void main() {
  group('isValidCpf', () {
    test('aceita CPFs com dígitos verificadores corretos', () {
      expect(isValidCpf('529.982.247-25'), isTrue);
      expect(isValidCpf('52998224725'), isTrue);
      expect(isValidCpf('111.444.777-35'), isTrue);
    });

    test('rejeita dígitos verificadores errados', () {
      expect(isValidCpf('529.982.247-24'), isFalse);
      expect(isValidCpf('111.444.777-34'), isFalse);
      expect(isValidCpf('123.456.789-01'), isFalse);
    });

    test('rejeita sequências repetidas mesmo com dígitos válidos', () {
      expect(isValidCpf('000.000.000-00'), isFalse);
      expect(isValidCpf('111.111.111-11'), isFalse);
      expect(isValidCpf('99999999999'), isFalse);
    });

    test('rejeita tamanhos errados e vazio', () {
      expect(isValidCpf(''), isFalse);
      expect(isValidCpf('1234567890'), isFalse);
      expect(isValidCpf('123456789012'), isFalse);
    });
  });

  group('isValidCnj', () {
    test('aceita números reais com e sem máscara', () {
      // Processos reais retornados pela API pública do DataJud (29/07/2026).
      expect(isValidCnj('0000842-67.2023.8.21.7000'), isTrue);
      expect(isValidCnj('00008426720238217000'), isTrue);
      expect(isValidCnj('50144802820258219000'), isTrue);
      expect(isValidCnj('0020731-06.2020.5.04.0252'), isTrue);
    });

    test('rejeita dígito verificador errado', () {
      expect(isValidCnj('00008426720238217001'), isFalse);
      expect(isValidCnj('0000842-68.2023.8.21.7000'), isFalse);
    });

    test('rejeita tamanhos errados e vazio', () {
      expect(isValidCnj(''), isFalse);
      expect(isValidCnj('123'), isFalse);
      expect(isValidCnj('000084267202382170001'), isFalse);
    });
  });

  group('validateCnjField', () {
    test('vazio pede o número; inválido explica o padrão', () {
      expect(validateCnjField(''), 'Informe o número do processo');
      expect(validateCnjField(null), 'Informe o número do processo');
      expect(validateCnjField('123'), contains('padrão'));
      expect(validateCnjField('0000842-67.2023.8.21.7000'), isNull);
    });
  });

  group('isValidEmail', () {
    test('aceita e-mails comuns', () {
      expect(isValidEmail('samuel@jurii.com.br'), isTrue);
      expect(isValidEmail('a.b-c+d@sub.dominio.co'), isTrue);
    });

    test('rejeita formatos que o validador antigo aceitava', () {
      expect(isValidEmail('a@b.'), isFalse);
      expect(isValidEmail('.@.'), isFalse);
      expect(isValidEmail('com espaco@x.com'), isFalse);
      expect(isValidEmail('semarroba.com'), isFalse);
    });
  });

  group('validatePasswordField', () {
    test('exige o mínimo unificado de $kMinPasswordLength caracteres', () {
      expect(validatePasswordField('1234567'), isNotNull);
      expect(validatePasswordField('12345678'), isNull);
      expect(validatePasswordField(''), isNotNull);
      expect(validatePasswordField(null), isNotNull);
    });
  });

  group('digitsOnly', () {
    test('remove máscara de CPF', () {
      expect(digitsOnly('529.982.247-25'), '52998224725');
    });
  });

  group('validateOptionalPhoneField', () {
    test('aceita vazio e telefones brasileiros com DDD', () {
      expect(validateOptionalPhoneField(''), isNull);
      expect(validateOptionalPhoneField('(51) 3333-4444'), isNull);
      expect(validateOptionalPhoneField('(51) 99999-8888'), isNull);
      expect(validateOptionalPhoneField('+55 (51) 99999-8888'), isNull);
    });

    test('rejeita telefone incompleto', () {
      expect(validateOptionalPhoneField('(51) 9999'), isNotNull);
    });
  });

  group('validateFullNameField', () {
    test('rejeita nome acima do limite compartilhado', () {
      final longName = 'Ana ${List.filled(kMaxFullNameCharacters, 'S').join()}';

      expect(
        validateFullNameField(longName),
        'Use no máximo $kMaxFullNameCharacters caracteres',
      );
    });
  });
}
