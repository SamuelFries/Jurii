import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/firm_role.dart';
import '../models/firm_team_member.dart';
import '../models/firm_workspace.dart';
import '../theme/app_theme.dart';

class FirmTeamScreen extends StatelessWidget {
  const FirmTeamScreen({
    super.key,
    this.workspace,
    this.teamMembers,
    this.onInviteLawyer,
    this.onUpdateMemberRoles,
  });

  final FirmWorkspace? workspace;
  final List<FirmTeamMember>? teamMembers;
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equipe',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Advogados e operação do escritório.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: () => _openInviteDialog(context, canInvite),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.officePurple,
                  foregroundColor: AppTheme.card,
                ),
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Convidar membro',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (members.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.officePurpleBorder),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sua equipe aparecerá aqui',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Convide advogados verificados pelo botão acima para '
                    'montar o time do escritório.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
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
                    ? () => _openRolesDialog(context, members[index])
                    : null,
              ),
              if (index < members.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _openInviteDialog(BuildContext context, bool canInvite) async {
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
          content: Text('Apenas donos e admins podem convidar advogados.'),
        ),
      );
      return;
    }

    final invited = await showDialog<bool>(
      context: context,
      builder: (_) => _InviteLawyerDialog(onInviteLawyer: onInviteLawyer!),
    );

    if (invited == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite enviado ao advogado.')),
      );
    }
  }

  Future<void> _openRolesDialog(
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
          content: Text('Apenas donos e admins podem editar cargos.'),
        ),
      );
      return;
    }

    if (member.effectiveRoles.hasOwner && workspace?.isOwner != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apenas donos podem alterar outro dono.')),
      );
      return;
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _MemberRolesDialog(
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

class _MemberRolesDialog extends StatefulWidget {
  const _MemberRolesDialog({
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
  State<_MemberRolesDialog> createState() => _MemberRolesDialogState();
}

class _MemberRolesDialogState extends State<_MemberRolesDialog> {
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
      return 'Apenas donos e admins ativos podem editar cargos.';
    }
    if (message.contains('Only owners can grant or remove owner role')) {
      return 'Apenas donos podem conceder ou remover o cargo de dono.';
    }
    if (message.contains('Office must keep at least one owner')) {
      return 'O escritório precisa manter pelo menos um dono ativo.';
    }
    if (message.contains('Invalid firm roles')) {
      return 'A lista de cargos tem um valor inválido.';
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
    return AlertDialog(
      title: Text('Cargos de ${widget.member.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in FirmRole.orderedValues)
              CheckboxListTile(
                value: _selectedRoles.contains(role),
                onChanged:
                    _isSubmitting ||
                        (role == FirmRole.owner && !widget.canEditOwnerRole)
                    ? null
                    : (selected) => _toggleRole(role, selected),
                title: Text(role.label),
                subtitle: Text(
                  _roleDescription(role),
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorText!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.card,
                  ),
                )
              : const Text('Salvar cargos'),
        ),
      ],
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

class _InviteLawyerDialog extends StatefulWidget {
  const _InviteLawyerDialog({required this.onInviteLawyer});

  final Future<void> Function({
    required String oabState,
    required String oabNumber,
  })
  onInviteLawyer;

  @override
  State<_InviteLawyerDialog> createState() => _InviteLawyerDialogState();
}

class _InviteLawyerDialogState extends State<_InviteLawyerDialog> {
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

    if (message.contains('Lawyer not found') ||
        normalizedMessage.contains('not approved')) {
      return 'Não encontramos um advogado verificado com essa OAB.';
    }

    if (message.contains('Only active office owners')) {
      return 'Apenas donos e admins ativos podem convidar advogados.';
    }

    if (message.contains('Lawyer already active')) {
      return 'Esse advogado já está ativo neste escritório.';
    }

    if (message.contains('Lawyer invite already pending')) {
      return 'Já existe um convite pendente para esse advogado.';
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
    return AlertDialog(
      title: const Text('Convidar advogado'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informe a OAB de um advogado já verificado na Jurii.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _stateController,
              enabled: !_isSubmitting,
              textCapitalization: TextCapitalization.characters,
              maxLength: 2,
              decoration: const InputDecoration(
                labelText: 'UF da OAB',
                hintText: 'SP',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
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
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: AppTheme.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.card,
                  ),
                )
              : const Text('Enviar convite'),
        ),
      ],
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({required this.member, this.onEditRoles});

  final FirmTeamMember member;
  final VoidCallback? onEditRoles;

  @override
  Widget build(BuildContext context) {
    final roleLabel = member.roleLabel;
    final detailLabel = member.specialty == roleLabel
        ? roleLabel
        : '$roleLabel - ${member.specialty}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.officePurpleBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: member.available
                  ? AppTheme.officePurple
                  : AppTheme.textSecondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                member.initials,
                style: const TextStyle(
                  color: AppTheme.card,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
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
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detailLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
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
          const SizedBox(width: 8),
          IconButton(
            onPressed:
                onEditRoles ??
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Perfil do membro em preparação.'),
                    ),
                  );
                },
            icon: Icon(
              onEditRoles == null ? Icons.chevron_right : Icons.manage_accounts,
            ),
            color: AppTheme.textSecondary,
            tooltip: onEditRoles == null ? 'Abrir membro' : 'Editar cargos',
          ),
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
        color: AppTheme.officePurpleSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.officePurple,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
