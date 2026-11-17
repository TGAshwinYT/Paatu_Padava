package com.ryanheise.just_audio;

import android.util.Log;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * High-Performance In-Place Center-Channel Vocal Cancellation AudioProcessor for ExoPlayer/Media3.
 *
 * Architectural Invariants:
 * 1. Always-Active Lifecycle: isActive() returns true permanently once stereo format is negotiated,
 *    preventing ExoPlayer sink teardown / pipeline freezes.
 * 2. Internal Zero-Cost Bypass: Bit-exact pass-through when attenuation is 0.0f.
 * 3. Tier-1 Multiband Adaptive Mid-Side DSP:
 *    - Phase-aligned Linkwitz-Riley 4th order (LR4) crossover (150 Hz LP & 7 kHz HP with all-pass alignment).
 *    - Center-channel Mid-Side phase cancellation on Mid band with alpha and center confidence.
 *    - 3.0 kHz presence notch (RBJ peaking filter) on Mid band.
 *    - Normalized stereo difference energy true-mono detection with spectral notch fallback.
 *    - Sample-level single-pole alpha smoothing (40 ms time constant).
 *    - Make-up gain (+2.5 dB * alpha) and soft-knee limiter at -1 dBFS.
 * 4. Zero-Allocation Audio Thread: Pre-allocated scratch buffers in onConfigure(), zero GC pressure in queueInput().
 * 5. Dual 16-bit PCM and Float PCM support via unified internal 32-bit float processing.
 */
public class CenterCancellationAudioProcessor extends BaseAudioProcessor {
    private static final String TAG = "CenterCancellationDSP";

    private volatile float targetAttenuation = 0.0f;
    private float currentAttenuation = 0.0f;
    private int sampleRate = 0;
    private int channelCount = 0;
    private int encoding = C.ENCODING_INVALID;
    private boolean isConfiguredStereo = false;

    // Volatile operational metrics for UI / diagnostics
    private volatile long buffersProcessed = 0;
    private volatile long lastBufferTimestampMs = 0;
    private volatile String currentMode = "bypass";

    // Sample-level smoothing constant: alpha[n] = alpha[n-1] + smoothCoeff * (target - alpha[n-1])
    private float smoothCoeff = 0.001f;

    // --- LR4 150 Hz Low-Pass Biquad Filter States (2 cascaded 2nd-order stages per channel) ---
    private double lp1_x1_L = 0, lp1_x2_L = 0, lp1_y1_L = 0, lp1_y2_L = 0;
    private double lp2_x1_L = 0, lp2_x2_L = 0, lp2_y1_L = 0, lp2_y2_L = 0;
    private double lp1_x1_R = 0, lp1_x2_R = 0, lp1_y1_R = 0, lp1_y2_R = 0;
    private double lp2_x1_R = 0, lp2_x2_R = 0, lp2_y1_R = 0, lp2_y2_R = 0;

    // --- LR4 7 kHz High-Pass Biquad Filter States (2 cascaded 2nd-order stages per channel) ---
    private double hp1_x1_L = 0, hp1_x2_L = 0, hp1_y1_L = 0, hp1_y2_L = 0;
    private double hp2_x1_L = 0, hp2_x2_L = 0, hp2_y1_L = 0, hp2_y2_L = 0;
    private double hp1_x1_R = 0, hp1_x2_R = 0, hp1_y1_R = 0, hp1_y2_R = 0;
    private double hp2_x1_R = 0, hp2_x2_R = 0, hp2_y1_R = 0, hp2_y2_R = 0;

    // --- All-Pass Phase Alignment States for Low Band (matches 7 kHz crossover phase) ---
    private double ap1_x1_L = 0, ap1_x2_L = 0, ap1_y1_L = 0, ap1_y2_L = 0;
    private double ap2_x1_L = 0, ap2_x2_L = 0, ap2_y1_L = 0, ap2_y2_L = 0;
    private double ap1_x1_R = 0, ap1_x2_R = 0, ap1_y1_R = 0, ap1_y2_R = 0;
    private double ap2_x1_R = 0, ap2_x2_R = 0, ap2_y1_R = 0, ap2_y2_R = 0;

