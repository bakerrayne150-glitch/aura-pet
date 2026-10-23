import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/pet_service.dart';
import 'services/pet_widget_service.dart';
import 'services/sounds.dart';
import 'services/assistant_service.dart';
import 'services/billing_service.dart';
import 'services/notification_service.dart';
import 'screens/pet_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';

/// Deep-link requests from the home screen widget (e.g. open the Chat tab).
/// Set by the widgetClicked listener / cold-start check in main();
/// MainTabs consumes and clears it.
final widgetDeepLink = ValueNotifier<Uri?>(null);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase - same project for debug and release (just HTTPS).
  // Get these from your Supabase dashboard: Project Settings -> API.
  await Supabase.initialize(
    url: 'https://YOUR_PROJECT_REF.supabase.co',
    anonKey: 'YOUR_ANON_KEY',
  );

  // Home screen widget: background taps (Feed/Play/Nap) run the
  // top-level widgetActionCallback even when the app is closed; taps that
  // should open the app (Chat button, widget body) arrive as deep links.
  // Wrapped defensively: the app must start even if widget setup fails.
  try {
    await HomeWidget.registerInteractivityCallback(widgetActionCallback);
    HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) widgetDeepLink.value = uri;
    });
    widgetDeepLink.value = await HomeWidget.initiallyLaunchedFromHomeWidget();
  } catch (_) {}

  await PetNotifications.init();
  runApp(const AuraPetApp());
}

class AuraPetApp extends StatelessWidget {
  const AuraPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PetService()..load()),
        ChangeNotifierProvider(create: (_) => PetSounds()..load()),
        ChangeNotifierProvider(create: (_) => AssistantService()..init()),
        ChangeNotifierProxyProvider<AssistantService, BillingService>(
          create: (ctx) => BillingService(ctx.read<AssistantService>()),
          update: (_, __, billing) => billing!..ensureInit(),
        ),
      ],
      child: MaterialApp(
        title: 'Aura Pet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.tealAccent,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF121216),
          useMaterial3: true,
        ),
        home: const RootGate(),
      ),
    );
  }
}

/// Onboarding (name your pet) until a pet exists, then the main tabs.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final petService = context.watch<PetService>();
    if (!petService.loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!petService.hasPet) {
      return const OnboardingScreen();
    }
    return const MainTabs();
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  late final AnimationController _wobble;
  bool _hatching = false;
  bool _cracked = false;

  @override
  void initState() {
    super.initState();
    _wobble = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _wobble.dispose();
    super.dispose();
  }

  /// The hatching beat: the egg wobbles, cracks, then the pet pops out
  /// with the celebration wiggle on the other side.
  Future<void> _hatchSequence() async {
    if (_hatching) return;
    FocusScope.of(context).unfocus();
    setState(() => _hatching = true);
    _wobble.repeat();
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _wobble.stop();
    setState(() => _cracked = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final service = context.read<PetService>();
    await service.createPet(_name.text.trim());
    // Bump after the first frame so the fresh PetCreature's celebrate
    // listener catches the tick and plays the pop-out wiggle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      service.celebrateTick.value++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _wobble,
                builder: (context, child) {
                  final wobble = _hatching && !_cracked
                      ? math.sin(_wobble.value * math.pi * 4) * 0.18
                      : 0.0;
                  return Transform.rotate(angle: wobble, child: child);
                },
                child: Text(
                  _cracked ? '🐣' : '🥚',
                  style: const TextStyle(fontSize: 72),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _cracked ? 'They made it!' : 'Something is hatching…',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Feed it, play with it, and chat with its AI brain — the first 7 days of big-brain chat are free.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              const Text(
                'Give your pet a name to begin.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                enabled: !_hatching,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: 'e.g. Aura',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _hatchSequence(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _hatching ? null : _hatchSequence,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 4),
                  child: Text(_hatching ? 'Hatching…' : 'Hatch!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;

  static const _screens = [
    PetScreen(),
    ChatScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _consumeWidgetDeepLink(widgetDeepLink.value);
    widgetDeepLink.addListener(_onWidgetDeepLink);
    // First launch with a pet: let the pet pitch notification access
    // itself, so its hungry/bored nudges can actually fire.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await PetNotifications.ensurePermission(context);
    });
  }

  @override
  void dispose() {
    widgetDeepLink.removeListener(_onWidgetDeepLink);
    super.dispose();
  }

  void _onWidgetDeepLink() => _consumeWidgetDeepLink(widgetDeepLink.value);

  /// aurapet://open?tab=chat -> Chat tab; tab=pet (or anything else) -> Pet.
  void _consumeWidgetDeepLink(Uri? uri) {
    if (uri == null || uri.host != 'open') return;
    widgetDeepLink.value = null; // consume first so we can't loop
    final idx = uri.queryParameters['tab'] == 'chat' ? 1 : 0;
    if (idx != _index && mounted) setState(() => _index = idx);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.pets), label: 'Pet'),
          NavigationDestination(icon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
