package com.ryanheise.just_audio;

import android.content.Context;
import android.content.Intent;
import android.media.audiofx.AudioEffect;
import android.media.audiofx.BassBoost;
import android.media.audiofx.Equalizer;
import android.media.audiofx.Virtualizer;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.List;

public class EqualizerBridge implements MethodCallHandler {
    private static final String CHANNEL_NAME = "com.tamilgaming.paatupadava/equalizer";
    private static EqualizerBridge instance;
    private MethodChannel channel;
    private final Context context;

    private Equalizer equalizer;
    private BassBoost bassBoost;
    private Virtualizer virtualizer;
    private int currentSessionId = 0;
    private short currentBassStrength = 0;
    private short currentVirtualizerStrength = 0;
    private short[] currentLevels = null;

    private EqualizerBridge(Context context, BinaryMessenger messenger) {
        this.context = context.getApplicationContext();
        this.channel = new MethodChannel(messenger, CHANNEL_NAME);
        this.channel.setMethodCallHandler(this);
    }

    public static synchronized void register(Context context, BinaryMessenger messenger) {
        if (instance == null) {
            instance = new EqualizerBridge(context, messenger);
        } else {
            instance.updateMessenger(messenger);
        }
    }

    public static synchronized void unregister() {
        if (instance != null && instance.channel != null) {
            instance.channel.setMethodCallHandler(null);
            instance.channel = null;
        }
    }

    private void updateMessenger(BinaryMessenger messenger) {
        if (this.channel != null) {
            this.channel.setMethodCallHandler(null);
        }
        this.channel = new MethodChannel(messenger, CHANNEL_NAME);
        this.channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "setAudioSessionId": {
                Integer sessId = call.argument("sessionId");
                int sessionId = (sessId != null) ? sessId : 0;
                if (sessionId != 0 && sessionId != currentSessionId) {
                    try {
                        if (currentSessionId != 0) {
                            try {
                                Intent closeIntent = new Intent(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION);
                                closeIntent.putExtra(AudioEffect.EXTRA_AUDIO_SESSION, currentSessionId);
                                closeIntent.putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.getPackageName());
                                context.sendBroadcast(closeIntent);
                            } catch (Exception ignored) {}
                        }

                        if (equalizer != null) {
                            equalizer.release();
                            equalizer = null;
                        }
                        equalizer = new Equalizer(1000, sessionId);
                        equalizer.setEnabled(true);
                        if (currentLevels != null) {
                            short numBands = equalizer.getNumberOfBands();
                            for (int i = 0; i < currentLevels.length && i < numBands; i++) {
                                equalizer.setBandLevel((short) i, currentLevels[i]);
                            }
                        }

                        if (bassBoost != null) {
                            bassBoost.release();
                            bassBoost = null;
                        }
                        try {
                            bassBoost = new BassBoost(1000, sessionId);
                            bassBoost.setEnabled(true);
                            if (currentBassStrength > 0 && bassBoost.getStrengthSupported()) {
                                bassBoost.setStrength(currentBassStrength);
                            }
                        } catch (Exception ignored) {}

                        if (virtualizer != null) {
                            virtualizer.release();
                            virtualizer = null;
                        }
                        try {
                            virtualizer = new Virtualizer(1000, sessionId);
                            virtualizer.setEnabled(true);
                            try {
                                virtualizer.forceVirtualizationMode(Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL);
                            } catch (Exception ignored) {}
                            if (currentVirtualizerStrength > 0 && virtualizer.getStrengthSupported()) {
                                virtualizer.setStrength(currentVirtualizerStrength);
                            }
                        } catch (Exception ignored) {}

                        currentSessionId = sessionId;

                        try {
                            Intent openIntent = new Intent(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION);
                            openIntent.putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId);
                            openIntent.putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.getPackageName());
                            openIntent.putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC);
                            context.sendBroadcast(openIntent);
                        } catch (Exception ignored) {}

