import '../data/mock/mock_license_plans.dart';
import '../models/law_firm_license.dart';
import '../services/supabase_config.dart';

/// Planos e assinatura do licenciamento do escritório.
///
/// Leitura direta (RLS: planos ativos para todo autenticado; assinatura para o
/// contratante e para quem fala pelo escritório). Escrita só pela RPC
/// `choose_law_firm_plan`, que cria o teste grátis ou troca o plano.
class LicenseRepository {
  const LicenseRepository();

  bool get _demo =>
      !SupabaseConfig.isReady || SupabaseConfig.client.auth.currentUser == null;

  Future<List<LicensePlan>> fetchPlans() async {
    if (_demo) return mockLicensePlans;

    final rows = await SupabaseConfig.client
        .from('law_firm_license_plans')
        // Lista explícita: coluna esquecida aqui chega NULA no model, sem
        // erro nenhum. Foi o que aconteceu com annual_price_cents, e o
        // efeito na tela foi a chave Mensal/Anual não mudar preço nem
        // mostrar desconto. O teste de sincronia abaixo trava isso.
        .select(
          'code, name, max_lawyers, monthly_price_cents, '
          'annual_price_cents, sort_order',
        )
        .eq('is_active', true)
        .order('sort_order');

    return rows
        .cast<Map<String, dynamic>>()
        .map(LicensePlan.fromRow)
        .toList(growable: false);
  }

  /// A licença NÃO GASTA de quem chama, isto é, a que ainda não virou banca.
  /// Nula quando nunca escolheu plano, e é o que manda a paywall aparecer.
  ///
  /// O filtro por `law_firm_id` nulo não é detalhe: desde que a cobrança
  /// passou a ser por ESCRITÓRIO, uma pessoa pode ter várias assinaturas (uma
  /// por banca) mais, no máximo, uma ainda não gasta. Sem o filtro, o
  /// `maybeSingle` estouraria para quem tem duas bancas, justo na consulta
  /// que decide se a paywall aparece.
  Future<LicenseSubscription?> fetchMyLicense() async {
    if (_demo) return null;

    final row = await SupabaseConfig.client
        .from('law_firm_license_subscriptions')
        .select('*, law_firm_license_plans(*)')
        .eq(
          'owner_profile_id',
          SupabaseConfig.client.auth.currentUser!.id,
        )
        .isFilter('law_firm_id', null)
        .neq('status', 'canceled')
        .maybeSingle();

    if (row == null) return null;
    return LicenseSubscription.fromRow(row);
  }

  /// A assinatura do ESCRITÓRIO, para o perfil (sócio/admin leem pela RLS).
  Future<LicenseSubscription?> fetchFirmLicense(String lawFirmId) async {
    if (_demo) return null;

    final row = await SupabaseConfig.client
        .from('law_firm_license_subscriptions')
        .select('*, law_firm_license_plans(*)')
        .eq('law_firm_id', lawFirmId)
        .neq('status', 'canceled')
        .maybeSingle();

    if (row == null) return null;
    return LicenseSubscription.fromRow(row);
  }

  /// Escolhe (ou troca) o plano. No primeiro uso cria o teste grátis de 30
  /// dias; nas trocas o fim do teste NÃO renova — o servidor garante.
  /// Escolhe ou troca o plano.
  ///
  /// Com [lawFirmId], troca o plano DAQUELA banca, e o servidor exige ser
  /// gestor dela. Sem ele, contrata uma licença nova, que é o caminho de
  /// quem vai abrir um escritório. Antes o servidor escolhia sozinho, e com
  /// duas bancas ele trocava o plano da errada.
  Future<LicenseSubscription> choosePlan(
    String planCode, {
    String billingCycle = 'monthly',
    String? lawFirmId,
  }) async {
    if (_demo) {
      // Demo: a paywall é atravessável para o fluxo inteiro ser demonstrável.
      return LicenseSubscription(
        id: 'demo',
        ownerProfileId: 'demo',
        planCode: planCode,
        billingCycle: billingCycle,
        status: LicenseStatus.trialing,
        trialEndsAt: DateTime.now().add(const Duration(days: 30)),
      );
    }

    final rows = await SupabaseConfig.client.rpc(
      'choose_law_firm_plan',
      params: {
        'plan_code_value': planCode,
        'billing_cycle_value': billingCycle,
        'law_firm_id_value': lawFirmId,
      },
    );

    final row = (rows as List<dynamic>).cast<Map<String, dynamic>>().first;
    return LicenseSubscription.fromRow({
      ...row,
      'owner_profile_id': SupabaseConfig.client.auth.currentUser!.id,
    });
  }
}
