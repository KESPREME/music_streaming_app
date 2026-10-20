package com.example.music_streaming_app;

import android.media.AudioManager;
import android.media.audiofx.BassBoost;
import android.media.audiofx.Equalizer;
import android.media.audiofx.LoudnessEnhancer;
import android.media.audiofx.Virtualizer;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * The equalizer's native engine: android.media.audiofx effects bound to the
 * player's audio session ids.
 *
 * Why this is native and not just_audio's AndroidEqualizer: that one must be
 * built into the player's pipeline up front, and on a device that cannot create
 * the effect it throws out of play(). Here every effect is created on demand,
 * each in its own try/catch; a device that cannot do something simply reports
 * it, and playback is never involved.
 *
 * The contract is declarative. Dart sends the whole desired state ("these
 * sessions, these levels"); this class releases what is no longer wanted,
 * creates what is missing and updates the rest. Calling sync with no sessions
 * releases everything, which also gives back the low-power audio path (an
 * attached effect disables decode offload).
 *
 * All effect work runs on one background thread: creating an effect can block
 * for tens of milliseconds and must never stall the UI.
 */
final class EqualizerChannel implements MethodChannel.MethodCallHandler {
    static final String NAME = "mine_music/equalizer";

    private final AudioManager audio;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    /** audio session id -> its effects. Touched only on [worker]. */
    private final Map<Integer, Fx> live = new HashMap<>();

    private static final class Fx {
        Equalizer eq;
        BassBoost bass;
        Virtualizer virt;
        LoudnessEnhancer loud;

        void release() {
            try { if (eq != null) eq.release(); } catch (Throwable ignored) { }
            try { if (bass != null) bass.release(); } catch (Throwable ignored) { }
            try { if (virt != null) virt.release(); } catch (Throwable ignored) { }
            try { if (loud != null) loud.release(); } catch (Throwable ignored) { }
            eq = null; bass = null; virt = null; loud = null;
        }
    }

    private EqualizerChannel(AudioManager audio) {
        this.audio = audio;
    }

    static void register(AudioManager audio, BinaryMessenger messenger) {
        new MethodChannel(messenger, NAME).setMethodCallHandler(new EqualizerChannel(audio));
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "probe":
                worker.execute(() -> reply(result, probe()));
                break;
            case "sync": {
                final List<Integer> sessions = new ArrayList<>();
                final List<?> rawSessions = call.argument("sessions");
                if (rawSessions != null) {
                    for (Object o : rawSessions) {
                        if (o instanceof Number) sessions.add(((Number) o).intValue());
                    }
                }
                final List<Integer> levels = new ArrayList<>();
                final List<?> rawLevels = call.argument("levelsMb");
                if (rawLevels != null) {
                    for (Object o : rawLevels) {
                        levels.add(o instanceof Number ? ((Number) o).intValue() : 0);
                    }
                }
                final int bass = intArg(call, "bass");
                final int virt = intArg(call, "virt");
                final int loud = intArg(call, "loudnessMb");
                worker.execute(() -> reply(result, sync(sessions, levels, bass, virt, loud)));
                break;
            }
            case "release":
                worker.execute(() -> {
                    releaseAll();
                    reply(result, null);
                });
                break;
            default:
                result.notImplemented();
        }
    }

    private static int intArg(MethodCall call, String key) {
        Object v = call.argument(key);
        return v instanceof Number ? ((Number) v).intValue() : 0;
    }

    private void reply(MethodChannel.Result result, Object value) {
        main.post(() -> result.success(value));
    }

    // ── probe ────────────────────────────────────────────────────────────────

    /** A throwaway session to read what this device's effects can do. */
    private Map<String, Object> probe() {
        Map<String, Object> m = new HashMap<>();
        m.put("available", false);
        m.put("engine", "Android audio effects");
        int session = audio.generateAudioSessionId();
        if (session <= 0) {
            return m;
        }

        Equalizer eq = null;
        try {
            eq = new Equalizer(0, session);
            short bands = eq.getNumberOfBands();
            short[] range = eq.getBandLevelRange();
            List<Map<String, Object>> list = new ArrayList<>();
            for (short i = 0; i < bands; i++) {
                int[] r = eq.getBandFreqRange(i);
                Map<String, Object> b = new HashMap<>();
                // The platform speaks milliHertz.
                b.put("centerHz", eq.getCenterFreq(i) / 1000.0);
                b.put("lowHz", r[0] / 1000.0);
                b.put("highHz", r[1] / 1000.0);
                list.add(b);
            }
            m.put("bands", list);
            m.put("minDb", range[0] / 100.0);
            m.put("maxDb", range[1] / 100.0);
            m.put("available", bands > 0);
        } catch (Throwable t) {
            m.put("available", false);
        } finally {
            if (eq != null) {
                try { eq.release(); } catch (Throwable ignored) { }
            }
        }

        BassBoost b = null;
        try {
            b = new BassBoost(0, session);
            m.put("bassBoost", b.getStrengthSupported());
        } catch (Throwable t) {
            m.put("bassBoost", false);
        } finally {
            if (b != null) {
                try { b.release(); } catch (Throwable ignored) { }
            }
        }

        Virtualizer v = null;
        try {
            v = new Virtualizer(0, session);
            m.put("virtualizer", v.getStrengthSupported());
        } catch (Throwable t) {
            m.put("virtualizer", false);
        } finally {
            if (v != null) {
                try { v.release(); } catch (Throwable ignored) { }
            }
        }

        LoudnessEnhancer l = null;
        try {
            l = new LoudnessEnhancer(session);
            m.put("loudness", true);
        } catch (Throwable t) {
            m.put("loudness", false);
        } finally {
            if (l != null) {
                try { l.release(); } catch (Throwable ignored) { }
            }
        }
        return m;
    }

    // ── sync ─────────────────────────────────────────────────────────────────

    private Map<String, Object> sync(List<Integer> sessions, List<Integer> levels,
                                     int bass, int virt, int loudMb) {
        Set<Integer> want = new HashSet<>(sessions);

        // Release sessions that are no longer wanted.
        for (Iterator<Map.Entry<Integer, Fx>> it = live.entrySet().iterator(); it.hasNext(); ) {
            Map.Entry<Integer, Fx> e = it.next();
            if (!want.contains(e.getKey())) {
                e.getValue().release();
                it.remove();
            }
        }

        boolean anyEq = false;
        boolean any = false;
        for (Integer session : want) {
            if (session == null || session <= 0) continue;
            Fx fx = live.get(session);
            if (fx == null) {
                fx = new Fx();
                live.put(session, fx);
            }
            if (fx.eq == null) {
                try { fx.eq = new Equalizer(0, session); } catch (Throwable ignored) { }
            }
            if (fx.bass == null && bass > 0) {
                try { fx.bass = new BassBoost(0, session); } catch (Throwable ignored) { }
            }
            if (fx.virt == null && virt > 0) {
                try { fx.virt = new Virtualizer(0, session); } catch (Throwable ignored) { }
            }
            if (fx.loud == null && loudMb > 0) {
                try { fx.loud = new LoudnessEnhancer(session); } catch (Throwable ignored) { }
            }
            apply(fx, levels, bass, virt, loudMb);
            if (fx.eq != null) anyEq = true;
            if (fx.eq != null || fx.bass != null || fx.virt != null || fx.loud != null) any = true;
        }

        Map<String, Object> out = new HashMap<>();
        out.put("ok", want.isEmpty() || any);
        out.put("eq", want.isEmpty() || anyEq);
        out.put("sessions", live.size());
        return out;
    }

    private void apply(Fx fx, List<Integer> levels, int bass, int virt, int loudMb) {
        if (fx.eq != null) {
            try {
                short[] range = fx.eq.getBandLevelRange();
                short count = fx.eq.getNumberOfBands();
                for (short i = 0; i < count; i++) {
                    int mb = i < levels.size() ? levels.get(i) : 0;
                    if (mb < range[0]) mb = range[0];
                    if (mb > range[1]) mb = range[1];
                    fx.eq.setBandLevel(i, (short) mb);
                }
                fx.eq.setEnabled(true);
            } catch (Throwable ignored) { }
        }
        if (fx.bass != null) {
            try {
                if (fx.bass.getStrengthSupported()) {
                    fx.bass.setStrength((short) Math.max(0, Math.min(1000, bass)));
                }
                fx.bass.setEnabled(bass > 0);
            } catch (Throwable ignored) { }
        }
        if (fx.virt != null) {
            try {
                if (fx.virt.getStrengthSupported()) {
                    fx.virt.setStrength((short) Math.max(0, Math.min(1000, virt)));
                }
                fx.virt.setEnabled(virt > 0);
            } catch (Throwable ignored) { }
        }
        if (fx.loud != null) {
            try {
                fx.loud.setTargetGain(Math.max(0, loudMb));
                fx.loud.setEnabled(loudMb > 0);
            } catch (Throwable ignored) { }
        }
    }

    private void releaseAll() {
        for (Fx fx : live.values()) {
            fx.release();
        }
        live.clear();
    }
}
