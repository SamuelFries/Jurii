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
}
