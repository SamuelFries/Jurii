import 'package:flutter/material.dart';

import '../data/legal_practice_areas.dart';
import '../models/lawyer_profile_summary.dart';
import '../repositories/favorites_repository.dart';
import '../repositories/messaging_repository.dart';
import '../repositories/review_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/favorite_heart_button.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/reviews_panel.dart';
import 'chat_screen.dart';

class LawyerProfileScreen extends StatefulWidget {
  const LawyerProfileScreen({
    super.key,
    required this.lawyer,
    this.messagingRepository = const MessagingRepository(),
  });

  final LawyerProfileSummary lawyer;
  final MessagingRepository messagingRepository;

  @override
  State<LawyerProfileScreen> createState() => _LawyerProfileScreenState();
}

class _LawyerProfileScreenState extends State<LawyerProfileScreen> {
  bool _isOpeningChat = false;

  Color _avatarColor(AppColors colors) => switch (widget.lawyer.avatarType) {
    'gold' => colors.accent,
    'navy' => colors.primary,
    _ => colors.lightBlue,
  };

  Color _avatarTextColor(AppColors colors) =>
      switch (widget.lawyer.avatarType) {
        'gold' || 'navy' => colors.card,
        _ => colors.primary,
      };

  Future<void> _openChat() async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);

    try {
      final conversation = await widget.messagingRepository
          .startLawyerConversation(lawyer: widget.lawyer);

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
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Perfil profissional'),
        actions: [
          FavoriteHeartButton(
            type: FavoriteTargetType.lawyer,
            targetId: widget.lawyer.id,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.card,
                border: Border.all(color: colors.lightGoldBorder),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProfileAvatar(
                        imageUrl: widget.lawyer.photoUrl,
                        initials: widget.lawyer.initials,
                        size: 64,
                        backgroundColor: _avatarColor(colors),
                        foregroundColor: _avatarTextColor(colors),
                        borderRadius: BorderRadius.circular(18),
                        fontSize: 20,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.lawyer.name,
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
                              practiceAreaSummary(widget.lawyer.practiceAreas),
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
                        icon: Icons.workspace_premium_outlined,
                        label: widget.lawyer.oabLabel,
                      ),
                      _InfoChip(
                        icon: Icons.star,
                        label: widget.lawyer.reviews == 0
                            ? 'Novo'
                            : '${widget.lawyer.rating} (${widget.lawyer.reviews})',
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
                  _AreaTags(areas: widget.lawyer.practiceAreas),
                  const SizedBox(height: 12),
                  Text(
                    widget.lawyer.bio,
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
            const _ProfileSection(
              title: 'Atendimento',
              child: Column(
                children: [
                  _ContactRow(
                    icon: Icons.chat_bubble_outline,
                    label: 'Atendimento online pela Jurii',
                  ),
                  SizedBox(height: 10),
                  _ContactRow(
                    icon: Icons.lock_outline,
                    label: 'Conversa privada e segura',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ReviewsPanel(
              target: ReviewTarget.lawyer,
              targetId: widget.lawyer.id,
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
        border: Border.all(color: colors.lightGoldBorder),
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
                color: colors.lightGold,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                area,
                style: TextStyle(
                  color: colors.accent,
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
        Icon(icon, color: colors.accent, size: 20),
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
