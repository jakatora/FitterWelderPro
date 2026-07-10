import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/db_bootstrap.dart';
import 'services/premium_service.dart';
import 'services/user_profile.dart';
import 'services/welder_identity.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Fabryka bazy zależna od platformy (desktop → FFI, web → SQLite w WASM,
  // mobile → wbudowana). Wybór rozstrzyga warunkowy import, bo `dart:ffi`
  // i `dart:js_interop` wykluczają się nawzajem. Nie pytamy tu o platformę
  // przez `dart:io Platform` — to rzucało `Unsupported operation:
  // Platform._operatingSystem` i wywracało aplikację w przeglądarce.
  initDatabaseFactory();

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

  // P0-08: hydrate persistent welder identity so the weld journal editor
  // can auto-fill welder + fitter fields on the very first new entry of
  // the session — no need to wait for the first await elsewhere.
  WelderIdentityService.instance.get().catchError((Object e) {
    debugPrint('WelderIdentityService startup hydrate failed: $e');
    return null;
  });

  // Warm the first-run user profile (first + last name) so the RootGate can
  // decide onboarding-vs-home from cache without a visible spinner flash.
  UserProfileService.instance.get().catchError((Object e) {
    debugPrint('UserProfileService startup hydrate failed: $e');
    return null;
  });

  runApp(const CutListApp());
}
