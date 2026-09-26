import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/db_bootstrap.dart';
import 'domain/qualification/certificate_status.dart';
import 'i18n/app_language.dart';
import 'services/chat_service.dart';
import 'services/premium_service.dart';
import 'services/user_profile.dart';
import 'services/welder_identity.dart';
import 'services/welder_qualification_service.dart';

Future<void> main() async {
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
  //
  // Przy kPaidFeaturesEnabled == false refreshFromBackend wraca PRZED
  // jakimkolwiek żądaniem (pinuje to test/services/device_identity_test.dart),
  // a init() tylko CZYTA SharedPreferences — start niczego nie wysyła i nie
  // tworzy identyfikatora instalacji. Ten powstaje dopiero przy pierwszym
  // żądaniu z nim (czat, skaner, asystent), więc „Usuń moje dane" u montera,
  // który nigdy nie rozmawiał z serwerem, wie, że tam nic nie ma.
  PremiumService.instance.init().then((_) {
    return PremiumService.instance.refreshFromBackend();
  }).catchError((Object e) {
    debugPrint('PremiumService startup refresh failed: $e');
    return PremiumService.instance.status;
  });

  // Sekret instalacji: powiązanie z device_id na serwerze (TOFU) — im
  // wcześniej, tym krócej ktoś znający wyciekły device_id mógłby go „zająć".
  // ALE tylko u montera, który już zaakceptował zasady czatu; bez zgody nic
  // nie wychodzi z telefonu (reszta osób zarejestruje się przy wejściu na
  // czat). Stary backend (404) i brak sieci: po cichu.
  unawaited(ChatService.instance.registerDeviceIfConsented());

  // P0-08: hydrate persistent welder identity so the weld journal editor
  // can auto-fill welder + fitter fields on the very first new entry of
  // the session — no need to wait for the first await elsewhere.
  WelderIdentityService.instance.get().catchError((Object e) {
    debugPrint('WelderIdentityService startup hydrate failed: $e');
    return null;
  });

  // Warm the user profile (first + last name) so the home screen can greet
  // the user by name on the first frame. The profile is no longer required to
  // open the app — only the chat asks for it (see community_gate.dart).
  UserProfileService.instance.get().catchError((Object e) {
    debugPrint('UserProfileService startup hydrate failed: $e');
    return null;
  });

  // Język MUSI być znany przed runApp: AppLanguageController.current jest
  // czytany statycznie poza drzewem (formatowanie liczb, komunikaty po await).
  // Zapisany wybór, a bez niego język telefonu. Nigdy nie rzuca.
  await AppLanguageController.restore();

  runApp(const CutListApp());

  // Rejestr uprawnień spawacza: jednorazowe przeniesienie starego „WPQR"
  // z tożsamości, przeliczenie terminów (daty biegną, dziennik mógł dostać
  // spoiny) i — tylko gdy spawacz sam je włączył — ponowne zaplanowanie
  // przypomnień. Po runApp i bez await: start nie czeka na bazę. Nigdy nie
  // pyta o zgodę na powiadomienia (to robi dopiero przełącznik w rejestrze).
  WelderQualificationService.instance.refresh().catchError((Object e) {
    debugPrint('WelderQualificationService startup refresh failed: $e');
    return QualificationOverview.empty;
  });
}
