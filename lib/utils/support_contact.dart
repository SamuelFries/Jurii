import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const String supportEmail = 'contato@jurii.com.br';

/// Abre o app de e-mail com o endereço de suporte preenchido. Sem app de
/// e-mail configurado (comum em emulador e em alguns Android), cai para um
/// diálogo com o endereço e botão de copiar. Nunca um toque sem resposta.
Future<void> openSupportEmail(BuildContext context, {String? subject}) async {
  final uri = Uri(
    scheme: 'mailto',
    path: supportEmail,
    query: 'subject=${Uri.encodeComponent(subject ?? 'Suporte Jurii')}',
  );

  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    launched = false;
  }

  if (launched || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Fale com a gente'),
      content: const Text(
        'Escreva para $supportEmail e responderemos por e-mail.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: supportEmail));
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: const Text('Copiar e-mail'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
