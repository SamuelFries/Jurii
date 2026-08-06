import 'package:flutter/services.dart';

/// Máscara de CNPJ: `00.000.000/0000-00`.
///
/// A formatação vive numa função pura porque dois lugares precisam dela por
/// motivos diferentes: o cadastro, enquanto a pessoa digita, e a edição, que
/// só EXIBE o CNPJ já verificado — lá não há entrada para formatar.
String formatCnpj(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  final limited = digits.length > 14 ? digits.substring(0, 14) : digits;

  final buffer = StringBuffer();
  for (var index = 0; index < limited.length; index++) {
    if (index == 2 || index == 5) {
      buffer.write('.');
    } else if (index == 8) {
      buffer.write('/');
    } else if (index == 12) {
      buffer.write('-');
    }
    buffer.write(limited[index]);
  }
  return buffer.toString();
}

class CnpjInputFormatter extends TextInputFormatter {
  const CnpjInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatCnpj(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
