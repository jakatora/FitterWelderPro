import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'services/premium_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Fire-and-forget: hydrate Premium status from backend so the gate is open
  // immediately if the user already paid. Failure leaves the cached state
  // intact — the Premium screen will retry on its own. Errors get logged
  // (don't crash the splash) and silently swallowed; without the catch,
  // a transient DNS hiccup at startup would surface as an unhandled
  // future and (on debug) interrupt the user.
  PremiumService.instance.init().then((_) {
    return PremiumService.instance.refreshFromBackend();
  }).catchError((Object e) {
    debugPrint('PremiumService startup refresh failed: $e');
    return PremiumService.instance.status;
  });

  runApp(const CutListApp());
}
