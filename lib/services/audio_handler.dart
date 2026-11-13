import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'playback_service.dart';

/// Connects PlaybackService to Android's media system:
/// the notification, lock screen, Bluetooth/headset buttons, and smartwatches.
class TomecastAudioHandler extends BaseAudioHandler {
  TomecastAudioHandler(this.service) {
    service.player.playbackEventStream.listen((_) => _broadcastState());
    service.player.playingStream.listen((_) => _broadcastState());
    service.addListener(_updateMediaItem);
  }

  final PlaybackService service;
  String? _lastItemKey;

  /// What the notification / lock screen shows (title, cover, length).
  void _updateMediaItem() {
    final book = service.book;
    if (book == null) return;

    final duration = service.player.duration;
    final key = '${service.currentFilePath}|$duration';
    if (key == _lastItemKey) return; // nothing changed
    _lastItemKey = key;

    mediaItem.add(MediaItem(
      id: service.currentFilePath,
      title: book.title,
      artist: 'File ${service.fileIndex + 1} of ${book.files.length}',
      album: book.title,
      duration: duration,
      artUri: book.coverPath != null ? Uri.file(book.coverPath!) : null,
    ));
  }

  /// Buttons and play state shown in the notification.
  void _broadcastState() {
    final player = service.player;
    final playing = service.isPlaying;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
    ));
  }

  // ---- Buttons from the notification, lock screen and headset ----

  @override
  Future<void> play() => service.play();

  @override
  Future<void> pause() => service.pause();

  @override
  Future<void> seek(Duration position) => service.seekTo(position);

  @override
  Future<void> rewind() => service.seekBy(const Duration(seconds: -10));

  @override
  Future<void> fastForward() => service.seekBy(const Duration(seconds: 10));

  // Headset "next/previous" (e.g. double/triple tap on earbuds):
  // skip 30 seconds instead of jumping a whole file.
  @override
  Future<void> skipToNext() => service.seekBy(const Duration(seconds: 30));

  @override
  Future<void> skipToPrevious() => service.seekBy(const Duration(seconds: -30));

  @override
  Future<void> stop() async {
    await service.pause();
    await super.stop();
  }
}
