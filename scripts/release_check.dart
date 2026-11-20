import 'dart:io';

final _ansi = stdout.supportsAnsiEscapes;
final _green = _ansi ? '\x1B[32m' : '';
final _red = _ansi ? '\x1B[31m' : '';
final _yellow = _ansi ? '\x1B[33m' : '';
final _reset = _ansi ? '\x1B[0m' : '';

final _versionLine = RegExp(r'^version:\s*([^\s#]+)', multiLine: true);

class Version {
  Version(this.raw, this.parts, this.build);

  final String raw;
  final List<int> parts;
  final int? build;

  String get name => parts.join('.');

  static Version? parse(String raw) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-[\w.]+)?(?:\+(\d+))?$').firstMatch(raw.trim());
    if (m == null) return null;
    return Version(
      raw.trim(),
      [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)],
      m[4] == null ? null : int.parse(m[4]!),
    );
  }

  int compareName(Version other) {
    for (var i = 0; i < 3; i++) {
      final d = parts[i] - other.parts[i];
      if (d != 0) return d;
    }
    return 0;
  }
}

class Report {
  final passed = <String>[];
  final failed = <String>[];
  final warnings = <String>[];
}

void main(List<String> args) {
  final against = _option(args, '--against');
  final positional = [
    for (var i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') && (i == 0 || args[i - 1] != '--against')) args[i],
  ];
  final root = positional.isEmpty ? '.' : positional.first;

  final pubspec = File('$root/pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('No pubspec.yaml in $root. Run it from your Flutter project root.');
    exit(2);
  }

  final report = Report();
  final current = _readVersion(pubspec.readAsStringSync());
  if (current == null) {
    stderr.writeln('Could not read a version like 1.4.0+52 from pubspec.yaml.');
    exit(2);
  }

  final baseRef = against ?? _latestTag(root);
  _checkBump(root, current, baseRef, report);
  _checkAndroid(root, report);
  _checkIos(root, report);

  print('Flutter release check: ${current.raw}${baseRef == null ? '' : ' (against $baseRef)'}\n');
  for (final p in report.passed) {
    print('  $_green✓$_reset $p');
  }
  for (final w in report.warnings) {
    print('  $_yellow!$_reset $w');
  }
  for (final f in report.failed) {
    print('  $_red✗$_reset $f');
  }

  if (report.failed.isEmpty) {
    print('\nReady to ship.');
    return;
  }
  print('\n${report.failed.length} problem${report.failed.length == 1 ? '' : 's'}. Fix before you upload.');
  exit(1);
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i != -1 && i + 1 < args.length) return args[i + 1];
  final inline = args.where((a) => a.startsWith('$name='));
  return inline.isEmpty ? null : inline.first.substring(name.length + 1);
}

Version? _readVersion(String pubspec) {
  final m = _versionLine.firstMatch(pubspec);
  return m == null ? null : Version.parse(m[1]!);
}

String? _git(String root, List<String> args) {
  try {
    final res = Process.runSync('git', ['-C', root, ...args]);
    return res.exitCode == 0 ? (res.stdout as String).trim() : null;
  } on ProcessException {
    return null;
  }
}

String? _latestTag(String root) {
  final tag = _git(root, ['describe', '--tags', '--abbrev=0']);
  return tag == null || tag.isEmpty ? null : tag;
}

void _checkBump(String root, Version current, String? ref, Report report) {
  if (current.build == null) {
    report.failed.add('No build number in pubspec.yaml. Use name+build, like ${current.name}+1');
    return;
  }

  if (ref == null) {
    report.warnings.add('No git tag to compare with. Tag each release (git tag v${current.name}) '
        'or pass --against <ref|version>');
    return;
  }

  var previous = Version.parse(ref.replaceFirst(RegExp(r'^v'), ''));
  if (previous == null || previous.build == null) {
    final old = _git(root, ['show', '$ref:pubspec.yaml']);
    final fromGit = old == null ? null : _readVersion(old);
    if (fromGit != null) previous = fromGit;
  }
  if (previous == null) {
    report.warnings.add("Couldn't read the previous version from '$ref'");
    return;
  }

  final nameDiff = current.compareName(previous);
  if (nameDiff > 0) {
    report.passed.add('Version name bumped: ${previous.name} -> ${current.name}');
  } else if (nameDiff == 0) {
    report.failed.add('Version name is still ${current.name}. Google Play takes the upload, but update '
        'prompts compare the name, so users are never told. Bump it to '
        '${current.parts[0]}.${current.parts[1]}.${current.parts[2] + 1}');
  } else {
    report.failed.add('Version name went backwards: ${previous.name} -> ${current.name}');
  }

  if (previous.build == null) return;
  if (current.build! > previous.build!) {
    report.passed.add('Build number bumped: ${previous.build} -> ${current.build}');
  } else {
    report.failed.add('Build number ${current.build} is not above ${previous.build}. '
        'Both stores reject an upload that reuses or lowers it');
  }
}

void _checkAndroid(String root, Report report) {
  final gradle = [
    File('$root/android/app/build.gradle.kts'),
    File('$root/android/app/build.gradle'),
  ].where((f) => f.existsSync());
  if (gradle.isEmpty) return;

  final src = gradle.first
      .readAsLinesSync()
      .map((l) => l.replaceFirst(RegExp(r'//.*'), ''))
      .join('\n');
  final file = 'android/app/${gradle.first.uri.pathSegments.last}';
  final code = RegExp(r'^\s*versionCode\s*=?\s*(\S+)', multiLine: true).firstMatch(src)?[1];
  final name = RegExp(r'^\s*versionName\s*=?\s*(\S+)', multiLine: true).firstMatch(src)?[1];

  final hardcoded = <String>[
    if (code != null && !code.contains('flutter')) 'versionCode $code',
    if (name != null && !name.contains('flutter')) 'versionName $name',
  ];
  if (hardcoded.isEmpty) {
    report.passed.add('Android reads the version from pubspec.yaml');
  } else {
    report.failed.add('$file hardcodes ${hardcoded.join(' and ')}, so your pubspec bump never '
        'reaches Android. Use flutter.versionCode and flutter.versionName');
  }
}

void _checkIos(String root, Report report) {
  final plist = File('$root/ios/Runner/Info.plist');
  if (!plist.existsSync()) return;

  final src = plist.readAsStringSync();
  String? value(String key) =>
      RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(src)?[1];

  final short = value('CFBundleShortVersionString');
  final build = value('CFBundleVersion');
  final hardcoded = <String>[
    if (short != null && !short.contains('FLUTTER_BUILD_NAME') && !short.contains('MARKETING_VERSION'))
      'CFBundleShortVersionString $short',
    if (build != null && !build.contains('FLUTTER_BUILD_NUMBER') && !build.contains('CURRENT_PROJECT_VERSION'))
      'CFBundleVersion $build',
  ];
  if (hardcoded.isEmpty) {
    report.passed.add('iOS reads the version from pubspec.yaml');
  } else {
    report.failed.add('ios/Runner/Info.plist hardcodes ${hardcoded.join(' and ')}. '
        r'Use $(FLUTTER_BUILD_NAME) and $(FLUTTER_BUILD_NUMBER)');
  }
}
