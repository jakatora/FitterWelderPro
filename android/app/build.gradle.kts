import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()

if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.startklaar.fitterwelder"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                if (!storeFilePath.isNullOrBlank()) {
                    storeFile = keystorePropertiesFile.parentFile.resolve(storeFilePath)
                }
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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.startklaar.fitterwelder"
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
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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

flutter {
    source = "../.."
}


dependencies {
    // Latest AndroidX core APIs for Android 15 edge-to-edge handling.
    implementation("androidx.core:core-ktx:1.17.0")
    // Desugaring dla flutter_local_notifications (patrz compileOptions).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
