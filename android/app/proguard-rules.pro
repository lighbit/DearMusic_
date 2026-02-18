############################################
# Flutter core & plugin loader
############################################
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
# Jangan hilangkan registrant, biar auto-registrasi plugin gak KO
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry { *; }

############################################
# Keep R classes (hindari masalah resource)
############################################
-keep class **.R { *; }
-keepclassmembers class **.R$* { public static <fields>; }

############################################
# AndroidX WorkManager + Startup
############################################
# WorkManager (direflect dan disimpan di DB)
-keep public class androidx.work.** { *; }
-keep class * extends androidx.work.ListenableWorker
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.RxWorker
-keep class * extends androidx.work.CoroutineWorker
-keep class androidx.work.impl.background.systemjob.SystemJobService { *; }
-keep class androidx.work.impl.background.systemjob.RescheduleReceiver { *; }
# Startup (beberapa plugin pakai App Startup)
-keep class androidx.startup.** { *; }

# keep MainActivity (method channel) dan AudioService Activity/Service
-keep class com.app.dearmusic.MainActivity { *; }
-keep class com.ryanheise.audioservice.AudioServiceActivity { *; }
-keep class com.ryanheise.audioservice.AudioService { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class android.support.v4.media.** { *; }
-keep class androidx.media.** { *; }
-keep class es.antonborri.home_widget.** { *; }
-keep class com.app.dearmusic.** { *; }

############################################
# just_audio / just_audio_background / audio_service
############################################
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.just_audio_background.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.just_audio.**
-dontwarn com.ryanheise.just_audio_background.**
-dontwarn com.ryanheise.audioservice.**

############################################
# ExoPlayer / Media3 (dipakai just_audio)
# just_audio versi baru migrasi ke androidx.media3.*
############################################
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
# buat jaga-jaga kalau dependensi lama masih com.google.android.exoplayer2
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

############################################
# on_audio_query (akses MediaStore)
############################################
-keep class com.lucasjosino.on_audio_query.** { *; }
-dontwarn com.lucasjosino.on_audio_query.**

############################################
# Android media & audio effects panel (EQ)
############################################
-keep class android.media.audiofx.** { *; }

############################################
# AndroidX media compatibility (notif/kontrol media)
############################################
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**

############################################
# Kotlin stdlib (umumnya aman, tapi biar r8 gak rewel)
############################################
-dontwarn kotlin.**
-keepclassmembers class kotlin.Metadata { *; }

############################################
# FFmpegKit (JNI + kelas yang suka di-reflect)
# Log error lo nunjuk ke com.antonkarpenko.ffmpegkit.AbiDetect.getNativeCpuAbi()
# Jadi: keep seluruh paket + JANGAN obfuscate native methods.
############################################
# Namespace resmi Arthenica & fork Anton
-keep class com.arthenica.** { *; }
-keep class com.antonkarpenko.ffmpegkit.** { *; }
# Jaga semua method native di seluruh app (RegisterNatives butuh nama aslinya)
-keepclasseswithmembers,includedescriptorclasses class * {
    native <methods>;
}
# (opsional) jangan spam warning kalau ada varian yang gak kepake
-dontwarn com.arthenica.**
-dontwarn com.antonkarpenko.ffmpegkit.**

############################################
# Hilt/Assisted (aman walau gak dipakai)
############################################
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keepnames class **_AssistedFactory
# -keep class dagger.hilt.** { *; }
# -keep class * implements dagger.hilt.android.internal.managers.** { *; }

############################################
# Flutter Local Notifications (jika dipakai)
############################################
-keep class com.dexterous.flutterlocalnotifications.** { *; }

############################################
# Play Core / SplitCompat / SplitInstall
############################################
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
