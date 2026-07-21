package com.prayerlock.prayer_lock.blocking

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the interception decision.
 *
 * The emergency-allowlist cases here are safety-critical: a regression that
 * blocks the dialer could prevent someone reaching emergency services. They
 * run on the JVM with no emulator so they execute on every build.
 */
class BlockingPolicyTest {

    private val ownPackage = "com.prayerlock.prayer_lock"

    private fun policyFor(vararg blocked: String) =
        BlockingPolicy(blocked.toSet(), ownPackage)

    @Test
    fun `intercepts a blocked package`() {
        val policy = policyFor("com.instagram.android")
        assertTrue(policy.shouldIntercept("com.instagram.android"))
    }

    @Test
    fun `ignores a package that is not blocked`() {
        val policy = policyFor("com.instagram.android")
        assertFalse(policy.shouldIntercept("com.duolingo"))
    }

    @Test
    fun `never intercepts itself`() {
        // Would otherwise loop: the lock screen is itself a foreground activity.
        val policy = policyFor(ownPackage)
        assertFalse(policy.shouldIntercept(ownPackage))
    }

    @Test
    fun `handles null and blank package names`() {
        val policy = policyFor("com.instagram.android")
        assertFalse(policy.shouldIntercept(null))
        assertFalse(policy.shouldIntercept(""))
        assertFalse(policy.shouldIntercept("   "))
    }

    // -- Safety-critical: emergency access ---------------------------------

    @Test
    fun `never blocks the dialer even when explicitly listed`() {
        // A user must always be able to call for help, regardless of config.
        val policy = policyFor(
            "com.android.dialer",
            "com.google.android.dialer",
            "com.android.server.telecom",
        )
        assertFalse(policy.shouldIntercept("com.android.dialer"))
        assertFalse(policy.shouldIntercept("com.google.android.dialer"))
        assertFalse(policy.shouldIntercept("com.android.server.telecom"))
    }

    @Test
    fun `never blocks emergency apps`() {
        val policy = policyFor("com.android.emergency", "com.google.android.apps.safetyhub")
        assertFalse(policy.shouldIntercept("com.android.emergency"))
        assertFalse(policy.shouldIntercept("com.google.android.apps.safetyhub"))
    }

    @Test
    fun `never blocks settings so the user can always recover`() {
        val policy = policyFor("com.android.settings")
        assertFalse(policy.shouldIntercept("com.android.settings"))
    }

    @Test
    fun `never blocks messaging`() {
        // Emergency SMS is the only route for many deaf and hard-of-hearing
        // users, who cannot place a voice call.
        val policy = policyFor("com.google.android.apps.messaging")
        assertFalse(policy.shouldIntercept("com.google.android.apps.messaging"))
    }

    @Test
    fun `never blocks the system ui`() {
        val policy = policyFor("com.android.systemui")
        assertFalse(policy.shouldIntercept("com.android.systemui"))
    }

    // -- Launchers ---------------------------------------------------------

    @Test
    fun `never blocks known launchers`() {
        // Blocking home would read as a bricked phone, not a prayer reminder.
        val launchers = listOf(
            "com.google.android.apps.nexuslauncher",
            "com.android.launcher3",
            "com.sec.android.app.launcher",
            "com.miui.home",
            "com.oneplus.launcher",
        )
        val policy = BlockingPolicy(launchers.toSet(), ownPackage)
        launchers.forEach { assertFalse(it, policy.shouldIntercept(it)) }
    }

    @Test
    fun `never blocks packages with a launcher suffix`() {
        // Catches OEM launchers not in the known list.
        val policy = policyFor("com.unknown.oem.launcher")
        assertFalse(policy.shouldIntercept("com.unknown.oem.launcher"))
    }

    // -- Configuration behaviour -------------------------------------------

    @Test
    fun `an empty block list intercepts nothing`() {
        val policy = policyFor()
        assertFalse(policy.shouldIntercept("com.instagram.android"))
    }

    @Test
    fun `matching is exact and not a prefix match`() {
        // "com.instagram" must not block "com.instagram.android" or vice
        // versa; a prefix match would block unrelated apps by accident.
        val policy = policyFor("com.instagram.android")
        assertFalse(policy.shouldIntercept("com.instagram"))
        assertFalse(policy.shouldIntercept("com.instagram.android.extra"))
    }

    @Test
    fun `blocks several apps independently`() {
        val policy = policyFor(
            "com.instagram.android",
            "com.zhiliaoapp.musically",
            "com.netflix.mediaclient",
        )
        assertTrue(policy.shouldIntercept("com.instagram.android"))
        assertTrue(policy.shouldIntercept("com.zhiliaoapp.musically"))
        assertTrue(policy.shouldIntercept("com.netflix.mediaclient"))
        assertFalse(policy.shouldIntercept("com.spotify.music"))
    }
}