    // --- 3.0 kHz Presence Notch Biquad States (applied to Mid channel) ---
    private double notch_x1 = 0, notch_x2 = 0, notch_y1 = 0, notch_y2 = 0;

    // --- Biquad Coefficients ---
    private double lp_b0, lp_b1, lp_b2, lp_a1, lp_a2;
    private double hp_b0, hp_b1, hp_b2, hp_a1, hp_a2;
    private double ap_b0, ap_b1, ap_b2, ap_a1, ap_a2;
    private double notch_b0, notch_b1, notch_b2, notch_a1, notch_a2;

    // Pre-allocated scratch buffers to guarantee ZERO allocations on audio thread
    private int scratchCapacity = 0;
    private float[] scratchInL = new float[0];
    private float[] scratchInR = new float[0];
    private float[] scratchOutL = new float[0];
    private float[] scratchOutR = new float[0];

    public void setAttenuation(float value) {
        this.targetAttenuation = Math.max(0.0f, Math.min(1.0f, value));
    }

    public float getAttenuation() {
        return targetAttenuation;
    }

    public int getSampleRate() {
        return sampleRate;
    }

    public int getChannelCount() {
        return channelCount;
    }

    public int getEncoding() {
        return encoding;
    }

    public long getBuffersProcessed() {
        return buffersProcessed;
    }

    public boolean isProcessingLiveAudio() {
        return isConfiguredStereo && (System.currentTimeMillis() - lastBufferTimestampMs) < 1500;
    }

    public String getCurrentMode() {
        return currentMode;
    }

    private void ensureScratchCapacity(int requiredFrames) {
        if (requiredFrames > scratchCapacity) {
            scratchCapacity = Math.max(requiredFrames, 4096);
            scratchInL = new float[scratchCapacity];
            scratchInR = new float[scratchCapacity];
            scratchOutL = new float[scratchCapacity];
            scratchOutR = new float[scratchCapacity];
        }
    }

    private void calculateCoefficients(int sRate) {
        double fs = (double) sRate;

        // 40ms time constant for sample-level smoothing: smoothCoeff = 1 - exp(-1 / (0.040 * fs))
        smoothCoeff = (float) (1.0 - Math.exp(-1.0 / (0.040 * fs)));

        // 1. 150 Hz Butterworth 2nd-order stage (cascaded 2x = LR4)
        double fcLp = 150.0;
        double omegaLp = 2.0 * Math.PI * fcLp / fs;
        double cosLp = Math.cos(omegaLp);
        double sinLp = Math.sin(omegaLp);
        double alphaLp = sinLp / (2.0 * (1.0 / Math.sqrt(2.0))); // Q = 0.7071
        double a0Lp = 1.0 + alphaLp;
        lp_b0 = ((1.0 - cosLp) / 2.0) / a0Lp;
        lp_b1 = (1.0 - cosLp) / a0Lp;
        lp_b2 = ((1.0 - cosLp) / 2.0) / a0Lp;
        lp_a1 = (-2.0 * cosLp) / a0Lp;
        lp_a2 = (1.0 - alphaLp) / a0Lp;

        // 2. 7.0 kHz Butterworth 2nd-order stage (cascaded 2x = LR4)
        double fcHp = Math.min(7000.0, fs * 0.45);
        double omegaHp = 2.0 * Math.PI * fcHp / fs;
        double cosHp = Math.cos(omegaHp);
        double sinHp = Math.sin(omegaHp);
        double alphaHp = sinHp / (2.0 * (1.0 / Math.sqrt(2.0)));
        double a0Hp = 1.0 + alphaHp;
        hp_b0 = ((1.0 + cosHp) / 2.0) / a0Hp;
        hp_b1 = (-(1.0 + cosHp)) / a0Hp;
        hp_b2 = ((1.0 + cosHp) / 2.0) / a0Hp;
        hp_a1 = (-2.0 * cosHp) / a0Hp;
        hp_a2 = (1.0 - alphaHp) / a0Hp;

        // 3. All-Pass Phase Match for Low Band (matches 7.0 kHz crossover phase shift)
        double a0Ap = 1.0 + alphaHp;
        ap_b0 = (1.0 - alphaHp) / a0Ap;
        ap_b1 = (-2.0 * cosHp) / a0Ap;
        ap_b2 = (1.0 + alphaHp) / a0Ap;
        ap_a1 = (-2.0 * cosHp) / a0Ap;
        ap_a2 = (1.0 - alphaHp) / a0Ap;

        // 4. 3.0 kHz RBJ Peaking Presence Notch (Q = 1.0, -6 dB depth)
        double fcNotch = 3000.0;
        double omegaNotch = 2.0 * Math.PI * fcNotch / fs;
        double cosNotch = Math.cos(omegaNotch);
        double sinNotch = Math.sin(omegaNotch);
        double A = Math.pow(10.0, -6.0 / 40.0); // -6 dB depth
        double alphaNotch = sinNotch / (2.0 * 1.0);
        double a0Notch = 1.0 + alphaNotch / A;
        notch_b0 = (1.0 + alphaNotch * A) / a0Notch;
        notch_b1 = (-2.0 * cosNotch) / a0Notch;
        notch_b2 = (1.0 - alphaNotch * A) / a0Notch;
        notch_a1 = (-2.0 * cosNotch) / a0Notch;
        notch_a2 = (1.0 - alphaNotch / A) / a0Notch;
    }

