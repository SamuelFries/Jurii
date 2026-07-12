import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'jurii_form_motion.dart';
import 'jurii_motion.dart';

/// Rótulo curto do modo de tema para subtítulos de menu.
String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'Claro';
    case ThemeMode.dark:
      return 'Escuro';
    case ThemeMode.system:
      return 'Automático';
  }
}

/// Abre o seletor de aparência (claro/escuro/automático).
///
/// A troca aplica na hora — o app reanima atrás do sheet — e é persistida
/// pelo [ThemeController].
Future<void> showThemeModeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // Sem o teto de 9/16 dos sheets padrão; em telas baixas as três opções
    // estouravam o limite.
    isScrollControlled: true,
    builder: (_) => const _ThemeModeSheet(),
  );
}

class _ThemeModeSheet extends StatelessWidget {
  const _ThemeModeSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiModalSheetScaffold(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.instance,
        builder: (context, mode, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aparência',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Escolha como a Jurii deve se apresentar.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              _ThemeModeOption(
                mode: ThemeMode.system,
                selected: mode == ThemeMode.system,
                icon: Icons.brightness_auto_outlined,
                title: 'Automático',
                description: 'Segue o tema do aparelho.',
              ),
              const SizedBox(height: 10),
              _ThemeModeOption(
                mode: ThemeMode.light,
                selected: mode == ThemeMode.light,
                icon: Icons.light_mode_outlined,
                title: 'Claro',
                description: 'Fundo claro, sempre.',
              ),
              const SizedBox(height: 10),
              _ThemeModeOption(
                mode: ThemeMode.dark,
                selected: mode == ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                title: 'Escuro',
                description: 'Navy profundo com dourado.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.mode,
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
  });

  final ThemeMode mode;
  final bool selected;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ThemeController.instance.setMode(mode),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: JuriiMotion.fast,
          curve: JuriiMotion.ease,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? colors.lightBlue : colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.primary : colors.lightBlueBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: JuriiMotion.fast,
                child: selected
                    ? Icon(
                        Icons.check_circle,
                        key: const ValueKey('selected'),
                        color: colors.primary,
                        size: 22,
                      )
                    : Icon(
                        Icons.circle_outlined,
                        key: const ValueKey('unselected'),
                        color: colors.muted,
                        size: 22,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
