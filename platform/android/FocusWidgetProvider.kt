package __PACKAGE__

// Installed by tool/setup_platforms.dart. Edit this copy in platform/android/.

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/** Home screen widget: the current block, the task in progress and a progress bar. */
class FocusWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent()
        val openApp = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.focus_widget)
            views.setTextViewText(R.id.fb_chip, widgetData.getString("fb_chip", "FOCUS BLOCKS"))
            views.setTextViewText(R.id.fb_streak, widgetData.getString("fb_streak", ""))
            views.setTextViewText(R.id.fb_title, widgetData.getString("fb_title", "Open the app to start"))

            val line = widgetData.getString("fb_line", "") ?: ""
            views.setTextViewText(R.id.fb_line, line)
            views.setViewVisibility(R.id.fb_line, if (line.isEmpty()) View.GONE else View.VISIBLE)

            val progress = widgetData.getString("fb_progress", "-1")?.toIntOrNull() ?: -1
            if (progress >= 0) {
                views.setViewVisibility(R.id.fb_progress, View.VISIBLE)
                views.setProgressBar(R.id.fb_progress, 100, progress, false)
            } else {
                views.setViewVisibility(R.id.fb_progress, View.GONE)
            }

            val footer = widgetData.getString("fb_footer", "") ?: ""
            views.setTextViewText(R.id.fb_footer, footer)
            views.setViewVisibility(R.id.fb_footer, if (footer.isEmpty()) View.GONE else View.VISIBLE)

            views.setOnClickPendingIntent(R.id.fb_root, openApp)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
