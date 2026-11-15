package com.tamilgaming.paatupadava

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import kotlin.math.*

/**
 * High-performance real-time vocal cancellation AudioProcessor.
 *
 * Implements:
 * 1. 2nd-order Butterworth crossover filter at 150 Hz to split low (kick/bass) and high (vocals/mids).
 * 2. Center-channel phase cancellation on high band: M = (L + R) / 2, L_out = L - alpha * M, R_out = R - alpha * M.
 * 3. Preserves un-cancelled low frequencies so rhythm and bass foundation remain punchy and loud.
 * 4. Smooth linear interpolation of wet/dry attenuation across buffer frames to eliminate audio clicks/pops.
 * 5. Mono-correlation guard: attenuates cancellation if L and R are highly correlated (near-mono).
 */
class CenterCancellationAudioProcessor : BaseAudioProcessor() {
    private var targetAttenuation: Float = 0.0f
    private var currentAttenuation: Float = 0.0f

    // 2nd-order Butterworth crossover state (150 Hz)
    // Low-pass biquad: L and R
    private var lpL_x1 = 0.0; private var lpL_x2 = 0.0
    private var lpL_y1 = 0.0; private var lpL_y2 = 0.0
    private var lpR_x1 = 0.0; private var lpR_x2 = 0.0
    private var lpR_y1 = 0.0; private var lpR_y2 = 0.0

    // High-pass biquad: L and R
    private var hpL_x1 = 0.0; private var hpL_x2 = 0.0
    private var hpL_y1 = 0.0; private var hpL_y2 = 0.0
    private var hpR_x1 = 0.0; private var hpR_x2 = 0.0
    private var hpR_y1 = 0.0; private var hpR_y2 = 0.0

    // Filter coefficients
    private var lp_b0 = 0.0; private var lp_b1 = 0.0; private var lp_b2 = 0.0
    private var lp_a1 = 0.0; private var lp_a2 = 0.0
    private var hp_b0 = 0.0; private var hp_b1 = 0.0; private var hp_b2 = 0.0
    private var hp_a1 = 0.0; private var hp_a2 = 0.0

    fun setAttenuation(value: Float) {
        targetAttenuation = value.coerceIn(0.0f, 1.0f)
    }

    fun getAttenuation(): Float = targetAttenuation

    private fun calculateCoefficients(sampleRate: Int) {
        val fc = 150.0
        val omega = 2.0 * PI * fc / sampleRate.toDouble()
        val cosOmega = cos(omega)
        val sinOmega = sin(omega)
        val alpha = sinOmega / (2.0 * (1.0 / sqrt(2.0))) // Q = 0.7071

        // Butterworth 2nd order Low-Pass
        val lp_a0 = 1.0 + alpha
        lp_b0 = ((1.0 - cosOmega) / 2.0) / lp_a0
        lp_b1 = (1.0 - cosOmega) / lp_a0
        lp_b2 = ((1.0 - cosOmega) / 2.0) / lp_a0
        lp_a1 = (-2.0 * cosOmega) / lp_a0
        lp_a2 = (1.0 - alpha) / lp_a0

        // Butterworth 2nd order High-Pass
        val hp_a0 = 1.0 + alpha
        hp_b0 = ((1.0 + cosOmega) / 2.0) / hp_a0
        hp_b1 = (-(1.0 + cosOmega)) / hp_a0
        hp_b2 = ((1.0 + cosOmega) / 2.0) / hp_a0
        hp_a1 = (-2.0 * cosOmega) / hp_a0
        hp_a2 = (1.0 - alpha) / hp_a0
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT || inputAudioFormat.channelCount != 2) {
            return AudioProcessor.AudioFormat.NOT_SET
        }
        calculateCoefficients(inputAudioFormat.sampleRate)
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return

        val sampleCount = remaining / 4 // 2 channels * 2 bytes per 16-bit sample
        val outputBuffer = replaceOutputBuffer(remaining)

        if (targetAttenuation == 0.0f && currentAttenuation == 0.0f) {
            // Bypass mode: direct transfer
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            return
        }

