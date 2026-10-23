import 'package:flutter/services.dart';

/// Every buzz in the app lives here, so each action feels different
/// instead of the same buzz for everything:
///
/// - UI taps (buttons, toggles, petting) → selection click
/// - Feed → light impact
/// - Play → medium impact
/// - Milestones → a little heavy fanfare (heavy, medium, heavy)
abstract final class PetHaptics {
  /// Buttons, toggles, tapping the pet.
  static Future<void> tap() => HapticFeedback.selectionClick();

  /// Feeding — gentle.
  static Future<void> feed() => HapticFeedback.lightImpact();

  /// Playing — a bit more oomph.
  static Future<void> play() => HapticFeedback.mediumImpact();

  /// Milestones — celebratory heavy sequence.
  static Future<void> fanfare() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.heavyImpact();
  }
}
