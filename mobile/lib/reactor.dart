import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decorative motion reflects the conversation state; it is not an audio meter.
class JarvisReactor extends StatefulWidget {
  final bool active, speaking, thinking;
  const JarvisReactor({
    super.key,
    required this.active,
    required this.speaking,
    required this.thinking,
  });
  @override
  State<JarvisReactor> createState() => _JarvisReactorState();
}

class _JarvisReactorState extends State<JarvisReactor>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  @override
  void initState() {
    super.initState();
    if (widget.active || widget.speaking || widget.thinking) clock.repeat();
  }

  @override
  void didUpdateWidget(covariant JarvisReactor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active || widget.speaking || widget.thinking) {
      if (!clock.isAnimating) clock.repeat();
    } else {
      clock.stop();
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final label = widget.speaking
        ? 'RISPOSTA VOCALE'
        : widget.thinking
        ? 'ELABORAZIONE'
        : widget.active
        ? 'IN ASCOLTO'
        : 'SISTEMI PRONTI';
    return Semantics(
      label: label,
      child: RepaintBoundary(
        child: SizedBox(
          height: 255,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: clock,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: ReactorPainter(
                      phase: reduced ? 0 : clock.value * math.pi * 2,
                      speaking: widget.speaking,
                      active: widget.active,
                      thinking: widget.thinking,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 5,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: widget.speaking
                          ? const Color(0xffa5faff)
                          : const Color(0xff54c6d5),
                      fontSize: 10,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReactorPainter extends CustomPainter {
  final double phase;
  final bool speaking, active, thinking;
  ReactorPainter({
    required this.phase,
    required this.speaking,
    required this.active,
    required this.thinking,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 - 10);
    final r = math.min(size.width / 2 - 14, 105.0);
    const color = Color(0xff2ed9ee);
    final pulse = speaking
        ? .5 + .5 * math.sin(phase * 19)
        : .35 + .15 * math.sin(phase * 3);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: speaking ? .26 : .10),
          color.withValues(alpha: .025),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.35));
    canvas.drawCircle(c, r * 1.35, glow);
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = color.withValues(alpha: .15);
    for (final ratio in [.98, .89, .68]) {
      canvas.drawCircle(c, r * ratio, thin);
    }
    for (var i = 0; i < 72; i++) {
      final a = i * math.pi * 2 / 72;
      final big = i % 6 == 0;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r,
        c + Offset(math.cos(a), math.sin(a)) * (r + (big ? 6 : 2)),
        Paint()
          ..color = color.withValues(alpha: big ? 0.65 : .25)
          ..strokeWidth = big ? 1.2 : .7,
      );
    }
    for (var layer = 0; layer < 3; layer++) {
      final radius = r * (.83 - layer * .14);
      final turn = phase * (layer % 2 == 0 ? 1 : -1) * (thinking ? 2 : 1);
      for (var i = 0; i < 3; i++) {
        final start = turn + i * math.pi * 2 / 3;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius),
          start,
          math.pi * (layer == 0 ? 0.43 : .29),
          false,
          Paint()
            ..color = color.withValues(alpha: layer == 0 ? 0.78 : .38)
            ..style = PaintingStyle.stroke
            ..strokeWidth = layer == 0 ? 4 : 2
            ..strokeCap = StrokeCap.butt,
        );
      }
    }
    // Quiet, geometric core expands while the assistant is speaking.
    final core = r * (.27 + .025 * pulse);
    canvas.drawCircle(
      c,
      core * 1.4,
      Paint()
        ..color = color.withValues(alpha: .11 + .1 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xffc9fdff), Color(0xff27d8f4), Color(0xff057baf)],
        ).createShader(Rect.fromCircle(center: c, radius: core)),
    );
    canvas.drawCircle(
      c,
      core * 1.18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: .65),
    );
    for (var i = 0; i < 32; i++) {
      final a = i * math.pi * 2 / 32;
      final extension = speaking
          ? 2 + 12 * (.5 + .5 * math.sin(phase * 23 + i * .85))
          : active
          ? 2 + 4 * (.5 + .5 * math.sin(phase * 8 + i))
          : 2.0;
      final start = r * .41;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * start,
        c + Offset(math.cos(a), math.sin(a)) * (start + extension),
        Paint()
          ..color = color.withValues(alpha: speaking ? 0.9 : .35)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    // Short guide lines evoke a HUD without pretending to show system statistics.
    for (final side in [-1, 1]) {
      final x = c.dx + side * (r + 15);
      canvas.drawLine(Offset(x, c.dy - 28), Offset(x, c.dy + 28), thin);
      canvas.drawLine(
        Offset(x, c.dy),
        Offset(x + side * 16, c.dy),
        Paint()
          ..color = color.withValues(alpha: .6)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x, c.dy), 2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant ReactorPainter old) =>
      phase != old.phase ||
      speaking != old.speaking ||
      active != old.active ||
      thinking != old.thinking;
}
