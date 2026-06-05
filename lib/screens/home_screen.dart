import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Jurii',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0A1C3B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFB8972A),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),

                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF1F8),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.notifications_none,
                    color: Color(0xFF0A1C3B),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            const Text(
              'Como podemos ajudar hoje?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A1C3B),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              decoration: InputDecoration(
                hintText: 'Descreva seu problema jurídico',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFFB8972A),
                ),
                filled: true,
                fillColor: const Color(0xFFF7F8FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Ex.: "Quero me divorciar"',
              style: TextStyle(
                color: Color(0xFF6B7A99),
              ),
            ),

            const SizedBox(height: 32),

            // CATEGORIAS

            const Text(
              'Categorias Populares',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A1C3B),
              ),
            ),

            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
              children: const [
                CategoryCard(
                  emoji: '👨‍👩‍👧',
                  title: 'Divórcio',
                  isGold: false,
                ),
                CategoryCard(
                  emoji: '👶',
                  title: 'Pensão\nAlimentícia',
                  isGold: true,
                ),
                CategoryCard(
                  emoji: '💼',
                  title: 'Trabalhista',
                  isGold: false,
                ),
                CategoryCard(
                  emoji: '🏠',
                  title: 'Imobiliário',
                  isGold: true,
                ),
                CategoryCard(
                  emoji: '🚗',
                  title: 'Acidente de\nTrânsito',
                  isGold: false,
                ),
                CategoryCard(
                  emoji: '🛒',
                  title: 'Direito do\nConsumidor',
                  isGold: true,
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ESCRITÓRIOS

            const Text(
              'Escritórios Recomendados',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A1C3B),
              ),
            ),

            const SizedBox(height: 16),

            const OfficeCard(
              initials: 'FA',
              officeName: 'Fries Advogados',
              rating: '4.9',
              reviews: '128',
              distance: '1,8 km',
              specialty: 'Direito Trabalhista',
              avatarColor: Color(0xFF0A1C3B),
            ),

            const SizedBox(height: 12),

            const OfficeCard(
              initials: 'SA',
              officeName: 'Silva & Associados',
              rating: '4.8',
              reviews: '94',
              distance: '2,4 km',
              specialty: 'Direito de Família',
              avatarColor: Color(0xFF1A3A6B),
            ),

            const SizedBox(height: 12),

            const OfficeCard(
              initials: 'MA',
              officeName: 'Moura Advogados',
              rating: '4.7',
              reviews: '76',
              distance: '3,1 km',
              specialty: 'Direito do Consumidor',
              avatarColor: Color(0xFFB8972A),
            ),

            const SizedBox(height: 24),

            // BANNER

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1C3B),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PRIMEIRA CONSULTA',
                    style: TextStyle(
                      color: Color(0xFFB8972A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tire suas dúvidas gratuitamente',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Saiba mais'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class CategoryCard extends StatelessWidget {
  final String emoji;
  final String title;
  final bool isGold;

  const CategoryCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.isGold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isGold
            ? const Color(0xFFFDF6E3)
            : const Color(0xFFEEF1F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGold
              ? const Color(0xFFE8D5A0)
              : const Color(0xFFC5CFE8),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0A1C3B),
            ),
          ),
        ],
      ),
    );
  }
}

class OfficeCard extends StatelessWidget {
  final String initials;
  final String officeName;
  final String rating;
  final String reviews;
  final String distance;
  final String specialty;
  final Color avatarColor;

  const OfficeCard({
    super.key,
    required this.initials,
    required this.officeName,
    required this.rating,
    required this.reviews,
    required this.distance,
    required this.specialty,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    officeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF0A1C3B),
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '⭐ $rating ($reviews) • $distance',
                    style: const TextStyle(
                      color: Color(0xFF6B7A99),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF1F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      specialty,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1A3A6B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            ElevatedButton(
              onPressed: () {},
              child: const Text('Perfil'),
            ),
          ],
        ),
      ),
    );
  }
}