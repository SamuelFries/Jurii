import 'package:flutter/material.dart';
import '../widgets/profile_header_card.dart';
import '../widgets/profile_menu_section.dart';
import '../widgets/profile_menu_item.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: substituir por dados vindos da API/banco
    const userName = 'João Silva';
    const userEmail = 'joao.silva@email.com';
    const userInitials = 'JS';
    const userMemberSince = 'Cliente desde Junho de 2026';

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Perfil',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A1C3B),
                ),
              ),
              const Text(
                'Gerencie sua conta e acompanhe suas informações.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),

              const SizedBox(height: 24),

              ProfileHeaderCard(
                name: userName,
                email: userEmail,
                initials: userInitials,
                memberSince: userMemberSince,
                onEditTap: () {},
              ),

              const SizedBox(height: 32),

              ProfileMenuSection(
                title: 'MINHA CONTA',
                items: [
                  ProfileMenuItem(
                    icon: Icons.person_outline,
                    iconColor: const Color(0xFF6B7EAA),
                    label: 'Dados Pessoais',
                    subtitle: 'Atualize suas informações',
                  ),
                  ProfileMenuItem(
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFFE07B3A),
                    label: 'Segurança',
                    subtitle: 'Senha e configurações de acesso',
                  ),
                  ProfileMenuItem(
                    icon: Icons.description_outlined,
                    iconColor: const Color(0xFF6B7EAA),
                    label: 'Meus Documentos',
                    subtitle: 'Visualize documentos enviados',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              ProfileMenuSection(
                title: 'ATENDIMENTO',
                items: [
                  ProfileMenuItem(
                    icon: Icons.chat_bubble_outline,
                    iconColor: const Color(0xFF6B7EAA),
                    label: 'Conversas',
                    subtitle: 'Acesse suas conversas com escritórios',
                  ),
                  ProfileMenuItem(
                    icon: Icons.folder_outlined,
                    iconColor: const Color(0xFFE0A800),
                    label: 'Meus Casos',
                    subtitle: 'Acompanhe seus atendimentos',
                  ),
                  ProfileMenuItem(
                    icon: Icons.calendar_month_outlined,
                    iconColor: const Color(0xFF6B7EAA),
                    label: 'Reuniões',
                    subtitle: 'Visualize reuniões agendadas',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              ProfileMenuSection(
                title: 'PLATAFORMA',
                items: [
                  ProfileMenuItem(
                    icon: Icons.help_outline,
                    iconColor: const Color(0xFFE05C5C),
                    label: 'Central de Ajuda',
                  ),
                  ProfileMenuItem(
                    icon: Icons.phone_outlined,
                    iconColor: const Color(0xFFE05C5C),
                    label: 'Suporte',
                  ),
                  ProfileMenuItem(
                    icon: Icons.article_outlined,
                    iconColor: const Color(0xFFE0A800),
                    label: 'Termos de Uso',
                  ),
                  ProfileMenuItem(
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFFE0A800),
                    label: 'Política de Privacidade',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.logout, color: Color(0xFFE05C5C)),
                  label: const Text(
                    'Sair da Conta',
                    style: TextStyle(
                      color: Color(0xFFE05C5C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const Center(
                child: Text(
                  'Jurii · Versão 1.0.0',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}