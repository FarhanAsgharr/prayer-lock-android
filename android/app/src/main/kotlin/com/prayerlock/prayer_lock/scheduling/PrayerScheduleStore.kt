package com.prayerlock.prayer_lock.scheduling

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * The native side's own copy of today's prayer windows and blocking policy.
 *
 * Why this exists rather than asking Flutter:
 *
 * After a reboot, or after Android kills the app to reclaim memory, there is no
 * Flutter engine and no Dart isolate. An alarm still has to fire, decide whether
 * apps should be blocked, and act — without starting a Flutter engine, which
 * would cost seconds and might be killed again immediately. So everything the
 * decision needs is mirrored here, in plain SharedPreferences, and Dart pushes
 * an update whenever the schedule or the user's state changes.
 *
 * This mirror is deliberately *not* the source of truth. Dart owns the encrypted
 * database; this holds only what enforcement needs, and is overwritten wholesale
 * on every sync. Nothing here is sensitive on its own — it is a list of times
 * and package names, no prayer history and no verification record.
 *
 * All instants are epoch milliseconds in UTC. Wall-clock strings would break
 * across timezone changes and DST, which is exactly the case this must survive.
 */
class PrayerScheduleStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** One prayer's blocking window as the native side needs it. */
    data class Window(
        val prayer: String,
        val startsAt: Long,
        /** When the lock actually engages: start plus the grace period. */
        val engagesAt: Long,
        val endsAt: Long,
        /** End of the same-day qaza opportunity. */
        val qazaEndsAt: Long,
        /** Whether the user has already discharged this prayer. */
        val fulfilled: Boolean,
    ) {
        val durationMillis: Long get() = (endsAt - startsAt).coerceAtLeast(0)

        fun toJson(): JSONObject = JSONObject().apply {
            put(KEY_PRAYER, prayer)
            put(KEY_STARTS_AT, startsAt)
            put(KEY_ENGAGES_AT, engagesAt)
            put(KEY_ENDS_AT, endsAt)
            put(KEY_QAZA_ENDS_AT, qazaEndsAt)
            put(KEY_FULFILLED, fulfilled)
        }

        companion object {
            fun fromJson(json: JSONObject): Window = Window(
                prayer = json.optString(KEY_PRAYER, "prayer"),
                startsAt = json.optLong(KEY_STARTS_AT),
                engagesAt = json.optLong(KEY_ENGAGES_AT, json.optLong(KEY_STARTS_AT)),
                endsAt = json.optLong(KEY_ENDS_AT),
                qazaEndsAt = json.optLong(KEY_QAZA_ENDS_AT, json.optLong(KEY_ENDS_AT)),
                fulfilled = json.optBoolean(KEY_FULFILLED, false),
            )
        }
    }

    /** The full enforcement picture: windows plus the policy applied to them. */
    data class Schedule(
        val windows: List<Window>,
        val blockedPackages: Set<String>,
        val blockingEnabled: Boolean,
        /** "on_verification", "full_duration" or "earliest_of". */
        val unlockPolicy: String,
        val blockUntilQazaCompleted: Boolean,
        val morningProtectionEnabled: Boolean,
        val updatedAt: Long,
    ) {
        /**
         * The window that should be blocking at [now], or null.
         *
         * This is the native mirror of Dart's LockDecisionMaker. The two must
         * agree: if they disagree, a lock engaged by an alarm would be released
         * by the next Dart tick, and the user would watch apps flicker between
         * blocked and allowed. The rules are kept deliberately few so that
         * staying in agreement is tractable.
         */
        fun activeWindowAt(now: Long): Window? {
            if (!blockingEnabled || blockedPackages.isEmpty()) return null

            // Inside a prayer's own window.
            val current = windows.firstOrNull { now >= it.engagesAt && now < it.endsAt }
            if (current != null) {
                val holdsThroughDuration = unlockPolicy == POLICY_FULL_DURATION
                if (!current.fulfilled || holdsThroughDuration) return current
            }

            if (!blockUntilQazaCompleted) return null

            // An earlier prayer whose window closed unfulfilled and whose qaza
            // opportunity is still open. Oldest first: a user should clear the
            // oldest debt before the newest.
            return windows
                .filter { !it.fulfilled && now >= it.endsAt && now < it.qazaEndsAt }
                .minByOrNull { it.startsAt }
        }

        /**
         * Every future instant at which [activeWindowAt] could change its answer.
         *
         * These become the exact alarms. Derived from the same fields the
         * decision reads, so an alarm cannot be missing for a transition that
         * the decision would make.
         */
        fun transitionsAfter(now: Long): List<Long> {
            if (!blockingEnabled) return emptyList()

            val instants = sortedSetOf<Long>()
            for (window in windows) {
                instants.add(window.startsAt)
                instants.add(window.engagesAt)
                instants.add(window.endsAt)
                if (blockUntilQazaCompleted) instants.add(window.qazaEndsAt)
            }
            return instants.filter { it > now }
        }
    }

    /** Replace the stored schedule wholesale. */
    fun save(schedule: Schedule) {
        val windows = JSONArray()
        schedule.windows.forEach { windows.put(it.toJson()) }

        val payload = JSONObject().apply {
            put(KEY_WINDOWS, windows)
            put(KEY_PACKAGES, JSONArray(schedule.blockedPackages.toList()))
            put(KEY_BLOCKING_ENABLED, schedule.blockingEnabled)
            put(KEY_UNLOCK_POLICY, schedule.unlockPolicy)
            put(KEY_BLOCK_UNTIL_QAZA, schedule.blockUntilQazaCompleted)
            put(KEY_MORNING_PROTECTION, schedule.morningProtectionEnabled)
            put(KEY_UPDATED_AT, schedule.updatedAt)
        }

        // commit() rather than apply(): the caller is often about to schedule
        // alarms that a receiver will read back, possibly in another process
        // after a kill. An async write that has not landed yet would be read as
        // "no schedule" and enforcement would silently do nothing.
        prefs.edit().putString(KEY_SCHEDULE, payload.toString()).commit()
    }

    /** The stored schedule, or null if none has been synced yet. */
    fun load(): Schedule? {
        val raw = prefs.getString(KEY_SCHEDULE, null) ?: return null

        return try {
            val payload = JSONObject(raw)

            val windowsJson = payload.optJSONArray(KEY_WINDOWS) ?: JSONArray()
            val windows = (0 until windowsJson.length()).mapNotNull { index ->
                windowsJson.optJSONObject(index)?.let(Window::fromJson)
            }

            val packagesJson = payload.optJSONArray(KEY_PACKAGES) ?: JSONArray()
            val packages = (0 until packagesJson.length())
                .mapNotNull { packagesJson.optString(it).takeIf(String::isNotEmpty) }
                .toSet()

            Schedule(
                windows = windows.sortedBy { it.startsAt },
                blockedPackages = packages,
                blockingEnabled = payload.optBoolean(KEY_BLOCKING_ENABLED, true),
                unlockPolicy = payload.optString(KEY_UNLOCK_POLICY, POLICY_ON_VERIFICATION),
                blockUntilQazaCompleted = payload.optBoolean(KEY_BLOCK_UNTIL_QAZA, false),
                morningProtectionEnabled = payload.optBoolean(KEY_MORNING_PROTECTION, true),
                updatedAt = payload.optLong(KEY_UPDATED_AT),
            )
        } catch (error: Exception) {
            // A corrupted mirror must not crash a boot receiver. Discarding it
            // degrades to "no enforcement until Dart next syncs", which is
            // recoverable; a crash loop on every boot is not.
            Log.e(TAG, "Discarding corrupt schedule mirror", error)
            clear()
            null
        }
    }

    fun clear() {
        prefs.edit().remove(KEY_SCHEDULE).commit()
    }

    // -- clock integrity ----------------------------------------------------

    /**
     * Record the current wall clock against the monotonic clock.
     *
     * Used to detect the user winding the system clock back to escape a lock.
     * `elapsedRealtime` counts since boot and cannot be set by the user, so a
     * wall clock that has moved much less than the monotonic clock — or moved
     * backwards at all — indicates manipulation rather than the ordinary drift
     * of NTP correction.
     */
    fun recordClockCheckpoint(wallClock: Long, elapsedRealtime: Long) {
        prefs.edit()
            .putLong(KEY_WALL_CLOCK, wallClock)
            .putLong(KEY_ELAPSED_REALTIME, elapsedRealtime)
            .apply()
    }

    /**
     * How far the wall clock has been moved backwards relative to the monotonic
     * clock since the last checkpoint, in milliseconds. Zero when the clocks
     * agree, or when there is no checkpoint to compare against.
     *
     * A reboot resets `elapsedRealtime`, so a negative monotonic delta means
     * "rebooted", not "manipulated", and is reported as no drift.
     */
    fun backwardsClockDrift(wallClock: Long, elapsedRealtime: Long): Long {
        val lastWall = prefs.getLong(KEY_WALL_CLOCK, 0L)
        val lastElapsed = prefs.getLong(KEY_ELAPSED_REALTIME, 0L)
        if (lastWall == 0L || lastElapsed == 0L) return 0L

        val monotonicDelta = elapsedRealtime - lastElapsed
        if (monotonicDelta < 0) return 0L

        val wallDelta = wallClock - lastWall
        val drift = monotonicDelta - wallDelta
        return if (drift > CLOCK_DRIFT_TOLERANCE_MS) drift else 0L
    }

    companion object {
        private const val TAG = "PrayerScheduleStore"
        private const val PREFS_NAME = "prayer_lock_schedule"

        private const val KEY_SCHEDULE = "schedule"
        private const val KEY_WINDOWS = "windows"
        private const val KEY_PACKAGES = "packages"
        private const val KEY_BLOCKING_ENABLED = "blockingEnabled"
        private const val KEY_UNLOCK_POLICY = "unlockPolicy"
        private const val KEY_BLOCK_UNTIL_QAZA = "blockUntilQaza"
        private const val KEY_MORNING_PROTECTION = "morningProtection"
        private const val KEY_UPDATED_AT = "updatedAt"

        private const val KEY_PRAYER = "prayer"
        private const val KEY_STARTS_AT = "startsAt"
        private const val KEY_ENGAGES_AT = "engagesAt"
        private const val KEY_ENDS_AT = "endsAt"
        private const val KEY_QAZA_ENDS_AT = "qazaEndsAt"
        private const val KEY_FULFILLED = "fulfilled"

        private const val KEY_WALL_CLOCK = "lastWallClock"
        private const val KEY_ELAPSED_REALTIME = "lastElapsedRealtime"

        const val POLICY_ON_VERIFICATION = "on_verification"
        const val POLICY_FULL_DURATION = "full_duration"
        const val POLICY_EARLIEST_OF = "earliest_of"

        /**
         * Clock movement below this is treated as ordinary correction rather
         * than manipulation. NTP steps are typically well under a second;
         * two minutes leaves room for a slow device without letting a user
         * meaningfully skip a prayer window.
         */
        const val CLOCK_DRIFT_TOLERANCE_MS = 2 * 60 * 1000L
    }
}
