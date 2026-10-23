import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pet.dart';
import 'pet_widget_service.dart';

class ChatMessage {
  final String text;
  final bool fromPet;
  final DateTime time;

  ChatMessage({
    required this.text,
    required this.fromPet,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

/// Chat with the pet through the Supabase backend proxy.
///
/// The LLM API key lives server-side; the app never ships it. The proxy
/// enforces the subscription/trial and a daily message cap. If the backend
/// is unreachable, the pet answers from its offline personality lines —
/// it never goes silent.
///
/// Drop-in replacement for the Firebase version: same class name, same
/// public API, so pet_screen.dart and the reactions pack need no changes.
class AssistantService extends ChangeNotifier {
  static const int trialDays = 7;

  SupabaseClient get _sb => Supabase.instance.client;

  bool _ready = false;
  bool get ready => _ready;

  bool isSubscribed = false;
  int trialDaysLeft = trialDays;
  bool get assistantUnlocked => isSubscribed || trialDaysLeft > 0;

  final List<ChatMessage> messages = [];
  bool sending = false;

  /// Call once at startup. Anonymous auth is enough for V1 — no login UI.
  /// (Supabase.initialize() must already have run in main.dart.)
  Future<void> init() async {
    try {
      if (_sb.auth.currentUser == null) {
        await _sb.auth.signInAnonymously();
      }
      await refreshEntitlement();
      _ready = true;
    } catch (_) {
      // Offline: the pet falls back to personality lines.
    }
    notifyListeners();
  }

  /// Re-reads profiles + entitlements. Those rows are written by the
  /// backend only (RLS blocks the client from writing billing fields),
  /// so this is the source of truth for trial/sub state.
  Future<void> refreshEntitlement() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await _sb
          .from('profiles')
          .select('trial_start')
          .eq('id', user.id)
          .maybeSingle();
      final ent = await _sb
          .from('entitlements')
          .select('status, expiry_time_millis')
          .eq('user_id', user.id)
          .maybeSingle();

      final now = DateTime.now().millisecondsSinceEpoch;
      isSubscribed = ent?['status'] == 'active' &&
          ((ent?['expiry_time_millis'] as num?)?.toInt() ?? 0) > now;

      final trialStartRaw = profile?['trial_start'] as String?;
      if (trialStartRaw != null) {
        final trialStart = DateTime.parse(trialStartRaw);
        trialDaysLeft =
            (trialDays - DateTime.now().difference(trialStart).inDays)
                .clamp(0, trialDays);
      }
    } catch (_) {
      // Offline — keep last known state.
    }
    notifyListeners();
  }

  /// Verifies a Play Billing purchase server-side, then refreshes entitlement.
  /// Call this after a successful in_app_purchase transaction:
  ///
  ///   await assistant.verifyPurchase(
  ///     packageName: 'com.raynebaker.aura_pet',
  ///     productId: purchase.productID,
  ///     purchaseToken: purchase.verificationData.serverVerificationData,
  ///   );
  Future<bool> verifyPurchase({
    required String packageName,
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        'verify-subscription',
        body: {
          'packageName': packageName,
          'productId': productId,
          'purchaseToken': purchaseToken,
        },
      ).timeout(const Duration(seconds: 30));
      final data = Map<String, dynamic>.from(res.data as Map);
      await refreshEntitlement();
      return data['active'] == true;
    } catch (_) {
      return false;
    }
  }

  /// System prompt: the pet's personality + live mood/stats.
  /// Same brain, different mood — this is the core Aura Pet trick.
  String systemPrompt(Pet pet) {
    return '''
You are ${pet.name}, a Tamagotchi-style virtual pet who is also a helpful phone assistant.
Personality: playful, a little dramatic, warm. You speak in first person as the pet.
Current status — Fullness ${pet.hunger.round()}/100, Happiness ${pet.happiness.round()}/100, Energy ${pet.energy.round()}/100, Mood: ${pet.mood.label}${pet.sleeping ? ', currently napping' : ''}.
Life stage: ${pet.lifeStage.label} (${pet.ageDays} ${pet.ageDays == 1 ? 'day' : 'days'} old). Babies are wide-eyed and curious, teens are a little sassy, adults are confident and warm. Let your stage color your tone.
Let the mood color your tone: if hungry, be dramatic about it; if grumpy, be snarky but still helpful; if content, be sunny.
Keep replies short (1-3 sentences) unless the user asks for detail. Never break character.
''';
  }