                        result.success(true);
                    } catch (Exception e) {
                        result.error("EQ_ERROR", e.getMessage(), null);
                    }
                } else {
                    result.success(true);
                }
                break;
            }
            case "setBandLevel": {
                Integer band = call.argument("band");
                Integer level = call.argument("level");
                int b = (band != null) ? band : 0;
                int l = (level != null) ? level : 0;
                try {
                    if (equalizer != null) {
                        short[] range = equalizer.getBandLevelRange();
                        short clamped = (short) Math.max(range[0], Math.min(range[1], l));
                        equalizer.setBandLevel((short) b, clamped);
                    }
                    result.success(true);
                } catch (Exception e) {
                    result.error("EQ_ERROR", e.getMessage(), null);
                }
                break;
            }
            case "setAllBands": {
                List<Integer> levels = call.argument("levels");
                if (levels != null) {
                    currentLevels = new short[levels.size()];
                    for (int i = 0; i < levels.size(); i++) {
                        currentLevels[i] = levels.get(i).shortValue();
                    }
                    if (equalizer != null) {
                        try {
                            short[] range = equalizer.getBandLevelRange();
                            short numBands = equalizer.getNumberOfBands();
                            for (int i = 0; i < currentLevels.length && i < numBands; i++) {
                                short clamped = (short) Math.max(range[0], Math.min(range[1], currentLevels[i]));
                                equalizer.setBandLevel((short) i, clamped);
                            }
                            result.success(true);
                        } catch (Exception e) {
                            result.error("EQ_ERROR", e.getMessage(), null);
                        }
                    } else {
                        result.success(true);
                    }
                } else {
                    result.success(false);
                }
                break;
            }
            case "setBassBoostStrength": {
                Integer strength = call.argument("strength");
                currentBassStrength = (strength != null) ? strength.shortValue() : 0;
                try {
                    if (bassBoost != null) {
                        bassBoost.setEnabled(true);
                        if (bassBoost.getStrengthSupported()) {
                            bassBoost.setStrength(currentBassStrength);
                        }
                    }
                    result.success(true);
                } catch (Exception e) {
                    result.error("BASS_ERROR", e.getMessage(), null);
                }
                break;
            }
            case "setVirtualizerStrength": {
                Integer strength = call.argument("strength");
                currentVirtualizerStrength = (strength != null) ? strength.shortValue() : 0;
                try {
                    if (virtualizer != null) {
                        virtualizer.setEnabled(true);
                        try {
                            virtualizer.forceVirtualizationMode(Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL);
                        } catch (Exception ignored) {}
                        if (virtualizer.getStrengthSupported()) {
                            virtualizer.setStrength(currentVirtualizerStrength);
                        }
                    }
                    result.success(true);
                } catch (Exception e) {
                    result.error("VIRTUALIZER_ERROR", e.getMessage(), null);
                }
                break;
            }
            case "openSystemEqualizer": {
                Integer sessId = call.argument("sessionId");
                int sessionId = (sessId != null) ? sessId : currentSessionId;
                try {
                    Intent intent = new Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL);
                    intent.putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId);
                    intent.putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.getPackageName());
                    intent.putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC);
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    context.startActivity(intent);
                    result.success(true);
                } catch (Exception e) {
                    result.success(false);
                }
                break;
            }
            case "release": {
                try {
                    if (currentSessionId != 0) {
                        Intent closeIntent = new Intent(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION);
                        closeIntent.putExtra(AudioEffect.EXTRA_AUDIO_SESSION, currentSessionId);
                        closeIntent.putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.getPackageName());
                        context.sendBroadcast(closeIntent);
                    }
                } catch (Exception ignored) {}
                if (equalizer != null) {
                    try { equalizer.release(); } catch (Exception ignored) {}
                    equalizer = null;
                }
                if (bassBoost != null) {
                    try { bassBoost.release(); } catch (Exception ignored) {}
                    bassBoost = null;
                }
                if (virtualizer != null) {
                    try { virtualizer.release(); } catch (Exception ignored) {}
                    virtualizer = null;
                }
                currentSessionId = 0;
                result.success(true);
                break;
            }
            case "setVocalCancellation": {
                Double att = call.argument("attenuation");
                float attenuation = (att != null) ? att.floatValue() : 0.0f;
                boolean success = KaraokeDsp.getInstance().setAttenuation(attenuation);
                result.success(success);
                break;
            }
            case "isDspAvailable": {
                result.success(KaraokeDsp.getInstance().isAttached());
                break;
            }
            case "getDspStatus": {
                result.success(KaraokeDsp.getInstance().getDspStatus());
                break;
            }
            case "getBandCount": {
                int count = (equalizer != null) ? equalizer.getNumberOfBands() : 5;
                result.success(count);
                break;
            }
            default:
                result.notImplemented();
                break;
        }
    }
}
