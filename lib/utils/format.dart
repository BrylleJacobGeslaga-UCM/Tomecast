/// 75 seconds → "1:15", 3725 seconds → "1:02:05"
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// 1.0 → "1.0x", 1.25 → "1.25x", 1.5 → "1.5x"
String formatSpeed(double speed) {
  var t = speed.toStringAsFixed(2);
  if (t.endsWith('0')) t = t.substring(0, t.length - 1);
  return '${t}x';
}
