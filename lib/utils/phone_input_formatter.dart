import 'package:flutter/services.dart';

import 'validators.dart';

const int maxBrazilianPhoneDigits = 11;
const int maxFormattedBrazilianPhoneCharacters = 15;

/// Formata telefone brasileiro como `(00) 0000-0000` ou `(00) 00000-0000`.
/// O prefixo internacional `+55`, comum no autofill do celular, é removido
/// antes da máscara para não transformar o código do país em DDD.
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = normalizeBrazilianPhoneDigits(newValue.text);
    if (digits.length > maxBrazilianPhoneDigits) {
      // Mantém o valor anterior: uma colagem gigante não causa overflow nem
      // vira silenciosamente outro telefone válido por truncamento.
      return oldValue;
    }

    final formatted = formatPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String formatPhone(String value) {
  final normalizedDigits = normalizeBrazilianPhoneDigits(value);
  final digits = normalizedDigits.length > maxBrazilianPhoneDigits
      ? normalizedDigits.substring(0, maxBrazilianPhoneDigits)
      : normalizedDigits;
  if (digits.isEmpty) return '';

  final buffer = StringBuffer('(');
  for (var index = 0; index < digits.length; index++) {
    if (index == 2) {
      buffer.write(') ');
    }
    final hyphenIndex = digits.length > 10 ? 7 : 6;
    if (index == hyphenIndex) {
      buffer.write('-');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String normalizeBrazilianPhoneDigits(String value) {
  final digits = digitsOnly(value);
  if ((digits.length == 12 || digits.length == 13) && digits.startsWith('55')) {
    return digits.substring(2);
  }
  return digits;
}
