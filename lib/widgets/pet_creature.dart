import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/pet.dart';

/// The pet itself — a little blob whose face reflects its mood,
/// now with idle life: breathing, blinking, celebration wiggles,
/// and floating Z's while asleep.
///
/// Pure CustomPainter + transforms, so V1 still needs zero image assets.
class PetCreature extends StatefulWidget {
  final PetMood mood;
  final bool sleeping;
  final double size;

  /// Growth stage — babies are smaller with bigger eyes, adults get
  /// blush cheeks and a deeper coat.
  final LifeStage stage;

  /// Fires (value increments) when the pet should do a happy wiggle —
  /// wire to [PetService.celebrateTick].
  final ValueListenable<int>? celebrate;

  /// Fires with the tap position (in the creature's own coordinate box)
  /// when the user taps the pet — the eyes dart toward it briefly
  /// before the celebration wiggle plays.
  final ValueListenable<Offset?>? lookAt;

  const PetCreature({
    super.key,
    required this.mood,
    required this.sleeping,
    this.size = 200,
    this.stage = LifeStage.adult,
    this.celebrate,
    this.lookAt,
  });

  @override
  State<PetCreature> createState() => _PetCreatureState();
}

class _PetCreatureState extends State<PetCreature>
    with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _blink;
  late final AnimationController _celebrate;
  Timer? _blinkTimer;
  final _random = math.Random();
  int _lastCelebrate = 0;

  /// Where the eyes are currently looking (creature coordinates),
  /// or null for straight ahead.
  Offset? _lookTarget;
  Timer? _lookTimer;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: widget.sleeping
          ? const Duration(milliseconds: 4200)
          : const Duration(milliseconds: 2600),
    )..repeat();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _celebrate = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _lastCelebrate = widget.celebrate?.value ?? 0;
    widget.celebrate?.addListener(_onCelebrate);
    widget.lookAt?.addListener(_onLook);
    _scheduleBlink();
  }

  @override
  void didUpdateWidget(covariant PetCreature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sleeping != widget.sleeping) {
      _breathe.duration = widget.sleeping
          ? const Duration(milliseconds: 4200)
          : const Duration(milliseconds: 2600);
      _breathe.repeat();
    }
    if (oldWidget.celebrate != widget.celebrate) {
      oldWidget.celebrate?.removeListener(_onCelebrate);
      _lastCelebrate = widget.celebrate?.value ?? 0;
      widget.celebrate?.addListener(_onCelebrate);
    }
    if (oldWidget.lookAt != widget.lookAt) {
      oldWidget.lookAt?.removeListener(_onLook);
      widget.lookAt?.addListener(_onLook);
    }
  }

  void _onCelebrate() {
    final v = widget.celebrate?.value ?? 0;
    if (v != _lastCelebrate) {
      _lastCelebrate = v;
      _celebrate.forward(from: 0);
    }
  }

  /// A new tap position: point the pupils at it, then relax back to
  /// center after a beat (the wiggle itself is triggered separately).
  void _onLook() {
    final target = widget.lookAt?.value;
    _lookTimer?.cancel();
    setState(() => _lookTarget = target);
    if (target != null) {
      _lookTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() => _lookTarget = null);
      });
    }
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(
      Duration(milliseconds: 2200 + _random.nextInt(3200)),
      () async {
        if (!mounted) return;
        await _blink.forward();
        if (!mounted) return;
        await _blink.reverse();
        if (mounted) _scheduleBlink();
      },
    );
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _lookTimer?.cancel();
    widget.celebrate?.removeListener(_onCelebrate);
    widget.lookAt?.removeListener(_onLook);
    _breathe.dispose();
    _blink.dispose();
    _celebrate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _blink, _celebrate]),
      builder: (context, _) {
        final t = _breathe.value * math.pi * 2;
        final breatheAmp = widget.sleeping ? 0.045 : 0.028;
        final bob = math.sin(t) * (widget.sleeping ? 2.0 : 5.0);

        // Celebration: squash-and-stretch + wobble, decaying over ~750ms.
        final c = _celebrate.value;
        final decay = 1 - c;
        final wiggle = math.sin(c * math.pi * 4) * decay;
        final squash = wiggle * 0.10;
        final rot = math.sin(c * math.pi * 3) * decay * 0.10;

        final wave = math.sin(t);
        final scaleX =
            (1 + breatheAmp * 0.6 * wave) * (1 + squash * 0.8);
        final scaleY = (1 + breatheAmp * wave) * (1 - squash);

        return Transform.translate(
          offset: Offset(0, -bob),
          child: Transform.rotate(
            angle: rot,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _PetPainter(
                    mood: widget.mood,
                    sleeping: widget.sleeping,
                    stage: widget.stage,
                    blink: _blink.value,
                    zPhase: widget.sleeping ? _breathe.value : 0,
                    look: _lookTarget,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PetPainter extends CustomPainter {
  final PetMood mood;
  final bool sleeping;
  final LifeStage stage;

  /// 0 = eyes open, 1 = fully blinked shut.
  final double blink;

  /// 0..1 loop driving the floating Z's while asleep.
  final double zPhase;

  /// Tap position in the painter's coordinate box, or null for
  /// straight ahead — the pupils lean toward it briefly.
  final Offset? look;

  _PetPainter({
    required this.mood,
    required this.sleeping,
    required this.stage,
    this.blink = 0,
    this.zPhase = 0,
    this.look,
  });

  /// Pupil offset toward the tap position, clamped so the pupils stay
  /// inside the whites.
  Offset _gaze(Offset eyeCenter, double maxShift) {
    final l = look;
    if (l == null) return Offset.zero;
    final d = l - eyeCenter;
    final dist = d.distance;
    if (dist < 0.5) return Offset.zero;
    return d / dist * math.min(dist * 0.3, maxShift);
  }

  void _drawZ(Canvas canvas, double x, double y, double size,
      double opacity) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'z',
        style: TextStyle(
          color: Colors.white
              .withOpacity(opacity.clamp(0.0, 1.0) * 0.75),
          fontSize: size,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Growth: babies are smaller with bigger eyes and a lighter coat;
    // adults are full-size with blush cheeks and a deeper coat.
    final growth = switch (stage) {
      LifeStage.baby => 0.82,
      LifeStage.teen => 0.92,
      LifeStage.adult => 1.0,
    };
    final eyeScale = switch (stage) {
      LifeStage.baby => 1.30,
      LifeStage.teen => 1.12,
      LifeStage.adult => 1.0,
    };
    final bodyColor = switch (stage) {
      LifeStage.baby => const Color(0xFF7FE8DC),
      LifeStage.teen => const Color(0xFF4DD0C4),
      LifeStage.adult => const Color(0xFF2EB8AC),
    };
    final r = size.width * 0.36 * growth;

    // Body.
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = bodyColor,
    );
    // Shine.
    canvas.drawCircle(
      Offset(cx - r * 0.32, cy - r * 0.38),
      r * 0.42,
      Paint()..color = Colors.white.withOpacity(0.16),
    );

    // Floating Z's while asleep.
    if (sleeping) {
      _drawZ(canvas, cx + r * 0.95, cy - r * 1.05 - zPhase * r * 0.55,
          r * 0.30, 1 - zPhase);
      final p2 = (zPhase + 0.5) % 1.0;
      _drawZ(canvas, cx + r * 0.55, cy - r * 0.72 - p2 * r * 0.55,
          r * 0.22, 1 - p2);
    }

    final white = Paint()..color = Colors.white;
    final dark = Paint()..color = const Color(0xFF102220);
    final line = Paint()
      ..color = const Color(0xFF102220)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round;
    final lidLine = Paint()
      ..color = const Color(0xFF102220)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.10
      ..strokeCap = StrokeCap.round;

    const pi = 3.14159;
    final eyeY = cy - r * 0.12;
    final dx = r * 0.38;
    final eyeR =
        (mood == PetMood.hungry ? r * 0.27 : r * 0.21) * eyeScale;
    final eyesClosed = sleeping || mood == PetMood.tired;
    final open = eyesClosed ? 0.0 : (1 - blink).clamp(0.0, 1.0);
    final squashH = math.max(open, 0.08);

    if (eyesClosed) {
      for (final sgn in [-1.0, 1.0]) {
        canvas.drawArc(
          Rect.fromCircle(
              center: Offset(cx + sgn * dx, eyeY), radius: eyeR * 0.8),
          0.15 * pi,
          0.7 * pi,
          false,
          line,
        );
      }
    } else {
      for (final sgn in [-1.0, 1.0]) {
        final c = Offset(cx + sgn * dx, eyeY);
        final pupilR =
            mood == PetMood.hungry ? eyeR * 0.35 : eyeR * 0.5;
        canvas.drawOval(
          Rect.fromCenter(
              center: c, width: eyeR * 2, height: eyeR * 2 * squashH),
          white,
        );
        if (open > 0.35) {
          canvas.drawOval(
            Rect.fromCenter(
              center: c +
                  Offset(0, eyeR * 0.12 * squashH) +
                  _gaze(c, eyeR * 0.45),
              width: pupilR * 2,
              height: pupilR * 2 * squashH,
            ),
            dark,
          );
        }
      }
      if (mood == PetMood.grumpy) {
        // Angled brows.
        for (final sgn in [-1.0, 1.0]) {
          canvas.drawLine(
            Offset(cx + sgn * dx * 0.45, eyeY - eyeR * 1.55),
            Offset(cx + sgn * dx * 1.30, eyeY - eyeR * 1.95),
            line,
          );
        }
      }
      if (mood == PetMood.bored) {
        // Half-mast lids.
        for (final sgn in [-1.0, 1.0]) {
          canvas.drawLine(
            Offset(cx + sgn * dx - eyeR, eyeY - eyeR * 0.4),
            Offset(cx + sgn * dx + eyeR, eyeY - eyeR * 0.4),
            lidLine,
          );
        }
      }
    }

    // Adults get blush cheeks.
    if (stage == LifeStage.adult && !eyesClosed) {
      final blush = Paint()..color = Colors.pink.withOpacity(0.35);
      for (final sgn in [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + sgn * r * 0.58, eyeY + r * 0.52),
            width: r * 0.30,
            height: r * 0.20,
          ),
          blush,
        );
      }
    }

    // Mouth.
    final mouthY = cy + r * 0.35;
    if (mood == PetMood.hungry) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, mouthY), width: r * 0.34, height: r * 0.44),
        dark,
      );
    } else if (mood == PetMood.grumpy) {
      canvas.drawArc(
        Rect.fromCircle(
            center: Offset(cx, mouthY + r * 0.28), radius: r * 0.3),
        1.15 * pi,
        0.7 * pi,
        false,
        line,
      );
    } else if (mood == PetMood.bored || eyesClosed) {
      canvas.drawLine(
        Offset(cx - r * 0.2, mouthY),
        Offset(cx + r * 0.2, mouthY),
        line,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(
            center: Offset(cx, mouthY - r * 0.14), radius: r * 0.32),
        0.15 * pi,
        0.7 * pi,
        false,
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PetPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.sleeping != sleeping ||
      oldDelegate.stage != stage ||
      oldDelegate.blink != blink ||
      oldDelegate.zPhase != zPhase ||
      oldDelegate.look != look;
}
