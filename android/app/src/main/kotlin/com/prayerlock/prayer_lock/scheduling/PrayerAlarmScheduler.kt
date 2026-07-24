package com.prayerlock.prayer_lock.scheduling

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Arms the exact alarms that drive blocking while the app is not running.
 *
 * Why alarms rather than a long-lived timer:
 *
 * A prayer window can be three and a half hours. Keeping a foreground service
 * polling for its end would burn battery for hours to observe a single instant.
 * An exact alarm costs nothing until it fires, and Android will deliver it even
 * in Doze — which a timer inside a killed process will not.
 *
 * Only a small number of alarms are armed at once (see [MAX_ARMED_ALARMS]).
 * Android will happily accept dozens, but each one is a scheduled wakeup, and a
 * week of windows would be over a hundred. Every alarm re-arms the next batch
 * when it fires, so the chain continues without holding them all at once.
 */
class PrayerAlarmScheduler(private val context: Context) {

    private val alarmManager: AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /**
     * Re-arm alarms for the upcoming transitions in [schedule].
     *
     * Idempotent: existing alarms with the same request code are replaced, so
     * calling this repeatedly — which the Dart side does on every sync — does
     * not accumulate duplicates.
     */
    fun rearm(schedule: PrayerScheduleStore.Schedule, now: Long = System.currentTimeMillis()) {
        cancelAll()

        val transitions = schedule.transitionsAfter(now).take(MAX_ARMED_ALARMS)
        if (transitions.isEmpty()) {
            Log.i(TAG, "No upcoming transitions to arm")
            return
        }

        transitions.forEachIndexed { index, instant ->
            arm(index, instant)
        }

        Log.i(TAG, "Armed ${transitions.size} alarms; next at ${transitions.first()}")
    }

    private fun arm(slot: Int, triggerAtMillis: Long) {
        val pendingIntent = pendingIntentFor(slot) ?: return

        // setAlarmClock is the only tier Android will not defer in Doze. It is
        // the correct choice here for the same reason it is correct for an
        // alarm clock: firing late is not a degraded outcome, it is a failure —
        // a lock that engages twenty minutes into a prayer has already missed
        // the moment it existed for.
        //
        // The trade-off is that it surfaces the next alarm in the status bar on
        // some OEM skins. That is acceptable; being silently deferred is not.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !alarmManager.canScheduleExactAlarms()
            ) {
                // The user revoked exact-alarm permission. Fall back rather than
                // throwing: an approximate lock is worth more than none, and the
                // Dart layer surfaces the permission prompt separately.
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent,
                )
                return
            }

            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent()),
                pendingIntent,
            )
        } catch (error: SecurityException) {
            // Some OEM builds reject exact alarms even when the permission
            // check passes. Degrade instead of crashing a boot receiver.
            Log.w(TAG, "Exact alarm refused, falling back to inexact", error)
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        }
    }

    fun cancelAll() {
        for (slot in 0 until MAX_ARMED_ALARMS) {
            // FLAG_NO_CREATE so cancelling does not create the very intents it
            // is trying to remove.
            val existing = pendingIntentFor(slot, create = false)
            if (existing != null) {
                alarmManager.cancel(existing)
                existing.cancel()
            }
        }
    }

    private fun pendingIntentFor(slot: Int, create: Boolean = true): PendingIntent? {
        val intent = Intent(context, PrayerAlarmReceiver::class.java).apply {
            action = PrayerAlarmReceiver.ACTION_EVALUATE
            // The data URI makes each slot's intent distinct. Extras alone do
            // not participate in PendingIntent equality, so without this every
            // slot would collide onto one alarm.
            `package` = context.packageName
            putExtra(PrayerAlarmReceiver.EXTRA_SLOT, slot)
        }

        var flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        if (!create) flags = flags or PendingIntent.FLAG_NO_CREATE

        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE_BASE + slot,
            intent,
            flags,
        )
    }

    /** Tapping the alarm entry in the status bar opens the app. */
    private fun showIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        REQUEST_CODE_SHOW,
        context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        private const val TAG = "PrayerAlarmScheduler"

        /**
         * How many transitions to hold armed at once.
         *
         * A day has at most twenty (five prayers x start, engage, end, qaza).
         * Arming a day at a time means the chain survives a device that is not
         * opened for twenty-four hours, without registering a week of wakeups.
         */
        const val MAX_ARMED_ALARMS = 20

        private const val REQUEST_CODE_BASE = 8100
        private const val REQUEST_CODE_SHOW = 8099
    }
}
