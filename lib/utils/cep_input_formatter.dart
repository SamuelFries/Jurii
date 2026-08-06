import 'package:flutter/services.dart';

/// Máscara de CEP: `00000-000`.
///
/// Era uma classe privada dentro do formulário de cadastro do escritório.
/// Virou util quando a tela de edição precisou da mesma máscara — duas cópias
/// divergiriam no primeiro ajuste, e o campo de CEP aparece nos dois lugares
/// que alimentam a mesma coluna.
class CepInputFormatter extends TextInputFormatter {
  const CepInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;

    final buffer = StringBuffer();
    for (var index = 0; index < limited.length; index++) {
      if (index == 5) buffer.write('-');
      buffer.write(limited[index]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
