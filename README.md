# Reclaim

A private AI screen-time coach for Android — on-device Gemma 3, zero
servers, and an accessibility-powered app freezer that holds the line.

Built for [Hacktoberfest 2026 — Week 2: Side Hustle](https://dev.to/challenges/hacktoberfest-week2-2026-10-12).

<img width="2400" height="1500" alt="reclaim-banner-v3" src="https://github.com/user-attachments/assets/771f216f-14fe-47bd-a58a-fe8ac9c0765b" />


## What it is

Reclaim reads the ~7 days of usage history Android already keeps and turns
it into a blunt, kind coaching digest — plus enforceable app-freeze windows
— entirely on-device.

- `UsageStatsManager` bulk-pull reconstructs real sessions: pickups,
  late-night usage, 20m+ "long sessions", per-day breakdowns
- A locally-running Gemma 3 1B IT model (LiteRT/MediaPipe) narrates the
  numbers — every stat is computed in Dart, never by the model
- Structured coaching output: verdict, sink app, daily goal,
  cap/protect/replace actions, and wins — benchmarked against bundled
  global data
- Custom Kotlin `AccessibilityService` freezes chosen apps on a schedule,
  showing a full-screen blocker with an emergency 5-minute unlock

## Why open-source AI

- **Private by design**: usage history never leaves the phone — there is no
  server to send it to
- **Offline**: coaching works with zero signal after a one-time model
  download
- **Inspect**: the `.task` model file is swappable — audit it, replace it,
  bring your own
- **Zero cost**: no API bill, ever

## Stack

| Layer | Tech |
|---|---|
| App | Flutter 3.44.5 / Dart 3.12.2 |
| AI | Gemma 3 1B IT (`gemma3-1b-it-int4.task`) via `flutter_edge_ai` + `flutter_edge_ai_mediapipe` |
| Usage data | `usage_stats` (UsageStatsManager), `installed_apps` |
| Blocking | Custom Kotlin `AccessibilityService` + `BlockerActivity` |
| Benchmarks | `assets/benchmarks.json` — bundled global stats, no network |
| UI | `fl_chart`, `confetti` |

## Quick start

```bash
fvm flutter pub get
fvm flutter run           # physical Android device — usage stats don't exist on emulators
fvm flutter test
fvm flutter build apk --debug
```

Grant **Usage Access** on first launch. In the coach screen, paste a
Hugging Face token (free account; accept the Gemma license once) to
download the ~0.6 GB model, or `adb push` any `.task` file. Enable the
accessibility service in Settings to use app freezing.

## Project structure

```
lib/
  main.dart               # app entry + theme
  aggregator.dart         # raw events -> sessions/stats
  coach_service.dart      # two-pass on-device coaching
  benchmarks.dart         # "you vs the world" comparisons
  freeze_rules.dart       # freeze-rule store + native bridge
  daily_archive.dart      # extends history past Android's 7d cap
  wins.dart               # streaks, milestones, coach tone
  screens/                # dashboard, coach, freeze rules, onboarding
assets/
  benchmarks.json         # bundled global screen-time facts
android/                  # Custom Kotlin AccessibilityService + blocker
```

## License

MIT

---

<p align="center">Built with ❤️ by <a href="https://github.com/Musaddiq625">Musaddiq625</a></p>
