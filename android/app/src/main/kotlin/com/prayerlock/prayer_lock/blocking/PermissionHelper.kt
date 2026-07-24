package com.prayerlock.prayer_lock.blocking

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings

/**
 * Checks and requests the special permissions app blocking depends on.
 *
 * All three are "special access" permissions: they cannot be requested with a
 * normal runtime dialog and instead require sending the user into a specific
 * Settings screen. Blocking silently does nothing without them, so the app
 * must verify each one rather than assume it was granted.
 */
object PermissionHelper {

    /**
     * PACKAGE_USAGE_STATS — required to see which app is in the foreground.
     *
     * There is no direct API to query this permission, so it is inferred via
     * AppOpsManager, which is the documented approach.
     */
    fun hasUsageStatsPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager

        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }

        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** SYSTEM_ALERT_WINDOW — required to show the lock over other apps. */
    fun hasOverlayPermission(context: Context): Boolean =
        Settings.canDrawOverlays(context)

    /**
     * Whether battery optimisation is disabled for this app.
     *
     * Not strictly a permission, but with optimisation active the OS may
     * freeze the polling service, and blocking stops working with no visible
     * error. Aggressive OEM skins (Xiaomi, Huawei, Oppo, Samsung) are the
     * usual culprits, which is why this is surfaced to the user explicitly.
     */
    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val powerManager =
            context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun usageStatsSettingsIntent(): Intent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun overlaySettingsIntent(context: Context): Intent =
        Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * SCHEDULE_EXACT_ALARM — required for a lock that engages *at* the adhan.
     *
     * From Android 12 this is revocable, and from Android 13 apps that are not
     * alarm clocks or calendars are not granted it by default. Without it,
     * alarms are deferred by Doze and a prayer lock can engage twenty minutes
     * late — by which time the moment it existed for has passed.
     */
    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true

        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    /**
     * The settings screen for granting exact-alarm access, or null on versions
     * where the permission does not exist and the request would open nothing.
     */
    fun exactAlarmSettingsIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null

        return Intent(
            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    @Suppress("BatteryLife") // Justified: enforcement must survive Doze.
    fun batteryOptimizationIntent(context: Context): Intent =
        Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Every permission state in one call, for the setup checklist screen. */
    fun permissionStatus(context: Context): Map<String, Boolean> = mapOf(
        "usageStats" to hasUsageStatsPermission(context),
        "overlay" to hasOverlayPermission(context),
        "batteryOptimizationDisabled" to isIgnoringBatteryOptimizations(context),
        "exactAlarms" to canScheduleExactAlarms(context),
    )
}
