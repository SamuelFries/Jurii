import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/data/mock/mock_users.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/models/lawyer_profile_summary.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/screens/client_profile_screen.dart';
import 'package:jurii/screens/lawyer_profile_screen.dart';
import 'package:jurii/services/supabase_config.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/conversation_card.dart';
import 'package:jurii/widgets/lawyer_profile_card.dart';
import 'package:jurii/widgets/profile_avatar.dart';

const _avatarPath =
    '/storage/v1/object/public/profile-avatars/'
    '92000000-0000-0000-0000-000000000001/avatar.png';

const _lawyerWithAvatar = LawyerProfileSummary(
  id: 'lawyer-avatar',
  name: 'Ana Souza',
  initials: 'AS',
  oabNumber: '123456',
  oabState: 'SP',
  primaryArea: 'Direito Trabalhista',
  practiceAreas: ['Direito Trabalhista'],
  bio: 'Atuação em Direito Trabalhista.',
  rating: 4.9,
  reviews: 12,
  avatarType: 'navy',
  photoUrl: _avatarPath,
);

const _conversationWithAvatar = Conversation(
  initials: 'AS',
  avatarUrl: _avatarPath,
  officeName: 'Ana Souza',
  specialty: 'Direito Trabalhista',
  lastMessage: 'Conversa iniciada.',
  time: 'Agora',
  unreadCount: 0,
  type: 'client_lawyer',
  lawyerId: 'lawyer-avatar',
);

Widget _cardApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _screenApp(Widget child) {
  return MaterialApp(theme: AppTheme.lightTheme, home: child);
}

void _expectRemoteAvatar(WidgetTester tester) {
  expect(find.byType(ProfileAvatar), findsOneWidget);

  final image = tester.widget<Image>(find.byType(Image));
  expect(image.image, isA<NetworkImage>());
  expect(
    (image.image as NetworkImage).url,
    '${SupabaseConfig.url}$_avatarPath',
  );
}

void main() {
  testWidgets('card de advogado usa a foto do perfil', (tester) async {
    await tester.pumpWidget(
      _cardApp(const LawyerProfileCard(lawyer: _lawyerWithAvatar)),
    );

    _expectRemoteAvatar(tester);
  });

  testWidgets('mini perfil do advogado usa a foto do perfil', (tester) async {
    await tester.pumpWidget(
      _screenApp(const LawyerProfileScreen(lawyer: _lawyerWithAvatar)),
    );

    _expectRemoteAvatar(tester);
  });

  testWidgets('card de conversa usa a foto da contraparte', (tester) async {
    await tester.pumpWidget(
      _cardApp(
        ConversationCard(conversation: _conversationWithAvatar, onTap: () {}),
      ),
    );

    _expectRemoteAvatar(tester);
  });

  testWidgets('cabeçalho do chat usa a foto da contraparte', (tester) async {
    await tester.pumpWidget(
      _screenApp(
        const ChatScreen(
          conversation: _conversationWithAvatar,
          isLawyer: false,
          allowTriage: false,
        ),
      ),
    );

    _expectRemoteAvatar(tester);
  });

  testWidgets('mini perfil do cliente usa a foto do perfil', (tester) async {
    final clientWithAvatar = mockCurrentUser.copyWith(avatarUrl: _avatarPath);

    await tester.pumpWidget(
      _screenApp(ClientProfileScreen(profile: clientWithAvatar)),
    );

    _expectRemoteAvatar(tester);
  });

  testWidgets('card de conversa sem foto mantém as iniciais', (tester) async {
    const conversationWithoutAvatar = Conversation(
      initials: 'CL',
      officeName: 'Cliente sem foto',
      specialty: 'Direito Cível',
      lastMessage: 'Conversa iniciada.',
      time: 'Agora',
      unreadCount: 0,
      type: 'client_lawyer',
    );

    await tester.pumpWidget(
      _cardApp(
        ConversationCard(conversation: conversationWithoutAvatar, onTap: () {}),
      ),
    );

    expect(find.byType(ProfileAvatar), findsOneWidget);
    expect(find.text('CL'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
