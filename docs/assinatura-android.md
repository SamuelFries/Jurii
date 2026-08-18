# Assinatura Android de release

O release do app precisa ser assinado com uma chave REAL (a de debug serve
para rodar no aparelho, e só). Nada de chave, senha ou keystore entra no
Git: `.gitignore` (raiz) e `android/.gitignore` ignoram `key.properties`,
`*.jks`, `*.keystore` e `*.p12` em qualquer pasta. Este documento diz o que
preencher, onde, como obter o SHA-256 que o App Link (`assetlinks.json`)
precisa, e o que ainda depende de decisão humana.

## O que o build lê

`android/app/build.gradle.kts` monta a `signingConfig` de release a partir
de quatro valores, cada um buscado nesta ordem (variável de ambiente
primeiro, arquivo depois; a resolução é por valor):

| Valor | Variável de ambiente (CI) | Chave em `android/key.properties` (local) |
|---|---|---|
| caminho da keystore | `JURII_KEYSTORE_PATH` | `storeFile` |
| senha da keystore | `JURII_KEYSTORE_PASSWORD` | `storePassword` |
| alias da chave | `JURII_KEY_ALIAS` | `keyAlias` |
| senha da chave | `JURII_KEY_PASSWORD` | `keyPassword` |

Caminho da keystore: absoluto (sem `~`, que não expande) ou relativo à
pasta `android/` (vale para os dois: `storeFile` e `JURII_KEYSTORE_PATH`,
não é relativo ao diretório do shell). Modelo:
`android/key.properties.example` (copiar para `android/key.properties`).

Comportamento, decidido na configuração do Gradle (portanto em qualquer
invocação, inclusive `flutter run` e o sync da IDE):

- **Os quatro presentes**: release assinado com a keystore. Se o arquivo
  não existir no caminho, o build falha dizendo o caminho.
- **Nenhum presente**: release cai na chave de **debug**. Ao pedir um
  release (`assembleRelease`/`bundleRelease`) sai `AVISO: release do Jurii
  assinado com a chave de DEBUG` (nível QUIET, visível também sob o `-q`
  com que o Flutter chama o Gradle). `flutter run --release` e
  `flutter build apk --release` continuam funcionando em qualquer máquina.
- **Alguns presentes**: o build falha listando o que falta, em QUALQUER
  build (debug inclusive): meio caminho é erro de configuração, não
  fallback. Corrigir ou remover o `key.properties`.
- **`-PexigirAssinatura=true`** (ou `JURII_EXIGIR_ASSINATURA=true`): sem os
  quatro, o build falha. É o modo para o pipeline que gera o AAB de loja.
  Pelo Flutter: `flutter build appbundle --release -PexigirAssinatura=true`
  (`-P` é o atalho de `--android-project-arg`).

O que NÃO muda: a assinatura de debug (`assembleDebug` segue com a chave
de debug padrão do SDK) e o restante do build.

Cuidado com o fallback: o Google Play recusa AAB/APK assinado em debug,
então ele não vira loja por acidente. Mas um APK release-com-debug
distribuído por fora (testador, link direto) não aceita depois atualização
assinada com a chave real (assinatura diferente obriga desinstalar), e o
App Link não verifica. Para qualquer distribuição, use a chave real.

## Passo a passo (uma vez)

