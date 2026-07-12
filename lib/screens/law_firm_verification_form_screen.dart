import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../data/mock/mock_law_firm_verification.dart';
import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_document.dart';
import '../models/law_firm_verification_status.dart';
import '../models/pending_verification_upload.dart';
import '../models/user_profile.dart';
import '../repositories/law_firm_verification_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/document_file_validation.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/practice_area_selector.dart';
import 'law_firm_verification_success_screen.dart';

class LawFirmVerificationFormScreen extends StatefulWidget {
  const LawFirmVerificationFormScreen({
    super.key,
    required this.user,
    this.onVerificationSubmitted,
    this.repository = const LawFirmVerificationRepository(),
  });

  final UserProfile user;
  final ValueChanged<LawFirmVerification>? onVerificationSubmitted;
  final LawFirmVerificationRepository repository;

  @override
  State<LawFirmVerificationFormScreen> createState() =>
      _LawFirmVerificationFormScreenState();
}

class _LawFirmVerificationFormScreenState
    extends State<LawFirmVerificationFormScreen> {
  final firmNameController = TextEditingController();
  final cnpjController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final addressController = TextEditingController();
  bool showErrors = false;
  bool isSubmitting = false;
  String? errorMessage;
  List<String> selectedAreas = const [];
  late List<LawFirmVerificationDocument> documents;
  final Map<String, PendingVerificationUpload> _pickedFiles = {};

  bool get formIsValid {
    return _dataStepComplete &&
        selectedAreas.isNotEmpty &&
        documents.every((document) => document.uploaded);
  }

  bool get _dataStepComplete {
    return firmNameController.text.trim().length >= 3 &&
        _onlyDigits(cnpjController.text).length == 14 &&
        _isValidPhone(phoneController.text) &&
        emailController.text.trim().contains('@') &&
        addressController.text.trim().length >= 8;
  }

  int get _completedSteps {
    var completed = 0;
    if (firmNameController.text.trim().length >= 3) completed++;
    if (_onlyDigits(cnpjController.text).length == 14) completed++;
    if (_isValidPhone(phoneController.text)) completed++;
    if (emailController.text.trim().contains('@')) completed++;
    if (addressController.text.trim().length >= 8) completed++;
    if (selectedAreas.isNotEmpty) completed++;
    completed += documents.where((document) => document.uploaded).length;
    return completed;
  }

  int get _totalSteps => 6 + documents.length;

  @override
  void initState() {
    super.initState();
    documents = mockRequiredLawFirmVerificationDocuments
        .map((document) => document.copyWith())
        .toList();
    for (final controller in _textControllers) {
      controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers) {
      controller.removeListener(_handleTextChanged);
    }
    firmNameController.dispose();
    cnpjController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    super.dispose();
  }

  List<TextEditingController> get _textControllers => [
    firmNameController,
    cnpjController,
    phoneController,
    emailController,
    addressController,
  ];

  void _handleTextChanged() => setState(() {});

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
                'Verificação\ndo Escritório',
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
                'Envie os dados da pessoa jurídica e os documentos do responsável pelo cadastro.',
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
                title: formIsValid
                    ? 'Tudo pronto para análise'
                    : 'Complete o cadastro do escritório',
                subtitle:
                    'Dados da pessoa jurídica, áreas atendidas e documentos.',
                accentColor: colors.officePurple,
                surfaceColor: colors.officePurpleSurface,
                borderColor: colors.officePurpleBorder,
              ),
              const SizedBox(height: 32),
              JuriiFormSectionHeader(
                stepNumber: 1,
                title: 'Dados do escritório',
                isComplete: _dataStepComplete,
                accentColor: colors.officePurple,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: firmNameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Nome do escritório',
                  errorText:
                      showErrors && firmNameController.text.trim().length < 3
                      ? 'Informe o nome do escritório'
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: cnpjController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  _CnpjInputFormatter(),
                  LengthLimitingTextInputFormatter(18),
                ],
                decoration: InputDecoration(
                  hintText: 'CNPJ',
                  errorText:
                      showErrors &&
                          _onlyDigits(cnpjController.text).length != 14
                      ? 'Informe um CNPJ válido'
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  _PhoneInputFormatter(),
                  LengthLimitingTextInputFormatter(15),
                ],
                decoration: InputDecoration(
                  hintText: 'Telefone comercial',
                  errorText: showErrors && !_isValidPhone(phoneController.text)
                      ? 'Informe um telefone de contato'
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'E-mail comercial',
                  errorText:
                      showErrors && !emailController.text.trim().contains('@')
                      ? 'Informe um e-mail válido'
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: addressController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Endereço do escritório',
                  errorText:
                      showErrors && addressController.text.trim().length < 8
                      ? 'Informe o endereço do escritório'
                      : null,
                ),
              ),
              const SizedBox(height: 32),
              JuriiFormSectionHeader(
                stepNumber: 2,
                title: 'Áreas atendidas',
                isComplete: selectedAreas.isNotEmpty,
                accentColor: colors.officePurple,
              ),
              const SizedBox(height: 16),
              PracticeAreaSelector(
                selectedAreas: selectedAreas,
                showError: showErrors,
                selectedColor: colors.officePurple,
                label: 'Selecione as áreas',
                onChanged: (areas) => setState(() => selectedAreas = areas),
              ),
              const SizedBox(height: 32),
              JuriiFormSectionHeader(
                stepNumber: 3,
                title: 'Documentos',
                isComplete: documents.every((document) => document.uploaded),
                accentColor: colors.officePurple,
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < documents.length; index++) ...[
                _uploadCard(
                  document: documents[index],
                  hasError: showErrors && !documents[index].uploaded,
                  onTap: () => _pickDocument(index),
                ),
                if (index < documents.length - 1) const SizedBox(height: 14),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.officePurpleSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.officePurpleBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: colors.officePurple),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'A análise confirma a existência do escritório e o vínculo do responsável. A OAB não é exigida para este cadastro.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: colors.officePurpleText,
                        ),
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
                backgroundColor: colors.officePurple,
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
    required LawFirmVerificationDocument document,
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
          Icon(_iconForDocument(document.type), color: colors.officePurple),
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

  Future<void> _submit() async {
    if (!formIsValid) {
      setState(() {
        showErrors = true;
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
              firmName: firmNameController.text.trim(),
              cnpj: cnpjController.text.trim(),
              phone: phoneController.text.trim(),
              email: emailController.text.trim(),
              address: addressController.text.trim(),
              practiceAreas: selectedAreas,
              documents: documents,
              uploads: _pickedFiles.values.toList(),
            )
          : LawFirmVerification(
              ownerProfileId: widget.user.id,
              firmName: firmNameController.text.trim(),
              cnpj: cnpjController.text.trim(),
              phone: phoneController.text.trim(),
              email: emailController.text.trim(),
              address: addressController.text.trim(),
              practiceAreas: selectedAreas,
              documents: documents,
              status: LawFirmVerificationStatus.pending,
            );

      widget.onVerificationSubmitted?.call(verification);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LawFirmVerificationSuccessScreen(),
        ),
      );
    } catch (error) {
      debugPrint('Law firm verification submit failed: $error');
      if (!mounted) return;
      setState(() => errorMessage = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  Future<void> _pickDocument(int index) async {
    final document = documents[index];

    // Modo demo/testes (sem Supabase): sem Storage para receber o arquivo.
    if (!SupabaseConfig.isReady) {
      setState(() {
        documents[index] = document.copyWith(uploaded: true);
      });
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: verificationAllowedExtensions,
    );
    final file = picked?.files.single;
    if (file == null) return;

    final validation = validateVerificationDocument(
      fileName: file.name,
      bytes: file.bytes,
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
        fileName: file.name,
        mimeType: validation.mimeType!,
        bytes: file.bytes!,
      );
      documents[index] = document.copyWith(uploaded: true);
    });
  }

  IconData _iconForDocument(LawFirmVerificationDocumentType type) {
    return switch (type) {
      LawFirmVerificationDocumentType.cnpjRegistration =>
        Icons.apartment_outlined,
      LawFirmVerificationDocumentType.articlesOfAssociation =>
        Icons.assignment_outlined,
      LawFirmVerificationDocumentType.addressProof =>
        Icons.location_on_outlined,
      LawFirmVerificationDocumentType.ownerIdentity => Icons.badge_outlined,
    };
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  bool _isValidPhone(String value) {
    final digits = _onlyDigits(value);
    return digits.length == 10 || digits.length == 11;
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    final code = error is PostgrestException ? error.code : null;
    if (code == '42P01' || message.contains('does not exist')) {
      debugPrint('Law firm verification table missing: $message');
      return 'O cadastro de escritórios está temporariamente indisponível.';
    }
    if (code == 'PGRST204' || message.contains('schema cache')) {
      debugPrint('Law firm verification schema cache stale: $message');
      return 'O cadastro de escritórios está temporariamente indisponível. Tente novamente em instantes.';
    }
    if (message.contains('já existe uma verificação')) {
      return 'Já existe uma verificação em andamento para este escritório.';
    }
    if (code == '23503' || message.contains('foreign key')) {
      return 'Seu perfil ainda não foi encontrado. Saia e entre novamente antes de enviar.';
    }
    if (message.contains('row-level security') || message.contains('rls')) {
      debugPrint('Law firm verification RLS denied: $message');
      return 'Não foi possível enviar o cadastro. Tente novamente mais tarde.';
    }
    if (message.contains('authenticated') || message.contains('auth')) {
      return 'Faça login novamente para enviar o cadastro do escritório.';
    }
    return 'Não foi possível enviar o cadastro do escritório. Tente novamente.';
  }
}

class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 14 ? digits.substring(0, 14) : digits;
    final formattedCnpj = _formatCnpj(limitedDigits);
    return TextEditingValue(
      text: formattedCnpj,
      selection: TextSelection.collapsed(offset: formattedCnpj.length),
    );
  }

  String _formatCnpj(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index == 2 || index == 5) {
        buffer.write('.');
      } else if (index == 8) {
        buffer.write('/');
      } else if (index == 12) {
        buffer.write('-');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formattedPhone = _formatPhone(limitedDigits);
    return TextEditingValue(
      text: formattedPhone,
      selection: TextSelection.collapsed(offset: formattedPhone.length),
    );
  }

  String _formatPhone(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index == 0) {
        buffer.write('(');
      } else if (index == 2) {
        buffer.write(') ');
      } else if (index == (digits.length > 10 ? 7 : 6)) {
        buffer.write('-');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}
