import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny sound effects for feed / play / milestone — OFF by default.
///
/// Zero new packages, zero audio assets, zero native changes: it just
/// plays the platform's built-in system sounds. If real synthesized
/// tones are ever wanted, the swap is this one file (e.g. audioplayers
/// + generated WAV bytes).
class PetSounds extends ChangeNotifier {
  static const _key = 'aura_pet_sounds_enabled';

  bool _enabled = false;

  /// False until the user flips the toggle in Settings.
  bool get enabled => _enabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    notifyListeners();
  }

  Future<void> _blip(SystemSoundType type) async {
    if (!_enabled) return;
    try {
      await SystemSound.play(type);
    } catch (_) {
      // Some devices have no system sounds — stay silent instead of
      // crashing the action.
    }
  }

  /// Single soft blip.
  Future<void> feed() => _blip(SystemSoundType.click);

  /// Bouncy double blip.
  Future<void> play() async {
    await _blip(SystemSoundType.click);
    await Future.delayed(const Duration(milliseconds: 90));
    await _blip(SystemSoundType.click);
  }

  /// Little fanfare: two blips plus the alert tone.
  Future<void> milestone() async {
    await _blip(SystemSoundType.click);
    await Future.delayed(const Duration(milliseconds: 90));
    await _blip(SystemSoundType.click);
    await Future.delayed(const Duration(milliseconds: 90));
    await _blip(SystemSoundType.alert);
  }
}