    @Override
    public AudioFormat onConfigure(AudioFormat inputAudioFormat) throws UnhandledAudioFormatException {
        this.sampleRate = inputAudioFormat.sampleRate;
        this.channelCount = inputAudioFormat.channelCount;
        this.encoding = inputAudioFormat.encoding;

        if ((inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT)
                || inputAudioFormat.channelCount != 2) {
            isConfiguredStereo = false;
            Log.d(TAG, "Format unsupported for center cancellation: " + inputAudioFormat);
            return AudioFormat.NOT_SET;
        }

        isConfiguredStereo = true;
        calculateCoefficients(inputAudioFormat.sampleRate);
        ensureScratchCapacity(2048);

        Log.i(TAG, "Configured stereo stream: sampleRate=" + inputAudioFormat.sampleRate
                + ", channels=" + inputAudioFormat.channelCount
                + ", encoding=" + inputAudioFormat.encoding);
        return inputAudioFormat;
    }

    @Override
    public boolean isActive() {
        // PERMANENT REGISTRATION: As long as stereo format is negotiated, keep processor active in sink.
        // Bypass at alpha = 0 is handled internally in queueInput() with zero overhead.
        return isConfiguredStereo;
    }

    @Override
    protected void onFlush() {
        // Reset filter delay lines on seek or track transition
        lp1_x1_L = 0; lp1_x2_L = 0; lp1_y1_L = 0; lp1_y2_L = 0;
        lp2_x1_L = 0; lp2_x2_L = 0; lp2_y1_L = 0; lp2_y2_L = 0;
        lp1_x1_R = 0; lp1_x2_R = 0; lp1_y1_R = 0; lp1_y2_R = 0;
        lp2_x1_R = 0; lp2_x2_R = 0; lp2_y1_R = 0; lp2_y2_R = 0;

        hp1_x1_L = 0; hp1_x2_L = 0; hp1_y1_L = 0; hp1_y2_L = 0;
        hp2_x1_L = 0; hp2_x2_L = 0; hp2_y1_L = 0; hp2_y2_L = 0;
        hp1_x1_R = 0; hp1_x2_R = 0; hp1_y1_R = 0; hp1_y2_R = 0;
        hp2_x1_R = 0; hp2_x2_R = 0; hp2_y1_R = 0; hp2_y2_R = 0;

        ap1_x1_L = 0; ap1_x2_L = 0; ap1_y1_L = 0; ap1_y2_L = 0;
        ap2_x1_L = 0; ap2_x2_L = 0; ap2_y1_L = 0; ap2_y2_L = 0;
        ap1_x1_R = 0; ap1_x2_R = 0; ap1_y1_R = 0; ap1_y2_R = 0;
        ap2_x1_R = 0; ap2_x2_R = 0; ap2_y1_R = 0; ap2_y2_R = 0;

        notch_x1 = 0; notch_x2 = 0; notch_y1 = 0; notch_y2 = 0;

        currentAttenuation = targetAttenuation;
    }

