import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/invite_link_screen.dart';
import '../utils/invite_link.dart';
import 'app_navigator.dart';

/// Recebe o link de convite e leva à tela certa, na hora certa.
///
/// DUAS PORTAS DE ENTRADA, um destino: o link que ABRIU o app (getInitialLink,
/// app fechado) e o link que chegou com o app vivo (uriLinkStream). Os dois
/// caem em [_receber], que só guarda o token e pede para navegar.
///
/// QUANDO NAVEGAR é a pergunta que importa. Quem clica no link pode não ter
/// conta, ou ter conta e estar deslogado, ou estar no portão de completar
/// cadastro. Em nenhum desses casos a tela do convite pode empilhar por cima:
/// o token fica GUARDADO e a navegação espera o mesmo portão que o push já
/// respeita ([appCanRouteNotifications]). Quando ele abre, o convite reaparece
/// sozinho, com o token intacto: a pessoa entra ou cria conta e cai de volta
/// no convite, sem reconstruir nada.
///
/// `app_links` é o pacote que o supabase_flutter já traz para o
/// login-callback: promovê-lo a dependência direta não adiciona um byte.
class InviteLinkService {
  InviteLinkService({AppLinks? appLinks, this.onEntrouNaBanca})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;
  VoidCallback? _portaoListener;

  /// Repassado à tela do convite: quando o pedido já foi aprovado, "Ir para
  /// o escritório" recarrega o workspace e troca de área (estado da raiz).
  final VoidCallback? onEntrouNaBanca;

  /// O token esperando o app estar utilizável. Um só: link novo substitui o
  /// anterior (a pessoa clicou no mais recente de propósito). É notifier
  /// para a tela de login poder dizer "há um convite esperando você entrar".
  final ValueNotifier<String?> tokenPendente = ValueNotifier<String?>(null);

  /// A tela do convite já está no topo? Evita empilhar duas para o mesmo
  /// token quando o mesmo link chega duas vezes (Android costuma entregar o
  /// initial E o stream para o link que abriu o app).
  String? _tokenNoTopo;

  Future<void> start() async {
    // O link que abriu o app, se foi um.
    try {
      final inicial = await _appLinks.getInitialLink();
      if (inicial != null) _receber(inicial);
    } catch (error) {
      debugPrint('InviteLinkService: getInitialLink falhou: $error');
    }
    // E os que chegarem com o app vivo.
    _sub ??= _appLinks.uriLinkStream.listen(
      _receber,
      onError: (Object error) =>
          debugPrint('InviteLinkService: uriLinkStream falhou: $error'),
    );
    // O portão: quando o app fica utilizável, drena o pendente.
    _portaoListener ??= () {
      if (appCanRouteNotifications.value) _drenar();
    };
    appCanRouteNotifications.addListener(_portaoListener!);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    if (_portaoListener != null) {
      appCanRouteNotifications.removeListener(_portaoListener!);
      _portaoListener = null;
    }
    tokenPendente.dispose();
  }

  /// Também usado pelos testes e por quem tiver um Uri na mão (ex.: um QR).
  @visibleForTesting
  void receber(Uri uri) => _receber(uri);

  void _receber(Uri uri) {
    final token = inviteTokenFromUri(uri);
    // Não é convite (login-callback, ou lixo): não é assunto deste serviço.
    if (token == null) return;
    tokenPendente.value = token;
    _drenar();
  }

  void _drenar() {
    final token = tokenPendente.value;
    if (token == null) return;
    if (!appCanRouteNotifications.value) return; // espera o portão
    final navigator = appNavigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    if (_tokenNoTopo == token) {
      tokenPendente.value = null;
      return;
    }
    tokenPendente.value = null;
    _tokenNoTopo = token;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => InviteLinkScreen(
              token: token,
              onEntrouNaBanca: onEntrouNaBanca,
            ),
          ),
        )
        .whenComplete(() {
          if (_tokenNoTopo == token) _tokenNoTopo = null;
        });
  }
}
