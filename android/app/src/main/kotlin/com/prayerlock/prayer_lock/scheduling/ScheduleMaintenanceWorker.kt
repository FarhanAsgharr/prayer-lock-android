package com.prayerlock.prayer_lock.scheduling

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import android.util.Log
import java.util.concurrent.TimeUnit

/**
 * Daily safety net for the alarm chain.
 *
 * The alarm chain is self-perpetuating: each alarm re-arms the next batch when
 * it fires. Self-perpetuating chains have one failure mode — if a link is ever
 * missed, nothing re-arms and the chain is silently dead forever. A force-stop
 * from the app info screen, an aggressive OEM battery manager, or an alarm
 * dropped under memory pressure will all do it.
 *
 * WorkManager is the right tool for the repair because it is the one scheduling
 * primitive Android persists across reboots, app updates and process death, and
 * it will re-run work that was missed. It is deliberately *not* used for the
 * transitions themselves: its minimum period is fifteen minutes and its timing
 * is approximate, which is useless for "lock at 12:17".
 *
 * The worker never fetches prayer times — that needs the Dart layer and the
 * network. It only re-arms from the mirror, which is why the mirror holds
 * several days of windows rather than only today's.
 */
class ScheduleMaintenanceWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {

    override fun doWork(): Result {
        val store = PrayerScheduleStore(applicationContext)
        val schedule = store.load()

        if (schedule == null) {
            // Nothing synced yet. Not a failure — the user may not have
            // finished onboarding — so do not ask WorkManager to retry.
            Log.i(TAG, "No mirrored schedule to maintain")
            return Result.success()
        }

        val now = System.currentTimeMillis()
        val remaining = schedule.transitionsAfter(now)

        if (remaining.isEmpty()) {
            // The mirror has been exhausted: every window it holds is in the
            // past. Enforcement is now inert until the app is opened and Dart
            // pushes a fresh horizon. Logged loudly because this is the state
            // that looks like "blocking stopped working for no reason".
            Log.w(TAG, "Mirrored schedule is exhausted; awaiting a sync from the app")
            return Result.success()
        }

        PrayerAlarmScheduler(applicationContext).rearm(schedule, now)
        Log.i(TAG, "Re-armed alarms; ${remaining.size} transitions remain in the mirror")

        return Result.success()
    }

    companion object {
        private const val TAG = "ScheduleMaintenance"
        private const val WORK_NAME = "prayer_lock_schedule_maintenance"

        /**
         * Register the repeating repair job.
         *
         * KEEP rather than REPLACE: replacing on every app start would reset
         * the period each time, so on a device opened daily the work would
         * never actually run.
         */
        fun enqueue(context: Context) {
            val request = PeriodicWorkRequestBuilder<ScheduleMaintenanceWorker>(
                REPEAT_INTERVAL_HOURS,
                TimeUnit.HOURS,
                // Flex window: lets Android batch this with other wakeups
                // instead of demanding its own.
                FLEX_INTERVAL_HOURS,
                TimeUnit.HOURS,
            )
                .setConstraints(
                    // No network or charging constraint: re-arming alarms is
                    // local work, and gating it on connectivity would mean an
                    // offline device — exactly the case this protects — never
                    // gets repaired.
                    Constraints.Builder().build()
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }

        private const val REPEAT_INTERVAL_HOURS = 6L
        private const val FLEX_INTERVAL_HOURS = 2L
    }
}
