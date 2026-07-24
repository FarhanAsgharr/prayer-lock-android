package com.prayerlock.prayer_lock.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the home-screen widget says.
 *
 * A widget is glanced at rather than read, and it only redraws at prayer
 * boundaries, so the failure worth guarding against is not an ugly string —
 * it is a confidently wrong one: yesterday's prayer, a frozen countdown, or a
 * blank card that looks like the app has broken.
 */
class WidgetContentTest {

    private val hour = 3_600_000L
    private val minute = 60_000L

    /** Fixed so the tests do not depend on the device's clock format. */
    private val format: (Long) -> String = { instant -> "T$instant" }

    private fun window(
        name: String,
        startsAt: Long,
        endsAt: Long,
        isJumuah: Boolean = false,
        detail: String? = null,
    ) = WidgetContent.Window(name, startsAt, endsAt, isJumuah, detail)

    private fun lines(windows: List<WidgetContent.Window>, now: Long) =
        WidgetContent.linesFor(windows, now, format)

    // -- choosing which prayer to show --------------------------------------

    @Test
    fun `shows the prayer that is currently open`() {
        val result = lines(
            listOf(
                window("Fajr", 0, 2 * hour),
                window("Dhuhr", 6 * hour, 9 * hour),
            ),
            now = hour,
        )

        assertEquals("Fajr", result.prayer)
        assertEquals("T0", result.time)
        assertTrue(result.detail.contains("1h left"))
    }

    @Test
    fun `shows the next prayer once the current one has closed`() {
        val result = lines(
            listOf(
                window("Fajr", 0, 2 * hour),
                window("Dhuhr", 6 * hour, 9 * hour),
            ),
            now = 3 * hour,
        )

        assertEquals("Dhuhr", result.prayer)
        assertEquals("in 3h", result.detail)
    }

    @Test
    fun `never shows a window that has already ended`() {
        // The bug this guards: a widget still advertising Fajr at midday
        // because the list happened to be ordered that way.
        val result = lines(
            listOf(
                window("Dhuhr", 6 * hour, 9 * hour),
                window("Fajr", 0, 2 * hour),
            ),
            now = 7 * hour,
        )

        assertEquals("Dhuhr", result.prayer)
    }

    @Test
    fun `picks the earliest of several upcoming windows`() {
        val result = lines(
            listOf(
                window("Isha", 20 * hour, 24 * hour),
                window("Maghrib", 18 * hour, 20 * hour),
                window("Asr", 15 * hour, 18 * hour),
            ),
            now = 10 * hour,
        )

        assertEquals("Asr", result.prayer)
    }

    // -- Jumu'ah ------------------------------------------------------------

    @Test
    fun `carries the mosque on a Friday`() {
        val result = lines(
            listOf(
                window(
                    "Jumu'ah",
                    6 * hour,
                    9 * hour,
                    isJumuah = true,
                    detail = "University Mosque",
                ),
            ),
            now = hour,
        )

        assertEquals("Jumu'ah", result.prayer)
        assertEquals("At University Mosque", result.detail)
    }

    @Test
    fun `shows the mosque and the time left once Jumu'ah has started`() {
        val result = lines(
            listOf(
                window(
                    "Jumu'ah",
                    0,
                    2 * hour,
                    isJumuah = true,
                    detail = "University Mosque",
                ),
            ),
            now = 30 * minute,
        )

        assertEquals("At University Mosque · 1h 30m left", result.detail)
    }

    @Test
    fun `ignores a blank mosque rather than printing an empty line`() {
        val result = lines(
            listOf(window("Jumu'ah", 6 * hour, 9 * hour, isJumuah = true, detail = "  ")),
            now = hour,
        )

        assertEquals("in 5h", result.detail)
    }

    // -- the empty and broken cases -----------------------------------------

    @Test
    fun `asks the user to open the app when nothing has been synced`() {
        val result = lines(emptyList(), now = hour)

        assertEquals("Prayer Lock", result.prayer)
        assertEquals("", result.time)
        assertTrue(result.detail.isNotEmpty())
    }

    @Test
    fun `asks the user to open the app when every window is stale`() {
        // The daily refresh has not run — better to say so than to show a
        // prayer that finished yesterday.
        val result = lines(
            listOf(window("Isha", 20 * hour, 24 * hour)),
            now = 30 * hour,
        )

        assertEquals("Prayer Lock", result.prayer)
        assertTrue(result.detail.contains("refresh"))
    }

    // -- durations ----------------------------------------------------------

    @Test
    fun `formats durations in the coarsest useful unit`() {
        assertEquals("45m", WidgetContent.remaining(45 * minute))
        assertEquals("2h", WidgetContent.remaining(2 * hour))
        assertEquals("1h 22m", WidgetContent.remaining(hour + 22 * minute))
    }

    @Test
    fun `never renders a negative duration`() {
        // A widget redrawn a moment after a window closed, before the alarm
        // that would have moved it on. "-3m left" would look broken.
        assertEquals("0m", WidgetContent.remaining(-3 * minute))
        assertEquals("0m", WidgetContent.remaining(0))
    }

    @Test
    fun `rounds down to whole minutes rather than showing seconds`() {
        assertEquals("5m", WidgetContent.remaining(5 * minute + 59_000))
    }
}