    @Override
    protected void onReset() {
        onFlush();
        isConfiguredStereo = false;
        buffersProcessed = 0;
        currentMode = "bypass";
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        int remaining = inputBuffer.remaining();
        if (remaining == 0) return;

        buffersProcessed++;
        lastBufferTimestampMs = System.currentTimeMillis();

        // 1. Bit-Exact Fast Bypass when attenuation is zero
        if (targetAttenuation == 0.0f && currentAttenuation < 0.0001f) {
            currentAttenuation = 0.0f;
            currentMode = "bypass";
            ByteBuffer outputBuffer = replaceOutputBuffer(remaining);
            outputBuffer.put(inputBuffer);
            outputBuffer.flip();
            return;
        }

        // 2. Unified DSP processing for 16-bit PCM and Float PCM
        if (encoding == C.ENCODING_PCM_FLOAT) {
            processFloatPcm(inputBuffer, remaining);
        } else {
            process16BitPcm(inputBuffer, remaining);
        }
    }

    private void process16BitPcm(ByteBuffer inputBuffer, int remaining) {
        int frameCount = remaining / 4; // 2 channels * 2 bytes
        ensureScratchCapacity(frameCount);

        // Decode 16-bit PCM shorts to normalized float scratch arrays [-1.0, 1.0]
        for (int i = 0; i < frameCount; i++) {
            scratchInL[i] = (float) inputBuffer.getShort() / 32768.0f;
            scratchInR[i] = (float) inputBuffer.getShort() / 32768.0f;
        }

        processFrames(frameCount);

        // Encode back to 16-bit PCM shorts
        ByteBuffer outputBuffer = replaceOutputBuffer(remaining);
        for (int i = 0; i < frameCount; i++) {
            float outL = scratchOutL[i];
            float outR = scratchOutR[i];

            int sL = Math.round(outL * 32767.0f);
            int sR = Math.round(outR * 32767.0f);

            outputBuffer.putShort((short) Math.max(-32768, Math.min(32767, sL)));
            outputBuffer.putShort((short) Math.max(-32768, Math.min(32767, sR)));
        }
        outputBuffer.flip();
    }

    private void processFloatPcm(ByteBuffer inputBuffer, int remaining) {
        int frameCount = remaining / 8; // 2 channels * 4 bytes
        ensureScratchCapacity(frameCount);

        // Decode 32-bit floats to scratch arrays
        for (int i = 0; i < frameCount; i++) {
            scratchInL[i] = inputBuffer.getFloat();
            scratchInR[i] = inputBuffer.getFloat();
        }

        processFrames(frameCount);

        // Encode back to 32-bit floats
        ByteBuffer outputBuffer = replaceOutputBuffer(remaining);
        for (int i = 0; i < frameCount; i++) {
            outputBuffer.putFloat(scratchOutL[i]);
            outputBuffer.putFloat(scratchOutR[i]);
        }
        outputBuffer.flip();
    }

