import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Overlay micro-animations that play on top of the pet inside the pet
/// screen's Stack. All self-contained: each widget runs its own
/// controller and calls [onDone] when finished so the screen can remove
/// it. Pure Flutter — no image assets, no new packages.
///
/// All three take [size], the side length of the square pet box they are
/// positioned inside (the pet creature's own coordinate space). The
/// Stack uses `clipBehavior: Clip.none`, so particles may fly outside
/// the box freely.

/// A snack arcs along a curved path from below (as if tossed from the
/// Feed button) into the pet's mouth, shrinking as it arrives.
class SnackArc extends StatefulWidget {
  final double size;
  final VoidCallback onDone;

  const SnackArc({super.key, required this.size, required this.onDone});

  @override
  State<SnackArc> createState() => _SnackArcState();
}

class _SnackArcState extends State<SnackArc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Quadratic bezier: from below, wide left arc, into the mouth.
  Offset _pos(double t) {
    final s = widget.size;
    final p0 = Offset(s * 0.5, s + 40); // tossed up from below
    final p1 = Offset(s * 0.02, s * 0.55); // wide left arc
    final p2 = Offset(s * 0.5, s * 0.60); // the mouth
    final u = 1 - t;
    return p0 * u * u + p1 * 2 * u * t + p2 * t * t;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeIn.transform(_controller.value);
          final pos = _pos(t);
          final fade = (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0);
          final scale = 1.0 - 0.45 * t;
          return Stack(
            children: [
              Positioned(
                left: pos.dx - 15,
                top: pos.dy - 15,
                child: Opacity(
                  opacity: fade,
                  child: Transform.scale(
                    scale: scale,
                    child: const Text('🍪',
                        style: TextStyle(fontSize: 30)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A ball drops from above and bounces with real gravity (fixed-step
/// sim, restitution 0.55) in front of the pet, with a little shadow.
/// The pet's happy wiggle fires from the Play action itself, so the
/// bounce reads as the pet reacting to the ball.
class BallBounce extends StatefulWidget {
  final double size;
  final VoidCallback onDone;

  const BallBounce({super.key, required this.size, required this.onDone});

  @override
  State<BallBounce> createState() => _BallBounceState();
}

class _BallBounceState extends State<BallBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _simSeconds = 1.15;
  static const _gravity = 2600.0; // px/s^2
  static const _restitution = 0.55;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Cheap fixed-step gravity sim. 120 steps per frame is nothing.
  double _ballY(double t) {
    final s = widget.size;
    final ground = s * 0.90;
    double y = -s * 0.35;
    double v = 0;
    double time = 0;
    const dt = 1 / 120;
    final target = t * _simSeconds;
    while (time < target) {
      v += _gravity * dt;
      y += v * dt;
      if (y >= ground) {
        y = ground;
        v = -v * _restitution;
        if (v.abs() < 80) v = 0; // settled
      }
      if (v == 0 && y >= ground) break;
      time += dt;
    }
    return y;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final s = widget.size;
          final ground = s * 0.90;
          final y = _ballY(t);
          final x = s * 0.5 + s * 0.22 * Curves.easeOut.transform(t);
          final heightAbove = (ground - y).clamp(0.0, s);
          final shadowScale =
              (1 - heightAbove / (s * 1.2)).clamp(0.25, 1.0);
          return Stack(
            children: [
              // Shadow shrinks/fades as the ball rises.
              Positioned(
                left: x - 17 * shadowScale,
                top: ground + 12,
                child: Opacity(
                  opacity: 0.30 * shadowScale,
                  child: Container(
                    width: 34 * shadowScale,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: x - 15,
                top: y - 15,
                child:
                    const Text('⚽', style: TextStyle(fontSize: 30)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Confetti burst for milestones: ~70 spinning pieces fly out from the
/// pet with gravity, fading as they die. CustomPainter, no assets.
class ConfettiBurst extends StatefulWidget {
  final double size;
  final VoidCallback onDone;

  const ConfettiBurst(
      {super.key, required this.size, required this.onDone});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiParticle {
  final double vx;
  final double vy;
  final double spin;
  final double phase;
  final double size;
  final double life; // seconds
  final Color color;
  final bool circle;

  _ConfettiParticle({
    required this.vx,
    required this.vy,
    required this.spin,
    required this.phase,
    required this.size,
    required this.life,
    required this.color,
    required this.circle,
  });
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;

  static const _palette = [
    Colors.tealAccent,
    Colors.pinkAccent,
    Colors.amberAccent,
    Colors.lightBlueAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
  ];

  @override
  void initState() {
    super.initState();
    final rand = math.Random();
    _particles = List.generate(70, (_) {
      final angle = rand.nextDouble() * math.pi * 2;
      final speed = 140 + rand.nextDouble() * 300;
      return _ConfettiParticle(
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 220, // biased upward
        spin: (rand.nextDouble() - 0.5) * 12,
        phase: rand.nextDouble() * math.pi * 2,
        size: 5 + rand.nextDouble() * 5,
        life: 0.9 + rand.nextDouble() * 0.5,
        color: _palette[rand.nextInt(_palette.length)],
        circle: rand.nextBool(),
      );
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(
            particles: _particles,
            t: _controller.value,
            origin: Offset(widget.size / 2, widget.size / 2),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;

  /// 0..1 progress of the burst.
  final double t;
  final Offset origin;

  _ConfettiPainter({
    required this.particles,
    required this.t,
    required this.origin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const total = 1.4; // seconds — matches the controller duration
    final age = t * total;
    for (final p in particles) {
      if (age > p.life) continue;
      final x = origin.dx + p.vx * age;
      final y = origin.dy + p.vy * age + 0.5 * 900 * age * age;
      // Hold full opacity, then fade out over the last 40% of life.
      final fadeStart = p.life * 0.6;
      final alpha = age < fadeStart
          ? 1.0
          : (1 - (age - fadeStart) / (p.life - fadeStart))
              .clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + p.spin * age);
      final paint = Paint()..color = p.color.withOpacity(alpha);
      if (p.circle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.62),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.particles != particles ||
      oldDelegate.origin != origin;
}
