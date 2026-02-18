package com.app.dearmusic

import android.content.ActivityNotFoundException
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.content.Context
import android.window.OnBackInvokedDispatcher
import android.window.OnBackInvokedCallback
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {

    private val CHANNEL_AUDIO = "dearmusic/system_audio"
    private val CHANNEL_BATTERY = "dearmusic/battery"
    private val CHANNEL_SHARE = "dearmusic/share"

    private var backCallback: OnBackInvokedCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val cb = OnBackInvokedCallback {
                @Suppress("DEPRECATION")
                super.onBackPressed()
            }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT, cb
            )
            backCallback = cb
        }
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // === AUDIO ===
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_AUDIO)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openEqualizer" -> {
                        val sessionId = (call.argument<Int>("sessionId")) ?: 0
                        val intent =
                            Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL).apply {
                                putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                                putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                                putExtra(
                                    AudioEffect.EXTRA_CONTENT_TYPE,
                                    AudioEffect.CONTENT_TYPE_MUSIC
                                )
                            }
                        try {
                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent)
                                result.success(true)
                            } else result.success(false)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }

                    "openOutputSwitcher" -> {
                        val intents = mutableListOf(
                            Intent("android.settings.MEDIA_OUTPUT"),
                            Intent("android.settings.MEDIA_OUTPUT_APP"),
                            Intent("android.settings.MEDIA_OUTPUT_GROUP"),
                            Intent(Settings.ACTION_BLUETOOTH_SETTINGS),
                            Intent(Settings.ACTION_SOUND_SETTINGS),
                        )
                        var launched = false
                        for (it in intents) {
                            try {
                                if (it.resolveActivity(packageManager) != null) {
                                    startActivity(it); launched = true; break
                                }
                            } catch (_: ActivityNotFoundException) { /* skip */
                            }
                        }
                        result.success(launched)
                    }

                    else -> result.notImplemented()
                }
            }

        // === BATTERY ===
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_BATTERY)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }

                    else -> result.notImplemented()
                }
            }

        // === SHARE TO IG STORY ===
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SHARE)
            .setMethodCallHandler { call, result ->
                // AFTER: di configureFlutterEngine -> CHANNEL_SHARE.setMethodCallHandler { ... }
                when (call.method) {

                    "ig_story" -> {
                        try {
                            val bytes = call.argument<ByteArray>("pngBytes")
                            val contentUrl = call.argument<String>("contentUrl") ?: ""
                            if (bytes == null || bytes.isEmpty()) {
                                result.error("NO_IMAGE", "pngBytes empty", null); return@setMethodCallHandler
                            }
                            if (contentUrl.isEmpty()) {
                                result.error("NO_URL", "contentUrl empty", null); return@setMethodCallHandler
                            }

                            val outFile = writeToCachePng(bytes, "story_bg.png")
                            val uri = toFileUri(outFile)

                            val appId = getString(R.string.facebook_app_id)
                            val interactiveAssetUri = Uri.Builder()
                                .scheme("instagram")
                                .authority("sticker")
                                .appendPath("share")
                                .appendQueryParameter("interactive_asset_uri", contentUrl)
                                .appendQueryParameter("app_id", appId)
                                .build()

                            val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
                                setDataAndType(uri, "image/*")
                                putExtra("source_application", applicationContext.packageName)
                                putExtra("interactive_asset_uri", interactiveAssetUri.toString())
                                putExtra("content_url", contentUrl)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                setPackage("com.instagram.android")
                            }

                            grantUriPermission("com.instagram.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent)
                                result.success(true)
                            } else {
                                // fallback bukain Play Store URL biar user gak bengong
                                val ps = Intent(Intent.ACTION_VIEW, Uri.parse(contentUrl)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(ps)
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("ERR", e.message, e.stackTraceToString())
                        }
                    }

                    "wa_status" -> {
                        try {
                            val bytes = call.argument<ByteArray>("pngBytes")
                            val text = call.argument<String>("text") ?: ""
                            if (bytes == null || bytes.isEmpty()) {
                                result.error("NO_IMAGE", "pngBytes empty", null); return@setMethodCallHandler
                            }
                            val outFile = writeToCachePng(bytes, "wa_status.png")
                            val uri = toFileUri(outFile)

                            // Prioritas: WhatsApp reguler, kalau gak ada coba Business
                            val targets = listOf("com.whatsapp", "com.whatsapp.w4b")
                            var launched = false
                            for (pkg in targets) {
                                val intent = Intent(Intent.ACTION_SEND).apply {
                                    type = "image/*"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_TEXT, text)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    setPackage(pkg)
                                }
                                if (intent.resolveActivity(packageManager) != null) {
                                    grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    startActivity(intent)
                                    launched = true
                                    break
                                }
                            }
                            // kalau dua-duanya gak ada, pakai chooser umum
                            if (!launched) {
                                val chooser = Intent(Intent.ACTION_SEND).apply {
                                    type = "image/*"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_TEXT, text)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(Intent.createChooser(chooser, "Share image"))
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERR", e.message, e.stackTraceToString())
                        }
                    }

                    "save_image" -> {
                        try {
                            val bytes = call.argument<ByteArray>("pngBytes")
                            val filename = call.argument<String>("filename") ?: "DearMusic_Story.png"
                            val relativeDir = call.argument<String>("relativeDir") ?: "Pictures"

                            if (bytes == null || bytes.isEmpty()) {
                                result.error("NO_IMAGE", "pngBytes empty", null); return@setMethodCallHandler
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                // MediaStore, no permission needed
                                val values = android.content.ContentValues().apply {
                                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, filename)
                                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
                                    put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, relativeDir)
                                    put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                                }
                                val resolver = contentResolver
                                val uri = resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                                if (uri != null) {
                                    resolver.openOutputStream(uri)?.use { it.write(bytes) }
                                    values.clear()
                                    values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                                    resolver.update(uri, values, null, null)
                                    result.success(true)
                                } else {
                                    result.error("ERR", "Failed to insert into MediaStore", null)
                                }
                            } else {
                                // < Android 10: tulis langsung, mungkin butuh WRITE_EXTERNAL_STORAGE kalau targetSdk < 33
                                val dir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES)
                                val sub = File(dir, "DearMusic").apply { mkdirs() }
                                val out = File(sub, filename)
                                out.outputStream().use { it.write(bytes) }
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("ERR", e.message, e.stackTraceToString())
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val cmd = intent.getStringExtra("dearmusic_widget_cmd")
        if (cmd != null) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                val channel = MethodChannel(messenger, "dearmusic/widget")
                channel.invokeMethod("command", cmd)
            }
        }
    }

    private fun writeToCachePng(bytes: ByteArray, name: String = "story_bg.png"): File {
        val dir = File(cacheDir, "share_cache").apply { mkdirs() }
        val outFile = File(dir, name)
        outFile.outputStream().use { it.write(bytes) }
        return outFile
    }

    private fun toFileUri(f: File): Uri {
        return FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            f
        )
    }
}
