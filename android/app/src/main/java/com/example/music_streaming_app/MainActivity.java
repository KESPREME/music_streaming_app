package com.example.music_streaming_app;

import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioDeviceInfo;
import android.media.AudioDeviceCallback;
import android.media.AudioManager;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;

import com.ryanheise.audioservice.AudioServiceFragmentActivity;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import android.os.Handler;
import android.os.Looper;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends AudioServiceFragmentActivity {
    private static final String METHODS = "mine_music/audio_output";
    private static final String EVENTS = "mine_music/audio_output_events";
    private static final String DECODE = "mine_music/audio_decode";

    /** One analysis at a time; a decode is seconds of CPU, never to be queued up. */
    private final ExecutorService decodeExecutor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private AudioManager audioManager;
    private EventChannel.EventSink eventSink;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        // Analysis decode: file in, small mono PCM out. See AudioDecoder.
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DECODE)
                .setMethodCallHandler((call, result) -> {
                    if (!"decode".equals(call.method)) {
                        result.notImplemented();
                        return;
                    }
                    final String path = call.argument("path");
                    final Integer rate = call.argument("rate");
                    final Integer maxSeconds = call.argument("maxSeconds");
                    final Integer channels = call.argument("channels");
                    if (path == null) {
                        result.error("ARG", "path required", null);
                        return;
                    }
                    final int outRate = rate == null ? 11025 : rate;
                    final int limit = maxSeconds == null ? 900 : maxSeconds;
                    final int outChannels = channels == null ? 1 : channels;
                    decodeExecutor.execute(() -> {
                        try {
                            final byte[] pcm = AudioDecoder.decodeToPcm16(path, outRate, limit, outChannels);
                            mainHandler.post(() -> result.success(pcm));
                        } catch (AudioDecoder.DecodeException e) {
                            mainHandler.post(() -> result.error("DECODE", e.getMessage(), null));
                        } catch (Throwable t) {
                            mainHandler.post(() -> result.error("DECODE", String.valueOf(t), null));
                        }
                    });
                });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), METHODS)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "getOutputs":
                            result.success(getOutputs());
                            break;
                        case "getVolume":
                            result.success(getVolume());
                            break;
                        case "setVolume": {
                            Object v = call.argument("index");
                            if (v instanceof Number) {
                                setVolume(((Number) v).intValue());
                                result.success(null);
                            } else {
                                result.error("ARG", "index required", null);
                            }
                            break;
                        }
                        case "openSoundSettings":
                            openSoundSettings();
                            result.success(null);
                            break;
                        case "openBluetoothSettings":
                            openBluetoothSettings();
                            result.success(null);
                            break;
                        default:
                            result.notImplemented();
                    }
                });

        new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), EVENTS)
                .setStreamHandler(new EventChannel.StreamHandler() {
                    private BroadcastReceiver receiver;
                    private AudioDeviceCallback deviceCallback;

                    @Override
                    public void onListen(Object args, EventChannel.EventSink sink) {
                        eventSink = sink;
                        receiver = new BroadcastReceiver() {
                            @Override
                            public void onReceive(Context c, Intent i) {
                                pushVolume();
                                pushRoutesChanged();
                            }
                        };
                        IntentFilter f = new IntentFilter();
                        f.addAction("android.media.VOLUME_CHANGED_ACTION");
                        f.addAction(BluetoothDevice.ACTION_ACL_CONNECTED);
                        f.addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            registerReceiver(receiver, f, Context.RECEIVER_NOT_EXPORTED);
                        } else {
                            // noinspection deprecation
                            registerReceiver(receiver, f);
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            deviceCallback = new AudioDeviceCallback() {
                                @Override
                                public void onAudioDevicesAdded(AudioDeviceInfo[] d) {
                                    pushRoutesChanged();
                                }

                                @Override
                                public void onAudioDevicesRemoved(AudioDeviceInfo[] d) {
                                    pushRoutesChanged();
                                }
                            };
                            audioManager.registerAudioDeviceCallback(deviceCallback, null);
                        }
                        pushVolume();
                        pushRoutesChanged();
                    }

                    @Override
                    public void onCancel(Object args) {
                        if (receiver != null) {
                            try {
                                unregisterReceiver(receiver);
                            } catch (Exception ignored) {
                            }
                            receiver = null;
                        }
                        if (deviceCallback != null
                                && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                audioManager.unregisterAudioDeviceCallback(deviceCallback);
                            } catch (Exception ignored) {
                            }
                            deviceCallback = null;
                        }
                        eventSink = null;
                    }
                });
    }

    private void pushVolume() {
        if (eventSink != null) {
            Map<String, Object> m = new HashMap<>(getVolume());
            m.put("type", "volume");
            eventSink.success(m);
        }
    }

    private void pushRoutesChanged() {
        if (eventSink != null) {
            Map<String, Object> m = new HashMap<>();
            m.put("type", "routes");
            eventSink.success(m);
        }
    }

    private Map<String, Integer> getVolume() {
        Map<String, Integer> m = new HashMap<>();
        int max = Math.max(1, audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC));
        m.put("volume", audioManager.getStreamVolume(AudioManager.STREAM_MUSIC));
        m.put("max", max);
        return m;
    }

    private void setVolume(int index) {
        int max = Math.max(1, audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC));
        int clamped = Math.max(0, Math.min(max, index));
        // Flag 0: no system UI - our own slider is the UI.
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, clamped, 0);
    }

    private void openSoundSettings() {
        try {
            Intent i = new Intent(Settings.ACTION_SOUND_SETTINGS);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Exception ignored) {
        }
    }

    private void openBluetoothSettings() {
        try {
            Intent i = new Intent(Settings.ACTION_BLUETOOTH_SETTINGS);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Exception ignored) {
        }
    }

    // --- Output listing. BitChord's AudioRouting rules, ported verbatim. ---
    //
    // Showing where audio goes is a pure function of the connected-device list,
    // because reading MediaRouter's selected route flickers while a Bluetooth
    // profile negotiates. Sinks that cannot render music (telephony SCO and
    // earpiece, remote submix, recorder virtual sinks) are never offered:
    // offering those is offering silence. A2DP wins any tie within one device,
    // because pointing a track at the SCO entry plays out of the phone speaker
    // at the Bluetooth volume index instead. Ids are not persisted anywhere:
    // they are only valid while the device stays connected.

    private List<Map<String, Object>> getOutputs() {
        List<Map<String, Object>> out = new ArrayList<>();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || audioManager == null) {
            return out;
        }
        AudioDeviceInfo[] infos;
        try {
            infos = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);
        } catch (Exception e) {
            return out;
        }
        if (infos == null) return out;

        AudioDeviceInfo active = systemDefault(infos);

        // One row per physical device: group by (name, kind), keep the entry
        // that can actually render music.
        Map<String, AudioDeviceInfo> best = new HashMap<>();
        Map<String, String> bestKind = new HashMap<>();
        for (AudioDeviceInfo info : infos) {
            String kind = kindOf(info.getType());
            if (kind == null) continue;
            String name = nameOf(info, kind);
            String key = kind + "\u0000" + name;
            AudioDeviceInfo prev = best.get(key);
            if (prev == null
                    || preferenceWithin(info.getType()) < preferenceWithin(prev.getType())) {
                best.put(key, info);
                bestKind.put(key, kind);
            }
        }
        // Stable order: phone, wired, usb, bluetooth, hdmi, other.
        String[] order = {"phone", "wired", "usb", "bluetooth", "hdmi", "other"};
        for (String want : order) {
            for (Map.Entry<String, AudioDeviceInfo> e : best.entrySet()) {
                if (!bestKind.get(e.getKey()).equals(want)) continue;
                AudioDeviceInfo info = e.getValue();
                Map<String, Object> m = new HashMap<>();
                m.put("id", info.getId());
                m.put("kind", want);
                m.put("name", nameOf(info, want));
                m.put("isActive", active != null && info.getId() == active.getId());
                out.add(m);
            }
        }
        return out;
    }

    private AudioDeviceInfo systemDefault(AudioDeviceInfo[] infos) {
        AudioDeviceInfo bt = null, wired = null, usb = null, hdmi = null, speaker = null;
        for (AudioDeviceInfo info : infos) {
            String kind = kindOf(info.getType());
            if (kind == null) continue;
            if (kind.equals("bluetooth") && bt == null) bt = preferA2dp(info, infos, bt);
            else if (kind.equals("wired") && wired == null) wired = info;
            else if (kind.equals("usb") && usb == null) usb = info;
            else if (kind.equals("hdmi") && hdmi == null) hdmi = info;
            else if (info.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER && speaker == null) {
                speaker = info;
            }
        }
        if (bt != null) return bt;
        if (wired != null) return wired;
        if (usb != null) return usb;
        if (hdmi != null) return hdmi;
        return speaker;
    }

    private AudioDeviceInfo preferA2dp(
            AudioDeviceInfo candidate, AudioDeviceInfo[] infos, AudioDeviceInfo current) {
        // If several entries share the Bluetooth name, the A2DP one renders
        // music and the others do not - same tie-break as the row grouping.
        AudioDeviceInfo best = current == null ? candidate : current;
        String name = nameOf(candidate, "bluetooth");
        for (AudioDeviceInfo info : infos) {
            if (!"bluetooth".equals(kindOf(info.getType()))) continue;
            if (!nameOf(info, "bluetooth").equals(name)) continue;
            if (preferenceWithin(info.getType()) < preferenceWithin(best.getType())) {
                best = info;
            }
        }
        return best;
    }

    private int preferenceWithin(int type) {
        if (type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) return 0;
        if (type == 26 || type == 27) return 1; // BLE_HEADSET, BLE_SPEAKER
        return 2;
    }

    private String kindOf(int type) {
        switch (type) {
            case AudioDeviceInfo.TYPE_BUILTIN_SPEAKER:
                return "phone";
            case AudioDeviceInfo.TYPE_WIRED_HEADSET:
            case AudioDeviceInfo.TYPE_WIRED_HEADPHONES:
            case AudioDeviceInfo.TYPE_LINE_ANALOG:
            case AudioDeviceInfo.TYPE_AUX_LINE:
                return "wired";
            case AudioDeviceInfo.TYPE_USB_DEVICE:
            case AudioDeviceInfo.TYPE_USB_HEADSET:
            case AudioDeviceInfo.TYPE_USB_ACCESSORY:
                return "usb";
            case AudioDeviceInfo.TYPE_BLUETOOTH_A2DP:
            case 26: // BLE_HEADSET
            case 27: // BLE_SPEAKER
            case 28: // BLE_BROADCAST
            case 23: // HEARING_AID
                return "bluetooth";
            case AudioDeviceInfo.TYPE_HDMI:
            case AudioDeviceInfo.TYPE_HDMI_ARC:
                return "hdmi";
            default:
                return null;
        }
    }

    private String nameOf(AudioDeviceInfo info, String kind) {
        // productName is the phone model for the speaker and wired outputs -
        // nobody calls their ears "SM-S911B" - so only named outputs keep it.
        // The UI supplies the label for the blank ones.
        if (kind.equals("phone") || kind.equals("wired")) return "";
        try {
            CharSequence n = info.getProductName();
            return n == null ? "" : n.toString().trim();
        } catch (Exception e) {
            return "";
        }
    }
}
