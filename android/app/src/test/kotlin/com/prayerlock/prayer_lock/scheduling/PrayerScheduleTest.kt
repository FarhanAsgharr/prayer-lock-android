package com.prayerlock.prayer_lock.scheduling

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the native side's blocking decision.
 *
 * This logic runs after a reboot, with no Flutter engine and no Dart isolate.
 * If it disagrees with the Dart implementation, the user sees apps flicker
 * between blocked and allowed as the two fight each other — so these tests pin
 * the same rules the Dart LockDecisionMaker tests pin.
 *
 * These are plain JVM tests: no emulator, so they run on every build rather
 * than only during an instrumented run.
 */
class PrayerScheduleTest {

    private val hour = 3_600_000L
    private val minute = 60_000L

    /** A day roughly matching the reference schedule, in epoch millis. */
    private fun window(
        prayer: String,
        startHour: Double,
        endHour: Double,
        graceMinutes: Long = 0,
        fulfilled: Boolean = false,
        qazaEndHour: Double? = null,
    ): PrayerScheduleStore.Window {
        val start = (startHour * hour).toLong()
        val end = (endHour * hour).toLong()
        return PrayerScheduleStore.Window(
            prayer = prayer,
            startsAt = start,
            engagesAt = start + graceMinutes * minute,
            endsAt = end,
            qazaEndsAt = qazaEndHour?.let { (it * hour).toLong() } ?: end,
            fulfilled = fulfilled,
        )
    }

    private fun schedule(
        windows: List<PrayerScheduleStore.Window>,
        packages: Set<String> = setOf("com.instagram.android"),
        blockingEnabled: Boolean = true,
        unlockPolicy: String = PrayerScheduleStore.POLICY_ON_VERIFICATION,
        blockUntilQaza: Boolean = false,
    ) = PrayerScheduleStore.Schedule(
        windows = windows.sortedBy { it.startsAt },
        blockedPackages = packages,
        blockingEnabled = blockingEnabled,
        unlockPolicy = unlockPolicy,
        blockUntilQazaCompleted = blockUntilQaza,
        morningProtectionEnabled = true,
        updatedAt = 0L,
    )

    /** Fajr 04:18-05:41, Dhuhr 12:17-15:54, Asr 15:54-19:12. */
    private fun referenceDay(
        graceMinutes: Long = 0,
        fulfilled: Set<String> = emptySet(),
    ) = schedule(
        listOf(
            window("fajr", 4.30, 5.68, graceMinutes, "fajr" in fulfilled, 28.30),
            window("dhuhr", 12.28, 15.90, graceMinutes, "dhuhr" in fulfilled, 28.30),
            window("asr", 15.90, 19.20, graceMinutes, "asr" in fulfilled, 28.30),
        ),
    )

    // -- active window ------------------------------------------------------

    @Test
    fun `blocks inside a window`() {
        val active = referenceDay().activeWindowAt((13 * hour))
        assertEquals("dhuhr", active?.prayer)
    }

    @Test
    fun `does not block before the window opens`() {
        assertNull(referenceDay().activeWindowAt((11 * hour)))
    }

    @Test
    fun `does not block in the gap between sunrise and Dhuhr`() {
        // The morning gap belongs to no prayer. Blocking through it would mean
        // apps are restricted for most of the morning.
        assertNull(referenceDay().activeWindowAt((8 * hour)))
    }

    @Test
    fun `releases exactly at the window end`() {
        // 15.90 hours is where Dhuhr ends and Asr begins.
        val boundary = (15.90 * hour).toLong()
        assertEquals("asr", referenceDay().activeWindowAt(boundary)?.prayer)
    }

    @Test
    fun `stays blocked deep into a long window`() {
        // Dhuhr runs over three and a half hours; the lock must not lapse.
        val lateInWindow = (15.80 * hour).toLong()
        assertEquals("dhuhr", referenceDay().activeWindowAt(lateInWindow)?.prayer)
    }

    @Test
    fun `respects the grace period`() {
        val withGrace = referenceDay(graceMinutes = 5)
        val start = (12.28 * hour).toLong()

        assertNull(withGrace.activeWindowAt(start + 2 * minute))
        assertEquals("dhuhr", withGrace.activeWindowAt(start + 5 * minute)?.prayer)
    }

    // -- policy -------------------------------------------------------------

    @Test
    fun `releases a fulfilled prayer under the verification policy`() {
        val done = referenceDay(fulfilled = setOf("dhuhr"))
        assertNull(done.activeWindowAt((13 * hour)))
    }

    @Test
    fun `holds a fulfilled prayer under the full-duration policy`() {
        val done = schedule(
            listOf(window("dhuhr", 12.28, 15.90, fulfilled = true)),
            unlockPolicy = PrayerScheduleStore.POLICY_FULL_DURATION,
        )
        assertEquals("dhuhr", done.activeWindowAt((13 * hour))?.prayer)
    }

    @Test
    fun `the full-duration policy still releases at the window end`() {
        val done = schedule(
            listOf(window("dhuhr", 12.28, 15.90, fulfilled = true)),
            unlockPolicy = PrayerScheduleStore.POLICY_FULL_DURATION,
        )
        assertNull(done.activeWindowAt((15.90 * hour).toLong()))
    }

