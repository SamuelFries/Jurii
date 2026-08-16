#!/bin/bash
# Prova de ponta a ponta dos documentos do caso, contra o Supabase LOCAL.
#
# POR QUE ELA EXISTE ALEM DO pgTAP: as policies de storage sao consultadas
# pela API de Storage, e a API tem regras proprias que o pgTAP nao enxerga.
# Foi ela que revelou que DELETE exige SELECT no objeto, o que mantinha
# quebrados (403 silencioso) os rollbacks de upload do chat e da verificacao
# desde que nasceram.
#
# COMO RODAR:  supabase start && supabase db reset && ./provas/documentos-no-storage.sh
#
# Ela cria e APAGA os proprios usuarios (sufixo -doc@jurii.local): rodar duas
# vezes seguidas nao acumula nada, e a suite pgTAP nao herda advogado fantasma
# com OAB que colide com fixture.
set -u
API=http://127.0.0.1:54321
ANON=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
SR=sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

ok=0; falha=0
confere() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "ok   $1"; else falha=$((falha+1)); echo "FALHA $1 (esperado $3, veio $2)"; fi }

# Limpa QUALQUER resto de rodada anterior antes de comecar, e de novo ao sair.
limpa() {
  psql "$DB" -q -c "delete from auth.users where email like '%-doc@jurii.local';" 2>/dev/null
  rm -f doc.pdf
}
limpa
trap limpa EXIT

# Duas contas de verdade
CLI=$(curl -s -X POST $API/auth/v1/admin/users -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" -d '{"email":"cli-doc@jurii.local","password":"provadedocumentos1","email_confirm":true}' | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
ADV=$(curl -s -X POST $API/auth/v1/admin/users -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" -d '{"email":"adv-doc@jurii.local","password":"provadedocumentos1","email_confirm":true}' | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")

psql "$DB" -q -c "
update public.profiles set lawyer_status='approved' where id='$ADV';
insert into public.lawyer_profiles (id, oab_number, oab_state, primary_area, practice_areas, approved_at)
values ('$ADV','515151','RS','Direito Cível',array['Direito Cível'],now());
insert into public.legal_cases (id, client_id, assigned_lawyer_id, title, area, status)
values ('cd000000-0000-4000-8000-00000000000d','$CLI','$ADV','Prova de documentos','Direito Cível','open');
insert into public.case_participants (case_id, profile_id, role)
values ('cd000000-0000-4000-8000-00000000000d','$CLI','client'),
       ('cd000000-0000-4000-8000-00000000000d','$ADV','lawyer');"

TOKCLI=$(curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"email":"cli-doc@jurii.local","password":"provadedocumentos1"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
TOKADV=$(curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"email":"adv-doc@jurii.local","password":"provadedocumentos1"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

printf '%%PDF-1.4 prova de documento do caso' > doc.pdf

# 1. Advogada sobe o OBJETO na propria pasta
S=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/storage/v1/object/case-documents/$ADV/cd000000/procuracao.pdf" -H "Authorization: Bearer $TOKADV" -H "apikey: $ANON" -H "Content-Type: application/pdf" --data-binary @doc.pdf)
confere "advogada sobe objeto na propria pasta" "$S" "200"

# 2. E a LINHA
S=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/rest/v1/case_documents" -H "Authorization: Bearer $TOKADV" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"case_id\":\"cd000000-0000-4000-8000-00000000000d\",\"uploaded_by\":\"$ADV\",\"title\":\"Procuração assinada\",\"storage_path\":\"$ADV/cd000000/procuracao.pdf\",\"mime_type\":\"application/pdf\",\"file_size_bytes\":34}")
confere "e registra a linha" "$S" "201"

# 3. O CLIENTE lista e assina a URL
N=$(curl -s "$API/rest/v1/case_documents?case_id=eq.cd000000-0000-4000-8000-00000000000d&select=id" -H "Authorization: Bearer $TOKCLI" -H "apikey: $ANON" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))")
confere "cliente ve o documento na lista" "$N" "1"

URL=$(curl -s -X POST "$API/storage/v1/object/sign/case-documents/$ADV/cd000000/procuracao.pdf" -H "Authorization: Bearer $TOKCLI" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"expiresIn":300}' | python3 -c "import sys,json;print(json.load(sys.stdin).get('signedURL',''))")
[ -n "$URL" ] && confere "cliente consegue assinar a URL do documento" "sim" "sim" || confere "cliente consegue assinar a URL do documento" "nao" "sim"

CORPO=$(curl -s "$API/storage/v1$URL" | head -c 8)
confere "e a URL assinada entrega o PDF" "$CORPO" "%PDF-1.4"

# 4. INTRUSO: nem lista, nem assina
INT=$(curl -s -X POST $API/auth/v1/admin/users -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" -d '{"email":"int-doc@jurii.local","password":"provadedocumentos1","email_confirm":true}' | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
TOKINT=$(curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"email":"int-doc@jurii.local","password":"provadedocumentos1"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

N=$(curl -s "$API/rest/v1/case_documents?case_id=eq.cd000000-0000-4000-8000-00000000000d&select=id" -H "Authorization: Bearer $TOKINT" -H "apikey: $ANON" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))")
confere "intruso ve lista vazia" "$N" "0"

S=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/storage/v1/object/sign/case-documents/$ADV/cd000000/procuracao.pdf" -H "Authorization: Bearer $TOKINT" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"expiresIn":300}')
confere "intruso nao assina a URL" "$S" "400"

# 5. Pasta alheia: advogada nao escreve na pasta do cliente
S=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/storage/v1/object/case-documents/$CLI/cd000000/na-pasta-alheia.pdf" -H "Authorization: Bearer $TOKADV" -H "apikey: $ANON" -H "Content-Type: application/pdf" --data-binary @doc.pdf)
confere "escrever na pasta de OUTRA pessoa e recusado" "$S" "400"

# 6. Cliente nao apaga a linha da advogada (delete roda e leva zero)
curl -s -o /dev/null -X DELETE "$API/rest/v1/case_documents?title=eq.Procura%C3%A7%C3%A3o%20assinada" -H "Authorization: Bearer $TOKCLI" -H "apikey: $ANON"
N=$(psql "$DB" -tAc "select count(*) from public.case_documents where case_id='cd000000-0000-4000-8000-00000000000d';")
confere "cliente nao apaga a linha da advogada" "$N" "1"

# 7. A advogada apaga: linha e objeto
curl -s -o /dev/null -X DELETE "$API/rest/v1/case_documents?title=eq.Procura%C3%A7%C3%A3o%20assinada" -H "Authorization: Bearer $TOKADV" -H "apikey: $ANON"
N=$(psql "$DB" -tAc "select count(*) from public.case_documents where case_id='cd000000-0000-4000-8000-00000000000d';")
confere "a advogada apaga a propria linha" "$N" "0"

S=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$API/storage/v1/object/case-documents/$ADV/cd000000/procuracao.pdf" -H "Authorization: Bearer $TOKADV" -H "apikey: $ANON")
confere "e o proprio objeto no bucket" "$S" "200"

echo; echo "=== $ok ok, $falha falhas ==="
[ $falha -eq 0 ]
