import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class LoginLogo extends StatelessWidget {
  const LoginLogo({
    super.key,
    this.subtitle = 'Conectando você aos melhores\nespecialistas jurídicos.',
  });

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    // Lockup empilhado da marca (símbolo + wordmark). PNG por decisão de
    // produção: os SVGs do kit dependem da fonte Sora via @import, que o
    // Flutter não resolve — os SVGs são o master (assets/brand/svg), o app
    // empacota só os PNGs prontos. A versão acompanha o tema.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lockup = isDark
        ? 'assets/brand/png/jurii-lockup-empilhado-escuro.png'
        : 'assets/brand/png/jurii-lockup-empilhado-claro.png';

    return Column(
      children: [
        Image.asset(
          lockup,
          height: 148,
          fit: BoxFit.contain,
          semanticLabel: 'Jurii',
          // Se o asset faltar num build quebrado, a wordmark de texto segura
          // o login em vez de um quadrado cinza de erro.
          errorBuilder: (context, error, stackTrace) => Text(
            'Jurii',
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
          ),
        ),

        const SizedBox(height: 16),

        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
