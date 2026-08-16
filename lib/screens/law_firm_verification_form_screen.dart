import 'dart:async';

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
import '../services/cep_service.dart';
import '../utils/cep_input_formatter.dart';
import '../utils/cnpj_input_formatter.dart';
import '../utils/phone_input_formatter.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';
import '../utils/document_file_validation.dart';
import '../utils/profile_avatar_validation.dart';
import '../utils/safe_file_picker.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/jurii_motion.dart';
import '../widgets/practice_area_selector.dart';
import '../services/form_draft_store.dart';
import 'law_firm_verification_success_screen.dart';

class LawFirmVerificationFormScreen extends StatefulWidget {
  const LawFirmVerificationFormScreen({
    super.key,
    required this.user,
    this.onVerificationSubmitted,
    this.repository = const LawFirmVerificationRepository(),
    this.cepService = const CepService(),
    this.draftStore = const FormDraftStore(),
  });

  final FormDraftStore draftStore;

  final UserProfile user;
  final ValueChanged<LawFirmVerification>? onVerificationSubmitted;
  final LawFirmVerificationRepository repository;

  /// Injetável para o teste exercitar o preenchimento sem ir à rede — mesmo
  /// contrato da tela de edição do cadastro.
  final CepService cepService;

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
  final addressNumberController = TextEditingController();
  final addressComplementController = TextEditingController();
  final cepController = TextEditingController();
  bool showErrors = false;
  bool isSubmitting = false;
  String? errorMessage;
  List<String> selectedAreas = const [];
  late List<LawFirmVerificationDocument> documents;
  final Map<String, PendingVerificationUpload> _pickedFiles = {};
  PendingVerificationUpload? _profilePhoto;
  bool _demoProfilePhotoSelected = false;

  /// Consulta de CEP em andamento (evita duas para o mesmo CEP quando o blur
  /// e o envio disparam quase juntos, em ordem que varia).
  Future<void>? _cepEmCurso;
  bool _consultandoCep = false;

  /// Resultado da última consulta, guardado por CEP. É daqui que saem tanto o
  /// endereço preenchido quanto as coordenadas do envio — uma consulta só.
  CepLookup? _resultadoDoCep;
  String? _cepConsultado;

  /// O número usado na última consulta — parte da chave junto com o CEP.
  String? _numeroConsultado;

