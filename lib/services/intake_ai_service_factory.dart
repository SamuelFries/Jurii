import 'intake_ai_service.dart';
import 'remote_intake_ai_service.dart';
import 'supabase_config.dart';

/// Ponto único de composição da IA de triagem.
///
/// Com o Supabase configurado, a triagem usa a IA real (Edge Function
/// `intake-chat`, Sonnet 5, chave só no servidor); o [RemoteIntakeAIService]
/// carrega o [RuleBasedIntakeAIService] como rede de segurança POR TURNO, e
/// por isso a troca não cria modo de falha novo: sem API, a triagem continua
/// exatamente como era. No modo demo (sem Supabase) a implementação local é a
/// própria titular.
IntakeAIService resolveIntakeAIService() => SupabaseConfig.isReady
    ? RemoteIntakeAIService()
    : RuleBasedIntakeAIService();
