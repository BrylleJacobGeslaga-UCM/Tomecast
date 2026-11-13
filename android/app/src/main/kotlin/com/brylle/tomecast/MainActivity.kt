package com.brylle.tomecast

import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (instead of FlutterActivity) lets the background
// audio service and the app UI share the same Flutter engine.
class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // "tomecast/audio": decodes audio for live read-along syncing.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tomecast/audio")
            .setMethodCallHandler { call, result ->
                if (call.method != "decodeToWav") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")!!
                val startMs = call.argument<Number>("startMs")!!.toLong()
                val durationMs = call.argument<Number>("durationMs")!!.toLong()
                val outPath = call.argument<String>("outPath")!!
                val main = Handler(Looper.getMainLooper())

                // Decoding takes a moment: do it off the main thread.
                Thread {
                    try {
                        val ms = PcmDecoder.decodeToWav(path, startMs, durationMs, outPath)
                        main.post { result.success(ms) }
                    } catch (e: Exception) {
                        main.post { result.error("DECODE_FAILED", e.message, null) }
                    }
                }.start()
            }
    }
}
