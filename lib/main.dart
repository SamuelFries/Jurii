import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/cases_screen.dart';
import 'screens/profile_screen.dart';

import 'theme/app_theme.dart';
import 'widgets/jurii_bottom_nav.dart';

import 'screens/lawyer_home_screen.dart';

void main() {
  runApp(const JuriiApp());
}

class JuriiApp extends StatelessWidget {
  const JuriiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jurii',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      //home: const RegisterScreen(),
      home: const MainNavigation(),
      //home: const LoginScreen(),
      home: Scaffold(
  body: const LawyerHomeScreen(),
  bottomNavigationBar: JuriiBottomNav(
    currentIndex: 0,
    onTap: (_) {},
  ),
),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int currentIndex = 0;

  final List<Widget> pages = const [
    HomeScreen(),
    MessagesScreen(),
    CasesScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[currentIndex],
      bottomNavigationBar: JuriiBottomNav(
        currentIndex: currentIndex,
        onTap: (index) {
          setState(() {
            currentIndex = index;
          });
        },
      ),
    );
  }
}
