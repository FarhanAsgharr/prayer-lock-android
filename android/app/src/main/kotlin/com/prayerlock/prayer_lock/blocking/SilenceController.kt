package com.prayerlock.prayer_lock.blocking

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioManager
import android.provider.Settings
import android.util.Log

/**
 * Silences the phone for the duration of a prayer, and puts it back afterwards.
 *
 * ## Why this is more careful than it looks
 *
 * Silencing someone's phone is an intrusive thing for an app to do, and getting
 * the *restore* wrong is far worse than never silencing at all — a user who
 * misses a call from their family because a prayer app left Do Not Disturb on
 * will uninstall, and they would be right to.
 *
 * So:
 *
 *  * The previous state is **recorded before** anything changes, and restore
 *    puts back exactly what was there — not "off", which would unsilence a
 *    phone the user had silenced themselves.
 *  * The record lives in SharedPreferences, not memory, so a restore still
 *    works after the process is killed mid-prayer.
 *  * Restore is attempted on every lock release, including releases caused by
 *    a crash-recovery path, so there is no route that leaves DND stuck on.
 *  * Nothing happens at all without the user granting notification-policy
 *    access, which is a Settings screen they must visit deliberately.
 *
 * ## Interruption filter, not ringer mode alone
 *
 * Setting the ringer to silent is not enough on modern Android: alarms and
 * media still sound. `INTERRUPTION_FILTER_PRIORITY` is what actually quietens a
 * phone, and it is the one that needs the special permission.
 */
object SilenceController {

    private const val TAG = "SilenceController"
    private const val PREFS = "prayer_lock_silence"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * The state machine, backed by SharedPreferences.
     *
     * Not memory: a restore still has to work after the process is killed
     * mid-prayer, which is exactly when leaving Do Not Disturb on would do the
     * most damage.
     */
    private fun memory(context: Context): SilenceMemory =
        SilenceMemory(object : SilenceMemory.Store {
            override fun readBoolean(key: String, fallback: Boolean): Boolean =
                prefs(context).getBoolean(key, fallback)

            override fun readInt(key: String, fallback: Int): Int =
                prefs(context).getInt(key, fallback)

            override fun write(active: Boolean, filter: Int, ringer: Int) {
                val editor = prefs(context).edit()
                if (active) {
                    editor.putBoolean(SilenceMemory.KEY_ACTIVE, true)
                        .putInt(SilenceMemory.KEY_FILTER, filter)
                        .putInt(SilenceMemory.KEY_RINGER, ringer)
                } else {
                    editor.remove(SilenceMemory.KEY_ACTIVE)
                        .remove(SilenceMemory.KEY_FILTER)
                        .remove(SilenceMemory.KEY_RINGER)
                }
                // commit() rather than apply(): the caller is about to change
                // the phone's sound state, and an async write that has not
                // landed when the process dies would lose the only record of
                // what to put back.
                editor.commit()
            }
        })

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /**
     * Whether the user has granted the access this needs.
     *
     * Cannot be requested with a runtime dialog — it is a Settings screen, so
     * the app has to explain why and send the user there.
     */
    fun canSilence(context: Context): Boolean =
        notificationManager(context).isNotificationPolicyAccessGranted

    /** The Settings screen where the access is granted. */
    fun policyAccessIntent(): Intent =
        Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * Quieten the phone, remembering what it was doing first.
     *
     * A no-op when the permission is absent, or when a silence is already
     * active. See [SilenceMemory.remember] for why the second case matters.
     */
    fun silence(context: Context) {
        if (!canSilence(context)) {
            Log.i(TAG, "Notification policy access not granted; not silencing")
            return
        }

        val manager = notificationManager(context)
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val previousFilter = manager.currentInterruptionFilter
        val previousRinger = audio.ringerMode

        val memory = memory(context)
        if (!memory.remember(previousFilter, previousRinger)) {
            Log.i(TAG, "Already silenced; leaving the remembered state alone")
            return
        }

        try {
            manager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
            Log.i(TAG, "Silenced (was filter=$previousFilter ringer=$previousRinger)")
        } catch (error: SecurityException) {
            // The permission can be revoked between the check and the call.
            // Forget the record so a later restore does not act on a change
            // that never happened.
            Log.w(TAG, "Refused to set interruption filter", error)
            memory.forget()
        }
    }

    /**
     * Put the phone back exactly as it was.
     *
     * Safe to call when nothing was silenced — it returns immediately, which is
     * what lets every lock-release path call it unconditionally.
     */
    fun restore(context: Context) {
        val memory = memory(context)
        val previous = memory.recall() ?: return

        try {
            if (canSilence(context)) {
                notificationManager(context)
                    .setInterruptionFilter(previous.interruptionFilter)
                Log.i(TAG, "Restored interruption filter to ${previous.interruptionFilter}")
            } else {
                // Permission revoked while silenced. Nothing can be done about
                // the filter, and saying so is better than failing quietly —
                // the user will notice a silent phone and needs the log to
                // explain it.
                Log.w(TAG, "Cannot restore: notification policy access revoked")
            }
        } catch (error: SecurityException) {
            Log.w(TAG, "Refused to restore interruption filter", error)
        } finally {
            memory.forget()
        }
    }

    /** Whether a silence started by this app is currently in effect. */
    fun isSilenced(context: Context): Boolean = memory(context).isActive

    init {
        // The mirrors in SilenceMemory exist so it can stay free of Android
        // imports and be tested on the JVM. If the platform ever changed these
        // values, a restore would put the phone into the wrong mode, so the
        // assumption is checked rather than trusted.
        require(SilenceMemory.FILTER_ALL == NotificationManager.INTERRUPTION_FILTER_ALL) {
            "INTERRUPTION_FILTER_ALL changed value"
        }
        require(SilenceMemory.RINGER_NORMAL == AudioManager.RINGER_MODE_NORMAL) {
            "RINGER_MODE_NORMAL changed value"
        }
    }
}
