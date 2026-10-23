import 'package:flutter/material.dart';

/// Labeled stat bar (Fullness / Happy / Energy). Red < 25, orange < 35.
/// Thresholds match the mood bands in [Pet.mood] so the bar color and
/// the pet's face always agree.
/// Value changes animate smoothly instead of jumping.
class StatBar extends StatelessWidget {
  final String label;
  final double value; // 0–100
  final IconData icon;

  const StatBar({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  Color _color(double v) {
    if (v < 25) return Colors.redAccent;
    if (v < 35) return Colors.orangeAccent;
    return Colors.tealAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child:
                Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0, end: value),
                builder: (context, animated, _) {
                  return LinearProgressIndicator(
                    value: animated / 100,
                    minHeight: 10,
                    backgroundColor: Colors.white10,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_color(animated)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: value),
              builder: (context, animated, _) => Text(
                '${animated.round()}',
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
