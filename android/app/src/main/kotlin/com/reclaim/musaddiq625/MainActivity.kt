package com.reclaim.musaddiq625

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "reclaim/freeze"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isServiceEnabled" -> result.success(isFreezeServiceEnabled())
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "setRulesFile" -> {
                        val path = call.argument<String>("path")
                        getSharedPreferences("reclaim", Context.MODE_PRIVATE)
                            .edit().putString("rules_file", path).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isFreezeServiceEnabled(): Boolean {
        val expected = ComponentName(this, FreezeService::class.java)
            .flattenToString()
        val am = getSystemService(Context.ACCESSIBILITY_SERVICE)
            as AccessibilityManager
        return am.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK
        ).any {
            it.resolveInfo.serviceInfo.packageName == expected.substringBefore('/') &&
                it.resolveInfo.serviceInfo.name == expected.substringAfter('/')
        }
    }
}
