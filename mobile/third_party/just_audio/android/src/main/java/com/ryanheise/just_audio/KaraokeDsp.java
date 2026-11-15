package com.ryanheise.just_audio;

import java.util.HashMap;
import java.util.Map;

/**
 * Process-wide singleton managing the ExoPlayer CenterCancellationAudioProcessor.
 * Retains state across engine attachments and provides status inspection.
 */
public class KaraokeDsp {
    private static final KaraokeDsp INSTANCE = new KaraokeDsp();

    private final CenterCancellationAudioProcessor processor;
    private volatile boolean isAttached = false;
    private volatile float targetAttenuation = 0.0f;

    private KaraokeDsp() {
        this.processor = new CenterCancellationAudioProcessor();
    }

    public static KaraokeDsp getInstance() {
        return INSTANCE;
    }

    public CenterCancellationAudioProcessor getProcessor() {
        return processor;
    }

    public synchronized void setAttached(boolean attached) {
        this.isAttached = attached;
    }

    public boolean isAttached() {
        return isAttached;
    }

    public synchronized boolean setAttenuation(float attenuation) {
        this.targetAttenuation = Math.max(0.0f, Math.min(1.0f, attenuation));
        processor.setAttenuation(this.targetAttenuation);
        return true;
    }

    public float getAttenuation() {
        return targetAttenuation;
    }

    public Map<String, Object> getDspStatus() {
        Map<String, Object> status = new HashMap<>();
        status.put("attached", isAttached);
        status.put("active", isAttached && processor.isActive());
        status.put("attenuation", (double) targetAttenuation);
        status.put("mode", isAttached ? "native_dsp_center_cancellation" : "none");
        status.put("channelCount", 2);
        return status;
    }
}
