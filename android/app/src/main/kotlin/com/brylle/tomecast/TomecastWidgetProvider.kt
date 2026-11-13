package com.brylle.tomecast

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget: cover, title, and rewind / play-pause / forward.
 * The buttons send normal media-button presses (like a Bluetooth headset),
 * so they control playback without opening the app.
 * The Dart side (WidgetUpdater) saves what to show and asks for a refresh.
 */
class TomecastWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.tomecast_widget)

            views.setTextViewText(R.id.widget_title,
                widgetData.getString("title", null) ?: "Tomecast")
            views.setTextViewText(R.id.widget_subtitle,
                widgetData.getString("subtitle", null) ?: "Tap to open your library")

            val playing = widgetData.getBoolean("playing", false)
            views.setImageViewResource(R.id.widget_play,
                if (playing) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play)

            val cover = widgetData.getString("cover", null)
            val bitmap = cover?.let { loadSmallBitmap(it) }
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.widget_cover, bitmap)
            } else {
                views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
            }

            // Tapping the widget opens the app.
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(
                context, 0, launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))

            views.setOnClickPendingIntent(R.id.widget_rewind,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_REWIND, 1))
            views.setOnClickPendingIntent(R.id.widget_play,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 2))
            views.setOnClickPendingIntent(R.id.widget_forward,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, 3))

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun mediaButton(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setClass(context, MediaButtonReceiver::class.java)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Widgets have a small memory limit: load the cover at ~256 px. */
    private fun loadSmallBitmap(path: String) = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= 256 && bounds.outHeight / (sample * 2) >= 256) {
            sample *= 2
        }
        BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    } catch (e: Exception) {
        null
    }
}
