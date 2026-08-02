/// Razões de denúncia aceitas pelo servidor (whitelist da RPC
/// report_conversation). O valor do banco nunca vem de texto livre.
enum ReportReason {
  abusiveContent('conteudo_abusivo', 'Conteúdo abusivo ou ofensivo'),
  scamOrFraud('golpe_ou_fraude', 'Golpe ou fraude'),
  fakeIdentity('falsa_identidade', 'Perfil falso ou identidade falsa'),
  spam('spam', 'Spam ou propaganda'),
  other('outro', 'Outro');

  const ReportReason(this.databaseValue, this.label);

  final String databaseValue;
  final String label;
}
