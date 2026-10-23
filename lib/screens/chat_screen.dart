import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pet.dart';
import '../services/assistant_service.dart';
import '../services/billing_service.dart';
import '../services/pet_service.dart';
import '../widgets/pet_creature.dart';

/// The assistant tab: chat with the pet, gated behind the
/// subscription/trial paywall when locked.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// Last message count seen in build — when it grows, the pet's reply
  /// just landed and we ease to the bottom.
  int _seenMessages = 0;

  static const _suggestions = [
    'Set a reminder',
    'Morning briefing',
    'Summarize my notifications',
    'Tell me a joke',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sendPreset(String text) {
    _controller.text = text;
    _send();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final pet = context.read<PetService>().pet;
    if (pet == null) return;
    _controller.clear();
    context.read<AssistantService>().sendMessage(text, pet);
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final assistant = context.watch<AssistantService>();
    if (!assistant.assistantUnlocked) {
      return const _Paywall();
    }

    // Whenever the message count grows — user message or pet reply —
    // ease to the bottom so long replies never sit below the fold.
    if (assistant.messages.length != _seenMessages) {
      _seenMessages = assistant.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    final pet = context.watch<PetService>().pet;
    final mood = pet?.mood ?? PetMood.content;
    final showTrialBanner =
        !assistant.isSubscribed && assistant.trialDaysLeft <= 3;

    return SafeArea(
      child: Column(
        children: [
          if (showTrialBanner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.tealAccent.withOpacity(0.10),
              child: Text(
                '${assistant.trialDaysLeft} ${assistant.trialDaysLeft == 1 ? 'day' : 'days'} of free brain left ✦',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.tealAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: assistant.messages.isEmpty
                ? _EmptyChat(mood: mood)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: assistant.messages.length,
                    itemBuilder: (ctx, i) {
                      final m = assistant.messages[i];
                      if (m.fromPet) {
                        return Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                  right: 8, bottom: 4),
                              child: PetCreature(
                                mood: mood,
                                sleeping: false,
                                size: 36,
                              ),
                            ),
                            Flexible(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.teal[900],
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                                child: Text(m.text),
                              ),
                            ),
                            const SizedBox(width: 44),
                          ],
                        );
                      }
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(ctx).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(m.text),
                        ),
                      );
                    },
                  ),
          ),
          if (assistant.sending)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 4, 4),
                child: _TypingDots(),
              ),
            ),
          _SuggestionRow(onSuggestion: _sendPreset),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask your pet anything…',
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Suggestion chips, pinned above the input at all times so the pet's
/// capabilities stay discoverable after the first message.
class _SuggestionRow extends StatelessWidget {
  final void Function(String) onSuggestion;

  const _SuggestionRow({required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        children: [
          for (final s in _ChatScreenState._suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(s),
                onPressed: () => onSuggestion(s),
              ),
            ),
        ],
      ),
    );
  }
}

/// Empty state: mini pet and greeting. (Suggestion chips live in the
/// pinned row above the input now.)
class _EmptyChat extends StatelessWidget {
  final PetMood mood;

  const _EmptyChat({required this.mood});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PetCreature(mood: mood, sleeping: false, size: 96),
            const SizedBox(height: 12),
            const Text(
              'Say hi to your pet ✦',
              style: TextStyle(
                  color: Colors.white38, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three bouncing dots while the assistant "thinks".
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 2.5),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.tealAccent.withOpacity(
                    0.25 +
                        0.75 *
                            (0.5 +
                                0.5 *
                                    math.sin(2 *
                                        math.pi *
                                        (_controller.value -
                                            i / 3))),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Paywall extends StatelessWidget {
  const _Paywall();

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingService>();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧠', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text(
              "Pssst… my big brain costs snacks to run.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Unlock the assistant to chat, set reminders, and get morning briefings. The pet sim stays free forever.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            if (billing.loadingProducts)
              const CircularProgressIndicator()
            else if (!billing.storeAvailable)
              const Text(
                'Subscriptions are not available on this device or store.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              )
            else ...[
              for (final product in billing.products)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton(
                    onPressed: billing.purchasing
                        ? null
                        : () => billing.buy(product),
                    child: Text('${product.title} — ${product.price}'),
                  ),
                ),
              if (billing.products.isEmpty && billing.error == null)
                const Text(
                  'No subscription products found.',
                  style: TextStyle(color: Colors.white70),
                ),
              TextButton(
                onPressed:
                    billing.purchasing ? null : () => billing.restore(),
                child: const Text('Restore purchase'),
              ),
            ],
            if (billing.purchasing) ...[
              const SizedBox(height: 8),
              const Text('Talking to the Play Store…',
                  style: TextStyle(color: Colors.white38)),
            ],
            if (billing.error != null) ...[
              const SizedBox(height: 12),
              Text(
                billing.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
