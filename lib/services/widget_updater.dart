import 'package:home_widget/home_widget.dart';

import 'playback_service.dart';

/// Keeps the home screen widget showing the current book and play state.
class WidgetUpdater {
  static String _last = '';

  static void start() {
    final service = PlaybackService.instance;
    service.addListener(() => _update(service));
  }

  static Future<void> _update(PlaybackService service) async {
    final book = service.book;
    final title = book?.title;
    final subtitle = book == null
        ? null
        : 'File ${service.fileIndex + 1} of ${book.files.length}';
    final playing = service.isPlaying;
    final cover = book?.coverPath;

    // The service notifies often (e.g. every second with a sleep timer):
    // only touch the widget when something it shows has changed.
    final key = '$title|$subtitle|$playing|$cover';
    if (key == _last) return;
    _last = key;

    try {
      await HomeWidget.saveWidgetData<String>('title', title);
      await HomeWidget.saveWidgetData<String>('subtitle', subtitle);
      await HomeWidget.saveWidgetData<bool>('playing', playing);
      await HomeWidget.saveWidgetData<String>('cover', cover);
      await HomeWidget.updateWidget(androidName: 'TomecastWidgetProvider');
    } catch (_) {
      // No widget on the home screen, or not supported: ignore.
    }
  }
}