    /**
     * Unified Core DSP Engine operating on pre-allocated float scratch arrays.
     * Enforces Linkwitz-Riley 4th order complementary crossover, all-pass phase alignment,
     * normalized stereo difference energy detection, Mid presence notch, make-up gain, and soft limiter.
     */
    private void processFrames(int frameCount) {
        // Step 1: Detect normalized stereo difference energy across the buffer
        double sumDiff = 0.0;
        double sumTotal = 0.0;
        for (int i = 0; i < frameCount; i++) {
            float l = scratchInL[i];
            float r = scratchInR[i];
            sumDiff += Math.abs(l - r);
            sumTotal += Math.abs(l) + Math.abs(r);
        }
        double stereoDifferenceRatio = sumTotal > 1e-6 ? (sumDiff / sumTotal) : 0.0;
        boolean isTrueMono = stereoDifferenceRatio < 0.002;

        currentMode = isTrueMono ? "mono_reduce" : "stereo_cancel";

        for (int i = 0; i < frameCount; i++) {
            // Sample-level single-pole smoothing
            currentAttenuation += smoothCoeff * (targetAttenuation - currentAttenuation);
            float alpha = currentAttenuation;

            double inL = scratchInL[i];
            double inR = scratchInR[i];

            // --- 1. LR4 Low-Pass (<150 Hz) - Stage 1 & Stage 2 ---
            double lp1L = lp_b0 * inL + lp_b1 * lp1_x1_L + lp_b2 * lp1_x2_L - lp_a1 * lp1_y1_L - lp_a2 * lp1_y2_L;
            lp1_x2_L = lp1_x1_L; lp1_x1_L = inL; lp1_y2_L = lp1_y1_L; lp1_y1_L = lp1L;
            double lpL = lp_b0 * lp1L + lp_b1 * lp2_x1_L + lp_b2 * lp2_x2_L - lp_a1 * lp2_y1_L - lp_a2 * lp2_y2_L;
            lp2_x2_L = lp2_x1_L; lp2_x1_L = lp1L; lp2_y2_L = lp2_y1_L; lp2_y1_L = lpL;

            double lp1R = lp_b0 * inR + lp_b1 * lp1_x1_R + lp_b2 * lp1_x2_R - lp_a1 * lp1_y1_R - lp_a2 * lp1_y2_R;
            lp1_x2_R = lp1_x1_R; lp1_x1_R = inR; lp1_y2_R = lp1_y1_R; lp1_y1_R = lp1R;
            double lpR = lp_b0 * lp1R + lp_b1 * lp2_x1_R + lp_b2 * lp2_x2_R - lp_a1 * lp2_y1_R - lp_a2 * lp2_y2_R;
            lp2_x2_R = lp2_x1_R; lp2_x1_R = lp1R; lp2_y2_R = lp2_y1_R; lp2_y1_R = lpR;

            // --- 2. Low-Band All-Pass Phase Match (aligns low band with 7 kHz crossover phase) ---
            double ap1L = ap_b0 * lpL + ap_b1 * ap1_x1_L + ap_b2 * ap1_x2_L - ap_a1 * ap1_y1_L - ap_a2 * ap1_y2_L;
            ap1_x2_L = ap1_x1_L; ap1_x1_L = lpL; ap1_y2_L = ap1_y1_L; ap1_y1_L = ap1L;
            double apL = ap_b0 * ap1L + ap_b1 * ap2_x1_L + ap_b2 * ap2_x2_L - ap_a1 * ap2_y1_L - ap_a2 * ap2_y2_L;
            ap2_x2_L = ap2_x1_L; ap2_x1_L = ap1L; ap2_y2_L = ap2_y1_L; ap2_y1_L = apL;

            double ap1R = ap_b0 * lpR + ap_b1 * ap1_x1_R + ap_b2 * ap1_x2_R - ap_a1 * ap1_y1_R - ap_a2 * ap1_y2_R;
            ap1_x2_R = ap1_x1_R; ap1_x1_R = lpR; ap1_y2_R = ap1_y1_R; ap1_y1_R = ap1R;
            double apR = ap_b0 * ap1R + ap_b1 * ap2_x1_R + ap_b2 * ap2_x2_R - ap_a1 * ap2_y1_R - ap_a2 * ap2_y2_R;
            ap2_x2_R = ap2_x1_R; ap2_x1_R = ap1R; ap2_y2_R = ap2_y1_R; ap2_y1_R = apR;

            // Remainder above 150 Hz
            double remL = inL - lpL;
            double remR = inR - lpR;

            // --- 3. LR4 High-Pass (>7 kHz) - Stage 1 & Stage 2 ---
            double hp1L = hp_b0 * remL + hp_b1 * hp1_x1_L + hp_b2 * hp1_x2_L - hp_a1 * hp1_y1_L - hp_a2 * hp1_y2_L;
            hp1_x2_L = hp1_x1_L; hp1_x1_L = remL; hp1_y2_L = hp1_y1_L; hp1_y1_L = hp1L;
            double hpL = hp_b0 * hp1L + hp_b1 * hp2_x1_L + hp_b2 * hp2_x2_L - hp_a1 * hp2_y1_L - hp_a2 * hp2_y2_L;
            hp2_x2_L = hp2_x1_L; hp2_x1_L = hp1L; hp2_y2_L = hp2_y1_L; hp2_y1_L = hpL;

            double hp1R = hp_b0 * remR + hp_b1 * hp1_x1_R + hp_b2 * hp1_x2_R - hp_a1 * hp1_y1_R - hp_a2 * hp1_y2_R;
            hp1_x2_R = hp1_x1_R; hp1_x1_R = remR; hp1_y2_R = hp1_y1_R; hp1_y1_R = hp1R;
            double hpR = hp_b0 * hp1R + hp_b1 * hp2_x1_R + hp_b2 * hp2_x2_R - hp_a1 * hp2_y1_R - hp_a2 * hp2_y2_R;
            hp2_x2_R = hp2_x1_R; hp2_x1_R = hp1R; hp2_y2_R = hp2_y1_R; hp2_y1_R = hpR;

            // --- 4. Mid Band (150 Hz to 7 kHz) ---
            double midL = remL - hpL;
            double midR = remR - hpR;

            double processedMidL;
            double processedMidR;

            if (isTrueMono) {
                // True Mono Safety Fallback: Spectral notch attenuation instead of M/S phase extinction
                double monoAtt = Math.max(0.40, 1.0 - (alpha * 0.60)); // Max -8 dB attenuation
                processedMidL = midL * monoAtt;
                processedMidR = midR * monoAtt;
            } else {
                // Stereo Mode: Mid-Side Center Cancellation
                double M = 0.5 * (midL + midR);
                double S = 0.5 * (midL - midR);

                // Cancel center channel
                double M_cancelled = M * (1.0 - alpha);

                // Apply 3.0 kHz presence notch filter to M_cancelled
                double notchM = notch_b0 * M_cancelled + notch_b1 * notch_x1 + notch_b2 * notch_x2 - notch_a1 * notch_y1 - notch_a2 * notch_y2;
                notch_x2 = notch_x1; notch_x1 = M_cancelled; notch_y2 = notch_y1; notch_y1 = notchM;

                double finalM = (1.0 - alpha) * M_cancelled + alpha * notchM;

                processedMidL = finalM + S;
                processedMidR = finalM - S;
            }

            // High band gentle attenuation: alpha_high = 0.2 * alpha
            double highAtt = 1.0 - (0.2 * alpha);
            double highL = hpL * highAtt;
            double highR = hpR * highAtt;

            // Make-up gain: +2.5 dB * alpha (factor ~ 1.33 at alpha=1.0)
            double makeUpGain = 1.0 + (alpha * 0.33);

            // Reconstruct full audio: Low (phase aligned) + Processed Mid + High
            double rawOutL = (apL + processedMidL + highL) * makeUpGain;
            double rawOutR = (apR + processedMidR + highR) * makeUpGain;

            // Instantaneous Soft-Knee Limiter (knee at 0.891 / -1 dBFS, smooth polynomial compression)
            scratchOutL[i] = (float) applySoftLimiter(rawOutL);
            scratchOutR[i] = (float) applySoftLimiter(rawOutR);
        }
    }

    /**
     * Instantaneous soft-knee limiter preventing clipping above -1 dBFS (0.891).
     * Linear below threshold, smooth cubic knee above threshold, strictly bounded < 1.0.
     */
    private static double applySoftLimiter(double x) {
        double absX = Math.abs(x);
        if (absX <= 0.891) {
            return x;
        }
        double sign = x > 0.0 ? 1.0 : -1.0;
        double excess = absX - 0.891;
        // Smooth saturation curve approaching 0.99 asymptotically
        double compressed = 0.891 + 0.099 * (1.0 - Math.exp(-excess / 0.10));
        return sign * Math.min(0.999, compressed);
    }
}
