package com.ryanheise.just_audio;

import android.util.Log;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;

/**
 * Center-Channel Vocal Cancellation AudioProcessor for ExoPlayer/Media3.
 *
 * Implements:
 * 1. 150 Hz 2nd-order Butterworth crossover: low band (<150 Hz) is preserved intact for punchy bass & kick.
 * 2. Mid-Side phase cancellation on high band (>150 Hz): Mid = (L + R) / 2, L_out = L - alpha * Mid, R_out = R - alpha * Mid.
 * 3. Smooth per-frame linear attenuation interpolation to eliminate pops and clicks.
 * 4. High-pass mono-correlation guard to avoid total muting on mono/acappella content.
 * 5. Full onFlush() filter state reset on seeks.
 * 6. Dual 16-bit PCM and Float PCM support.
 */
public class CenterCancellationAudioProcessor extends BaseAudioProcessor {
    private static final String TAG = "CenterCancellationDSP";

    private volatile float targetAttenuation = 0.0f;
    private float currentAttenuation = 0.0f;
    private int sampleRate = 0;
    private int channelCount = 0;
    private int encoding = C.ENCODING_INVALID;
    private boolean isConfiguredStereo = false;

    // Butterworth 2nd-order crossover filter states (L and R)
    private double lpL_x1 = 0, lpL_x2 = 0, lpL_y1 = 0, lpL_y2 = 0;
    private double lpR_x1 = 0, lpR_x2 = 0, lpR_y1 = 0, lpR_y2 = 0;
    private double hpL_x1 = 0, hpL_x2 = 0, hpL_y1 = 0, hpL_y2 = 0;
    private double hpR_x1 = 0, hpR_x2 = 0, hpR_y1 = 0, hpR_y2 = 0;

    // Filter coefficients
    private double lp_b0, lp_b1, lp_b2, lp_a1, lp_a2;
    private double hp_b0, hp_b1, hp_b2, hp_a1, hp_a2;

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

    private void calculateCoefficients(int sRate) {
        double fc = 150.0;
        double omega = 2.0 * Math.PI * fc / (double) sRate;
        double cosOmega = Math.cos(omega);
        double sinOmega = Math.sin(omega);
        double alpha = sinOmega / (2.0 * (1.0 / Math.sqrt(2.0))); // Q = 0.7071

        // Butterworth 2nd order Low-Pass
        double lp_a0 = 1.0 + alpha;
        lp_b0 = ((1.0 - cosOmega) / 2.0) / lp_a0;
        lp_b1 = (1.0 - cosOmega) / lp_a0;
        lp_b2 = ((1.0 - cosOmega) / 2.0) / lp_a0;
        lp_a1 = (-2.0 * cosOmega) / lp_a0;
        lp_a2 = (1.0 - alpha) / lp_a0;

        // Butterworth 2nd order High-Pass
        double hp_a0 = 1.0 + alpha;
        hp_b0 = ((1.0 + cosOmega) / 2.0) / hp_a0;
        hp_b1 = (-(1.0 + cosOmega)) / hp_a0;
        hp_b2 = ((1.0 + cosOmega) / 2.0) / hp_a0;
        hp_a1 = (-2.0 * cosOmega) / hp_a0;
        hp_a2 = (1.0 - alpha) / hp_a0;
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
        Log.i(TAG, "Configured stereo stream: sampleRate=" + inputAudioFormat.sampleRate
                + ", channels=" + inputAudioFormat.channelCount
                + ", encoding=" + inputAudioFormat.encoding);
        return inputAudioFormat;
    }

    @Override
    public boolean isActive() {
        return isConfiguredStereo && (targetAttenuation > 0.0f || currentAttenuation > 0.0f);
    }

