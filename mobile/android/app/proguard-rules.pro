# Flutter Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Just Audio & Audio Service
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-dontwarn com.ryanheise.**

# ExoPlayer / Media3
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Hive and TypeAdapters
-keep class io.hive.** { *; }
-keep class io.hivedb.** { *; }
-dontwarn io.hivedb.**

# Play Core & Deferred Components (prevent R8 missing class warnings/errors)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# JNI & Native Libraries
-keepclasseswithmembernames class * {
    native <methods>;
}
