import 'dart:async';

import 'package:flutter/material.dart';

/// O campo de busca das listas (conversas e casos).
///
/// Existe como widget único porque seis telas precisam da mesma busca: seis
/// cópias virariam seis comportamentos diferentes de debounce, de botão de
/// limpar e de rótulo acessível.
///
/// O CONTROLLER É DO PAI, de propósito: o estado de "nenhum resultado" tem um
/// botão "Limpar busca" que precisa esvaziar o campo de fora para dentro. Com
/// o controller escondido aqui, esse botão limparia o filtro e deixaria o
/// texto na tela, dizendo que a busca continua ativa quando não está mais.
class JuriiSearchField extends StatefulWidget {
  const JuriiSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String hintText;

  /// Chamado já com debounce aplicado.
  final ValueChanged<String> onChanged;

  /// Rótulo lido pelo leitor de tela. O hint sozinho some assim que a pessoa
  /// digita a primeira letra.
  final String? semanticLabel;

  @override
  State<JuriiSearchField> createState() => _JuriiSearchFieldState();
}

class _JuriiSearchFieldState extends State<JuriiSearchField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// 250ms: a filtragem é local (nenhuma ida ao servidor), então o debounce
  /// existe só para não reconstruir a lista a cada tecla. Na home, onde cada
  /// mudança dispara duas RPCs, o valor é 350ms.
  void _onChanged(String value) {
    _debounce?.cancel();
    // Redesenha já o botão de limpar, sem refazer o filtro.
    setState(() {});
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => widget.onChanged(value),
    );
  }

  void _clear() {
    _debounce?.cancel();
    widget.controller.clear();
    setState(() {});
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: widget.semanticLabel ?? widget.hintText,
      child: TextField(
        controller: widget.controller,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: (value) {
          _debounce?.cancel();
          widget.onChanged(value);
        },
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: _clear,
                  icon: const Icon(Icons.close),
                  tooltip: 'Limpar busca',
                ),
        ),
      ),
    );
  }
}
