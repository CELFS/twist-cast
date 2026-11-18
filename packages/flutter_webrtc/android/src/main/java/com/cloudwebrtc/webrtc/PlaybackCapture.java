package com.cloudwebrtc.webrtc;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioPlaybackCaptureConfiguration;
import android.media.AudioRecord;
import android.media.projection.MediaProjection;
import android.os.Build;
import java.nio.ByteBuffer;

/** Internal playback only. No microphone is created, even on capture failure. */
public final class PlaybackCapture {
    private static MediaProjection projection;
    private static AudioRecord recorder;
    private static boolean enabled;
    private static int rate;
    private static int channels;
    public static Runnable onStopped;

    public static synchronized void attach(MediaProjection value) {
        projection = value;
    }

    public static synchronized void setEnabled(boolean value) {
        enabled = value;
        releaseRecorder();
        if (value) {
            if (Build.VERSION.SDK_INT < 29 || projection == null) {
                throw new IllegalStateException("Playback capture unavailable");
            }
            createRecorder(48000, 1);
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
        recorder = new AudioRecord.Builder().setAudioPlaybackCaptureConfig(config)
            .setAudioFormat(new AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate).setChannelMask(channelMask).build())
            .setBufferSizeInBytes(Math.max(minimum * 2, sampleRate * channelCount / 5)).build();
        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            releaseRecorder();
            throw new IllegalStateException("Playback recorder initialization failed");
        }
        rate = sampleRate;
        channels = channelCount;
        recorder.startRecording();
    }

    public static synchronized long fill(ByteBuffer buffer, int format, int channelCount,
            int sampleRate, int bytesRead, long timestamp) {
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
