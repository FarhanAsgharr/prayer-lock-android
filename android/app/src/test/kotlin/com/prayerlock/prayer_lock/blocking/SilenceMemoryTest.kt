package com.prayerlock.prayer_lock.blocking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The rules that keep a user's phone from being stranded on Do Not Disturb.
 *
 * Every test here describes a way the feature could fail badly rather than a
 * way it could work: silencing twice, restoring twice, a restore that throws,
 * a process killed mid-prayer. Those are the paths that leave someone unable
 * to hear a phone call, so they are the ones worth pinning down.
 */
class SilenceMemoryTest {

    /** SharedPreferences stands in as a plain map. */
    private class FakeStore : SilenceMemory.Store {
        val values = mutableMapOf<String, Any>()

        override fun readBoolean(key: String, fallback: Boolean): Boolean =
            values[key] as? Boolean ?: fallback

        override fun readInt(key: String, fallback: Int): Int =
            values[key] as? Int ?: fallback

        override fun write(active: Boolean, filter: Int, ringer: Int) {
            if (active) {
                values[SilenceMemory.KEY_ACTIVE] = true
                values[SilenceMemory.KEY_FILTER] = filter
                values[SilenceMemory.KEY_RINGER] = ringer
            } else {
                values.clear()
            }
        }
    }

    private val store = FakeStore()
    private val memory = SilenceMemory(store)

    // -- the ordinary path --------------------------------------------------

    @Test
    fun `records the state it was given`() {
        assertTrue(memory.remember(filter = 3, ringer = 1))

        val previous = memory.recall()
        assertEquals(3, previous?.interruptionFilter)
        assertEquals(1, previous?.ringerMode)
    }

    @Test
    fun `nothing to recall before anything is silenced`() {
        assertNull(memory.recall())
        assertFalse(memory.isActive)
    }

    @Test
    fun `forgetting leaves nothing behind`() {
        memory.remember(filter = 3, ringer = 1)
        memory.forget()

        assertFalse(memory.isActive)
        assertNull(memory.recall())
    }

    // -- the paths that would strand a phone --------------------------------

    @Test
    fun `a second silence does not overwrite the remembered state`() {
        // The phone was on "all notifications" when the first prayer silenced
        // it. A second silence sees the *silenced* filter — recording that
        // would make restore put the phone back to silent, permanently.
        memory.remember(filter = SilenceMemory.FILTER_ALL, ringer = 2)

        val accepted = memory.remember(filter = 2, ringer = 0)

        assertFalse("a second silence must be refused", accepted)
        assertEquals(SilenceMemory.FILTER_ALL, memory.recall()?.interruptionFilter)
        assertEquals(2, memory.recall()?.ringerMode)
    }

    @Test
    fun `restores a phone the user had already silenced to silent, not to loud`() {
        // The user had their own Do Not Disturb on before the prayer. Restoring
        // to "all" would unsilence a phone they deliberately silenced.
        memory.remember(filter = 2, ringer = 0)

        assertEquals(2, memory.recall()?.interruptionFilter)
        assertEquals(0, memory.recall()?.ringerMode)
    }

    @Test
    fun `recall does not clear, so a crash mid-restore keeps the record`() {
        memory.remember(filter = 3, ringer = 1)

        memory.recall()

        assertTrue("the record must survive a failed restore", memory.isActive)
        assertEquals(3, memory.recall()?.interruptionFilter)
    }

    @Test
    fun `a failed restore still forgets, so the next silence records properly`() {
        memory.remember(filter = 3, ringer = 1)
        // Restore threw; the controller calls forget() in its finally block.
        memory.forget()

        // Without the forget, this would be refused and the real state lost.
        assertTrue(memory.remember(filter = SilenceMemory.FILTER_ALL, ringer = 2))
        assertEquals(SilenceMemory.FILTER_ALL, memory.recall()?.interruptionFilter)
    }

    @Test
    fun `restoring twice is harmless`() {
        memory.remember(filter = 3, ringer = 1)
        memory.forget()

        assertNull(memory.recall())
        memory.forget()
        assertNull(memory.recall())
    }

    @Test
    fun `state survives a new instance over the same store`() {
        // The process is killed mid-prayer and the service is restarted. The
        // restore has to work from whatever landed on disk.
        memory.remember(filter = 3, ringer = 1)

        val afterRestart = SilenceMemory(store)

        assertTrue(afterRestart.isActive)
        assertEquals(3, afterRestart.recall()?.interruptionFilter)
    }

    @Test
    fun `falls back to unsilenced when the record is incomplete`() {
        // A partially written record — the flag landed, the values did not.
        // Guessing "all notifications" is the safe direction: it can unsilence
        // a phone that should have stayed quiet, which the user can fix, rather
        // than leaving one silent, which they may not notice for hours.
        store.values[SilenceMemory.KEY_ACTIVE] = true

        val previous = memory.recall()

        assertEquals(SilenceMemory.FILTER_ALL, previous?.interruptionFilter)
        assertEquals(SilenceMemory.RINGER_NORMAL, previous?.ringerMode)
    }
}
