package com.prayerlock.prayer_lock.widget

/**
 * Chooses what the home-screen widget says.
 *
 * Free of any Android import so the choice can be tested on the JVM. The rules
 * look small but each one exists because the alternative reads badly on a
 * launcher: a widget is glanced at, and a line that is stale, empty, or wrong
 * is worse than no widget at all.
 *
 * [PrayerWidgetProvider] owns the RemoteViews; this owns the words.
 */
object WidgetContent {

    /** One prayer, as the widget needs it. */
    data class Window(
        val name: String,
        val startsAt: Long,
        val endsAt: Long,
        val isJumuah: Boolean,
        /** The mosque, on a Friday with one chosen. */
        val detail: String? = null,
    )

    /** The three lines the widget renders. */
    data class Lines(
        val prayer: String,
        val time: String,
        val detail: String,
    )

    /**
     * What to show at [now], given the mirrored windows.
     *
     * @param windows every known window, in any order
     * @param formatTime renders an instant as the user's clock format; injected
     *   because 12- vs 24-hour is a device setting the JVM cannot see
     */
    fun linesFor(
        windows: List<Window>,
        now: Long,
        formatTime: (Long) -> String,
    ): Lines {
        // Nothing synced yet, or every window is in the past and the daily
        // refresh has not run. Saying so beats showing yesterday's Fajr.
        val upcoming = windows.filter { it.endsAt > now }.minByOrNull { it.startsAt }
            ?: return Lines(
                prayer = "Prayer Lock",
                time = "",
                detail = "Open the app to refresh",
            )

        val current = upcoming.startsAt <= now

        return Lines(
            prayer = upcoming.name,
            time = formatTime(upcoming.startsAt),
            detail = detailFor(upcoming, now, current),
        )
    }

    private fun detailFor(window: Window, now: Long, current: Boolean): String {
        // A mosque name is the most useful thing a Friday widget can carry —
        // it is the one detail that differs between people.
        window.detail?.takeIf { it.isNotBlank() }?.let { mosque ->
            return if (current) "At $mosque · ${remaining(window.endsAt - now)} left"
            else "At $mosque"
        }

        if (current) return "${remaining(window.endsAt - now)} left"
        return "in ${remaining(window.startsAt - now)}"
    }

    /**
     * A duration in the coarsest useful unit.
     *
     * Never seconds: the widget only redraws at prayer boundaries, so a
     * seconds-precision countdown would be visibly frozen and wrong. Minutes
     * are honest at the refresh rate this actually has.
     */
    fun remaining(millis: Long): String {
        if (millis <= 0) return "0m"

        val totalMinutes = millis / 60_000
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60

        return when {
            hours == 0L -> "${minutes}m"
            minutes == 0L -> "${hours}h"
            else -> "${hours}h ${minutes}m"
        }
    }
}
