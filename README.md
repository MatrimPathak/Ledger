# Ledger

Ledger is a Flutter Android personal finance app with Firebase Auth/Firestore,
Claude-powered SMS parsing and analytics, native Android SMS background
processing, and local transaction notifications.

## Tech Stack

| Area | Implementation |
| --- | --- |
| App | Flutter / Dart SDK `^3.8.1` |
| State and routing | Riverpod, GoRouter |
| Backend | Firebase Auth, Cloud Firestore |
| AI | Anthropic Messages API through `ClaudeService` |
| Android SMS | Foreground `another_telephony`; killed/background native `SmsReceiver` + WorkManager |
| Notifications | `flutter_local_notifications` plus native Android notification fallback |

## Required Local Files

These files are intentionally gitignored and must be supplied locally:

| File | How to create it |
| --- | --- |
| `.env` | Add `CLAUDE_API_KEY=YOUR_CLAUDE_API_KEY_HERE` or a real Claude API key |
| `lib/firebase_options.dart` | Run `flutterfire configure` |
| `android/app/google-services.json` | Download from the Firebase Android app settings |

Do not commit real Firebase config or Claude keys.

## Setup

```bash
flutter pub get
npm install
```

Create `.env`:

```bash
printf 'CLAUDE_API_KEY=YOUR_CLAUDE_API_KEY_HERE\n' > .env
```

Generate Firebase options and add the Android config file:

```bash
flutterfire configure
# then place google-services.json at android/app/google-services.json
```

Run on an Android device or emulator:

```bash
flutter run
```

## Tests

Run Flutter/Dart tests:

```bash
flutter test
```

Run Firestore security rules tests:

```bash
npm test
```

Focused commands:

| Area | Command |
| --- | --- |
| SMS pipeline | `flutter test test/sms_service_test.dart test/services/sms/bank_sms_filter_test.dart` |
| Claude behavior | `flutter test test/services/ai/claude_service_test.dart test/claude_service_test.dart` |
| Firestore and rules | `flutter test test/services/firebase/firestore_service_test.dart test/firestore_service_test.dart && npm test` |
| Build configuration | `flutter test test/build_configuration_test.dart` |

## Android SMS Notes

The current SMS architecture has two runtime paths:

- Foreground: `SmsService.startListening()` uses `another_telephony` with
  `listenInBackground: false`.
- Background or killed app: Android `SMS_RECEIVED` is handled by
  `SmsReceiver.kt`, which enqueues `SmsProcessingWorker.kt` through WorkManager.

SharedPreferences bridges settings and secrets needed outside the foreground
Flutter UI: `uid`, `auto_detect_enabled`, `notifications_enabled`,
`claude_api_key`, `processed_sms_ids`, and `last_sms_timestamp`.

E-mandate/NACH pre-debit notices currently differ by path: the Dart foreground
handler skips them entirely after marking the fingerprint processed, while the
native Kotlin worker writes a non-balance transaction with
`affectsBalance=false`.

## Known Drift

Some regression tests document intended invariants that are not yet reflected in
this checkout:

- `test/android_manifest_test.dart` still expects the old
  `another_telephony` background receiver behavior, but the manifest disables
  that receiver and registers `.SmsReceiver`.
- `test/build_configuration_test.dart` expects `.env.example`, a specific
  `.gitignore` explanation, and `kotlin.incremental=false`.

Update the tests or source together when resolving those contracts.
