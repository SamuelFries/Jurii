import 'package:flutter/services.dart';

/// Máscara de CPF (000.000.000-00) compartilhada pelo cadastro e pela tela de
/// completar perfil. O valor enviado ao banco continua sendo só os 11 dígitos
/// (ver [digitsOnly]) — CPF mascarado quebraria comparação e deduplicação.
class CpfInputFormatter extends TextInputFormatter {
  const CpfInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formattedCpf = formatCpf(newValue.text);
    return TextEditingValue(
      text: formattedCpf,
      selection: TextSelection.collapsed(offset: formattedCpf.length),
    );
  }
}

String formatCpf(String value) {
  final rawDigits = value.replaceAll(RegExp(r'\D'), '');
  final digits = rawDigits.length > 11 ? rawDigits.substring(0, 11) : rawDigits;
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index == 3 || index == 6) {
      buffer.write('.');
    } else if (index == 9) {
      buffer.write('-');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
