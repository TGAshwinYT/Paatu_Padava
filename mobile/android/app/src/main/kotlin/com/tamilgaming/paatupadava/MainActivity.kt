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
    private val EQUALIZER_CHANNEL = "com.tamilgaming.paatupadava/equalizer"
    private val SYNC_CHANNEL_ID = "com.paatupaadava.music.channel.sync"
    private val SYNC_NOTIFICATION_ID = 2001
    private var dataSyncWakeLock: PowerManager.WakeLock? = null
    private lateinit var audioDspBridge: AudioDspBridge

    private fun updateSyncNotification(title: String, message: String, progress: Int, max: Int) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager ?: return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(applicationContext, SYNC_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(applicationContext)
        }
        val appIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.stat_sys_download
        builder.setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(appIcon)
            .setOngoing(true)
            .setAutoCancel(false)
        if (max > 0) {
            builder.setProgress(max, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        notificationManager.notify(SYNC_NOTIFICATION_ID, builder.build())
    }

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

                val syncChannel = android.app.NotificationChannel(
                    SYNC_CHANNEL_ID,
                    "Paatu Padava Background Tasks",
                    android.app.NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Download and playlist sync progress"
                    setShowBadge(false)
                    enableVibration(false)
                    enableLights(false)
                }
                notificationManager.createNotificationChannel(syncChannel)
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
                "startDataSync" -> {
                    val title = call.argument<String>("title") ?: "Background Task"
                    val message = call.argument<String>("message") ?: "Processing..."
                    val max = call.argument<Int>("max") ?: 0
                    val progress = call.argument<Int>("progress") ?: 0

                    if (dataSyncWakeLock == null) {
                        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        dataSyncWakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PaatuPadava:DataSyncWakeLock")?.apply {
                            setReferenceCounted(false)
                        }
                    }
                    try {
                        dataSyncWakeLock?.acquire(30 * 60 * 1000L) // 30 min safety timeout
                    } catch (_: Exception) {}

                    updateSyncNotification(title, message, progress, max)
                    result.success(true)
                }
                "updateDataSyncProgress" -> {
                    val title = call.argument<String>("title") ?: "Background Task"
                    val message = call.argument<String>("message") ?: "Processing..."
                    val max = call.argument<Int>("max") ?: 0
                    val progress = call.argument<Int>("progress") ?: 0
                    updateSyncNotification(title, message, progress, max)
                    result.success(true)
                }
                "stopDataSync" -> {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
                    notificationManager?.cancel(SYNC_NOTIFICATION_ID)
                    try {
                        if (dataSyncWakeLock?.isHeld == true) {
                            dataSyncWakeLock?.release()
                        }
                    } catch (_: Exception) {}
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

        // Native Android DSP & Left/Right Stereo Balance channel
        audioDspBridge = AudioDspBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EQUALIZER_CHANNEL).setMethodCallHandler { call, result ->
            audioDspBridge.handleMethodCall(call, result)
        }

    }

    override fun onDestroy() {
        if (::audioDspBridge.isInitialized) {
            audioDspBridge.release()
        }
        try {
            if (dataSyncWakeLock?.isHeld == true) {
                dataSyncWakeLock?.release()
            }
        } catch (_: Exception) {}
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
        notificationManager?.cancel(SYNC_NOTIFICATION_ID)
        super.onDestroy()
    }
}
