import 'package:flutter/material.dart';

import 'package:jurii/widgets/categories_section.dart';
import 'package:jurii/widgets/offices_section.dart';

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
              const Text(
                'Como podemos ajudar hoje?',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
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

              OfficesSection(),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
