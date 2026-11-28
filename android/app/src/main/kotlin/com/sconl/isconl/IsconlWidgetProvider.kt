package com.sconl.isconl

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * BI26100138: the home-screen widget.
 *
 * It never touches the network and never boots Flutter. It draws what the app last wrote into its own
 * SharedPreferences ("isconl_widget", key "snapshot"), and says when that was ("as of 14:05") so a stale widget
 * reads as stale instead of wrong. The snapshot is built in Dart and holds a block name, an end time and the next
 * item's title: nothing from finance or health, and no message contents.
 */
class IsconlWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, render(context))
    }

    companion object {
        const val PREFS = "isconl_widget"
        const val KEY = "snapshot"

        fun save(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply()
            refresh(context)
        }

        fun refresh(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, IsconlWidgetProvider::class.java))
            for (id in ids) mgr.updateAppWidget(id, render(context))
        }

        private fun open(context: Context, action: String, code: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun render(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.isconl_widget)
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            val snap = try { if (raw == null) null else JSONObject(raw) } catch (e: Exception) { null }
            views.setTextViewText(R.id.widget_block, snap?.optString("block").orEmpty().ifEmpty { context.getString(R.string.widget_open_app) })
            views.setTextViewText(R.id.widget_block_left, snap?.optString("blockLeft").orEmpty())
            views.setTextViewText(R.id.widget_next, snap?.optString("next").orEmpty())
            views.setTextViewText(R.id.widget_asof, snap?.optString("asOf").orEmpty().let { if (it.isEmpty()) "" else "as of $it" })
            views.setOnClickPendingIntent(R.id.widget_next, open(context, "com.sconl.isconl.TODAY", 1))
            views.setOnClickPendingIntent(R.id.widget_block, open(context, "com.sconl.isconl.TODAY", 1))
            views.setOnClickPendingIntent(R.id.widget_capture, open(context, "com.sconl.isconl.CAPTURE", 2))
            views.setOnClickPendingIntent(R.id.widget_mic, open(context, "com.sconl.isconl.VOICE", 3))
            return views
        }
    }
}
