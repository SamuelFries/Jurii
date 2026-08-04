/// Assina URLs de anexo em LOTE e guarda o resultado até perto do vencimento.
///
/// O bucket `chat-attachments` é privado: nada nele tem URL pública, e cada
/// foto ou vídeo que aparece dentro do balão precisa de uma URL assinada. Sem
/// este cache seriam N chamadas de rede para abrir uma conversa (uma por
/// mídia) e outra a cada rebuild da lista.
///
/// O [signer] e o relógio são injetados para o cache poder ser testado inteiro
/// sem Supabase e sem esperar uma hora passar.
typedef SignedUrlBatchSigner =
    Future<Map<String, String>> Function(List<String> storagePaths, Duration ttl);

class _CachedUrl {
  const _CachedUrl(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;
}

class AttachmentUrlCache {
  AttachmentUrlCache({
    required this.signer,
    DateTime Function()? clock,
    this.ttl = const Duration(hours: 1),
    this.refreshMargin = const Duration(minutes: 5),
    this.requestTimeout = const Duration(seconds: 25),
  }) : _clock = clock ?? DateTime.now;

  final SignedUrlBatchSigner signer;

  /// Uma hora. A URL assinada só dá acesso a um arquivo que quem está olhando
  /// já pode ler pela policy do Storage — o prazo curto não é a defesa, é
  /// contenção. Uma hora cobre a sessão de chat sem reassinar a cada rolagem.
  final Duration ttl;

  /// Reassina quando falta menos que isto para vencer, para a URL não morrer
  /// no meio de um download já começado.
  final Duration refreshMargin;

  /// Teto de espera de um lote. Sem ele, uma requisição que fica pendurada
  /// (troca de Wi-Fi para 4G com o socket num buraco negro, app suspenso no
  /// meio da chamada) deixa os caminhos daquele lote presos "em voo" para
  /// sempre: esqueleto cinza eterno, que nem mensagem nova nem toque desfazem.
  final Duration requestTimeout;

  final DateTime Function() _clock;
  final Map<String, _CachedUrl> _urls = {};
  final Map<String, Future<void>> _inFlight = {};

  /// Caminhos que já gastaram a tentativa AUTOMÁTICA de reassinatura.
  final Set<String> _autoRefreshed = {};

  /// URL válida agora, ou `null` (nunca assinada, já vencida ou falhou).
  String? cachedUrlFor(String storagePath) {
    final entry = _urls[storagePath];
    if (entry == null) return null;
    if (!entry.expiresAt.isAfter(_clock())) return null;
    return entry.url;
  }

  /// `true` enquanto o lote que cobre este caminho não voltou. Serve para a
  /// interface distinguir "ainda carregando" de "não deu" — sem isso, falha de
  /// rede e carregamento lento viram o mesmo esqueleto para sempre.
  bool isPending(String storagePath) => _inFlight.containsKey(storagePath);

  /// Assina o que falta e devolve quando o lote terminou. Caminhos já
  /// assinados e ainda longe do vencimento não geram chamada; caminhos já em
  /// voo entram na espera em vez de disparar um segundo lote.
  Future<void> ensureUrls(Iterable<String> storagePaths) async {
    final unique = <String>{...storagePaths}
      ..removeWhere((path) => path.trim().isEmpty);
    if (unique.isEmpty) return;

    final waiting = <Future<void>>[];
    final toSign = <String>[];

    for (final path in unique) {
      final inFlight = _inFlight[path];
      if (inFlight != null) {
        waiting.add(inFlight);
        continue;
      }
      if (_needsSigning(path)) toSign.add(path);
    }

    if (toSign.isNotEmpty) {
      final batch = _startBatch(toSign);
      for (final path in toSign) {
        _inFlight[path] = batch;
      }
      waiting.add(batch);
    }

    if (waiting.isEmpty) return;
    await Future.wait(waiting);
  }

  /// Descarta a URL guardada. Chamado quando o download falhou com uma URL que
  /// parecia válida (vencida no servidor, objeto movido): sem isto a próxima
  /// tentativa reusaria exatamente a URL que acabou de falhar.
  void forget(String storagePath) {
    _urls.remove(storagePath);
    _inFlight.remove(storagePath);
  }

  /// Descarte AUTOMÁTICO, disparado pelo download que falhou — com teto de UM
  /// por caminho. Retorna `false` quando o caminho já gastou a tentativa.
  ///
  /// O teto existe porque a recuperação é circular: descartar gera URL nova,
  /// URL nova reconstrói o balão, o balão baixa e falha de novo. Quando a
  /// causa é permanente (objeto sumiu do bucket, imagem corrompida que passou
  /// pela checagem de assinatura, 403 que veio para ficar) isso não converge, e
  /// quem paga é o plano de dados de alguém que só está lendo a conversa.
  /// Um trinco dentro do balão não resolveria: cada volta recria o widget.
  bool forgetForAutoRetry(String storagePath) {
    if (!_autoRefreshed.add(storagePath)) return false;
    forget(storagePath);
    return true;
  }

  void clear() {
    _urls.clear();
    _inFlight.clear();
    _autoRefreshed.clear();
  }

  bool _needsSigning(String storagePath) {
    final entry = _urls[storagePath];
    if (entry == null) return true;
    return !entry.expiresAt.isAfter(_clock().add(refreshMargin));
  }

  Future<void> _startBatch(List<String> paths) {
    late final Future<void> batch;
    batch = () async {
      final expiresAt = _clock().add(ttl);
      Map<String, String> signed;
      try {
        signed = await signer(paths, ttl).timeout(requestTimeout);
      } catch (_) {
        // Falha NÃO vira cache: a próxima chamada tenta de novo. Guardar o
        // erro deixaria a conversa sem imagem até fechar a tela.
        signed = const {};
      }
      for (final path in paths) {
        // Se já não é o lote registrado para este caminho, um forget() entrou
        // no meio — o resultado antigo não pode sobrescrever a limpeza.
        if (!identical(_inFlight[path], batch)) continue;
        _inFlight.remove(path);
        final url = signed[path];
        if (url != null) _urls[path] = _CachedUrl(url, expiresAt);
      }
    }();
    return batch;
  }
}
