import 'package:flutter/material.dart';

import '../models/law_firm.dart';
import '../repositories/messaging_repository.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

class LawFirmProfileScreen extends StatefulWidget {
  const LawFirmProfileScreen({
    super.key,
    required this.lawFirm,
    this.messagingRepository = const MessagingRepository(),
  });

  final LawFirm lawFirm;
  final MessagingRepository messagingRepository;

  @override
  State<LawFirmProfileScreen> createState() => _LawFirmProfileScreenState();
}

class _LawFirmProfileScreenState extends State<LawFirmProfileScreen> {
  bool _isOpeningChat = false;

  Color get _avatarColor => switch (widget.lawFirm.avatarType) {
    'navy' => AppTheme.primary,
    'gold' => AppTheme.accent,
    _ => AppTheme.lightBlue,
  };

  Color get _avatarTextColor => switch (widget.lawFirm.avatarType) {
    'navy' || 'gold' => AppTheme.card,
    _ => AppTheme.primary,
  };

  Future<void> _openChat() async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);

    try {
      final conversation = await widget.messagingRepository
          .startLawFirmConversation(lawFirm: widget.lawFirm);

      if (!mounted) return;
      setState(() => _isOpeningChat = false);

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(conversation: conversation, isLawyer: false),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isOpeningChat = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a conversa.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final description =
        widget.lawFirm.description ??
        'Escritório verificado na Jurii para atendimento jurídico especializado e acompanhamento de casos pela plataforma.';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Perfil do escritório')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.card,
                border: Border.all(color: AppTheme.lightBlueBorder),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: _avatarColor,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Text(
                            widget.lawFirm.initials,
                            style: TextStyle(
                              color: _avatarTextColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
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
                              widget.lawFirm.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.lawFirm.specialty,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.star,
                        label:
                            '${widget.lawFirm.rating} (${widget.lawFirm.reviews})',
                      ),
                      _InfoChip(
                        icon: Icons.location_on_outlined,
                        label: widget.lawFirm.distance.isEmpty
                            ? 'Atendimento online'
                            : widget.lawFirm.distance,
                      ),
                      const _InfoChip(
                        icon: Icons.verified_outlined,
                        label: 'Verificado',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _ProfileSection(
              title: 'Sobre',
              child: Text(
                description,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ProfileSection(
              title: 'Contato',
              child: Column(
                children: [
                  _ContactRow(
                    icon: Icons.mail_outline,
                    label: widget.lawFirm.email ?? 'Contato pela Jurii',
                  ),
                  const SizedBox(height: 10),
                  _ContactRow(
                    icon: Icons.location_city_outlined,
                    label: widget.lawFirm.address ?? 'Atendimento remoto',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isOpeningChat ? null : _openChat,
                icon: _isOpeningChat
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.card,
                        ),
                      )
                    : const Icon(Icons.chat_bubble_outline),
                label: const Text('Enviar mensagem'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border.all(color: AppTheme.lightBlueBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.lightGold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.accent, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
