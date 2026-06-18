import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, User;

import 'data/mock/mock_users.dart';
import 'models/appointment.dart';
import 'models/law_firm_verification.dart';
import 'models/law_firm_verification_status.dart';
import 'models/lawyer_status.dart';
import 'models/lawyer_verification.dart';
import 'models/firm_role.dart';
import 'models/firm_workspace.dart';
import 'models/social_auth_provider.dart';
import 'models/user_profile.dart';
import 'repositories/auth_repository.dart';
import 'repositories/firm_invitation_repository.dart';
import 'repositories/firm_workspace_repository.dart';
import 'repositories/law_firm_verification_repository.dart';
import 'repositories/lawyer_verification_repository.dart';
import 'repositories/profile_repository.dart';
import 'screens/agenda_screen.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/password_reset_screen.dart';
import 'screens/cases_screen.dart';
import 'screens/firm_cases_screen.dart';
import 'screens/firm_home_screen.dart';
import 'screens/firm_messages_screen.dart';
import 'screens/firm_profile_screen.dart';
import 'screens/firm_team_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lawyer_home_screen.dart';
import 'screens/lawyer_messages_screen.dart';
import 'screens/lawyer_cases_screen.dart';

import 'theme/app_theme.dart';
import 'services/supabase_config.dart';
import 'types/auth_callbacks.dart';
import 'widgets/firm_bottom_nav.dart';
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
  final LawyerVerificationRepository _lawyerVerificationRepository =
      const LawyerVerificationRepository();
  final LawFirmVerificationRepository _lawFirmVerificationRepository =
      const LawFirmVerificationRepository();
  final FirmWorkspaceRepository _firmWorkspaceRepository =
      const FirmWorkspaceRepository();
  final FirmInvitationRepository _firmInvitationRepository =
      const FirmInvitationRepository();
  StreamSubscription<AuthState>? _authSubscription;

  bool _isLoggedIn = false;
  bool _isLawyerMode = false;
  bool _isFirmMode = false;
  bool _isBootstrapping = true;
  bool _isPasswordRecovery = false;
  bool _isPasswordRecoveryExpected = false;
  bool _isCompletingAuthSession = false;
  UserProfile _currentUser = mockCurrentUser;
  LawyerVerification? _lawyerVerification;
  LawFirmVerification? _lawFirmVerification;
  FirmWorkspace? _firmWorkspace;

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.isReady) {
      _authSubscription = SupabaseConfig.client.auth.onAuthStateChange.listen(
        _handleAuthStateChange,
      );
    }
    _bootstrapSession();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _handleAuthStateChange(AuthState authState) {
    if (!mounted) return;

    if (authState.event == AuthChangeEvent.passwordRecovery) {
      _openPasswordRecoveryFlow();
      return;
    }

    if (authState.event == AuthChangeEvent.signedOut) {
      setState(_clearSessionState);
      return;
    }

    if (authState.event == AuthChangeEvent.signedIn ||
        authState.event == AuthChangeEvent.initialSession) {
      final user = authState.session?.user;
      if (user != null) {
        if (_isPasswordRecoveryExpected) {
          _openPasswordRecoveryFlow();
          return;
        }
        _completeAuthenticatedSession(authUser: user);
      }
    }
  }

  void _openPasswordRecoveryFlow() {
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _isLawyerMode = false;
      _isFirmMode = false;
      _isPasswordRecovery = true;
      _isPasswordRecoveryExpected = true;
      _isBootstrapping = false;
    });
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
      await _completeAuthenticatedSession(authUser: session.user);
      if (mounted && !_isLoggedIn && !_isCompletingAuthSession) {
        setState(() => _isBootstrapping = false);
      }
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
    _isPasswordRecoveryExpected = false;
    await _completeAuthenticatedSession(
      authUser: response.user ?? SupabaseConfig.client.auth.currentUser,
      fallbackEmail: email,
    );
  }

  Future<void> _handleSocialLogin(SocialAuthProvider provider) async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase is not configured.');
    }

    _isPasswordRecoveryExpected = false;
    final launched = await _authRepository.signInWithSocialProvider(provider);
    if (!launched) {
      throw StateError('Could not launch social login.');
    }
  }

  Future<void> _handlePasswordResetRequested(String email) async {
    if (!SupabaseConfig.isConfigured) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _isPasswordRecoveryExpected = true;
      return;
    }

    await _authRepository.sendPasswordResetEmail(email);
    _isPasswordRecoveryExpected = true;
  }

  Future<void> _handlePasswordUpdate(String password) async {
    if (!SupabaseConfig.isReady) {
      throw StateError('Supabase is not ready.');
    }

    await _authRepository.updatePassword(password);
    _isPasswordRecoveryExpected = false;
    await _authRepository.signOut();
    if (!mounted) return;
    setState(_clearSessionState);
  }

  Future<void> _completeAuthenticatedSession({
    User? authUser,
    String? fallbackEmail,
  }) async {
    if (!SupabaseConfig.isReady || _isCompletingAuthSession) return;

    _isCompletingAuthSession = true;
    try {
      final user = authUser ?? SupabaseConfig.client.auth.currentUser;
      if (user == null) return;

      final typedEmail = fallbackEmail ?? user.email ?? '';
      final fallbackProfile = _localProfileFromAuthUser(user, typedEmail);

      UserProfile? profile;
      var profileFetchFailed = false;
      try {
        profile = await _profileRepository.fetchCurrentProfile();
      } catch (error) {
        profileFetchFailed = true;
        debugPrint('Supabase profile fetch after login failed: $error');
      }

      if (profile == null && !profileFetchFailed) {
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

      final lawyerVerification = await _fetchLatestLawyerVerification();
      final lawFirmVerification = await _fetchLatestLawFirmVerification();
      final firmWorkspace = await _fetchCurrentFirmWorkspace(
        lawFirmVerification,
      );

      if (!mounted) return;
      setState(() {
        _lawyerVerification = lawyerVerification;
        _currentUser = _userWithLawyerVerification(
          profile ?? fallbackProfile,
          lawyerVerification,
        );
        _lawFirmVerification = lawFirmVerification;
        _firmWorkspace = firmWorkspace;
        _isLoggedIn = true;
        _isPasswordRecovery = false;
        _isBootstrapping = false;
      });
    } finally {
      _isCompletingAuthSession = false;
    }
  }

  void _clearSessionState() {
    _isLoggedIn = false;
    _isLawyerMode = false;
    _isFirmMode = false;
    _isBootstrapping = false;
    _isPasswordRecovery = false;
    _isPasswordRecoveryExpected = false;
    _currentUser = mockCurrentUser;
    _lawyerVerification = null;
    _lawFirmVerification = null;
    _firmWorkspace = null;
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

    setState(_clearSessionState);
  }

  void _switchToLawyer() {
    if (_currentUser.lawyerStatus != LawyerStatus.approved) return;
    setState(() {
      _isLawyerMode = true;
      _isFirmMode = false;
    });
    _refreshFirmWorkspace();
  }

  void _switchToFirm() {
    final hasApprovedVerification =
        _lawFirmVerification?.status == LawFirmVerificationStatus.approved;
    final hasSyncedWorkspace = _firmWorkspace?.fromSupabase == true;

    if (!hasApprovedVerification && !hasSyncedWorkspace) {
      return;
    }
    setState(() {
      _isFirmMode = true;
      _isLawyerMode = false;
    });
    _refreshFirmWorkspace();
  }

  void _switchToClient() {
    setState(() {
      _isLawyerMode = false;
      _isFirmMode = false;
    });
  }

  void _handleVerificationSubmitted(LawyerVerification verification) {
    setState(() {
      _lawyerVerification = verification;
      _currentUser = _userWithLawyerVerification(_currentUser, verification);
      _isLawyerMode = false;
    });
  }

  Future<void> _refreshLawyerVerification() async {
    if (!SupabaseConfig.isReady) return;

    final verification = await _fetchLatestLawyerVerification();
    if (!mounted) return;
    setState(() {
      _lawyerVerification = verification;
      _currentUser = _userWithLawyerVerification(_currentUser, verification);
    });
  }

  Future<LawyerVerification?> _fetchLatestLawyerVerification() async {
    try {
      return await _lawyerVerificationRepository.fetchLatestForCurrentUser();
    } catch (error) {
      debugPrint('Supabase lawyer verification fetch failed: $error');
      return _lawyerVerification;
    }
  }

  UserProfile _userWithLawyerVerification(
    UserProfile user,
    LawyerVerification? verification,
  ) {
    if (verification == null) return user;
    return user.copyWith(
      lawyerStatus: verification.status,
      oabNumber: verification.oabNumber.isEmpty
          ? user.oabNumber
          : 'OAB/${verification.oabState} ${verification.oabNumber}',
    );
  }

  Future<void> _refreshLawFirmVerification() async {
    if (!SupabaseConfig.isReady) return;

    final verification = await _fetchLatestLawFirmVerification();
    final workspace = await _fetchCurrentFirmWorkspace(verification);
    if (!mounted) return;
    setState(() {
      _lawFirmVerification = verification;
      _firmWorkspace = workspace;
    });
  }

  Future<LawFirmVerification?> _fetchLatestLawFirmVerification() async {
    try {
      return await _lawFirmVerificationRepository.fetchLatestForCurrentUser();
    } catch (error) {
      debugPrint('Supabase law firm verification fetch failed: $error');
      return _lawFirmVerification;
    }
  }

  void _handleLawFirmVerificationSubmitted(LawFirmVerification verification) {
    setState(() {
      _lawFirmVerification = verification;
      _firmWorkspace = null;
      _isLawyerMode = false;
    });
  }

  Future<void> _refreshFirmWorkspace() async {
    if (!SupabaseConfig.isReady) return;

    final workspace = await _fetchCurrentFirmWorkspace(_lawFirmVerification);
    if (!mounted) return;
    setState(() => _firmWorkspace = workspace);
  }

  Future<FirmWorkspace?> _fetchCurrentFirmWorkspace([
    LawFirmVerification? verification,
  ]) async {
    try {
      return await _firmWorkspaceRepository.fetchCurrentWorkspace(
        verification: verification ?? _lawFirmVerification,
      );
    } catch (error) {
      debugPrint('Supabase firm workspace fetch failed: $error');
      return _firmWorkspace;
    }
  }

  Future<void> _inviteLawyerToFirm({
    required String oabState,
    required String oabNumber,
  }) async {
    final workspace = _firmWorkspace;
    if (workspace == null || !workspace.fromSupabase) {
      throw StateError(
        'A área do escritório precisa estar aprovada e sincronizada.',
      );
    }

    await _firmInvitationRepository.inviteVerifiedLawyer(
      lawFirmId: workspace.firm.id,
      oabState: oabState,
      oabNumber: oabNumber,
    );
    await _refreshFirmWorkspace();
  }

  Future<void> _updateFirmMemberRoles({
    required String memberProfileId,
    required List<FirmRole> roles,
  }) async {
    final workspace = _firmWorkspace;
    if (workspace == null || !workspace.fromSupabase) {
      throw StateError(
        'A Ã¡rea do escritÃ³rio precisa estar aprovada e sincronizada.',
      );
    }

    await _firmWorkspaceRepository.updateMemberRoles(
      lawFirmId: workspace.firm.id,
      memberProfileId: memberProfileId,
      roles: roles,
    );
    await _refreshFirmWorkspace();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jurii',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _isBootstrapping
          ? const _BootstrapScreen()
          : _isPasswordRecovery
          ? PasswordResetScreen(
              onUpdatePassword: _handlePasswordUpdate,
              onCancel: _handleLogout,
            )
          : !_isLoggedIn
          ? LoginScreen(
              onLogin: _handleLogin,
              onSocialLogin: _handleSocialLogin,
              onPasswordResetRequested: _handlePasswordResetRequested,
              onRegister: _handleRegister,
            )
          : _isFirmMode
          ? FirmNavigation(
              user: _currentUser,
              workspace: _firmWorkspace,
              onInviteLawyer: _inviteLawyerToFirm,
              onUpdateMemberRoles: _updateFirmMemberRoles,
              onSwitchToClient: _switchToClient,
              onSwitchToLawyer:
                  _currentUser.lawyerStatus == LawyerStatus.approved
                  ? _switchToLawyer
                  : null,
              onLogout: _handleLogout,
            )
          : _isLawyerMode
          ? LawyerNavigation(
              user: _currentUser,
              workspace: _firmWorkspace,
              onRefreshFirmWorkspace: _refreshFirmWorkspace,
              onSwitchToFirm: _switchToFirm,
              onSwitchToClient: _switchToClient,
              onLogout: _handleLogout,
            )
          : MainNavigation(
              user: _currentUser,
              lawyerVerification: _lawyerVerification,
              lawFirmVerification: _lawFirmVerification,
              onSwitchToLawyer: _switchToLawyer,
              onSwitchToFirm: _switchToFirm,
              onVerificationSubmitted: _handleVerificationSubmitted,
              onRefreshLawyerVerification: _refreshLawyerVerification,
              onLawFirmVerificationSubmitted:
                  _handleLawFirmVerificationSubmitted,
              onRefreshLawFirmVerification: _refreshLawFirmVerification,
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
  final LawFirmVerification? lawFirmVerification;
  final VoidCallback onSwitchToLawyer;
  final VoidCallback onSwitchToFirm;
  final ValueChanged<LawyerVerification> onVerificationSubmitted;
  final Future<void> Function() onRefreshLawyerVerification;
  final ValueChanged<LawFirmVerification> onLawFirmVerificationSubmitted;
  final Future<void> Function() onRefreshLawFirmVerification;
  final VoidCallback onLogout;

  const MainNavigation({
    super.key,
    required this.user,
    required this.lawyerVerification,
    required this.lawFirmVerification,
    required this.onSwitchToLawyer,
    required this.onSwitchToFirm,
    required this.onVerificationSubmitted,
    required this.onRefreshLawyerVerification,
    required this.onLawFirmVerificationSubmitted,
    required this.onRefreshLawFirmVerification,
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
        lawFirmVerification: widget.lawFirmVerification,
        onSwitchToLawyer: widget.onSwitchToLawyer,
        onVerificationSubmitted: widget.onVerificationSubmitted,
        onRefreshLawyerVerification: widget.onRefreshLawyerVerification,
        onLawFirmVerificationSubmitted: widget.onLawFirmVerificationSubmitted,
        onOpenLawFirmArea: widget.onSwitchToFirm,
        onRefreshLawFirmVerification: widget.onRefreshLawFirmVerification,
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
        onTap: (index) {
          setState(() => currentIndex = index);
          if (index == 3) {
            widget.onRefreshLawyerVerification();
            widget.onRefreshLawFirmVerification();
          }
        },
      ),
    );
  }

  void _openAgenda(AppointmentRole role) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AgendaScreen(role: role)));
  }
}

