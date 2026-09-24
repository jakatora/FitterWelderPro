// Skaner ISO w darmowym trybie z limitem: flagi i adres backendu.
//
// Pilnuje, że skaner jest osiągalny BEZ płatności (darmowy tryb), a płatności
// nadal są wyłączone — czyli nic w aplikacji nie może prowadzić do ekranu
// z ceną. Adres skanera to dedykowany backend, ten sam co reszta aplikacji.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/config/backend_config.dart';
import 'package:cut_list_app/config/feature_flags.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

void main() {
  test('darmowy tryb skanera: osiągalny bez płatności', () {
    expect(kAiScannerEnabled, isTrue);
    expect(kAiScannerFreeTier, isTrue);
    expect(kPaidFeaturesEnabled, isFalse,
        reason: 'płatności wyłączone — żaden ekran nie pokazuje ceny');
    expect(kAiScannerReachable, isTrue);
  });

  test('klientowy limit dzienny = domyślny limit serwera (bezpiecznik)', () {
    // backend/src/config/env.js: AI_SCAN_DAILY_PER_DEVICE domyślnie 10.
    expect(kAiScanDailyLimitPerDevice, 10);
  });

  test('skaner na dedykowanym backendzie, nie na PrzetargAI', () {
    expect(BackendConfig.scannerBaseUrl, BackendConfig.baseUrl);
    expect(BackendConfig.scannerBaseUrl, isNot(contains('a43e3')));
  });

  test('kafel skanera jest w rejestrze i nie wymaga imienia', () {
    final scanner = toolById('iso_scanner');
    expect(scanner, isNotNull);
    // Zdjęcie rysunku nie jest publikowane pod nazwiskiem — zgoda na
    // wysyłkę jest pytana przed pierwszym skanem (scan_consent_gate.dart),
    // a ręczne wpisywanie wymiarów działa bez niczego.
    expect(scanner!.needsAccount, isFalse);
  });
}
