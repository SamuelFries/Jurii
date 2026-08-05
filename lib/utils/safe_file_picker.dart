import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Arquivo escolhido SEM os bytes em memória: nome e tamanho vêm do seletor,
/// e [readBytes] só deve ser chamado depois da checagem de tamanho — um
/// vídeo de 800 MB escolhido por engano não pode virar OOM.
class SafePickedFile {
  const SafePickedFile._(this._file);

  final PlatformFile _file;

  String get name => _file.name;
  int get size => _file.size;

  /// Caminho no disco. Só serve onde ele existe de verdade (celular); na web
  /// o seletor devolve uma referência de blob, e quem precisa de caminho —
  /// hoje, só o compressor de vídeo — não roda lá.
  String get path => _file.xFile.path;

  Future<Uint8List> readBytes() => _file.xFile.readAsBytes();
}

/// Abre o seletor para um único arquivo. Retorna null quando o usuário
/// cancela. Erros do seletor (permissão negada, plugin) SOBEM para quem
/// chama mostrar a orientação certa — antes, permissão negada era um toque
/// sem nenhuma resposta.
Future<SafePickedFile?> pickSingleFile({
  required List<String> allowedExtensions,
}) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowMultiple: false,
    allowedExtensions: allowedExtensions,
  );
  final file = picked?.files.single;
  if (file == null) return null;
  return SafePickedFile._(file);
}

/// Lê os bytes tolerando falha (retorna null): os validadores de documento
/// já têm a mensagem certa para "não foi possível ler o arquivo".
Future<Uint8List?> readPickedBytesOrNull(SafePickedFile file) async {
  try {
    return await file.readBytes();
  } catch (_) {
    return null;
  }
}
