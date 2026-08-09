import 'package:flutter/material.dart';

import 'jurii_empty_state.dart';

/// "A busca não achou" é diferente de "não existe nada".
///
/// Antes só existia o segundo: filtrar até zerar a lista mostrava "Nenhum
/// caso iniciado", e quem lê isso acha que perdeu os dados, não que o próprio
/// filtro escondeu. Por isso a mensagem diz explicitamente que nada foi
/// apagado e oferece o botão que desfaz o filtro.
class JuriiNoResultsState extends StatelessWidget {
  const JuriiNoResultsState({
    super.key,
    required this.message,
    required this.onClear,
    this.icon = Icons.search_off,
  });

  /// O que sobrou escondido, na língua da tela. Ex.: "Seus 12 casos continuam
  /// aqui, só não aparecem com esse filtro."
  final String message;

  final VoidCallback onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: JuriiEmptyState(
        icon: icon,
        title: 'Nenhum resultado',
        message: message,
        actionLabel: 'Limpar busca',
        onAction: onClear,
      ),
    );
  }
}
