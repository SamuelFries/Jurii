import 'package:flutter/material.dart';

import 'data/mock/mock_users.dart';
import 'models/appointment.dart';
import 'models/lawyer_status.dart';
import 'models/lawyer_verification.dart';
import 'models/user_profile.dart';
import 'screens/agenda_screen.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/cases_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lawyer_home_screen.dart';
import 'screens/lawyer_messages_screen.dart';
import 'screens/lawyer_cases_screen.dart';

import 'theme/app_theme.dart';
import 'services/supabase_config.dart';
import 'widgets/jurii_bottom_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const JuriiApp());
}

class JuriiApp extends StatefulWidget {
  const JuriiApp({super.key});

  @override
  State<JuriiApp> createState() => _JuriiAppState();
}

class _JuriiAppState extends State<JuriiApp> {
  bool _isLoggedIn = false;
  bool _isLawyerMode = false;
  UserProfile _currentUser = mockCurrentUser;
  LawyerVerification? _lawyerVerification;

  void _handleLogin() => setState(() => _isLoggedIn = true);
  void _handleLogout() => setState(() {
    _isLoggedIn = false;
    _isLawyerMode = false;
    _currentUser = mockCurrentUser;
    _lawyerVerification = null;
  });
  void _switchToLawyer() {
    if (_currentUser.lawyerStatus != LawyerStatus.approved) return;
    setState(() => _isLawyerMode = true);
  }

  void _switchToClient() => setState(() => _isLawyerMode = false);
  void _handleVerificationSubmitted(LawyerVerification verification) {
    setState(() {
      _lawyerVerification = verification;
      _currentUser = _currentUser.copyWith(
        lawyerStatus: LawyerStatus.pending,
        oabNumber: 'OAB/${verification.oabState} ${verification.oabNumber}',
      );
      _isLawyerMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jurii',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: !_isLoggedIn
          ? LoginScreen(onLogin: _handleLogin)
          : _isLawyerMode
          ? LawyerNavigation(
              user: _currentUser,
              onSwitchToClient: _switchToClient,
              onLogout: _handleLogout,
            )
          : MainNavigation(
              user: _currentUser,
              lawyerVerification: _lawyerVerification,
              onSwitchToLawyer: _switchToLawyer,
              onVerificationSubmitted: _handleVerificationSubmitted,
              onLogout: _handleLogout,
            ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final UserProfile user;
  final LawyerVerification? lawyerVerification;
  final VoidCallback onSwitchToLawyer;
  final ValueChanged<LawyerVerification> onVerificationSubmitted;
  final VoidCallback onLogout;

  const MainNavigation({
    super.key,
    required this.user,
    required this.lawyerVerification,
    required this.onSwitchToLawyer,
    required this.onVerificationSubmitted,
    required this.onLogout,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const HomeScreen(),
      MessagesScreen(onFindLawFirms: () => setState(() => currentIndex = 0)),
      CasesScreen(onFindLawFirms: () => setState(() => currentIndex = 0)),
      ProfileScreen(
        user: widget.user,
        lawyerVerification: widget.lawyerVerification,
        onSwitchToLawyer: widget.onSwitchToLawyer,
        onVerificationSubmitted: widget.onVerificationSubmitted,
        onOpenMessages: () => setState(() => currentIndex = 1),
        onOpenCases: () => setState(() => currentIndex = 2),
        onOpenAgenda: () => _openAgenda(AppointmentRole.client),
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: pages[currentIndex],
      bottomNavigationBar: JuriiBottomNav(
        currentIndex: currentIndex,
        onTap: (index) => setState(() => currentIndex = index),
      ),
    );
  }

  void _openAgenda(AppointmentRole role) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AgendaScreen(role: role)));
  }
}

class LawyerNavigation extends StatefulWidget {
  final UserProfile user;
  final VoidCallback onSwitchToClient;
  final VoidCallback onLogout;

  const LawyerNavigation({
    super.key,
    required this.user,
    required this.onSwitchToClient,
    required this.onLogout,
  });

  @override
  State<LawyerNavigation> createState() => _LawyerNavigationState();
}

class _LawyerNavigationState extends State<LawyerNavigation> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      LawyerHomeScreen(
        user: widget.user,
        onOpenMessages: () => setState(() => currentIndex = 1),
        onOpenCases: () => setState(() => currentIndex = 2),
        onOpenAgenda: () => _openAgenda(AppointmentRole.lawyer),
      ),
      const LawyerMessagesScreen(),
      const LawyerCasesScreen(),
      ProfileScreen(
        user: widget.user,
        onSwitchToClient: widget.onSwitchToClient,
        onOpenMessages: () => setState(() => currentIndex = 1),
        onOpenCases: () => setState(() => currentIndex = 2),
        onOpenAgenda: () => _openAgenda(AppointmentRole.lawyer),
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: pages[currentIndex],
      bottomNavigationBar: JuriiBottomNav(
        currentIndex: currentIndex,
        onTap: (index) => setState(() => currentIndex = index),
      ),
    );
  }

  void _openAgenda(AppointmentRole role) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AgendaScreen(role: role)));
  }
}
