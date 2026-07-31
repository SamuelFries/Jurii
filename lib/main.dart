import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, User;

import 'firebase_options.dart';
import 'services/push_notification_service.dart';

import 'models/appointment.dart';
import 'models/law_firm_verification.dart';
import 'models/law_firm_verification_status.dart';
import 'models/lawyer_status.dart';
import 'models/lawyer_verification.dart';
import 'models/profile_avatar_file.dart';
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
import 'screens/complete_profile_screen.dart';
import 'screens/edit_profile_screen.dart';
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

import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'services/app_navigator.dart';
import 'services/supabase_config.dart';
import 'types/auth_callbacks.dart';
import 'widgets/firm_bottom_nav.dart';
import 'widgets/jurii_bottom_nav.dart';
import 'widgets/jurii_motion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  await ThemeController.instance.load();
  await _initFirebase();
  runApp(const JuriiApp());
}

/// Inicializa o Firebase (para o push). Best-effort: se falhar, o app segue sem
/// push em vez de nao abrir.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (error) {
    debugPrint('Firebase init failed: $error');
  }
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
  final PushNotificationService _pushService = PushNotificationService();
  final FirmInvitationRepository _firmInvitationRepository =
      const FirmInvitationRepository();
  StreamSubscription<AuthState>? _authSubscription;

  static const UserProfile _guestUser = UserProfile(
    id: '',
    name: 'Usuário Jurii',
    email: '',
    initials: 'U',
    memberSince: 'Cliente Jurii',
    lawyerStatus: LawyerStatus.client,
  );

  bool _isLoggedIn = false;
  bool _isLawyerMode = false;
  bool _isFirmMode = false;
  bool _isBootstrapping = true;
  bool _bootstrapFailed = false;
  bool _isPasswordRecovery = false;
  bool _isPasswordRecoveryExpected = false;
  bool _needsProfileCompletion = false;
  Future<void>? _sessionCompletion;
  UserProfile _currentUser = _guestUser;
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
        unawaited(
          _completeAuthenticatedSession(authUser: user).catchError((error) {
            debugPrint('Supabase auth session completion failed: $error');
          }),
        );
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
      if (mounted && !_isLoggedIn) {
        setState(() => _isBootstrapping = false);
      }
    } on DeletedAccountException {
      // Sessão já encerrada em _completeAuthenticatedSession.
    } catch (error) {
      debugPrint('Supabase bootstrap failed: $error');
      if (!mounted) return;
      // Sessão válida, mas o perfil não pôde ser carregado (ex.: sem rede).
      // Mantém a sessão e oferece nova tentativa em vez de exibir dados falsos.
      setState(() {
        _isLoggedIn = false;
        _isBootstrapping = false;
        _bootstrapFailed = true;
      });
    }
  }

  Future<void> _retryBootstrap() async {
    setState(() {
      _bootstrapFailed = false;
      _isBootstrapping = true;
    });
    await _bootstrapSession();
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

  /// Conclui a sessão autenticada. Chamadas concorrentes (login aguardado +
  /// evento do stream de auth) compartilham o mesmo Future, para que erros
  /// cheguem a quem estiver aguardando em vez de serem engolidos.
  Future<void> _completeAuthenticatedSession({
    User? authUser,
    String? fallbackEmail,
  }) {
    final inFlight = _sessionCompletion;
    if (inFlight != null) return inFlight;

    final completion = _runAuthenticatedSessionCompletion(
      authUser: authUser,
      fallbackEmail: fallbackEmail,
    ).whenComplete(() => _sessionCompletion = null);
    _sessionCompletion = completion;
    return completion;
  }

  Future<void> _runAuthenticatedSessionCompletion({
    User? authUser,
    String? fallbackEmail,
  }) async {
    if (!SupabaseConfig.isReady) return;

    final user = authUser ?? SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    final typedEmail = fallbackEmail ?? user.email ?? '';
    final fallbackProfile = _localProfileFromAuthUser(user, typedEmail);

    UserProfile? profile;
    try {
      profile = await _fetchProfileWithRetry();
    } on DeletedAccountException {
      await _authRepository.signOut();
      if (mounted) {
        setState(_clearSessionState);
      }
      rethrow;
    }

    if (profile == null) {
      try {
        await _profileRepository.upsertProfile(
          fullName: fallbackProfile.name,
          cpf: user.userMetadata?['cpf'] as String?,
        );
        profile = await _profileRepository.fetchCurrentProfile();
      } catch (error) {
        debugPrint('Supabase profile recovery after login failed: $error');
      }
    }

    final lawyerVerification = await _fetchLatestLawyerVerification();
    final lawFirmVerification = await _fetchLatestLawFirmVerification();
    final firmWorkspace = await _fetchCurrentFirmWorkspace(lawFirmVerification);

    if (!mounted) return;
    setState(() {
      _lawyerVerification = lawyerVerification;
      _currentUser = _userWithLawyerVerification(
        profile ?? fallbackProfile,
        lawyerVerification,
      );
      _lawFirmVerification = lawFirmVerification;
      _firmWorkspace = firmWorkspace;
      // Só cobra os dados quando o perfil REAL foi lido: se a linha não veio
      // (falha ao criar/recuperar), o usuário não é barrado por uma dúvida
      // nossa — a cobrança volta no próximo login.
      _needsProfileCompletion =
          profile != null && profile.needsProfileCompletion;
      _isLoggedIn = true;
      _bootstrapFailed = false;
      _isPasswordRecovery = false;
      _isBootstrapping = false;
    });

    // Registra o token de push deste dispositivo. Best-effort — nao bloqueia
    // nem derruba a sessao se o push falhar.
    unawaited(_pushService.registerForCurrentUser());
  }

  /// Grava nome e CPF de quem entrou por Google/Apple e recarrega o perfil —
  /// é o retorno do banco que libera o acesso, não a suposição do app.
  Future<void> _handleCompleteProfile({
    required String fullName,
    required String? cpf,
  }) async {
    if (!SupabaseConfig.isReady) {
      setState(() {
        _currentUser = _currentUser.copyWith(name: fullName, cpf: cpf);
        _needsProfileCompletion = false;
      });
      return;
    }

    await _profileRepository.upsertProfile(fullName: fullName, cpf: cpf);

    final profile = await _profileRepository.fetchCurrentProfile();
    if (!mounted || profile == null) return;

    setState(() {
      _currentUser = _userWithLawyerVerification(profile, _lawyerVerification);
      _needsProfileCompletion = profile.needsProfileCompletion;
    });
  }

  Future<void> _handleProfileEdit({
    required String fullName,
    required String phone,
    ProfileAvatarFile? avatar,
    required bool removeAvatar,
  }) async {
    final normalizedName = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (!SupabaseConfig.isReady) {
      setState(() {
        _currentUser = _currentUser.copyWith(
          name: normalizedName,
          initials: _initialsForName(normalizedName),
          phone: phone.isEmpty ? null : phone,
          clearPhone: phone.isEmpty,
          clearAvatarUrl: removeAvatar,
        );
      });
      return;
    }

    final profile = await _profileRepository.updateCustomization(
      fullName: normalizedName,
      phone: phone,
      previousAvatarUrl: _currentUser.avatarUrl,
      avatar: avatar,
      removeAvatar: removeAvatar,
    );
    if (!mounted) return;

    var updated = _userWithLawyerVerification(profile, _lawyerVerification);
    if (updated.oabNumber == null && _currentUser.oabNumber != null) {
      updated = updated.copyWith(oabNumber: _currentUser.oabNumber);
    }
    setState(() => _currentUser = updated);
  }

  String _initialsForName(String value) {
    final parts = value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'UJ';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Uma nova tentativa cobre falhas transitórias de rede; se ambas falharem,
  /// o erro sobe para o chamador (login mostra o erro, bootstrap mostra a
  /// tela de nova tentativa) em vez de concluir a sessão com dados falsos.
  Future<UserProfile?> _fetchProfileWithRetry() async {
    try {
      return await _profileRepository.fetchCurrentProfile();
    } on DeletedAccountException {
      rethrow;
    } catch (error) {
      debugPrint('Supabase profile fetch failed, retrying: $error');
      return _profileRepository.fetchCurrentProfile();
    }
  }

  Future<void> _handleDeleteAccount() async {
    if (!SupabaseConfig.isReady) {
      setState(_clearSessionState);
      return;
    }

    await _pushService.disableForCurrentUser();
    await _profileRepository.deleteCurrentAccount();
    await _authRepository.signOut();
    if (!mounted) return;
    setState(_clearSessionState);
  }

  void _clearSessionState() {
    _isLoggedIn = false;
    _isLawyerMode = false;
    _isFirmMode = false;
    _isBootstrapping = false;
    _bootstrapFailed = false;
    _isPasswordRecovery = false;
    _isPasswordRecoveryExpected = false;
    _needsProfileCompletion = false;
    _currentUser = _guestUser;
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
    _isPasswordRecoveryExpected = false;
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
        await _profileRepository.upsertProfile(fullName: fullName, cpf: cpf);
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

    return UserProfile(
      id: id ?? '',
      name: name,
      email: email,
      initials: initials,
      memberSince: 'Cliente Jurii',
      lawyerStatus: LawyerStatus.client,
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
    try {
      if (SupabaseConfig.isConfigured) {
        // Remove o token ANTES do signOut (o unregister depende de auth.uid()),
        // para o aparelho nao receber push apos sair.
        await _pushService.disableForCurrentUser();
        await _authRepository.signOut();
      }
    } catch (error) {
      // Sem rede o endpoint de logout falha; a sessão local é limpa
      // mesmo assim para o usuário nunca ficar preso dentro do app.
      debugPrint('Supabase sign out failed: $error');
    } finally {
      if (mounted) {
        setState(_clearSessionState);
      }
    }
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
    final hasSyncedWorkspace = _firmWorkspace?.fromSupabase == true;
    final hasLocalDemoWorkspace =
        !SupabaseConfig.isReady &&
        _lawFirmVerification?.status == LawFirmVerificationStatus.approved;

    if (!hasSyncedWorkspace && !hasLocalDemoWorkspace) {
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
    // A foto profissional virou avatar no banco durante o submit; recarrega o
    // perfil para refletir no header.
    _refreshAvatarFromProfile();
  }

  Future<void> _refreshAvatarFromProfile() async {
    if (!SupabaseConfig.isReady) return;
    try {
      final profile = await _profileRepository.fetchCurrentProfile();
      if (!mounted || profile == null || profile.avatarUrl == null) return;
      setState(() {
        _currentUser = _currentUser.copyWith(avatarUrl: profile.avatarUrl);
      });
    } catch (error) {
      debugPrint('Falha ao atualizar avatar após verificação: $error');
    }
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
        'A área do escritório precisa estar aprovada e sincronizada.',
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'Jurii',
        debugShowCheckedModeBanner: false,
        // O toque num push chega de fora da árvore de widgets: sem esta chave
        // não há como navegar para o caso ou a conversa.
        navigatorKey: appNavigatorKey,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    // Só empilha destino de notificação quando o app está utilizável: nem no
    // boot, nem no login, nem na recuperação de senha, nem no portão de
    // completar cadastro (que é bloqueante de propósito).
    appCanRouteNotifications.value =
        !_isBootstrapping &&
        !_bootstrapFailed &&
        !_isPasswordRecovery &&
        _isLoggedIn &&
        !_needsProfileCompletion;

    return _isBootstrapping
        ? const _BootstrapScreen()
        : _bootstrapFailed
        ? _BootstrapErrorScreen(
            onRetry: _retryBootstrap,
            onLogout: _handleLogout,
          )
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
        // Google/Apple autenticam sem CPF (e a Apple, muitas vezes, sem nome).
        // Nada do app abre antes desses dados existirem.
        : _needsProfileCompletion
        ? CompleteProfileScreen(
            profile: _currentUser,
            onSubmit: _handleCompleteProfile,
            onLogout: _handleLogout,
          )
        : _isFirmMode
        ? FirmNavigation(
            user: _currentUser,
            workspace: _firmWorkspace,
            onInviteLawyer: _inviteLawyerToFirm,
            onUpdateMemberRoles: _updateFirmMemberRoles,
            onSwitchToClient: _switchToClient,
            onSwitchToLawyer: _currentUser.lawyerStatus == LawyerStatus.approved
                ? _switchToLawyer
                : null,
            onLogout: _handleLogout,
            onDeleteAccount: _handleDeleteAccount,
          )
        : _isLawyerMode
        ? LawyerNavigation(
            user: _currentUser,
            workspace: _firmWorkspace,
            onRefreshFirmWorkspace: _refreshFirmWorkspace,
            onSwitchToFirm: _switchToFirm,
            onSwitchToClient: _switchToClient,
            onLogout: _handleLogout,
            onDeleteAccount: _handleDeleteAccount,
            onEditProfile: _handleProfileEdit,
          )
        : MainNavigation(
            user: _currentUser,
            lawyerVerification: _lawyerVerification,
            lawFirmVerification: _lawFirmVerification,
            onSwitchToLawyer: _switchToLawyer,
            onSwitchToFirm: _firmWorkspace?.fromSupabase == true
                ? _switchToFirm
                : null,
            onVerificationSubmitted: _handleVerificationSubmitted,
            onRefreshLawyerVerification: _refreshLawyerVerification,
            onLawFirmVerificationSubmitted: _handleLawFirmVerificationSubmitted,
            onRefreshLawFirmVerification: _refreshLawFirmVerification,
            onLogout: _handleLogout,
            onDeleteAccount: _handleDeleteAccount,
            onEditProfile: _handleProfileEdit,
          );
  }
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(child: CircularProgressIndicator(color: colors.primary)),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.onRetry, required this.onLogout});

  final Future<void> Function() onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 56,
                color: colors.textSecondary,
              ),
              const SizedBox(height: 20),
              Text(
                'Não foi possível carregar sua conta',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Verifique sua conexão com a internet e tente novamente.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onLogout,
                child: const Text('Sair da conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final UserProfile user;
  final LawyerVerification? lawyerVerification;
  final LawFirmVerification? lawFirmVerification;
  final VoidCallback onSwitchToLawyer;
  final VoidCallback? onSwitchToFirm;
  final ValueChanged<LawyerVerification> onVerificationSubmitted;
  final Future<void> Function() onRefreshLawyerVerification;
  final ValueChanged<LawFirmVerification> onLawFirmVerificationSubmitted;
  final Future<void> Function() onRefreshLawFirmVerification;
  final VoidCallback onLogout;
  final Future<void> Function() onDeleteAccount;
  final ProfileEditSubmit onEditProfile;

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
    required this.onDeleteAccount,
    required this.onEditProfile,
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
        onDeleteAccount: widget.onDeleteAccount,
        onEditProfile: widget.onEditProfile,
      ),
    ];

    return Scaffold(
      body: JuriiFadeThroughSwitcher(
        child: KeyedSubtree(
          key: ValueKey('client_page_$currentIndex'),
          child: pages[currentIndex],
        ),
      ),
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
    required this.onDeleteAccount,
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
  final Future<void> Function() onDeleteAccount;

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
        onDeleteAccount: widget.onDeleteAccount,
      ),
    ];

    return Scaffold(
      body: JuriiFadeThroughSwitcher(
        child: KeyedSubtree(
          key: ValueKey('firm_page_$currentIndex'),
          child: pages[currentIndex],
        ),
      ),
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
  final Future<void> Function() onDeleteAccount;
  final ProfileEditSubmit onEditProfile;

  const LawyerNavigation({
    super.key,
    required this.user,
    required this.workspace,
    required this.onRefreshFirmWorkspace,
    required this.onSwitchToFirm,
    required this.onSwitchToClient,
    required this.onLogout,
    required this.onDeleteAccount,
    required this.onEditProfile,
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
        onDeleteAccount: widget.onDeleteAccount,
        onEditProfile: widget.onEditProfile,
      ),
    ];

    return Scaffold(
      body: JuriiFadeThroughSwitcher(
        child: KeyedSubtree(
          key: ValueKey('lawyer_page_$currentIndex'),
          child: pages[currentIndex],
        ),
      ),
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
