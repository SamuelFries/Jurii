import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/cases_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lawyer_home_screen.dart';
import 'screens/lawyer_messages_screen.dart';
import 'screens/lawyer_cases_screen.dart';

import 'theme/app_theme.dart';
import 'widgets/jurii_bottom_nav.dart';

void main() {
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

  void _handleLogin() => setState(() => _isLoggedIn = true);
  void _handleLogout() => setState(() {
        _isLoggedIn = false;
        _isLawyerMode = false;
      });
  void _switchToLawyer() => setState(() => _isLawyerMode = true);
  void _switchToClient() => setState(() => _isLawyerMode = false);

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
                  onSwitchToClient: _switchToClient,
                  onLogout: _handleLogout,
                )
              : MainNavigation(
                  onSwitchToLawyer: _switchToLawyer,
                  onLogout: _handleLogout,
                ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final VoidCallback onSwitchToLawyer;
  final VoidCallback onLogout;

  const MainNavigation({
    super.key,
    required this.onSwitchToLawyer,
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
      const MessagesScreen(),
      const CasesScreen(),
      ProfileScreen(
        onSwitchToLawyer: widget.onSwitchToLawyer,
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
}

class LawyerNavigation extends StatefulWidget {
  final VoidCallback onSwitchToClient;
  final VoidCallback onLogout;

  const LawyerNavigation({
    super.key,
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
      const LawyerHomeScreen(),
      const LawyerMessagesScreen(),
      const LawyerCasesScreen(),
      ProfileScreen(
        onSwitchToClient: widget.onSwitchToClient,
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
}