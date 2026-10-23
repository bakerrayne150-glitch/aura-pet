import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet.dart';
import 'notification_service.dart';
import 'pet_widget_service.dart';

/// Owns the pet: load/save, stat decay, and care actions.
/// Every action re-applies wall-clock decay first so stats are
/// always current, then persists.
///
/// Home screen widget: every mutation is pushed to the widget via
/// PetWidgetService, and load()/actions adopt a newer widget-side copy
/// (widget Feed/Play/Nap taps run in a background isolate while the app
/// is closed, so the widget copy can be fresher than the app's).
class PetService extends ChangeNotifier {
  static const _key = 'aura_pet_v1';

  Pet? _pet;
  bool _loaded = false;

  Pet? get pet => _pet;
  bool get loaded => _loaded;
  bool get hasPet => _pet != null;

  /// Bumps every time the user feeds, plays with, or pets — the UI
  /// listens and plays a happy wiggle. Separate from ChangeNotifier
  /// so the creature can react without a full rebuild.
  final ValueNotifier<int> celebrateTick = ValueNotifier<int>(0);

  /// Bumps when the pet hits a milestone: any stat newly reaching 100,
  /// or the mood lifting back to content. The UI listens and fires
  /// confetti + a haptic fanfare.
  final ValueNotifier<int> milestoneTick = ValueNotifier<int>(0);

  /// Bumps when the pet grows into a new life stage. The UI listens and
  /// throws an evolution party: confetti, fanfare, speech bubble.
  final ValueNotifier<int> evolutionTick = ValueNotifier<int>(0);

  /// True until the UI acknowledges an evolution — so a pet that grew
  /// while the app was closed still gets its party on return.
  bool _evolutionUnseen = false;

  /// True once per evolution, then resets. The UI calls this on start
  /// to catch evolutions that happened while it was away.
  bool consumeEvolution() {
    if (!_evolutionUnseen) return false;
    _evolutionUnseen = false;
    return true;
  }

  /// After decay or a care action: if the pet outgrew its last announced
  /// stage, announce the new one.
  void _checkEvolution() {
    final p = _pet;
    if (p == null) return;
    if (p.lifeStage != p.lastStage) {
      p.lastStage = p.lifeStage;
      _evolutionUnseen = true;
      evolutionTick.value++;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _pet = await _pickNewest(raw, await PetWidgetService.readPetJson());
    if (_pet != null) {
      _pet!.applyDecay(DateTime.now());
      _checkEvolution();
    }
    _loaded = true;
    notifyListeners();
    if (_pet != null) {
      await save();
      await PetNotifications.checkAndNotify(_pet!);
    }
    // Keep the home screen widget in sync on every launch.
    await PetWidgetService.pushUpdate(pet: _pet);
  }

  /// Parse both pet JSON copies (app prefs + widget prefs) and return the
  /// one with the newer lastUpdated. Null when neither parses.
  Future<Pet?> _pickNewest(String? appRaw, String? widgetRaw) async {
    Pet? appPet;
    Pet? widgetPet;
    try {
      if (appRaw != null) {
        appPet = Pet.fromJson(jsonDecode(appRaw) as Map<String, dynamic>);
      }
    } catch (_) {}
    try {
      if (widgetRaw != null) {
        widgetPet =
            Pet.fromJson(jsonDecode(widgetRaw) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (appPet == null) return widgetPet;
    if (widgetPet == null) return appPet;
    return widgetPet.lastUpdated.isAfter(appPet.lastUpdated)
        ? widgetPet
        : appPet;
  }

  /// Adopt the widget-side pet when it is newer (a widget button tap ran
  /// while the app was alive but its in-memory pet is stale).
  Future<void> _syncFromWidget() async {
    final widgetRaw = await PetWidgetService.readPetJson();
    if (widgetRaw == null || widgetRaw.isEmpty) return;
    try {
      final widgetPet =
          Pet.fromJson(jsonDecode(widgetRaw) as Map<String, dynamic>);
      final cur = _pet;
      if (cur == null || widgetPet.lastUpdated.isAfter(cur.lastUpdated)) {
        _pet = widgetPet;
      }
    } catch (_) {}
  }

  Future<void> createPet(String name) async {
    _pet = Pet.fresh(name);
    await save();
    notifyListeners();
    await PetWidgetService.pushUpdate(pet: _pet);
  }

  Future<void> save() async {
    if (_pet == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_pet!.toJson()));
  }

  Future<void> _act(void Function(Pet) fn) async {
    await _syncFromWidget();
    final p = _pet;
    if (p == null) return;
    p.applyDecay(DateTime.now());
    final hungerBefore = p.hunger;
    final happinessBefore = p.happiness;
    final energyBefore = p.energy;
    final moodBefore = p.mood;
    fn(p);
    _checkEvolution();
    // Milestones: a stat newly maxed, or the mood lifting to content.
    final hitMax = (hungerBefore < 100 && p.hunger >= 100) ||
        (happinessBefore < 100 && p.happiness >= 100) ||
        (energyBefore < 100 && p.energy >= 100);
    final moodLift =
        moodBefore != PetMood.content && p.mood == PetMood.content;
    if (hitMax || moodLift) milestoneTick.value++;
    await save();
    notifyListeners();
    await PetWidgetService.pushUpdate(pet: p);
    await PetNotifications.checkAndNotify(p);
  }

  Future<void> feed() async {
    await _act((p) => p.feed());
    _celebrateIfAwake();
  }

  Future<void> play() async {
    await _act((p) => p.play());
    _celebrateIfAwake();
  }

  Future<void> stroke() async {
    await _act((p) => p.pet());
    _celebrateIfAwake();
  }

  /// The happy wiggle only fires while the pet is awake — care actions
  /// while asleep are applied silently (the UI shows a "shhh…" instead).
  void _celebrateIfAwake() {
    if (_pet != null && !_pet!.sleeping) celebrateTick.value++;
  }

  Future<void> toggleSleep() => _act((p) => p.toggleSleep());

  Future<void> rename(String name) async {
    if (_pet == null || name.trim().isEmpty) return;
    _pet!.name = name.trim();
    await save();
    notifyListeners();
    await PetWidgetService.pushUpdate(pet: _pet);
  }

  Future<void> reset() async {
    _pet = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
    await PetWidgetService.pushUpdate(pet: null);
  }
}
