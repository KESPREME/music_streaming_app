package com.example.music_streaming_app;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;

/**
 * Decodes an audio file (any container/codec the platform plays: AAC in MP4,
 * Opus in WebM, MP3, FLAC...) to 16-bit PCM at a low sample rate, for analysis
 * only. Nothing here is heard.
 *
 * Mono at 11 025 Hz is 22 KB per second of audio: four minutes of music is
 * about 5 MB, and everything AutoMix measures (the level envelope, the beat,
 * where the music stops) survives that rate. Stereo doubles that, and is what
 * the loudness meter needs: BS.1770 sums the power of the two channels, which
 * a mono downmix cannot reproduce (it read up to 3 dB low on wide mixes). The
 * decoder does the rate conversion itself, so only the small result crosses
 * into Dart.
 *
 * Runs on the caller's thread; the plugin calls it from a background thread.
 */
final class AudioDecoder {
    private AudioDecoder() {}

    /** Thrown for anything that means "this file cannot be analysed". */
    static final class DecodeException extends Exception {
        DecodeException(String message) { super(message); }
        DecodeException(String message, Throwable cause) { super(message, cause); }
    }

    /**
     * @param path        a file path
     * @param outRate     the sample rate to produce, Hz
     * @param maxSeconds  stop after this much audio (a guard against a runaway file)
     * @param outChannels 1 for a mono mix-down, 2 for interleaved left/right
     *                    (a mono source is written to both)
     * @return little-endian 16-bit samples
     */
    static byte[] decodeToPcm16(String path, int outRate, int maxSeconds, int outChannels)
            throws DecodeException {
        final boolean stereo = outChannels >= 2;
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(path);

            int track = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat f = extractor.getTrackFormat(i);
                String mime = f.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) {
                    track = i;
                    format = f;
                    break;
                }
            }
            if (track < 0 || format == null) throw new DecodeException("no audio track");
            extractor.selectTrack(track);

            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
            codec.configure(format, null, null, 0);
            codec.start();

            int srcRate = format.containsKey(MediaFormat.KEY_SAMPLE_RATE)
                    ? format.getInteger(MediaFormat.KEY_SAMPLE_RATE) : 44100;
            int channels = format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                    ? format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) : 2;

            ByteBuffer out = ByteBuffer.allocate(Math.max(1, outRate * 2 * (stereo ? 2 : 1) * 120));
            out.order(ByteOrder.LITTLE_ENDIAN);

            // Box-filter resampler: average every input sample that falls into
            // one output sample. Cheap, and plenty for an analysis signal.
            double step = (double) outRate / srcRate;
            double pos = 0.0;
            double sumL = 0.0;
            double sumR = 0.0;
            int n = 0;
            long maxOut = (long) outRate * maxSeconds;
            long produced = 0;

            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            boolean outputDone = false;
            long idleSpins = 0;

            while (!outputDone && produced < maxOut) {
                if (!inputDone) {
                    int inIndex = codec.dequeueInputBuffer(10_000);
                    if (inIndex >= 0) {
                        ByteBuffer in = codec.getInputBuffer(inIndex);
                        int size = in == null ? -1 : extractor.readSampleData(in, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size,
                                    extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }

                int outIndex = codec.dequeueOutputBuffer(info, 10_000);
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat of = codec.getOutputFormat();
                    if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        srcRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                        step = (double) outRate / srcRate;
                    }
                    if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
                    }
                } else if (outIndex >= 0) {
                    idleSpins = 0;
                    ByteBuffer buf = codec.getOutputBuffer(outIndex);
                    if (buf != null && info.size > 0) {
                        buf.position(info.offset);
                        buf.limit(info.offset + info.size);
                        ShortBuffer shorts = buf.order(ByteOrder.nativeOrder()).asShortBuffer();
                        int frames = shorts.remaining() / Math.max(1, channels);
                        for (int f = 0; f < frames; f++) {
                            // Channels 0 and 1 are left and right; anything past
                            // them (a surround file) is skipped, and a mono file
                            // feeds both sides.
                            int l = shorts.get();
                            int r = channels >= 2 ? shorts.get() : l;
                            for (int c = 2; c < channels; c++) shorts.get();
                            sumL += l;
                            sumR += r;
                            n++;
                            pos += step;
                            if (pos >= 1.0) {
                                pos -= 1.0;
                                if (out.remaining() < 4) out = grow(out);
                                if (stereo) {
                                    out.putShort((short) Math.round(sumL / n));
                                    out.putShort((short) Math.round(sumR / n));
                                } else {
                                    out.putShort((short) Math.round((sumL + sumR) / (2.0 * n)));
                                }
                                produced++;
                                sumL = 0.0;
                                sumR = 0.0;
                                n = 0;
                            }
                        }
                    }
                    codec.releaseOutputBuffer(outIndex, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true;
                    }
                } else if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    // Nothing ready yet. A decoder that never produces is stuck:
                    // give up rather than spin forever.
                    if (inputDone && ++idleSpins > 500) {
                        throw new DecodeException("decoder stalled");
                    }
                }
            }

            byte[] result = new byte[out.position()];
            out.flip();
            out.get(result);
            return result;
        } catch (IOException | IllegalStateException | IllegalArgumentException e) {
            throw new DecodeException("decode failed: " + e.getMessage(), e);
        } finally {
            if (codec != null) {
                try { codec.stop(); } catch (Exception ignored) {}
                try { codec.release(); } catch (Exception ignored) {}
            }
            extractor.release();
        }
    }

    private static ByteBuffer grow(ByteBuffer old) {
        ByteBuffer bigger = ByteBuffer.allocate(old.capacity() * 2);
        bigger.order(ByteOrder.LITTLE_ENDIAN);
        old.flip();
        bigger.put(old);
        return bigger;
    }
}