class FirmNavigation extends StatefulWidget {
  const FirmNavigation({
    super.key,
    required this.user,
    required this.workspace,
    required this.onInviteLawyer,
    required this.onUpdateMemberRoles,
    required this.onSwitchToClient,
    this.onSwitchToLawyer,
    required this.onLogout,
  });

  final UserProfile user;
  final FirmWorkspace? workspace;
  final Future<void> Function({
    required String oabState,
    required String oabNumber,
  })
  onInviteLawyer;
  final Future<void> Function({
    required String memberProfileId,
    required List<FirmRole> roles,
  })
  onUpdateMemberRoles;
  final VoidCallback onSwitchToClient;
  final VoidCallback? onSwitchToLawyer;
  final VoidCallback onLogout;

  @override
  State<FirmNavigation> createState() => _FirmNavigationState();
}

class _FirmNavigationState extends State<FirmNavigation> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      FirmHomeScreen(
        workspace: widget.workspace,
        onOpenMessages: () => setState(() => currentIndex = 1),
        onOpenTeam: () => setState(() => currentIndex = 2),
        onOpenCases: () => setState(() => currentIndex = 3),
      ),
      FirmMessagesScreen(workspace: widget.workspace),
      FirmTeamScreen(
        workspace: widget.workspace,
        teamMembers: widget.workspace?.teamMembers,
        onInviteLawyer: widget.onInviteLawyer,
        onUpdateMemberRoles: widget.onUpdateMemberRoles,
      ),
      FirmCasesScreen(workspace: widget.workspace),
      FirmProfileScreen(
        user: widget.user,
        workspace: widget.workspace,
        onSwitchToClient: widget.onSwitchToClient,
        onSwitchToLawyer: widget.onSwitchToLawyer,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: pages[currentIndex],
      bottomNavigationBar: FirmBottomNav(
        currentIndex: currentIndex,
        onTap: (index) => setState(() => currentIndex = index),
      ),
    );
  }
}

class LawyerNavigation extends StatefulWidget {
  final UserProfile user;
  final FirmWorkspace? workspace;
  final Future<void> Function() onRefreshFirmWorkspace;
  final VoidCallback onSwitchToFirm;
  final VoidCallback onSwitchToClient;
  final VoidCallback onLogout;

  const LawyerNavigation({
    super.key,
    required this.user,
    required this.workspace,
    required this.onRefreshFirmWorkspace,
    required this.onSwitchToFirm,
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
        workspace: widget.workspace,
        onOpenMessages: () => setState(() => currentIndex = 1),
        onOpenCases: () => setState(() => currentIndex = 2),
        onOpenAgenda: () => _openAgenda(AppointmentRole.lawyer),
        onNotificationsChanged: widget.onRefreshFirmWorkspace,
      ),
      const LawyerMessagesScreen(),
      const LawyerCasesScreen(),
      ProfileScreen(
        user: widget.user,
        firmWorkspace: widget.workspace,
        onOpenLawFirmArea: widget.onSwitchToFirm,
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
