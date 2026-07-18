/// Validações compartilhadas de formulário (cadastro, login, reset de senha).
library;

/// Tamanho mínimo de senha em todo o app — alinhar com a política
/// configurada no Supabase Auth (Authentication → Providers → Email).
const int kMinPasswordLength = 8;
const int kMaxFullNameCharacters = 100;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidEmail(String value) => _emailPattern.hasMatch(value.trim());

/// Remove tudo que não é dígito (máscara de CPF, telefone etc.).
String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Valida CPF pelos dígitos verificadores, rejeitando sequências repetidas
/// (000..., 111... são aritmeticamente válidas, mas não são CPFs reais).
bool isValidCpf(String value) {
  final cpf = digitsOnly(value);
  if (cpf.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;

  int checkDigit(int length) {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += int.parse(cpf[i]) * (length + 1 - i);
    }
    final remainder = (sum * 10) % 11;
    return remainder == 10 ? 0 : remainder;
  }

  return checkDigit(9) == int.parse(cpf[9]) &&
      checkDigit(10) == int.parse(cpf[10]);
}

String? validateEmailField(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Informe seu e-mail';
  if (!isValidEmail(email)) return 'Informe um e-mail válido';
  return null;
}

String? validatePasswordField(String? value) {
  if (value == null || value.isEmpty) return 'Informe sua senha';
  if (value.length < kMinPasswordLength) {
    return 'Use pelo menos $kMinPasswordLength caracteres';
  }
  return null;
}

String? validateCpfField(String? value) {
  if (!isValidCpf(value ?? '')) return 'Informe um CPF válido';
  return null;
}

String? validateOptionalPhoneField(String? value) {
  var phone = digitsOnly(value ?? '');
  if ((phone.length == 12 || phone.length == 13) && phone.startsWith('55')) {
    phone = phone.substring(2);
  }
  if (phone.isEmpty) return null;
  if (phone.length != 10 && phone.length != 11) {
    return 'Informe um telefone com DDD';
  }
  return null;
}

/// Nome completo = pelo menos dois nomes. Um nome só (o que o login social da
/// Apple costuma entregar, quando entrega) não identifica ninguém num contrato
/// ou processo.
bool isCompleteName(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.length >= 2)
      .toList();
  return parts.length >= 2;
}

String? validateFullNameField(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Informe seu nome completo';
  if (name.length > kMaxFullNameCharacters) {
    return 'Use no máximo $kMaxFullNameCharacters caracteres';
  }
  if (!isCompleteName(name)) return 'Informe nome e sobrenome';
  return null;
}
