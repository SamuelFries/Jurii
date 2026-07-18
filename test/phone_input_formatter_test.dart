import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/phone_input_formatter.dart';

void main() {
  test('formata telefone fixo e celular com DDD', () {
    expect(formatPhone('5133334444'), '(51) 3333-4444');
    expect(formatPhone('51999998888'), '(51) 99999-8888');
  });

  test('remove +55 antes de formatar telefone do autofill', () {
    expect(formatPhone('+55 (51) 99999-8888'), '(51) 99999-8888');
    expect(normalizeBrazilianPhoneDigits('+55 51 99999-8888'), '51999998888');
  });

  test('ignora dígitos excedentes sem alterar o telefone anterior', () {
    const formatter = PhoneInputFormatter();
    const oldValue = TextEditingValue(
      text: '(51) 99999-8888',
      selection: TextSelection.collapsed(offset: 15),
    );

    final result = formatter.formatEditUpdate(
      oldValue,
      const TextEditingValue(text: '44519999988881234567890'),
    );

    expect(result, oldValue);
    expect(result.text.length, lessThanOrEqualTo(15));
  });

  test('formatter reposiciona o cursor ao final da máscara', () {
    const formatter = PhoneInputFormatter();
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '51999998888'),
    );

    expect(result.text, '(51) 99999-8888');
    expect(result.selection, const TextSelection.collapsed(offset: 15));
  });
}
