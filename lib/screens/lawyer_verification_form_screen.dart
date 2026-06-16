import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../data/mock/mock_documents.dart';
import '../data/mock/mock_professional_profile.dart';
import '../models/lawyer_status.dart';
import '../models/lawyer_verification.dart';
import '../models/user_profile.dart';
import '../models/verification_document.dart';
import '../repositories/lawyer_verification_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
import '../widgets/practice_area_selector.dart';
import 'lawyer_verification_success_screen.dart';

class LawyerVerificationFormScreen extends StatefulWidget {
  final UserProfile user;
  final ValueChanged<LawyerVerification>? onVerificationSubmitted;
  final LawyerVerificationRepository repository;

  const LawyerVerificationFormScreen({
    super.key,
    required this.user,
    this.onVerificationSubmitted,
    this.repository = const LawyerVerificationRepository(),
  });

  @override
  State<LawyerVerificationFormScreen> createState() =>
      _LawyerVerificationFormScreenState();
}

class _LawyerVerificationFormScreenState
    extends State<LawyerVerificationFormScreen> {
  final oabController = TextEditingController();
  bool mostrarErros = false;
  bool isSubmitting = false;
  String? errorMessage;
  String? selectedState;
  List<String> selectedAreas = const [];
  late List<VerificationDocument> documents;

  bool get formularioValido {
    return oabController.text.trim().isNotEmpty &&
        selectedState != null &&
        selectedAreas.isNotEmpty &&
        documents.every((document) => document.uploaded);
  }

  @override
  void initState() {
    super.initState();
    documents = mockRequiredVerificationDocuments
        .map((document) => document.copyWith())
        .toList();

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
      appBar: AppBar(backgroundColor: AppTheme.background, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: oabController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  hintText: 'Número da OAB',
                  errorText: mostrarErros && oabController.text.trim().isEmpty
                      ? 'Informe seu número da OAB'
                      : null,
                ),
              ),

              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                initialValue: selectedState,
                isExpanded: true,
                menuMaxHeight: 280,
                decoration: InputDecoration(
                  hintText: 'Estado da OAB',
                  errorText: mostrarErros && selectedState == null
                      ? 'Selecione o estado'
                      : null,
                ),
                items: mockBrazilianStates
                    .map(
                      (state) =>
                          DropdownMenuItem(value: state, child: Text(state)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedState = value;
                  });
                },
              ),

              const SizedBox(height: 14),

              PracticeAreaSelector(
                selectedAreas: selectedAreas,
                showError: mostrarErros,
                onChanged: (areas) => setState(() => selectedAreas = areas),
              ),

              const SizedBox(height: 32),

              const Text(
                'Documentos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 16),

              for (var index = 0; index < documents.length; index++) ...[
                _uploadCard(
                  document: documents[index],
                  hasError: mostrarErros && !documents[index].uploaded,
                  onTap: () => _markDocumentUploaded(index),
                ),
                if (index < documents.length - 1) const SizedBox(height: 14),
              ],

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.warningSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.warningBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.accent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Todos os documentos enviados são protegidos e utilizados exclusivamente para validação profissional.',
                        style: TextStyle(fontSize: 13, height: 1.5),
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
                  onPressed: isSubmitting ? null : _submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.card,
                          ),
                        )
                      : const Text('Enviar para análise'),
                ),
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadCard({
    required VerificationDocument document,
    required bool hasError,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasError ? AppTheme.danger : AppTheme.lightBlueBorder,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_iconForDocument(document.type), color: AppTheme.primary),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  document.subtitle,
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
                  color: document.uploaded
                      ? AppTheme.success
                      : AppTheme.lightBlueBorder,
                ),
              ),
              onPressed: onTap,
              child: Text(
                document.uploaded ? 'Anexado' : 'Selecionar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: document.uploaded
                      ? AppTheme.success
                      : AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _markDocumentUploaded(int index) {
    setState(() {
      documents[index] = documents[index].copyWith(uploaded: true);
    });
  }

  Future<void> _submit() async {
    if (!formularioValido) {
      setState(() {
        mostrarErros = true;
        errorMessage = null;
      });
      return;
    }

    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    try {
      final verification = SupabaseConfig.isReady
          ? await widget.repository.submitVerification(
              oabNumber: oabController.text.trim(),
              oabState: selectedState!,
              practiceArea: selectedAreas.first,
              practiceAreas: selectedAreas,
              documents: documents,
            )
          : LawyerVerification(
              userId: widget.user.id,
              oabNumber: oabController.text.trim(),
              oabState: selectedState!,
              practiceArea: selectedAreas.first,
              practiceAreas: selectedAreas,
              documents: documents,
              status: LawyerStatus.pending,
            );

      widget.onVerificationSubmitted?.call(verification);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LawyerVerificationSuccessScreen(),
        ),
      );
    } catch (error) {
      debugPrint('Lawyer verification submit failed: $error');
      if (!mounted) return;
      setState(() => errorMessage = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    final code = error is PostgrestException ? error.code : null;
    if (code == '42P01' || message.contains('does not exist')) {
      return 'A tabela de verificação profissional não foi encontrada no Supabase.';
    }
    if (code == 'PGRST204' || message.contains('schema cache')) {
      return 'O Supabase ainda não atualizou o schema da tabela. Recarregue o schema cache e tente novamente.';
    }
    if (code == '23503' || message.contains('foreign key')) {
      return 'Seu perfil ainda não foi encontrado no banco. Saia e entre novamente antes de enviar.';
    }
    if (message.contains('row-level security') || message.contains('rls')) {
      return 'Não foi possível enviar por permissão do banco. Verifique as policies no Supabase.';
    }
    if (message.contains('authenticated') || message.contains('auth')) {
      return 'Faça login novamente para enviar sua verificação.';
    }
    return 'Não foi possível enviar sua verificação. Tente novamente.';
  }

  IconData _iconForDocument(VerificationDocumentType type) {
    return switch (type) {
      VerificationDocumentType.identity => Icons.badge_outlined,
      VerificationDocumentType.oabCard => Icons.workspace_premium_outlined,
      VerificationDocumentType.professionalPhoto => Icons.photo_camera_outlined,
    };
  }
}
