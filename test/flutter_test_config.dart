// Wspólna konfiguracja wszystkich testów (`flutter test` ładuje ją sam).
//
// Dane zawodowe — rejestry w bazie i zapisy modułów w SharedPreferences —
// należą do właściciela danych, więc każdy odczyt i zapis pyta o konto.
// Prawdziwy AccountService sięga do pamięci bezpiecznej, której w testach nie
// ma (brak wtyczki), więc domyślnie każdy test działa jako gość offline:
// dane sprzed kont i zapisy testów bez konta są gościa, jak w aplikacji.
// Testy kont ustawiają własne AccountService (`seedSignedInAccount`, `signIn`)
// tak jak dotąd.

import 'dart:async';

import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSecureStorage.setMockInitialValues({});
  AccountService.instance = AccountService.forTesting(
      MockClient((_) async => http.Response('{}', 500)));
  await testMain();
}
