/// Regras puras do formulário de cadastro do escritório.
///
/// Ficam fora da tela para poderem ser exercitadas sem pintar widget nenhum —
/// e porque "o que conta como alteração" e "o que é um site válido" são
/// decisões, não desenho.
library;

/// Normaliza o endereço do site antes de gravar.
///
/// Quem digita "weber.com.br" está certo, mas o valor sem esquema não abre
/// quando o app tenta lançar a URL: vira busca no navegador, ou nada. Como o
/// campo aceita texto livre, a correção acontece aqui em vez de virar uma
/// mensagem de erro pedindo que a pessoa escreva "https://".
String? normalizeWebsiteUrl(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  return 'https://$value';
}

/// Estado do formulário, para decidir se há o que salvar.
class FirmProfileDraft {
  const FirmProfileDraft({
    required this.name,
    required this.phone,
    required this.email,
    required this.websiteUrl,
    required this.address,
    required this.cep,
    required this.primaryArea,
    required this.practiceAreas,
    this.description = '',
    this.hasNewLogo = false,
    this.removeLogo = false,
  });

  final String name;
  final String phone;
  final String email;
  final String websiteUrl;
  final String address;
  final String cep;
  final String primaryArea;
  final List<String> practiceAreas;

  /// Apresentação pública (a "bio" do escritório). Vive no mesmo formulário
  /// dos dados desde que os dois itens de menu viraram um lápis só.
  final String description;
  final bool hasNewLogo;
  final bool removeLogo;

  /// Recorte imutável com outra apresentação — usado quando ela é gravada por
  /// uma RPC separada da dos dados: salva a apresentação, o retrato avança só
  /// nela, e uma falha nos dados logo depois não volta a botão mentindo que a
  /// apresentação ainda está pendente.
  FirmProfileDraft withDescription(String value) => FirmProfileDraft(
    name: name,
    phone: phone,
    email: email,
    websiteUrl: websiteUrl,
    address: address,
    cep: cep,
    primaryArea: primaryArea,
    practiceAreas: practiceAreas,
    description: value,
    hasNewLogo: hasNewLogo,
    removeLogo: removeLogo,
  );

  /// `true` quando nada mudou em relação a [original].
  ///
  /// Serve para desligar o botão de salvar: um "Salvar" sempre ativo convida a
  /// gravar sem querer, e cada gravação aqui reescreve o cartão que o cliente
  /// vê na descoberta.
  bool matches(FirmProfileDraft original) {
    return name.trim() == original.name.trim() &&
        _digits(phone) == _digits(original.phone) &&
        email.trim().toLowerCase() == original.email.trim().toLowerCase() &&
        normalizeWebsiteUrl(websiteUrl) ==
            normalizeWebsiteUrl(original.websiteUrl) &&
        address.trim() == original.address.trim() &&
        _digits(cep) == _digits(original.cep) &&
        primaryArea == original.primaryArea &&
        _sameAreas(practiceAreas, original.practiceAreas) &&
        description.trim() == original.description.trim() &&
        !hasNewLogo &&
        !removeLogo;
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  static bool _sameAreas(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final ordenadoA = [...a]..sort();
    final ordenadoB = [...b]..sort();
    for (var i = 0; i < ordenadoA.length; i++) {
      if (ordenadoA[i] != ordenadoB[i]) return false;
    }
    return true;
  }
}
