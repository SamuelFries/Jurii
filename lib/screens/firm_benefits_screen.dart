import 'package:flutter/material.dart';

import '../models/law_firm_license.dart';
import '../models/law_firm_verification.dart';
import '../models/user_profile.dart';
import '../repositories/license_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_motion.dart';
import 'firm_plan_screen.dart';
import 'law_firm_verification_screen.dart';

/// A porta de entrada do escritório: por que estar na Jurii.
///
/// É a primeira tela do funil de licenciamento (vantagens → plano →
/// verificação). Cada vantagem aqui mapeia para uma funcionalidade que EXISTE
/// — vender o que não está no ar cobra a conta na primeira semana de uso.
///
/// O texto evita promessa de resultado ("garanta clientes") de propósito:
/// publicidade de advocacia responde ao Provimento 205/2021 da OAB, e a
/// plataforma não pode empurrar o escritório para fora da linha.
class FirmBenefitsScreen extends StatefulWidget {
  const FirmBenefitsScreen({
    super.key,
    required this.user,
    this.onVerificationSubmitted,
    this.licenseRepository = const LicenseRepository(),
  });

  final UserProfile user;
  final ValueChanged<LawFirmVerification>? onVerificationSubmitted;
  final LicenseRepository licenseRepository;

  @override
  State<FirmBenefitsScreen> createState() => _FirmBenefitsScreenState();
}

class _FirmBenefitsScreenState extends State<FirmBenefitsScreen> {
  /// Quem já escolheu plano (voltou no meio do cadastro, ou foi recusado e
  /// vai reenviar) não vê a paywall de novo: o CTA vira "Continuar cadastro".
  LicenseSubscription? _licenca;

  @override
  void initState() {
    super.initState();
    _carregarLicenca();
  }

  Future<void> _carregarLicenca() async {
    try {
      final licenca = await widget.licenseRepository.fetchMyLicense();
      if (!mounted) return;
      setState(() => _licenca = licenca);
    } catch (_) {
      // Sem leitura, segue como se não houvesse licença: a paywall de verdade
      // é a do banco — esta tela só decide qual botão mostrar.
    }
  }

  bool get _jaTemLicenca => _licenca?.ativa == true;

  Future<void> _trocarPlano() async {
    final licenca = _licenca;
    if (licenca == null) return;
    final nova = await Navigator.of(context).push<LicenseSubscription>(
      MaterialPageRoute(
        builder: (_) => FirmPlanScreen.upgrade(upgradeDe: licenca.planCode),
      ),
    );
    if (nova != null && mounted) {
      setState(() => _licenca = nova);
    }
  }

  void _avancar() {
    if (_jaTemLicenca) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LawFirmVerificationScreen(
            user: widget.user,
            onVerificationSubmitted: widget.onVerificationSubmitted,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FirmPlanScreen(
          user: widget.user,
          onVerificationSubmitted: widget.onVerificationSubmitted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    final beneficios = [
      (
        icon: Icons.search_outlined,
        titulo: 'Apareça para quem procura',
        texto:
            'Clientes buscam por área do direito e por proximidade. O '
            'escritório entra na descoberta com perfil completo, avaliações '
            'e distância.',
      ),
      (
        icon: Icons.group_outlined,
        titulo: 'Equipe num lugar só',
        texto:
            'Convide advogados pelo número da OAB e organize papéis: sócio, '
            'admin, advogado, secretaria. Cada um vê o que é seu.',
      ),
      (
        icon: Icons.chat_bubble_outline,
        titulo: 'Conversas e casos centralizados',
        texto:
            'Mensagens de clientes e da equipe, casos por advogado e '
            'andamento, sem WhatsApp perdido no celular de cada um.',
      ),
      (
        icon: Icons.insights_outlined,
        titulo: 'Números de verdade',
        texto:
            'O painel de alcance mostra quantas pessoas viram o escritório, '
            'abriram o perfil e começaram conversa, semana a semana.',
      ),
      (
        icon: Icons.schedule_outlined,
        titulo: 'Perfil que responde sozinho',
        texto:
            'Horários de atendimento, apresentação, áreas e endereço com '
            'distância: o cliente decide escrever antes de você dizer oi.',
      ),
      (
        icon: Icons.workspace_premium_outlined,
        titulo: 'Destaque quando você quiser',
        texto:
            'Posições patrocinadas na descoberta, sempre identificadas e '
            'disponíveis para contratar quando fizer sentido.',
      ),
    ];

    final passos = [
      ('1', 'Escolha o plano', '30 dias grátis, sem cartão.'),
      ('2', 'Verifique o CNPJ', 'Análise humana dos documentos.'),
      ('3', 'Equipe no ar', 'Convide advogados e comece a atender.'),
    ];

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Herói na pele do fluxo roxo: é a identidade da área do
                  // escritório desde a home.
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.officePurple,
                          Color.lerp(colors.officePurple, Colors.black, 0.18)!,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colors.card.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(
                                  Icons.arrow_back_ios_new,
                                  color: colors.card,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Icon(
                          Icons.apartment_outlined,
                          color: colors.lightGold,
                          size: 34,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Seu escritório,\nonde o cliente procura',
                          style: TextStyle(
                            color: colors.card,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'A Jurii conecta quem precisa de um advogado a quem '
                          'atende a área, e dá ao escritório a gestão da '
                          'equipe, das conversas e dos casos.',
                          style: TextStyle(
                            color: colors.card.withValues(alpha: 0.85),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < beneficios.length; i++) ...[
                          JuriiStaggeredItem(
                            index: i,
                            child: _CartaoDeBeneficio(
                              icon: beneficios[i].icon,
                              titulo: beneficios[i].titulo,
                              texto: beneficios[i].texto,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'COMO FUNCIONA',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final (numero, titulo, texto) in passos) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: colors.officePurpleSurface,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    numero,
                                    style: TextStyle(
                                      color: colors.officePurple,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titulo,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      texto,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // CTA fixo: a decisão não pode morar no fim de um scroll longo.
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: BoxDecoration(
                color: colors.background,
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      key: const Key('firm_benefits_cta'),
                      onPressed: _avancar,
                      child: Text(
                        _jaTemLicenca
                            ? 'Continuar cadastro'
                            : 'Conhecer os planos',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  // Quem já escolheu plano e reentrou no funil também pode
                  // mudar de ideia. Sem esta porta, a troca só existiria
                  // depois da aprovação (Perfil do escritório).
                  if (_jaTemLicenca)
                    TextButton(
                      key: const Key('firm_benefits_trocar_plano'),
                      onPressed: _trocarPlano,
                      child: const Text('Trocar de plano'),
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

class _CartaoDeBeneficio extends StatelessWidget {
  const _CartaoDeBeneficio({
    required this.icon,
    required this.titulo,
    required this.texto,
  });

  final IconData icon;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.officePurpleBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.officePurpleSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colors.officePurple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  texto,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
