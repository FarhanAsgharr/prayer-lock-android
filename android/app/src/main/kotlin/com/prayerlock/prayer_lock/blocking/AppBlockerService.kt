package com.prayerlock.prayer_lock.blocking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.Log
import com.prayerlock.prayer_lock.MainActivity
import com.prayerlock.prayer_lock.R

/**
 * Foreground service that watches which app is in front and intercepts
 * blocked ones during an active prayer lock.
 *
 * Implementation notes, and why this approach rather than the obvious one:
 *
 * The obvious approach is an AccessibilityService, which gets window-change
 * events pushed to it. We deliberately do not use one as the primary
 * mechanism. Google Play's policy restricts AccessibilityService to genuine
 * accessibility use, and screen-time apps are routinely rejected or removed
 * for relying on it. Polling UsageStatsManager is less elegant and slightly
 * slower to react, but it is policy-compliant and will survive review.
 *
 * The service runs at a 700ms poll interval. That is a deliberate balance:
 * fast enough that a blocked app is intercepted before meaningful content is
 * consumed, slow enough that battery impact stays negligible. Android's own
 * Digital Wellbeing uses a comparable strategy.
 */
class AppBlockerService : Service() {

    private lateinit var usageStatsManager: UsageStatsManager
    private lateinit var workerThread: HandlerThread
    private lateinit var handler: Handler

    private var policy: BlockingPolicy = BlockingPolicy(emptySet(), "")
    private var isLockActive = false

    /**
     * When the current prayer window closes, as epoch milliseconds, or 0 when
     * the lock has no scheduled end.
     *
     * The alarm chain is the primary mechanism for releasing the lock. This is
     * a second, independent one: the poll loop is already running every 700ms,
     * so checking an integer comparison costs nothing, and it means a dropped
     * or deferred alarm cannot leave a user locked out past the end of a window.
     * Two mechanisms for *releasing* is the right asymmetry — the failure mode
     * of an over-eager release is mild, and of a stuck lock is severe.
     */
    private var lockEndsAtMillis = 0L

    /** The prayer this lock belongs to, for the notification text. */
    private var currentPrayerName = "prayer"

    /**
     * Timestamp of the last usage event we have already examined.
     *
     * Tracked so each poll queries only the new window of events rather than
     * re-scanning history, which would be both slow and would re-trigger on
     * events already handled.
     */
    private var lastEventTimestamp = 0L

    /** Guards against relaunching the lock screen while it is already up. */
    private var lastInterceptedPackage: String? = null
    private var lastInterceptAtMillis = 0L

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (isLockActive) {
                if (hasWindowExpired()) {
                    Log.i(TAG, "Window ended; releasing lock without waiting for the alarm")
                    stopLock()
                    return
                }

                try {
                    checkForegroundApp()
                } catch (error: Exception) {
                    // Never let a single failed poll kill the service; a
                    // dead service means blocking silently stops working.
                    Log.e(TAG, "Foreground check failed", error)
                }
            }
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    /**
     * Whether the prayer window this lock belongs to has closed.
     *
     * Deliberately one-directional: this can end a lock early relative to the
     * alarm, but never extend one. Extending on the strength of the wall clock
     * would hand a user who moves their clock forward a way to skip a window;
     * releasing on it only risks unblocking slightly early if the clock is
     * wrong, which the next alarm evaluation corrects.
     */
    private fun hasWindowExpired(): Boolean =
        lockEndsAtMillis > 0L && System.currentTimeMillis() >= lockEndsAtMillis

    override fun onCreate() {
        super.onCreate()
        usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        // Polling on a dedicated thread keeps the main thread free; a stutter
        // in the launcher animation would be attributed to our app.
        workerThread = HandlerThread("PrayerLockBlocker").apply { start() }
        handler = Handler(workerThread.looper)

        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_LOCK -> startLock(intent)
            ACTION_STOP_LOCK -> stopLock()
            ACTION_UPDATE_APPS -> updateBlockedApps(intent)
        }

