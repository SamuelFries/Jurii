import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/firm_role.dart';
import '../models/firm_team_member.dart';
import '../models/firm_workspace.dart';
import '../repositories/license_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_list_card.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/profile_avatar.dart';

class FirmTeamScreen extends StatelessWidget {
  const FirmTeamScreen({
    super.key,
    this.workspace,
    this.teamMembers,
    this.onInviteLawyer,
    this.onUpdateMemberRoles,
    this.licenseRepository = const LicenseRepository(),
  });

  final FirmWorkspace? workspace;
  final List<FirmTeamMember>? teamMembers;
  final LicenseRepository licenseRepository;
  final Future<void> Function({
    required String oabState,
    required String oabNumber,
  })?
  onInviteLawyer;
  final Future<void> Function({
    required String memberProfileId,
    required List<FirmRole> roles,
  })?
  onUpdateMemberRoles;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final members = teamMembers ?? const <FirmTeamMember>[];
    final canManageMembers =
        workspace?.fromSupabase == true && workspace?.canManageMembers == true;
    final canInvite = canManageMembers;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equipe',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Advogados e operação do escritório.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: () => _openInviteSheet(context, canInvite),
                style: IconButton.styleFrom(
                  backgroundColor: colors.officePurple,
                  foregroundColor: colors.card,
                ),
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Convidar membro',
              ),
            ],
          ),
          const SizedBox(height: 20),
          // O AVISO VEM ANTES DA LISTA porque ele explica por que o convite
          // vai ser recusado. Sem ele a pessoa só descobria depois de abrir a
          // folha, digitar a OAB e clicar.
          if (canManageMembers && workspace != null)
            _AvisoDeCobranca(
              lawFirmId: workspace!.firm.id,
              repository: licenseRepository,
            ),
          if (members.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.officePurpleBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sua equipe aparecerá aqui',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Convide advogados verificados pelo botão acima para '
                    'montar o time do escritório.',
                    style: TextStyle(color: colors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            )
          else
            for (var index = 0; index < members.length; index++) ...[
              _TeamMemberCard(
                member: members[index],
                onEditRoles:
                    canManageMembers &&
                        onUpdateMemberRoles != null &&
                        (workspace?.isOwner == true ||
                            !members[index].effectiveRoles.hasOwner)
                    ? () => _openRolesSheet(context, members[index])
                    : null,
              ),
              if (index < members.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _openInviteSheet(BuildContext context, bool canInvite) async {
    if (workspace?.fromSupabase != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O escritório precisa estar aprovado para convidar advogados.',
          ),
        ),
      );
      return;
    }

    if (!canInvite || onInviteLawyer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas sócios e admins podem convidar advogados.'),
        ),
      );
      return;
    }

    final invited = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _InviteLawyerSheet(onInviteLawyer: onInviteLawyer!),
    );

    if (invited == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitação processada. Se a OAB estiver elegível, o advogado receberá o convite.',
          ),
        ),
      );
    }
  }

  Future<void> _openRolesSheet(
    BuildContext context,
    FirmTeamMember member,
  ) async {
    if (workspace?.fromSupabase != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronize o escritorio antes de editar cargos.'),
        ),
      );
      return;
    }

    if (workspace?.canManageMembers != true || onUpdateMemberRoles == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas sócios e admins podem editar cargos.'),
        ),
      );
      return;
    }

    if (member.effectiveRoles.hasOwner && workspace?.isOwner != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas sócios podem alterar outro sócio.'),
        ),
      );
      return;
    }

    final updated = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MemberRolesSheet(
        member: member,
        canEditOwnerRole: workspace?.isOwner == true,
        onUpdateMemberRoles: onUpdateMemberRoles!,
      ),
    );

    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cargos atualizados.')));
    }
  }
}

class _MemberRolesSheet extends StatefulWidget {
  const _MemberRolesSheet({
    required this.member,
    required this.canEditOwnerRole,
    required this.onUpdateMemberRoles,
  });

