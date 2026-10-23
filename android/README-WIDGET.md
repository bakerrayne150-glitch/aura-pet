# Aura Pet — Home Screen Widget pack

Your pet on the Android home screen: name, mood, stat bars, the assistant's
latest line, and **Feed / Play / Nap / Chat** buttons. Feed, Play and Nap work
right from the home screen without opening the app; Chat opens the app
straight into the Chat tab.

## Setup (do once)

1. **Copy the files in.** Extract this zip into your project root
   (`C:\Users\laura\Downloads\aura-pet-fresh-start\aura-pet-fresh`), letting it
   overwrite. It adds/updates `lib/`, `pubspec.yaml`, and the `android/` files.

2. **Patch the manifest** (one line, run from the project root):
   `powershell -ExecutionPolicy Bypass -File android\add-widget-to-manifest.ps1`

3. **Get the package:**
   `flutter pub get`
   (home_widget needs Flutter 3.38.1+ — if pub complains, run `flutter upgrade`.)

4. **Run it:**
   `flutter run`

5. **Add the widget** — either:
   - In the app: Settings → **Home screen widget** (tries to pin it for you), or
   - Long-press the home screen → Widgets → **Aura Pet** → drag it on.

## How it works

- `lib/services/pet_widget_service.dart` — pushes pet state to the widget
  after every action, and handles Feed/Play/Nap taps in a background isolate
  (works even when the app is fully closed).
- `PetService` pushes a widget update on every feed/play/pet/nap/rename, and
  adopts widget-side changes when you act from the home screen while the app
  is open.
- `AssistantService` saves each reply so the widget shows the latest one.
- Tapping the widget body opens the Pet tab; the Chat button opens Chat.
- The native widget (`AuraPetWidgetProvider.kt`) re-applies the same
  wall-clock decay as the Dart pet model, so stats stay truthful on the
  system's 30-minute refreshes while the app is closed.
- If your launcher can't auto-pin: long-press home screen → Widgets → Aura Pet.
- If the buttons look clipped, drag the widget taller — it's resizable.

## Files

| File | What it is |
|---|---|
| `lib/services/pet_widget_service.dart` | **New.** Widget bridge + background tap handler |
| `lib/services/pet_service.dart` | Updated: pushes widget updates, syncs widget-side actions |
| `lib/services/assistant_service.dart` | Updated: saves latest reply for the widget |
| `lib/screens/settings_screen.dart` | Updated: "Home screen widget" row with pin button |
| `lib/main.dart` | Updated: widget callback registration + deep-link tab routing |
| `pubspec.yaml` | Updated: adds `home_widget: ^0.10.0` |
| `android/.../AuraPetWidgetProvider.kt` | **New.** Native widget provider (renders + decay + clicks) |
| `android/.../res/layout/aura_pet_widget.xml` | **New.** Widget layout |
| `android/.../res/xml/aura_pet_widget_info.xml` | **New.** Widget size/refresh config |
| `android/.../res/drawable/widget_background.xml` | **New.** Rounded dark background |
| `android/.../res/values/widget_strings.xml` | **New.** Widget description string |
| `android/add-widget-to-manifest.ps1` | One-time manifest patch script |

Android-only in v1 (that's your phone — the S23+).