    @Override
    protected void onFlush() {
        // Clear filter memory on seeks or track transitions
        lpL_x1 = 0; lpL_x2 = 0; lpL_y1 = 0; lpL_y2 = 0;
        lpR_x1 = 0; lpR_x2 = 0; lpR_y1 = 0; lpR_y2 = 0;
        hpL_x1 = 0; hpL_x2 = 0; hpL_y1 = 0; hpL_y2 = 0;
        hpR_x1 = 0; hpR_x2 = 0; hpR_y1 = 0; hpR_y2 = 0;
        currentAttenuation = targetAttenuation;
    }

    @Override
    protected void onReset() {
        onFlush();
        isConfiguredStereo = false;
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        int remaining = inputBuffer.remaining();
        if (remaining == 0) return;

        if (targetAttenuation == 0.0f && currentAttenuation == 0.0f) {
            // Bypass mode: direct pass-through
            ByteBuffer outputBuffer = replaceOutputBuffer(remaining);
            outputBuffer.put(inputBuffer);
            outputBuffer.flip();
            return;
        }

        if (encoding == C.ENCODING_PCM_FLOAT) {
            processFloatPcm(inputBuffer, remaining);
        } else {
            process16BitPcm(inputBuffer, remaining);
        }
    }

    private void process16BitPcm(ByteBuffer inputBuffer, int remaining) {
        int sampleCount = remaining / 4; // 2 channels * 2 bytes
        ByteBuffer outputBuffer = replaceOutputBuffer(remaining);

        short[] tempL = new short[sampleCount];
        short[] tempR = new short[sampleCount];
        double sumHpLR = 0.0, sumSqHpL = 0.0, sumSqHpR = 0.0;

        // First pass: decode samples and apply crossover filters
        double[] hpLArray = new double[sampleCount];
        double[] hpRArray = new double[sampleCount];
        double[] lpLArray = new double[sampleCount];
        double[] lpRArray = new double[sampleCount];

        for (int i = 0; i < sampleCount; i++) {
            short l = inputBuffer.getShort();
            short r = inputBuffer.getShort();
            tempL[i] = l;
            tempR[i] = r;

            double inL = (double) l;
            double inR = (double) r;

            // Low-pass filter (bass foundation <150 Hz)
            double lpL = lp_b0 * inL + lp_b1 * lpL_x1 + lp_b2 * lpL_x2 - lp_a1 * lpL_y1 - lp_a2 * lpL_y2;
            lpL_x2 = lpL_x1; lpL_x1 = inL; lpL_y2 = lpL_y1; lpL_y1 = lpL;
            lpLArray[i] = lpL;

            double lpR = lp_b0 * inR + lp_b1 * lpR_x1 + lp_b2 * lpR_x2 - lp_a1 * lpR_y1 - lp_a2 * lpR_y2;
            lpR_x2 = lpR_x1; lpR_x1 = inR; lpR_y2 = lpR_y1; lpR_y1 = lpR;
            lpRArray[i] = lpR;

            // High-pass filter (>150 Hz)
            double hpL = hp_b0 * inL + hp_b1 * hpL_x1 + hp_b2 * hpL_x2 - hp_a1 * hpL_y1 - hp_a2 * hpL_y2;
            hpL_x2 = hpL_x1; hpL_x1 = inL; hpL_y2 = hpL_y1; hpL_y1 = hpL;
            hpLArray[i] = hpL;

            double hpR = hp_b0 * inR + hp_b1 * hpR_x1 + hp_b2 * hpR_x2 - hp_a1 * hpR_y1 - hp_a2 * hpR_y2;
            hpR_x2 = hpR_x1; hpR_x1 = inR; hpR_y2 = hpR_y1; hpR_y1 = hpR;
            hpRArray[i] = hpR;

            sumHpLR += hpL * hpR;
            sumSqHpL += hpL * hpL;
            sumSqHpR += hpR * hpR;
        }

        // High-pass correlation guard (prevents mono audio cancellation mute)
        double denom = Math.sqrt(sumSqHpL * sumSqHpR);
        float hpCorrelation = denom > 1e-6 ? (float) (sumHpLR / denom) : 1.0f;

        float deltaAtt = (targetAttenuation - currentAttenuation) / (float) sampleCount;

        for (int i = 0; i < sampleCount; i++) {
            currentAttenuation += deltaAtt;
            float rawAtt = Math.max(0.0f, Math.min(1.0f, currentAttenuation));

            // Only attenuate mono guard if correlation > 0.95 on the vocal band
            float effectiveAtt = rawAtt;
            if (hpCorrelation > 0.95f) {
                effectiveAtt = rawAtt * Math.max(0.20f, 1.0f - (hpCorrelation - 0.95f) * 10f);
            }

            double hpL = hpLArray[i];
            double hpR = hpRArray[i];
            double midHp = (hpL + hpR) * 0.5;

            // Center cancellation on high band
            double outHpL = hpL - (effectiveAtt * midHp);
            double outHpR = hpR - (effectiveAtt * midHp);

            // Recombine low band + processed high band
            double outL = lpLArray[i] + outHpL;
            double outR = lpRArray[i] + outHpR;

            short sOutL = (short) Math.max(-32768, Math.min(32767, (int) Math.round(outL)));
            short sOutR = (short) Math.max(-32768, Math.min(32767, (int) Math.round(outR)));

            outputBuffer.putShort(sOutL);
            outputBuffer.putShort(sOutR);
        }

        currentAttenuation = targetAttenuation;
        outputBuffer.flip();
    }

