import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jurii/models/case_document.dart';
import 'package:jurii/repositories/case_document_repository.dart';
import 'package:jurii/theme/app_theme.dart';
import 'package:jurii/utils/document_file_validation.dart';
import 'package:jurii/widgets/case_documents_section.dart';

/// Documentos do caso: o model, a validação e a seção da tela.
///
/// A regra que mais importa na tela é a que ela NÃO decide: remover é só de
/// quem subiu, e o botão segue o `isMine` para não oferecer o que o servidor
/// vai negar.
class _RepositorioFalso extends CaseDocumentRepository {
  _RepositorioFalso({this.documentos = const [], this.estoura = false});

  final List<CaseDocument> documentos;
  final bool estoura;

  @override
  bool get isAvailable => true;

  @override
  Future<List<CaseDocument>> fetchForCase(String caseId) async {
    if (estoura) throw Exception('offline');
    return documentos;
  }
}

CaseDocument _documento({
  String id = 'd1',
  String title = 'Procuração assinada',
  bool isMine = false,
  String? mimeType = 'application/pdf',
  int? fileSizeBytes = 120000,
}) {
  return CaseDocument(
    id: id,
    caseId: 'c1',
    uploadedBy: isMine ? 'eu' : 'outra-pessoa',
    title: title,
    storagePath: 'x/y.pdf',
    isMine: isMine,
    mimeType: mimeType,
    fileSizeBytes: fileSizeBytes,
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  );
}

Widget _tela(CaseDocumentRepository repositorio) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(
    body: SingleChildScrollView(
      child: CaseDocumentsSection(caseId: 'c1', repository: repositorio),
    ),
  ),
);

void main() {
  group('modelo', () {
    test('tamanho legível fala como gente', () {
      expect(_documento(fileSizeBytes: 340 * 1024).readableSize, '340 KB');
      expect(_documento(fileSizeBytes: 1258291).readableSize, '1,2 MB');
      expect(_documento(fileSizeBytes: 12 * 1024 * 1024).readableSize, '12 MB');
      expect(_documento(fileSizeBytes: null).readableSize, '');
      expect(_documento(fileSizeBytes: 0).readableSize, '');
    });

    test('isMine compara com quem está olhando', () {
      final row = {
        'id': 'd1',
        'case_id': 'c1',
        'uploaded_by': 'u1',
        'title': 'Contrato',
        'storage_path': 'u1/c1/contrato.pdf',
      };
      expect(
        CaseDocument.fromRow(row, currentUserId: 'u1').isMine,
        isTrue,
      );
      expect(
        CaseDocument.fromRow(row, currentUserId: 'u2').isMine,
        isFalse,
      );
      expect(
        CaseDocument.fromRow(row, currentUserId: null).isMine,
        isFalse,
      );
    });
  });

  group('validação', () {
    final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);

    test('PDF de verdade passa', () {
      final result = validateCaseDocument(
        fileName: 'procuracao.pdf',
        bytes: pdf,
        sizeBytes: pdf.length,
      );
      expect(result.isValid, isTrue);
      expect(result.mimeType, 'application/pdf');
    });

    test('executável renomeado para .pdf é recusado pelos magic bytes', () {
      final elf = Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01]);
      final result = validateCaseDocument(
        fileName: 'disfarcado.pdf',
        bytes: elf,
        sizeBytes: elf.length,
      );
      expect(result.isValid, isFalse);
    });

    test('DOCX passa (o bucket do caso aceita Word, o da verificação não)', () {
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]);
      final result = validateCaseDocument(
        fileName: 'peticao.docx',
        bytes: zip,
        sizeBytes: zip.length,
      );
      expect(result.isValid, isTrue);
    });

    test('acima de 25 MB é recusado', () {
      final result = validateCaseDocument(
        fileName: 'grande.pdf',
        bytes: pdf,
        sizeBytes: 26 * 1024 * 1024,
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('25 MB'));
    });
  });

  group('seção da tela', () {
    testWidgets('lista os documentos, e só o MEU tem botão de remover', (
      tester,
    ) async {
      await tester.pumpWidget(_tela(_RepositorioFalso(documentos: [
        _documento(id: 'd1', title: 'Procuração assinada', isMine: true),
        _documento(id: 'd2', title: 'RG e CPF', isMine: false),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('Procuração assinada'), findsOneWidget);
      expect(find.text('RG e CPF'), findsOneWidget);
      // A regra do banco é "cada um remove o que subiu": um botão de remover
      // no documento alheio seria oferecer o que o servidor nega.
      expect(find.byTooltip('Remover documento'), findsOneWidget);
    });

    testWidgets('sem documentos, o vazio explica para que a seção serve', (
      tester,
    ) async {
      await tester.pumpWidget(_tela(_RepositorioFalso()));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum documento anexado'), findsOneWidget);
      expect(find.text('Anexar'), findsOneWidget);
    });

    testWidgets('falha de rede vira erro com retry, nunca lista vazia', (
      tester,
    ) async {
      // "Você não tem documentos" quando a rede caiu seria mentira com cara
      // de estado vazio.
      await tester.pumpWidget(_tela(_RepositorioFalso(estoura: true)));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar os documentos'),
        findsOneWidget,
      );
      expect(find.text('Nenhum documento anexado'), findsNothing);
    });

    testWidgets('sem Supabase a seção some inteira', (tester) async {
      // Repositório REAL fora do demo diria isAvailable=false; aqui o
      // padrão (const CaseDocumentRepository()) responde isso nos testes.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: CaseDocumentsSection(caseId: 'c1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Documentos'), findsNothing);
      expect(find.text('Anexar'), findsNothing);
    });
  });
}
