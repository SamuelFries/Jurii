import 'package:flutter/material.dart';

import '../models/lawyer_recommendation.dart';
import '../theme/app_colors.dart';
import 'profile_avatar.dart';
import 'chat_bubble_metrics.dart';

/// Miniatura do perfil do advogado sugerido pelo escritório, exibida no chat
/// como um card (o mesmo lugar que a caixa de aceite de caso ocupava).
///
/// O botão grande é do cliente: é ele quem abre a conversa com o advogado.
/// Para o escritório, que enviou a sugestão, o card fica sem botão — vira só o
/// registro do que foi indicado.
class LawyerRecommendationCard extends StatelessWidget {
  const LawyerRecommendationCard({
    super.key,
    required this.recommendation,
    required this.time,
    this.canMessage = false,
    this.isOpeningChat = false,
    this.onMessage,
  });

  final LawyerRecommendation recommendation;
  final String time;
  final bool canMessage;
  final bool isOpeningChat;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    final area = recommendation.primaryArea;
    final note = recommendation.note;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: chatCardWidthFor(MediaQuery.sizeOf(context).width),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            border: Border.all(color: colors.officePurpleBorder),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.officePurpleSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.recommend_outlined,
                      size: 15,
                      color: colors.officePurple,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sugestão do escritório',
                      style: TextStyle(
                        color: colors.officePurple,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ProfileAvatar(
                    imageUrl: recommendation.photoUrl,
                    initials: recommendation.initials,
                    size: 64,
                    backgroundColor: colors.officePurpleSurface,
                    foregroundColor: colors.officePurple,
                    borderRadius: BorderRadius.circular(18),
                    fontSize: 18,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recommendation.name,
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
                          recommendation.oabLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (area != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: 12),
                Text(
                  note,
                  style: TextStyle(color: colors.textSecondary, height: 1.35),
                ),
              ],
              if (canMessage) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isOpeningChat ? null : onMessage,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: isOpeningChat
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
              const SizedBox(height: 8),
              Text(
                time,
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
