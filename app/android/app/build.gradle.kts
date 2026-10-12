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
        // Android 8.0: required by valhalla-mobile (offline routing); above
        // MapLibre's, flutter_secure_storage's and the Car App Library's (J4).
        minSdk = 26
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

dependencies {
    // Offline routing on the region's Valhalla graph (MIT). Bundles Valhalla
    // 3.9.0, matching the graphs built by pipeline/ (Valhalla 3.9.x).
    implementation("io.github.rallista:valhalla-mobile:0.6.1")
    implementation("io.github.rallista:valhalla-models:0.5.2")
    implementation("io.github.rallista:valhalla-models-config:0.5.2")
    // JSON <-> valhalla-mobile models (the library only exposes typed routes).
    // Same version as the library's own runtime dependency.
    implementation("com.squareup.moshi:moshi-kotlin:1.15.1")
}
