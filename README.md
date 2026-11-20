# flutter-release-check

Catches the release mistakes that stop users from ever seeing your update: a version name that didn't move, a build number that went backwards, and Android or iOS files that ignore `pubspec.yaml`.

Run it before every upload, by hand, in CI, or through your AI coding agent as a skill.

## The problem

```yaml
version: 1.4.0+52   # last release
version: 1.4.0+53   # this release
```

Google Play accepts that upload. But almost every "new version available" popup compares the version name, and `1.4.0` didn't change, so your users are never told an update exists. And if `build.gradle` or `Info.plist` hardcode the version, your bump in `pubspec.yaml` never reaches the stores at all.

## Run it

```bash
git clone https://github.com/TaheBenSaid/flutter-release-check.git
dart flutter-release-check/scripts/release_check.dart
```

Run it from your Flutter project root. It compares `pubspec.yaml` with your latest git tag:

```
Flutter release check: 1.4.0+53 (against v1.4.0)

  ✓ Build number bumped: 52 -> 53
  ✓ Android reads the version from pubspec.yaml
  ✓ iOS reads the version from pubspec.yaml
  ✗ Version name is still 1.4.0. Google Play takes the upload, but update prompts compare the name, so users are never told. Bump it to 1.4.1

1 problem. Fix before you upload.
```

No tags yet? Compare with a version or any git ref:

```bash
dart release_check.dart --against 1.4.0+52
dart release_check.dart --against main
```

No dependencies, nothing to add to your `pubspec.yaml`.

## What it checks

| Check | Why it matters |
| --- | --- |
| Version name went up | Update popups compare the name, and it's the number users see in the store |
| Build number went up | Both stores reject a reused or lower build number |
| `versionCode` / `versionName` in `android/app/build.gradle(.kts)` come from Flutter | A hardcoded value silently ignores `pubspec.yaml` |
| `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist` come from Flutter | Same thing on iOS |

## Use it as a skill

Clone it into your agent's skills folder:

```bash
git clone https://github.com/TaheBenSaid/flutter-release-check.git ~/.claude/skills/flutter-release-check
```

Then say "prepare a release" or "bump the version". The agent bumps both parts of the version, runs the check, fixes hardcoded platform versions, and reminds you to tag the release and update any minimum/latest version your backend serves.

## Use it in CI

The script exits with code 1 when something is wrong. Copy `release_check.dart` into your repo, for example under `tools/`, and add a step before the build:

```yaml
- run: dart tools/release_check.dart
```

Make sure the checkout fetches tags (`fetch-depth: 0` on `actions/checkout`).

## More tools

Part of a series of small Flutter tools, each tied to a problem I write about. The full list is in [flutter-skills](https://github.com/TaheBenSaid/flutter-skills).

## License

MIT