  /// O CEP tem 8 dígitos e a consulta não trouxe nada. Sem isto a falha morre
  /// num `debugPrint`, que não existe em release: a pessoa fica olhando um
  /// campo que não preenche e não sabe se esperou pouco ou digitou errado.
  bool _cepNaoEncontrado = false;

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
        addressController.text.trim().length >= 8 &&
        _cepIsValid;
  }

  bool get _cepIsValid => _onlyDigits(cepController.text).length == 8;

  int get _completedSteps {
    var completed = 0;
    if (firmNameController.text.trim().length >= 3) completed++;
    if (_onlyDigits(cnpjController.text).length == 14) completed++;
    if (_isValidPhone(phoneController.text)) completed++;
    if (emailController.text.trim().contains('@')) completed++;
    if (addressController.text.trim().length >= 8) completed++;
    if (_cepIsValid) completed++;
    if (selectedAreas.isNotEmpty) completed++;
    completed += documents.where((document) => document.uploaded).length;
    return completed;
  }

  int get _totalSteps => 7 + documents.length;

  @override
  void initState() {
    super.initState();
    documents = mockRequiredLawFirmVerificationDocuments
        .map((document) => document.copyWith())
        .toList();
    for (final controller in _textControllers) {
      controller.addListener(_handleTextChanged);
    }
    unawaited(_restaurarRascunho());
  }

  /// Devolve o que a pessoa digitou antes de sair. Fotos e documentos não
  /// voltam (bytes só na memória): re-escolher custa toques, redigitar nove
  /// campos custava o formulário.
  Future<void> _restaurarRascunho() async {
    final draft = await widget.draftStore.load(
      FormDraftStore.firmVerificationKey,
    );
    if (draft == null || !mounted) return;
    setState(() {
      void devolve(TextEditingController controller, String chave) {
        final valor = draft[chave];
        if (valor is String && controller.text.trim().isEmpty) {
          controller.text = valor;
        }
      }

      devolve(firmNameController, 'nome');
      devolve(cnpjController, 'cnpj');
      devolve(phoneController, 'telefone');
      devolve(emailController, 'email');
      devolve(addressController, 'endereco');
      devolve(addressNumberController, 'numero');
      devolve(addressComplementController, 'complemento');
      devolve(cepController, 'cep');
      final areas = draft['areas'];
      if (areas is List && selectedAreas.isEmpty) {
        selectedAreas = areas.whereType<String>().toList();
      }
    });
  }

  void _salvarRascunho() {
    unawaited(
      widget.draftStore.save(FormDraftStore.firmVerificationKey, {
        'nome': firmNameController.text.trim(),
        'cnpj': cnpjController.text.trim(),
        'telefone': phoneController.text.trim(),
        'email': emailController.text.trim(),
        'endereco': addressController.text.trim(),
        'numero': addressNumberController.text.trim(),
        'complemento': addressComplementController.text.trim(),
        'cep': cepController.text.trim(),
        'areas': selectedAreas,
      }),
    );
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
    addressNumberController.dispose();
    addressComplementController.dispose();
    cepController.dispose();
    super.dispose();
  }

  List<TextEditingController> get _textControllers => [
    firmNameController,
    cnpjController,
    phoneController,
    emailController,
    addressController,
    addressNumberController,
    addressComplementController,
    cepController,
  ];

  void _handleTextChanged() {
    setState(() {});
    _salvarRascunho();
  }

  /// Busca o endereço do CEP e preenche os campos que o CEP determina.
  ///
  /// O endereço JÁ vinha nesta chamada e era jogado fora: o envio usava
  /// `CepService.lookup`, que por dentro é `lookupFull(...)?.coordinates`.
  /// Resultado: o escritório digitava à mão os ~70 caracteres de
  /// "Rua Germano Petersen Júnior, 70 - 1102, Auxiliadora, Porto Alegre - RS"
  /// enquanto o app tinha a rua, o bairro, a cidade e a UF na resposta. Agora
  /// o que sobra para digitar é o número e o complemento.
  Future<void> _lookupCep() {
    final busca = _lookupCepInterno();
    _cepEmCurso = busca;
    return busca;
  }

  Future<void> _lookupCepInterno() async {
    final digits = _onlyDigits(cepController.text);
    // Foco entra e sai mais de uma vez num preenchimento normal; sem esta
    // guarda, cada ida e volta custaria outra consulta do MESMO CEP.
    final numero = addressNumberController.text.trim();
    if (digits.length != 8 ||
        _consultandoCep ||
        (digits == _cepConsultado && numero == _numeroConsultado)) {
      return;
    }

    setState(() {
      _consultandoCep = true;
      _cepNaoEncontrado = false;
    });
    try {
      final resultado = await widget.cepService.lookupFull(
        digits,
        addressNumber: addressNumberController.text,
      );
      if (!mounted) return;

      setState(() {
        _cepConsultado = digits;
        _numeroConsultado = numero;
        _resultadoDoCep = resultado;
        _cepNaoEncontrado = resultado == null;
      });

      final endereco = resultado?.formattedAddress ?? '';
      // Só preenche o que está VAZIO: sobrescrever apagaria o número e o
      // complemento, que o CEP não sabe.
      if (endereco.isNotEmpty && addressController.text.trim().isEmpty) {
        setState(() => addressController.text = endereco);
      }
    } finally {
      if (mounted) setState(() => _consultandoCep = false);
    }
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
                key: const Key('firm_verification_name_field'),
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
                key: const Key('firm_verification_cnpj_field'),
                controller: cnpjController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  const CnpjInputFormatter(),
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
                key: const Key('firm_verification_phone_field'),
                controller: phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  const PhoneInputFormatter(),
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
                key: const Key('firm_verification_email_field'),
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
                key: const Key('firm_verification_address_field'),
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

              // O que o CEP NÃO sabe, e o que o cliente precisa para chegar.
              // Opcionais de propósito: existe "s/n", existe "Km 12", e
              // exigir faria a pessoa inventar um número para o formulário
              // deixar salvar — número inventado é pior que ausente, porque
              // parece certo.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    // O número também refina a coordenada, então sair dele
                    // dispara a consulta: sem isto, quem digita o CEP e SÓ
                    // DEPOIS o número ficaria com o centroide da rua.
                    child: Focus(
                      onFocusChange: (temFoco) {
                        if (!temFoco) _lookupCep();
                      },
                      child: TextField(
                        key: const Key('firm_verification_number_field'),
                        controller: addressNumberController,
                        keyboardType: TextInputType.streetAddress,
                        maxLength: 20,
                        decoration: const InputDecoration(
                          hintText: 'Número (ou s/n)',
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: const Key('firm_verification_complement_field'),
                      controller: addressComplementController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        hintText: 'Complemento (sala, andar…)',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Focus(
                // Busca ao SAIR do campo, e não a cada tecla: uma chamada de
                // rede por dígito seriam oito para digitar um CEP.
                onFocusChange: (temFoco) {
                  if (!temFoco) _lookupCep();
                },
                child: TextField(
                  key: const Key('firm_verification_cep_field'),
                  controller: cepController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    const CepInputFormatter(),
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: InputDecoration(
                    hintText: 'CEP do escritório',
                    helperText: _cepNaoEncontrado
                        ? 'Não encontramos esse CEP. Confira, ou preencha o '
                              'endereço à mão.'
                        : 'Preenche o endereço e mostra a distância até o cliente.',
                    helperMaxLines: 2,
                    errorText: showErrors && !_cepIsValid
                        ? 'Informe um CEP válido'
                        : null,
                    suffixIcon: _consultandoCep
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
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
                onChanged: (areas) {
                  setState(() => selectedAreas = areas);
                  _salvarRascunho();
                },
              ),
              const SizedBox(height: 32),
              JuriiFormSectionHeader(
                stepNumber: 3,
                title: 'Documentos',
                isComplete: documents.every((document) => document.uploaded),
                accentColor: colors.officePurple,
              ),
              const SizedBox(height: 16),
              _profilePhotoUploadCard(onTap: _pickProfilePhoto),
              const SizedBox(height: 14),
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

  Widget _profilePhotoUploadCard({required VoidCallback onTap}) {
    final colors = context.jColors;
    final selected = _profilePhoto != null || _demoProfilePhotoSelected;

    return AnimatedContainer(
      key: const ValueKey('law_firm_profile_photo_card'),
      duration: JuriiMotion.fast,
      curve: JuriiMotion.ease,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? colors.success : colors.lightBlueBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.softShadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.photo_camera_outlined, color: colors.officePurple),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Foto de perfil do escritório',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Opcional',
                  style: TextStyle(
                    color: colors.officePurple,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _profilePhoto?.fileName ??
                      (selected
                          ? 'Foto adicionada'
                          : 'JPG, PNG ou WEBP de até 5 MB · exibida no perfil após aprovação'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? colors.success : colors.textSecondary,
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
                  color: selected ? colors.success : colors.lightBlueBorder,
                ),
              ),
              onPressed: onTap,
              child: Text(
                selected ? 'Trocar foto' : 'Adicionar foto',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.success : colors.textPrimary,
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
      // Geocodifica o CEP para a distância na descoberta. Best-effort: sem
      // coordenadas o cadastro segue — o comprovante de endereço já cobre a
      // conferência humana.
      //
      // MESMO caminho do preenchimento automático, de propósito: ele guarda o
      // resultado por CEP, então enviar direto do campo — que dispara blur e
      // envio quase juntos, em ordem que varia — resolve numa consulta só.
      final cepDigits = _onlyDigits(cepController.text);
      await _cepEmCurso;
      if (!mounted) return;
      if (SupabaseConfig.isReady && cepDigits != _cepConsultado) {
        await _lookupCep();
        if (!mounted) return;
      }
      final coordinates = cepDigits == _cepConsultado
          ? _resultadoDoCep?.coordinates
          : null;

      final verification = SupabaseConfig.isReady
          ? await widget.repository.submitVerification(
              firmName: firmNameController.text.trim(),
              cnpj: cnpjController.text.trim(),
              phone: phoneController.text.trim(),
              email: emailController.text.trim(),
              address: addressController.text.trim(),
              addressNumber: addressNumberController.text.trim(),
              addressComplement: addressComplementController.text.trim(),
              practiceAreas: selectedAreas,
              documents: documents,
              uploads: _pickedFiles.values.toList(),
              profilePhoto: _profilePhoto,
              cep: cepDigits,
              latitude: coordinates?.latitude,
              longitude: coordinates?.longitude,
            )
          : LawFirmVerification(
              ownerProfileId: widget.user.id,
              firmName: firmNameController.text.trim(),
              cnpj: cnpjController.text.trim(),
              phone: phoneController.text.trim(),
              email: emailController.text.trim(),
              address: addressController.text.trim(),
              addressNumber: addressNumberController.text.trim(),
              addressComplement: addressComplementController.text.trim(),
              practiceAreas: selectedAreas,
              documents: documents,
              status: LawFirmVerificationStatus.pending,
            );

      // Enviado é enviado: o rascunho morre junto, senão o próximo cadastro
      // abriria pré-preenchido com o escritório anterior.
      unawaited(widget.draftStore.clear(FormDraftStore.firmVerificationKey));

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
      setState(() => errorMessage = 'Cada documento pode ter no máximo 10 MB.');
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

  Future<void> _pickProfilePhoto() async {
    if (!SupabaseConfig.isReady) {
      setState(() => _demoProfilePhotoSelected = true);
      return;
    }

    final SafePickedFile? file;
    try {
      file = await pickSingleFile(
        allowedExtensions: profileAvatarAllowedExtensions,
      );
    } catch (error) {
      debugPrint('Firm profile photo picker failed: $error');
      if (!mounted) return;
      setState(() {
        errorMessage =
            'Não foi possível abrir a galeria. '
            'Verifique as permissões do app nos Ajustes.';
      });
      return;
    }
    if (file == null) return;

    if (file.size > maxProfileAvatarBytes) {
      if (!mounted) return;
      setState(() => errorMessage = 'A foto pode ter no máximo 5 MB.');
      return;
    }

    final bytes = await readPickedBytesOrNull(file);

    final validation = validateProfileAvatar(
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
      _profilePhoto = PendingVerificationUpload(
        documentId: 'profile_photo',
        documentType: 'profile_photo',
        title: 'Foto de perfil do escritório',
        fileName: file!.name,
        mimeType: validation.mimeType!,
        bytes: bytes!,
      );
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
