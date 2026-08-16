import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/case_document.dart';
import '../repositories/case_document_repository.dart';
import '../theme/app_colors.dart';
import '../utils/document_file_validation.dart';
import '../utils/relative_time.dart';
import '../utils/safe_file_picker.dart';
import 'jurii_empty_state.dart';
import 'jurii_error_state.dart';
import 'jurii_motion.dart';

/// A seção de documentos do detalhe do caso.
///
/// Procuração, contrato, comprovante: o papel do caso mora aqui, visível para
/// os dois lados. As regras são do banco e a tela só as traduz — anexa quem é
/// do caso, todo mundo do caso lê, e REMOVE só quem subiu (por isso o botão
/// de remover só aparece nos itens `isMine`: não se oferece o que o servidor
/// vai negar).
///
/// Widget com fetch próprio, no mesmo padrão do plano no perfil: nenhuma
/// lista passa documentos por parâmetro, e a seção se vira sozinha.
class CaseDocumentsSection extends StatefulWidget {
  const CaseDocumentsSection({
    super.key,
    required this.caseId,
    this.repository = const CaseDocumentRepository(),
  });

  final String caseId;
  final CaseDocumentRepository repository;

  @override
  State<CaseDocumentsSection> createState() => _CaseDocumentsSectionState();
}

class _CaseDocumentsSectionState extends State<CaseDocumentsSection> {
  List<CaseDocument>? _documents;
  bool _failed = false;
  bool _isBusy = false;

  /// Sem Supabase (demo) a seção nem aparece: o botão de anexar levaria a
  /// lugar nenhum, e botão que não faz nada é link morto. O seam mora no
  /// repositório para os testes renderizarem a seção com um fake.
  bool get _available => widget.repository.isAvailable;

  @override
  void initState() {
    super.initState();
    if (_available) _load();
  }

  Future<void> _load() async {
    try {
      final documents = await widget.repository.fetchForCase(widget.caseId);
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _failed = false;
      });
    } catch (error) {
      debugPrint('Case documents fetch failed: $error');
      if (!mounted) return;
      // Só vira tela de erro quando não há NADA para mostrar: com a lista já
      // na tela, uma recarga que falhou não pode apagá-la.
      setState(() => _failed = _documents == null);
    }
  }

  Future<void> _attach() async {
    if (_isBusy) return;
    final messenger = ScaffoldMessenger.of(context);

    SafePickedFile? picked;
    try {
      picked = await pickSingleFile(
        allowedExtensions: caseDocumentAllowedExtensions,
      );
    } catch (error) {
      debugPrint('Case document pick failed: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível abrir o seletor de arquivos. Verifique as '
            'permissões do aplicativo.',
          ),
        ),
      );
      return;
    }
    if (picked == null || !mounted) return;

    // Tamanho ANTES dos bytes: um vídeo de 800 MB escolhido por engano não
    // pode virar OOM. Mesma regra de todos os seletores do app.
    if (picked.size > maxCaseDocumentFileBytes) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cada documento pode ter no máximo 25 MB.'),
        ),
      );
      return;
    }

    final bytes = await picked.readBytes();
    final validation = validateCaseDocument(
      fileName: picked.name,
      bytes: bytes,
      sizeBytes: picked.size,
    );
    if (!validation.isValid) {
      messenger.showSnackBar(SnackBar(content: Text(validation.error!)));
      return;
    }
    if (!mounted) return;

    // O título é o nome pelo qual o OUTRO lado vai procurar o documento;
    // "IMG_4021.jpg" não conta uma história. Vem pré-preenchido com o nome
    // do arquivo sem a extensão, e a pessoa melhora se quiser.
    final title = await _askTitle(_suggestedTitle(picked.name));
    if (title == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await widget.repository.upload(
        caseId: widget.caseId,
        title: title,
        fileName: picked.name,
        mimeType: validation.mimeType!,
        bytes: bytes,
      );
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        const SnackBar(content: Text('Documento anexado ao caso.')),
      );
    } catch (error) {
      debugPrint('Case document upload failed: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível anexar. Tente novamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _suggestedTitle(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final cleaned = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return cleaned.isEmpty ? 'Documento' : cleaned;
  }

  Future<String?> _askTitle(String suggestion) {
    final controller = TextEditingController(text: suggestion);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nome do documento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ex.: Procuração assinada',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(
                dialogContext,
              ).pop(value.isEmpty ? 'Documento' : value);
            },
            child: const Text('Anexar'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(CaseDocument document) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await widget.repository.signedUrl(document);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o arquivo.')),
        );
      }
    } catch (error) {
      debugPrint('Case document open failed: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o documento agora.'),
        ),
      );
    }
  }

  Future<void> _confirmRemove(CaseDocument document) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover documento?'),
        content: Text(
          '"${document.title}" sai do caso para todos. '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.repository.remove(document);
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        const SnackBar(content: Text('Documento removido.')),
      );
    } catch (error) {
      debugPrint('Case document remove failed: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível remover. Tente novamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final colors = context.jColors;
    final documents = _documents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Documentos',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _isBusy ? null : _attach,
              icon: _isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file, size: 18),
              label: Text(_isBusy ? 'Enviando...' : 'Anexar'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Visíveis para todos que participam do caso.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (_failed)
          JuriiErrorState(
            title: 'Não foi possível carregar os documentos',
            onRetry: () {
              setState(() => _failed = false);
              _load();
            },
          )
        else if (documents == null)
          const JuriiSkeletonList(itemCount: 2, itemHeight: 64)
        else if (documents.isEmpty)
          const JuriiEmptyState(
            icon: Icons.folder_open_outlined,
            title: 'Nenhum documento anexado',
            message:
                'Procuração, contrato, comprovantes: anexe aqui o que fizer '
                'parte do caso.',
          )
        else
          for (var index = 0; index < documents.length; index++) ...[
            JuriiStaggeredItem(
              key: ValueKey('case_document_${documents[index].id}'),
              index: index,
              child: _DocumentTile(
                document: documents[index],
                onOpen: () => _open(documents[index]),
                onRemove: documents[index].isMine
                    ? () => _confirmRemove(documents[index])
                    : null,
              ),
            ),
            if (index < documents.length - 1) const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onOpen,
    this.onRemove,
  });

  final CaseDocument document;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  IconData get _icon {
    if (document.isPdf) return Icons.picture_as_pdf_outlined;
    if (document.isImage) return Icons.image_outlined;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final created = document.createdAt;
    final detalhes = [
      if (document.readableSize.isNotEmpty) document.readableSize,
      if (created != null) formatRelativeTime(created),
    ].join(' · ');

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.lightBlueBorder),
          ),
          child: Row(
            children: [
              Icon(_icon, color: colors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detalhes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detalhes,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remover documento',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
