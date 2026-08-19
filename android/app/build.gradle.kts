import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Assinatura de release.
//
// As credenciais NUNCA ficam no repositório. Vêm, nesta ordem, de:
//   1. variáveis de ambiente JURII_KEYSTORE_PATH, JURII_KEYSTORE_PASSWORD,
//      JURII_KEY_ALIAS, JURII_KEY_PASSWORD (CI);
//   2. android/key.properties (máquina local; está no .gitignore).
// Ver android/key.properties.example e docs/assinatura-android.md.
//
// Sem credenciais, o release cai na chave de DEBUG (com aviso), para
// `flutter run --release` e `flutter build apk --release` continuarem
// funcionando em qualquer máquina. O Google Play recusa upload assinado em
// debug, então esse fallback não chega a produção por acidente. Para o CI
// exigir a chave real: -PexigirAssinatura=true (ou JURII_EXIGIR_ASSINATURA=true).
// ---------------------------------------------------------------------------
val keystoreProperties = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) FileInputStream(arquivo).use { load(it) }
}

fun credencial(env: String, chave: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(chave)?.takeIf { it.isNotBlank() }

// Nomes com prefixo "release" de propósito: dentro de create("release") { }
// o receptor é o SigningConfig, cujas propriedades keyAlias/keyPassword
// sombreariam vals de mesmo nome (e a config nasceria com alias nulo).
val releaseKeystorePath = credencial("JURII_KEYSTORE_PATH", "storeFile")
val releaseKeystorePassword = credencial("JURII_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = credencial("JURII_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = credencial("JURII_KEY_PASSWORD", "keyPassword")

val credenciaisInformadas = listOfNotNull(
    releaseKeystorePath, releaseKeystorePassword, releaseKeyAlias, releaseKeyPassword
)
val assinaturaDeReleaseConfigurada = credenciaisInformadas.size == 4

if (credenciaisInformadas.isNotEmpty() && !assinaturaDeReleaseConfigurada) {
    val faltando = buildList {
        if (releaseKeystorePath == null) add("storeFile / JURII_KEYSTORE_PATH")
        if (releaseKeystorePassword == null) add("storePassword / JURII_KEYSTORE_PASSWORD")
        if (releaseKeyAlias == null) add("keyAlias / JURII_KEY_ALIAS")
        if (releaseKeyPassword == null) add("keyPassword / JURII_KEY_PASSWORD")
    }
    throw GradleException(
        "Assinatura de release incompleta. Faltam: ${faltando.joinToString(", ")}. " +
            "Preencha android/key.properties (ver key.properties.example) ou as variáveis de ambiente."
    )
}

// Caminho relativo resolve a partir de android/ (onde fica o key.properties),
// não de android/app: é o que a pessoa espera ao escrever o arquivo.
val releaseKeystoreFile = releaseKeystorePath?.let { caminho ->
    val f = File(caminho)
    if (f.isAbsolute) f else rootProject.file(caminho)
}

if (assinaturaDeReleaseConfigurada && releaseKeystoreFile?.exists() != true) {
    throw GradleException(
        "Keystore de release não encontrada em '${releaseKeystoreFile?.absolutePath}'. " +
            "Confira storeFile em android/key.properties (ou JURII_KEYSTORE_PATH)."
    )
}

val exigirAssinatura =
    (findProperty("exigirAssinatura")?.toString() ?: System.getenv("JURII_EXIGIR_ASSINATURA"))
        ?.equals("true", ignoreCase = true) == true

if (exigirAssinatura && !assinaturaDeReleaseConfigurada) {
    throw GradleException(
        "exigirAssinatura=true, mas as credenciais de release não foram informadas. " +
            "Defina JURII_KEYSTORE_PATH, JURII_KEYSTORE_PASSWORD, JURII_KEY_ALIAS e JURII_KEY_PASSWORD."
    )
}

// Só avisa quando o pedido é de release: em `flutter run` (debug) e no sync
// da IDE o aviso seria ruído sobre um artefato que ninguém está gerando.
// logger.quiet, e não warn: o Flutter chama o Gradle com -q, que engole WARN.
val pediuRelease = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (!assinaturaDeReleaseConfigurada && pediuRelease) {
    logger.quiet(
        "AVISO: release do Jurii assinado com a chave de DEBUG (sem android/key.properties nem " +
            "JURII_KEYSTORE_*). Serve para rodar no aparelho; NÃO serve para o Google Play. " +
            "Ver docs/assinatura-android.md."
    )
}

android {
    namespace = "br.com.jurii.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.com.jurii.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (assinaturaDeReleaseConfigurada) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Chave real quando há credenciais; debug (com aviso) quando não há.
            // O aviso e o porquê estão no bloco de assinatura no topo deste arquivo.
            signingConfig = if (assinaturaDeReleaseConfigurada) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
