package com.sconl.isconl

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Live SMS capture.
 *
 * Deliberately does almost nothing. It notes that something arrived and lets the
 * app pull it from the inbox on its next read, rather than shipping the message
 * body from a broadcast receiver.
 *
 * That is the safer shape for three reasons. A receiver has no session and no
 * token, so it cannot talk to the agent without storing a credential somewhere a
 * background component can reach. It runs on the main thread with a few seconds
 * to live, so it must not do network work. And the inbox is already the durable
 * record - re-reading from it means a crash mid-handling loses nothing, because
 * the message is still there and the high-water mark has not moved.
 *
 * So: record the arrival time and stop. lib/services/sms_ingest.dart does the
 * rest, with a session, off the main thread, and idempotently.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val fromMpesa = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            ?.any { it.originatingAddress?.replace("-", "")?.uppercase() == "MPESA" } ?: false
        if (!fromMpesa) return

        // A flag and a timestamp. No body, no network, no credential.
        context.getSharedPreferences("isconl_sms", Context.MODE_PRIVATE)
            .edit()
            .putLong("pending_since", System.currentTimeMillis())
            .putBoolean("pending", true)
            .apply()
    }
}
