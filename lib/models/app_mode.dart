import '../models/jurii_notification.dart';

/// Os três fluxos do app.
///
/// Existe como tipo próprio porque antes o modo era um par de booleanos
/// (`_isLawyerMode`, `_isFirmMode`) espalhado pela árvore — e um par de
/// booleanos admite o estado impossível "advogado e escritório ao mesmo
/// tempo", que o código tinha que zerar na mão a cada troca.
enum AppMode {
  client('Cliente', 'Buscar advogado e acompanhar seus casos'),
  lawyer('Profissional', 'Atender clientes e gerir seus casos'),
  firm('Escritório', 'Equipe, balcão e casos da banca');

  const AppMode(this.label, this.description);

  /// Nome curto, o mesmo em todos os lugares onde o modo é citado.
  final String label;

  /// Uma linha do que se faz aqui — para quem tem os três não precisar
  /// lembrar qual é qual.
  final String description;

  /// Escopo de notificação correspondente. É o que liga "há algo esperando"
  /// ao fluxo certo no seletor.
  NotificationScope get notificationScope => switch (this) {
    AppMode.client => NotificationScope.client,
    AppMode.lawyer => NotificationScope.lawyer,
    AppMode.firm => NotificationScope.firm,
  };
}
