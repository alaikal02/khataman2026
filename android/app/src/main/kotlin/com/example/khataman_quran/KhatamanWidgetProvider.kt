package com.example.khataman_quran

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class KhatamanWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.khataman_widget_layout)

            // Setup click to open app
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            // Get widget localization labels
            val isEn = widgetData.getString("app_language", "id") == "en"
            val titleText = "Khataman Quran"
            val statusText = if (isEn) "Active Progress" else "Progress Aktif"
            val emptyText = if (isEn) "No active khataman\nTap to start" else "Tidak ada khataman aktif\nKetuk untuk memulai"

            views.setTextViewText(R.id.widget_title, titleText)
            views.setTextViewText(R.id.widget_status, statusText)

            val count = widgetData.getInt("khataman_count", 0)

            if (count == 0) {
                views.setViewVisibility(R.id.khataman_empty_state, View.VISIBLE)
                views.setViewVisibility(R.id.khataman_item_1, View.GONE)
                views.setViewVisibility(R.id.khataman_item_2, View.GONE)
                views.setTextViewText(R.id.khataman_empty_text, emptyText)
            } else {
                views.setViewVisibility(R.id.khataman_empty_state, View.GONE)

                // Item 1
                views.setViewVisibility(R.id.khataman_item_1, View.VISIBLE)
                val title0 = widgetData.getString("khataman_title_0", if (isEn) "Mandiri" else "Mandiri")
                val progress0 = getDoubleOrFloat(widgetData, "khataman_progress_0", 0.0f)
                views.setTextViewText(R.id.khataman_title_0, title0)
                views.setProgressBar(R.id.khataman_progress_bar_0, 100, progress0.toInt(), false)
                val progress0Str = if (progress0 % 1.0f == 0.0f) "${progress0.toInt()}%" else String.format("%.1f%%", progress0)
                views.setTextViewText(R.id.khataman_progress_text_0, progress0Str)

                // Item 2
                if (count >= 2) {
                    views.setViewVisibility(R.id.khataman_item_2, View.VISIBLE)
                    val title1 = widgetData.getString("khataman_title_1", "")
                    val progress1 = getDoubleOrFloat(widgetData, "khataman_progress_1", 0.0f)
                    views.setTextViewText(R.id.khataman_title_1, title1)
                    views.setProgressBar(R.id.khataman_progress_bar_1, 100, progress1.toInt(), false)
                    val progress1Str = if (progress1 % 1.0f == 0.0f) "${progress1.toInt()}%" else String.format("%.1f%%", progress1)
                    views.setTextViewText(R.id.khataman_progress_text_1, progress1Str)
                } else {
                    views.setViewVisibility(R.id.khataman_item_2, View.GONE)
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun getDoubleOrFloat(prefs: SharedPreferences, key: String, defaultValue: Float): Float {
        val rawValue = prefs.all[key] ?: return defaultValue
        return when (rawValue) {
            is Float -> rawValue
            is Double -> rawValue.toFloat()
            is Long -> java.lang.Double.longBitsToDouble(rawValue).toFloat()
            is Int -> rawValue.toFloat()
            is String -> rawValue.toFloatOrNull() ?: defaultValue
            else -> defaultValue
        }
    }
}
