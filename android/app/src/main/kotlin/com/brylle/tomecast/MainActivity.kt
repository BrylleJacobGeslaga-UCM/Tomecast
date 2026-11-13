package com.brylle.tomecast

import android.media.MediaMetadataRetriever
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
                if (call.method == "fileInfo") {
                    readFileInfo(call.argument<List<String>>("paths")!!, result)
                    return@setMethodCallHandler
                }
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

    /** Length and title tag of each audio file (for hours/percent display). */
    private fun readFileInfo(paths: List<String>, result: MethodChannel.Result) {
        val main = Handler(Looper.getMainLooper())
        Thread {
            val info = paths.map { path ->
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(path)
                    mapOf(
                        "durationMs" to (retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L),
                        "title" to retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_TITLE),
                    )
                } catch (e: Exception) {
                    mapOf("durationMs" to 0L, "title" to null)
                } finally {
                    retriever.release()
                }
            }
            main.post { result.success(info) }
        }.start()
    }
}
