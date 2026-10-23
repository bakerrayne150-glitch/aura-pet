import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pet.dart';
import '../services/assistant_service.dart';
import '../services/haptics.dart';
import '../services/pet_service.dart';
import '../services/sounds.dart';
import '../widgets/action_overlays.dart';
import '../widgets/pet_creature.dart';
import '../widgets/stat_bar.dart';

/// The pet tab: creature, mood line, stat bars, care actions.
/// Tapping the pet itself counts as petting it (with haptics).
class PetScreen extends StatefulWidget {
  const PetScreen({super.key});

  @override
  State<PetScreen> createState() => _PetScreenState();
}

enum _ActionKind { feed, play, other }

class _PetScreenState extends State<PetScreen> {
  static const double _petBoxSize = 220;

  final List<_Floater> _floaters = [];
  int _nextFloaterId = 0;

  /// Overlay micro-animations currently playing (snack arc, ball
  /// bounce, confetti). Each removes itself via its onDone callback.
  final List<_OverlayAnim> _overlays = [];
  int _nextOverlayId = 0;

  final GlobalKey _petBoxKey = GlobalKey();

  /// Tap position in the pet box's coordinates — the creature's eyes
  /// dart toward it briefly before the wiggle plays.
  final ValueNotifier<Offset?> _lookAt = ValueNotifier<Offset?>(null);

  /// AI reaction speech bubble text + auto-dismiss timer.
  String? _speechText;
  Timer? _speechTimer;

  int _lastMilestone = 0;

  /// Saved in initState so dispose() never does an ancestor lookup on a
  /// deactivated widget (which throws "looking up a deactivated widget's
  /// ancestor is unsafe").
  late final PetService _petService;
  late final AssistantService _assistantService;