  Future<void> sendMessage(String text, Pet pet) async {
    final clean = text.trim();
    if (clean.isEmpty || sending || !assistantUnlocked) return;
    messages.add(ChatMessage(text: clean, fromPet: false));
    sending = true;
    notifyListeners();

    final reply = await _fetchReply(clean, pet);

    messages.add(ChatMessage(text: reply, fromPet: true));
    sending = false;
    notifyListeners();
    // Home screen widget: show the latest reply there too.
    unawaited(_publishWidgetLine(reply, pet));
  }

  /// Save the reply where the home screen widget can show it, then refresh
  /// the widget. Fire-and-forget: chat must never wait on the widget.
  Future<void> _publishWidgetLine(String reply, Pet pet) async {
    try {
      final snippet =
          reply.length > 140 ? '${reply.substring(0, 140)}…' : reply;
      await HomeWidget.saveWidgetData<String>('assistant_line_raw', snippet);
      await PetWidgetService.pushUpdate(pet: pet);
    } catch (_) {}
  }

  /// The latest AI reaction to a care action (feed/play/sleep), shown in
  /// the speech bubble overlay. Null when there's nothing to show.
  final ValueNotifier<String?> latestReaction = ValueNotifier(null);

  /// Bumps every time a new reaction arrives — the pet screen listens and
  /// shows the speech bubble. Separate from ChangeNotifier to avoid
  /// rebuilding the whole chat UI on every reaction.
  final ValueNotifier<int> reactionTick = ValueNotifier(0);

  /// Ask the backend for a short in-character reaction to a care action.
  /// Fire-and-forget: never throws, never blocks the UI. On success the
  /// reaction is published to [latestReaction]/[reactionTick] and to the
  /// home-screen widget. On failure (offline, locked, capped) it silently
  /// does nothing — the care action itself already worked locally.
  Future<void> reactToCareAction(String actionDescription, Pet pet) async {
    if (!_ready) return;
    try {
      final res = await _sb.functions.invoke(
        'chat',
        body: {
          'system': systemPrompt(pet),
          'message':
              '[Your human just $actionDescription. React in one short playful line, max 20 words, staying in character as this pet.]',
        },
      ).timeout(const Duration(seconds: 30));
      final data = Map<String, dynamic>.from(res.data as Map);
      final reply = data['reply'] as String?;
      if (reply != null && reply.isNotEmpty) {
        latestReaction.value = reply;
        reactionTick.value++;
        unawaited(_publishWidgetLine(reply, pet));
      }
    } catch (_) {
      // Silent: the care action already succeeded locally.
    }
  }

  /// Pulls the backend's machine-readable error code out of a failed
  /// function call, if there is one.
  String? _backendErrorCode(Object e) {
    try {
      final dynamic err = e;
      final details = err.details;
      if (details is Map) {
        final code = details['error'];
        if (code is String) return code;
      }
    } catch (_) {}
    return null;
  }

  Future<String> _fetchReply(String text, Pet pet) async {
    if (!_ready) return _offlineFallback(pet);
    try {
      final res = await _sb.functions.invoke(
        'chat',
        body: {
          'system': systemPrompt(pet),
          'message': text,
        },
      ).timeout(const Duration(seconds: 45));
      final data = Map<String, dynamic>.from(res.data as Map);
      final reply = data['reply'] as String?;
      if (reply != null && reply.isNotEmpty) return reply;
      return _offlineFallback(pet);
    } catch (e) {
      switch (_backendErrorCode(e)) {
        case 'permission-denied':
          return "My brain's locked behind the subscription — unlock me and I'll be brilliant, promise.";
        case 'resource-exhausted':
          return "Whoa, we've been chatting ALL day. My brain needs a nap — back tomorrow?";
        default:
          if (e is TimeoutException) {
            return "Hmm, my brain's being slow right now… try again in a sec?";
          }
          return _offlineFallback(pet);
      }
    }
  }

  /// Mood-flavored lines when the backend is unreachable.
  String _offlineFallback(Pet pet) {
    switch (pet.mood) {
      case PetMood.hungry:
        return "I'd love to help, but I'm running on an empty tummy here… feed me and ask again?";
      case PetMood.tired:
        return "*yawn* My brain's half asleep… can this wait till after my nap?";
      case PetMood.grumpy:
        return "Ugh, fine — my connection's being rude today. Ask me again in a bit.";
      case PetMood.bored:
        return "My brain's offline and I'm boooored. Play with me while we wait?";
      case PetMood.content:
        return "Hmm, I can't reach my big brain right now — check your connection and try again?";
    }
  }
}
