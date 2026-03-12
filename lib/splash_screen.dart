import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'login_screen.dart';

/// New splash: fast glitch -> instant show "ConfigTool" -> animated "Granite" colors
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

enum _Phase { glitch, showConfig, showGranite }

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _glitchController; // drives jitter and flashes
  late final AnimationController
  _configShowController; // quick pop for ConfigTool
  late final AnimationController
  _graniteColorController; // drives granite colors

  _Phase _phase = _Phase.glitch;

  @override
  void initState() {
    super.initState();

    // slower glitch ticks for a less frantic feel
    _glitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();

    // ConfigTool pop-in scale (slightly slower)
    _configShowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    // Granite color cycling (slower cycle)
    _graniteColorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Phase timeline: glitch ~1100ms, then ConfigTool appears, after 420ms Granite appears
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() => _phase = _Phase.showConfig);
      _glitchController.stop();
      _configShowController.forward();

      Future.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        setState(() => _phase = _Phase.showGranite);
        // granite controller already repeating; keep it running
        // navigate to home after a short total delay so user sees the result
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const LoginScreen(),
              transitionDuration: const Duration(milliseconds: 1200),
              transitionsBuilder: (_, animation, __, child) {
                // Fade in
                return FadeTransition(
                  opacity: animation,
                  // Scale slightly from 1.1 down to 1.0
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.1, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
            ),
          );
        });
      });
    });
  }

  @override
  void dispose() {
    _glitchController.dispose();
    _configShowController.dispose();
    _graniteColorController.dispose();
    super.dispose();
  }

  // Granite shades palette interpolation
  Color _graniteShade(double t) {
    const shades = [
      Color(0xFF9A0E0E),
      Color(0xFFB21A1A),
      Color(0xFFC73939),
      Color(0xFFDF4E4E),
    ];
    final pos = (t * (shades.length - 1)).clamp(0.0, shades.length - 1.0);
    final i = pos.floor();
    final f = pos - i;
    return Color.lerp(
      shades[i],
      shades[(i + 1).clamp(0, shades.length - 1)],
      f,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _glitchController,
              _configShowController,
              _graniteColorController,
            ]),
            builder: (context, _) {
              // compute glitch offsets and flash intensity
              final g = _glitchController.value; // 0..1 rapidly
              final jitterX = (_phase == _Phase.glitch)
                  ? (math.sin(g * math.pi * 8) * 10.0)
                  : 0.0;
              final jitterY = (_phase == _Phase.glitch)
                  ? (math.cos(g * math.pi * 6) * 4.0)
                  : 0.0;

              // ConfigTool pop scale
              final pop = 0.8 + 0.2 * _configShowController.value;

              return Transform.translate(
                offset: Offset(jitterX, jitterY),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glitch: draw a sliced/chromatic glitch of the title during glitch phase
                    if (_phase == _Phase.glitch)
                      GlitchText(
                        text: 'ConfigTool',
                        textStyle: TextStyle(
                          color:
                              theme.textTheme.headlineLarge?.color ??
                              colorScheme.onSurface,
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                        t: _glitchController.value,
                        channelRed: colorScheme.primary,
                        channelBlue: colorScheme.secondary,
                      )
                    else
                      // When not glitching, show the popped ConfigTool
                      Transform.scale(
                        scale: pop,
                        child: Text(
                          'ConfigTool',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                theme.textTheme.headlineLarge?.color ??
                                colorScheme.onSurface,
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Granite: appears only after phase moves to showGranite; per-letter color animation
                    if (_phase != _Phase.glitch)
                      Opacity(
                        opacity: _phase == _Phase.showConfig ? 0.0 : 1.0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate('Granite'.length, (i) {
                            final t =
                                (_graniteColorController.value + i * 0.12) %
                                1.0;
                            // Granite letter tint anchored to colorScheme.primary for theme coherence.
                            final base = _graniteShade(t);
                            final col = Color.lerp(
                              base,
                              colorScheme.primary,
                              0.25,
                            )!;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2.0,
                              ),
                              child: Text(
                                'Granite'[i],
                                style: TextStyle(
                                  color: col,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      color: col.withOpacity(0.45),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// _SplashHome removed — was a simple placeholder and is not referenced.

/// Widget that paints a sliced/chromatic glitch effect for a title.
class GlitchText extends StatelessWidget {
  final String text;
  final TextStyle textStyle;
  final double t; // animation progress 0..1
  final Color? channelRed;
  final Color? channelBlue;

  const GlitchText({
    super.key,
    required this.text,
    required this.textStyle,
    required this.t,
    this.channelRed,
    this.channelBlue,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(360, 80),
      painter: _GlitchPainter(
        text: text,
        textStyle: textStyle,
        t: t,
        channelRed: channelRed,
        channelBlue: channelBlue,
      ),
    );
  }
}

class _GlitchPainter extends CustomPainter {
  final String text;
  final TextStyle textStyle;
  final double t;
  final Color? channelRed;
  final Color? channelBlue;

  _GlitchPainter({
    required this.text,
    required this.textStyle,
    required this.t,
    this.channelRed,
    this.channelBlue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    final cx = (size.width - tp.width) / 2;
    final cy = (size.height - tp.height) / 2;

    // Draw multiple slices with small translations and RGB offsets.
    final slices = 6;
    final sliceH = tp.height / slices;

    for (var i = 0; i < slices; i++) {
      final y0 = cy + i * sliceH;
      final rect = Rect.fromLTWH(cx, y0, tp.width, sliceH);

      // compute per-slice offset using sin waves to avoid randomness
      final phase = (t * 12.0 + i * 1.7);
      final dx = (math.sin(phase) * 18.0) * (1.0 - i / slices);
      final dy = (math.cos(phase * 0.7) * 3.0) * (i.isEven ? 1 : -1);

      canvas.save();
      canvas.clipRect(rect);
      canvas.translate(dx, dy);

      // Draw red channel slightly offset
      final redPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: textStyle.copyWith(
            color: (channelRed ?? Colors.red).withOpacity(0.9),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      redPainter.paint(canvas, Offset(cx + 2.0, cy));

      // Draw blue channel slightly opposite offset
      final bluePainter = TextPainter(
        text: TextSpan(
          text: text,
          style: textStyle.copyWith(
            color: (channelBlue ?? Colors.blue).withOpacity(0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bluePainter.paint(canvas, Offset(cx - 2.0, cy));

      // Draw base white
      tp.paint(canvas, Offset(cx, cy));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.text != text;
}
