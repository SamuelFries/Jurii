import 'package:flutter/material.dart';

import '../repositories/favorites_repository.dart';
import '../theme/app_colors.dart';

/// Coração de favoritar nos perfis de advogado/escritório. Autocontido:
/// carrega o próprio estado, alterna com atualização OTIMISTA (reverte e
/// avisa se o servidor recusar) e some por inteiro no modo demo/deslogado.
class FavoriteHeartButton extends StatefulWidget {
  const FavoriteHeartButton({
    super.key,
    required this.type,
    required this.targetId,
    this.repository = const FavoritesRepository(),
  });

  final FavoriteTargetType type;
  final String targetId;
  final FavoritesRepository repository;

  @override
  State<FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<FavoriteHeartButton> {
  /// null = estado ainda não carregado (coração desabilitado, sem chute).
  bool? _isFavorite;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    if (!widget.repository.isAvailable) return;
    try {
      final keys = await widget.repository.fetchFavoriteKeys();
      if (!mounted) return;
      setState(() {
        _isFavorite = keys.contains(
          favoriteKey(widget.type.value, widget.targetId),
        );
      });
    } catch (_) {
      // Sem estado não há toggle confiável; o coração fica fora em vez de
      // mentir vazio sobre um favorito que talvez exista.
    }
  }

  Future<void> _toggle() async {
    final current = _isFavorite;
    if (current == null || _isToggling) return;

    // Otimista: vira na hora; servidor discordou, reverte e avisa.
    setState(() {
      _isFavorite = !current;
      _isToggling = true;
    });

    try {
      final result = await widget.repository.toggleFavorite(
        type: widget.type,
        id: widget.targetId,
      );
      if (!mounted) return;
      setState(() {
        _isFavorite = result;
        _isToggling = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFavorite = current;
        _isToggling = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar o favorito.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isAvailable) return const SizedBox.shrink();

    final isFavorite = _isFavorite;
    return IconButton(
      onPressed: isFavorite == null ? null : _toggle,
      tooltip: isFavorite == true
          ? 'Remover dos favoritos'
          : 'Adicionar aos favoritos',
      icon: Icon(
        isFavorite == true ? Icons.favorite : Icons.favorite_border,
        color: isFavorite == true
            ? context.jColors.danger
            : context.jColors.textSecondary,
      ),
    );
  }
}
