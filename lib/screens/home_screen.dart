import 'package:flutter/material.dart';

import 'package:jurii/models/jurii_notification.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/widgets/categories_section.dart';
import 'package:jurii/widgets/notification_bell.dart';
import 'package:jurii/widgets/offices_section.dart';
import 'package:jurii/widgets/recommended_lawyers_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Como podemos ajudar hoje?',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  NotificationBell(
                    scope: NotificationScope.client,
                    iconColor: AppTheme.accent,
                    backgroundColor: AppTheme.card,
                    borderColor: AppTheme.lightGoldBorder,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              TextField(
                decoration: InputDecoration(
                  hintText: 'Descreva seu problema jurídico',
                  prefixIcon: Icon(Icons.search),
                ),
              ),

              const SizedBox(height: 12),

              const Text('Ex.: "Quero me divorciar"'),

              SizedBox(height: 40),

              CategoriesSection(),

              SizedBox(height: 40),

              RecommendedLawyersSection(),

              SizedBox(height: 40),

              OfficesSection(),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