    private void processFloatPcm(ByteBuffer inputBuffer, int remaining) {
        int sampleCount = remaining / 8; // 2 channels * 4 bytes
        ByteBuffer outputBuffer = replaceOutputBuffer(remaining);

        float deltaAtt = (targetAttenuation - currentAttenuation) / (float) sampleCount;

        for (int i = 0; i < sampleCount; i++) {
            float inL = inputBuffer.getFloat();
            float inR = inputBuffer.getFloat();

            currentAttenuation += deltaAtt;
            float att = Math.max(0.0f, Math.min(1.0f, currentAttenuation));

            double dInL = (double) inL;
            double dInR = (double) inR;

            // Low-pass (<150 Hz)
            double lpL = lp_b0 * dInL + lp_b1 * lpL_x1 + lp_b2 * lpL_x2 - lp_a1 * lpL_y1 - lp_a2 * lpL_y2;
            lpL_x2 = lpL_x1; lpL_x1 = dInL; lpL_y2 = lpL_y1; lpL_y1 = lpL;

            double lpR = lp_b0 * dInR + lp_b1 * lpR_x1 + lp_b2 * lpR_x2 - lp_a1 * lpR_y1 - lp_a2 * lpR_y2;
            lpR_x2 = lpR_x1; lpR_x1 = dInR; lpR_y2 = lpR_y1; lpR_y1 = lpR;

            // High-pass (>150 Hz)
            double hpL = hp_b0 * dInL + hp_b1 * hpL_x1 + hp_b2 * hpL_x2 - hp_a1 * hpL_y1 - hp_a2 * hpL_y2;
            hpL_x2 = hpL_x1; hpL_x1 = dInL; hpL_y2 = hpL_y1; hpL_y1 = hpL;

            double hpR = hp_b0 * dInR + hp_b1 * hpR_x1 + hp_b2 * hpR_x2 - hp_a1 * hpR_y1 - hp_a2 * hpR_y2;
            hpR_x2 = hpR_x1; hpR_x1 = dInR; hpR_y2 = hpR_y1; hpR_y1 = hpR;

            double midHp = (hpL + hpR) * 0.5;
            double outHpL = hpL - (att * midHp);
            double outHpR = hpR - (att * midHp);

            float outL = (float) Math.max(-1.0, Math.min(1.0, lpL + outHpL));
            float outR = (float) Math.max(-1.0, Math.min(1.0, lpR + outHpR));

            outputBuffer.putFloat(outL);
            outputBuffer.putFloat(outR);
        }

        currentAttenuation = targetAttenuation;
        outputBuffer.flip();
    }
}
