import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../data/mock/mock_law_firm_verification.dart';
import '../models/law_firm_verification.dart';
import '../models/law_firm_verification_document.dart';
import '../models/law_firm_verification_status.dart';
import '../models/user_profile.dart';
import '../repositories/law_firm_verification_repository.dart';
import '../services/supabase_config.dart';
import '../theme/app_theme.dart';
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
  final lawyersCountController = TextEditingController(text: '1');
  bool showErrors = false;
  bool isSubmitting = false;
  String? errorMessage;
  late List<LawFirmVerificationDocument> documents;

  bool get formIsValid {
    return firmNameController.text.trim().length >= 3 &&
        _onlyDigits(cnpjController.text).length == 14 &&
        _isValidPhone(phoneController.text) &&
        emailController.text.trim().contains('@') &&
        addressController.text.trim().length >= 8 &&
        int.tryParse(lawyersCountController.text.trim()) != null &&
        documents.every((document) => document.uploaded);
  }

  @override
  void initState() {
    super.initState();
    documents = mockRequiredLawFirmVerificationDocuments
        .map((document) => document.copyWith())
        .toList();
  }

  @override
  void dispose() {
    firmNameController.dispose();
    cnpjController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    lawyersCountController.dispose();
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
                'Verificação\ndo Escritório',
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
                'Envie os dados da pessoa jurídica e os documentos do responsável pelo cadastro.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Dados do Escritório',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
              const SizedBox(height: 14),
              TextField(
                controller: lawyersCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  hintText: 'Quantidade de advogados',
                  errorText:
                      showErrors &&
                          int.tryParse(lawyersCountController.text.trim()) ==
                              null
                      ? 'Informe a quantidade de advogados'
                      : null,
                ),
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
                  hasError: showErrors && !documents[index].uploaded,
                  onTap: () => _markDocumentUploaded(index),
                ),
                if (index < documents.length - 1) const SizedBox(height: 14),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.officePurpleSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.officePurpleBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.officePurple),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'A análise confirma a existência do escritório e o vínculo do responsável. A OAB não é exigida para este cadastro.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppTheme.officePurpleText,
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
    required LawFirmVerificationDocument document,
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
          Icon(_iconForDocument(document.type), color: AppTheme.officePurple),
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
              lawyersCount: int.parse(lawyersCountController.text.trim()),
              documents: documents,
            )
          : LawFirmVerification(
              ownerProfileId: widget.user.id,
              firmName: firmNameController.text.trim(),
              cnpj: cnpjController.text.trim(),
              phone: phoneController.text.trim(),
              email: emailController.text.trim(),
              address: addressController.text.trim(),
              lawyersCount: int.parse(lawyersCountController.text.trim()),
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

  void _markDocumentUploaded(int index) {
    setState(() {
      documents[index] = documents[index].copyWith(uploaded: true);
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
      return 'A tabela de verificação do escritório ainda não está pronta. Rode o patch 004 no Supabase.';
    }
    if (code == 'PGRST204' || message.contains('schema cache')) {
      return 'O Supabase ainda não atualizou o schema da tabela. Recarregue o schema cache ou rode o patch 004 novamente.';
    }
    if (code == '23503' || message.contains('foreign key')) {
      return 'Seu perfil ainda não foi encontrado no banco. Saia e entre novamente antes de enviar.';
    }
    if (message.contains('row-level security') || message.contains('rls')) {
      return 'Não foi possível enviar por permissão do banco. Verifique as policies no Supabase.';
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