    @Test
    fun `never blocks when blocking is disabled`() {
        assertNull(
            schedule(
                listOf(window("dhuhr", 12.28, 15.90)),
                blockingEnabled = false,
            ).activeWindowAt((13 * hour)),
        )
    }

    @Test
    fun `never blocks when no apps are selected`() {
        assertNull(
            schedule(
                listOf(window("dhuhr", 12.28, 15.90)),
                packages = emptySet(),
            ).activeWindowAt((13 * hour)),
        )
    }

    // -- qaza ---------------------------------------------------------------

    @Test
    fun `qaza enforcement is off by default`() {
        // A missed Fajr must not lock the phone until the following dawn
        // unless the user asked for exactly that.
        assertNull(referenceDay().activeWindowAt((8 * hour)))
    }

    @Test
    fun `qaza enforcement blocks past the window when enabled`() {
        val enforced = schedule(
            listOf(window("fajr", 4.30, 5.68, qazaEndHour = 28.30)),
            blockUntilQaza = true,
        )
        assertEquals("fajr", enforced.activeWindowAt((8 * hour))?.prayer)
    }

    @Test
    fun `qaza enforcement clears once the prayer is fulfilled`() {
        val enforced = schedule(
            listOf(
                window("fajr", 4.30, 5.68, fulfilled = true, qazaEndHour = 28.30),
            ),
            blockUntilQaza = true,
        )
        assertNull(enforced.activeWindowAt((8 * hour)))
    }

    @Test
    fun `the oldest outstanding qaza is resolved first`() {
        val enforced = schedule(
            listOf(
                window("fajr", 4.30, 5.68, qazaEndHour = 28.30),
                window("dhuhr", 12.28, 15.90, qazaEndHour = 28.30),
            ),
            blockUntilQaza = true,
        )
        // Both are outstanding at 16:00; the earlier debt is the one to clear.
        assertEquals("fajr", enforced.activeWindowAt((16 * hour))?.prayer)
    }

    @Test
    fun `an open window outranks an older qaza debt`() {
        val enforced = schedule(
            listOf(
                window("fajr", 4.30, 5.68, qazaEndHour = 28.30),
                window("dhuhr", 12.28, 15.90, qazaEndHour = 28.30),
            ),
            blockUntilQaza = true,
        )
        // Inside Dhuhr's window, Dhuhr is what is due — not the Fajr debt.
        assertEquals("dhuhr", enforced.activeWindowAt((13 * hour))?.prayer)
    }

    // -- transitions --------------------------------------------------------

    @Test
    fun `transitions cover every window start and end`() {
        val day = referenceDay()
        val transitions = day.transitionsAfter(0L)

        for (window in day.windows) {
            assertTrue(
                "missing start for ${window.prayer}",
                transitions.contains(window.startsAt),
            )
            assertTrue(
                "missing end for ${window.prayer}",
                transitions.contains(window.endsAt),
            )
        }
    }

    @Test
    fun `transitions are strictly in the future and ascending`() {
        val now = (13 * hour)
        val transitions = referenceDay().transitionsAfter(now)

        assertTrue(transitions.all { it > now })
        assertEquals(transitions.sorted(), transitions)
    }

    @Test
    fun `transitions are deduplicated at shared boundaries`() {
        // Dhuhr's end and Asr's start are the same instant; arming two alarms
        // for it would be a wasted wakeup.
        val transitions = referenceDay().transitionsAfter(0L)
        assertEquals(transitions.distinct().size, transitions.size)
    }

    @Test
    fun `transitions omit the qaza deadline when qaza is not enforced`() {
        val qazaEnd = (28.30 * hour).toLong()
        assertTrue(!referenceDay().transitionsAfter(0L).contains(qazaEnd))
    }

    @Test
    fun `transitions include the qaza deadline when qaza is enforced`() {
        val enforced = schedule(
            listOf(window("fajr", 4.30, 5.68, qazaEndHour = 28.30)),
            blockUntilQaza = true,
        )
        assertTrue(
            enforced.transitionsAfter(0L).contains((28.30 * hour).toLong()),
        )
    }

    @Test
    fun `transitions are empty when blocking is disabled`() {
        assertTrue(
            schedule(
                listOf(window("dhuhr", 12.28, 15.90)),
                blockingEnabled = false,
            ).transitionsAfter(0L).isEmpty(),
        )
    }

    @Test
    fun `an exhausted schedule yields no transitions`() {
        // The state that looks like "blocking stopped working for no reason".
        // It must be observable rather than silently indistinguishable from a
        // schedule that simply has nothing due yet.
        assertTrue(referenceDay().transitionsAfter(48 * hour).isEmpty())
    }

    // -- window arithmetic --------------------------------------------------

    @Test
    fun `duration is the span of the window`() {
        val dhuhr = window("dhuhr", 12.28, 15.90)
        assertEquals(((15.90 - 12.28) * hour).toLong(), dhuhr.durationMillis)
    }

    @Test
    fun `a backwards window reports zero duration rather than a negative one`() {
        // Defensive: a negative duration crossing the channel would produce a
        // notification chronometer counting up from a time in the past.
        val broken = PrayerScheduleStore.Window(
            prayer = "isha",
            startsAt = 10 * hour,
            engagesAt = 10 * hour,
            endsAt = 2 * hour,
            qazaEndsAt = 2 * hour,
            fulfilled = false,
        )
        assertEquals(0L, broken.durationMillis)
    }
}
