package com.prayerlock.prayer_lock.scheduling

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.prayerlock.prayer_lock.blocking.AppBlockerService
import com.prayerlock.prayer_lock.blocking.PermissionHelper
import com.prayerlock.prayer_lock.widget.PrayerWidgetProvider

/**
 * Restores enforcement after events that silently destroy it.
 *
 * Android discards every pending alarm on reboot. Without this, a phone
 * restarted overnight would have no armed transitions the following day: no
 * lock at Fajr, no release at sunrise, and nothing to tell the user that
 * anything had stopped working. The failure is invisible until a prayer is
 * missed, which is the worst possible way for it to be discovered.
 *
 * The same restoration is needed after several other events:
 *
 *   BOOT_COMPLETED / QUICKBOOT   the alarm table was cleared
 *   MY_PACKAGE_REPLACED          an app update cancels alarms
 *   TIME_SET                     RTC alarms are anchored to wall-clock time, so
 *                                moving the clock moves every armed alarm
 *   TIMEZONE_CHANGED             stored instants are UTC and do not move, but
 *                                the user has probably travelled, so the
 *                                schedule itself may now be wrong
 *
 * Crucially this runs with no Flutter engine. It reads the mirrored schedule
 * written by [PrayerScheduleStore], re-arms alarms, and restarts the blocking
 * service if a window is currently open — all in native code, in the few
 * seconds a boot receiver is given.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in HANDLED_ACTIONS) return

        try {
            restore(context.applicationContext, action)
        } catch (error: Exception) {
            // A boot receiver that throws can be disabled by the system. Log
            // and give up on this event rather than risk that.
            Log.e(TAG, "Restore after $action failed", error)
        }
    }

    private fun restore(context: Context, action: String) {
        val store = PrayerScheduleStore(context)
        val schedule = store.load()

        if (schedule == null) {
            Log.i(TAG, "Nothing to restore after $action")
            return
        }

        val now = System.currentTimeMillis()

        // A reboot resets the monotonic clock, so the previous checkpoint can
        // no longer be compared against. Re-baseline rather than reporting a
        // false manipulation.
        store.recordClockCheckpoint(now, SystemClock.elapsedRealtime())

        // Re-arm first. If starting the service fails — a revoked permission,
        // a background-start restriction — the alarms still carry enforcement
        // forward to the next transition.
        PrayerAlarmScheduler(context).rearm(schedule, now)
        PrayerWidgetProvider.refresh(context)

        val active = schedule.activeWindowAt(now)
        if (active == null) {
            Log.i(TAG, "Restored alarms after $action; no window currently open")
            return
        }

        if (!PermissionHelper.hasUsageStatsPermission(context)) {
            Log.w(TAG, "Usage access revoked; enforcement cannot resume")
            return
        }

        val serviceIntent = Intent(context, AppBlockerService::class.java)
            .setAction(AppBlockerService.ACTION_START_LOCK)
            .putStringArrayListExtra(
                AppBlockerService.EXTRA_BLOCKED_PACKAGES,
                ArrayList(schedule.blockedPackages),
            )
            .putExtra(
                AppBlockerService.EXTRA_PRAYER_NAME,
                active.label ?: active.prayer.replaceFirstChar { it.uppercase() },
            )
            .putExtra(AppBlockerService.EXTRA_ENDS_AT, active.endsAt)
            .putExtra(AppBlockerService.EXTRA_SILENCE, active.silence)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        Log.i(TAG, "Resumed blocking for ${active.prayer} after $action")
    }

    companion object {
        private const val TAG = "PrayerLockBootReceiver"

        private val HANDLED_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            // Several OEMs use a "fast boot" that never emits BOOT_COMPLETED.
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
    }
}
