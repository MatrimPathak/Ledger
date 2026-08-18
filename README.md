# ledger

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firebase Setup

This app uses Firebase (Auth + Firestore), so it needs `lib/firebase_options.dart`
and `android/app/google-services.json` to build. Both files are intentionally
excluded from version control (see `.gitignore`) since they contain
per-developer/project credentials — you need to generate your own after cloning:

1. Create a Firebase project at the [Firebase console](https://console.firebase.google.com/)
   and register an Android app with package name `com.matrimpathak.ledger`.
2. Enable **Authentication** (Google sign-in provider) and **Cloud Firestore**
   in that project.
3. Install the FlutterFire CLI if you don't have it:
   ```
   dart pub global activate flutterfire_cli
   ```
4. From the repo root, run:
   ```
   flutterfire configure
   ```
   and select the Firebase project and platform(s) you need (Android at minimum).
   This generates `lib/firebase_options.dart` and downloads
   `android/app/google-services.json` for you.

See `lib/firebase_options.example.dart` for the shape FlutterFire generates —
do not use it as-is, it contains placeholder values only.
