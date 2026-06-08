import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'lawyer_verification_success_screen.dart';

class LawyerVerificationFormScreen extends StatefulWidget {
  const LawyerVerificationFormScreen({super.key});

  @override
  State<LawyerVerificationFormScreen> createState() =>
      _LawyerVerificationFormScreenState();
}

class _LawyerVerificationFormScreenState
    extends State<LawyerVerificationFormScreen> {
  final oabController = TextEditingController();
  bool mostrarErros = false;

  bool documentoIdentidadeEnviado = false;
  bool carteiraOabEnviada = false;
  bool fotoProfissionalEnviada = false;

  String? selectedState;
  String? selectedArea;

  final states = const [
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO'
  ];

  final areas = const [
    'Direito Civil',
    'Direito Trabalhista',
    'Direito Previdenciário',
    'Direito Empresarial',
    'Direito Criminal',
    'Direito Tributário',
    'Direito Ambiental',
    'Direito de Família',
    'Direito Imobiliário',
    'Direito Digital',
    'Direito Internacional',
    'Direito do Consumidor',
    'Direito Administrativo',
    'Direito Eleitoral',
    'Direito Constitucional',
    'Direito Marítimo',
    'Direito Agrário',
    'Direito Desportivo',
    'Direito Médico',
    'Direito da Propriedade Intelectual',
  ];

  bool get formularioValido {
    return oabController.text.trim().isNotEmpty &&
        selectedState != null &&
        selectedArea != null &&
        documentoIdentidadeEnviado &&
        carteiraOabEnviada &&
        fotoProfissionalEnviada;
  }

  @override
  void initState() {
    super.initState();

    oabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    oabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            24,
            8,
            24,
            32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verificação\nProfissional',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.15,
                  fontFamily: 'Serif',
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Envie seus dados e documentos para validar seu perfil profissional.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                'Dados Profissionais',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: oabController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  hintText: 'Número da OAB',
                  errorText: mostrarErros && oabController.text.trim().isEmpty
                      ? ''
                      : null,
                ),
              ),

              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                value: selectedState,
                isExpanded: true,
                menuMaxHeight: 280,
                decoration: InputDecoration(
                  hintText: 'Estado da OAB',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  errorText: mostrarErros && selectedState == null
                      ? ''
                      : null,
                ),
                items: states
                    .map(
                      (state) => DropdownMenuItem(
                        value: state,
                        child: Text(state),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedState = value;
                  });
                },
              ),

              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                value: selectedArea,
                isExpanded: true,
                menuMaxHeight: 280,
                decoration: InputDecoration(
                  hintText: 'Área de atuação',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  errorText: mostrarErros && selectedArea == null
                      ? ''
                      : null,
                ),
                items: areas
                    .map(
                      (area) => DropdownMenuItem(
                        value: area,
                        child: Text(
                          area,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedArea = value;
                  });
                },
              ),

              const SizedBox(height: 32),

              const Text(
                'Documentos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              _uploadCard(
                icon: Icons.badge_outlined,
                title: 'Documento de identificação',
                subtitle: 'RG ou CNH',
                uploaded: documentoIdentidadeEnviado,
                hasError: mostrarErros && !documentoIdentidadeEnviado,
                onTap: () {
                  setState(() {
                    documentoIdentidadeEnviado = true;
                  });
                },
              ),

              const SizedBox(height: 14),

              _uploadCard(
                icon: Icons.workspace_premium_outlined,
                title: 'Carteira da OAB',
                subtitle: 'Documento oficial',
                uploaded: carteiraOabEnviada,
                hasError: mostrarErros && !carteiraOabEnviada,
                onTap: () {
                  setState(() {
                    carteiraOabEnviada = true;
                  });
                },
              ),

              const SizedBox(height: 14),

              _uploadCard(
                icon: Icons.photo_camera_outlined,
                title: 'Foto profissional',
                subtitle: 'Imagem exibida no perfil',
                uploaded: fotoProfissionalEnviada,
                hasError: mostrarErros && !fotoProfissionalEnviada,
                onTap: () {
                  setState(() {
                    fotoProfissionalEnviada = true;
                  });
                },
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF9EB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFF0E5C0),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Todos os documentos enviados são protegidos e utilizados exclusivamente para validação profissional.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (!formularioValido) {
                      setState(() {
                        mostrarErros = true;
                      });
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const LawyerVerificationSuccessScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Enviar para análise',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool uploaded,
    required bool hasError,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError ? Colors.red : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120A1C3B),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppTheme.primary,
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          SizedBox(
            width: 120,
            height: 42,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                side: BorderSide(
                  color: Colors.grey.shade300,
                ),
              ),
              onPressed: onTap,
              child: Text(
                uploaded ? 'Anexado ✓' : 'Selecionar',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}