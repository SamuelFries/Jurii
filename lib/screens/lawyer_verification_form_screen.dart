import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../data/brazilian_states.dart';
import '../data/verification_document_catalog.dart';
import '../models/lawyer_status.dart';
import '../models/lawyer_verification.dart';
import '../models/pending_verification_upload.dart';
import '../models/user_profile.dart';
import '../models/verification_document.dart';
import '../repositories/lawyer_verification_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/document_file_validation.dart';
import '../utils/safe_file_picker.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
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
  final Map<String, PendingVerificationUpload> _pickedFiles = {};

  bool get formularioValido {
    return oabController.text.trim().isNotEmpty &&
        selectedState != null &&
        selectedAreas.isNotEmpty &&
        documents.every((document) => document.uploaded);
  }

  int get _completedSteps {
    var completed = 0;
    if (oabController.text.trim().isNotEmpty) completed++;
    if (selectedState != null) completed++;
    if (selectedAreas.isNotEmpty) completed++;
    completed += documents.where((document) => document.uploaded).length;
    return completed;
  }

  int get _totalSteps => 3 + documents.length;

  @override
  void initState() {
    super.initState();
    documents = requiredVerificationDocuments
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
    final colors = context.jColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(backgroundColor: colors.background, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verificação\nProfissional',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  height: 1.15,
                  fontFamily: 'Serif',
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Envie seus dados e documentos para validar seu perfil profissional.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              JuriiFormProgressCard(
                completedSteps: _completedSteps,
                totalSteps: _totalSteps,
                title: formularioValido
                    ? 'Tudo pronto para análise'
                    : 'Complete sua verificação',
                subtitle:
                    'Dados profissionais, áreas de atuação e documentos obrigatórios.',
                accentColor: colors.primary,
                surfaceColor: colors.lightBlue,
                borderColor: colors.lightBlueBorder,
              ),

              const SizedBox(height: 32),

              JuriiFormSectionHeader(
                stepNumber: 1,
                title: 'Dados profissionais',
                isComplete:
                    oabController.text.trim().isNotEmpty &&
                    selectedState != null,
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
                items: brazilianStates
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

              const SizedBox(height: 32),

              JuriiFormSectionHeader(
                stepNumber: 2,
                title: 'Áreas de atuação',
                isComplete: selectedAreas.isNotEmpty,
              ),

              const SizedBox(height: 16),

              PracticeAreaSelector(
                selectedAreas: selectedAreas,
                showError: mostrarErros,
                label: 'Selecione as áreas',
                onChanged: (areas) => setState(() => selectedAreas = areas),
              ),

              const SizedBox(height: 32),

              JuriiFormSectionHeader(
                stepNumber: 3,
                title: 'Documentos',
                isComplete: documents.every((document) => document.uploaded),
              ),

              const SizedBox(height: 16),

              for (var index = 0; index < documents.length; index++) ...[
                _uploadCard(
                  document: documents[index],
                  hasError: mostrarErros && !documents[index].uploaded,
                  onTap: () => _pickDocument(index),
                ),
                if (index < documents.length - 1) const SizedBox(height: 14),
              ],

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.warningSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.warningBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: colors.accent),
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

              JuriiLoadingButton(
                label: 'Enviar para análise',
                isLoading: isSubmitting,
                onPressed: isSubmitting ? null : _submit,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),

              JuriiFormErrorBanner(message: errorMessage),
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
    final colors = context.jColors;
    final borderColor = document.uploaded
        ? colors.success
        : hasError
        ? colors.danger
        : colors.lightBlueBorder;

    return AnimatedContainer(
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.softShadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_iconForDocument(document.type), color: colors.primary),

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
                  _pickedFiles[document.id]?.fileName ?? document.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _pickedFiles.containsKey(document.id)
                        ? colors.success
                        : colors.textSecondary,
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
                      ? colors.success
                      : colors.lightBlueBorder,
                ),
              ),
              onPressed: onTap,
              child: document.uploaded
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: colors.success,
                          size: 16,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Anexado',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.success,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Selecionar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDocument(int index) async {
    final document = documents[index];

    // Modo demo/testes (sem Supabase): não há Storage para receber o arquivo,
    // então mantém o comportamento de marcar como anexado.
    if (!SupabaseConfig.isReady) {
      setState(() {
        documents[index] = document.copyWith(uploaded: true);
      });
      return;
    }

    final SafePickedFile? file;
    try {
      file = await pickSingleFile(
        allowedExtensions: verificationAllowedExtensions,
      );
    } catch (error) {
      debugPrint('Verification document picker failed: $error');
      if (!mounted) return;
      setState(() {
        errorMessage =
            'Não foi possível abrir o seletor de arquivos. '
            'Verifique as permissões do app nos Ajustes.';
      });
      return;
    }
    if (file == null) return;

    // Tamanho antes de ler: os bytes só entram na memória dentro do teto.
    if (file.size > maxVerificationFileBytes) {
      if (!mounted) return;
      setState(
        () => errorMessage = 'Cada documento pode ter no máximo 10 MB.',
      );
      return;
    }

    final bytes = await readPickedBytesOrNull(file);

    final validation = validateVerificationDocument(
      fileName: file.name,
      bytes: bytes,
      sizeBytes: file.size,
    );
    if (!mounted) return;
    if (!validation.isValid) {
      setState(() => errorMessage = validation.error);
      return;
    }

    setState(() {
      errorMessage = null;
      _pickedFiles[document.id] = PendingVerificationUpload(
        documentId: document.id,
        documentType: document.id,
        title: document.title,
        fileName: file!.name,
        mimeType: validation.mimeType!,
        bytes: bytes!,
      );
      documents[index] = document.copyWith(uploaded: true);
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
              uploads: _pickedFiles.values.toList(),
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
