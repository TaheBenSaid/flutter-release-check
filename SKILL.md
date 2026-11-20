---
name: flutter-release-check
description: Prepare and verify a Flutter app release so users actually get the update. Use when the user wants to release, ship, bump the version, upload to the App Store or Google Play, or asks why users don't see the "new version available" popup.
---

# Flutter release check

The checker is `scripts/release_check.dart` in this skill's folder. It has no dependencies.

## Steps

1. Read `version:` in `pubspec.yaml`. It has two parts: `name+build`, for example `1.4.0+52`.

2. Bump both parts unless the user says otherwise. Patch for fixes (`1.4.0` -> `1.4.1`), minor for features (`1.4.0` -> `1.5.0`). The build number always goes up by at least one. Never bump only the build number: update prompts compare the name, so users would never be told.

3. From the project root, run:

   ```bash
   dart <skill-folder>/scripts/release_check.dart
   ```

   It compares with the latest git tag. If the project has no tags, ask the user for the last released version and pass `--against 1.4.0+52`.

4. Fix what it reports:
   - Hardcoded `versionCode` / `versionName` in `android/app/build.gradle(.kts)`: replace with `flutter.versionCode` and `flutter.versionName`.
   - Hardcoded `CFBundleShortVersionString` / `CFBundleVersion` in `ios/Runner/Info.plist`: replace with `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)`.

5. Run it again until it says "Ready to ship".

6. Remind the user, without doing these unless asked:
   - tag the release after it goes live (`git tag v1.4.1`) so the next check has something to compare with,
   - if the app has a forced or soft update check served by a backend, raise the "latest version" only once the build is downloadable in the store, and raise the "minimum version" only on purpose.
