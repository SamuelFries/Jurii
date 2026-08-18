import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/login_logo.dart';

/// A apresentação de primeira abertura.
///
/// O app abria direto no login: quem chegava pela loja decidia criar conta
/// sem saber o que existe do outro lado da porta. Três telas dizem o
/// essencial — achar o advogado certo, acompanhar o caso, e o lado de quem
/// advoga — e saem da frente.
///
/// REGRAS DA CASA que esta tela obedece: "Pular" está sempre visível (intro
/// não é pedágio); ela aparece UMA vez por aparelho (quem guarda é o
/// JuriiApp, e a tela só avisa que acabou); e a última página troca o botão
/// por "Começar", que leva ao login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinish});

  /// Chamado tanto no "Começar" quanto no "Pular": visto é visto.
  final VoidCallback onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Pagina {
  const _Pagina({required this.icone, required this.titulo, required this.texto});

  /// Nulo na primeira página: lá quem aparece é a marca.
  final IconData? icone;
  final String titulo;
  final String texto;
}

const _paginas = [
  _Pagina(
    icone: null,
    titulo: 'O advogado certo,\nsem adivinhar',
    texto:
        'Busque por área, compare avaliações de clientes reais e fale '
        'direto com quem pode assumir o seu caso.',
  ),
  _Pagina(
    icone: Icons.forum_outlined,
    titulo: 'Seu caso,\nacompanhado de perto',
    texto:
        'Conversa, documentos e cada movimento do processo numa linha do '
        'tempo que se atualiza sozinha, com a fonte oficial do CNJ.',
  ),
  _Pagina(
    icone: Icons.gavel_outlined,
    titulo: 'Advoga?\nTrabalhe por aqui',
    texto:
        'Perfil verificado pela OAB, agenda com lembretes, equipe e os '
        'casos do escritório no mesmo lugar.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _pagina = 0;

  bool get _ultima => _pagina == _paginas.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _avancar() {
    if (_ultima) {
      widget.onFinish();
      return;
    }
    _controller.nextPage(
      duration: JuriiMotion.standard,
      curve: JuriiMotion.ease,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Pular SEMPRE à mão, desde a primeira página: apresentação que
            // prende a pessoa vira pedágio, e pedágio na primeira abertura é
            // onde se perde gente.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextButton(
                  onPressed: widget.onFinish,
                  child: Text(
                    'Pular',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _paginas.length,
                onPageChanged: (index) => setState(() => _pagina = index),
                itemBuilder: (context, index) {
                  final pagina = _paginas[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        JuriiStaggeredItem(
                          key: ValueKey('onboarding_arte_$index'),
                          index: 0,
                          child: pagina.icone == null
                              ? const Center(child: LoginLogo(subtitle: ''))
                              : Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    color: colors.lightBlue,
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: colors.lightBlueBorder,
                                    ),
                                  ),
                                  child: Icon(
                                    pagina.icone,
                                    size: 44,
                                    color: colors.primary,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 32),
                        JuriiStaggeredItem(
                          key: ValueKey('onboarding_titulo_$index'),
                          index: 1,
                          child: Text(
                            pagina.titulo,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                              height: 1.15,
                              fontFamily: 'Serif',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        JuriiStaggeredItem(
                          key: ValueKey('onboarding_texto_$index'),
                          index: 2,
                          child: Text(
                            pagina.texto,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
              child: Row(
                children: [
                  // Os pontos dizem onde a pessoa está; o ativo alonga, no
                  // padrão que o resto do app usa para seleção.
                  for (var i = 0; i < _paginas.length; i++) ...[
                    AnimatedContainer(
                      duration: JuriiMotion.fast,
                      curve: JuriiMotion.ease,
                      width: i == _pagina ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _pagina
                            ? colors.primary
                            : colors.lightBlueBorder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: _avancar,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.card,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _ultima ? 'Começar' : 'Avançar',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
