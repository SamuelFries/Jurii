import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'data/mock/mock_users.dart';
import 'models/appointment.dart';
import 'models/lawyer_status.dart';
import 'models/lawyer_verification.dart';
import 'models/user_profile.dart';
import 'repositories/auth_repository.dart';
import 'repositories/profile_repository.dart';
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
import 'types/auth_callbacks.dart';
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
  final AuthRepository _authRepository = const AuthRepository();
  final ProfileRepository _profileRepository = const ProfileRepository();

  bool _isLoggedIn = false;
  bool _isLawyerMode = false;
  bool _isBootstrapping = true;
  UserProfile _currentUser = mockCurrentUser;
  LawyerVerification? _lawyerVerification;

  @override
  void initState() {
    super.initState();
    _bootstrapSession();
  }

  Future<void> _bootstrapSession() async {
    if (!SupabaseConfig.isConfigured) {
      setState(() => _isBootstrapping = false);
      return;
    }

    final session = _authRepository.currentSession;
    if (session == null) {
      setState(() => _isBootstrapping = false);
      return;
    }

    try {
      final profile = await _profileRepository.fetchCurrentProfile();
      setState(() {
        _currentUser = profile ?? mockCurrentUser;
        _isLoggedIn = true;
        _isBootstrapping = false;
      });
    } catch (error) {
      debugPrint('Supabase bootstrap failed: $error');
      setState(() {
        _isLoggedIn = false;
        _isBootstrapping = false;
      });
    }
  }

  Future<void> _handleLogin(String email, String password) async {
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        _currentUser = _localProfileForRegistration(
          fullName: _nameFromEmail(email),
          email: email,
        );
        _isLoggedIn = true;
      });
      return;
    }

    final response = await _authRepository.signIn(
      email: email,
      password: password,
    );
    final user = response.user ?? SupabaseConfig.client.auth.currentUser;
    final fallbackProfile = _localProfileFromAuthUser(user, email);

    UserProfile? profile;
    var profileFetchFailed = false;
    try {
      profile = await _profileRepository.fetchCurrentProfile();
    } catch (error) {
      profileFetchFailed = true;
      debugPrint('Supabase profile fetch after login failed: $error');
    }

    if (profile == null && !profileFetchFailed && user != null) {
      try {
        await _profileRepository.upsertProfile(
          id: user.id,
          fullName: fallbackProfile.name,
          email: fallbackProfile.email,
          cpf: user.userMetadata?['cpf'] as String?,
        );
        profile = await _profileRepository.fetchCurrentProfile();
      } catch (error) {
        debugPrint('Supabase profile recovery after login failed: $error');
      }
    }

    setState(() {
      _currentUser = profile ?? fallbackProfile;
      _isLoggedIn = true;
    });
  }

  Future<RegisterResult> _handleRegister({
    required String fullName,
    required String email,
    required String cpf,
    required String password,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        _currentUser = _localProfileForRegistration(
          fullName: fullName,
          email: email,
        );
        _isLoggedIn = true;
      });
      return RegisterResult.signedIn;
    }

    final response = await _authRepository.signUp(
      fullName: fullName,
      email: email,
      password: password,
      cpf: cpf,
    );

    if (response.session == null) {
      return RegisterResult.needsEmailConfirmation;
    }

    final user = response.user;
    if (user != null) {
      try {
        await _profileRepository.upsertProfile(
          id: user.id,
          fullName: fullName,
          email: email,
          cpf: cpf,
        );
      } catch (error) {
        debugPrint('Supabase profile update after sign up failed: $error');
      }
    }

    UserProfile? profile;
    try {
      profile = await _profileRepository.fetchCurrentProfile();
    } catch (error) {
      debugPrint('Supabase profile fetch after sign up failed: $error');
    }

    setState(() {
      _currentUser =
          profile ??
          _localProfileForRegistration(
            id: user?.id,
            fullName: fullName,
            email: email,
          );
      _isLoggedIn = true;
    });
    return RegisterResult.signedIn;
  }

  UserProfile _localProfileForRegistration({
    String? id,
    required String fullName,
    required String email,
  }) {
    final name = fullName.trim().isEmpty ? 'Usuário Jurii' : fullName.trim();
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = parts.length > 1
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : parts.first.substring(0, 1).toUpperCase();

    return mockCurrentUser.copyWith(
      id: id ?? mockCurrentUser.id,
      name: name,
      email: email,
      initials: initials,
      lawyerStatus: LawyerStatus.client,
      oabNumber: null,
    );
  }

  UserProfile _localProfileFromAuthUser(User? user, String typedEmail) {
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final email = user?.email ?? typedEmail;
    final fullName =
        metadata['full_name'] as String? ??
        metadata['name'] as String? ??
        _nameFromEmail(email);

    return _localProfileForRegistration(
      id: user?.id,
      fullName: fullName,
      email: email,
    );
  }

  String _nameFromEmail(String email) {
    final localPart = email.split('@').first.trim();
    if (localPart.isEmpty) return 'Usuário Jurii';
    return localPart
        .split(RegExp(r'[._-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _handleLogout() async {
    if (SupabaseConfig.isConfigured) {
      await _authRepository.signOut();
    }

    setState(() {
      _isLoggedIn = false;
      _isLawyerMode = false;
      _currentUser = mockCurrentUser;
      _lawyerVerification = null;
    });
  }

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
      home: _isBootstrapping
          ? const _BootstrapScreen()
          : !_isLoggedIn
          ? LoginScreen(onLogin: _handleLogin, onRegister: _handleRegister)
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

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
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
