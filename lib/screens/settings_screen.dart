import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import '../services/assistant_service.dart';
import '../services/billing_service.dart';
import '../services/notification_service.dart';
import '../services/pet_service.dart';
import '../services/pet_widget_service.dart';
import '../services/sounds.dart';

/// Rename, subscription status, permission explainers, reset.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final petService = context.watch<PetService>();
    final assistant = context.watch<AssistantService>();
    final sounds = context.watch<PetSounds>();
    final pet = petService.pet;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Settings',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.pets),
            title: Text(pet?.name ?? 'No pet'),
            subtitle: const Text('Tap to rename'),
            onTap: () => _renameDialog(context, petService),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium),
            title: const Text('Assistant'),
            subtitle: Text(assistant.isSubscribed
                ? 'Subscribed — thank you!'
                : '${assistant.trialDaysLeft} trial days left'),
            onTap: () => _subscriptionDialog(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notification access'),
            subtitle: const Text(
                'Lets your pet nudge you when hungry or bored.'),
            onTap: () => PetNotifications.ensurePermission(context),
          ),
          ListTile(
            leading: const Icon(Icons.widgets),
            title: const Text('Home screen widget'),
            subtitle: const Text(
                'See your pet on the home screen. Feed and play without opening the app.'),
            onTap: () => _addWidget(context),
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up),
            title: const Text('Sound effects'),
            subtitle: const Text(
                'Tiny blips when feeding, playing, or hitting a milestone. Off by default.'),
            value: sounds.enabled,
            onChanged: (v) => context.read<PetSounds>().setEnabled(v),
          ),
          const Divider(),
          ListTile(
            leading:
                const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Release pet (reset)',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () => _confirmReset(context, petService),
          ),
        ],
      ),
    );
  }

  void _subscriptionDialog(BuildContext context) {
    final billing = context.read<BillingService>();
    final assistant = context.read<AssistantService>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assistant subscription'),
        content: Text(
          assistant.isSubscribed
              ? 'Your subscription is active. To cancel or change it, open the Play Store → Payments & subscriptions → Subscriptions.'
              : 'You have ${assistant.trialDaysLeft} trial days left. Unlock any time from the Chat tab. Already subscribed on this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              billing.restore();
            },
            child: const Text('Restore purchase'),
          ),
        ],
      ),
    );
  }

  /// Ask the launcher to pin the Aura Pet widget (Android 8+). Falls back
  /// to instructions when the launcher doesn't support pinning.
  Future<void> _addWidget(BuildContext context) async {
    try {
      await HomeWidget.requestPinWidget(
        qualifiedAndroidName: PetWidgetService.providerClass,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'That launcher can\'t pin widgets — long-press the home screen, tap Widgets, and add Aura Pet manually.'),
          ),
        );
      }
    }
  }

  void _renameDialog(BuildContext context, PetService service) {    final c = TextEditingController(text: service.pet?.name ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename your pet'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              service.rename(c.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context, PetService service) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Release your pet?'),
        content:
            const Text("This erases everything. They'll pretend not to be hurt."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () {
              service.reset();
              Navigator.pop(context);
            },
            child: const Text('Release'),
          ),
        ],
      ),
    );
  }
}
