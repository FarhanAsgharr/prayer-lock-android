package com.prayerlock.prayer_lock.scheduling

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.prayerlock.prayer_lock.blocking.AppBlockerService
import com.prayerlock.prayer_lock.blocking.PermissionHelper

/**
 * Applies the blocking decision when an alarm fires.
 *
 * This is the path that keeps the product working when the app is not running:
 * the alarm wakes the device, this receiver reads the mirrored schedule, decides
 * whether apps should be blocked *right now*, starts or stops the foreground
 * service accordingly, and re-arms the next batch of alarms.
 *
 * It is idempotent and stateless. It never asks "what did I do last time" —
 * it computes the state the device should be in and converges on it. That is
 * what makes it safe to fire twice, to fire late, or to fire after a reboot
 * when the previous state is entirely unknown.
 */
class PrayerAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // goAsync would be needed for I/O; everything here is SharedPreferences
        // and a service start, both of which are fast enough for the 10-second
        // broadcast budget. Keeping it synchronous avoids leaking a pending
        // result if an exception escapes.
        try {
            evaluate(context.applicationContext, intent.action)
        } catch (error: Exception) {
            // A receiver that throws is an ANR and, on some OEM builds, a
            // reason to stop delivering future broadcasts to the app. Swallow
            // and log: losing one transition is recoverable, losing the
            // receiver is not.
            Log.e(TAG, "Alarm evaluation failed", error)
        }
    }

    private fun evaluate(context: Context, action: String?) {
        val store = PrayerScheduleStore(context)
        val schedule = store.load()

        if (schedule == null) {
            Log.i(TAG, "No mirrored schedule; nothing to enforce")
            return
        }

        val now = System.currentTimeMillis()

        // Clock manipulation check. A user who winds the clock back to escape a
        // lock moves the wall clock without moving the monotonic clock, so the
        // two disagree. The response is not to guess the "real" time — we
        // cannot know it — but to refuse to release a lock on the strength of a
        // clock that has demonstrably been tampered with.
        val drift = store.backwardsClockDrift(now, SystemClock.elapsedRealtime())
        val clockIsSuspect = drift > 0
        if (clockIsSuspect) {
            Log.w(TAG, "Wall clock moved backwards by ${drift}ms relative to uptime")
        }
        store.recordClockCheckpoint(now, SystemClock.elapsedRealtime())

        val active = schedule.activeWindowAt(now)

        when {
            active != null -> startBlocking(context, schedule, active)

            // The clock says nothing is due, but the clock has been moved
            // backwards. Holding the existing lock rather than releasing it
            // means the worst case of a genuine clock correction is a lock that
            // persists until the next honest transition, instead of a trivial
            // bypass.
            clockIsSuspect -> Log.w(TAG, "Holding lock: clock integrity check failed")

            else -> stopBlocking(context)
        }

        // Re-arm regardless of the outcome. The chain of alarms is what carries
        // enforcement forward; dropping it because nothing is due right now
        // would mean the next prayer never engages.
        PrayerAlarmScheduler(context).rearm(schedule, now)

        Log.i(TAG, "Evaluated ($action): active=${active?.prayer ?: "none"}")
    }

    private fun startBlocking(
        context: Context,
        schedule: PrayerScheduleStore.Schedule,
        window: PrayerScheduleStore.Window,
    ) {
        // Starting a service that cannot enforce anything would leave the user
        // with a persistent notification claiming protection they do not have.
        if (!PermissionHelper.hasUsageStatsPermission(context)) {
            Log.w(TAG, "Usage access revoked; cannot enforce")
            return
        }

        val intent = Intent(context, AppBlockerService::class.java)
            .setAction(AppBlockerService.ACTION_START_LOCK)
            .putStringArrayListExtra(
                AppBlockerService.EXTRA_BLOCKED_PACKAGES,
                ArrayList(schedule.blockedPackages),
            )
            .putExtra(AppBlockerService.EXTRA_PRAYER_NAME, displayName(window.prayer))
            .putExtra(AppBlockerService.EXTRA_ENDS_AT, window.endsAt)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun stopBlocking(context: Context) {
        context.startService(
            Intent(context, AppBlockerService::class.java)
                .setAction(AppBlockerService.ACTION_STOP_LOCK)
        )
    }

    private fun displayName(wireValue: String): String =
        wireValue.replaceFirstChar { it.uppercase() }

    companion object {
        private const val TAG = "PrayerAlarmReceiver"

        const val ACTION_EVALUATE = "com.prayerlock.action.EVALUATE_SCHEDULE"
        const val EXTRA_SLOT = "slot"
    }
}
