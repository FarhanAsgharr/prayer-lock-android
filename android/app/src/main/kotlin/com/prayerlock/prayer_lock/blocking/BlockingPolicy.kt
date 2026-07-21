package com.prayerlock.prayer_lock.blocking

/**
 * Decides whether a foreground package should be intercepted.
 *
 * Kept as a pure class with no Android dependencies so it can be unit tested
 * on the JVM without an emulator. The service does I/O; this makes decisions.
 */
class BlockingPolicy(
    private val blockedPackages: Set<String>,
    private val ownPackageName: String,
) {

    /**
     * Packages that must never be blocked, so a locked-out user can always
     * reach emergency services.
     *
     * This is a deliberate hole in enforcement. A user who has spent their
     * emergency unlock must still be able to dial 999/911, and a user who
     * cannot reach Settings cannot recover from a misconfigured device. The
     * cost is that a determined user can technically reach a browser through
     * some of these; that trade is correct.
     */
    private val neverBlocked = setOf(
        // Dialer and telephony
        "com.android.dialer",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.android.server.telecom",
        "com.android.phone",
        "com.android.incallui",
        // Emergency
        "com.android.emergency",
        "com.google.android.apps.safetyhub",
        // System recovery paths
        "com.android.settings",
        "com.android.systemui",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        // Messaging is included because emergency SMS is a real access need
        // for deaf and hard-of-hearing users, who cannot use a voice call.
        "com.android.messaging",
        "com.google.android.apps.messaging",
    )

    fun shouldIntercept(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        // Never intercept ourselves, or we would loop: the lock screen is
        // itself a foreground activity.
        if (packageName == ownPackageName) return false
        if (packageName in neverBlocked) return false
        if (isLauncher(packageName)) return false
        return packageName in blockedPackages
    }

    /**
     * Home screens are never blocked.
     *
     * Blocking the launcher would leave the user with no way to navigate
     * anywhere, which reads as a bricked phone rather than a prayer reminder.
     */
    private fun isLauncher(packageName: String): Boolean =
        packageName in knownLaunchers || packageName.endsWith(".launcher")

    private companion object {
        val knownLaunchers = setOf(
            "com.google.android.apps.nexuslauncher",
            "com.android.launcher",
            "com.android.launcher3",
            "com.sec.android.app.launcher",
            "com.miui.home",
            "com.huawei.android.launcher",
            "com.oppo.launcher",
            "com.oneplus.launcher",
        )
    }
}
