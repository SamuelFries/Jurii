import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/mock/mock_firm_workspace.dart';
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
  });

  final FirmWorkspace? workspace;
  final List<FirmTeamMember>? teamMembers;
  final Future<void> Function({
    required String oabState,
    required String oabNumber,
  })?
  onInviteLawyer;

  @override
  Widget build(BuildContext context) {
    final members = teamMembers ?? mockFirmTeamMembers;
    final canInvite =
        workspace?.fromSupabase == true &&
        (workspace?.currentUserRole == FirmRole.owner ||
            workspace?.currentUserRole == FirmRole.admin);

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
          for (var index = 0; index < members.length; index++) ...[
            _TeamMemberCard(member: members[index]),
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
            'Aprove o escritório e rode o patch 006 antes de convidar.',
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
      if (!mounted) return;
      setState(() {
        _errorText = _friendlyError(error);
        _isSubmitting = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('Lawyer not found') ||
        message.contains('not approved')) {
      return 'Não encontramos um advogado verificado com essa OAB.';
    }

    if (message.contains('Only active office owners')) {
      return 'Apenas donos e admins ativos podem convidar advogados.';
    }

    if (message.contains('invite_verified_lawyer_to_law_firm') ||
        message.contains('function') ||
        message.contains('patch')) {
      return 'Rode o patch 007 no Supabase antes de enviar convites.';
    }

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
  const _TeamMemberCard({required this.member});

  final FirmTeamMember member;

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (member.role) {
      FirmRole.owner => 'Líder',
      FirmRole.admin => 'Admin',
      FirmRole.secretary => 'Secretaria',
      FirmRole.lawyer => 'Advogado',
    };

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
                  '$roleLabel · ${member.specialty}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MiniBadge('${member.activeCases} casos'),
                    _MiniBadge('${member.responseHours}h resposta'),
                    _MiniBadge('★ ${member.rating}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Perfil do membro em preparação.'),
                ),
              );
            },
            icon: const Icon(Icons.chevron_right),
            color: AppTheme.textSecondary,
            tooltip: 'Abrir membro',
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
