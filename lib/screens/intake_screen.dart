import 'package:flutter/material.dart';

import '../data/legal_documents.dart';
import '../models/intake_session.dart';
import '../models/intake_summary.dart';
import '../services/intake_ai_service.dart';
import '../services/intake_ai_service_factory.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../widgets/intake_summary_view.dart';
import '../widgets/jurii_motion.dart';
import 'legal_document_screen.dart';

/// Resultado da triagem que volta para o chat: o resumo estruturado e a
/// overview formatada que será enviada como mensagem ao profissional.
class IntakeChatResult {
  const IntakeChatResult({required this.summary, required this.overviewText});

  final IntakeSummary summary;
  final String overviewText;
}

/// Triagem conversacional com a assistente da Jurii, aberta de dentro de uma
/// conversa cliente → advogado/escritório já iniciada. A sessão roda 100%
/// local (em memória); nada é persistido pela triagem em si. Ao final, o
/// cliente revisa o resumo e decide enviá-lo na conversa — o envio é a única
/// saída do relato, e acontece apenas por ação explícita dele (`pop` com
/// [IntakeChatResult]; `null` = não enviar).
///
/// A tela depende apenas do contrato [IntakeAIService] (injetável por
/// construtor, default via [resolveIntakeAIService]); trocar para a IA real no
/// futuro não altera esta UI.
class IntakeScreen extends StatefulWidget {
  const IntakeScreen({
    super.key,
    this.service,
    this.counterpartLabel = 'profissional',
  });

  final IntakeAIService? service;

  /// Como chamar o destinatário nos textos ("advogado" ou "escritório").
  final String counterpartLabel;

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> {
  late final IntakeAIService _service;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  ClientIntakeSession? _session;
  IntakeSummary? _summary;
  bool _isSending = false;
  bool _isGeneratingSummary = false;
  bool _startFailed = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? resolveIntakeAIService();
    _startSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _clientId =>
      (SupabaseConfig.isReady
          ? SupabaseConfig.client.auth.currentUser?.id
          : null) ??
      'local-client';

  Future<void> _startSession() async {
    setState(() => _startFailed = false);
    try {
      final session = await _service.startSession(clientId: _clientId);
      if (!mounted) return;
      setState(() {
        _session = session;
        _summary = null;
      });
      _scrollToBottom();
    } catch (error) {
      debugPrint('Intake start failed: $error');
      if (!mounted) return;
      setState(() => _startFailed = true);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final session = _session;
    if (text.isEmpty || _isSending || _isGeneratingSummary || session == null) {
      return;
    }

    _controller.clear();
    setState(() => _isSending = true);

    try {
      final updated = await _service.sendClientMessage(session, text);
      if (!mounted) return;
      setState(() {
        _session = updated;
        _isSending = false;
      });
      _scrollToBottom();
      if (updated.isReadyForSummary) {
        await _generateSummary(updated);
      }
    } catch (error) {
      debugPrint('Intake message send failed: $error');
      if (!mounted) return;
      setState(() => _isSending = false);
      // Restaura o texto só se o usuário não começou outro rascunho.
      if (_controller.text.trim().isEmpty) _controller.text = text;
      _showSnack('Não foi possível enviar sua mensagem. Tente de novo.');
    }
  }

  Future<void> _generateSummary(ClientIntakeSession session) async {
    setState(() => _isGeneratingSummary = true);
    try {
      final summary = await _service.buildSummary(session);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isGeneratingSummary = false;
      });
    } catch (error) {
      debugPrint('Intake summary build failed: $error');
      if (!mounted) return;
      setState(() => _isGeneratingSummary = false);
      _showSnack('Não foi possível preparar o resumo agora.');
    }
  }

  void _restart() {
    setState(() {
      _summary = null;
      _session = null;
      _isGeneratingSummary = false;
    });
    _startSession();
  }

  /// Envio explícito: devolve o resumo para o chat, que o publica como
  /// mensagem na conversa com o profissional escolhido pelo cliente.
  void _sendToChat(IntakeSummary summary) {
    final overview = _service.buildLawyerOverview(summary);
    Navigator.of(context).pop(
      IntakeChatResult(summary: summary, overviewText: overview.formattedText),
    );
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sair da triagem?'),
        content: const Text(
          'Seu relato ainda não foi organizado e não será salvo se você sair '
          'agora.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final session = _session;
    final hasConversation =
        session != null && session.clientStatements.isNotEmpty;
    // No resumo (ou antes de escrever qualquer coisa) sair é livre; no meio da
    // conversa, confirma para não perder um relato longo por engano.
    final canPop = _summary != null || !hasConversation;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await _confirmDiscard();
        if (leave) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assistente Jurii',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              Text(
                'Triagem inicial',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        body: SafeArea(child: _buildBody(colors)),
      ),
    );
  }

  Widget _buildBody(AppColors colors) {
    if (_startFailed) {
      return _IntakeErrorState(onRetry: _startSession);
    }

    final session = _session;
    if (session == null) {
      // Skeleton de bolhas: hoje o serviço local resolve na hora, mas a IA
      // remota (Edge Function) terá latência real aqui.
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: JuriiSkeletonList(itemCount: 3, itemHeight: 64, gap: 10),
      );
    }

    if (_summary != null) {
      return _buildSummary(colors, _summary!);
    }

    return Column(
      children: [
        const _DisclaimerBanner(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: session.messages.length,
            itemBuilder: (context, index) =>
                _IntakeBubble(message: session.messages[index]),
          ),
        ),
        if (_isGeneratingSummary) const _GeneratingSummaryStrip(),
        _IntakeComposer(
          controller: _controller,
          enabled: !_isSending && !_isGeneratingSummary,
          isSending: _isSending,
          onSend: _sendMessage,
        ),
      ],
    );
  }

  Widget _buildSummary(AppColors colors, IntakeSummary summary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntakeSummaryView(summary: summary),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _sendToChat(summary),
            icon: const Icon(Icons.send, size: 18),
            label: Text('Enviar resumo ao ${widget.counterpartLabel}'),
          ),
          const SizedBox(height: 6),
          Text(
            'Ao enviar, o resumo aparece como mensagem nesta conversa.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: _restart, child: const Text('Refazer triagem')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Agora não'),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.lightBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.lightBlueBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A assistente organiza seu relato e não substitui um '
                  'advogado. Isto não é aconselhamento jurídico.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        type: LegalDocumentType.privacyPolicy,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Saiba mais',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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

class _IntakeBubble extends StatelessWidget {
  const _IntakeBubble({required this.message});

  final IntakeMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final isClient = message.sender == IntakeMessageSender.client;
    final bubbleColor = isClient ? colors.primary : colors.card;
    final textColor = isClient ? colors.card : colors.textPrimary;

    return Align(
      alignment: isClient ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.80,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isClient ? 16 : 4),
              bottomRight: Radius.circular(isClient ? 4 : 16),
            ),
            border: isClient ? null : Border.all(color: colors.lightBlueBorder),
          ),
          child: Text(
            message.body,
            style: TextStyle(color: textColor, height: 1.35),
          ),
        ),
      ),
    );
  }
}

class _GeneratingSummaryStrip extends StatelessWidget {
  const _GeneratingSummaryStrip();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colors.background,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Preparando o resumo do seu caso...',
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntakeComposer extends StatelessWidget {
  const _IntakeComposer({
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Conte o que aconteceu...',
                filled: true,
                fillColor: colors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: ElevatedButton(
              onPressed: enabled ? onSend : null,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isSending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: colors.card,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntakeErrorState extends StatelessWidget {
  const _IntakeErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: colors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Não foi possível iniciar a triagem.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
