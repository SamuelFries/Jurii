import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/cases_screen.dart';
import 'screens/profile_screen.dart';

import 'theme/app_theme.dart';
import 'widgets/jurii_bottom_nav.dart';

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
      home: const MainNavigation(),
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