        // START_STICKY so Android restarts the service if it is killed under
        // memory pressure. Without this, a low-memory event would silently
        // disable enforcement mid-prayer.
        return START_STICKY
    }

    private fun startLock(intent: Intent) {
        val blocked = intent.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES)
            ?.toSet()
            ?: emptySet()
        val prayerName = intent.getStringExtra(EXTRA_PRAYER_NAME) ?: "prayer"
        val endsAt = intent.getLongExtra(EXTRA_ENDS_AT, 0L)

        // A window that has already closed by the time the intent is delivered
        // — a deferred alarm, a slow boot — must not start a lock that would
        // then need its own release. Refusing here is simpler and cannot get
        // stuck.
        if (endsAt > 0L && System.currentTimeMillis() >= endsAt) {
            Log.i(TAG, "Ignoring start for $prayerName: window already closed")
            stopLock()
            return
        }

        policy = BlockingPolicy(blocked, packageName)
        isLockActive = true
        lockEndsAtMillis = endsAt
        currentPrayerName = prayerName
        lastEventTimestamp = System.currentTimeMillis()

        startForeground(NOTIFICATION_ID, buildNotification(prayerName, endsAt))
        handler.removeCallbacks(pollRunnable)
        handler.post(pollRunnable)

        Log.i(
            TAG,
            "Lock started for $prayerName with ${blocked.size} blocked apps" +
                if (endsAt > 0L) ", ending at $endsAt" else ", no scheduled end",
        )
    }

    private fun stopLock() {
        isLockActive = false
        lockEndsAtMillis = 0L
        handler.removeCallbacks(pollRunnable)
        lastInterceptedPackage = null

        // Dismiss any lock screen still showing, otherwise the user stays
        // trapped behind it after a successful verification.
        sendBroadcast(Intent(LockScreenActivity.ACTION_DISMISS_LOCK).setPackage(packageName))

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        Log.i(TAG, "Lock stopped")
    }

    private fun updateBlockedApps(intent: Intent) {
        val blocked = intent.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES)
            ?.toSet()
            ?: emptySet()
        policy = BlockingPolicy(blocked, packageName)
    }

    /**
     * Query usage events since the last poll and intercept if a blocked app
     * moved to the foreground.
     */
    private fun checkForegroundApp() {
        val now = System.currentTimeMillis()
        // Query a slightly wider window than strictly needed; UsageStats
        // event delivery lags by a few hundred milliseconds and a tight
        // window drops events.
        val events = usageStatsManager.queryEvents(lastEventTimestamp - QUERY_SLACK_MS, now)
        val event = UsageEvents.Event()

        var foregroundPackage: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                foregroundPackage = event.packageName
            }
        }
        lastEventTimestamp = now

        if (foregroundPackage == null) return

        if (policy.shouldIntercept(foregroundPackage)) {
            interceptApp(foregroundPackage, now)
        }
    }

    private fun interceptApp(packageName: String, now: Long) {
        // Debounce: without this, the poll fires repeatedly while the blocked
        // app is still technically foregrounded during the transition,
        // stacking multiple lock activities.
        val isRepeat = packageName == lastInterceptedPackage &&
            (now - lastInterceptAtMillis) < INTERCEPT_DEBOUNCE_MS
        if (isRepeat) return

        lastInterceptedPackage = packageName
        lastInterceptAtMillis = now

        val lockIntent = Intent(this, LockScreenActivity::class.java).apply {
            // NEW_TASK is required to start an activity from a service.
            // CLEAR_TOP and SINGLE_TOP prevent a stack of lock screens.
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra(LockScreenActivity.EXTRA_BLOCKED_PACKAGE, packageName)
        }
        startActivity(lockIntent)

        Log.i(TAG, "Intercepted $packageName")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Prayer Lock",
            // LOW so the persistent notification does not make a sound every
            // time the service starts; it is informational, not an alert.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows while apps are restricted during prayer"
            setShowBadge(false)
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(prayerName: String, endsAt: Long): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("It's time for $prayerName")
            .setContentText(notificationBody(endsAt))
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(openApp)
            .setOngoing(true)

        // A live countdown to the end of the window. Far more reassuring than a
        // static "apps are restricted": under dynamic durations the wait can be
        // hours, and a user who cannot see when it ends assumes it is broken.
        if (endsAt > 0L) {
            builder
                .setWhen(endsAt)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
        }

        return builder.build()
    }

    private fun notificationBody(endsAt: Long): String {
        if (endsAt <= 0L) return "Apps are restricted until you verify your prayer."

        val remaining = endsAt - System.currentTimeMillis()
        if (remaining <= 0L) return "This prayer's window has ended."

        val totalMinutes = remaining / 60_000L
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60

        val window = when {
            hours > 0 && minutes > 0 -> "${hours}h ${minutes}m"
            hours > 0 -> "${hours}h"
            else -> "${minutes}m"
        }

        return "Apps are restricted. $window left in this window."
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        workerThread.quitSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "AppBlockerService"

        const val ACTION_START_LOCK = "com.prayerlock.action.START_LOCK"
        const val ACTION_STOP_LOCK = "com.prayerlock.action.STOP_LOCK"
        const val ACTION_UPDATE_APPS = "com.prayerlock.action.UPDATE_APPS"

        const val EXTRA_BLOCKED_PACKAGES = "blocked_packages"
        const val EXTRA_PRAYER_NAME = "prayer_name"

        /** Epoch millis at which the prayer window closes. 0 means unbounded. */
        const val EXTRA_ENDS_AT = "ends_at"

        private const val CHANNEL_ID = "prayer_lock_service"
        private const val NOTIFICATION_ID = 4711

        /** Balance between interception latency and battery drain. */
        private const val POLL_INTERVAL_MS = 700L

        /** UsageStats event delivery lags; widen the query window to match. */
        private const val QUERY_SLACK_MS = 1500L

        /** Suppress repeat interceptions of the same app within this window. */
        private const val INTERCEPT_DEBOUNCE_MS = 1200L
    }
}
