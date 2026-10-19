// kAppVersion musi być równa `version:` z pubspec.yaml — inaczej sygnały
// feedbacku przypisywałyby problemy złej wersji aplikacji.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/config/app_version.dart';

void main() {
  test('kAppVersion = version z pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([^\s#]+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'brak linii version: w pubspec.yaml');
    expect(kAppVersion, match!.group(1),
        reason: 'podbij lib/config/app_version.dart razem z pubspec.yaml');
  });
}
