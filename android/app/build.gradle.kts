import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Bez id("kotlin-android") — migracja do Built-in Kotlin (Flutter 3.47,
    // AGP 9). android.builtInKotlin zostaje false, dopóki wtyczki
    // (device_info_plus, flutter_tts, package_info_plus, share_plus,
    // wakelock_plus) same nakładają KGP.
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

// Release MUSI być podpisany kluczem uploadu. Wcześniej brak key.properties
// dawał po cichu „release" podpisany kluczem debug — Play go odrzuca, a w
// najgorszym razie trafia do testów pod złą sygnaturą. Teraz build release
// bez kompletnego key.properties kończy się błędem (debug działa jak dotąd).
val releaseSigningProblem: String? = when {
    !keystorePropertiesFile.exists() ->
        "Brak android/key.properties (wzór: android/key.properties.example)."
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .any { keystoreProperties.getProperty(it).isNullOrBlank() } ->
        "android/key.properties nie ma kompletu: storeFile, storePassword, keyAlias, keyPassword."
    !keystorePropertiesFile.parentFile.resolve(keystoreProperties.getProperty("storeFile")).exists() ->
        "Plik keystore z android/key.properties (storeFile) nie istnieje."
    else -> null
}
val hasReleaseKeystore = releaseSigningProblem == null

android {
    namespace = "com.startklaar.fitterwelder"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = keystorePropertiesFile.parentFile
                    .resolve(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    compileOptions {
        // flutter_local_notifications (przypomnienia o uprawnieniach spawacza)
        // wymaga desugaringu java.time — bez tego build release się nie
        // składa (README wtyczki, sekcja „Gradle setup").
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.startklaar.fitterwelder"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Google Play (od 31.08.2026): apka musi celować w Android 16 (API 36)
        // lub nowszy, inaczej nie da się jej aktualizować. compileSdk = 36 już
        // jest ustawione wyżej.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Bez klucza uploadu: brak podpisu (NIE klucz debug), a zadanie
            // verifyReleaseSigning niżej zatrzymuje build release błędem.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // R8: skracanie i optymalizacja kodu + usuwanie nieuzywanych zasobow.
            // Play Console zaleca to dla mniejszego rozmiaru i zuzycia pamieci.
            // UWAGA: R8 potrafi sie skompilowac, a wywalic w runtime (strip przez
            // refleksje) — dlatego release z R8 trzeba przetestowac na SCIEZCE
            // TESTOWEJ (na telefonie) zanim trafi na produkcje.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// Każdy build wariantu release (apk, appbundle, install) przechodzi przez
// preReleaseBuild — tam wpinamy twarde sprawdzenie klucza uploadu.
val signingProblem = releaseSigningProblem
val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        if (signingProblem != null) {
            throw GradleException(
                "Build release przerwany: $signingProblem Release nie jest podpisywany " +
                    "kluczem debug. Skopiuj key.properties i upload-keystore.jks (patrz " +
                    "android/key.properties.example) albo zbuduj wariant debug.",
            )
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyReleaseSigning)
}


dependencies {
    // Latest AndroidX core APIs for Android 15 edge-to-edge handling.
    implementation("androidx.core:core-ktx:1.17.0")
    // Desugaring dla flutter_local_notifications (patrz compileOptions).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

dependencies {
    debugImplementation("androidx.test:runner:1.6.2")
    debugImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
}
