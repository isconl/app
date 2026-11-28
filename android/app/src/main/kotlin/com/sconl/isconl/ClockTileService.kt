package com.sconl.isconl

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast

/**
 * BI26101528: the quick-settings tile. One tile whose label is the next action the journal allows: Clock in, Break,
 * Back. A tap queues the entry at once (see [ClockStore]) and the label changes; it never waits for the network.
 * Long-press opens [ClockOutActivity], which clocks out. With the app lock on, a tap opens the app instead.
 */
class ClockTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        val ctx = applicationContext
        if (ClockStore.locked(ctx)) {
            openApp(ctx)
            return
        }
        ClockTap.tap(ctx, ClockStore.nextAction(ClockStore.state(ctx)))
        refresh()
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val st = ClockStore.state(this)
        tile.label = ClockStore.label(ClockStore.nextAction(st))
        tile.state = if (st == "out") Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = ClockStore.stateWord(st)
        tile.updateTile()
    }

    @Suppress("DEPRECATION")
    private fun openApp(ctx: Context) {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            action = "com.sconl.isconl.CLOCK"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(ctx, 11, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
        } else {
            startActivityAndCollapse(intent)
        }
    }
}

/** What a tap does, shared by the tile, the widget button and the long-press: queue, then refresh both surfaces. */
object ClockTap {
    fun tap(ctx: Context, action: String): Boolean {
        val ok = ClockStore.record(ctx, action)
        if (!ok) {
            Toast.makeText(ctx, "Can't ${ClockStore.label(action).lowercase()} now: the day is ${ClockStore.stateWord(ClockStore.state(ctx)).lowercase()}.", Toast.LENGTH_SHORT).show()
        }
        ClockWidgetProvider.refresh(ctx)
        refreshTile(ctx)
        return ok
    }

    fun refreshTile(ctx: Context) {
        try {
            TileService.requestListeningState(ctx, ComponentName(ctx, ClockTileService::class.java))
        } catch (e: Exception) {
            // The tile is not added to the panel: nothing to refresh.
        }
    }
}
