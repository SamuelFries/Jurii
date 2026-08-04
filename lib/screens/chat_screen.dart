import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mock/mock_chat_messages.dart';
import '../models/case_request.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/lawyer_recommendation.dart';
import '../models/report_reason.dart';
import '../repositories/case_repository.dart';
import '../repositories/law_firm_repository.dart';
import '../repositories/lawyer_profile_repository.dart';
import '../repositories/messaging_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/attachment_url_cache.dart';
import '../services/intake_ai_service.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/chat_attachment_rules.dart';
import '../utils/document_file_validation.dart';
import '../utils/safe_file_picker.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/chat_media_viewer.dart';
import '../widgets/jurii_empty_state.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/lawyer_recommendation_card.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/recommend_lawyer_sheet.dart';
import 'client_profile_screen.dart';
import 'intake_screen.dart';
import 'law_firm_profile_screen.dart';
import 'lawyer_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  final bool isLawyer;

  /// Propor caso é do advogado responsável pela conversa. O escritório não
  /// propõe mais caso — ele sugere um advogado ([canRecommendLawyer]).
  final bool canRequestCase;

  /// Escritório sugerindo um advogado da organização ao cliente. Ocupa, na
  /// barra do topo, o lugar do antigo botão de solicitar aceite do caso.
  final bool canRecommendLawyer;

  /// Serviço da triagem IA (injetável para testes; default via factory).
  final IntakeAIService? intakeService;

  /// A triagem só faz sentido quando quem vê o chat é o CLIENTE da conversa.
  /// Contextos de escritório (ex.: chat interno de equipe, que também abre
  /// com isLawyer=false) devem passar `false`.
  final bool allowTriage;

  /// Denunciar/bloquear é para conversa entre partes (cliente ↔
  /// profissional). O chat interno de equipe passa `false`: lá não existe
  /// "contraparte" e um membro poderia congelar o canal do escritório.
  final bool allowModeration;

  const ChatScreen({
    super.key,
    required this.conversation,
    required this.isLawyer,
    this.canRequestCase = true,
    this.canRecommendLawyer = false,
    this.intakeService,
    this.allowTriage = true,
    this.allowModeration = true,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MessagingRepository _repository = const MessagingRepository();
  final CaseRepository _caseRepository = const CaseRepository();
  final ProfileRepository _profileRepository = const ProfileRepository();
  final LawyerProfileRepository _lawyerProfileRepository =
      const LawyerProfileRepository();
  final LawFirmRepository _lawFirmRepository = const LawFirmRepository();

  /// Bucket de anexo é privado: foto e vídeo dentro do balão só aparecem com
  /// URL assinada. O cache vive junto da tela (morre com ela) e assina em lote.
  late final AttachmentUrlCache _mediaUrls = AttachmentUrlCache(
    signer: (paths, ttl) {
      if (!SupabaseConfig.isReady) return Future.value(const {});
      return _repository.createSignedAttachmentUrls(paths, ttl);
    },
  );

  /// Reassina antes do vencimento mesmo sem nada acontecer na conversa. Sem
  /// isto, um chat deixado aberto passa da validade da URL e TODA foto do
  /// histórico vira cartão de erro no primeiro rebuild — e nada a conserta até
  /// chegar mensagem nova.
  Timer? _mediaUrlRefreshTimer;

  RealtimeChannel? _messagesChannel;
  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _hasSubscribedOnce = false;
  bool _isSending = false;
  bool _isUploadingAttachment = false;
  bool _isOpeningProfile = false;
  bool _isCreatingCaseRequest = false;
  bool _isRecommendingLawyer = false;

  // Bloqueio congela a conversa para os dois lados; quem bloqueou destrava.
  bool _isBlocked = false;
  bool _blockedByMe = false;
  bool _isTogglingBlock = false;
  String? _respondingCaseRequestId;
  String? _openingRecommendedLawyerId;

  // Menu do botão "+" (anexo/triagem) e dica sutil da triagem.
  late final AnimationController _plusMenuController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _plusMenuAnimation = CurvedAnimation(
    parent: _plusMenuController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  bool _isPlusMenuOpen = false;
  bool _showTriageHint = false;
  bool _triageHintShown = false;
  bool _triageDotVisible = false;
  bool _isStartingTriage = false;
  bool _everHadMessages = false;
  Timer? _triageHintTimer;

  bool get _usesSupabase => widget.conversation.id != null;

  bool get _triageAvailable => !widget.isLawyer && widget.allowTriage;

  /// Banner de triagem: só para o cliente, apenas em conversa nova
  /// (sem nenhum histórico) — depois disso a triagem vive no botão "+".
  /// O latch [_everHadMessages] impede que um refresh que retorne vazio
  /// (queda de realtime, token expirando) ressuscite o banner numa conversa
  /// que já teve histórico.
  bool get _showTriageBanner =>
      _triageAvailable &&
      !_isLoading &&
      !_loadFailed &&
      _messages.isEmpty &&
      !_everHadMessages;

  // O interlocutor é o advogado sempre que a conversa tem lawyer_id — o type
  // é 'client_firm' até em conversa direta com advogado (herança do schema),
  // então decidir por ele rotularia o composer como "escritório".
  String get _triageCounterpartLabel =>
      widget.conversation.lawyerId != null ? 'advogado' : 'escritório';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
    // 10 minutos contra uma validade de 1 hora: qualquer tique cai dentro da
    // margem de renovação antes de a URL morrer, e o tique que não tem nada a
    // renovar não gera rede nem rebuild.
    _mediaUrlRefreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(_ensureMediaUrls()),
    );
  }

  @override
  void dispose() {
    final channel = _messagesChannel;
    if (channel != null && SupabaseConfig.isReady) {
      SupabaseConfig.client.removeChannel(channel);
    }
    _mediaUrlRefreshTimer?.cancel();
    _mediaUrls.clear();
    _triageHintTimer?.cancel();
    _plusMenuAnimation.dispose();
    _plusMenuController.dispose();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    if (!_usesSupabase) {
      setState(() {
        _messages = _mockMessages();
        _isLoading = false;
      });
      _scrollToBottom();
      return;
    }

    // O estado de bloqueio viaja em future PRÓPRIA, fail-open: se só esta
    // leitura falhar (RPC ainda não aplicada, sessão expirada), as mensagens
    // continuam aparecendo — quem trava envio de verdade é o servidor.
    unawaited(_refreshBlockState());

    try {
      final messages = await _messagesWithPendingCaseRequestFallback(
        await _repository.fetchMessages(widget.conversation.id!),
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
        _loadFailed = false;
      });
      unawaited(_ensureMediaUrls());
      _scrollToBottom();
    } catch (error) {
      debugPrint('Supabase messages fetch failed: $error');
      if (!mounted) return;
      setState(() {
        _messages = _usesSupabase ? const [] : _mockMessages();
        _isLoading = false;
        // Falha de rede não pode parecer conversa vazia: mostra erro + retry.
        _loadFailed = _usesSupabase;
      });
      _scrollToBottom();
    }
  }

  /// Assina em UM lote as mídias que a lista precisa desenhar. Chamado depois
  /// de carregar e a cada mensagem nova — a segunda chamada não repete o que já
  /// está assinado, então sai barata.
  Future<void> _ensureMediaUrls() async {
    if (!_usesSupabase || !SupabaseConfig.isReady) return;

    final paths = _messages
        .map((message) => message.attachment)
        .whereType<ChatAttachment>()
        .where((attachment) => attachment.isMedia)
        .map((attachment) => attachment.storagePath)
        .toList();
    if (paths.isEmpty) return;

    final before = paths.map(_mediaUrls.cachedUrlFor).toList();
    // `ensureUrls` marca os caminhos como em voo ANTES do primeiro await, então
    // o quadro que está sendo montado agora já mostra esqueleto — e não o
    // cartão de "não foi possível carregar", que seria o estado de URL ausente.
    await _mediaUrls.ensureUrls(paths);
    if (!mounted) return;

    // O balão lê a URL do cache no build; sem este setState a foto só
    // apareceria na próxima vez que a tela se redesenhasse por outro motivo.
    // Comparar antes/depois evita que o tique periódico (que quase sempre não
    // tem o que renovar) redesenhe a conversa inteira de dez em dez minutos.
    final after = paths.map(_mediaUrls.cachedUrlFor).toList();
    if (!listEquals(before, after)) setState(() {});
  }

  /// Nova tentativa para uma mídia que não carregou: joga fora a URL guardada
  /// (reusá-la repetiria a falha) e assina outra.
  ///
  /// [automatic] é a recuperação disparada pelo próprio download que falhou —
  /// essa tem teto de UMA por anexo enquanto a tela viver. Sem o teto vira
  /// laço: assinar gera URL nova, URL nova recria o balão, o balão baixa e
  /// falha de novo. Para um objeto que sumiu do bucket isso não converge, e o
  /// custo é rede e bateria de quem só está lendo a conversa. O toque em
  /// "Tentar de novo" ([automatic] falso) não tem teto: é decisão da pessoa.
  Future<void> _retryMedia(
    ChatAttachment attachment, {
    required bool automatic,
  }) async {
    if (automatic) {
      if (!_mediaUrls.forgetForAutoRetry(attachment.storagePath)) return;
    } else {
      _mediaUrls.forget(attachment.storagePath);
    }
    if (mounted) setState(() {});
    await _ensureMediaUrls();
  }

  void _subscribeToMessages() {
    final conversationId = widget.conversation.id;
    if (conversationId == null || !SupabaseConfig.isReady) return;

    _messagesChannel = SupabaseConfig.client
        .channel('conversation_messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            unawaited(_appendRealtimeMessage(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            unawaited(_upsertRealtimeMessage(payload.newRecord));
          },
        )
        .subscribe((status, [error]) {
          // O Supabase não reenvia eventos perdidos: ao reassinar depois de
          // uma queda, refaz o fetch (o dedupe por id absorve repetidos).
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (_hasSubscribedOnce) {
              unawaited(_refreshMessagesSilently());
            }
            _hasSubscribedOnce = true;
          }
        });
  }

  Future<void> _appendRealtimeMessage(Map<String, dynamic> row) async {
    final message = await _repository.messageFromRowWithAttachment(
      row,
      currentUserId: SupabaseConfig.client.auth.currentUser?.id,
    );
    _appendMessage(message);
  }

  Future<void> _upsertRealtimeMessage(Map<String, dynamic> row) async {
    final message = await _repository.messageFromRowWithAttachment(
      row,
      currentUserId: SupabaseConfig.client.auth.currentUser?.id,
    );
    _upsertMessage(message);
  }

  List<ChatMessage> _mockMessages() {
    return mockChatMessages
        .where(
          (message) =>
              message.conversationKey == widget.conversation.officeName,
        )
        .toList();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    _closePlusMenu();
    _messageController.clear();
    await _sendText(text);
  }

  /// Envia [text] na conversa. Retorna `true` quando a mensagem foi de fato
  /// enviada/anexada — o fluxo da triagem depende disso para nunca perder o
  /// resumo em silêncio.
  Future<bool> _sendText(
    String text, {
    bool countsAsBannerIgnored = true,
    bool restoreToComposerOnFailure = true,
    bool showErrorSnackBar = true,
  }) async {
    if (text.isEmpty || _isSending) return false;

    // O banner some com a primeira mensagem; se ele estava visível e o cliente
    // preferiu escrever direto, mostramos a dica de que a triagem mora no "+".
    final ignoredTriageBanner = countsAsBannerIgnored && _showTriageBanner;

    if (!_usesSupabase) {
      _appendMessage(
        ChatMessage(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          conversationKey: widget.conversation.officeName,
          author: MessageAuthor.me,
          text: text,
          time: 'Agora',
          read: false,
        ),
      );
      _maybeShowTriageHint(ignoredTriageBanner);
      return true;
    }

    setState(() => _isSending = true);
    try {
      final message = await _repository.sendMessage(
        conversationId: widget.conversation.id!,
        body: text,
        senderType: widget.isLawyer ? 'lawyer' : 'client',
      );
      if (!mounted) return false;
      _appendMessage(message);
      setState(() => _isSending = false);
      _maybeShowTriageHint(ignoredTriageBanner);
      return true;
    } catch (error) {
      debugPrint('Supabase message send failed: $error');
      if (!mounted) return false;
      setState(() => _isSending = false);
      // A outra parte pode ter bloqueado depois que a tela abriu: o servidor
      // recusa e a UI passa a refletir o congelamento. O refetch corrige
      // também o blockedByMe (bloqueio meu feito em outro aparelho).
      if (error.toString().contains('conversation_blocked')) {
        setState(() => _isBlocked = true);
        _closePlusMenu();
        unawaited(_refreshBlockState());
        if (showErrorSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Esta conversa está bloqueada.')),
          );
        }
        return false;
      }
      if (showErrorSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
        );
      }
      // Restaura o texto só se o usuário não começou outro rascunho.
      if (restoreToComposerOnFailure &&
          _messageController.text.trim().isEmpty) {
        _messageController.text = text;
      }
      return false;
    }
  }

  void _togglePlusMenu() {
    // O menu ocupa o mesmo espaço do teclado, e os dois abertos ao mesmo tempo
    // não cabem em tela pequena — o composer (campo e botão enviar) era
    // empurrado para fora. Quem toca no "+" quer anexar, não digitar.
    if (!_isPlusMenuOpen) FocusScope.of(context).unfocus();
    setState(() {
      _isPlusMenuOpen = !_isPlusMenuOpen;
      if (_isPlusMenuOpen) {
        // Abriu o menu: a triagem foi "descoberta" — dica e ponto saem de
        // cena e não voltam a disparar depois.
        _triageHintShown = true;
        _triageDotVisible = false;
        _showTriageHint = false;
        _triageHintTimer?.cancel();
        _plusMenuController.forward();
      } else {
        _plusMenuController.reverse();
      }
    });
  }

  void _closePlusMenu() {
    if (_isPlusMenuOpen) _togglePlusMenu();
  }

  void _maybeShowTriageHint(bool ignoredTriageBanner) {
    if (!ignoredTriageBanner ||
        _triageHintShown ||
        !_triageAvailable ||
        !mounted) {
      return;
    }
    _triageHintShown = true;
    setState(() {
      _showTriageHint = true;
      _triageDotVisible = true;
    });
    _triageHintTimer?.cancel();
    _triageHintTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _showTriageHint = false);
    });
  }

  /// Abre a triagem com a assistente e, se o cliente confirmar no resumo,
  /// envia a overview como mensagem nesta conversa — é assim que o
  /// advogado/escritório recebe o caso organizado para avaliar.
  Future<void> _startTriage() async {
    // Double-tap no banner/menu não pode empilhar duas triagens.
    if (_isStartingTriage) return;
    _isStartingTriage = true;
    try {
      await _runTriageFlow();
    } finally {
      _isStartingTriage = false;
    }
  }

  Future<void> _runTriageFlow() async {
    _closePlusMenu();

    final result = await Navigator.of(context).push<IntakeChatResult>(
      PageRouteBuilder<IntakeChatResult>(
        transitionDuration: JuriiMotion.standard,
        reverseTransitionDuration: JuriiMotion.fast,
        pageBuilder: (_, _, _) => IntakeScreen(
          service: widget.intakeService,
          counterpartLabel: _triageCounterpartLabel,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: JuriiMotion.ease,
            reverseCurve: JuriiMotion.exitEase,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );

    if (!mounted || result == null) return;
    await _sendTriageOverview(
      'Triagem da assistente Jurii\n\n${result.overviewText}',
    );
  }

  /// O resumo da triagem não pode se perder em silêncio: a sessão é só em
  /// memória e a tela já fechou. Falhou (rede ou outro envio em andamento)?
  /// Snackbar com "Tentar de novo" reenviando o mesmo texto.
  Future<void> _sendTriageOverview(String overviewMessage) async {
    // Enviar o resumo é usar a triagem — não conta como "ignorou o banner".
    final sent = await _sendText(
      overviewMessage,
      countsAsBannerIgnored: false,
      restoreToComposerOnFailure: false,
      showErrorSnackBar: false,
    );
    if (sent || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('O resumo da triagem ainda não foi enviado.'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Tentar de novo',
          onPressed: () => _sendTriageOverview(overviewMessage),
        ),
      ),
    );
  }

  Future<void> _sendAttachment() async {
    if (_isUploadingAttachment) return;

    if (!_usesSupabase || !SupabaseConfig.isReady) {
      _showSnackBar('Anexos estão disponíveis apenas em conversas online.');
      return;
    }

    final SafePickedFile? file;
    try {
      file = await pickSingleFile(
        allowedExtensions: chatAttachmentAllowedExtensions,
      );
    } catch (error) {
      // Permissão negada era um toque sem nenhuma resposta.
      debugPrint('Attachment picker failed: $error');
      if (mounted) {
        _showSnackBar(
          'Não foi possível abrir o seletor de arquivos. '
          'Verifique as permissões do app nos Ajustes.',
        );
      }
      return;
    }
    if (file == null || !mounted) return;

    final mimeType = chatAttachmentMimeType(file.name);
    final kind = chatAttachmentKindForMime(mimeType);

    if (mimeType == null || kind == null) {
      _showSnackBar(
        'Envie apenas fotos, vídeos (MP4 ou MOV), PDF, DOC ou DOCX.',
      );
      return;
    }

    // Tamanho ANTES de ler os bytes: a leitura só acontece dentro do teto.
    if (file.size > maxChatAttachmentBytes(kind)) {
      _showSnackBar(chatAttachmentSizeLimitMessage(kind));
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readBytes();
    } catch (error) {
      debugPrint('Attachment read failed: $error');
      if (mounted) {
        _showSnackBar('Não foi possível ler o arquivo selecionado.');
      }
      return;
    }
    if (!mounted) return;

    if (bytes.isEmpty) {
      _showSnackBar('Não foi possível ler o arquivo selecionado.');
      return;
    }

    if (!bytesMatchMimeType(bytes, mimeType)) {
      _showSnackBar('Arquivo inválido ou corrompido.');
      return;
    }

    await _uploadAttachment(
      fileName: file.name,
      mimeType: mimeType,
      kind: kind,
      bytes: bytes,
    );
  }

  /// Foto pela galeria ou câmera via image_picker: no iOS o plugin re-encoda
  /// para JPEG — é o que faz foto de iPhone (HEIC) chegar num formato que
  /// todos os aparelhos abrem. maxWidth também segura o tamanho do upload.
  Future<void> _sendPhoto(ImageSource source) async {
    if (_isUploadingAttachment) return;

    if (!_usesSupabase || !SupabaseConfig.isReady) {
      _showSnackBar('Anexos estão disponíveis apenas em conversas online.');
      return;
    }

    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2560,
        imageQuality: 85,
      );
    } catch (error) {
      debugPrint('Image picker failed: $error');
      if (mounted) {
        _showSnackBar(
          source == ImageSource.camera
              ? 'Não foi possível abrir a câmera. '
                    'Verifique a permissão nos Ajustes.'
              : 'Não foi possível abrir a galeria. '
                    'Verifique a permissão nos Ajustes.',
        );
      }
      return;
    }
    if (photo == null) return;

    final size = await photo.length();
    if (!mounted) return;
    if (size > maxChatImageBytes) {
      _showSnackBar(chatAttachmentSizeLimitMessage(ChatAttachmentKind.image));
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await photo.readAsBytes();
    } catch (error) {
      debugPrint('Photo read failed: $error');
      if (mounted) _showSnackBar('Não foi possível ler a foto.');
      return;
    }
    if (!mounted) return;

    if (bytes.isEmpty || !bytesMatchMimeType(bytes, 'image/jpeg')) {
      _showSnackBar('Não foi possível ler a foto.');
      return;
    }

    await _uploadAttachment(
      fileName: 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg',
      mimeType: 'image/jpeg',
      kind: ChatAttachmentKind.image,
      bytes: bytes,
    );
  }

  /// Vídeo pela câmera ou pela galeria.
  ///
  /// Diferente da foto, NÃO existe recompressão: o image_picker do Android
  /// entrega o arquivo original e o do iOS grava em qualidade alta e só copia.
  /// O teto de 25 MB é, portanto, a única coisa entre a galeria do usuário e a
  /// conta de Storage — e por isso o tamanho é conferido ANTES de ler os bytes.
  Future<void> _sendVideo(ImageSource source) async {
    if (_isUploadingAttachment) return;

    if (!_usesSupabase || !SupabaseConfig.isReady) {
      _showSnackBar('Anexos estão disponíveis apenas em conversas online.');
      return;
    }

    final XFile? video;
    try {
      video = await ImagePicker().pickVideo(
        source: source,
        // Corta a GRAVAÇÃO em 1 minuto. Vídeo escolhido na galeria ignora este
        // limite (o sistema não recorta o que já existe) e é barrado adiante
        // pelo tamanho — o teto de bytes é quem vale nos dois caminhos.
        maxDuration: const Duration(minutes: 1),
      );
    } catch (error) {
      debugPrint('Video picker failed: $error');
      if (mounted) {
        _showSnackBar(
          source == ImageSource.camera
              ? 'Não foi possível abrir a câmera. '
                    'Verifique as permissões de câmera e microfone nos Ajustes.'
              : 'Não foi possível abrir a galeria. '
                    'Verifique a permissão nos Ajustes.',
        );
      }
      return;
    }
    if (video == null) return;

    // A extensão vem do arquivo que o sistema entregou (.MOV no iPhone,
    // .mp4 no Android). Formato fora dos dois é recusado aqui em vez de subir
    // para o bucket recusar depois — o upload já teria custado a rede.
    final mimeType = chatAttachmentMimeType(video.name);
    if (mimeType == null ||
        chatAttachmentKindForMime(mimeType) != ChatAttachmentKind.video) {
      _showSnackBar('Envie vídeos em MP4 ou MOV.');
      return;
    }

    final size = await video.length();
    if (!mounted) return;
    if (size > maxChatVideoBytes) {
      _showSnackBar(chatAttachmentSizeLimitMessage(ChatAttachmentKind.video));
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await video.readAsBytes();
    } catch (error) {
      debugPrint('Video read failed: $error');
      if (mounted) _showSnackBar('Não foi possível ler o vídeo.');
      return;
    }
    if (!mounted) return;

    if (bytes.isEmpty || !bytesMatchMimeType(bytes, mimeType)) {
      _showSnackBar('Vídeo inválido ou corrompido.');
      return;
    }

    await _uploadAttachment(
      fileName: video.name,
      mimeType: mimeType,
      kind: ChatAttachmentKind.video,
      bytes: bytes,
    );
  }

  Future<void> _uploadAttachment({
    required String fileName,
    required String mimeType,
    required ChatAttachmentKind kind,
    required Uint8List bytes,
  }) async {
    final ignoredTriageBanner = _showTriageBanner;
    setState(() => _isUploadingAttachment = true);
    try {
      final message = await _repository.sendAttachment(
        conversationId: widget.conversation.id!,
        fileName: fileName,
        mimeType: mimeType,
        fileSizeBytes: bytes.length,
        bytes: bytes,
        kind: kind,
        senderType: widget.isLawyer ? 'lawyer' : 'client',
      );
      if (!mounted) return;
      _appendMessage(message);
      _maybeShowTriageHint(ignoredTriageBanner);
    } catch (error) {
      debugPrint('Supabase attachment send failed: $error');
      if (!mounted) return;
      // Mesmo tratamento do envio de texto: anexo recusado por bloqueio
      // congela a UI (senão dava para tentar de novo indefinidamente).
      if (error.toString().contains('conversation_blocked')) {
        setState(() => _isBlocked = true);
        _closePlusMenu();
        unawaited(_refreshBlockState());
      }
      _showSnackBar(_friendlyAttachmentError(error));
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<void> _openAttachment(ChatAttachment attachment) async {
    if (!SupabaseConfig.isReady) return;

    try {
      // Mídia já tem URL assinada no cache (é ela que desenha a prévia):
      // reaproveitar evita uma ida ao servidor a cada toque. Documento não
      // passa pelo cache — assina na hora, com prazo curto.
      final signedUrl =
          (attachment.isMedia
              ? _mediaUrls.cachedUrlFor(attachment.storagePath)
              : null) ??
          await _repository.createSignedAttachmentUrl(attachment);
      if (!mounted) return;

      if (attachment.isMedia) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ChatMediaViewerPage(
              attachment: attachment,
              signedUrl: signedUrl,
            ),
          ),
        );
        return;
      }

      final uri = Uri.parse(signedUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showSnackBar('Não foi possível abrir o arquivo.');
      }
    } catch (error) {
      debugPrint('Supabase attachment open failed: $error');
      if (!mounted) return;
      _showSnackBar('Não foi possível abrir o anexo.');
    }
  }

  String _friendlyAttachmentError(Object error) {
    final message = error.toString().toLowerCase();
    debugPrint('Chat attachment error: $error');
    if (message.contains('conversation_blocked')) {
      return 'Esta conversa está bloqueada.';
    }
    if ((message.contains('metadata') && message.contains('ambiguous')) ||
        message.contains('42702')) {
      return 'Não foi possível enviar o anexo. Tente novamente mais tarde.';
    }
    if (message.contains('send_chat_attachment') ||
        message.contains('chat-attachments') ||
        message.contains('message_attachments') ||
        message.contains('pgrst202') ||
        message.contains('schema cache')) {
      return 'Não foi possível enviar o anexo. Tente novamente mais tarde.';
    }
    if (message.contains('row-level security') ||
        message.contains('permission denied')) {
      return 'Você não tem permissão para enviar anexos nesta conversa.';
    }
    return 'Não foi possível enviar o anexo.';
  }

  Future<void> _openReportSheet() async {
    final draft = await showModalBottomSheet<_ReportDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ReportSheet(),
    );
    if (draft == null || !mounted) return;

    try {
      await _repository.reportConversation(
        conversationId: widget.conversation.id!,
        reason: draft.reason,
        details: draft.details.isEmpty ? null : draft.details,
      );
      if (!mounted) return;
      _showSnackBar('Denúncia enviada. Nossa equipe vai analisar.');
    } catch (error) {
      debugPrint('Conversation report failed: $error');
      if (!mounted) return;
      _showSnackBar(
        error.toString().contains('Report limit')
            ? 'Você atingiu o limite de denúncias de hoje.'
            : 'Não foi possível enviar a denúncia. Tente novamente.',
      );
    }
  }

  Future<void> _confirmBlockConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bloquear conversa?'),
        content: const Text(
          'Nenhum dos dois lados poderá enviar novas mensagens até você '
          'desbloquear. As mensagens já trocadas continuam visíveis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _setConversationBlocked(true);
  }

  /// Fail-open: quem trava o envio de verdade é o trigger no servidor; se
  /// esta leitura falhar, a tela continua utilizável com o estado que tinha.
  Future<void> _refreshBlockState() async {
    if (!_usesSupabase || !SupabaseConfig.isReady) return;
    try {
      final state = await _repository.fetchConversationBlockState(
        widget.conversation.id!,
      );
      if (!mounted) return;
      if (state.isBlocked != _isBlocked || state.blockedByMe != _blockedByMe) {
        setState(() {
          _isBlocked = state.isBlocked;
          _blockedByMe = state.blockedByMe;
        });
        if (state.isBlocked) _closePlusMenu();
      }
    } catch (error) {
      debugPrint('Block state refresh failed: $error');
    }
  }

  Future<void> _setConversationBlocked(bool blocked) async {
    if (_isTogglingBlock) return;
    setState(() => _isTogglingBlock = true);
    try {
      if (blocked) {
        await _repository.blockConversation(widget.conversation.id!);
      } else {
        await _repository.unblockConversation(widget.conversation.id!);
      }
      // Depois de desbloquear, a conversa pode CONTINUAR bloqueada pela
      // outra parte — o estado real vem do servidor, não da intenção local.
      final state = await _repository.fetchConversationBlockState(
        widget.conversation.id!,
      );
      if (!mounted) return;
      setState(() {
        _isBlocked = state.isBlocked;
        _blockedByMe = state.blockedByMe;
      });
    } catch (error) {
      debugPrint('Conversation block toggle failed: $error');
      if (!mounted) return;
      _showSnackBar('Não foi possível concluir. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isTogglingBlock = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _appendMessage(ChatMessage message) {
    if (!mounted ||
        _shouldHideCaseRequestStatusText(message) ||
        _messages.any((item) => item.id == message.id)) {
      return;
    }
    // Conversa bloqueada não recebe mensagem nova (trigger no servidor);
    // se uma chegou pelo realtime, a outra parte desbloqueou — sem isto,
    // quem foi bloqueado ficava preso na barra sem conseguir responder.
    if (_isBlocked) unawaited(_refreshBlockState());
    setState(
      () => _messages = [..._withoutDuplicateCaseRequest(message), message],
    );
    unawaited(_ensureMediaUrls());
    _scrollToBottom();
  }

  void _upsertMessage(ChatMessage message) {
    if (!mounted) return;

    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      if (_shouldHideCaseRequestStatusText(message)) return;
      setState(
        () => _messages = [..._withoutDuplicateCaseRequest(message), message],
      );
      unawaited(_ensureMediaUrls());
      _scrollToBottom();
      return;
    }

    final nextMessages = [..._messages];
    nextMessages[index] = message;
    setState(() => _messages = nextMessages);
    unawaited(_ensureMediaUrls());
  }

  /// Remove o card sintético de solicitação de caso (id `case_request_<id>`)
  /// quando a mensagem real da mesma solicitação chega via realtime —
  /// sem isso o cliente veria a solicitação duplicada com dois pares de botões.
  List<ChatMessage> _withoutDuplicateCaseRequest(ChatMessage incoming) {
    final requestId = incoming.caseRequestId;
    if (requestId == null) return _messages;
    return _messages
        .where(
          (item) => item.id == incoming.id || item.caseRequestId != requestId,
        )
        .toList(growable: false);
  }

  bool _shouldHideCaseRequestStatusText(ChatMessage message) {
    if (message.isCaseRequest || message.author != MessageAuthor.system) {
      return false;
    }

    final text = message.text.trim().toLowerCase();
    return text == 'solicitação de caso aceita pelo cliente.' ||
        text == 'solicitação de caso recusada pelo cliente.';
  }

  Future<void> _refreshMessagesSilently() async {
    final conversationId = widget.conversation.id;
    if (conversationId == null) return;

    // Reassinar o canal é o momento de reconferir o bloqueio também: eventos
    // de conversation_blocks não chegam por realtime (tabela trancada).
    unawaited(_refreshBlockState());

    final messages = await _messagesWithPendingCaseRequestFallback(
      await _repository.fetchMessages(conversationId),
    );
    if (!mounted) return;
    setState(() => _messages = messages);
    unawaited(_ensureMediaUrls());
    _scrollToBottom();
  }

  Future<List<ChatMessage>> _messagesWithPendingCaseRequestFallback(
    List<ChatMessage> messages,
  ) async {
    final conversationId = widget.conversation.id;
    if (widget.isLawyer || conversationId == null || !SupabaseConfig.isReady) {
      return messages;
    }

    try {
      final requests = await _caseRepository.fetchClientCaseRequests();
      final fallbackMessages = requests
          .where((request) => request.conversationId == conversationId)
          .where(
            (request) =>
                !messages.any((message) => message.caseRequestId == request.id),
          )
          .map(_caseRequestFallbackMessage)
          .toList();

      return [
        ...messages.where(
          (message) => !_shouldHideCaseRequestStatusText(message),
        ),
        ...fallbackMessages,
      ];
    } catch (error) {
      debugPrint('Supabase case request fallback fetch failed: $error');
      return messages;
    }
  }

  ChatMessage _caseRequestFallbackMessage(CaseRequest request) {
    return ChatMessage(
      id: 'case_request_${request.id}',
      conversationKey: request.conversationId,
      author: MessageAuthor.system,
      text: 'Solicitação de aceite do caso: ${request.title}',
      time: request.createdAtLabel,
      read: false,
      metadata: {
        'type': 'case_request',
        'case_request_id': request.id,
        'request_status': 'pending',
        'conversation_id': request.conversationId,
        'title': request.title,
        'area': request.area,
      },
    );
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

  Future<void> _openCounterpartProfile() async {
    if (_isOpeningProfile || !SupabaseConfig.isReady) return;
    setState(() => _isOpeningProfile = true);

    try {
      if (widget.isLawyer && widget.conversation.clientId != null) {
        final profile = await _profileRepository.fetchProfileById(
          widget.conversation.clientId!,
        );
        if (!mounted) return;
        if (profile == null) throw StateError('Client profile not found.');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientProfileScreen(profile: profile),
          ),
        );
        return;
      }

      // Conversa direta com advogado carrega TAMBÉM o law_firm_id do vínculo
      // (para o painel do escritório enxergá-la) — por isso o advogado tem
      // precedência aqui: o interlocutor do cliente é ele, não o escritório.
      if (!widget.isLawyer && widget.conversation.lawyerId != null) {
        final lawyer = await _lawyerProfileRepository.fetchLawyerById(
          widget.conversation.lawyerId!,
        );
        if (!mounted) return;
        if (lawyer == null) throw StateError('Lawyer profile not found.');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LawyerProfileScreen(lawyer: lawyer),
          ),
        );
        return;
      }

      if (!widget.isLawyer && widget.conversation.lawFirmId != null) {
        final lawFirm = await _lawFirmRepository.fetchLawFirmById(
          widget.conversation.lawFirmId!,
        );
        if (!mounted) return;
        if (lawFirm == null) throw StateError('Law firm profile not found.');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LawFirmProfileScreen(lawFirm: lawFirm),
          ),
        );
        return;
      }

      throw StateError('Conversation profile not available.');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o perfil.')),
      );
    } finally {
      if (mounted) setState(() => _isOpeningProfile = false);
    }
  }

  // Os dois fluxos inserem mensagem no servidor — conversa bloqueada
  // recusaria de qualquer jeito; melhor nem oferecer o formulário.
  bool get _canRequestCase {
    return widget.isLawyer &&
        widget.canRequestCase &&
        _usesSupabase &&
        !_isBlocked &&
        widget.conversation.clientId != null;
  }

  bool get _canRecommendLawyer {
    return widget.canRecommendLawyer &&
        _usesSupabase &&
        !_isBlocked &&
        widget.conversation.lawFirmId != null;
  }

  Future<void> _openRecommendLawyerSheet() async {
    final lawFirmId = widget.conversation.lawFirmId;
    final conversationId = widget.conversation.id;
    if (_isRecommendingLawyer || lawFirmId == null || conversationId == null) {
      return;
    }

    final lawyerId = await showRecommendLawyerSheet(
      context,
      lawFirmId: lawFirmId,
    );
    if (!mounted || lawyerId == null) return;

    setState(() => _isRecommendingLawyer = true);

    try {
      await _repository.recommendLawyer(
        conversationId: conversationId,
        lawyerId: lawyerId,
      );
      await _refreshMessagesSilently();
      if (!mounted) return;
      _showSnackBar('Advogado sugerido ao cliente.');
    } catch (error) {
      debugPrint('Supabase lawyer recommendation failed: $error');
      if (!mounted) return;
      // A sugestão vira mensagem no servidor: bloqueio recusa e a UI congela.
      if (error.toString().contains('conversation_blocked')) {
        setState(() => _isBlocked = true);
        unawaited(_refreshBlockState());
        _showSnackBar('Esta conversa está bloqueada.');
      } else {
        _showSnackBar('Não foi possível sugerir o advogado.');
      }
    } finally {
      if (mounted) setState(() => _isRecommendingLawyer = false);
    }
  }

  /// O cliente aceitou a sugestão: abre (ou recupera) a conversa com o
  /// advogado indicado. É lá que o caso será proposto.
  Future<void> _openRecommendedLawyerChat(
    LawyerRecommendation recommendation,
  ) async {
    if (_openingRecommendedLawyerId != null || !SupabaseConfig.isReady) return;

    setState(() => _openingRecommendedLawyerId = recommendation.lawyerId);

    try {
      final conversation = await _repository.startLawyerConversationById(
        recommendation.lawyerId,
      );
      if (!mounted) return;
      setState(() => _openingRecommendedLawyerId = null);

      // A conversa com o advogado pode ser ESTA aqui (ex.: a sugestão foi
      // enviada dentro da própria conversa dele). Empilhar outra tela igual
      // criaria uma pilha infinita de chats idênticos.
      if (conversation.id == widget.conversation.id) {
        _showSnackBar('Você já está na conversa com este advogado.');
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(conversation: conversation, isLawyer: false),
        ),
      );
    } catch (error) {
      debugPrint('Supabase recommended lawyer conversation failed: $error');
      if (!mounted) return;
      setState(() => _openingRecommendedLawyerId = null);
      _showSnackBar('Não foi possível abrir a conversa com o advogado.');
    }
  }

  Future<void> _openCaseRequestSheet() async {
    if (_isCreatingCaseRequest) return;

    final draft = await showModalBottomSheet<_CaseRequestDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _CaseRequestSheet(initialTitle: widget.conversation.specialty),
    );

    if (!mounted || draft == null || widget.conversation.id == null) return;
    setState(() => _isCreatingCaseRequest = true);

    try {
      await _caseRepository.createCaseRequest(
        conversationId: widget.conversation.id!,
        title: draft.title,
        area: draft.area,
        summary: draft.summary,
      );
      await _refreshMessagesSilently();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitação enviada ao cliente.')),
      );
    } catch (error) {
      debugPrint('Supabase case request failed: $error');
      if (!mounted) return;
      // A solicitação também insere mensagem: bloqueio recusa e a UI congela.
      if (error.toString().contains('conversation_blocked')) {
        setState(() => _isBlocked = true);
        unawaited(_refreshBlockState());
        _showSnackBar('Esta conversa está bloqueada.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível enviar a solicitação.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingCaseRequest = false);
    }
  }

  Future<void> _respondToCaseRequestFromChat(
    ChatMessage message, {
    required bool accepted,
  }) async {
    final requestId = message.caseRequestId;
    if (requestId == null || _respondingCaseRequestId != null) return;

    setState(() => _respondingCaseRequestId = requestId);

    try {
      await _caseRepository.respondToCaseRequest(
        requestId: requestId,
        accepted: accepted,
      );
      await _refreshMessagesSilently();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? 'Caso aceito.' : 'Caso recusado.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível responder ao caso.')),
      );
    } finally {
      if (mounted) setState(() => _respondingCaseRequestId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Latch do banner: conversa que já exibiu mensagem alguma vez nunca volta
    // a contar como "nova" (atribuição direta, sem setState — só trava um
    // estado que o rebuild atual já reflete).
    if (_messages.isNotEmpty) _everHadMessages = true;

    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        titleSpacing: 0,
        title: InkWell(
          onTap: _isOpeningProfile ? null : _openCounterpartProfile,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                if (_isOpeningProfile)
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: widget.isLawyer
                        ? colors.lightGold
                        : colors.lightBlue,
                    child: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  ProfileAvatar(
                    imageUrl: widget.conversation.avatarUrl,
                    initials: widget.conversation.initials,
                    size: 36,
                    backgroundColor: widget.isLawyer
                        ? colors.lightGold
                        : colors.lightBlue,
                    foregroundColor: widget.isLawyer
                        ? colors.accent
                        : colors.primary,
                    borderRadius: BorderRadius.circular(18),
                    fontSize: 12,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.conversation.officeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.conversation.specialty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_canRequestCase)
            IconButton(
              onPressed: _isCreatingCaseRequest ? null : _openCaseRequestSheet,
              icon: _isCreatingCaseRequest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_add),
              tooltip: 'Enviar solicitação de caso',
            ),
          if (_canRecommendLawyer)
            IconButton(
              onPressed: _isRecommendingLawyer
                  ? null
                  : _openRecommendLawyerSheet,
              icon: _isRecommendingLawyer
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.recommend_outlined),
              tooltip: 'Sugerir advogado',
            ),
          if (_usesSupabase && widget.allowModeration)
            PopupMenuButton<String>(
              tooltip: 'Opções da conversa',
              onSelected: (value) {
                switch (value) {
                  case 'report':
                    _openReportSheet();
                  case 'block':
                    _confirmBlockConversation();
                  case 'unblock':
                    _setConversationBlocked(false);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'report', child: Text('Denunciar')),
                if (!_isBlocked)
                  const PopupMenuItem(
                    value: 'block',
                    child: Text('Bloquear conversa'),
                  )
                else if (_blockedByMe)
                  const PopupMenuItem(
                    value: 'unblock',
                    child: Text('Desbloquear conversa'),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        // O menu "+" precisa saber quanto espaço REAL sobra (barra e teclado já
        // descontados) para se limitar em vez de empurrar o composer para fora.
        child: LayoutBuilder(
          builder: (context, bodyConstraints) {
            // Reserva fixa para o composer e um naco da conversa; o menu
            // fica com o resto e rola quando não couber. Fração pura não
            // servia: a que cabia com o teclado aberto encolhia o menu à
            // toa no caso normal, que é o teclado fechado.
            final plusMenuMaxHeight = math.max(
              0.0,
              bodyConstraints.maxHeight - 180,
            );
            return Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: _showTriageBanner
                      ? _TriageBanner(
                          counterpartLabel: _triageCounterpartLabel,
                          onTap: _startTriage,
                        )
                      : const SizedBox(width: double.infinity),
                ),
                Expanded(
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: JuriiSkeletonList(
                            itemCount: 6,
                            itemHeight: 72,
                            gap: 10,
                          ),
                        )
                      : _loadFailed && _messages.isEmpty
                      ? _ChatLoadErrorState(onRetry: _loadMessages)
                      : _messages.isEmpty
                      ? const _EmptyChatState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final fromRight =
                                message.author == MessageAuthor.me;
                            final mediaPath =
                                message.attachment?.isMedia == true
                                ? message.attachment!.storagePath
                                : null;
                            return JuriiStaggeredItem(
                              key: ValueKey('chat_message_${message.id}'),
                              index: index,
                              beginOffset: Offset(fromRight ? 18 : -18, 8),
                              child: _MessageBubble(
                                message: message,
                                counterpartName: widget.conversation.officeName,
                                counterpartInitials:
                                    widget.conversation.initials,
                                canRespondToCaseRequest:
                                    !widget.isLawyer &&
                                    message.isPendingCaseRequest,
                                isRespondingCaseRequest:
                                    _respondingCaseRequestId ==
                                    message.caseRequestId,
                                // Só o cliente aciona o advogado sugerido; para o
                                // escritório o card é o registro da sugestão.
                                canMessageRecommendedLawyer: !widget.isLawyer,
                                isOpeningRecommendedLawyerChat:
                                    _openingRecommendedLawyerId != null &&
                                    _openingRecommendedLawyerId ==
                                        message.lawyerRecommendation?.lawyerId,
                                onMessageRecommendedLawyer:
                                    _openRecommendedLawyerChat,
                                onAcceptCaseRequest: () =>
                                    _respondToCaseRequestFromChat(
                                      message,
                                      accepted: true,
                                    ),
                                onDeclineCaseRequest: () =>
                                    _respondToCaseRequestFromChat(
                                      message,
                                      accepted: false,
                                    ),
                                onOpenAttachment: _openAttachment,
                                onRetryMedia: (attachment) => unawaited(
                                  _retryMedia(attachment, automatic: false),
                                ),
                                onAutoRetryMedia: (attachment) => unawaited(
                                  _retryMedia(attachment, automatic: true),
                                ),
                                mediaUrl: mediaPath == null
                                    ? null
                                    : _mediaUrls.cachedUrlFor(mediaPath),
                                isLoadingMediaUrl:
                                    mediaPath != null &&
                                    _mediaUrls.isPending(mediaPath),
                              ),
                            );
                          },
                        ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: _showTriageHint && !_isBlocked
                      ? const _TriageHintChip()
                      : const SizedBox(width: double.infinity),
                ),
                // Menu do "+": abre deslizando para cima, junto do composer.
                // Fora da árvore quando fechado (não fica "invisível" clicável)
                // e quando a conversa bloqueia (senão ficava órfão e clicável
                // sobre a barra de bloqueio, sem botão para fechá-lo).
                AnimatedBuilder(
                  animation: _plusMenuController,
                  builder: (context, _) {
                    if (_plusMenuController.isDismissed || _isBlocked) {
                      return const SizedBox(width: double.infinity);
                    }
                    return ClipRect(
                      child: SizeTransition(
                        sizeFactor: _plusMenuAnimation,
                        alignment: Alignment.bottomCenter,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(_plusMenuAnimation),
                          child: FadeTransition(
                            opacity: _plusMenuAnimation,
                            child: _PlusMenuSheet(
                              maxHeight: plusMenuMaxHeight,
                              showTriage: _triageAvailable,
                              onTakePhoto: () {
                                _closePlusMenu();
                                _sendPhoto(ImageSource.camera);
                              },
                              onPickPhoto: () {
                                _closePlusMenu();
                                _sendPhoto(ImageSource.gallery);
                              },
                              onRecordVideo: () {
                                _closePlusMenu();
                                _sendVideo(ImageSource.camera);
                              },
                              onPickVideo: () {
                                _closePlusMenu();
                                _sendVideo(ImageSource.gallery);
                              },
                              onAttach: () {
                                _closePlusMenu();
                                _sendAttachment();
                              },
                              onTriage: _startTriage,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (_isBlocked)
                  _BlockedConversationBar(
                    blockedByMe: _blockedByMe,
                    isBusy: _isTogglingBlock,
                    onUnblock: _blockedByMe
                        ? () => _setConversationBlocked(false)
                        : null,
                  )
                else
                  _Composer(
                    controller: _messageController,
                    isLawyer: widget.isLawyer,
                    counterpartLabel: _triageCounterpartLabel,
                    isSending: _isSending,
                    isUploadingAttachment: _isUploadingAttachment,
                    isPlusMenuOpen: _isPlusMenuOpen,
                    showTriageDot: _triageDotVisible,
                    onSend: _sendMessage,
                    onTogglePlusMenu: _togglePlusMenu,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BlockedConversationBar extends StatelessWidget {
  const _BlockedConversationBar({
    required this.blockedByMe,
    required this.isBusy,
    this.onUnblock,
  });

  final bool blockedByMe;
  final bool isBusy;
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  blockedByMe
                      ? 'Você bloqueou esta conversa.'
                      : 'Esta conversa foi bloqueada.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (onUnblock != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: isBusy ? null : onUnblock,
              child: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Desbloquear'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportDraft {
  const _ReportDraft({required this.reason, required this.details});

  final ReportReason reason;
  final String details;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final TextEditingController _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiModalSheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      // ConstrainedBox + scroll (não Flexible: quebra dentro do scaffold):
      // 5 razões + campo de texto + teclado não cabem numa tela baixa.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Denunciar',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A denúncia é analisada pela equipe da Jurii. A outra pessoa '
                'não é avisada.',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        value: reason,
                        title: Text(
                          reason.label,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _detailsController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Detalhes (opcional)',
                  hintText: 'Conte o que aconteceu',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _reason == null
                    ? null
                    : () => Navigator.of(context).pop(
                        _ReportDraft(
                          reason: _reason!,
                          details: _detailsController.text.trim(),
                        ),
                      ),
                child: const Text('Enviar denúncia'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseRequestSheet extends StatefulWidget {
  const _CaseRequestSheet({required this.initialTitle});

  final String initialTitle;

  @override
  State<_CaseRequestSheet> createState() => _CaseRequestSheetState();
}

class _CaseRequestSheetState extends State<_CaseRequestSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _areaController;
  final TextEditingController _summaryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'Novo caso jurídico');
    _areaController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _areaController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final area = _areaController.text.trim();
    if (title.isEmpty || area.isEmpty) return;

    Navigator.of(context).pop(
      _CaseRequestDraft(
        title: title,
        area: area,
        summary: _summaryController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return JuriiModalSheetScaffold(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Solicitar aceite do caso',
            style: TextStyle(
              color: context.jColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'O cliente poderá aceitar ou recusar pelo sino, pelo chat ou pela aba Meus Casos.',
            style: TextStyle(color: context.jColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Título do caso',
              hintText: 'Ex.: Rescisão trabalhista',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _areaController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Área jurídica',
              hintText: 'Ex.: Direito Trabalhista',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _summaryController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Resumo para o cliente',
              hintText: 'Explique o escopo inicial do atendimento',
            ),
          ),
          const SizedBox(height: 16),
          JuriiLoadingButton(
            label: 'Enviar solicitação',
            onPressed: _submit,
            shadow: false,
          ),
        ],
      ),
    );
  }
}

class _CaseRequestDraft {
  final String title;
  final String area;
  final String summary;

  const _CaseRequestDraft({
    required this.title,
    required this.area,
    required this.summary,
  });
}

class _ChatLoadErrorState extends StatelessWidget {
  const _ChatLoadErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Não foi possível carregar as mensagens.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.jColors.textSecondary,
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

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    // Rola em vez de estourar: com o menu "+" aberto (duas linhas) e teclado
    // na tela, a área que sobra num aparelho baixo fica menor que o estado.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: JuriiEmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'Nenhuma mensagem nesta conversa',
                message:
                    'Envie uma mensagem ou use + para anexar e iniciar a triagem.',
                accentColor: colors.primary,
                surfaceColor: colors.lightBlue,
                borderColor: colors.lightBlueBorder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String counterpartName;
  final String counterpartInitials;
  final bool canRespondToCaseRequest;
  final bool isRespondingCaseRequest;
  final bool canMessageRecommendedLawyer;
  final bool isOpeningRecommendedLawyerChat;
  final ValueChanged<LawyerRecommendation> onMessageRecommendedLawyer;
  final VoidCallback onAcceptCaseRequest;
  final VoidCallback onDeclineCaseRequest;
  final ValueChanged<ChatAttachment> onOpenAttachment;
  final ValueChanged<ChatAttachment> onRetryMedia;
  final ValueChanged<ChatAttachment> onAutoRetryMedia;

  /// URL assinada da mídia desta mensagem (`null` enquanto não há uma válida).
  final String? mediaUrl;
  final bool isLoadingMediaUrl;

  const _MessageBubble({
    required this.message,
    required this.counterpartName,
    required this.counterpartInitials,
    required this.canRespondToCaseRequest,
    required this.isRespondingCaseRequest,
    required this.canMessageRecommendedLawyer,
    required this.isOpeningRecommendedLawyerChat,
    required this.onMessageRecommendedLawyer,
    required this.onAcceptCaseRequest,
    required this.onDeclineCaseRequest,
    required this.onOpenAttachment,
    required this.onRetryMedia,
    required this.onAutoRetryMedia,
    required this.mediaUrl,
    required this.isLoadingMediaUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isCaseRequest) {
      return _CaseRequestMessageCard(
        message: message,
        requesterName: counterpartName,
        requesterInitials: counterpartInitials,
        canRespond: canRespondToCaseRequest,
        isSubmitting: isRespondingCaseRequest,
        onAccept: onAcceptCaseRequest,
        onDecline: onDeclineCaseRequest,
      );
    }

    final recommendation = message.lawyerRecommendation;
    if (recommendation != null) {
      return LawyerRecommendationCard(
        recommendation: recommendation,
        time: message.time,
        canMessage: canMessageRecommendedLawyer,
        isOpeningChat: isOpeningRecommendedLawyerChat,
        onMessage: () => onMessageRecommendedLawyer(recommendation),
      );
    }

    final colors = context.jColors;
    final isMine = message.author == MessageAuthor.me;
    final isSystem = message.author == MessageAuthor.system;
    final attachment = message.attachment;

    // "Foto enviada" / "Vídeo enviado" é rótulo que o servidor grava para a
    // prévia da lista de conversas, não texto de ninguém. Dentro do balão a
    // mídia já se explica, e repetir o rótulo embaixo dela é ruído.
    //
    // Só vale COM anexo: alguém que digita literalmente "Documento enviado"
    // (confirmando que mandou por outro canal) tem texto de verdade, e escondê-
    // -lo entregaria um balão vazio dos dois lados, sem erro nem log.
    final bodyText =
        attachment != null && isChatAttachmentAutoBody(message.text)
        ? ''
        : message.text.trim();
    final showsTimeOverMedia =
        attachment != null && attachment.isMedia && bodyText.isEmpty;

    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isSystem
        ? colors.lightGold
        : isMine
        ? colors.primary
        : colors.card;
    final textColor = isMine ? colors.card : colors.textPrimary;

    return Align(
      alignment: isSystem ? Alignment.center : alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          // Mídia sem legenda ocupa o balão quase inteiro (só a borda fina que
          // dá o formato); com legenda, o respiro normal de texto volta.
          padding: showsTimeOverMedia
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: isMine ? null : Border.all(color: colors.lightBlueBorder),
          ),
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (attachment != null) ...[
                if (attachment.isMedia)
                  ChatMediaBubble(
                    attachment: attachment,
                    signedUrl: mediaUrl,
                    isLoadingUrl: isLoadingMediaUrl,
                    isMine: isMine,
                    time: message.time,
                    read: message.read,
                    showTimestamp: showsTimeOverMedia,
                    onOpen: () => onOpenAttachment(attachment),
                    onRetry: () => onRetryMedia(attachment),
                    onAutoRetry: () => onAutoRetryMedia(attachment),
                  )
                else
                  _AttachmentTile(
                    attachment: attachment,
                    isMine: isMine,
                    onTap: () => onOpenAttachment(attachment),
                  ),
                if (bodyText.isNotEmpty) const SizedBox(height: 8),
              ],
              if (bodyText.isNotEmpty)
                Text(
                  bodyText,
                  style: TextStyle(color: textColor, height: 1.35),
                ),
              // Mídia carrega a própria hora sobreposta, no canto da foto; a
              // linha de baixo repetiria a informação e empurraria o balão.
              if (!showsTimeOverMedia) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.time,
                      style: TextStyle(
                        color: isMine
                            ? colors.card.withValues(alpha: 0.70)
                            : colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.read ? Icons.done_all : Icons.done,
                        size: 14,
                        color: colors.card.withValues(alpha: 0.70),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de DOCUMENTO. Foto e vídeo não passam mais por aqui — viram
/// [ChatMediaBubble]. Só continua atendendo o que não tem prévia possível
/// (PDF, DOC) e o `kind` desconhecido, que cai em documento por segurança.
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.isMine,
    required this.onTap,
  });

  final ChatAttachment attachment;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = attachment.mimeType == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.description_outlined;
    final colors = context.jColors;
    final surfaceColor = isMine
        ? colors.card.withValues(alpha: 0.14)
        : colors.lightBlue;
    final foregroundColor = isMine ? colors.card : colors.textPrimary;
    final secondaryColor = isMine
        ? colors.card.withValues(alpha: 0.72)
        : colors.textSecondary;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      pressedScale: 0.97,
      semanticLabel: 'Abrir anexo ${attachment.fileName}',
      child: Container(
        constraints: const BoxConstraints(minWidth: 210),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isMine
                    ? colors.card.withValues(alpha: 0.16)
                    : colors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: foregroundColor, size: 20),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Documento - ${attachment.sizeLabel}',
                    style: TextStyle(
                      color: secondaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.open_in_new, color: secondaryColor, size: 16),
          ],
        ),
      ),
    );
  }
}

class _CaseRequestMessageCard extends StatelessWidget {
  const _CaseRequestMessageCard({
    required this.message,
    required this.requesterName,
    required this.requesterInitials,
    required this.canRespond,
    required this.isSubmitting,
    required this.onAccept,
    required this.onDecline,
  });

  final ChatMessage message;
  final String requesterName;
  final String requesterInitials;
  final bool canRespond;
  final bool isSubmitting;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final status = message.caseRequestStatus ?? 'pending';

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            border: Border.all(color: colors.lightGoldBorder),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.lightGold,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        requesterInitials,
                        style: TextStyle(
                          color: colors.accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.caseRequestTitle ?? 'Solicitação de caso',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$requesterName · ${message.caseRequestArea ?? 'Atendimento jurídico'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (canRespond) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSubmitting ? null : onDecline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.danger,
                          side: BorderSide(color: colors.divider),
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Recusar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : onAccept,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: isSubmitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.card,
                                ),
                              )
                            : const Text('Aceitar caso'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                _CaseRequestStatusChip(status: status),
              ],
              const SizedBox(height: 8),
              Text(
                message.time,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseRequestStatusChip extends StatelessWidget {
  const _CaseRequestStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final accepted = status == 'accepted';
    final declined = status == 'declined';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accepted
            ? colors.successSurface
            : declined
            ? colors.danger.withValues(alpha: 0.10)
            : colors.lightGold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accepted
            ? 'Caso aceito'
            : declined
            ? 'Caso recusado'
            : 'Aguardando aceite do cliente',
        style: TextStyle(
          color: accepted
              ? colors.success
              : declined
              ? colors.danger
              : colors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final bool isLawyer;
  final String counterpartLabel;
  final bool isSending;
  final bool isUploadingAttachment;
  final bool isPlusMenuOpen;
  final bool showTriageDot;
  final VoidCallback onSend;
  final VoidCallback onTogglePlusMenu;

  const _Composer({
    required this.controller,
    required this.isLawyer,
    required this.counterpartLabel,
    required this.isSending,
    required this.isUploadingAttachment,
    required this.isPlusMenuOpen,
    required this.showTriageDot,
    required this.onSend,
    required this.onTogglePlusMenu,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_isFocused == _focusNode.hasFocus) return;
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return AnimatedContainer(
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(
          top: BorderSide(
            color: widget.isPlusMenuOpen
                ? colors.lightBlueBorder
                : colors.divider,
          ),
        ),
        boxShadow: [
          if (_isFocused || widget.isPlusMenuOpen)
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          final canSend = hasText && !widget.isSending;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _PlusMenuButton(
                isOpen: widget.isPlusMenuOpen,
                showDot: widget.showTriageDot,
                isBusy: widget.isUploadingAttachment,
                enabled: !widget.isSending,
                onPressed: widget.onTogglePlusMenu,
              ),
              Expanded(
                child: AnimatedContainer(
                  duration: JuriiMotion.fast,
                  curve: JuriiMotion.ease,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isFocused ? colors.primary : colors.background,
                      width: _isFocused ? 1.3 : 1,
                    ),
                  ),
                  child: TextField(
                    focusNode: _focusNode,
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: widget.isLawyer
                          ? 'Responder ao cliente'
                          : 'Mensagem para o ${widget.counterpartLabel}',
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => widget.onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: JuriiMotion.fast,
                curve: JuriiMotion.ease,
                opacity: canSend || widget.isSending ? 1 : 0.56,
                child: JuriiPressable(
                  onTap: widget.isSending ? null : widget.onSend,
                  borderRadius: BorderRadius.circular(14),
                  pressedScale: 0.95,
                  semanticLabel: 'Enviar mensagem',
                  child: AnimatedContainer(
                    duration: JuriiMotion.fast,
                    curve: JuriiMotion.ease,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: canSend || widget.isSending
                          ? colors.primary
                          : colors.lightBlueBorder,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: widget.isSending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: colors.card,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(Icons.send, color: colors.card, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Banner exibido no topo de uma conversa nova (sem histórico), convidando o
/// cliente a fazer a triagem guiada antes da primeira mensagem.
class _TriageBanner extends StatelessWidget {
  const _TriageBanner({required this.counterpartLabel, required this.onTap});

  final String counterpartLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: colors.lightGold,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.lightGoldBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: colors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comece com uma triagem guiada',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'A assistente organiza seu relato para o '
                        '$counterpartLabel avaliar seu caso mais rápido.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dica transitória mostrada quando o cliente ignora o banner e envia a
/// primeira mensagem: a triagem continua disponível no botão "+".
class _TriageHintChip extends StatelessWidget {
  const _TriageHintChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.lightGold,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.lightGoldBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'A triagem com a assistente está no botão +',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opções do botão "+" do composer: foto (câmera/galeria), arquivo e (para
/// o cliente) a triagem com IA. Sobe em slide/fade junto do composer.
class _PlusMenuSheet extends StatelessWidget {
  const _PlusMenuSheet({
    required this.maxHeight,
    required this.showTriage,
    required this.onTakePhoto,
    required this.onPickPhoto,
    required this.onRecordVideo,
    required this.onPickVideo,
    required this.onAttach,
    required this.onTriage,
  });

  /// Altura máxima do menu, medida no espaço real do corpo da tela.
  final double maxHeight;

  final bool showTriage;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickPhoto;
  final VoidCallback onRecordVideo;
  final VoidCallback onPickVideo;
  final VoidCallback onAttach;
  final VoidCallback onTriage;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    final options = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.photo_camera_outlined,
        label: 'Tirar foto',
        onTap: onTakePhoto,
      ),
      (icon: Icons.photo_outlined, label: 'Enviar foto', onTap: onPickPhoto),
      (
        icon: Icons.videocam_outlined,
        label: 'Gravar vídeo',
        onTap: onRecordVideo,
      ),
      (
        icon: Icons.video_library_outlined,
        label: 'Enviar vídeo',
        onTap: onPickVideo,
      ),
      (icon: Icons.attach_file, label: 'Anexar arquivo', onTap: onAttach),
      if (showTriage)
        (icon: Icons.auto_awesome, label: 'Triagem com IA', onTap: onTriage),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      // Teto + rolagem: com fonte de acessibilidade grande, ou numa tela muito
      // baixa, as opções passam a rolar dentro do menu em vez de empurrarem o
      // composer para fora da tela. O teto vem medido de fora (o espaço real
      // do corpo, já descontados barra e teclado) porque aqui dentro o Scaffold
      // já consumiu o viewInsets e MediaQuery devolveria a tela inteira.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Duas colunas por linha: quatro opções lado a lado não cabem
              // legíveis em 320dp.
              for (var row = 0; row * 2 < options.length; row++) ...[
                if (row > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col > 0) const SizedBox(width: 10),
                      Expanded(
                        child: row * 2 + col < options.length
                            ? JuriiStaggeredItem(
                                index: row * 2 + col,
                                beginOffset: const Offset(0, 8),
                                child: _PlusMenuOption(
                                  icon: options[row * 2 + col].icon,
                                  label: options[row * 2 + col].label,
                                  onTap: options[row * 2 + col].onTap,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlusMenuOption extends StatelessWidget {
  const _PlusMenuOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return JuriiPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      pressedScale: 0.97,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.lightBlueBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.primary, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão "+" do composer: gira (vira "×") quando o menu abre e exibe um ponto
/// dourado sutil enquanto a triagem ainda não foi descoberta pelo cliente.
class _PlusMenuButton extends StatelessWidget {
  const _PlusMenuButton({
    required this.isOpen,
    required this.showDot,
    required this.isBusy,
    required this.enabled,
    required this.onPressed,
  });

  final bool isOpen;
  final bool showDot;
  final bool isBusy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final canTap = enabled && !isBusy;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: JuriiMotion.fast,
          curve: JuriiMotion.ease,
          decoration: BoxDecoration(
            color: isOpen ? colors.lightGold : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: IconButton(
            onPressed: canTap ? onPressed : null,
            tooltip: isOpen ? 'Fechar opções' : 'Mais opções',
            icon: isBusy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: colors.primary,
                      strokeWidth: 2,
                    ),
                  )
                : AnimatedRotation(
                    // 45°: o "+" vira "×" (fechar). Um quarto de volta literal
                    // deixaria o ícone idêntico ao estado inicial.
                    turns: isOpen ? 0.125 : 0,
                    duration: JuriiMotion.fast,
                    curve: JuriiMotion.ease,
                    child: Icon(
                      Icons.add,
                      color: isOpen ? colors.accent : colors.primary,
                    ),
                  ),
          ),
        ),
        if (showDot && !isBusy)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: JuriiPulse(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.card, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.28),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
