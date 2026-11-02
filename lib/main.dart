import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/db_bootstrap.dart';
import 'data/database_location_problem.dart';
import 'domain/qualification/certificate_status.dart';
import 'i18n/app_language.dart';
import 'services/account_service.dart';
import 'services/chat_service.dart';
import 'services/electrode_reminders.dart';
import 'services/premium_service.dart';
import 'services/user_profile.dart';
import 'services/welder_identity.dart';
import 'services/welder_qualification_service.dart';
import 'screens/database_recovery_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Fabryka bazy zależna od platformy (desktop → FFI, web → SQLite w WASM,
  // mobile → wbudowana). Wybór rozstrzyga warunkowy import, bo `dart:ffi`
  // i `dart:js_interop` wykluczają się nawzajem. Nie pytamy tu o platformę
  // przez `dart:io Platform` — to rzucało `Unsupported operation:
  // Platform._operatingSystem` i wywracało aplikację w przeglądarce.
  try {
    await initDatabaseFactory();
  } catch (error) {
    // Never start with an empty database when the previous one cannot be
    // identified. The error is selectable to support recovery without moving
    // or deleting any of the user's files.
    if (error is DatabaseLocationProblem) {
      runApp(MaterialApp(
        home: DatabaseRecoveryScreen(
          problem: error,
          onSelect: (directory, candidates) async {
            await selectExistingDatabase(directory, candidates);
            await main();
          },
        ),
      ));
      return;
    }
    runApp(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('FitterWelder Pro')),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'Nie można bezpiecznie otworzyć danych aplikacji. '
              'Sprawdź, czy wcześniejszy folder z danymi jest dostępny. '
              'Jeśli istnieje kilka baz, zachowaj je i skontaktuj się z pomocą.\n\n'
              'The application data could not be opened safely. '
              'Check that the previous data folder is available. '
              'If several databases exist, keep them and contact support.\n\n'
              '$error',
            ),
          ),
        ),
      ),
    ));
    return;
  }

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

  // Powiadomienia o elektrodach starego konta znikają także wtedy, gdy
  // użytkownik przełączy konto poza ekranem dziennika elektrod.
  ElectrodeReminderAccountBinding(
    account: AccountService.instance,
    reminders: electrodeReminders,
  ).start();

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