1. Gerar a keystore de upload, FORA do repositório:

   ```sh
   mkdir -p ~/chaves/jurii
   keytool -genkey -v -keystore ~/chaves/jurii/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   O keytool atual gera PKCS12, que tem UMA senha (a da keystore); no
   `key.properties`, `keyPassword` = `storePassword`. Guardar o `.jks` e a
   senha num cofre. Com Play App Signing (obrigatório, ver abaixo), perder
   a chave de upload é recuperável junto ao Google; a chave de assinatura
   do app fica com ele.

2. Criar `android/key.properties` a partir do `.example` e preencher.

3. Conferir, sem compilar: `cd android && ./gradlew :app:signingReport`.
   Na seção `Variant: release` deve aparecer `Config: release`, o `Store:`
   apontando para a sua keystore, `Alias: upload` e o `SHA-256:` dela.

4. Conferir o artefato. O AAB é assinado em formato jar, então:

   ```sh
   flutter build appbundle --release
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
   ```

   O APK de release NÃO: com minSdk 24 o AGP assina só com v2/v3, e
   `keytool -printcert -jarfile app-release.apk` responde `Not a signed
   jar file` mesmo com a assinatura certa. Para APK use o `apksigner` do
   build-tools:

   ```sh
   ~/Library/Android/sdk/build-tools/35.0.0/apksigner verify --print-certs \
     build/app/outputs/flutter-apk/app-release.apk
   ```

## SHA-256 para o assetlinks.json

O App Link (`https://app.jurii.com.br/convite/<token>` abrir o app direto)
depende de `https://app.jurii.com.br/.well-known/assetlinks.json` listar o
SHA-256 do certificado que ASSINA O APK INSTALADO NO APARELHO. O arquivo
vive no repo `jurii-webapp`, em `public/.well-known/assetlinks.json`, e
hoje tem o marcador `SUBSTITUA_PELO_SHA256_DO_CERTIFICADO_DE_ASSINATURA_DE_RELEASE`
no array `sha256_cert_fingerprints`. O array aceita vários; o formato é
`AA:BB:CC:...` (32 pares hex maiúsculos separados por dois-pontos, como o
`keytool` imprime na linha `SHA256:`).

Há três certificados diferentes, e é fácil pôr o errado:

| Certificado | Quem assina o quê | Onde ver o SHA-256 |
|---|---|---|
| **Debug** (`~/.android/debug.keystore`, gerado pelo Android SDK na primeira build; diferente em cada máquina) | os builds de desenvolvimento e o release SEM credenciais | `keytool -list -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey` |
| **Upload** (o `.jks` que você gerou) | o AAB que você envia ao Play; e o APK instalado, só se instalado por fora da loja a partir de um build local | `keytool -list -v -keystore ~/chaves/jurii/upload-keystore.jks -alias upload` |
| **Assinatura do app** (Google Play, Play App Signing) | o APK que o Play entrega aos aparelhos | Play Console > o app > Testar e lançar > Configuração > Assinatura do app (em versões anteriores do console: Configuração > Integridade do app) |

Regra: no `assetlinks.json` de produção vai o SHA-256 do certificado do
APK que o usuário instala pela loja, ou seja, o **da assinatura do app**
que o Play Console mostra. O da chave de upload NÃO verifica quem instalou
pela loja. Se o console listar mais de um certificado de assinatura do
app, coloque TODOS no array; e acrescente o de upload para cobrir builds
internos assinados localmente. Para testar App Link num build de debug,
acrescente temporariamente o SHA-256 do `debug.keystore` da máquina que
gerou o build, e tire depois.

Conferir no aparelho (Android 12+), depois de publicar o `assetlinks.json`
e instalar o build assinado com o intent-filter `autoVerify` do PR #154:
`adb shell pm get-app-links br.com.jurii.app` deve mostrar
`app.jurii.com.br: verified`.

## Play App Signing

Não é escolha: app novo no Play Console é publicado como AAB e entra no
Play App Signing obrigatoriamente. A configuração do build é a de sempre
(você assina localmente com a keystore de upload acima); o Google guarda a
chave de assinatura do app e a sua vira chave de upload, substituível. A
única decisão sua nesse ponto é deixar o Google gerar a chave de
assinatura do app (o padrão, recomendado) ou enviar uma chave própria como
chave de assinatura, o que só faz sentido se o app já existisse na loja
com ela.

## Estado do build Android nesta data (18/08/2026)

Independente da assinatura, `flutter build apk` (debug ou release) falha
hoje em `compileReleaseJavaWithJavac`: `cannot find symbol
com.mr.flutter.plugin.filepicker.FilePickerPlugin`. Causa: o projeto usa
AGP 9.0.1 (`android/settings.gradle.kts`); o `file_picker` 11.0.3 detecta
AGP >= 9 e deixa de aplicar o plugin Kotlin dele, esperando o Kotlin
embutido do AGP 9; mas `android/gradle.properties` tem
`android.builtInKotlin=false` (flag do template Flutter), então o Kotlin
do `file_picker` nunca compila. Já falhava em `main` antes da configuração
de assinatura. A configuração de assinatura foi verificada com
`./gradlew :app:signingReport`, que não depende dessa compilação.
