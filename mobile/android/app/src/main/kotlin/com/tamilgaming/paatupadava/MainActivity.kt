package com.tamilgaming.paatupadava

import android.content.Intent
import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import androidx.annotation.NonNull
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceActivity() {
    private val CHANNEL = "com.tamilgaming.paatupadava/equalizer"
    private var equalizer: Equalizer? = null
    private var currentSessionId: Int = 0

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAudioSessionId" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    if (sessionId != 0 && sessionId != currentSessionId) {
                        try {
                            equalizer?.release()
                            equalizer = Equalizer(0, sessionId).apply {
                                enabled = true
                            }
                            currentSessionId = sessionId
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
                    if (levels != null && equalizer != null) {
                        try {
                            for (i in levels.indices) {
                                if (i < equalizer!!.numberOfBands) {
                                    equalizer!!.setBandLevel(i.toShort(), levels[i].toShort())
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EQ_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
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
                        equalizer?.release()
                    } catch (_) {}
                    equalizer = null
                    currentSessionId = 0
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try {
            equalizer?.release()
        } catch (_) {}
        equalizer = null
        super.onDestroy()
    }
}
