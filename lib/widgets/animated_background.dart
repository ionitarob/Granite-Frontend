import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Reusable animated background used by login and dashboard screens.
/// Renders a mesh gradient (Aurora) effect using moving blobs.
/// Supports both dark and light themes with configurable intensity.
class AnimatedBackgroundWidget extends StatefulWidget {
  final double intensity;
  const AnimatedBackgroundWidget({Key? key, this.intensity = 1.0})
    : super(key: key);

  @override
  State<AnimatedBackgroundWidget> createState() =>
      _AnimatedBackgroundWidgetState();
}

class _AnimatedBackgroundWidgetState extends State<AnimatedBackgroundWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Blob> _blobs = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Initialize random blobs
    final rng = math.Random();
    for (int i = 0; i < 5; i++) {
      _blobs.add(
        _Blob(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          vx: (rng.nextDouble() - 0.5) * 0.002, // Slow movement
          vy: (rng.nextDouble() - 0.5) * 0.002,
          radius: 0.4 + rng.nextDouble() * 0.4, // Large creates blending
          phase: rng.nextDouble() * 2 * math.pi,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;

        // Define palette based on theme
        final List<Color> palette = dark
            ? [
                const Color(0xFF0F0518), // Deep purple base
                const Color(0xFF4A1984), // Brighter purple
                const Color(0xFF2B0B55),
                const Color(0xFFD61C62).withOpacity(0.6), // Stronger Accent
                theme.colorScheme.primary.withOpacity(0.4),
              ]
            : [
                const Color(0xFFC0CCD9), // Significantly darker base
                const Color(0xFF9FB3C8),
                const Color(0xFFFFCC00).withOpacity(0.6), // Stronger Sun
                const Color(0xFF9F7AEA).withOpacity(0.6), // Stronger Purple
                theme.colorScheme.primary.withOpacity(0.5),
              ];

        // Update blob positions slightly based on time
        for (var blob in _blobs) {
          blob.update();
        }

        return Container(
          color: palette.first, // Background base
          child: CustomPaint(
            painter: _AuroraPainter(
              blobs: _blobs,
              palette: palette,
              t: t,
              isDark: dark,
              intensity: widget.intensity,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _Blob {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  double phase;

  _Blob({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.phase,
  });

  void update() {
    // Lissajous-like movement with boundary bounce
    x += vx;
    y += vy;
    // Soft bounce with some margin to keep blobs on screen
    if (x < -0.3 || x > 1.3) vx = -vx;
    if (y < -0.3 || y > 1.3) vy = -vy;
  }
}

class _AuroraPainter extends CustomPainter {
  final List<_Blob> blobs;
  final List<Color> palette;
  final double t;
  final bool isDark;
  final double intensity;

  _AuroraPainter({
    required this.blobs,
    required this.palette,
    required this.t,
    required this.isDark,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // We paint multiple radial gradients for a "mesh" effect
    for (int i = 0; i < blobs.length; i++) {
      final blob = blobs[i];
      // color selection loops through palette, skipping index 0 (bg)
      final color = palette[(i % (palette.length - 1)) + 1];

      // Dynamic pulsing
      final pulse = math.sin(t * 2 * math.pi + blob.phase) * 0.1;

      final paint = Paint()
        ..shader =
            RadialGradient(
              colors: [
                color.withOpacity(
                  (isDark ? 0.6 : 0.6) * intensity,
                ), // Increased opacity for light mode
                color.withOpacity(0.0),
              ],
              stops: const [0.0, 1.0],
            ).createShader(
              Rect.fromCircle(
                center: Offset(blob.x * size.width, blob.y * size.height),
                radius: size.shortestSide * (blob.radius + pulse),
              ),
            )
        // Use srcOver for light mode to ensure colors are visible against white
        // Use screen for dark mode for glowing effect
        ..blendMode = isDark ? BlendMode.screen : BlendMode.srcOver;

      canvas.drawRect(rect, paint);
    }

    // Optional: Subtle noise/dots on top for texture
    final noisePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(
        0.03 * intensity,
      )
      ..strokeWidth = 1.0;

    final rng = math.Random(42); // Seeded for static noise pattern
    for (int i = 0; i < 100; i++) {
      double dx = rng.nextDouble() * size.width;
      double dy = rng.nextDouble() * size.height;
      canvas.drawPoints(PointMode.points, [Offset(dx, dy)], noisePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => true;
}
