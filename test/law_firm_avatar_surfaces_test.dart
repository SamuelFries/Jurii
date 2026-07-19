import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/conversation.dart';
import 'package:jurii/models/law_firm.dart';
import 'package:jurii/screens/chat_screen.dart';
import 'package:jurii/screens/law_firm_profile_screen.dart';
import 'package:jurii/services/supabase_config.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/conversation_card.dart';
import 'package:jurii/widgets/office_card.dart';
import 'package:jurii/widgets/profile_avatar.dart';

const _firmAvatarPath =
    '/storage/v1/object/public/law-firm-avatars/'
    '93000000-0000-0000-0000-000000000001/'
    '93000000-0000-0000-0000-000000000002/escritorio.png';

const _lawFirmWithAvatar = LawFirm(
  id: 'firm-avatar',
  name: 'Fries Advogados',
  initials: 'FA',
  rating: 4.8,
  distance: '2 km',
  specialty: 'Direito Empresarial',
  practiceAreas: ['Direito Empresarial'],
  reviews: 18,
  avatarType: 'purple',
  avatarUrl: _firmAvatarPath,
);

const _firmConversationWithAvatar = Conversation(
  initials: 'FA',
  avatarUrl: _firmAvatarPath,
  officeName: 'Fries Advogados',
  specialty: 'Direito Empresarial',
  lastMessage: 'Conversa iniciada.',
  time: 'Agora',
  unreadCount: 0,
  type: 'client_firm',
  lawFirmId: 'firm-avatar',
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

void _expectFirmAvatar(WidgetTester tester) {
  expect(find.byType(ProfileAvatar), findsOneWidget);

  final image = tester.widget<Image>(find.byType(Image));
  expect(image.image, isA<NetworkImage>());
  expect(
    (image.image as NetworkImage).url,
    '${SupabaseConfig.url}$_firmAvatarPath',
  );
}

void main() {
  testWidgets('card de escritório usa a foto do perfil', (tester) async {
    await tester.pumpWidget(
      _cardApp(
        const OfficeCard(
          initials: 'FA',
          officeName: 'Fries Advogados',
          rating: 4.8,
          distance: '2 km',
          specialty: 'Direito Empresarial',
          reviews: 18,
          avatarType: 'purple',
          avatarUrl: _firmAvatarPath,
        ),
      ),
    );

    _expectFirmAvatar(tester);
  });

  testWidgets('perfil do escritório usa a foto enviada na verificação', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenApp(const LawFirmProfileScreen(lawFirm: _lawFirmWithAvatar)),
    );

    _expectFirmAvatar(tester);
  });

  testWidgets('card da conversa com escritório usa a foto do escritório', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardApp(
        ConversationCard(
          conversation: _firmConversationWithAvatar,
          onTap: () {},
        ),
      ),
    );

    _expectFirmAvatar(tester);
  });

  testWidgets('cabeçalho do chat usa a foto do escritório', (tester) async {
    await tester.pumpWidget(
      _screenApp(
        const ChatScreen(
          conversation: _firmConversationWithAvatar,
          isLawyer: false,
          allowTriage: false,
        ),
      ),
    );

    _expectFirmAvatar(tester);
  });

  testWidgets('card de escritório sem foto mantém as iniciais', (tester) async {
    await tester.pumpWidget(
      _cardApp(
        const OfficeCard(
          initials: 'SF',
          officeName: 'Sem Foto Advocacia',
          rating: 0,
          distance: '',
          specialty: 'Direito Cível',
          reviews: 0,
          avatarType: 'purple',
        ),
      ),
    );

    expect(find.byType(ProfileAvatar), findsOneWidget);
    expect(find.text('SF'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
