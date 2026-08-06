import 'package:flutter/material.dart';

import '../repositories/professional_bio_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_error_state.dart';

/// Editor da apresentação pública do ADVOGADO — o texto que o cliente lê
/// antes de decidir. Sem ele, todo perfil da Jurii exibia a mesma frase.
///
/// A variante de escritório morava aqui também, mas era um segundo botão para
/// o mesmo gesto de descrever o escritório: hoje a apresentação da firma vive
/// dentro de "Dados do escritório" (EditFirmProfileScreen), atrás do lápis.
class ProfessionalBioScreen extends StatefulWidget {
  const ProfessionalBioScreen.lawyer({
    super.key,
    this.repository = const ProfessionalBioRepository(),
  });

  final ProfessionalBioRepository repository;

  @override
  State<ProfessionalBioScreen> createState() => _ProfessionalBioScreenState();
}

class _ProfessionalBioScreenState extends State<ProfessionalBioScreen> {
  final _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final bio = await widget.repository.fetchMyBio();
      if (!mounted) return;
      setState(() {
        _controller.text = bio ?? '';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final text = _controller.text.trim();
    // Capturado ANTES do pop: depois dele este widget está desmontando, e
    // procurar o messenger pelo próprio context passa a depender de quem
    // sobrou na árvore.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.saveMyBio(text.isEmpty ? null : text);
      if (!mounted) return;
      // Devolve o texto salvo: quem abriu a tela atualiza o que exibe sem
      // refazer o fetch.
      Navigator.of(context).pop(text.isEmpty ? null : text);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            text.isEmpty ? 'Apresentação removida.' : 'Apresentação salva.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar. Tente novamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Apresentação'),
        backgroundColor: colors.background,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: JuriiErrorState(
                  title: 'Não foi possível carregar sua apresentação.',
                  onRetry: _load,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Text(
                    'Como você se apresenta',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Este texto aparece no seu perfil, para o cliente que '
                    'está escolhendo com quem falar. Sem ele, mostramos uma '
                    'frase padrão igual à de todo mundo.',
                    style: TextStyle(color: colors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    maxLines: 8,
                    minLines: 6,
                    maxLength: ProfessionalBioRepository.maxLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'Ex.: Atuo há 12 anos em direito de família, com '
                          'foco em divórcio e guarda.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Salvar apresentação'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
