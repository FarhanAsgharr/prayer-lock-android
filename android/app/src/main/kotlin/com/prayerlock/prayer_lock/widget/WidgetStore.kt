package com.prayerlock.prayer_lock.widget

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * The widget's own copy of what to display.
 *
 * Separate from `PrayerScheduleStore` on purpose. That mirror holds what
 * *enforcement* needs — wire ids, grace periods, qaza deadlines — and nothing
 * a person would read. The widget needs the opposite: display names, a mosque,
 * a Jumu'ah flag, and none of the policy. Sharing one blob would mean every
 * change to either concern risked breaking the other.
 *
 * Written by Dart on each schedule sync, covering the same horizon, so the
 * widget keeps working for days without the app being opened.
 */
class WidgetStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Replace the stored windows wholesale. */
    fun save(windows: List<WidgetContent.Window>) {
        val array = JSONArray()
        windows.forEach { window ->
            array.put(
                JSONObject().apply {
                    put(KEY_NAME, window.name)
                    put(KEY_STARTS_AT, window.startsAt)
                    put(KEY_ENDS_AT, window.endsAt)
                    put(KEY_IS_JUMUAH, window.isJumuah)
                    window.detail?.let { put(KEY_DETAIL, it) }
                },
            )
        }

        // commit(): a widget refresh is broadcast immediately after this, and
        // may be handled before an async write would have landed — which would
        // redraw the widget with the previous schedule.
        prefs.edit().putString(KEY_WINDOWS, array.toString()).commit()
    }

    /** The stored windows, or empty when nothing has been synced. */
    fun windows(): List<WidgetContent.Window> {
        val raw = prefs.getString(KEY_WINDOWS, null) ?: return emptyList()

        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val json = array.optJSONObject(index) ?: return@mapNotNull null
                WidgetContent.Window(
                    name = json.optString(KEY_NAME, "Prayer"),
                    startsAt = json.optLong(KEY_STARTS_AT),
                    endsAt = json.optLong(KEY_ENDS_AT),
                    isJumuah = json.optBoolean(KEY_IS_JUMUAH, false),
                    detail = json.optString(KEY_DETAIL).takeIf { it.isNotEmpty() },
                )
            }
        } catch (error: Exception) {
            // Corrupt data degrades to the placeholder rather than crashing a
            // launcher-hosted view.
            Log.e(TAG, "Discarding corrupt widget data", error)
            clear()
            emptyList()
        }
    }

    fun clear() {
        prefs.edit().remove(KEY_WINDOWS).commit()
    }

    private companion object {
        const val TAG = "WidgetStore"
        const val PREFS = "prayer_lock_widget"

        const val KEY_WINDOWS = "windows"
        const val KEY_NAME = "name"
        const val KEY_STARTS_AT = "startsAt"
        const val KEY_ENDS_AT = "endsAt"
        const val KEY_IS_JUMUAH = "isJumuah"
        const val KEY_DETAIL = "detail"
    }
}
