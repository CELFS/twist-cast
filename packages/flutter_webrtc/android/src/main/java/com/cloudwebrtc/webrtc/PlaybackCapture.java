package com.cloudwebrtc.webrtc;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioPlaybackCaptureConfiguration;
import android.media.AudioRecord;
import android.media.projection.MediaProjection;
import android.os.Build;
import android.os.SystemClock;
import java.nio.ByteBuffer;

/** Internal playback only. No microphone is created, even on capture failure. */
public final class PlaybackCapture {
    private static MediaProjection projection;
    private static AudioRecord recorder;
    private static boolean enabled;
    private static int rate;
    private static int channels;
    private static final ThreadLocal<long[]> nextFrameTimeNs =
        ThreadLocal.withInitial(() -> new long[1]);
    public static Runnable onStopped;

    public static synchronized void attach(MediaProjection value) {
        projection = value;
    }

    public static synchronized void setEnabled(boolean value) {
        if (enabled == value) return;
        enabled = false;
        releaseRecorder();
        if (value) {
            if (Build.VERSION.SDK_INT < 29 || projection == null) {
                throw new IllegalStateException("Playback capture unavailable");
            }
            createRecorder(48000, 1);
            enabled = true;
        }
    }

    private static void createRecorder(int sampleRate, int channelCount) {
        if (Build.VERSION.SDK_INT < 29) throw new IllegalStateException("Android 10 required");
        int channelMask = channelCount == 2 ? AudioFormat.CHANNEL_IN_STEREO : AudioFormat.CHANNEL_IN_MONO;
        AudioPlaybackCaptureConfiguration config = new AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN).build();
        int minimum = AudioRecord.getMinBufferSize(sampleRate, channelMask, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0) throw new IllegalStateException("Unsupported playback audio format");
        AudioRecord created = new AudioRecord.Builder().setAudioPlaybackCaptureConfig(config)
            .setAudioFormat(new AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate).setChannelMask(channelMask).build())
            .setBufferSizeInBytes(Math.max(minimum * 2, sampleRate * channelCount / 5)).build();
        try {
            if (created.getState() != AudioRecord.STATE_INITIALIZED) {
                throw new IllegalStateException("Playback recorder initialization failed");
            }
            created.startRecording();
            if (created.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) {
                throw new IllegalStateException("Playback recorder failed to start");
            }
        } catch (RuntimeException error) {
            created.release();
            throw error;
        }
        recorder = created;
        rate = sampleRate;
        channels = channelCount;
    }

    private static void awaitNextFrame(int bytes, int channelCount, int sampleRate) {
        // With WebRTC's microphone disabled, this callback owns the PCM clock,
        // including silent frames. Never wait while holding the recorder lock.
        long durationNs = bytes * 1_000_000_000L / (sampleRate * channelCount * 2L);
        long[] clock = nextFrameTimeNs.get();
        long now = System.nanoTime();
        long deadline = clock[0];
        if (deadline == 0 || now - deadline >= durationNs) deadline = now;
        while (now < deadline) {
            SystemClock.sleep((deadline - now + 999_999L) / 1_000_000L);
            now = System.nanoTime();
        }
        // Drop missed deadlines instead of sending a burst of overdue frames.
        clock[0] = (now - deadline >= durationNs ? now : deadline) + durationNs;
    }

    public static long fill(ByteBuffer buffer, int format, int channelCount,
            int sampleRate, int bytesRead, long timestamp) {
        awaitNextFrame(buffer.capacity(), channelCount, sampleRate);
        synchronized (PlaybackCapture.class) {
            buffer.clear();
            for (int i = 0; i < buffer.capacity(); i++) buffer.put(i, (byte) 0);
            if (!enabled || projection == null) return 0;
            try {
                if (recorder == null || rate != sampleRate || channels != channelCount) {
                    releaseRecorder();
                    createRecorder(sampleRate, channelCount);
                }
                int count = recorder.read(buffer, buffer.capacity(), AudioRecord.READ_NON_BLOCKING);
                if (count < 0) throw new IllegalStateException("Playback read failed");
                buffer.position(0);
                return System.nanoTime();
            } catch (RuntimeException error) {
                enabled = false;
                releaseRecorder();
                // Fail the session rather than quietly substituting another source.
                if (onStopped != null) onStopped.run();
                return 0;
            }
        }
    }

    private static void releaseRecorder() {
        if (recorder != null) {
            try { recorder.stop(); } catch (IllegalStateException ignored) { }
            recorder.release();
            recorder = null;
        }
    }

    public static void stopProjection() {
        MediaProjection active;
        synchronized (PlaybackCapture.class) { active = projection; close(); }
        if (active != null) active.stop();
    }

    public static synchronized void close() {
        enabled = false;
        releaseRecorder();
        projection = null;
    }
}
