package com.example.khataman_quran

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class PrayerWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.prayer_widget_layout)

            // Click to open app
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

            // Retrieve data sent from Flutter
            val location = widgetData.getString("prayer_location", if (isEn) "Unknown Location" else "Lokasi Tidak Diketahui")
            val dateStr = widgetData.getString("prayer_date", "")
            val nextName = widgetData.getString("prayer_next_name", "")
            val nextKey = widgetData.getString("prayer_next_key", "")
            val nextTime = widgetData.getString("prayer_next_time", "")

            views.setTextViewText(R.id.prayer_location, location)
            views.setTextViewText(R.id.prayer_date, dateStr)

            if (nextName.isNullOrEmpty()) {
                views.setViewVisibility(R.id.prayer_next_section, View.GONE)
            } else {
                views.setViewVisibility(R.id.prayer_next_section, View.VISIBLE)
                val labelText = if (isEn) "Next: $nextName" else "Selanjutnya: $nextName"
                views.setTextViewText(R.id.prayer_next_label, labelText)
                views.setTextViewText(R.id.prayer_next_time, nextTime)
            }

            // Fill individual prayer times
            val fardPrayers = arrayOf("subuh", "dzuhur", "ashar", "maghrib", "isya")

            for (p in fardPrayers) {
                val timeVal = widgetData.getString("prayer_time_$p", "--:--")

                // Get view IDs dynamically
                val nameViewId = context.resources.getIdentifier("time_name_$p", "id", context.packageName)
                val valViewId = context.resources.getIdentifier("time_val_$p", "id", context.packageName)
                val containerViewId = context.resources.getIdentifier("time_container_$p", "id", context.packageName)

                if (nameViewId != 0 && valViewId != 0) {
                    views.setTextViewText(valViewId, timeVal)

                    // Translate fard prayer names in widget bottom grid
                    val displayName = when (p) {
                        "subuh" -> if (isEn) "Fajr" else "Subuh"
                        "dzuhur" -> if (isEn) "Dhuhr" else "Dzuhur"
                        "ashar" -> if (isEn) "Asr" else "Ashar"
                        "maghrib" -> "Maghrib"
                        "isya" -> if (isEn) "Isha" else "Isya"
                        else -> p
                    }
                    views.setTextViewText(nameViewId, displayName)

                    // Highlight next/current active prayer in gold and give it a subtle highlight
                    if (!nextKey.isNullOrEmpty() && p.equals(nextKey, ignoreCase = true)) {
                        views.setTextColor(nameViewId, 0xFFD4AF37.toInt()) // Gold
                        views.setTextColor(valViewId, 0xFFD4AF37.toInt())  // Gold
                        if (containerViewId != 0) {
                            views.setInt(containerViewId, "setBackgroundColor", 0x1AFFFFFF) // 10% white background
                        }
                    } else {
                        views.setTextColor(nameViewId, 0xFF8B949E.toInt()) // Secondary grey
                        views.setTextColor(valViewId, 0xFFE6EDF3.toInt()) // Primary text white/light grey
                        if (containerViewId != 0) {
                            views.setInt(containerViewId, "setBackgroundColor", 0x00000000) // Transparent
                        }
                    }
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
