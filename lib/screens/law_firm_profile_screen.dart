import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../models/law_firm.dart';
import '../repositories/messaging_repository.dart';
import '../repositories/review_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/reviews_panel.dart';
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

  Color _avatarColor(AppColors colors) => switch (widget.lawFirm.avatarType) {
    'navy' => colors.primary,
    'gold' => colors.accent,
    _ => colors.lightBlue,
  };

  Color _avatarTextColor(AppColors colors) =>
      switch (widget.lawFirm.avatarType) {
        'navy' || 'gold' => colors.card,
        _ => colors.primary,
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
    final colors = context.jColors;
    final description =
        widget.lawFirm.description ??
        'Escritório verificado na Jurii para atendimento jurídico especializado e acompanhamento de casos pela plataforma.';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Perfil do escritório')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.card,
                border: Border.all(color: colors.lightBlueBorder),
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
                          color: _avatarColor(colors),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Text(
                            widget.lawFirm.initials,
                            style: TextStyle(
                              color: _avatarTextColor(colors),
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
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              practiceAreaSummary(widget.lawFirm.practiceAreas),
                              style: TextStyle(
                                color: colors.textSecondary,
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
                        label: widget.lawFirm.reviews == 0
                            ? 'Novo'
                            : '${widget.lawFirm.rating} (${widget.lawFirm.reviews})',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AreaTags(areas: widget.lawFirm.practiceAreas),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ],
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
                  if (widget.lawFirm.phone != null &&
                      widget.lawFirm.phone!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ContactRow(
                      icon: Icons.phone_outlined,
                      label: widget.lawFirm.phone!,
                    ),
                  ],
                  if (widget.lawFirm.websiteUrl != null &&
                      widget.lawFirm.websiteUrl!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ContactRow(
                      icon: Icons.language_outlined,
                      label: widget.lawFirm.websiteUrl!,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _ContactRow(
                    icon: Icons.location_city_outlined,
                    label: widget.lawFirm.address ?? 'Atendimento remoto',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ReviewsPanel(
              target: ReviewTarget.lawFirm,
              targetId: widget.lawFirm.id,
              accentColor: colors.officePurple,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isOpeningChat ? null : _openChat,
                icon: _isOpeningChat
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.card,
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
    final colors = context.jColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.lightBlueBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
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
    final colors = context.jColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.lightGold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.accent, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaTags extends StatelessWidget {
  const _AreaTags({required this.areas});

  final List<String> areas;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    if (areas.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: areas
          .map(
            (area) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.lightBlue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                area,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