  @override
  void initState() {
    super.initState();
    _petService = context.read<PetService>();
    _assistantService = context.read<AssistantService>();
    _lastMilestone = _petService.milestoneTick.value;
    _petService.milestoneTick.addListener(_onMilestone);
    _assistantService.reactionTick.addListener(_onReaction);
    _petService.evolutionTick.addListener(_onEvolution);
    // Catch an evolution that happened while the app was closed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _petService.consumeEvolution()) _onEvolution();
    });
  }

  @override
  void dispose() {
    _petService.milestoneTick.removeListener(_onMilestone);
    _assistantService.reactionTick.removeListener(_onReaction);
    _petService.evolutionTick.removeListener(_onEvolution);
    _speechTimer?.cancel();
    _lookAt.dispose();
    super.dispose();
  }

  /// Confetti + haptic fanfare (+ sound if enabled) when the pet hits a
  /// milestone. Silent while asleep, like the celebration wiggle.
  void _onMilestone() {
    final service = context.read<PetService>();
    final v = service.milestoneTick.value;
    if (v == _lastMilestone) return;
    _lastMilestone = v;
    if (service.pet?.sleeping ?? true) return;
    _spawnFloater('Milestone!', Icons.celebration);
    _spawnConfetti();
    PetHaptics.fanfare();
    context.read<PetSounds>().milestone();
  }

  /// Evolution party: the pet grew into a new life stage.
  void _onEvolution() {
    _petService.consumeEvolution(); // don't re-party on next rebuild
    final pet = _petService.pet;
    if (pet == null || !mounted) return;
    _speechTimer?.cancel();
    setState(() => _speechText =
        "I grew up! I'm ${pet.lifeStage.label.toLowerCase()} now!");
    _speechTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _speechText = null);
    });
    if (!pet.sleeping) {
      _spawnFloater('Evolved!', Icons.auto_awesome);
      _spawnConfetti();
      PetHaptics.fanfare();
      _petService.celebrateTick.value++;
      _petService.milestoneTick.value++;
    }
  }

  /// Show the AI's reaction to a care action in a speech bubble for a few
  /// seconds. Replaces any bubble currently showing.
  void _onReaction() {
    final text = context.read<AssistantService>().latestReaction.value;
    if (text == null || text.isEmpty || !mounted) return;
    _speechTimer?.cancel();
    setState(() => _speechText = text);
    _speechTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _speechText = null);
    });
  }

  String _moodLine(Pet pet) {
    final n = pet.name;
    if (pet.sleeping) return '$n is napping… shhh.';
    return switch (pet.mood) {
      PetMood.content => '$n is living their best life.',
      PetMood.hungry => '$n is STARVING. Feed them. Now. Please.',
      PetMood.bored => '$n is bored out of their tiny mind.',
      PetMood.tired => '$n can barely keep their eyes open…',
      PetMood.grumpy => '$n is grumpy. Approach with snacks.',
    };
  }

  void _spawnFloater(String label, IconData icon) {
    setState(() {
      _floaters.add(_Floater(_nextFloaterId++, label, icon));
    });
  }

  void _removeFloater(int id) {
    setState(() {
      _floaters.removeWhere((f) => f.id == id);
    });
  }

  void _spawnOverlay(Widget Function(VoidCallback onDone) build) {
    final id = _nextOverlayId++;
    setState(() {
      _overlays.add(_OverlayAnim(id, build));
    });
  }

  void _removeOverlay(int id) {
    setState(() {
      _overlays.removeWhere((o) => o.id == id);
    });
  }

  void _spawnSnack() => _spawnOverlay(
        (onDone) => SnackArc(size: _petBoxSize, onDone: onDone),
      );

  void _spawnBall() => _spawnOverlay(
        (onDone) => BallBounce(size: _petBoxSize, onDone: onDone),
      );

  void _spawnConfetti() => _spawnOverlay(
        (onDone) => ConfettiBurst(size: _petBoxSize, onDone: onDone),
      );

  /// Haptic tap + floating feedback, then the real action.
  /// While the pet sleeps, care actions are gentle: a "shhh…" floater
  /// with no haptic and no celebration wiggle (the service skips the
  /// wiggle too). The sleep toggle itself always behaves normally.
  void _doAction(
    Future<void> Function() action,
    String label,
    IconData icon, {
    bool respectSleep = true,
    _ActionKind kind = _ActionKind.other,
    String? reactionPrompt,
  }) {
    final sounds = context.read<PetSounds>();
    final sleeping =
        respectSleep && (context.read<PetService>().pet?.sleeping ?? false);
    if (sleeping) {
      _spawnFloater('shhh…', Icons.bedtime);
    } else {
      switch (kind) {
        case _ActionKind.feed:
          PetHaptics.feed();
          sounds.feed();
          _spawnSnack();
        case _ActionKind.play:
          PetHaptics.play();
          sounds.play();
          _spawnBall();
        case _ActionKind.other:
          PetHaptics.tap();
      }
      _spawnFloater(label, icon);
    }
    action();
    // Ask the backend for a playful in-character reaction. Silent while
    // asleep (no reactionPrompt) and never blocks the action itself.
    if (reactionPrompt != null && !sleeping) {
      final pet = context.read<PetService>().pet;
      if (pet != null) {
        unawaited(
          context
              .read<AssistantService>()
              .reactToCareAction(reactionPrompt, pet),
        );
      }
    }
  }

  /// Tapping the pet: the eyes dart toward the tap position first, then
  /// the happy wiggle lands a beat later.
  void _onPetTapDown(TapDownDetails details) {
    final service = context.read<PetService>();
    final box =
        _petBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _lookAt.value = box.globalToLocal(details.globalPosition);
      // Re-fire even when the tap lands on the same spot twice in a row.
      _lookAt.notifyListeners();
    }
    if (service.pet?.sleeping ?? false) {
      _spawnFloater('shhh…', Icons.bedtime);
    } else {
      PetHaptics.tap();
    }
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      service.stroke();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PetService>();
    final pet = service.pet;
    if (pet == null) {
      return const Center(child: Text('No pet yet'));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '${pet.name} • ${pet.lifeStage.label}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _moodLine(pet),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  key: _petBoxKey,
                  child: GestureDetector(
                    onTapDown: _onPetTapDown,
                    child: PetCreature(
                      mood: pet.mood,
                      sleeping: pet.sleeping,
                      stage: pet.lifeStage,
                      celebrate: service.celebrateTick,
                      lookAt: _lookAt,
                      size: _petBoxSize,
                    ),
                  ),
                ),
                for (final f in _floaters)
                  Positioned(
                    bottom: 36,
                    child: _FloaterBubble(
                      key: ValueKey(f.id),
                      floater: f,
                      onDone: () => _removeFloater(f.id),
                    ),
                  ),
                if (_speechText != null)
                  Positioned(
                    bottom: 196,
                    child: _SpeechBubble(text: _speechText!),
                  ),
                for (final o in _overlays)
                  o.build(() => _removeOverlay(o.id)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'tap to pet',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            StatBar(label: 'Fullness', value: pet.hunger, icon: Icons.restaurant),
            StatBar(
                label: 'Happy',
                value: pet.happiness,
                icon: Icons.sentiment_satisfied),
            StatBar(
                label: 'Energy',
                value: pet.energy,
                icon: Icons.battery_charging_full),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.restaurant,
                  label: 'Feed',
                  onTap: () => _doAction(
                    service.feed,
                    'Yum!',
                    Icons.restaurant,
                    kind: _ActionKind.feed,
                    reactionPrompt: 'fed you a tasty snack',
                  ),
                ),
                _ActionButton(
                  icon: Icons.sports_esports,
                  label: 'Play',
                  onTap: () => _doAction(
                    service.play,
                    'Wheee!',
                    Icons.sports_esports,
                    kind: _ActionKind.play,
                    reactionPrompt: 'played a fun game with you',
                  ),
                ),
                _ActionButton(
                  icon: pet.sleeping ? Icons.wb_sunny : Icons.bedtime,
                  label: pet.sleeping ? 'Wake' : 'Sleep',
                  onTap: () => _doAction(
                    service.toggleSleep,
                    pet.sleeping ? 'Rise & shine!' : 'Night night…',
                    pet.sleeping ? Icons.wb_sunny : Icons.bedtime,
                    respectSleep: false,
                    reactionPrompt: pet.sleeping
                        ? 'gently woke you up from your nap'
                        : 'tucked you in for a cozy nap',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Floater {
  final int id;
  final String label;
  final IconData icon;

  _Floater(this.id, this.label, this.icon);
}

/// An overlay micro-animation: an id plus a builder that receives the
/// onDone callback the overlay calls when its animation finishes.
class _OverlayAnim {
  final int id;
  final Widget Function(VoidCallback onDone) build;

  _OverlayAnim(this.id, this.build);
}

/// A little feedback pill that floats up and fades out, then reports done.
class _FloaterBubble extends StatefulWidget {
  final _Floater floater;
  final VoidCallback onDone;

  const _FloaterBubble({
    super.key,
    required this.floater,
    required this.onDone,
  });

  @override
  State<_FloaterBubble> createState() => _FloaterBubbleState();
}

class _FloaterBubbleState extends State<_FloaterBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Deterministic sideways drift so stacked floaters don't overlap.
    final drift = (widget.floater.id * 37 % 60) - 30.0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(drift * t, -76 * t),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.tealAccent.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.floater.icon,
                      size: 16, color: Colors.tealAccent),
                  const SizedBox(width: 6),
                  Text(
                    widget.floater.label,
                    style: const TextStyle(
                        color: Colors.tealAccent, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// A comic-style speech bubble showing the pet's AI reaction to a care
/// action. It appears when the reaction arrives and the screen dismisses
/// it after a few seconds.
class _SpeechBubble extends StatelessWidget {
  final String text;

  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
