package com.prayerlock.prayer_lock.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.text.format.DateFormat
import android.util.Log
import android.widget.RemoteViews
import com.prayerlock.prayer_lock.MainActivity
import com.prayerlock.prayer_lock.R
import java.util.Date

/**
 * The home-screen widget: the next prayer, and Jumu'ah with its mosque on
 * Fridays.
 *
 * ## Where its data comes from
 *
 * Not from Flutter. A widget is drawn by the launcher process, often while the
 * app is not running and sometimes before it has ever been opened since a
 * reboot, so starting a Flutter engine to render it is not an option. It reads
 * the same SharedPreferences mirror the alarm chain uses — written by Dart on
 * every schedule sync — which means the widget and the blocking service can
 * never disagree about when a prayer is.
 *
 * ## How it stays current
 *
 * `updatePeriodMillis` is 0 (see xml/prayer_widget_info.xml). Android's own
 * update mechanism is clamped to 30 minutes, which is both too coarse for a
 * countdown and not aligned to anything meaningful. Two things drive refreshes
 * instead:
 *
 *  * **Boundary alarms.** `PrayerAlarmReceiver` already wakes at every window
 *    transition, which is exactly when the *prayer being shown* changes.
 *  * **A ticking alarm, only while a widget is placed.** The boundaries alone
 *    are not enough: between Fajr closing and Dhuhr opening there can be six
 *    hours with no alarm, and a countdown that has not been redrawn in six
 *    hours is confidently wrong. [onEnabled] starts an inexact repeating alarm
 *    and [onDisabled] cancels it, so nothing ticks for a user who has no widget
 *    on their home screen.
 *
 * Inexact deliberately: the OS batches these with other wakeups, so the cost is
 * near zero, and a countdown that is a couple of minutes coarse is fine —
 * which is also why [WidgetContent] never renders seconds.
 */
class PrayerWidgetProvider : AppWidgetProvider() {

    /**
     * [ACTION_TICK] is our own action, which the base class does not know how
     * to dispatch — without this it would be delivered and silently ignored,
     * and the countdown would never move.
     */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TICK) {
            refresh(context)
            return
        }
        super.onReceive(context, intent)
    }

    /** The first widget was placed: start ticking. */
    override fun onEnabled(context: Context) {
        scheduleTick(context)
    }

    /** The last widget was removed: stop. */
    override fun onDisabled(context: Context) {
        cancelTick(context)
    }

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
    ) {
        widgetIds.forEach { render(context, manager, it) }

        // Re-armed here as well as in onEnabled. A repeating alarm does not
        // survive a reboot, and onEnabled only fires for the *first* widget —
        // so without this, a phone restarted overnight would have a widget that
        // never ticked again.
        scheduleTick(context)
    }

    private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val lines = try {
            WidgetContent.linesFor(
                windows = WidgetStore(context).windows(),
                now = System.currentTimeMillis(),
                // The device's own 12/24-hour setting. Formatting in Dart and
                // storing a string would freeze the choice at sync time and
                // survive the user changing it.
                formatTime = { instant ->
                    DateFormat.getTimeFormat(context).format(Date(instant))
                },
            )
        } catch (error: Exception) {
            // A widget that throws is removed from the home screen by some
            // launchers and is awkward to get back. Degrading to a placeholder
            // is always better than that.
            Log.e(TAG, "Falling back to placeholder", error)
            WidgetContent.Lines("Prayer Lock", "", "Open the app to refresh")
        }

        val views = RemoteViews(context.packageName, R.layout.prayer_widget).apply {
            setTextViewText(R.id.widget_prayer, lines.prayer)
            setTextViewText(R.id.widget_time, lines.time)
            setTextViewText(R.id.widget_detail, lines.detail)
            setOnClickPendingIntent(R.id.widget_prayer, launchIntent(context))
            setOnClickPendingIntent(R.id.widget_detail, launchIntent(context))
        }

        manager.updateAppWidget(widgetId, views)
    }

    private fun launchIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            // IMMUTABLE because nothing fills anything in: the intent opens the
            // app and nothing more. Required from API 31 regardless.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun scheduleTick(context: Context) {
        try {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            manager.setInexactRepeating(
                AlarmManager.RTC,
                System.currentTimeMillis() + TICK_INTERVAL_MS,
                TICK_INTERVAL_MS,
                tickIntent(context),
            )
        } catch (error: Exception) {
            // Losing the tick degrades the countdown, not the app. Boundary
            // alarms still keep the prayer itself correct.
            Log.w(TAG, "Could not schedule widget tick", error)
        }
    }

    private fun cancelTick(context: Context) {
        try {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            manager.cancel(tickIntent(context))
        } catch (error: Exception) {
            Log.w(TAG, "Could not cancel widget tick", error)
        }
    }

    private fun tickIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            TICK_REQUEST_CODE,
            Intent(context, PrayerWidgetProvider::class.java)
                .setAction(ACTION_TICK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    companion object {
        private const val TAG = "PrayerWidget"

        /** Our own action, so the tick is distinguishable in logs. */
        const val ACTION_TICK = "com.prayerlock.action.WIDGET_TICK"

        private const val TICK_REQUEST_CODE = 8801

        /**
         * How often the countdown is redrawn while a widget is placed.
         *
         * A minute would be precise and would also wake the device 1,440 times
         * a day for a line of text nobody is looking at. Ten minutes is coarse
         * enough to batch into wakeups that were happening anyway, and fine
         * enough that "1h 12m left" is never far off.
         */
        private const val TICK_INTERVAL_MS = 10 * 60 * 1000L

        /**
         * Redraw every placed widget.
         *
         * Safe and cheap to call when none exist — the id array comes back
         * empty and nothing happens — so callers do not need to know whether
         * the user has one on their home screen.
         */
        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context) ?: return
                val ids = manager.getAppWidgetIds(
                    ComponentName(context, PrayerWidgetProvider::class.java),
                )
                if (ids.isEmpty()) return

                context.sendBroadcast(
                    Intent(context, PrayerWidgetProvider::class.java)
                        .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
                )
            } catch (error: Exception) {
                // Called from an alarm receiver and from a method channel.
                // Neither should fail because a widget could not be redrawn.
                Log.w(TAG, "Widget refresh failed", error)
            }
        }
    }
}
