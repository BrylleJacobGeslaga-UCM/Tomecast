package com.brylle.tomecast

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Decodes part of an audio file (m4b, m4a, mp3, ...) with Android's built-in
 * decoders and writes it as a 16 kHz, mono, 16-bit WAV (what Whisper needs).
 */
object PcmDecoder {
    private const val TARGET_RATE = 16000

    /** Returns the length of audio written, in milliseconds. */
    fun decodeToWav(path: String, startMs: Long, durationMs: Long, outPath: String): Long {
        val extractor = MediaExtractor()
        extractor.setDataSource(path)

        var track = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                track = i
                format = f
                break
            }
        }
        if (track < 0 || format == null) {
            extractor.release()
            throw IllegalArgumentException("No audio track in $path")
        }
        val fmt: MediaFormat = format
        extractor.selectTrack(track)

        val codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(fmt, null, null, 0)
        codec.start()

        var sampleRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var floatPcm = false

        val startUs = startMs * 1000
        val endUs = (startMs + durationMs) * 1000
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

        val mono = ShortBuilder()
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false

        try {
            while (!outputDone) {
                // Feed compressed audio into the decoder.
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buffer = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0 || extractor.sampleTime > endUs + 500_000) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // Collect decoded PCM, mixed down to mono.
                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = codec.outputFormat
                    sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                } else if (outIndex >= 0) {
                    if (info.size > 0) {
                        val buffer = codec.getOutputBuffer(outIndex)!!
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        appendMono(buffer.slice().order(ByteOrder.nativeOrder()),
                            info.presentationTimeUs, sampleRate, channels, floatPcm,
                            startUs, endUs, mono)
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true
                    }
                }
            }
        } finally {
            codec.stop()
            codec.release()
            extractor.release()
        }

        val resampled = resample(mono.toArray(), sampleRate)
        writeWav(File(outPath), resampled)
        return resampled.size * 1000L / TARGET_RATE
    }

    private fun appendMono(
        buffer: ByteBuffer, ptsUs: Long, rate: Int, channels: Int, isFloat: Boolean,
        startUs: Long, endUs: Long, out: ShortBuilder,
    ) {
        val bytesPerSample = if (isFloat) 4 else 2
        val frames = buffer.remaining() / (bytesPerSample * channels)
        for (frame in 0 until frames) {
            val t = ptsUs + frame * 1_000_000L / rate
            if (t < startUs) continue
            if (t >= endUs) return
            var sum = 0f
            for (c in 0 until channels) {
                val index = (frame * channels + c) * bytesPerSample
                sum += if (isFloat) buffer.getFloat(index) * 32767f
                       else buffer.getShort(index).toFloat()
            }
            out.add((sum / channels).coerceIn(-32768f, 32767f).toInt().toShort())
        }
    }

    /** Downsample to 16 kHz by averaging (also acts as a simple low-pass filter). */
    private fun resample(src: ShortArray, rate: Int): ShortArray {
        if (rate == TARGET_RATE) return src
        val ratio = rate.toDouble() / TARGET_RATE
        val n = (src.size / ratio).toInt()
        return ShortArray(n) { i ->
            val from = (i * ratio).toInt()
            val to = minOf(((i + 1) * ratio).toInt(), src.size).coerceAtLeast(from + 1)
            var sum = 0L
            for (j in from until minOf(to, src.size)) sum += src[j]
            (sum / (to - from)).toInt().toShort()
        }
    }

    private fun writeWav(file: File, samples: ShortArray) {
        file.parentFile?.mkdirs()
        val dataSize = samples.size * 2
        DataOutputStream(FileOutputStream(file).buffered()).use { out ->
            fun intLE(v: Int) = out.write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array())
            fun shortLE(v: Int) = out.write(ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(v.toShort()).array())
            out.writeBytes("RIFF"); intLE(36 + dataSize); out.writeBytes("WAVE")
            out.writeBytes("fmt "); intLE(16); shortLE(1); shortLE(1)
            intLE(TARGET_RATE); intLE(TARGET_RATE * 2); shortLE(2); shortLE(16)
            out.writeBytes("data"); intLE(dataSize)
            val bytes = ByteBuffer.allocate(dataSize).order(ByteOrder.LITTLE_ENDIAN)
            for (s in samples) bytes.putShort(s)
            out.write(bytes.array())
        }
    }

    /** Growable ShortArray. */
    private class ShortBuilder {
        private var data = ShortArray(16000 * 40)
        private var size = 0
        fun add(v: Short) {
            if (size == data.size) data = data.copyOf(data.size * 2)
            data[size++] = v
        }
        fun toArray(): ShortArray = data.copyOf(size)
    }
}
