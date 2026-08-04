import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/cnj_input_formatter.dart';

TextEditingValue _format(String text) {
  const formatter = CnjInputFormatter();
  return formatter.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: text),
  );
}

void main() {
  group('formatCnj', () {
    test('aplica a máscara completa NNNNNNN-DD.AAAA.J.TR.OOOO', () {
      expect(formatCnj('00008426720238217000'), '0000842-67.2023.8.21.7000');
    });

    test('formata progressivamente enquanto digita', () {
      expect(formatCnj('0000842'), '0000842');
      expect(formatCnj('00008426'), '0000842-6');
      expect(formatCnj('000084267'), '0000842-67');
      expect(formatCnj('0000842672023'), '0000842-67.2023');
      expect(formatCnj('00008426720238'), '0000842-67.2023.8');
      expect(formatCnj('0000842672023821'), '0000842-67.2023.8.21');
      expect(formatCnj('00008426720238217'), '0000842-67.2023.8.21.7');
    });

    test('descarta excedente e caracteres não numéricos', () {
      expect(
        formatCnj('000084267202382170009999'),
        '0000842-67.2023.8.21.7000',
      );
      expect(formatCnj('abc0000842xyz67'), '0000842-67');
    });
  });

  group('CnjInputFormatter', () {
    test('reformata o valor digitado e posiciona o cursor no fim', () {
      final result = _format('00008426720238217000');
      expect(result.text, '0000842-67.2023.8.21.7000');
      expect(result.selection.baseOffset, result.text.length);
    });
  });
}
