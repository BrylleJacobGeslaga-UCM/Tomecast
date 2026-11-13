import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tome_theme.dart';

/// Gradient background with a faint rune circle, like the app icon.
class TomeBackground extends StatelessWidget {
  final Widget child;
  final bool runes;

  const TomeBackground({super.key, required this.child, this.runes = true});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.25,
          colors: [p.bgTop, p.bgBottom],
        ),
      ),
      child: runes
          ? CustomPaint(painter: _RuneCirclePainter(p.trim, p.glow, p.dark), child: child)
          : child,
    );
  }
}

class _RuneCirclePainter extends CustomPainter {
  final Color trim;
  final Color glow;
  final bool dark;

  _RuneCirclePainter(this.trim, this.glow, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.36);
    final r = size.width * 0.62;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = (dark ? glow : trim).withValues(alpha: dark ? 0.07 : 0.12)
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center, r - 18, paint..strokeWidth = 1);

    // Little rune marks between the two rings.
    final marks = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = paint.color;
    for (var i = 0; i < 32; i++) {
      final a = 2 * math.pi * i / 32;
      canvas.save();
      canvas.translate(center.dx + math.cos(a) * (r - 9), center.dy + math.sin(a) * (r - 9));
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
  bool shouldRepaint(_RuneCirclePainter old) =>
      old.trim != trim || old.glow != glow || old.dark != dark;
}

/// A gold (or iron) frame with corner ornaments, optionally glowing.
class OrnateFrame extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool glow;
  final double thickness;

  const OrnateFrame({
    super.key,
    required this.child,
    this.radius = 10,
    this.glow = false,
    this.thickness = 2,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + thickness + 2),
        boxShadow: [
          if (glow)
            BoxShadow(color: p.glow.withValues(alpha: p.dark ? 0.35 : 0.2), blurRadius: 28),
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.5 : 0.18),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _FramePainter(p.trim, p.trimDark, radius, thickness),
        child: Padding(
          padding: EdgeInsets.all(thickness + 2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final Color trim;
  final Color trimDark;
  final double radius;
  final double thickness;

  _FramePainter(this.trim, this.trimDark, this.radius, this.thickness);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
        rect.deflate(thickness / 2), Radius.circular(radius + thickness + 1));
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(trim, Colors.white, 0.35)!, trim, trimDark],
        ).createShader(rect),
    );

    // Corner diamonds
    final gem = Paint()..color = Color.lerp(trim, Colors.white, 0.2)!;
    final s = thickness + 3;
    for (final c in [
      Offset(radius * 0.6, radius * 0.6),
      Offset(size.width - radius * 0.6, radius * 0.6),
      Offset(radius * 0.6, size.height - radius * 0.6),
      Offset(size.width - radius * 0.6, size.height - radius * 0.6),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - s)
          ..lineTo(c.dx + s, c.dy)
          ..lineTo(c.dx, c.dy + s)
          ..lineTo(c.dx - s, c.dy)
          ..close(),
        gem,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.trim != trim || old.trimDark != trimDark || old.radius != radius;
}

/// Gold line with a diamond in the middle.
class OrnateDivider extends StatelessWidget {
  final double indent;

  const OrnateDivider({super.key, this.indent = 24});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    Widget line(bool left) => Expanded(
          child: Container(
            height: 1.2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: left
                    ? [p.trim.withValues(alpha: 0), p.trim]
                    : [p.trim, p.trim.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent, vertical: 6),
      child: Row(children: [
        line(true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 7, height: 7, color: p.trim),
          ),
        ),
        line(false),
      ]),
    );
  }
}

/// Section heading: "✦ TITLE ✦" in the title font.
class OrnateHeading extends StatelessWidget {
  final String text;

  const OrnateHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return Text(
      '✦  ${text.toUpperCase()}  ✦',
      textAlign: TextAlign.center,
      style: titleFont(Theme.of(context).textTheme.titleMedium)
          .copyWith(color: p.trim, letterSpacing: 2),
    );
  }
}

/// Round play/pause "seal": gold ring, dark center, glowing icon.
class MedallionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  const MedallionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 84,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(p.trim, Colors.white, 0.45)!, p.trim, p.trimDark],
          ),
          boxShadow: [
            BoxShadow(color: p.glow.withValues(alpha: p.dark ? 0.45 : 0.25), blurRadius: 26),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(size * 0.07),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: p.dark
                  ? [Color.lerp(p.surface, p.glow, 0.25)!, p.bgBottom]
                  : [p.surface, Color.lerp(p.surface, p.trim, 0.25)!],
            ),
          ),
          child: Icon(icon, size: size * 0.5, color: p.glow),
        ),
      ),
    );
  }
}

/// Placeholder "tome" cover for books without a picture.
class TomeCoverPlaceholder extends StatelessWidget {
  final String title;

  const TomeCoverPlaceholder({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final p = context.tome;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.dark
              ? [const Color(0xFF5A2219), const Color(0xFF2B0D09)]
              : [const Color(0xFF9B5A3A), const Color(0xFF6B3520)],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories, color: p.trim, size: 34),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: titleFont(const TextStyle(fontSize: 11))
                .copyWith(color: const Color(0xFFF1E2BD)),
          ),
        ],
      ),
    );
  }
}
