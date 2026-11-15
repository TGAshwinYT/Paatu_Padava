package com.tamilgaming.paatupadava

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceActivity() {
    private val BATTERY_CHANNEL = "com.tamilgaming.paatupadava/battery"
    private val WIDGET_CHANNEL = "com.tamilgaming.paatupadava/widget"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ensure audio notification channel priority is IMPORTANCE_LOW to avoid alert vibrations
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
            if (notificationManager != null) {
                val channel = android.app.NotificationChannel(
                    "com.paatupaadava.music.channel.audio",
                    "Paatu Padava Playback",
                    android.app.NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Background music playback controls"
                    setShowBadge(false)
                    enableVibration(false)
                    enableLights(false)
                }
                notificationManager.createNotificationChannel(channel)
            }
        }
        // Request POST_NOTIFICATIONS runtime permission on Android 13+ (API 33+) on launch
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1002)
            }
        }

        // Battery optimization & system device connection channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1002)
                        }
                        result.success(granted)
                    } else {
                        result.success(true)
                    }
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER ?: "")
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && powerManager != null) {
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }
                "detachForeground" -> {
                    result.success(true)
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        val intent = Intent()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            intent.action = Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                        } else {
                            intent.action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                            intent.data = Uri.parse("package:$packageName")
                        }
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.success(false)
                        }
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openCastSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_CAST_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                            result.success(true)
                        } else {
                            val fallback = Intent(Settings.ACTION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(fallback)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Home screen AppWidget synchronization channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val title = call.argument<String>("title")
                    val artist = call.argument<String>("artist")
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val coverBytes = call.argument<ByteArray>("coverBytes")
                    MusicWidgetProvider.updateAllWidgets(applicationContext, title, artist, isPlaying, coverBytes)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
