import 'package:flutter/services.dart';

/// Talks to the Android side (PcmDecoder.kt) to turn a piece of an audio
/// file (m4b, mp3, ...) into the 16 kHz mono WAV that Whisper needs.
class PcmDecoder {
  static const _channel = MethodChannel('tomecast/audio');

  /// Decodes [length] of [audioPath] starting at [start] into [wavPath].
  /// Returns how much audio was actually written (less at the end of a file).
  static Future<Duration> decodeToWav({
    required String audioPath,
    required Duration start,
    required Duration length,
    required String wavPath,
  }) async {
    final ms = await _channel.invokeMethod<int>('decodeToWav', {
      'path': audioPath,
      'startMs': start.inMilliseconds,
      'durationMs': length.inMilliseconds,
      'outPath': wavPath,
    });
    return Duration(milliseconds: ms ?? 0);
  }
}
