package com.prayerlock.prayer_lock.blocking

/**
 * Remembers what the phone's sound state was before a prayer silenced it.
 *
 * Deliberately free of any Android import. The rule this encodes — record once,
 * restore exactly that, forget — is the part of silencing that can strand a
 * user's phone on Do Not Disturb if it is wrong, and it is worth being able to
 * test it directly rather than only through an emulator.
 *
 * [SilenceController] owns the framework calls; this owns the decision about
 * whether to make them and what to put back.
 */
class SilenceMemory(private val store: Store) {

    /** The handful of values this needs to persist. */
    interface Store {
        fun readBoolean(key: String, fallback: Boolean): Boolean
        fun readInt(key: String, fallback: Int): Int

        /**
         * Persist the state, or clear it when [active] is false.
         *
         * A single call rather than per-key writes: the flag and the values it
         * refers to must land together, or a process death between them would
         * leave a flag pointing at nothing.
         */
        fun write(active: Boolean, filter: Int, ringer: Int)
    }

    /** Whether a silence started by this app is currently in effect. */
    val isActive: Boolean get() = store.readBoolean(KEY_ACTIVE, false)

    /**
     * Record the state to return to, if we are not already silenced.
     *
     * Returns false when a silence is already active, in which case the caller
     * must not change anything: recording again would overwrite the real
     * previous state with the silenced one, and the eventual restore would put
     * the phone back to silent and leave it there.
     */
    fun remember(filter: Int, ringer: Int): Boolean {
        if (isActive) return false
        store.write(active = true, filter = filter, ringer = ringer)
        return true
    }

    /**
     * The state to restore, or null if nothing was silenced.
     *
     * Reading does not clear — the caller clears with [forget] once it has
     * acted, so a crash between the two leaves the record intact for the next
     * attempt rather than losing it.
     */
    fun recall(): Previous? {
        if (!isActive) return null
        return Previous(
            interruptionFilter = store.readInt(KEY_FILTER, FILTER_ALL),
            ringerMode = store.readInt(KEY_RINGER, RINGER_NORMAL),
        )
    }

    /**
     * Drop the record.
     *
     * Called even when restoring failed. A restore that could not complete must
     * not leave the flag set, or the next silence would believe it was already
     * active and decline to record the real state — one failure would then
     * quietly disable the feature for good.
     */
    fun forget() {
        store.write(active = false, filter = FILTER_ALL, ringer = RINGER_NORMAL)
    }

    /** The sound state to put back after a prayer. */
    data class Previous(val interruptionFilter: Int, val ringerMode: Int)

    companion object {
        const val KEY_ACTIVE = "silence_active"
        const val KEY_FILTER = "previous_filter"
        const val KEY_RINGER = "previous_ringer"

        /**
         * Mirrors of the two framework constants this falls back to, so the
         * class stays free of Android imports. Asserted against the real values
         * in [SilenceController], which does import them.
         */
        const val FILTER_ALL = 1
        const val RINGER_NORMAL = 2
    }
}
