# Release builds are shrunk by R8 (Flutter's default); this file is picked up
# automatically by the Flutter Gradle plugin.

# valhalla-mobile ships no rules. Route requests and responses go through
# Moshi's Kotlin reflection on its models, which needs their names, members
# and Kotlin metadata intact.
-keep class com.valhalla.** { *; }
-keep class com.osrm.api.models.** { *; }
-keep class kotlin.Metadata { *; }
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,Signature,InnerClasses,EnclosingMethod

# Google Play Services are excluded from the build (build.gradle.kts), but
# maplibre_gl's GMSLocationEngine still references them. That code only runs
# with myLocationEnabled, which the app never sets.
-dontwarn com.google.android.gms.**
