package com.tamilgaming.paatupadava

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.view.KeyEvent
import android.widget.RemoteViews

class MusicWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_PLAY_PAUSE = "com.tamilgaming.paatupadava.WIDGET_PLAY_PAUSE"
        const val ACTION_PREV = "com.tamilgaming.paatupadava.WIDGET_PREV"
        const val ACTION_NEXT = "com.tamilgaming.paatupadava.WIDGET_NEXT"

        private var lastTitle: String = "Paatu Padava"
        private var lastArtist: String = "Tap to play"
        private var lastIsPlaying: Boolean = false
        private var lastCoverBytes: ByteArray? = null

        fun updateAllWidgets(
            context: Context,
            title: String?,
            artist: String?,
            isPlaying: Boolean,
            coverBytes: ByteArray? = null
        ) {
            if (title != null) lastTitle = title
            if (artist != null) lastArtist = artist
            lastIsPlaying = isPlaying
            if (coverBytes != null) lastCoverBytes = coverBytes

            val appWidgetManager = AppWidgetManager.getInstance(context) ?: return
            val componentName = ComponentName(context, MusicWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(componentName)

            for (widgetId in widgetIds) {
                val views = buildRemoteViews(context, lastTitle, lastArtist, lastIsPlaying, lastCoverBytes)
                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }

        private fun buildRemoteViews(
            context: Context,
            title: String,
            artist: String,
            isPlaying: Boolean,
            coverBytes: ByteArray?
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.music_widget_layout)

            views.setTextViewText(R.id.widget_song_title, title)
            views.setTextViewText(R.id.widget_artist_name, artist)

            val playPauseIcon = if (isPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            }
            views.setImageViewResource(R.id.widget_btn_play_pause, playPauseIcon)

            if (coverBytes != null && coverBytes.isNotEmpty()) {
                try {
                    val bmp = BitmapFactory.decodeByteArray(coverBytes, 0, coverBytes.size)
                    if (bmp != null) {
                        views.setImageViewBitmap(R.id.widget_album_art, bmp)
                    } else {
                        views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_notification)
                    }
                } catch (_: Exception) {
                    views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_notification)
                }
            } else {
                views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_notification)
            }

            // Click root -> Open App
            val openAppIntent = Intent(context, MainActivity::class.java)
            val pendingOpen = PendingIntent.getActivity(
                context,
                0,
                openAppIntent,
                getPendingIntentFlags()
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingOpen)

            // Button Intents
            views.setOnClickPendingIntent(
                R.id.widget_btn_play_pause,
                createActionIntent(context, ACTION_PLAY_PAUSE, 101)
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_prev,
                createActionIntent(context, ACTION_PREV, 102)
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_next,
                createActionIntent(context, ACTION_NEXT, 103)
            )

            return views
        }

        private fun createActionIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MusicWidgetProvider::class.java).apply {
                this.action = action
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                getPendingIntentFlags()
            )
        }

        private fun getPendingIntentFlags(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            val views = buildRemoteViews(context, lastTitle, lastArtist, lastIsPlaying, lastCoverBytes)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        val keyCode = when (intent.action) {
            ACTION_PLAY_PAUSE -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            ACTION_PREV -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            ACTION_NEXT -> KeyEvent.KEYCODE_MEDIA_NEXT
            else -> null
        }

        if (keyCode != null) {
            try {
                val mediaReceiver = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
                val down = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    component = mediaReceiver
                    putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                }
                val up = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    component = mediaReceiver
                    putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, keyCode))
                }
                context.sendBroadcast(down)
                context.sendBroadcast(up)
            } catch (_: Exception) {}
        }
    }
}
