# Aura Pet

Tamagotchi-style virtual pet + AI assistant for Android, built with Flutter.

## What it is

Raise a virtual creature that grows through life stages — **Baby → Teen → Adult** — with stats that decay in real time. Chat with your pet through an AI assistant, get care reminders, and check on it from a home-screen widget.

## Features

- **Evolution stages** — the pet visibly grows: Baby (days 0–1) → Teen (days 2–6) → Adult (day 7+), with an evolution celebration
- **AI chat** — talk to your pet through a Supabase edge-function proxy; the API key stays server-side, and an offline personality keeps the pet talking when the backend is unreachable
- **Real-time stats** — hunger / happiness / energy decay on a wall clock, with local notification nudges
- **Home-screen widget** — native Android widget showing your pet's status
- **Subscriptions** — 7-day trial + Play Billing, with server-side receipt verification

## Tech

Flutter · Dart · Supabase (auth + edge functions) · Play Billing (`in_app_purchase`) · `flutter_local_notifications` · `home_widget`

## Project layout

- `lib/main.dart` — entry, dark theme, onboarding, bottom tabs
- `lib/models/pet.dart` — stats, wall-clock decay, moods, persistence
- `lib/services/` — pet state, AI assistant, billing, notifications, widget, sounds, haptics
- `lib/screens/` — pet view, chat, settings
- `lib/widgets/` — the creature (CustomPainter), stat bars, action overlays
- `android/` — home-screen widget (Kotlin provider, layouts, resources)
- `supabase/` — backend: edge functions, DB migration, `.env.example`

## Getting started

### App

1. Install the Flutter SDK (>= 3.38.1, Dart >= 3.10.0)
2. `flutter pub get`
3. Put your Supabase project URL and anon key in `lib/main.dart` (`Supabase.initialize`)
4. `flutter run`

### Backend (Supabase)

1. `supabase/migrations/001_aura_pet_schema.sql` — run in the Supabase SQL editor
2. `supabase/functions/chat` — AI chat proxy (server-side LLM key, trial + daily cap enforced)
3. `supabase/functions/verify-subscription` — Play Billing purchase verification
4. Copy `supabase/.env.example` to `supabase/.env`, fill in real values (**never commit `.env`**), then:
   ```bash
   supabase functions deploy chat
   supabase functions deploy verify-subscription
   supabase secrets set LLM_API_KEY=... PLAY_SERVICE_ACCOUNT=...
   ```
