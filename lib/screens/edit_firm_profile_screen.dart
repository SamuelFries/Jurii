import 'package:flutter/material.dart';

import '../models/law_firm.dart';
import '../models/profile_avatar_file.dart';
import '../repositories/law_firm_profile_repository.dart';
import '../repositories/professional_bio_repository.dart';
import 'package:flutter/services.dart';

import '../services/cep_service.dart';
import '../theme/app_colors.dart';
import '../utils/cep_input_formatter.dart';
import '../utils/cnpj_input_formatter.dart';
import '../utils/firm_profile_form.dart';
import '../utils/phone_input_formatter.dart';
import '../utils/profile_avatar_validation.dart';
import '../utils/safe_file_picker.dart';
import '../utils/validators.dart';
import '../widgets/practice_area_selector.dart';
import '../widgets/profile_avatar.dart';

/// Edição do cadastro do escritório — o equivalente ao "Dados Pessoais" do
/// fluxo do advogado, que até aqui era um item de menu abrindo "em breve".
///
/// Depois de aprovado, nada do cadastro podia ser corrigido: telefone trocado,
/// mudança de endereço ou erro de digitação no nome ficavam para sempre. E o
/// endereço alimenta a ordenação por distância da descoberta, então "não dá
/// para corrigir" mexia em quem o cliente encontra.
///
/// A APRESENTAÇÃO também vive aqui: "Dados do escritório" e "Apresentação"
/// eram dois itens de menu para o mesmo gesto — descrever o escritório para o
/// cliente — e ninguém sabia em qual dos dois estava o quê. Um lápis, uma
/// tela, tudo dentro.
class EditFirmProfileScreen extends StatefulWidget {
  const EditFirmProfileScreen({
    super.key,
    required this.firm,
    this.repository = const LawFirmProfileRepository(),
    this.bioRepository = const ProfessionalBioRepository(),
    this.cepService = const CepService(),
  });

  final LawFirm firm;
  final LawFirmProfileRepository repository;
  final ProfessionalBioRepository bioRepository;
  final CepService cepService;

  @override
  State<EditFirmProfileScreen> createState() => _EditFirmProfileScreenState();
}