  final FirmTeamMember member;
  final bool canEditOwnerRole;
  final Future<void> Function({
    required String memberProfileId,
    required List<FirmRole> roles,
  })
  onUpdateMemberRoles;

  @override
  State<_MemberRolesSheet> createState() => _MemberRolesSheetState();
}

class _MemberRolesSheetState extends State<_MemberRolesSheet> {
  late final Set<FirmRole> _selectedRoles;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedRoles = widget.member.effectiveRoles.toSet();
  }

  Future<void> _submit() async {
    if (_selectedRoles.isEmpty) {
      setState(() {
        _errorText = 'Selecione pelo menos um cargo.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await widget.onUpdateMemberRoles(
        memberProfileId: widget.member.id,
        roles: FirmRole.normalize(_selectedRoles),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = _friendlyError(error);
        _isSubmitting = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('Only active office owners and admins')) {
      return 'Apenas sócios e admins ativos podem editar cargos.';
    }
    if (message.contains('Only owners can grant or remove owner role')) {
      return 'Apenas sócios podem conceder ou remover o cargo de sócio.';
    }
    if (message.contains('Office must keep at least one owner')) {
      return 'O escritório precisa manter pelo menos um sócio ativo.';
    }
    if (message.contains('Invalid firm roles')) {
      return 'A lista de cargos tem um valor inválido.';
    }
    // O teto de advogados vale AQUI também desde a 20260907120000: promover
    // alguém a advogado ocupa vaga igual a convidar de fora. Sem estas duas
    // frases a pessoa recebia "não foi possível atualizar os cargos", que não
    // diz o que houve nem para onde ir.
    if (message.contains('Subscription is not active')) {
      return 'A assinatura do escritório está pendente. Regularize o '
          'pagamento para promover advogados.';
    }
    if (message.contains('Lawyer seat limit reached')) {
      return 'Seu plano atual não comporta mais advogados. Troque de plano '
          'em Perfil > Plano para promover.';
    }
    if (message.contains('update_law_firm_member_roles') ||
        message.contains('function') ||
        message.contains('patch')) {
      debugPrint('Firm roles RPC unavailable: $message');
      return 'Não foi possível atualizar os cargos. Tente novamente em instantes.';
    }
    return 'Não foi possível atualizar os cargos.';
  }

  void _toggleRole(FirmRole role, bool? selected) {
    if (role == FirmRole.owner && !widget.canEditOwnerRole) return;

    setState(() {
      if (selected == true) {
        _selectedRoles.add(role);
      } else {
        _selectedRoles.remove(role);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiModalSheetScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cargos de ${widget.member.name}',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Defina o que este membro pode fazer dentro do escritório.',
            style: TextStyle(
              color: colors.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.48,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final role in FirmRole.orderedValues) ...[
                    _RoleToggleTile(
                      title: role.label,
                      description: _roleDescription(role),
                      selected: _selectedRoles.contains(role),
                      enabled:
                          !_isSubmitting &&
                          (role != FirmRole.owner || widget.canEditOwnerRole),
                      onChanged: (selected) => _toggleRole(role, selected),
                    ),
                    if (role != FirmRole.orderedValues.last)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          JuriiFormErrorBanner(message: _errorText),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: JuriiLoadingButton(
                  label: 'Salvar cargos',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                  height: 52,
                  backgroundColor: colors.officePurple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _roleDescription(FirmRole role) {
    return switch (role) {
      FirmRole.owner => 'Controle total e pode atuar com outros cargos.',
      FirmRole.admin => 'Gerencia equipe, convites e operacao.',
      FirmRole.lawyer => 'Atende casos atribuidos.',
      FirmRole.secretary => 'Cria solicitacoes e atribui casos.',
      FirmRole.intern => 'Acesso limitado para apoio interno.',
    };
  }
}

class _RoleToggleTile extends StatelessWidget {
  const _RoleToggleTile({
    required this.title,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final borderColor = selected
        ? colors.officePurple
        : colors.officePurpleBorder;
    final backgroundColor = selected ? colors.officePurpleSurface : colors.card;
    final iconColor = selected ? colors.officePurple : colors.textSecondary;

    return JuriiPressable(
      onTap: enabled ? () => onChanged(!selected) : null,
      borderRadius: BorderRadius.circular(14),
      semanticLabel: title,
      child: AnimatedContainer(
        duration: JuriiMotion.fast,
        curve: JuriiMotion.ease,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled
              ? backgroundColor
              : colors.lightBlue.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: JuriiMotion.fast,
              curve: JuriiMotion.ease,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? colors.officePurple : colors.card,
                shape: BoxShape.circle,
                border: Border.all(color: iconColor, width: 1.4),
              ),
              child: AnimatedSwitcher(
                duration: JuriiMotion.fast,
                child: selected
                    ? Icon(
                        Icons.check,
                        key: const ValueKey('selected'),
                        color: colors.card,
                        size: 16,
                      )
                    : const SizedBox(key: ValueKey('empty')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
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

class _InviteLawyerSheet extends StatefulWidget {
  const _InviteLawyerSheet({required this.onInviteLawyer});

  final Future<void> Function({
    required String oabState,
    required String oabNumber,
  })
  onInviteLawyer;

  @override
  State<_InviteLawyerSheet> createState() => _InviteLawyerSheetState();
}

class _InviteLawyerSheetState extends State<_InviteLawyerSheet> {
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _stateController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oabState = _stateController.text.trim().toUpperCase();
    final oabNumber = _numberController.text.trim();

    if (oabState.length != 2 || oabNumber.isEmpty) {
      setState(() {
        _errorText = 'Informe a UF e o número da OAB do advogado.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await widget.onInviteLawyer(oabState: oabState, oabNumber: oabNumber);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('Firm lawyer invite failed: $error');
      if (!mounted) return;
      setState(() {
        _errorText = _friendlyError(error);
        _isSubmitting = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    final normalizedMessage = message.toLowerCase();

    if (message.contains('Only active office owners')) {
      return 'Apenas sócios e admins ativos podem convidar advogados.';
    }

    if (message.contains('Too many invite attempts')) {
      return 'Muitas tentativas em pouco tempo. Aguarde antes de tentar novamente.';
    }

    if (message.contains('Subscription is not active')) {
      // OUTRO problema, e por isso outra frase: aqui não adianta trocar de
      // plano, porque nenhum plano está pago. Mandar a pessoa para a tela de
      // planos seria mandá-la para o lugar errado.
      return 'A assinatura do escritório está pendente. Regularize o '
          'pagamento para voltar a convidar advogados.';
    }

    if (message.contains('Lawyer seat limit reached')) {
      // O teto é do PLANO, não do alvo do convite: dizer qual é o problema
      // (e onde resolve) evita a pessoa reescrever a OAB três vezes.
      return 'Seu plano atual não comporta mais advogados. Troque de plano '
          'em Perfil > Plano para convidar.';
    }

    if (normalizedMessage.contains('permission denied') &&
        normalizedMessage.contains('invite_verified_lawyer_to_law_firm')) {
      debugPrint('Invite RPC permission denied: $message');
      return 'O envio de convites está temporariamente indisponível.';
    }

    if (normalizedMessage.contains('schema cache') ||
        normalizedMessage.contains('could not find the function') ||
        normalizedMessage.contains('pgrst202')) {
      debugPrint('Invite RPC missing from schema cache: $message');
      return 'O envio de convites está temporariamente indisponível. Tente novamente em instantes.';
    }

    debugPrint('Firm invite failed: $message');
    return 'Não foi possível enviar o convite. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return JuriiModalSheetScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Convidar advogado',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Informe a OAB de um advogado já verificado na Jurii.',
            style: TextStyle(
              color: colors.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _stateController,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 2,
                  decoration: const InputDecoration(
                    labelText: 'UF',
                    hintText: 'SP',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _numberController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Número da OAB',
                    hintText: '123456',
                  ),
                ),
              ),
            ],
          ),
          JuriiFormErrorBanner(message: _errorText),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: JuriiLoadingButton(
                  label: 'Enviar convite',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                  height: 52,
                  backgroundColor: colors.officePurple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({required this.member, this.onEditRoles});

  final FirmTeamMember member;
  final VoidCallback? onEditRoles;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final roleLabel = member.roleLabel;
    final detailLabel = member.specialty == roleLabel
        ? roleLabel
        : '$roleLabel - ${member.specialty}';

    return JuriiListCard(
      borderRadius: 14,
      borderColor: colors.officePurpleBorder,
      child: Row(
        children: [
          ProfileAvatar(
            imageUrl: member.avatarUrl,
            initials: member.initials,
            size: 48,
            backgroundColor: member.available
                ? colors.officePurple
                : colors.textSecondary,
            foregroundColor: colors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detailLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Badges só com dados reais — métricas por membro ainda não
                // existem no banco, então valores 0 ficam ocultos.
                if (member.activeCases > 0 ||
                    member.responseHours > 0 ||
                    member.rating > 0) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (member.activeCases > 0)
                        _MiniBadge('${member.activeCases} casos'),
                      if (member.responseHours > 0)
                        _MiniBadge('${member.responseHours}h resposta'),
                      if (member.rating > 0) _MiniBadge('★ ${member.rating}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Sem permissão de editar cargos não há ação nenhuma aqui — um
          // chevron promete navegação que não existe, então nada é exibido.
          if (onEditRoles != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onEditRoles,
              icon: const Icon(Icons.manage_accounts),
              color: colors.textSecondary,
              tooltip: 'Editar cargos',
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.jColors.officePurpleSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.jColors.officePurple,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// O aviso de que a banca não cresce enquanto a assinatura não anda.
///
/// EXISTE PARA DIZER ANTES. O servidor recusa convite e promoção quando a
/// assinatura está parada (20260907120000), e sem este cartão a pessoa só
/// descobria isso depois de abrir a folha de convite, digitar a OAB e clicar.
/// Oferecer um caminho que vai certamente falhar é o link morto de sempre.
///
/// Widget PRÓPRIO com fetch próprio, no mesmo padrão do plano no perfil: a
/// tela de equipe recebe dados prontos, e a resposta do teto precisa de uma
/// chamada que só ela faz.
///
/// A pergunta vai para o BANCO, e não é deduzida daqui: a regra tem três
/// respostas que dependem de enxergar as assinaturas canceladas, e as
/// consultas que o app já fazia filtram cancelada. Ver a 20260909120000.
class _AvisoDeCobranca extends StatefulWidget {
  const _AvisoDeCobranca({required this.lawFirmId, required this.repository});

  final String lawFirmId;
  final LicenseRepository repository;

  @override
  State<_AvisoDeCobranca> createState() => _AvisoDeCobrancaState();
}

class _AvisoDeCobrancaState extends State<_AvisoDeCobranca> {
  /// Começa TRUE: enquanto não sabe, não acusa. Um cartão de inadimplência
  /// piscando na tela de quem está em dia seria pior do que aviso nenhum.
  bool _podeCrescer = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final pode = await widget.repository.bancaPodeCrescer(widget.lawFirmId);
      if (!mounted) return;
      setState(() => _podeCrescer = pode);
    } catch (_) {
      // Falha de rede não vira acusação: quem recusa de verdade é o servidor,
      // e o erro do convite já explica o motivo quando chega a hora.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_podeCrescer) return const SizedBox.shrink();
    final colors = context.jColors;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.officePurple.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: colors.officePurple),
              const SizedBox(width: 8),
              Text(
                'Assinatura pendente',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // FALA DE CRESCER, E SÓ. Ninguém pode ler "assinatura pendente" como
          // "perdi o escritório": quem já está na equipe segue trabalhando, e
          // a frase diz isso com todas as letras.
          Text(
            'Enquanto o pagamento não entra, o escritório não inclui '
            'advogados novos, nem por convite nem promovendo quem já está '
            'aqui. Quem já faz parte da equipe continua trabalhando '
            'normalmente.',
            style: TextStyle(color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            'O pagamento é feito no site, em Assinatura.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
