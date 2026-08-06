class LawFirm {
  final String id;
  final String name;
  final String initials;
  final double rating;
  final String distance;
  final String specialty;
  final List<String> practiceAreas;
  final int reviews;
  final String avatarType;
  final String? avatarUrl;
  final String? description;
  final String? phone;
  final String? email;
  final String? websiteUrl;
  final String? address;

  /// Oito dígitos, sem máscara — é o que o formulário de edição reenvia e o
  /// que gera as coordenadas usadas na distância da descoberta.
  final String? cep;

  /// Posição patrocinada ativa na descoberta (destaque pago/cortesia).
  /// Vem de `is_featured` no RPC de descoberta; default false para mocks e
  /// para caminhos que não expõem o campo (ex.: fallback de leitura direta).
  final bool isFeatured;

  /// Ocupou uma das (no máximo duas) VAGAS PAGAS desta lista.
  ///
  /// Diferente de [isFeatured], que só diz que há patrocínio ativo: quem paga
  /// também aparece organicamente quando as vagas já estão tomadas. O selo na
  /// tela segue [isFeatured] — quem pagou é identificado sempre. Só a MEDIÇÃO
  /// usa este campo, porque atribuir à vaga uma impressão que ela não entregou
  /// infla o número que justifica a renovação.
  final bool isSponsoredSlot;

  /// Coordenadas do escritório (derivadas do CEP no cadastro). Nulas quando o
  /// escritório ainda não informou CEP — sem elas não há distância, e o app
  /// mostra o fallback de sempre. A distância em si é calculada NO APARELHO
  /// (a posição do usuário nunca sai do device).
  final double? latitude;
  final double? longitude;

  const LawFirm({
    required this.id,
    required this.name,
    required this.initials,
    required this.rating,
    required this.distance,
    required this.specialty,
    required this.practiceAreas,
    required this.reviews,
    required this.avatarType,
    this.avatarUrl,
    this.description,
    this.phone,
    this.email,
    this.websiteUrl,
    this.address,
    this.cep,
    this.isFeatured = false,
    this.isSponsoredSlot = false,
    this.latitude,
    this.longitude,
  });

  /// Escritório montado a partir da própria verificação aprovada.
  ///
  /// Caminho de exceção: só é usado quando a linha de `law_firms` não pôde ser
  /// lida (modo demo, sem Supabase). Carrega telefone, e-mail e endereço da
  /// verificação de propósito — é o mesmo formulário do lápis que consome este
  /// objeto, e campo que chega nulo aqui abre vazio lá.
  factory LawFirm.fromApprovedVerification({
    required String id,
    required String firmName,
    required String initials,
    required String specialty,
    required List<String> practiceAreas,
    required String phone,
    required String email,
    required String address,
    String? avatarUrl,
  }) {
    String? naoVazio(String value) {
      final texto = value.trim();
      return texto.isEmpty ? null : texto;
    }

    return LawFirm(
      id: id,
      name: firmName,
      initials: initials,
      rating: 0,
      distance: '',
      specialty: specialty,
      practiceAreas: practiceAreas,
      reviews: 0,
      avatarType: 'purple',
      avatarUrl: avatarUrl,
      phone: naoVazio(phone),
      email: naoVazio(email),
      address: naoVazio(address),
    );
  }

  bool get hasCoordinates => latitude != null && longitude != null;
}
