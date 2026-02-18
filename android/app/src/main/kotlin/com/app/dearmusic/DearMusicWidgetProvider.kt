package com.app.dearmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.media.session.MediaSessionManager
import android.net.Uri
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.widget.RemoteViews
import androidx.media.session.MediaButtonReceiver
import androidx.palette.graphics.Palette
import es.antonborri.home_widget.HomeWidgetProvider

class DearMusicWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.dearmusic_widget)
            updateViews(context, views, widgetData)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun updateViews(context: Context, views: RemoteViews, widgetData: SharedPreferences) {
        var title = widgetData.getString("now_title", "Track")
        var artist = widgetData.getString("now_subtitle", "–")
        var isPlaying = widgetData.getBoolean("is_playing", false)
        var artUriString = widgetData.getString("now_art_uri", null)

        try {
            val mediaSessionManager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val componentName = ComponentName(context, MediaButtonReceiver::class.java)
            val activeControllers = mediaSessionManager.getActiveSessions(componentName)

            if (activeControllers.isNotEmpty()) {
                val mediaController = activeControllers[0]
                val metadata = mediaController.metadata
                val playbackState = mediaController.playbackState

                title = metadata?.getString(MediaMetadataCompat.METADATA_KEY_TITLE) ?: title
                artist = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST) ?: artist
                isPlaying = playbackState?.state == PlaybackStateCompat.STATE_PLAYING
                artUriString = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ART_URI) ?: artUriString
            }
        } catch (_: SecurityException) {
        } catch (e: Exception) {
            Log.e("DearMusicWidget", "Error saat memproses MediaController: ${e.message}")
        }

        views.setTextViewText(R.id.txt_title, title)
        views.setTextViewText(R.id.txt_artist, artist)

        var bgColor = 0x40262220

        // Artwork + palette (logika ini sudah benar)
        if (!artUriString.isNullOrEmpty()) {
            try {
                val uri = Uri.parse(artUriString)
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    val bmp = BitmapFactory.decodeStream(stream)
                    if (bmp != null) {
                        views.setImageViewBitmap(R.id.img_art, bmp)
                        val palette = Palette.from(bmp).generate()
                        val dominant = palette.getDominantColor(bgColor.toInt())
                        bgColor = (dominant and 0x00FFFFFF) or 0x66000000
                    } else {
                        views.setImageViewResource(R.id.img_art, android.R.color.darker_gray)
                    }
                }
            } catch (_: Exception) {
                views.setImageViewResource(R.id.img_art, android.R.color.darker_gray)
            }
        } else {
            views.setImageViewResource(R.id.img_art, android.R.color.darker_gray)
        }
        views.setInt(R.id.root_container, "setBackgroundColor", bgColor.toInt())

        val icon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        views.setImageViewResource(R.id.btn_toggle, icon)

        views.setOnClickPendingIntent(
            R.id.btn_toggle,
            MediaButtonReceiver.buildMediaButtonPendingIntent(
                context, PlaybackStateCompat.ACTION_PLAY_PAUSE
            )
        )
        views.setOnClickPendingIntent(
            R.id.btn_next,
            MediaButtonReceiver.buildMediaButtonPendingIntent(
                context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT
            )
        )
        views.setOnClickPendingIntent(
            R.id.btn_prev,
            MediaButtonReceiver.buildMediaButtonPendingIntent(
                context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
            )
        )
        views.setOnClickPendingIntent(R.id.root_container, pendingOpenApp(context))
    }

    private fun pendingOpenApp(context: Context): PendingIntent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            1001,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}