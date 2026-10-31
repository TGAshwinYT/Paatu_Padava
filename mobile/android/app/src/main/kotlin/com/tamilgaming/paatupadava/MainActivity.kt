package com.tamilgaming.paatupadava

import android.content.Context
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceActivity() {
    private val CHANNEL = "com.tamilgaming.paatupadava/equalizer"
    private val BATTERY_CHANNEL = "com.tamilgaming.paatupadava/battery"
    private val WIDGET_CHANNEL = "com.tamilgaming.paatupadava/widget"
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var currentSessionId: Int = 0
    private var currentBassStrength: Short = 0
    private var currentVirtualizerStrength: Short = 0
    private var currentLevels: ShortArray? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAudioSessionId" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    if (sessionId != 0 && sessionId != currentSessionId) {
                        try {
                            if (currentSessionId != 0) {
                                try {
                                    val closeIntent = Intent(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION).apply {
                                        putExtra(AudioEffect.EXTRA_AUDIO_SESSION, currentSessionId)
                                        putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                                    }
                                    sendBroadcast(closeIntent)
                                } catch (e: Exception) {}
                            }

                            equalizer?.release()
                            equalizer = Equalizer(1000, sessionId).apply {
                                enabled = true
                                currentLevels?.let { levels ->
                                    for (i in levels.indices) {
                                        if (i < numberOfBands) {
                                            setBandLevel(i.toShort(), levels[i])
                                        }
                                    }
                                }
                            }
                            bassBoost?.release()
                            bassBoost = try {
                                BassBoost(1000, sessionId).apply {
                                    enabled = true
                                    if (currentBassStrength > 0 && strengthSupported) {
                                        setStrength(currentBassStrength)
                                    }
                                }
                            } catch (e: Exception) { null }
                            virtualizer?.release()
                            virtualizer = try {
                                Virtualizer(1000, sessionId).apply {
                                    enabled = true
                                    try {
                                        forceVirtualizationMode(Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL)
                                    } catch (e: Exception) {}
                                    if (currentVirtualizerStrength > 0 && strengthSupported) {
                                        setStrength(currentVirtualizerStrength)
                                    }
                                }
                            } catch (e: Exception) { null }
                            currentSessionId = sessionId

                            // Broadcast so Android AudioFlinger attaches DSP chain
                            try {
                                val openIntent = Intent(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION).apply {
                                    putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                                    putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                                    putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
                                }
                                sendBroadcast(openIntent)
                            } catch (e: Exception) {}

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EQ_ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "setBandLevel" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val millibels = call.argument<Int>("level") ?: 0
                    try {
                        equalizer?.setBandLevel(band.toShort(), millibels.toShort())
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EQ_ERROR", e.message, null)
                    }
                }
                "setAllBands" -> {
                    val levels = call.argument<List<Int>>("levels")
                    if (levels != null) {
                        val shortLevels = ShortArray(levels.size) { levels[it].toShort() }
                        currentLevels = shortLevels
                        if (equalizer != null) {
                            try {
                                for (i in shortLevels.indices) {
                                    if (i < equalizer!!.numberOfBands) {
                                        equalizer!!.setBandLevel(i.toShort(), shortLevels[i])
                                    }
                                }
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("EQ_ERROR", e.message, null)
                            }
                        } else {
                            result.success(true)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setBassBoostStrength" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    currentBassStrength = strength.toShort()
                    try {
                        if (bassBoost != null) {
                            bassBoost?.enabled = true
                            if (bassBoost?.strengthSupported == true) {
                                bassBoost?.setStrength(currentBassStrength)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BASS_ERROR", e.message, null)
                    }
                }
                "setVirtualizerStrength" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    currentVirtualizerStrength = strength.toShort()
                    try {
                        if (virtualizer != null) {
                            virtualizer?.enabled = true
                            try {
                                virtualizer?.forceVirtualizationMode(Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL)
                            } catch (e: Exception) {}
                            if (virtualizer?.strengthSupported == true) {
                                virtualizer?.setStrength(currentVirtualizerStrength)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VIRTUALIZER_ERROR", e.message, null)
                    }
                }
                "openSystemEqualizer" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: currentSessionId
                    try {
                        val intent = Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL).apply {
                            putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                            putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                            putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
                        }
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivityForResult(intent, 1001)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "release" -> {
                    try {
                        if (currentSessionId != 0) {
                            val closeIntent = Intent(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION).apply {
                                putExtra(AudioEffect.EXTRA_AUDIO_SESSION, currentSessionId)
                                putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                            }
                            sendBroadcast(closeIntent)
                        }
                    } catch (e: Exception) {}
                    try {
                        equalizer?.release()
                    } catch (e: Exception) {}
                    try {
                        bassBoost?.release()
                    } catch (e: Exception) {}
                    try {
                        virtualizer?.release()
                    } catch (e: Exception) {}
                    equalizer = null
                    bassBoost = null
                    virtualizer = null
                    currentSessionId = 0
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try {
            if (currentSessionId != 0) {
                val closeIntent = Intent(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION).apply {
                    putExtra(AudioEffect.EXTRA_AUDIO_SESSION, currentSessionId)
                    putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                }
                sendBroadcast(closeIntent)
            }
        } catch (e: Exception) {}
        try {
            equalizer?.release()
        } catch (e: Exception) {}
        try {
            bassBoost?.release()
        } catch (e: Exception) {}
        try {
            virtualizer?.release()
        } catch (e: Exception) {}
        equalizer = null
        bassBoost = null
        virtualizer = null
        super.onDestroy()
    }
}
