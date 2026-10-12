# Release builds are shrunk by R8 (Flutter's default); this file is picked up
# automatically by the Flutter Gradle plugin.

# Google Play Services are excluded from the build (build.gradle.kts).
# maplibre_gl still references them from its optional GMS location engine,
# which the app never activates.
-dontwarn com.google.android.gms.**