        // Mono-correlation guard pre-pass
        var sumLR = 0.0
        var sumSqL = 0.0
        var sumSqR = 0.0
        val tempL = ShortArray(sampleCount)
        val tempR = ShortArray(sampleCount)

        for (i in 0 until sampleCount) {
            val l = inputBuffer.short
            val r = inputBuffer.short
            tempL[i] = l
            tempR[i] = r
            val lD = l.toDouble()
            val rD = r.toDouble()
            sumLR += lD * rD
            sumSqL += lD * lD
            sumSqR += rD * rD
        }

        val denominator = sqrt(sumSqL * sumSqR)
        val correlation = if (denominator > 1e-6) (sumLR / denominator).toFloat() else 1.0f

        // Attenuation per sample with smooth linear interpolation across buffer
        val deltaAtt = (targetAttenuation - currentAttenuation) / sampleCount.toFloat()

        for (i in 0 until sampleCount) {
            currentAttenuation += deltaAtt
            val rawAtt = currentAttenuation.coerceIn(0.0f, 1.0f)

            // Mono guard: if correlation approaches 1.0 (near-mono track), reduce cancellation so track doesn't mute
            val effectiveAtt = if (correlation > 0.90f) {
                rawAtt * max(0.15f, 1.0f - (correlation - 0.90f) * 10f)
            } else {
                rawAtt
            }

            val inL = tempL[i].toDouble()
            val inR = tempR[i].toDouble()

            // 1. Low-Pass Butterworth Filter (keeps kick drum & bass < 150 Hz intact)
            val lpL = lp_b0 * inL + lp_b1 * lpL_x1 + lp_b2 * lpL_x2 - lp_a1 * lpL_y1 - lp_a2 * lpL_y2
            lpL_x2 = lpL_x1; lpL_x1 = inL; lpL_y2 = lpL_y1; lpL_y1 = lpL
            val lpR = lp_b0 * inR + lp_b1 * lpR_x1 + lp_b2 * lpR_x2 - lp_a1 * lpR_y1 - lp_a2 * lpR_y2
            lpR_x2 = lpR_x1; lpR_x1 = inR; lpR_y2 = lpR_y1; lpR_y1 = lpR

            // 2. High-Pass Butterworth Filter (> 150 Hz)
            val hpL = hp_b0 * inL + hp_b1 * hpL_x1 + hp_b2 * hpL_x2 - hp_a1 * hpL_y1 - hp_a2 * hpL_y2
            hpL_x2 = hpL_x1; hpL_x1 = inL; hpL_y2 = hpL_y1; hpL_y1 = hpL
            val hpR = hp_b0 * inR + hp_b1 * hpR_x1 + hp_b2 * hpR_x2 - hp_a1 * hpR_y1 - hp_a2 * hpR_y2
            hpR_x2 = hpR_x1; hpR_x1 = inR; hpR_y2 = hpR_y1; hpR_y1 = hpR

            // 3. Mid-Side Center Vocal Cancellation on High Band
            val midHp = (hpL + hpR) * 0.5
            val outHpL = hpL - (effectiveAtt * midHp)
            val outHpR = hpR - (effectiveAtt * midHp)

            // 4. Recombine Low Band + Processed High Band
            val outL = (lpL + outHpL).roundToInt().coerceIn(-32768, 32767).toShort()
            val outR = (lpR + outHpR).roundToInt().coerceIn(-32768, 32767).toShort()

            outputBuffer.putShort(outL)
            outputBuffer.putShort(outR)
        }

        currentAttenuation = targetAttenuation
        outputBuffer.flip()
    }

    override fun onReset() {
        lpL_x1 = 0.0; lpL_x2 = 0.0; lpL_y1 = 0.0; lpL_y2 = 0.0
        lpR_x1 = 0.0; lpR_x2 = 0.0; lpR_y1 = 0.0; lpR_y2 = 0.0
        hpL_x1 = 0.0; hpL_x2 = 0.0; hpL_y1 = 0.0; hpL_y2 = 0.0
        hpR_x1 = 0.0; hpR_x2 = 0.0; hpR_y1 = 0.0; hpR_y2 = 0.0
        currentAttenuation = targetAttenuation
    }
}
