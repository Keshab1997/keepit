import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Firebase majors we are on (flutterfire 7.x / core 5.x) raise two native
/// floors that no Dart test can see: minSdk 24 on Android, and Firebase Apple
/// SDK 13 on iOS. Nothing fails in `flutter test` if a future bump raises them
/// again — the build fails instead, minutes later, with an opaque Gradle or
/// CocoaPods error. Pin the floors here so the bump has to be deliberate.
void main() {
  final appRoot = Directory.current;

  File find(String path) {
    final file = File('${appRoot.path}/$path');
    expect(file.existsSync(), isTrue, reason: 'missing $path');
    return file;
  }

  int? minSdkFromGradle(String source) {
    // Either a literal or `flutter.minSdkVersion`, which the Flutter 3.50
    // toolchain pins at 24 (FlutterExtension.kt).
    final literal = RegExp(r'minSdk\s*=?\s*(\d+)').firstMatch(source);
    if (literal != null) return int.parse(literal.group(1)!);
    if (source.contains('flutter.minSdkVersion')) return 24;
    return null;
  }

  test('Android minSdk is at least the firebase 7 floor (24)', () {
    final gradle = find('android/app/build.gradle.kts').readAsStringSync();
    final minSdk = minSdkFromGradle(gradle);
    expect(minSdk, isNotNull, reason: 'could not read minSdk from gradle');
    expect(
      minSdk,
      greaterThanOrEqualTo(24),
      reason: 'firebase_core 5 / auth 7 / firestore 7 require minSdk 24',
    );
  });

  test('iOS deployment target is at least 15.0', () {
    final pbxproj = find(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
    ).allMatches(pbxproj).map((m) => double.parse(m.group(1)!)).toList();

    expect(targets, isNotEmpty, reason: 'no deployment target in pbxproj');
    expect(
      targets.reduce((a, b) => a < b ? a : b),
      greaterThanOrEqualTo(15.0),
      reason: 'Firebase Apple SDK 13 is the floor we build against',
    );
  });

  test('AGP is new enough for flutter_local_notifications 23', () {
    final settings = find('android/settings.gradle.kts').readAsStringSync();
    final agp = RegExp(
      r'com\.android\.application"\) version "([0-9.]+)"',
    ).firstMatch(settings);
    expect(agp, isNotNull);
    // A floor, not an equality: the project rides the toolchain Flutter 3.50
    // ships (AGP 9.3.1) and must never fall below what the notification
    // plugin needs.
    final parts = agp!.group(1)!.split('.').map(int.parse).toList();
    final major = parts[0], minor = parts[1];
    expect(
      major * 100 + minor,
      greaterThanOrEqualTo(901),
      reason: 'the notification plugin targets AGP 9.1.1; keep them aligned',
    );
  });
}
