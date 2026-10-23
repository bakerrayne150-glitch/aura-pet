import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet.dart';

/// Local pet-status nudges ("I'm starving… dramatic, I know").
///
/// V1 checks on app open/resume via [PetService]. Periodic background
/// checks are a V1.1 hardening (WorkManager / exact alarms).
class PetNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// Set once we've shown the rationale dialog, so we only pitch once.
  static const _askedKey = 'aura_notif_asked_v1';

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);

    const channel = AndroidNotificationChannel(
      'aura_pet',
      'Aura Pet',
      description: 'Pet status nudges',
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _ready = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Pet-voiced rationale dialog, then the Android 13+ system prompt.
  ///
  /// Call once on first launch (and from the Settings tile when the user
  /// wants to change their mind). Returns true if nudges are enabled
  /// afterwards.
  static Future<bool> ensurePermission(BuildContext context) async {
    final android = _android;
    if (android == null) return false;
    if (await android.areNotificationsEnabled() ?? false) return true;

    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool(_askedKey) ?? false;

    bool? allow = true;
    if (!alreadyAsked) {
      if (!context.mounted) return false;
      allow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pssst… can I nudge you?'),
          content: const Text(
            "When I'm starving or bored out of my tiny mind, I'd love to "
            'ping your phone so you can come rescue me. Deal?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Nah, I'm good"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sure, nudge away'),
            ),
          ],
        ),
      );
      await prefs.setBool(_askedKey, true);
    }

    if (allow == true) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// Show at most one nudge for the neediest stat.
  static Future<void> checkAndNotify(Pet pet) async {
    if (!_ready) return;

    String? body;
    if (pet.hunger < 20) {
      body = '${pet.name} is starving… dramatic, I know. Come feed me!';
    } else if (pet.happiness < 20) {
      body = '${pet.name} is bored out of their little mind. Play with me?';
    } else if (pet.energy < 15 && !pet.sleeping) {
      body = '${pet.name} can barely keep their eyes open. Nap time?';
    }
    if (body == null) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails('aura_pet', 'Aura Pet'),
    );
    // Fixed id so a new nudge replaces the previous one.
    await _plugin.show(id: 7, title: 'Aura Pet', body: body, notificationDetails: details);
  }
}
