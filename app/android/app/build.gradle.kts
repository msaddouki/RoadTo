plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.roadto.roadto"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.roadto.roadto"
        // Android 7.0 : requis par MapLibre et flutter_secure_storage, et seuil
        // de la Car App Library (jalon J4).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // POC : signé avec la clé de debug. Les clés de release iront dans
            // Vault (règle du plan), jamais sur un poste.
            signingConfig = signingConfigs.getByName("debug")
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

// No Google Play Services in the APK. maplibre_gl declares play-services-base
// and -location for an optional location engine (GMSLocationEngine) that only
// MapLibre's own location component uses; the app never enables it
// (myLocationEnabled stays false, see map_screen.dart) and draws its own
// position from DeviceLocation.kt.
configurations.all {
    exclude(group = "com.google.android.gms")
}
