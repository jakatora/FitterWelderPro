// Driver entry point — dev/QA only, never shipped.
//
// Boots the real app (lib/main.dart) with the Flutter Driver extension
// enabled so a tool can tap, type and read the widget tree of the running
// desktop/mobile build. Launch with:
//
//   flutter run -d windows -t test_driver/app.dart
//
// The production entry point stays untouched.

import 'package:flutter_driver/driver_extension.dart';

import 'package:cut_list_app/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
