import 'intake_ai_service.dart';

/// Ponto único de composição da IA de triagem.
///
/// Hoje devolve a implementação local e determinística
/// ([RuleBasedIntakeAIService]). Quando a IA real entrar (Edge Function
/// `intake-chat`, com a chave da API guardada só no servidor), basta trocar o
/// retorno aqui por `RemoteIntakeAIService()` — nenhuma tela muda, pois toda a
/// UI depende apenas do contrato [IntakeAIService].
IntakeAIService resolveIntakeAIService() => RuleBasedIntakeAIService();
