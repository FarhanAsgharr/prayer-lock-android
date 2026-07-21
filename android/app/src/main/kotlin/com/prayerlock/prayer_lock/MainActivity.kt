package com.prayerlock.prayer_lock

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import com.prayerlock.prayer_lock.blocking.AppBlockerService
import com.prayerlock.prayer_lock.blocking.LockScreenActivity
import com.prayerlock.prayer_lock.blocking.PermissionHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity and the Dart-to-native bridge for app blocking.
 *
 * Every method here is Android-only. The Dart side must never call these
 * without a platform check; `BlockingService` in Dart guards each call.
 */
class MainActivity : FlutterActivity() {

    /** Channel main.dart listens on for deep-link routes from the lock screen. */
    private var navigationChannel: MethodChannel? = null

    /** A route delivered before Flutter was ready to receive it. */
    private var pendingRoute: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Warm the lock screen's dedicated engine now, so the first
        // interception does not pay a cold-start cost while a blocked app is
        // already on screen.
        LockScreenActivity.warmUpEngine(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLOCKING_CHANNEL)
            .setMethodCallHandler { call, result -> handleMethodCall(call, result) }

        navigationChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAVIGATION_CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    // Flutter asks for any route it launched with. Answered
                    // once the router is ready, which may be after the intent
                    // arrived, so the route is buffered rather than lost.
                    if (call.method == "consumeInitialRoute") {
                        result.success(pendingRoute)
                        pendingRoute = null
                    } else {
                        result.notImplemented()
                    }
                }
            }

        // A route carried by the launching intent (cold start from the lock).
        intent?.getStringExtra(LockScreenActivity.EXTRA_INITIAL_ROUTE)?.let {
            pendingRoute = it
        }
    }

    /**
     * A route arriving while the app is already running (warm start from the
     * lock via REORDER_TO_FRONT). Pushed straight to Flutter if it is ready,
     * or buffered if not.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val route = intent.getStringExtra(LockScreenActivity.EXTRA_INITIAL_ROUTE)
            ?: return

        val channel = navigationChannel
        if (channel != null) {
            channel.invokeMethod("navigate", route)
        } else {
            pendingRoute = route
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPermissionStatus" ->
                result.success(PermissionHelper.permissionStatus(this))

            "requestUsageStatsPermission" -> {
                startActivity(PermissionHelper.usageStatsSettingsIntent())
                result.success(null)
            }

            "requestOverlayPermission" -> {
                startActivity(PermissionHelper.overlaySettingsIntent(this))
                result.success(null)
            }

            "requestDisableBatteryOptimization" -> {
                startActivity(PermissionHelper.batteryOptimizationIntent(this))
                result.success(null)
            }

            "getInstalledApps" -> result.success(installedLaunchableApps())

            // Reports whether res/raw/adhan exists, so the Dart layer can fall
            // back to the default notification sound instead of referencing a
            // missing resource — which the platform rejects outright.
            "hasAdhanSound" -> result.success(hasAdhanRawResource())

            "startLock" -> startLock(call, result)

            "stopLock" -> {
                startService(
                    Intent(this, AppBlockerService::class.java)
                        .setAction(AppBlockerService.ACTION_STOP_LOCK)
                )
                result.success(true)
            }

            "updateBlockedApps" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                startService(
                    Intent(this, AppBlockerService::class.java)
                        .setAction(AppBlockerService.ACTION_UPDATE_APPS)
                        .putStringArrayListExtra(
                            AppBlockerService.EXTRA_BLOCKED_PACKAGES,
                            ArrayList(packages),
                        )
                )
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun startLock(call: MethodCall, result: MethodChannel.Result) {
        // Refuse rather than start a lock that cannot actually enforce
        // anything. Silently running a no-op service would leave the user
        // believing they were protected.
        if (!PermissionHelper.hasUsageStatsPermission(this)) {
            result.error(
                "MISSING_USAGE_STATS",
                "Usage access permission has not been granted.",
                null,
            )
            return
        }
        if (!PermissionHelper.hasOverlayPermission(this)) {
            result.error(
                "MISSING_OVERLAY",
                "Display over other apps permission has not been granted.",
                null,
            )
            return
        }

        val packages = call.argument<List<String>>("packages") ?: emptyList()
        val prayerName = call.argument<String>("prayerName") ?: "prayer"

        val intent = Intent(this, AppBlockerService::class.java)
            .setAction(AppBlockerService.ACTION_START_LOCK)
            .putStringArrayListExtra(
                AppBlockerService.EXTRA_BLOCKED_PACKAGES,
                ArrayList(packages),
            )
            .putExtra(AppBlockerService.EXTRA_PRAYER_NAME, prayerName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        result.success(true)
    }

    /**
     * Whether a bundled adhan recording is present at res/raw/adhan.
     *
     * No recording ships by default: adhan recordings are generally
     * copyrighted by the muezzin or publisher, so one must be licensed and
     * added deliberately rather than assumed.
     */
    private fun hasAdhanRawResource(): Boolean =
        resources.getIdentifier("adhan", "raw", packageName) != 0

    /**
     * Launchable third-party apps, for the blocked-app picker.
     *
     * System apps are excluded: a user does not want to scroll past sixty OEM
     * components to find Instagram, and blocking system packages is either
     * useless or actively harmful.
     */
    private fun installedLaunchableApps(): List<Map<String, Any>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)

        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0L),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, 0)
        }

        return activities
            .mapNotNull { resolveInfo ->
                val appInfo = resolveInfo.activityInfo?.applicationInfo ?: return@mapNotNull null
                if (appInfo.packageName == packageName) return@mapNotNull null

                val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val isUpdatedSystemApp =
                    (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                // Keep updated system apps: Chrome ships preinstalled on many
                // devices but is exactly the kind of app users want blocked.
                if (isSystemApp && !isUpdatedSystemApp) return@mapNotNull null

                mapOf(
                    "packageName" to appInfo.packageName,
                    "appName" to packageManager.getApplicationLabel(appInfo).toString(),
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { (it["appName"] as String).lowercase() }
    }

    private companion object {
        const val BLOCKING_CHANNEL = "com.prayerlock/blocking"
        const val NAVIGATION_CHANNEL = "com.prayerlock/navigation"
    }
}
