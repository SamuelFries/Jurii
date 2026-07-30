import 'package:flutter/services.dart';

/// Máscara do número de processo CNJ (0000000-00.0000.0.00.0000). O valor
/// enviado ao banco continua sendo só os 20 dígitos (ver [digitsOnly]);
/// número mascarado quebraria a consulta ao DataJud e o dígito verificador.
class CnjInputFormatter extends TextInputFormatter {
  const CnjInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formattedCnj = formatCnj(newValue.text);
    return TextEditingValue(
      text: formattedCnj,
      selection: TextSelection.collapsed(offset: formattedCnj.length),
    );
  }
}

String formatCnj(String value) {
  final rawDigits = value.replaceAll(RegExp(r'\D'), '');
  final digits = rawDigits.length > 20 ? rawDigits.substring(0, 20) : rawDigits;
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index == 7) {
      buffer.write('-');
    } else if (index == 9 || index == 13 || index == 14 || index == 16) {
      buffer.write('.');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
