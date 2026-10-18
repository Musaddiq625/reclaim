package com.reclaim.musaddiq625

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray
import java.io.File
import java.util.Calendar

/**
 * Watches foreground-app changes and blocks apps during their freeze
 * windows. Reads freeze_rules.json written by the Flutter side — the file
 * is the single source of truth, so rules keep working when the UI is dead.
 */
class FreezeService : AccessibilityService() {

    companion object {
        val snoozes = mutableMapOf<String, Long>()
        private const val SNOOZE_MS = 5 * 60 * 1000L

        fun snooze(context: Context, pkg: String) {
            snoozes[pkg] = System.currentTimeMillis() + SNOOZE_MS
            recordEvent(context, pkg)
        }

        /** Appends an unlock to freeze_events.json next to the rules file. */
        private fun recordEvent(context: Context, pkg: String) {
            try {
                val rulesPath = context
                    .getSharedPreferences("reclaim", Context.MODE_PRIVATE)
                    .getString("rules_file", null) ?: return
                val eventsFile = File(File(rulesPath).parentFile, "freeze_events.json")
                val arr = if (eventsFile.exists()) JSONArray(eventsFile.readText())
                          else JSONArray()
                arr.put(org.json.JSONObject().apply {
                    put("package", pkg)
                    put("at", System.currentTimeMillis())
                })
                // keep the newest 200 events
                val trimmed = JSONArray()
                for (i in maxOf(0, arr.length() - 200) until arr.length()) {
                    trimmed.put(arr.get(i))
                }
                eventsFile.writeText(trimmed.toString())
            } catch (_: Exception) { }
        }
    }

    private var rulesPath: String? = null
    private var rules: List<Rule> = emptyList()
    private var rulesFileMs = -1L

    data class Rule(val pkg: String, val startMin: Int, val endMin: Int) {
        fun covers(minuteOfDay: Int): Boolean =
            if (startMin <= endMin) minuteOfDay in startMin until endMin
            else minuteOfDay >= startMin || minuteOfDay < endMin // crosses midnight
    }

    override fun onServiceConnected() {
        rulesPath = getSharedPreferences("reclaim", Context.MODE_PRIVATE)
            .getString("rules_file", null)
        reloadRules(force = true)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // never block ourselves

        // Reload first — a rule file change clears stale snoozes, so a
        // re-enabled rule freezes immediately instead of honoring an
        // unlock the user just revoked.
        reloadRules()

        snoozes[pkg]?.let {
            if (System.currentTimeMillis() < it) return else snoozes.remove(pkg)
        }
        val now = Calendar.getInstance()
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val rule = rules.firstOrNull { it.pkg == pkg && it.covers(minute) } ?: return
        showBlocker(pkg, rule.endMin)
    }

    private fun reloadRules(force: Boolean = false) {
        val path = rulesPath ?: return
        val f = File(path)
        if (!f.exists()) { rules = emptyList(); return }
        if (!force && f.lastModified() == rulesFileMs) return
        rulesFileMs = f.lastModified()
        // Any rule change — toggle, edit, add, delete — expires all
        // active emergency unlocks so re-enabled apps freeze immediately.
        snoozes.clear()
        rules = try {
            val arr = JSONArray(f.readText())
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.getJSONObject(i)
                if (o.optBoolean("enabled", true))
                    Rule(o.getString("package"), o.getInt("startMin"), o.getInt("endMin"))
                else null
            }
        } catch (e: Exception) { emptyList() }
    }

    private fun showBlocker(pkg: String, untilMin: Int) {
        val i = Intent(this, BlockerActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("package", pkg)
            putExtra("untilMin", untilMin)
        }
        startActivity(i)
    }

    override fun onInterrupt() {}
}
