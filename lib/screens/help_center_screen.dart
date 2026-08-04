import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/support_contact.dart';

class _HelpItem {
  const _HelpItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

class _HelpSection {
  const _HelpSection({required this.title, required this.items});

  final String title;
  final List<_HelpItem> items;
}

const List<_HelpSection> _sections = [
  _HelpSection(
    title: 'PARA CLIENTES',
    items: [
      _HelpItem(
        question: 'Como encontro um advogado ou escritório?',
        answer:
            'Descreva seu problema na busca com as suas palavras, como '
            '"fui demitido" ou "bati o carro". A Jurii entende a linguagem '
            'do dia a dia e mostra profissionais verificados da área certa. '
            'Você pode ordenar por relevância, avaliação ou distância.',
      ),
      _HelpItem(
        question: 'Como funciona a conversa com o profissional?',
        answer:
            'Tudo acontece dentro do app: mensagens, anexos (fotos e '
            'documentos) e a triagem assistida, que ajuda a organizar seu '
            'relato antes de enviá-lo ao advogado. Toque no botão "+" dentro '
            'da conversa para ver as opções.',
      ),
      _HelpItem(
        question: 'Como acompanho o andamento do meu processo?',
        answer:
            'Quando o advogado informa o número do processo, a linha do '
            'tempo aparece dentro do caso e você recebe um aviso no celular '
            'sempre que o processo anda. Processos em segredo de justiça '
            'não têm dados públicos, então a linha do tempo fica vazia.',
      ),
      _HelpItem(
        question: 'Quando posso avaliar um profissional?',
        answer:
            'Depois de ter um caso aceito com aquele profissional. Isso '
            'garante que todas as avaliações vêm de atendimentos reais.',
      ),
      _HelpItem(
        question: 'A Jurii tem acesso à minha localização?',
        answer:
            'Não. A distância até o escritório é calculada no seu aparelho '
            'e a sua posição nunca é enviada aos nossos servidores.',
      ),
    ],
  ),
  _HelpSection(
    title: 'PARA ADVOGADOS E ESCRITÓRIOS',
    items: [
      _HelpItem(
        question: 'Como ativo meu perfil profissional?',
        answer:
            'No Perfil, toque em ativar o modo profissional e envie seus '
            'dados da OAB com os documentos pedidos. A análise leva até 2 '
            'dias úteis (advogados) ou 3 dias úteis (escritórios). Se algo '
            'for recusado, o motivo aparece no seu perfil e você pode '
            'reenviar.',
      ),
      _HelpItem(
        question: 'Como proponho um caso a um cliente?',
        answer:
            'Dentro da conversa com o cliente, toque em "Enviar solicitação '
            'de caso" no topo do chat. Quando o cliente aceitar, o caso '
            'aparece na aba Casos para os dois.',
      ),
      _HelpItem(
        question: 'Como funciona a agenda?',
        answer:
            'Crie compromissos na aba Agenda e receba um lembrete cerca de '
            'uma hora antes. Pelo ícone de calendário você também pode '
            'assinar a agenda no Google, na Apple ou no Outlook.',
      ),
      _HelpItem(
        question: 'O que significa o selo "Destaque"?',
        answer:
            'Perfis impulsionados aparecem no topo da busca sempre com o '
            'selo visível. O destaque nunca altera as avaliações nem fura '
            'a ordenação que o cliente escolher.',
      ),
    ],
  ),
  _HelpSection(
    title: 'CONTA E PRIVACIDADE',
    items: [
      _HelpItem(
        question: 'Como altero meus dados?',
        answer:
            'Em Perfil, toque em "Dados Pessoais" para atualizar nome, '
            'telefone e foto. E-mail e CPF identificam a sua conta e não '
            'podem ser alterados pelo app.',
      ),
      _HelpItem(
        question: 'Como excluo minha conta?',
        answer:
            'Em Perfil, toque em "Segurança" e depois em "Excluir conta". '
            'Seus dados pessoais são removidos conforme a LGPD.',
      ),
      _HelpItem(
        question: 'Onde leio os Termos de Uso e a Política de Privacidade?',
        answer:
            'Na seção Suporte do Perfil, ou nos links exibidos nas telas de '
            'cadastro e login.',
      ),
    ],
  ),
];

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Central de Ajuda')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            for (final section in _sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                child: Text(
                  section.title,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              _HelpSectionCard(section: section),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            _SupportFooter(colors: colors),
          ],
        ),
      ),
    );
  }
}

class _HelpSectionCard extends StatelessWidget {
  const _HelpSectionCard({required this.section});

  final _HelpSection section;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    // Material (e não DecoratedBox): o ExpansionTile pinta fundo e ripple no
    // Material ancestral mais próximo.
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.lightBlueBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Remove as linhas divisórias que o ExpansionTile desenha ao abrir.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          children: [
            for (var i = 0; i < section.items.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: colors.divider),
              ExpansionTile(
                title: Text(
                  section.items[i].question,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                iconColor: colors.accent,
                collapsedIconColor: colors.textSecondary,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.items[i].answer,
                    style: TextStyle(color: colors.textSecondary, height: 1.45),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupportFooter extends StatelessWidget {
  const _SupportFooter({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.lightBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(
              'Não encontrou o que precisava?',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => openSupportEmail(context),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Falar com o suporte'),
            ),
          ],
        ),
      ),
    );
  }
}
