package com.sconl.isconl

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone

/**
 * BI26101528: the work-hours clock, as far as the quick-settings tile and the home-screen widget are concerned.
 *
 * Neither ever touches the network or boots Flutter. A tap is written here at once, as a pending entry with the
 * device time and timezone, and the state and net minutes are updated so the tile label and the widget change
 * immediately. The app drains the pending list into its outbox (in order) the next time it is in front, so an
 * offline tap is delivered later with the time it was made.
 *
 * What is stored is a state word and minutes: never a note, never anything from the journal.
 */
object ClockStore {
    const val PREFS = "isconl_clock"
    private const val STATE = "state" // "out", "working" or "break"
    private const val WORKED = "worked" // net minutes worked today, as of ASOF
    private const val ASOF = "asof" // epoch milliseconds
    private const val PENDING = "pending"
    private const val LOCKED = "locked"

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun state(c: Context): String = prefs(c).getString(STATE, "out") ?: "out"

    /** True when the app lock is on: a tap then opens the app instead of writing. */
    fun locked(c: Context): Boolean = prefs(c).getBoolean(LOCKED, false)

    fun nextAction(state: String): String = when (state) {
        "working" -> "break"
        "break" -> "back"
        else -> "in"
    }

    fun label(action: String): String = when (action) {
        "in" -> "Clock in"
        "break" -> "Break"
        "back" -> "Back"
        else -> "Clock out"
    }

    fun stateWord(state: String): String = when (state) {
        "working" -> "Working"
        "break" -> "On break"
        else -> "Clocked out"
    }

    fun allowed(state: String, action: String): Boolean = when (action) {
        "in" -> state == "out"
        "break" -> state == "working"
        "back" -> state == "break"
        "out" -> state == "working" || state == "break"
        else -> false
    }

    private fun after(action: String): String = when (action) {
        "in", "back" -> "working"
        "break" -> "break"
        else -> "out"
    }

    /** Net minutes worked today, counting the running stretch while the state is "working". */
    fun workedNow(c: Context, now: Long = System.currentTimeMillis()): Int {
        val p = prefs(c)
        val base = p.getInt(WORKED, 0)
        val since = p.getLong(ASOF, now)
        return if (state(c) == "working") base + ((now - since) / 60000L).toInt().coerceAtLeast(0) else base
    }

    /** The device clock with its offset, `2026-10-16T09:30:00+03:00`, built by hand (the X pattern needs API 24). */
    fun stamp(ms: Long): String {
        val tz = TimeZone.getDefault()
        val offMin = tz.getOffset(ms) / 60000
        val cal = java.util.Calendar.getInstance(tz).apply { timeInMillis = ms }
        val sign = if (offMin < 0) "-" else "+"
        val a = Math.abs(offMin)
        return String.format(
            "%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d",
            cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH),
            cal.get(java.util.Calendar.HOUR_OF_DAY), cal.get(java.util.Calendar.MINUTE), cal.get(java.util.Calendar.SECOND),
            sign, a / 60, a % 60,
        )
    }

    /** Queues [action] if the journal's order allows it from the current state. False means refused, nothing written. */
    fun record(c: Context, action: String, now: Long = System.currentTimeMillis()): Boolean {
        val st = state(c)
        if (!allowed(st, action)) return false
        val p = prefs(c)
        val pending = try { JSONArray(p.getString(PENDING, "[]")) } catch (e: Exception) { JSONArray() }
        pending.put(JSONObject().put("action", action).put("at", stamp(now)).put("tz", TimeZone.getDefault().id))
        // The net total up to this tap becomes the new baseline.
        val worked = workedNow(c, now)
        p.edit()
            .putString(PENDING, pending.toString())
            .putString(STATE, after(action))
            .putInt(WORKED, if (action == "in" && st == "out" && p.getLong(ASOF, 0) < startOfDay(now)) 0 else worked)
            .putLong(ASOF, now)
            .apply()
        return true
    }

    private fun startOfDay(ms: Long): Long {
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = ms }
        cal.set(java.util.Calendar.HOUR_OF_DAY, 0); cal.set(java.util.Calendar.MINUTE, 0)
        cal.set(java.util.Calendar.SECOND, 0); cal.set(java.util.Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    /** The queued taps as a JSON array string, oldest first; the list is emptied. */
    fun drain(c: Context): String {
        val p = prefs(c)
        val raw = p.getString(PENDING, "[]") ?: "[]"
        p.edit().putString(PENDING, "[]").apply()
        return raw
    }

    /** The app's view of the journal head: `{state, worked, asOf (epoch ms), locked}`. Taps still pending are kept. */
    fun publish(c: Context, json: String) {
        val o = JSONObject(json)
        val e = prefs(c).edit()
        val hasPending = (try { JSONArray(prefs(c).getString(PENDING, "[]")).length() } catch (x: Exception) { 0 }) > 0
        // A tap made since the app last looked is newer than the app's view: keep the local state then.
        if (!hasPending) {
            e.putString(STATE, o.optString("state", "out"))
            e.putInt(WORKED, o.optInt("worked", 0))
            e.putLong(ASOF, o.optLong("asOf", System.currentTimeMillis()))
        }
        e.putBoolean(LOCKED, o.optBoolean("locked", false))
        e.apply()
    }
}