class _EditFirmProfileScreenState extends State<EditFirmProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.firm.name);
  late final _phoneController = TextEditingController(
    text: widget.firm.phone ?? '',
  );
  late final _emailController = TextEditingController(
    text: widget.firm.email ?? '',
  );
  late final _websiteController = TextEditingController(
    text: widget.firm.websiteUrl ?? '',
  );
  late final _addressController = TextEditingController(
    text: widget.firm.address ?? '',
  );
  late final _cepController = TextEditingController(
    text: widget.firm.cep ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.firm.description ?? '',
  );

  late String _primaryArea = widget.firm.specialty;
  late List<String> _areas = [...widget.firm.practiceAreas];

  bool _showAreaError = false;
  bool _isLookingUpCep = false;

  /// CNPJ verificado, só para leitura. Nulo enquanto carrega e quando não há
  /// verificação aprovada.
  String? _cnpj;

  /// Coordenadas já resolvidas para [_cepConsultado]. A consulta ao sair do
  /// campo e a de salvar pediriam o MESMO CEP à BrasilAPI duas vezes; guardar
  /// o resultado deixa uma só.
  CepCoordinates? _coordenadasDoCep;
  String? _cepConsultado;

  /// Consulta de CEP em andamento. Tocar em "Salvar" direto do campo de CEP
  /// dispara o blur e o envio ao mesmo tempo — sem esperar a que já está em
  /// curso, os dois pediriam o mesmo CEP à BrasilAPI.
  Future<void>? _cepEmCurso;

  /// Retrato de como o cadastro estava ao abrir. É contra ele que o botão de
  /// salvar decide se há o que gravar. Não é final: a apresentação grava por
  /// RPC própria, e quando ela é salva o retrato avança só nela — assim uma
  /// falha nos dados logo depois não re-salva a apresentação no retry.
  late FirmProfileDraft _original = _draft();
  ProfileAvatarFile? _selectedLogo;
  bool _removeLogo = false;
  bool _isPickingLogo = false;
  bool _isSaving = false;
  String? _errorMessage;

  FirmProfileDraft _draft() => FirmProfileDraft(
    name: _nameController.text,
    phone: _phoneController.text,
    email: _emailController.text,
    websiteUrl: _websiteController.text,
    address: _addressController.text,
    cep: _cepController.text,
    primaryArea: _primaryArea,
    practiceAreas: _areas,
    description: _descriptionController.text,
    hasNewLogo: _selectedLogo != null,
    removeLogo: _removeLogo,
  );

  bool get _hasChanges => !_draft().matches(_original);

  /// Busca o endereço do CEP e preenche o campo. Chamado quando o campo perde
  /// o foco com oito dígitos — não a cada tecla, que seria uma chamada de rede
  /// por dígito.
  Future<void> _lookupCep() {
    final busca = _lookupCepInterno();
    _cepEmCurso = busca;
    return busca;
  }

  Future<void> _lookupCepInterno() async {
    final digits = digitsOnly(_cepController.text);
    // Foco entra e sai mais de uma vez numa edição normal; sem esta guarda,
    // cada ida e volta ao campo custaria outra consulta do MESMO CEP.
    if (digits.length != 8 || _isLookingUpCep || digits == _cepConsultado) {
      return;
    }

    setState(() => _isLookingUpCep = true);
    try {
      final resultado = await widget.cepService.lookupFull(digits);
      if (!mounted || resultado == null) return;

      setState(() {
        _cepConsultado = digits;
        _coordenadasDoCep = resultado.coordinates;
      });

      final endereco = resultado.formattedAddress;
      // Só preenche o que está VAZIO: sobrescrever um endereço já digitado
      // apagaria o número e o complemento, que o CEP não sabe.
      if (endereco.isNotEmpty && _addressController.text.trim().isEmpty) {
        setState(() => _addressController.text = endereco);
      }
    } finally {
      if (mounted) setState(() => _isLookingUpCep = false);
    }
  }

  /// Todos os campos de texto da tela, na ordem em que aparecem.
  List<TextEditingController> get _controllers => [
    _nameController,
    _phoneController,
    _emailController,
    _websiteController,
    _addressController,
    _cepController,
    _descriptionController,
  ];

  @override
  void initState() {
    super.initState();
    // Observa os controllers em vez de usar Form.onChanged: o callback do Form
    // não dispara de forma confiável em todos os caminhos de edição, e o botão
    // de salvar depende disto para saber que há o que gravar.
    for (final controller in _controllers) {
      controller.addListener(_onFieldChanged);
    }
    _carregarCnpj();
  }

  Future<void> _carregarCnpj() async {
    final cnpj = await widget.repository.fetchCnpj(widget.firm.id);
    if (!mounted) return;
    setState(() => _cnpj = cnpj);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_onFieldChanged);
    }
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _cepController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    if (_isPickingLogo || _isSaving) return;
    setState(() {
      _isPickingLogo = true;
      _errorMessage = null;
    });

    try {
      final file = await pickSingleFile(
        allowedExtensions: profileAvatarAllowedExtensions,
      );
      if (file == null || !mounted) return;

      // Tamanho ANTES de ler os bytes.
      if (file.size > maxProfileAvatarBytes) {
        setState(() => _errorMessage = 'A imagem pode ter no máximo 5 MB.');
        return;
      }

      final bytes = await readPickedBytesOrNull(file);
      if (!mounted) return;

      final validation = validateProfileAvatar(
        fileName: file.name,
        bytes: bytes,
        sizeBytes: file.size,
      );
      if (!validation.isValid) {
        setState(() => _errorMessage = validation.error);
        return;
      }

      setState(() {
        _selectedLogo = ProfileAvatarFile(
          fileName: file.name,
          mimeType: validation.mimeType!,
          bytes: bytes!,
        );
        _removeLogo = false;
      });
    } catch (error) {
      debugPrint('Firm logo picker failed: $error');
      if (mounted) {
        setState(
          () => _errorMessage =
              'Não foi possível abrir a galeria. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingLogo = false);
    }
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_areas.isEmpty) {
      setState(() {
        _showAreaError = true;
        _errorMessage = 'Escolha ao menos uma área atendida.';
      });
      return;
    }

    // Espera a consulta que o blur disparou, senão a linha abaixo não veria o
    // resultado dela e pediria o mesmo CEP de novo.
    await _cepEmCurso;
    if (!mounted) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Dois salvamentos separados porque são duas RPCs — e ambas já existem
      // em produção (estender a RPC dos dados quebraria o app na janela de
      // deploy). Cada uma só roda quando o SEU pedaço mudou: corrigir um
      // telefone não regrava a apresentação, e ajustar o texto não reescreve
      // o cadastro inteiro à toa.
      final novaApresentacao = _descriptionController.text.trim();
      final apresentacaoMudou = novaApresentacao != _original.description.trim();
      // Neutraliza a apresentação na comparação: sobra "algum DADO mudou?".
      final dadosMudaram = !_draft()
          .withDescription(_original.description)
          .matches(_original);

      // A apresentação vai PRIMEIRO: se falhar, nada foi gravado e o erro é
      // um só. Se gravar e os dados falharem adiante, o retrato avança só
      // nela — o retry salva o resto sem regravá-la.
      if (apresentacaoMudou) {
        await widget.bioRepository.saveLawFirmDescription(
          lawFirmId: widget.firm.id,
          // Vazio vira NULL para o texto padrão voltar quando o gestor limpa.
          description: novaApresentacao.isEmpty ? null : novaApresentacao,
        );
        _original = _original.withDescription(novaApresentacao);
      }

      if (!dadosMudaram) {
        // Só a apresentação mudou. Devolve a firma como sinal de "recarregue
        // o workspace" — o texto novo chega por lá.
        if (!mounted) return;
        navigator.pop(widget.firm);
        messenger.showSnackBar(
          const SnackBar(content: Text('Apresentação salva.')),
        );
        return;
      }

      final cepDigits = digitsOnly(_cepController.text);

      // Endereço mudou é o único momento em que vale gastar uma chamada de
      // geocodificação. Best-effort: sem coordenadas o cadastro grava igual,
      // só não entra na ordenação por distância.
      var latitude = widget.firm.latitude;
      var longitude = widget.firm.longitude;
      final cepMudou = cepDigits != widget.firm.cep;
      if (cepDigits.isEmpty) {
        // Coordenada órfã de um endereço que já não existe colocaria o
        // escritório na distância errada da descoberta.
        latitude = null;
        longitude = null;
      } else if (cepMudou || latitude == null) {
        // Duas razões para geocodificar, não uma:
        //
        // (a) o CEP MUDOU — a coordenada antiga passou a apontar para o lugar
        //     errado;
        // (b) o CEP é o MESMO mas não há coordenada. Em produção esse é o caso
        //     de 39 dos 40 escritórios: todos têm CEP, um só tem coordenada
        //     (as verificações antigas gravaram o CEP sem geocodificar). Sem
        //     esta segunda condição eles ficariam fora da ordenação por
        //     distância para sempre — nem salvando de novo voltariam, porque o
        //     CEP não mudou.
        //
        // MESMO caminho do preenchimento automático, de propósito: ele guarda
        // o resultado por CEP, então tocar em "Salvar" direto do campo — que
        // dispara blur e envio quase juntos, em ordem que varia — resolve numa
        // consulta só, qualquer que seja quem chegar primeiro.
        await _lookupCep();
        final coordinates = cepDigits == _cepConsultado
            ? _coordenadasDoCep
            : null;

        if (coordinates != null) {
          latitude = coordinates.latitude;
          longitude = coordinates.longitude;
        } else if (cepMudou) {
          // CEP novo e geocodificação falhou: manter a coordenada antiga
          // deixaria o escritório plotado no endereço de onde ele saiu — pior
          // que não ter distância nenhuma.
          latitude = null;
          longitude = null;
        }
        // CEP igual e a consulta falhou: fica como estava. É best-effort, e a
        // próxima gravação tenta de novo.
      }

      final updated = await widget.repository.updateProfile(
        lawFirmId: widget.firm.id,
        name: _nameController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        websiteUrl: normalizeWebsiteUrl(_websiteController.text),
        address: _addressController.text,
        cep: cepDigits.isEmpty ? null : cepDigits,
        latitude: latitude,
        longitude: longitude,
        primaryArea: _primaryArea,
        practiceAreas: _areas,
        logo: _selectedLogo,
        removeLogo: _removeLogo,
      );

      if (!mounted) return;
      navigator.pop(updated);
      messenger.showSnackBar(
        const SnackBar(content: Text('Cadastro atualizado.')),
      );
    } catch (error) {
      debugPrint('Firm profile update failed: $error');
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('not allowed')) {
      return 'Você não tem permissão para editar este escritório.';
    }
    if (message.contains('invalid phone')) return 'Confira o telefone.';
    if (message.contains('invalid email')) return 'Confira o e-mail.';
    if (message.contains('invalid cep')) return 'Confira o CEP.';
    if (message.contains('invalid practice area')) {
      // O servidor NOMEIA a área recusada; engolir o nome deixava a pessoa
      // procurando qual das dez seria — foi exatamente o que aconteceu em uso.
      final nome = RegExp(
        r'invalid practice area: ([^,)\n"]+)',
        caseSensitive: false,
      ).firstMatch(error.toString())?.group(1)?.trim();
      return nome == null || nome.isEmpty
          ? 'Uma das áreas escolhidas não é válida.'
          : 'A área "$nome" não está mais disponível. Escolha outra.';
    }
    if (message.contains('avatar')) {
      return 'Não foi possível atualizar o logo. Tente outra imagem.';
    }
    return 'Não foi possível salvar. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return PopScope(
      // Sair com alteração pendente perde tudo em silêncio — e este formulário
      // tem sete campos mais a apresentação, então costuma ser bastante coisa.
      canPop: !_hasChanges || _isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmarDescarte();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          title: const Text('Dados do escritório'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _logo(colors)),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome do escritório',
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Informe o nome do escritório'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Só leitura: o CNPJ é o dado VERIFICADO do escritório, e
                  // mudá-lo seria mudar de empresa — não é correção de
                  // cadastro, é nova verificação. Mostrar travado explica isso
                  // melhor do que simplesmente não ter o campo, que pareceria
                  // esquecimento.
                  TextFormField(
                    key: const Key('firm_cnpj_field'),
                    enabled: false,
                    readOnly: true,
                    controller: TextEditingController(
                      text: _cnpj == null ? '' : formatCnpj(_cnpj!),
                    ),
                    decoration: InputDecoration(
                      labelText: 'CNPJ',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      suffixIcon: Icon(Icons.lock_outline, color: colors.muted),
                      helperText:
                          'Verificado. Para corrigi-lo é preciso uma nova '
                          'verificação do escritório.',
                      hintText: _cnpj == null ? 'Carregando…' : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [PhoneInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: validateOptionalPhoneField,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail de contato',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return null;
                      return isValidEmail(email)
                          ? null
                          : 'Informe um e-mail válido';
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _websiteController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Site',
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Endereço',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Focus(
                    // Busca ao SAIR do campo, e não a cada tecla: uma chamada de
                    // rede por dígito seriam oito para digitar um CEP.
                    onFocusChange: (temFoco) {
                      if (!temFoco) _lookupCep();
                    },
                    child: TextFormField(
                      controller: _cepController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        const CepInputFormatter(),
                        LengthLimitingTextInputFormatter(9),
                      ],
                      decoration: InputDecoration(
                        labelText: 'CEP',
                        prefixIcon: const Icon(
                          Icons.markunread_mailbox_outlined,
                        ),
                        helperText:
                            'Preenche o endereço e mostra a distância até o cliente',
                        suffixIcon: _isLookingUpCep
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      validator: (value) {
                        final digits = digitsOnly(value ?? '');
                        if (digits.isEmpty) return null;
                        return digits.length == 8 ? null : 'CEP tem 8 dígitos';
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'ÁREAS ATENDIDAS',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PracticeAreaSelector(
                    selectedAreas: _areas,
                    // Áreas do cadastro antigo aparecem marcadas em vez de
                    // sumirem: invisíveis, elas iam junto no salvamento e
                    // voltavam recusadas, sem a pessoa poder ver a culpada.
                    extraAreas: widget.firm.practiceAreas,
                    showError: _showAreaError,
                    selectedColor: colors.officePurple,
                    onChanged: (selected) => setState(() {
                      _areas = selected;
                      if (selected.isNotEmpty) _showAreaError = false;
                      // A principal precisa continuar entre as escolhidas: sem
                      // isto, desmarcar a área principal deixaria o escritório
                      // com uma especialidade que ele já não atende.
                      if (!selected.contains(_primaryArea)) {
                        _primaryArea = selected.isEmpty ? '' : selected.first;
                      }
                    }),
                  ),

                  if (_areas.length > 1) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _areas.contains(_primaryArea)
                          ? _primaryArea
                          : _areas.first,
                      decoration: const InputDecoration(
                        labelText: 'Área principal',
                        prefixIcon: Icon(Icons.star_outline),
                        helperText: 'É ela que aparece no cartão do escritório',
                      ),
                      items: [
                        for (final area in _areas)
                          DropdownMenuItem(value: area, child: Text(area)),
                      ],
                      onChanged: (value) =>
                          setState(() => _primaryArea = value ?? _primaryArea),
                    ),
                  ],

                  const SizedBox(height: 24),
                  Text(
                    'APRESENTAÇÃO',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Morava numa tela própria ("Apresentação" no menu), mas era
                  // o mesmo gesto desta: descrever o escritório para o
                  // cliente. Dois lugares para isso = ninguém sabe onde está
                  // o quê. Um lápis, uma tela, tudo dentro.
                  TextFormField(
                    key: const Key('firm_description_field'),
                    controller: _descriptionController,
                    maxLines: 6,
                    minLines: 4,
                    maxLength: ProfessionalBioRepository.maxLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'Ex.: Banca de família e sucessões em Porto Alegre, '
                          'com atendimento presencial e online.',
                      helperText:
                          'É o texto que o cliente lê no perfil do escritório. '
                          'Vazio, mostramos uma descrição genérica.',
                      helperMaxLines: 2,
                      alignLabelWithHint: true,
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.dangerSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.dangerBorder),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: colors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      // Desligado sem alterações: um "Salvar" sempre ativo
                      // convida a gravar sem querer, e cada gravação reescreve o
                      // cartão que o cliente vê na descoberta.
                      onPressed: _isSaving || !_hasChanges ? null : _submit,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Salvar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarDescarte() async {
    final descartar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text('O que você mudou nesta tela não foi salvo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (descartar == true && mounted) Navigator.of(context).pop();
  }

  Widget _logo(AppColors colors) {
    final selected = _selectedLogo;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox.square(
            dimension: 104,
            child: selected != null
                ? Image.memory(selected.bytes, fit: BoxFit.cover)
                : ProfileAvatar(
                    imageUrl: _removeLogo ? null : widget.firm.avatarUrl,
                    initials: widget.firm.initials,
                    size: 104,
                    backgroundColor: colors.officePurple,
                    foregroundColor: colors.card,
                    borderRadius: BorderRadius.circular(24),
                    fontSize: 30,
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _isPickingLogo || _isSaving ? null : _pickLogo,
              icon: const Icon(Icons.photo_outlined, size: 18),
              label: Text(_isPickingLogo ? 'Abrindo...' : 'Trocar logo'),
            ),
            if (widget.firm.avatarUrl != null || selected != null) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () => setState(() {
                        _selectedLogo = null;
                        _removeLogo = true;
                        _errorMessage = null;
                      }),
                child: Text('Remover', style: TextStyle(color: colors.danger)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
