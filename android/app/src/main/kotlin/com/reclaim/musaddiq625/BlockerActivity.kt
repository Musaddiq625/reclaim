package com.reclaim.musaddiq625

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Full-screen block shown when a frozen app is opened. Covers the app
 * instantly — the only exits are home, or a 5-minute emergency unlock.
 */
class BlockerActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val pkg = intent.getStringExtra("package") ?: return finish()
        val untilMin = intent.getIntExtra("untilMin", 0)
        val label = try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(pkg, 0)
            ).toString()
        } catch (e: Exception) { pkg }
        val icon = try { packageManager.getApplicationIcon(pkg) } catch (e: Exception) { null }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(28), dp(28), dp(28))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.parseColor("#16182B"), Color.parseColor("#3A3B8F"))
            )
        }

        if (icon != null) {
            root.addView(ImageView(this).apply {
                setImageDrawable(icon)
                layoutParams = LinearLayout.LayoutParams(dp(72), dp(72))
            })
        }
        root.addView(TextView(this).apply {
            text = "$label is frozen"
            setTextColor(Color.WHITE)
            textSize = 24f
            gravity = Gravity.CENTER
            setPadding(0, dp(24), 0, dp(8))
        })
        root.addView(TextView(this).apply {
            text = "Frozen until ${fmtMin(untilMin)}\nYour experiment window is running."
            setTextColor(Color.parseColor("#B9BBE8"))
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(32))
        })
        root.addView(Button(this).apply {
            text = "Back to home"
            setOnClickListener { goHome() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        })
        root.addView(Button(this).apply {
            text = "Emergency unlock · 5 min"
            setTextColor(Color.parseColor("#8A8DBF"))
            setOnClickListener {
                FreezeService.snooze(this@BlockerActivity, pkg)
                finish()
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        })

        setContentView(root)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // refresh "until" label on re-block
        recreate()
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun fmtMin(min: Int): String {
        val h24 = min / 60
        val m = min % 60
        val suffix = if (h24 in 12..23) "pm" else "am"
        val h12 = when { h24 == 0 -> 12; h24 > 12 -> h24 - 12; else -> h24 }
        return String.format("%d:%02d %s", h12, m, suffix)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
