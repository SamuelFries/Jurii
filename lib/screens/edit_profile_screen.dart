import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/profile_avatar_file.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../utils/cpf_input_formatter.dart';
import '../utils/phone_input_formatter.dart';
import '../utils/profile_avatar_validation.dart';
import '../utils/validators.dart';
import '../widgets/jurii_form_motion.dart';
import '../widgets/profile_avatar.dart';

typedef ProfileEditSubmit =
    Future<void> Function({
      required String fullName,
      required String phone,
      ProfileAvatarFile? avatar,
      required bool removeAvatar,
    });

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.onSubmit,
  });

  final UserProfile profile;
  final ProfileEditSubmit onSubmit;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  ProfileAvatarFile? _selectedAvatar;
  bool _removeAvatar = false;
  bool _isPickingAvatar = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _phoneController = TextEditingController(
      text: formatPhone(widget.profile.phone ?? ''),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_isPickingAvatar || _isSaving) return;
    setState(() {
      _isPickingAvatar = true;
      _errorMessage = null;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        withData: true,
        allowedExtensions: profileAvatarAllowedExtensions,
      );
      final file = picked?.files.single;
      if (file == null || !mounted) return;

      final validation = validateProfileAvatar(
        fileName: file.name,
        bytes: file.bytes,
        sizeBytes: file.size,
      );
      if (!validation.isValid) {
        setState(() => _errorMessage = validation.error);
        return;
      }

      setState(() {
        _selectedAvatar = ProfileAvatarFile(
          fileName: file.name,
          mimeType: validation.mimeType!,
          bytes: file.bytes!,
        );
        _removeAvatar = false;
      });
    } catch (error) {
      debugPrint('Profile avatar picker failed: $error');
      if (mounted) {
        setState(
          () => _errorMessage =
              'Não foi possível abrir a galeria. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingAvatar = false);
    }
  }

  void _markAvatarForRemoval() {
    if (_isSaving) return;
    setState(() {
      _selectedAvatar = null;
      _removeAvatar = true;
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.onSubmit(
        fullName: _nameController.text.trim(),
        phone: normalizeBrazilianPhoneDigits(_phoneController.text),
        avatar: _selectedAvatar,
        removeAvatar: _removeAvatar,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('Profile edit failed: $error');
      if (mounted) setState(() => _errorMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('phone')) return 'Confira o telefone informado.';
    if (message.contains('avatar') || message.contains('storage')) {
      return 'Não foi possível atualizar a foto. Tente outra imagem.';
    }
    return 'Não foi possível salvar o perfil. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Editar perfil'),
        backgroundColor: colors.background,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AvatarEditor(
                  profile: widget.profile,
                  selectedAvatar: _selectedAvatar,
                  removeAvatar: _removeAvatar,
                  isPicking: _isPickingAvatar,
                  onPick: _pickAvatar,
                  onRemove:
                      widget.profile.avatarUrl != null ||
                          _selectedAvatar != null
                      ? _markAvatarForRemoval
                      : null,
                ),
                const SizedBox(height: 28),
                Text(
                  'INFORMAÇÕES PESSOAIS',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('edit_profile_name'),
                  controller: _nameController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  maxLength: kMaxFullNameCharacters,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    counterText: '',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: validateFullNameField,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('edit_profile_phone'),
                  controller: _phoneController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  maxLength: maxFormattedBrazilianPhoneCharacters,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: [const PhoneInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    hintText: '(00) 00000-0000',
                    counterText: '',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: validateOptionalPhoneField,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: widget.profile.email,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    helperText: 'Vinculado ao método de acesso da conta',
                    prefixIcon: Icon(Icons.mail_outline),
                    suffixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: widget.profile.cpf == null
                      ? 'Não informado'
                      : formatCpf(widget.profile.cpf!),
                  readOnly: true,
                  enableInteractiveSelection: false,
                  decoration: const InputDecoration(
                    labelText: 'CPF',
                    helperText: 'Dado de identificação protegido',
                    prefixIcon: Icon(Icons.badge_outlined),
                    suffixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 22),
                JuriiLoadingButton(
                  key: const Key('edit_profile_save'),
                  label: 'Salvar alterações',
                  isLoading: _isSaving,
                  onPressed: _isSaving ? null : _submit,
                ),
                JuriiFormErrorBanner(message: _errorMessage),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.profile,
    required this.selectedAvatar,
    required this.removeAvatar,
    required this.isPicking,
    required this.onPick,
    required this.onRemove,
  });

  final UserProfile profile;
  final ProfileAvatarFile? selectedAvatar;
  final bool removeAvatar;
  final bool isPicking;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.jColors;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.softBorder),
        boxShadow: [
          BoxShadow(
            color: colors.softShadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.accent, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: _avatar(colors),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: IconButton(
                  key: const Key('edit_profile_avatar'),
                  tooltip: 'Escolher foto',
                  onPressed: isPicking ? null : onPick,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: const Color(0xFF10131C),
                    side: BorderSide(color: colors.card, width: 3),
                  ),
                  icon: isPicking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            selectedAvatar?.fileName ??
                (removeAvatar ? 'Foto removida' : 'Foto do perfil'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'JPG, PNG ou WEBP · até 5 MB',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          if (onRemove != null && !removeAvatar) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: onRemove,
              child: Text(
                'Remover foto',
                style: TextStyle(color: colors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar(AppColors colors) {
    final selected = selectedAvatar;
    if (selected != null) {
      return Image.memory(selected.bytes, fit: BoxFit.cover);
    }
    return ProfileAvatar(
      imageUrl: removeAvatar ? null : profile.avatarUrl,
      initials: profile.initials,
      size: 104,
      backgroundColor: colors.primary,
      foregroundColor: colors.card,
      borderRadius: BorderRadius.circular(52),
      fontSize: 30,
    );
  }
}
