package com.sconl.isconl

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews

/**
 * BI26101528: the clock widget. Today's net worked, the current state and one button for the next action. It draws
 * from [ClockStore] only (no network, no Flutter) and is redrawn on every tap and whenever the app publishes the
 * journal head. Android's own refresh period for a widget is at least 30 minutes, so the running total is
 * recomputed from the stored baseline each time it is drawn.
 */
class ClockWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, render(context))
    }

    companion object {
        const val ACTION_TAP = "com.sconl.isconl.CLOCK_TAP"

        fun refresh(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, ClockWidgetProvider::class.java))
            for (id in ids) mgr.updateAppWidget(id, render(context))
        }

        fun worked(minutes: Int): String = if (minutes < 60) "$minutes min" else "${minutes / 60} h ${minutes % 60} min"

        fun render(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.clock_widget)
            val st = ClockStore.state(context)
            val next = ClockStore.nextAction(st)
            views.setTextViewText(R.id.clock_state, ClockStore.stateWord(st))
            views.setTextViewText(R.id.clock_worked, worked(ClockStore.workedNow(context)) + " worked today")
            views.setTextViewText(R.id.clock_button, ClockStore.label(next))
            val tap = Intent(context, ClockActionReceiver::class.java).apply { action = ACTION_TAP }
            views.setOnClickPendingIntent(
                R.id.clock_button,
                PendingIntent.getBroadcast(context, 21, tap, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
            return views
        }
    }
}

/** The widget button: with the app lock on it opens the app, otherwise it queues the next action. */
class ClockActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ClockWidgetProvider.ACTION_TAP) return
        if (ClockStore.locked(context)) {
            context.startActivity(
                Intent(context, MainActivity::class.java).apply {
                    action = "com.sconl.isconl.CLOCK"
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
            )
            return
        }
        ClockTap.tap(context, ClockStore.nextAction(ClockStore.state(context)))
    }
}

/**
 * The tile's long-press target (QS_TILE_PREFERENCES): clocks out, then closes at once. Invisible, so a long-press
 * from the lock screen is one gesture. With the app lock on it opens the app instead.
 */
class ClockOutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val ctx = applicationContext
        if (ClockStore.locked(ctx)) {
            startActivity(
                Intent(ctx, MainActivity::class.java).apply {
                    action = "com.sconl.isconl.CLOCK"
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
            )
        } else {
            ClockTap.tap(ctx, "out")
        }
        finish()
    }
}
