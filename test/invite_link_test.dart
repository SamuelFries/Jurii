import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/utils/invite_link.dart';

void main() {
  const token = '9107236ebd165c9958272324542e7027589a27d714955dbf';

  test('monta o link canonico do webapp, e so ele', () {
    expect(buildInviteLink(token), 'https://app.jurii.com.br/convite/$token');
  });

  test('le o link canonico, com e sem query', () {
    expect(inviteTokenFromUri(Uri.parse('https://app.jurii.com.br/convite/$token')), token);
    expect(inviteTokenFromUri(Uri.parse('https://app.jurii.com.br/convite/$token?utm=x')), token);
    // Host em maiusculas e http tambem: o sistema pode entregar assim.
    expect(inviteTokenFromUri(Uri.parse('HTTP://APP.JURII.COM.BR/convite/$token')), token);
  });

  test('le o esquema proprio, sem ser um formato que se divulga', () {
    expect(inviteTokenFromUri(Uri.parse('jurii://convite/$token')), token);
  });

  test('recusa o que nao e convite: outra rota, outro host, token torto', () {
    expect(inviteTokenFromUri(Uri.parse('jurii://login-callback?code=abc')), isNull);
    expect(inviteTokenFromUri(Uri.parse('https://app.jurii.com.br/entrar')), isNull);
    expect(inviteTokenFromUri(Uri.parse('https://evil.com/convite/$token')), isNull);
    expect(inviteTokenFromUri(Uri.parse('https://app.jurii.com.br/convite/')), isNull);
    // Token curto, ou com caractere fora do hex: nem vira chamada ao servidor.
    expect(inviteTokenFromUri(Uri.parse('https://app.jurii.com.br/convite/abc')), isNull);
    expect(inviteTokenFromUri(Uri.parse('https://app.jurii.com.br/convite/${token.substring(0, 47)}Z')), isNull);
    // Path traversal disfarcado de token.
    expect(inviteTokenFromUri(Uri.parse('https://app.jurii.com.br/convite/../entrar')), isNull);
  });
}
