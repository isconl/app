package com.sconl.isconl

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar

/**
 * BI26100138: the home-screen widget. The current day block with the time left in it, the next item due,
 * and two buttons that open a capture straight into the inbox (text, or a voice note).
 *
 * It never touches the network and never runs Dart. The app writes one snapshot (the day's blocks and the
 * next few items, see home_widget_snapshot.dart) and this side picks what is current by the clock. It
 * redraws itself at the next block boundary or in 15 minutes, whichever comes first, so the time left stays
 * honest while the app is closed.
 */
class TodayWidget : AppWidgetProvider() {

    companion object {
        const val PREFS = "isconl_widget"
        const val KEY_SNAPSHOT = "snapshot"
        const val ACTION_TICK = "com.sconl.isconl.widget.TICK"
        const val ACTION_CAPTURE = "com.sconl.isconl.action.CAPTURE"
        const val ACTION_VOICE = "com.sconl.isconl.action.VOICE"
        const val ACTION_TODAY = "com.sconl.isconl.action.TODAY"
        private const val REFRESH_MS = 15 * 60 * 1000L

        /** Stores a snapshot from the app and redraws every placed widget. */
        fun save(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_SNAPSHOT, json).apply()
            redrawAll(context)
        }

        fun redrawAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, TodayWidget::class.java))
            if (ids.isNotEmpty()) draw(context, mgr, ids)
        }

        private fun draw(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_SNAPSHOT, null)
            val snap = try { if (raw == null) null else JSONObject(raw) } catch (e: Exception) { null }
            val now = System.currentTimeMillis()
            val view = WidgetView.from(snap, now)
            for (id in ids) {
                val compact = isCompact(mgr.getAppWidgetOptions(id))
                mgr.updateAppWidget(id, render(context, view, compact))
            }
            scheduleNext(context, view.nextChangeAt ?: (now + REFRESH_MS), now)
        }

        private fun isCompact(options: Bundle?): Boolean {
            val h = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 0
            return h in 1..79
        }

        private fun render(context: Context, v: WidgetView, compact: Boolean): RemoteViews {
            val rv = RemoteViews(context.packageName, R.layout.widget_today)
            rv.setTextViewText(R.id.widget_block, v.blockLine)
            rv.setTextViewText(R.id.widget_left, v.leftLine)
            rv.setTextViewText(R.id.widget_next, v.nextLine)
            rv.setViewVisibility(R.id.widget_next, if (compact) View.GONE else View.VISIBLE)
            rv.setOnClickPendingIntent(R.id.widget_body, launch(context, ACTION_TODAY, 1))
            rv.setOnClickPendingIntent(R.id.widget_capture, launch(context, ACTION_CAPTURE, 2))
            rv.setOnClickPendingIntent(R.id.widget_voice, launch(context, ACTION_VOICE, 3))
            return rv
        }

        private fun launch(context: Context, action: String, code: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        /** An inexact alarm (no special permission) to redraw at the next change; Android may batch it. */
        private fun scheduleNext(context: Context, at: Long, now: Long) {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val tick = PendingIntent.getBroadcast(
                context, 0,
                Intent(context, TodayWidget::class.java).setAction(ACTION_TICK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarms.set(AlarmManager.RTC, at.coerceIn(now + 60_000L, now + REFRESH_MS), tick)
        }

        private fun cancelTick(context: Context) {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val tick = PendingIntent.getBroadcast(
                context, 0,
                Intent(context, TodayWidget::class.java).setAction(ACTION_TICK),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            ) ?: return
            alarms.cancel(tick)
        }
    }

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) = draw(context, mgr, ids)

    override fun onAppWidgetOptionsChanged(context: Context, mgr: AppWidgetManager, id: Int, newOptions: Bundle) =
        draw(context, mgr, intArrayOf(id))

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) redrawAll(context)
    }

    override fun onDisabled(context: Context) = cancelTick(context)
}

/** What the widget shows at one moment, worked out from the snapshot and the clock. */
internal data class WidgetView(
    val blockLine: String,
    val leftLine: String,
    val nextLine: String,
    val nextChangeAt: Long?,
) {
    companion object {
        fun from(snap: JSONObject?, now: Long): WidgetView {
            if (snap == null) return WidgetView("iSconl", "Open the app once to fill this in", "", null)
            val cal = Calendar.getInstance().apply { timeInMillis = now }
            val nowMin = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
            val midnight = now - (nowMin * 60_000L) - cal.get(Calendar.SECOND) * 1000L - cal.get(Calendar.MILLISECOND)

            var blockLine = "Day"
            var leftLine = ""
            var change: Long? = null
            val blocks = snap.optJSONArray("blocks")
            if (blocks != null) {
                for (i in 0 until blocks.length()) {
                    val b = blocks.optJSONObject(i) ?: continue
                    val start = b.optInt("start", -1)
                    val end = b.optInt("end", -1)
                    if (start < 0 || end < 0) continue
                    val inside = if (end > start) nowMin in start until end else (nowMin >= start || nowMin < end)
                    if (!inside) continue
                    val left = ((end - nowMin) + 1440) % 1440
                    blockLine = b.optString("name", "Block")
                    leftLine = leftText(if (left == 0) 1440 else left)
                    change = midnight + ((nowMin + left) * 60_000L)
                    break
                }
            }

            var nextLine = "Nothing else due today"
            val items = snap.optJSONArray("items")
            if (items != null) {
                for (i in 0 until items.length()) {
                    val item = items.optJSONObject(i) ?: continue
                    val until = item.optLong("until", 0L)
                    if (until <= now) continue
                    val at = item.optLong("at", 0L)
                    val title = item.optString("title", "")
                    nextLine = if (at <= now) "Now · $title" else "${clock(at)} · $title"
                    val flip = if (at > now) at else until
                    val soonest = change
                    if (soonest == null || flip < soonest) change = flip
                    break
                }
            }
            return WidgetView(blockLine, leftLine, nextLine, change)
        }

        private fun leftText(minutes: Int): String {
            val h = minutes / 60
            val m = minutes % 60
            return when {
                h == 0 -> "${m}m left"
                m == 0 -> "${h}h left"
                else -> "${h}h ${m}m left"
            }
        }

        private fun clock(ms: Long): String {
            val c = Calendar.getInstance().apply { timeInMillis = ms }
            return String.format("%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
        }
    }
}
