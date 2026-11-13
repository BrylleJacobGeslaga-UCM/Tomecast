import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ornaments.dart';
import '../theme/tome_theme.dart';
import 'library_screen.dart';

/// Short animated intro: the tome appears inside a turning rune ring,
/// glows, and "TOMECAST" fades in. Then fades into the library.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Book + title entrance
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  // Slow rune ring rotation + glow pulse (loops)
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), _goToLibrary);
  }

  void _goToLibrary() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, __, ___) => const LibraryScreen(),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  void dispose() {
    _intro.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    final theme = Theme.of(context);

    // Parts of the intro, one after another.
    final ring = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.5, curve: Curves.easeOut));
    final book = CurvedAnimation(parent: _intro, curve: const Interval(0.15, 0.65, curve: Curves.easeOutBack));
    final title = CurvedAnimation(parent: _intro, curve: const Interval(0.55, 1, curve: Curves.easeOut));

    return Scaffold(
      backgroundColor: p.bgBottom,
      body: TomeBackground(
        runes: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 260,
                height: 260,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_intro, _spin]),
                  builder: (context, _) {
                    final pulse = 0.5 + 0.5 * math.sin(_spin.value * 2 * math.pi * 4);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Glow
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: p.glow.withValues(
                                    alpha: (p.dark ? 0.25 : 0.15) * book.value * (0.6 + 0.4 * pulse)),
                                blurRadius: 60,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        // Turning rune ring
                        Opacity(
                          opacity: ring.value.clamp(0.0, 1.0),
                          child: Transform.rotate(
                            angle: _spin.value * 2 * math.pi,
                            child: CustomPaint(
                              size: const Size(260, 260),
                              painter: _RuneRingPainter(p.dark ? p.glow : p.trim),
                            ),
                          ),
                        ),
                        // The tome (same art as the app icon)
                        Opacity(
                          opacity: book.value.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.7 + 0.3 * book.value,
                            child: Image.asset(
                              'assets/icon/icon_foreground.png',
                              width: 250,
                              height: 250,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: title,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(title),
                  child: Column(
                    children: [
                      Text(
                        'TOMECAST',
                        style: titleFont(theme.textTheme.headlineMedium).copyWith(
                          color: p.trim,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const SizedBox(width: 180, child: OrnateDivider(indent: 0)),
                      const SizedBox(height: 6),
                      Text(
                        'Your tales await',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: p.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuneRingPainter extends CustomPainter {
  final Color color;

  _RuneRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.6;
    canvas.drawCircle(c, r, stroke);
    canvas.drawCircle(c, r - 20, stroke..strokeWidth = 1);

    final marks = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.6;
    const n = 24;
    for (var i = 0; i < n; i++) {
      final a = 2 * math.pi * i / n;
      canvas.save();
      canvas.translate(c.dx + math.cos(a) * (r - 10), c.dy + math.sin(a) * (r - 10));
      canvas.rotate(a + math.pi / 2);
      final path = Path();
      switch (i % 4) {
        case 0:
          path..moveTo(-3, -4)..lineTo(0, 4)..lineTo(3, -4);
        case 1:
          path..moveTo(-3, 0)..lineTo(3, 0)..moveTo(0, -4)..lineTo(0, 4);
        case 2:
          path..moveTo(0, -4)..lineTo(3, 0)..lineTo(0, 4)..lineTo(-3, 0)..close();
        default:
          path..moveTo(-3, -4)..lineTo(3, 4)..moveTo(3, -4)..lineTo(-3, 4);
      }
      canvas.drawPath(path, marks);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RuneRingPainter old) => old.color != color;
}
