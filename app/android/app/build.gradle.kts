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

    // The car library checks that icons exist: the Robolectric tests of the
    // car screens need the app's resources.
    testOptions {
        unitTests.isIncludeAndroidResources = true
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

// No Google Play Services in the APK: the app runs on phones without them
// (cross-cutting rule of the plan, checked by tool/check_no_trackers.sh).
// maplibre_gl declares play-services-location for its own location engine,
// which only starts with myLocationEnabled; the app never sets it (see
// lib/ui/map_screen.dart) and draws the position from DeviceLocation.
configurations.all {
    exclude(group = "com.google.android.gms")
}

// With resources, the unit tests package the merged assets, which the
// Flutter plugin also writes (copyFlutterAssetsDebug): order the two.
tasks.matching { it.name == "packageDebugUnitTestForUnitTest" }.configureEach {
    mustRunAfter(tasks.matching { it.name == "copyFlutterAssetsDebug" })
}

flutter {
    source = "../.."
}

dependencies {
    // Offline routing on the region's Valhalla graph (MIT). Bundles Valhalla
    // 3.9.0, matching the graphs built by pipeline/ (Valhalla 3.9.x).
    implementation("io.github.rallista:valhalla-mobile:0.6.4")
    implementation("io.github.rallista:valhalla-models:0.6.0")
    implementation("io.github.rallista:valhalla-models-config:0.6.0")
    // JSON <-> valhalla-mobile models (the library only exposes typed routes).
    // Same version as the library's own runtime dependency.
    implementation("com.squareup.moshi:moshi-kotlin:1.15.2")
    // Android Auto (car/): templates, and the map drawn on the car screen
    // with the same MapLibre build as maplibre_gl (OpenGL variant).
    implementation("androidx.car.app:app:1.7.0")
    implementation("androidx.car.app:app-projected:1.7.0")
    implementation("org.maplibre.gl:android-sdk-opengl:13.5.0")

    // Car screens tested on the JVM (Robolectric), without a head unit.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.car.app:app-testing:1.7.0")
    testImplementation("androidx.test:core:1.7.0")
}
