import 'package:flutter/material.dart';

import '../models/law_firm.dart';
import '../models/profile_avatar_file.dart';
import '../repositories/law_firm_profile_repository.dart';
import '../services/cep_service.dart';
import '../theme/app_colors.dart';
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
class EditFirmProfileScreen extends StatefulWidget {
  const EditFirmProfileScreen({
    super.key,
    required this.firm,
    this.repository = const LawFirmProfileRepository(),
    this.cepService = const CepService(),
  });

  final LawFirm firm;
  final LawFirmProfileRepository repository;
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

  late String _primaryArea = widget.firm.specialty;
  late List<String> _areas = [...widget.firm.practiceAreas];

  bool _showAreaError = false;
  ProfileAvatarFile? _selectedLogo;
  bool _removeLogo = false;
  bool _isPickingLogo = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _cepController.dispose();
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

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final cepDigits = digitsOnly(_cepController.text);

      // Endereço mudou é o único momento em que vale gastar uma chamada de
      // geocodificação. Best-effort: sem coordenadas o cadastro grava igual,
      // só não entra na ordenação por distância.
      var latitude = widget.firm.latitude;
      var longitude = widget.firm.longitude;
      if (cepDigits.length == 8 && cepDigits != widget.firm.cep) {
        final coordinates = await widget.cepService.lookup(cepDigits);
        latitude = coordinates?.latitude;
        longitude = coordinates?.longitude;
      } else if (cepDigits.isEmpty) {
        latitude = null;
        longitude = null;
      }

      final updated = await widget.repository.updateProfile(
        lawFirmId: widget.firm.id,
        name: _nameController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        websiteUrl: _websiteController.text,
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
      return 'Uma das áreas escolhidas não é válida.';
    }
    if (message.contains('avatar')) {
      return 'Não foi possível atualizar o logo. Tente outra imagem.';
    }
    return 'Não foi possível salvar. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
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
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Informe o nome do escritório'
                      : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
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

                TextFormField(
                  controller: _cepController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'CEP',
                    prefixIcon: Icon(Icons.markunread_mailbox_outlined),
                    helperText: 'Usado para mostrar a distância até você',
                  ),
                  validator: (value) {
                    final digits = digitsOnly(value ?? '');
                    if (digits.isEmpty) return null;
                    return digits.length == 8 ? null : 'CEP tem 8 dígitos';
                  },
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
                  showError: _showAreaError,
                  selectedColor: colors.officePurple,
                  onChanged: (selected) => setState(() {
                    _areas = selected;
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
                    onPressed: _isSaving ? null : _submit,
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
    );
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
