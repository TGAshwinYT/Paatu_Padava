package com.tamilgaming.paatupadava

import android.app.Activity
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * Native Android DSP & Stereo L/R Earbud Balance bridge for `com.tamilgaming.paatupadava/equalizer`.
 * Uses DynamicsProcessing (API 28+) for attenuation-only Left/Right channel gain so users with
 * uneven earbuds can lower the louder bud without clipping or distortion.
 */
class AudioDspBridge(private val activity: Activity) {
    private var sessionId: Int = 0
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var dynamicsProcessing: DynamicsProcessing? = null
    private var currentStereoBalance: Double = 0.0
    private var currentVocalAttenuation: Double = 0.0

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setAudioSessionId" -> {
                val sid = call.argument<Int>("sessionId") ?: 0
                attachToSession(sid)
                result.success(true)
            }
            "setStereoBalance" -> {
                val balance = call.argument<Double>("balance") ?: 0.0
                result.success(applyStereoBalance(balance))
            }
            "getDspStatus" -> {
                result.success(
                    mapOf(
                        "attached" to (sessionId != 0 && (dynamicsProcessing != null || equalizer != null)),
                        "active" to (currentStereoBalance != 0.0 || currentVocalAttenuation > 0.0),
                        "attenuation" to currentVocalAttenuation,
                        "stereoBalance" to currentStereoBalance,
                        "stereoBalanceSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P),
                        "mode" to if (dynamicsProcessing != null) "dynamics_processing" else "legacy_eq",
                        "channelCount" to 2
                    )
                )
            }
            "getBandCount" -> {
                val bands = try {
                    equalizer?.numberOfBands?.toInt() ?: 5
                } catch (_: Exception) {
                    5
                }
                result.success(bands)
            }
            "setBandLevel" -> {
                val band = call.argument<Int>("band") ?: 0
                val level = call.argument<Int>("level") ?: 0
                try {
                    equalizer?.let { eq ->
                        if (band >= 0 && band < eq.numberOfBands) {
                            val range = eq.bandLevelRange
                            val clamped = level.coerceIn(range[0].toInt(), range[1].toInt()).toShort()
                            eq.setBandLevel(band.toShort(), clamped)
                            eq.enabled = true
                        }
                    }
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
            "setBassBoostStrength" -> {
                val strength = (call.argument<Int>("strength") ?: 0).coerceIn(0, 1000)
                try {
                    bassBoost?.let { bb ->
                        if (bb.strengthSupported) {
                            bb.setStrength(strength.toShort())
                            bb.enabled = strength > 0
                        }
                    }
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
            "setVirtualizerStrength" -> {
                val strength = (call.argument<Int>("strength") ?: 0).coerceIn(0, 1000)
                try {
                    virtualizer?.let { vz ->
                        if (vz.strengthSupported) {
                            vz.setStrength(strength.toShort())
                            vz.enabled = strength > 0
                        }
                    }
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
            "setVocalCancellation" -> {
                val attenuation = (call.argument<Double>("attenuation") ?: 0.0).coerceIn(0.0, 1.0)
                currentVocalAttenuation = attenuation
                result.success(true)
            }
            "openSystemEqualizer" -> {
                if (sessionId == 0) {
                    result.success(false)
                    return
                }
                try {
                    val intent = Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL).apply {
                        putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                        putExtra(AudioEffect.EXTRA_PACKAGE_NAME, activity.packageName)
                        putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
                    }
                    if (intent.resolveActivity(activity.packageManager) != null) {
                        activity.startActivityForResult(intent, 1009)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (_: Exception) {
                    result.success(false)
                }
            }
            "release" -> {
                release()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun attachToSession(newSessionId: Int) {
        if (newSessionId == 0) {
            release()
            return
        }
        if (newSessionId == sessionId && (dynamicsProcessing != null || equalizer != null)) {
            return
        }
        release()
        sessionId = newSessionId

        try {
            equalizer = Equalizer(0, newSessionId).apply { enabled = true }
        } catch (_: Exception) {
            equalizer = null
        }

        try {
            bassBoost = BassBoost(0, newSessionId)
        } catch (_: Exception) {
            bassBoost = null
        }

        try {
            virtualizer = Virtualizer(0, newSessionId)
        } catch (_: Exception) {
            virtualizer = null
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                    2,
                    false, 0,
                    false, 0,
                    false, 0,
                    false
                ).build()
                dynamicsProcessing = DynamicsProcessing(0, newSessionId, config).apply {
                    enabled = true
                }
                applyStereoBalance(currentStereoBalance)
            } catch (_: Exception) {
                dynamicsProcessing = null
            }
        }
    }

    private fun applyStereoBalance(balance: Double): Boolean {
        val clamped = balance.coerceIn(-1.0, 1.0)
        currentStereoBalance = clamped
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val dp = dynamicsProcessing ?: return false
        return try {
            // Attenuation-only gain (0 dB down to -30 dB) prevents digital clipping.
            // Negative balance favors Left (attenuates Right channel 1).
            // Positive balance favors Right (attenuates Left channel 0).
            val maxAttenuationDb = 30.0
            val leftDb = if (clamped > 0.0) (-clamped * maxAttenuationDb).toFloat() else 0.0f
            val rightDb = if (clamped < 0.0) (clamped * maxAttenuationDb).toFloat() else 0.0f
            dp.setInputGainbyChannelIndex(0, leftDb)
            dp.setInputGainbyChannelIndex(1, rightDb)
            dp.enabled = true
            true
        } catch (_: Exception) {
            false
        }
    }

    fun release() {
        sessionId = 0
        try { equalizer?.release() } catch (_: Exception) {}
        try { bassBoost?.release() } catch (_: Exception) {}
        try { virtualizer?.release() } catch (_: Exception) {}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try { dynamicsProcessing?.release() } catch (_: Exception) {}
        }
        equalizer = null
        bassBoost = null
        virtualizer = null
        dynamicsProcessing = null
    }
}
