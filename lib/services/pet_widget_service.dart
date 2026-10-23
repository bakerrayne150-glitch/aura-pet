import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../models/pet.dart';

/// Bridge between the pet and the Android home screen widget.
///
/// The widget itself is native (RemoteViews) — see
/// android/app/src/main/kotlin/com/raynebaker/aura_pet/AuraPetWidgetProvider.kt.
/// This service pushes the pet's state into the widget's storage and
/// handles taps on the widget's Feed / Play / Nap buttons, which run here
/// in a background Dart isolate even when the app is closed.
///
/// Widget storage keys (all in home_widget's prefs, readable natively):
///   has_pet, pet_json, pet_name, mood_label, mood_emoji,
///   hunger, happiness, energy, sleeping, last_updated_ms,
///   assistant_line_raw (last assistant reply, written by AssistantService),
///   assistant_line (resolved line the widget actually shows).
class PetWidgetService {
  static const String providerClass =
      'com.raynebaker.aura_pet.AuraPetWidgetProvider';

  /// Push the pet's current state to the home screen widget.
  /// Pass null when there is no pet yet (empty widget state).
  /// Safe to call from the main isolate and the background isolate.
  static Future<void> pushUpdate({Pet? pet}) async {
    try {
      if (pet == null) {
        await HomeWidget.saveWidgetData<bool>('has_pet', false);
        await HomeWidget.saveWidgetData<String>('pet_json', null);
        await _update();
        return;
      }
      pet.applyDecay(DateTime.now());
      await HomeWidget.saveWidgetData<bool>('has_pet', true);
      await HomeWidget.saveWidgetData<String>(
          'pet_json', jsonEncode(pet.toJson()));
      await HomeWidget.saveWidgetData<String>('pet_name', pet.name);
      await HomeWidget.saveWidgetData<String>('mood_label', moodLabel(pet));
      await HomeWidget.saveWidgetData<String>('mood_emoji', moodEmoji(pet));
      await HomeWidget.saveWidgetData<int>('hunger', pet.hunger.round());
      await HomeWidget.saveWidgetData<int>(
          'happiness', pet.happiness.round());
      await HomeWidget.saveWidgetData<int>('energy', pet.energy.round());
      await HomeWidget.saveWidgetData<bool>('sleeping', pet.sleeping);
      await HomeWidget.saveWidgetData<int>(
          'last_updated_ms', DateTime.now().millisecondsSinceEpoch);
      final rawLine =
          await HomeWidget.getWidgetData<String>('assistant_line_raw');
      await HomeWidget.saveWidgetData<String>(
        'assistant_line',
        (rawLine == null || rawLine.isEmpty) ? greetingFor(pet) : rawLine,
      );
      await _update();
    } catch (_) {
      // Widget not installed / platform without home_widget — not fatal.
    }
  }

  /// Read the widget-side pet JSON. Returns null when absent or unreadable.
  /// PetService uses this to adopt widget actions that happened while the
  /// app was closed (the widget copy has the newer lastUpdated).
  static Future<String?> readPetJson() async {
    try {
      return await HomeWidget.getWidgetData<String>('pet_json');
    } catch (_) {
      return null;
    }
  }

  /// Handle a widget button tap in the background isolate.
  /// Only feed/play/sleep arrive here — the Chat button opens the app
  /// instead and is routed through HomeWidget.widgetClicked.
  static Future<void> handleAction(Uri? uri) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (uri == null) return;
      final action = uri.host;
      if (action != 'feed' && action != 'play' && action != 'sleep') return;
      final raw = await readPetJson();
      if (raw == null || raw.isEmpty) return;
      final pet = Pet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      pet.applyDecay(DateTime.now());
      switch (action) {
        case 'feed':
          pet.feed();
        case 'play':
          pet.play();
        case 'sleep':
          pet.toggleSleep();
      }
      await pushUpdate(pet: pet);
    } catch (_) {
      // Never crash the background isolate on a widget tap.
    }
  }

  static Future<void> _update() async {
    try {
      await HomeWidget.updateWidget(qualifiedAndroidName: providerClass);
    } catch (_) {}
  }

  /// Emoji for the pet's current state. Must match the mapping in
  /// AuraPetWidgetProvider.kt (the native side recomputes this after
  /// applying wall-clock decay while the app is closed).
  static String moodEmoji(Pet pet) {
    if (pet.sleeping) return '💤';
    return switch (pet.mood) {
      PetMood.content => '😻',
      PetMood.hungry => '😿',
      PetMood.bored => '😑',
      PetMood.tired => '😴',
      PetMood.grumpy => '😾',
    };
  }

  static String moodLabel(Pet pet) =>
      pet.sleeping ? 'Napping' : pet.mood.label;

  /// Fallback widget line when the assistant hasn't said anything yet.
  static String greetingFor(Pet pet) {
    if (pet.sleeping) return 'Shhh… ${pet.name} is napping.';
    return switch (pet.mood) {
      PetMood.hungry => 'Psst… ${pet.name} is getting hungry.',
      PetMood.bored => '${pet.name} is bored — come play?',
      PetMood.tired => '${pet.name} is sleepy…',
      PetMood.grumpy => '${pet.name} is grumpy. Tread carefully.',
      PetMood.content => '${pet.name} is feeling great!',
    };
  }
}

/// Background entry point for widget button taps. Registered once in main()
/// via HomeWidget.registerInteractivityCallback. Must stay top-level and
/// keep the pragma or the background isolate can't find it.
@pragma('vm:entry-point')
Future<void> widgetActionCallback(Uri? uri) =>
    PetWidgetService.handleAction(uri);
