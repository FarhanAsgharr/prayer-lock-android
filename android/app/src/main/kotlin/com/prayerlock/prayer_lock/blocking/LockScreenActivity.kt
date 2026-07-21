package com.prayerlock.prayer_lock.blocking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.core.content.ContextCompat
import com.prayerlock.prayer_lock.MainActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Full-screen prayer reminder shown when a blocked app is opened.
 *
 * Rendered with Flutter rather than native views so the lock screen shares the
 * app's design system and localisation, and so the prayer copy lives in one
 * place.
 *
 * A dedicated cached FlutterEngine is used rather than the main one. Sharing
 * the main engine would tear the user's place in the app out from under them
 * every time the lock appeared.
 */
class LockScreenActivity : FlutterActivity() {

    private var dismissReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        showOverLockScreenAndTurnScreenOn()
        interceptBackNavigation()
        registerDismissReceiver()

        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
        if (messenger != null) {
            val channel = MethodChannel(messenger, LOCK_CHANNEL)

            // Tell the Flutter side which app triggered this, so the copy can
            // be specific rather than generic.
            intent.getStringExtra(EXTRA_BLOCKED_PACKAGE)?.let { blockedPackage ->
                channel.invokeMethod("onAppBlocked", mapOf("package" to blockedPackage))
            }

            // Handle the lock screen's actions. The lock runs in its own
            // engine and cannot drive the main app's navigation directly, so
            // "complete" and "emergency unlock" are handed back to the native
            // layer, which opens the main app on the right screen and closes
            // this lock.
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openVerification" -> {
                        openMainApp(call.argument<String>("route"))
                        finishAndRemoveTask()
                        result.success(true)
                    }
                    "dismiss" -> {
                        finishAndRemoveTask()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Bring the main app forward, optionally on a specific route.
     *
     * REORDER_TO_FRONT reuses the existing main task rather than starting a
     * second copy, so the user keeps their place and the router state is not
     * reset.
     */
    private fun openMainApp(route: String?) {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )
            if (route != null) putExtra(EXTRA_INITIAL_ROUTE, route)
        }
        startActivity(intent)
    }

    /**
     * Display above the keyguard and wake the screen.
     *
     * Needed for the Fajr case specifically: the phone is typically locked and
     * asleep, and a reminder the user cannot see is not a reminder.
     */
    private fun showOverLockScreenAndTurnScreenOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    /**
     * Swallow the back gesture.
     *
     * Deliberately does *not* trap the user: Home and the emergency allowlist
     * both still work, and the Flutter UI always offers an emergency unlock.
     * Blocking back only prevents the reflexive dismissal that would make the
     * reminder meaningless.
     *
     * Two code paths are required. FlutterActivity extends plain
     * android.app.Activity rather than androidx ComponentActivity, so
     * `onBackPressedDispatcher` is unavailable. On Android 13+ the predictive
     * back API must be used, because overriding onBackPressed() alone is
     * ignored once the app opts into predictive back.
     */
    private fun interceptBackNavigation() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return

        // Built as a local so the type is non-null at the registration call,
        // then retained for unregistration.
        val callback = OnBackInvokedCallback { /* Intentionally ignored. */ }
        backInvokedCallback = callback

        onBackInvokedDispatcher.registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            callback,
        )
    }

    /** Retained so it can be unregistered in onDestroy. */
    private var backInvokedCallback: OnBackInvokedCallback? = null

    @Deprecated("Required for Android 12 and below, where predictive back does not exist.")
    @Suppress("DEPRECATION", "MissingSuperCall")
    override fun onBackPressed() {
        // Intentionally does not call super: back must not dismiss the prayer
        // reminder. Home and emergency access remain available.
    }

    private fun registerDismissReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                finishAndRemoveTask()
            }
        }
        dismissReceiver = receiver

        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(ACTION_DISMISS_LOCK),
            // Not exported: only our own service may dismiss the lock, or any
            // installed app could broadcast its way past the restriction.
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun getCachedEngineId(): String = LOCK_ENGINE_ID

    override fun onDestroy() {
        dismissReceiver?.let { unregisterReceiver(it) }
        dismissReceiver = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backInvokedCallback?.let {
                onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it)
            }
        }
        super.onDestroy()
    }

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
        const val EXTRA_INITIAL_ROUTE = "initial_route"
        const val ACTION_DISMISS_LOCK = "com.prayerlock.action.DISMISS_LOCK"
        const val LOCK_CHANNEL = "com.prayerlock/lock_screen"

        private const val LOCK_ENGINE_ID = "prayer_lock_screen_engine"

        /**
         * Warm the dedicated engine at app start.
         *
         * Cold-starting a Flutter engine takes hundreds of milliseconds, which
         * on the lock path would show the blocked app's content before the
         * reminder appeared — defeating the purpose.
         */
        fun warmUpEngine(context: Context) {
            if (FlutterEngineCache.getInstance().contains(LOCK_ENGINE_ID)) return

            val engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    io.flutter.FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "lockScreenMain",
                ),
            )
            FlutterEngineCache.getInstance().put(LOCK_ENGINE_ID, engine)
        }
    }
}
