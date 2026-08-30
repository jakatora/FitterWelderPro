# Audyt wszystkich modułów — plan wdrożenia

> **Dla agentów wykonawczych:** WYMAGANA UMIEJĘTNOŚĆ: użyj `superpowers:subagent-driven-development` (zalecane) albo `superpowers:executing-plans`, realizując zadania po kolei. Kroki używają pól wyboru (`- [ ]`).

**Cel:** Utworzyć kompletną, sprawdzalną inwentaryzację wszystkich modułów Fitter Welder Pro, wykryć regresje i nadać każdemu modułowi status poparty dowodem.

**Architektura:** Statyczny manifest opisuje moduły widoczne dla użytkownika, ich punkty wejścia, ryzyko i dowody. Test kompletności porównuje manifest z ekranami w `lib/screens` i `lib/modules/**/ui`; testy domenowe i widżetowe dostarczają dowodów, a generator tworzy raport Markdown.

**Stos technologiczny:** Flutter/Dart, `flutter_test`, SQLite, SharedPreferences.

**Specyfikacja:** `docs/superpowers/specs/2026-08-30-profesjonalna-platforma-spolecznosciowa-i-asystent-design.md`

## Ograniczenia globalne

- Nie usuwać ani nie ukrywać żadnego istniejącego modułu.
- Nie nadpisywać obecnych zmian skanera ISO.
- Nie wykonywać rzeczywistych płatności ani płatnych wywołań AI.
- Testy sieciowe używają podstawionego transportu; pełny test nie zależy od Railway.
- Status `działa prawidłowo` wymaga wskazanego testu lub ręcznego scenariusza z wynikiem.
- Po każdej partii uruchomić testy celowane; na końcu pełne analyze i testy.

## Struktura plików

- `tool/audit/module_manifest.dart` — typy i kompletna lista modułów.
- `tool/audit/render_audit_report.dart` — generator raportu.
- `test/audit/module_manifest_test.dart` — kompletność manifestu.
- `test/audit/fitter_calculations_audit_test.dart` — obliczenia monterskie.
- `test/audit/welder_calculations_audit_test.dart` — obliczenia spawalnicze.
- `test/audit/data_integrity_audit_test.dart` — dane, migracje i eksporty.
- `test/audit/module_smoke_test.dart` — renderowanie i stany błędów.
- `docs/audits/2026-08-30-module-audit.md` — raport końcowy.

---

### Task 1: Manifest i kontrola kompletności

**Pliki:**
- Utwórz: `tool/audit/module_manifest.dart`
- Utwórz: `test/audit/module_manifest_test.dart`

**Interfejsy:**
- Dostarcza: `AuditCategory`, `AuditRisk`, `AuditStatus`, `ModuleAuditEntry`, `moduleManifest`.
- Konsumują później: generator raportu i fabryka ekranów testowych.

- [ ] **Krok 1: Napisz test, który najpierw nie przejdzie**

Test wczytuje `lib/screens/*_screen.dart` i `lib/modules/**/ui/*_screen.dart`, wyodrębnia publiczne klasy pasujące do `class ([A-Z][A-Za-z0-9]+Screen)` i wymaga dokładnie jednego wpisu dla każdej klasy. Odrzuca powtórzone `id`, puste ścieżki i scenariusze.

```dart
test('każdy publiczny ekran ma dokładnie jeden wpis audytu', () {
  final discovered = discoverPublicScreens(Directory('lib'));
  final declared = moduleManifest.map((e) => e.entryPoint).toSet();
  expect(declared, discovered);
});

test('zaliczony status wskazuje dowód', () {
  final invalid = moduleManifest.where(
    (e) => e.status == AuditStatus.passed && e.evidence.isEmpty,
  );
  expect(invalid, isEmpty);
});
```

- [ ] **Krok 2: Potwierdź czerwoną fazę**

Uruchom: `flutter test --no-pub test/audit/module_manifest_test.dart`  
Oczekiwane: FAIL, ponieważ manifest jeszcze nie istnieje.

- [ ] **Krok 3: Dodaj minimalne typy i wszystkie wpisy**

```dart
enum AuditCategory { start, fitter, welder, project, document, social, account, ai }
enum AuditRisk { low, medium, high, safetyCritical }
enum AuditStatus { unverified, passed, simplify, broken, domainReview }

class ModuleAuditEntry {
  final String id;
  final String entryPoint;
  final String sourcePath;
  final AuditCategory category;
  final AuditRisk risk;
  final AuditStatus status;
  final String scenario;
  final List<String> evidence;
  const ModuleAuditEntry({required this.id, required this.entryPoint,
    required this.sourcePath, required this.category, required this.risk,
    required this.status, required this.scenario, this.evidence = const []});
}
```

Dodaj wpis dla każdej wykrytej klasy. Początkowy status to `unverified`. Scenariusz jest konkretny, np. dla `HeatInputScreen`: `12 V, 100 A, 100 mm/min, GTAW daje 0,432 kJ/mm`.

- [ ] **Krok 4: Potwierdź zieloną fazę**

Uruchom: `flutter test --no-pub test/audit/module_manifest_test.dart`  
Oczekiwane: PASS i identyczne zbiory ekranów.

- [ ] **Krok 5: Commit**

```text
git add tool/audit/module_manifest.dart test/audit/module_manifest_test.dart
git commit -m "test: zinwentaryzuj wszystkie moduly aplikacji"
```

### Task 2: Referencyjne obliczenia monterskie

**Pliki:**
- Utwórz: `test/audit/fitter_calculations_audit_test.dart`
- Modyfikuj po czerwonym teście: `lib/services/cut_calculator.dart`, `lib/services/prefab_engine.dart`, `lib/services/unit_parser.dart`, `lib/services/scan_to_project.dart`, `lib/services/saddle_template.dart`, `lib/services/bar_nesting.dart`, `lib/data/pipe_schedules.dart` albo `lib/data/elbow_takeouts.dart` — wyłącznie plik zawierający symbol wskazany przez czerwony test
- Modyfikuj: `tool/audit/module_manifest.dart`

**Interfejsy:**
- Konsumuje: `CutCalculator`, `PrefabEngine`, `UnitParser`, `planFromScan`, take-outy i schedule.
- Dostarcza: dowody dla kategorii `fitter` i `project`.

- [ ] **Krok 1: Dodaj po jednym teście dla każdego zachowania**

Obowiązkowe przykłady:

- `1 in = 25.4 mm`, `1 1/2 in = 38.1 mm`;
- kolano 90° LR DN100 ma take-out `152 mm`;
- `1200 - 152 - 152 = 896 mm` dla odcinka między kolanami;
- kolano–kołnierz nie daje CUT przed potwierdzeniem referencji;
- DN100 Sch40 daje OD `114.3 mm` i ściankę `6.02 mm`;
- nieznany schedule pozostawia grubość pustą;
- suma cięć i rzazów nie przekracza długości pręta;
- saddle jest symetryczny, skończony i nieujemny;
- rolling offset `300/400 mm` daje `500 mm`;
- spadek `1%` na `10 m` daje `100 mm`.

- [ ] **Krok 2: Uruchom test i potwierdź rzeczywiste porażki**

Uruchom: `flutter test --no-pub test/audit/fitter_calculations_audit_test.dart`  
Oczekiwane: każda niezgodność wskazuje oczekiwany i otrzymany wynik.

- [ ] **Krok 3: Napraw wyłącznie potwierdzone błędy**

Dla każdej porażki zachowaj czerwony test, popraw najmniejszą odpowiedzialną funkcję, uruchom pojedynczy test i zaktualizuj status manifestu ze ścieżką dowodu.

- [ ] **Krok 4: Uruchom regresję monterską**

Uruchom: `flutter test --no-pub test/cut_calculator_test.dart test/services/prefab_engine_test.dart test/services/unit_parser_test.dart test/services/scan_to_project_test.dart test/services/saddle_template_test.dart`  
Oczekiwane: PASS.

- [ ] **Krok 5: Commit**

```text
git add test/audit/fitter_calculations_audit_test.dart tool/audit/module_manifest.dart lib/services lib/data
git commit -m "test: zweryfikuj obliczenia monterskie"
```

### Task 3: Referencyjne obliczenia spawalnicze

**Pliki:**
- Utwórz: `test/audit/welder_calculations_audit_test.dart`
- Modyfikuj po czerwonym teście: `lib/services/orbital_tig.dart`, `lib/utils/rod_optimizer.dart`, `lib/data/tungsten.dart` lub `lib/modules/welder_tandem/tandem_calc.dart` — wyłącznie plik zawierający testowaną funkcję
- Modyfikuj: `tool/audit/module_manifest.dart`

**Interfejsy:**
- Konsumuje: heat input, orbital TIG, tandem TIG, tungsten i rod optimizer.
- Dostarcza: dowody dla kategorii `welder`.

- [ ] **Krok 1: Dodaj referencyjne testy**

- GTAW: `12 × 100 × 60 / (100 × 1000) × 0.60 = 0.432 kJ/mm`;
- zerowa i ujemna prędkość przesuwu są odrzucane;
- orbital TIG zwraca cztery skończone dodatnie poziomy;
- granice doboru wolframu nie mają przerw;
- tandem TIG nie zamienia lead/trail;
- optymalizator elektrod zachowuje długość i nie zwraca ujemnej reszty;
- hydrotest odrzuca wejście poza zakresem ekranu;
- passivation i heat tint oznaczają poradę nienormatywną.

- [ ] **Krok 2: Potwierdź czerwone testy**

Uruchom: `flutter test --no-pub test/audit/welder_calculations_audit_test.dart`.

- [ ] **Krok 3: Popraw minimalną logikę**

Jeżeli wzór istnieje tylko w widżecie, utrwal zachowanie testem widżetowym, następnie wydziel jedną czystą funkcję i zachowaj test zielony.

- [ ] **Krok 4: Uruchom regresję spawalniczą**

Uruchom: `flutter test --no-pub test/orbital_tig_test.dart test/tungsten_test.dart test/heat_tint_test.dart test/welder_journey_test.dart test/widgets/wpqr_chip_test.dart`  
Oczekiwane: PASS.

- [ ] **Krok 5: Commit**

```text
git add test/audit/welder_calculations_audit_test.dart tool/audit/module_manifest.dart lib/services lib/utils lib/data lib/modules/welder_tandem
git commit -m "test: zweryfikuj obliczenia spawalnicze"
```

### Task 4: Integralność danych, migracje i eksporty

**Pliki:**
- Utwórz: `test/audit/data_integrity_audit_test.dart`
- Modyfikuj po czerwonym teście: `lib/database/project_dao.dart`, `lib/database/segment_dao.dart`, `lib/database/weld_param_dao.dart`, `lib/data/app_database.dart`, `lib/services/weld_journal_export.dart` albo `lib/services/iso_pdf_export.dart` — zgodnie z symbolem wskazanym przez czerwony test
- Modyfikuj: `tool/audit/module_manifest.dart`

**Interfejsy:**
- Konsumuje: `ProjectDao`, `SegmentDao`, `WeldParamDao`, `WelderIdentityService`, eksporty CSV/PDF.
- Dostarcza: dowód braku utraty danych.

- [ ] **Krok 1: Dodaj testy na tymczasowej bazie**

Sprawdź utworzenie i edycję projektu/segmentu po ponownym otwarciu bazy; kaskadowe usunięcie tylko danych projektu; zachowanie pól parametru; odczyt `user_profile_v1`; zgodność filtrowanego CSV/PDF; jedno źródło CUT; rollback niepełnej transakcji; idempotentną migrację.

- [ ] **Krok 2: Potwierdź czerwone testy**

Uruchom: `flutter test --no-pub test/audit/data_integrity_audit_test.dart`.

- [ ] **Krok 3: Napraw transakcyjnie**

Nie zmieniaj schematu bez testu migracji. Nie kasuj bazy. Każda poprawka zachowuje starsze dane.

- [ ] **Krok 4: Uruchom regresję danych**

Uruchom: `flutter test --no-pub test/segment_dao_update_test.dart test/heat_photo_dao_test.dart test/services/weld_journal_export_test.dart test/services/welder_identity_test.dart`  
Oczekiwane: PASS.

- [ ] **Krok 5: Commit**

```text
git add test/audit/data_integrity_audit_test.dart tool/audit/module_manifest.dart lib/database lib/data lib/services
git commit -m "test: zabezpiecz dane i eksporty"
```

### Task 5: Smoke test wszystkich ekranów

**Pliki:**
- Utwórz: `test/audit/module_smoke_test.dart`
- Modyfikuj po czerwonym teście: wyłącznie ekran z potwierdzoną regresją
- Modyfikuj: `tool/audit/module_manifest.dart`

**Interfejsy:**
- Konsumuje: testowe fabryki ekranów dla wpisów manifestu.
- Dostarcza: dowód renderowania i obsługi błędów.

- [ ] **Krok 1: Dodaj testową fabrykę ekranów**

Mapuj `entryPoint` na widżet. Dla ekranów z `projectId` utwórz projekt w bazie testowej. Dla sieci wstrzyknij offline. Nie wywołuj AI, Stripe ani publikacji.

- [ ] **Krok 2: Napisz parametryzowany test**

```dart
for (final entry in moduleManifest) {
  testWidgets('${entry.entryPoint} renderuje stan startowy', (tester) async {
    final screen = await buildAuditedScreen(entry.entryPoint);
    await tester.pumpWidget(testApp(screen));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
```

Dodaj kontrole skali tekstu `1.3`, etykiety głównej akcji, zachowania formularza po błędzie oraz przycisku ponowienia dla sieci.

- [ ] **Krok 3: Uruchom test i napraw regresje**

Uruchom: `flutter test --no-pub test/audit/module_smoke_test.dart`  
Oczekiwane: każdy ekran renderuje stan startowy bez wyjątku.

- [ ] **Krok 4: Uruchom istniejące testy ekranów**

Uruchom: `flutter test --no-pub test/screens test/widget_test.dart test/readout_test.dart`  
Oczekiwane: PASS.

- [ ] **Krok 5: Commit**

```text
git add test/audit/module_smoke_test.dart tool/audit/module_manifest.dart lib/screens lib/widgets
git commit -m "test: sprawdz wszystkie ekrany aplikacji"
```

### Task 6: Raport i kolejka napraw

**Pliki:**
- Utwórz: `tool/audit/render_audit_report.dart`
- Utwórz: `docs/audits/2026-08-30-module-audit.md`
- Modyfikuj: `test/audit/module_manifest_test.dart`

**Interfejsy:**
- Konsumuje: `moduleManifest`.
- Dostarcza: tabelę wszystkich modułów i kolejkę P0–P3.

- [ ] **Krok 1: Napisz czerwony test renderera**

```dart
test('raport końcowy nie zawiera niezweryfikowanych modułów', () {
  final markdown = renderAuditReport(moduleManifest);
  expect(markdown, isNot(contains('unverified')));
});
```

Raport musi zawierać każdy `id`, punkt wejścia, kategorię, ryzyko, status, scenariusz i dowód.

- [ ] **Krok 2: Potwierdź porażkę**

Uruchom: `flutter test --no-pub test/audit/module_manifest_test.dart`  
Oczekiwane: brak renderera lub obecność `unverified`.

- [ ] **Krok 3: Zakończ klasyfikację i wygeneruj raport**

Priorytety: P0 — błędny CUT, utrata danych, obejście potwierdzenia lub pieniądze; P1 — błędny wynik branżowy albo niedziałający zapis/eksport; P2 — skomplikowana obsługa, brak wyjaśnienia, błąd dostępności; P3 — spójność wizualna i nazewnictwo.

Uruchom: `dart run tool/audit/render_audit_report.dart --output docs/audits/2026-08-30-module-audit.md`.

- [ ] **Krok 4: Wykonaj końcową weryfikację**

```text
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

Oczekiwane: analiza bez problemów, wszystkie testy PASS, brak błędów białych znaków.

- [ ] **Krok 5: Porównaj raport z manifestem**

Liczba modułów w raporcie jest równa `moduleManifest.length`, żaden wpis nie ma `unverified`, a każda pozycja P0/P1 wskazuje test reprodukujący problem.

- [ ] **Krok 6: Commit**

```text
git add tool/audit test/audit docs/audits/2026-08-30-module-audit.md
git commit -m "docs: zakoncz audyt wszystkich modulow"
```

## Wynik etapu

Etap kończy się, gdy każdy publiczny moduł ma status i dowód, pełny zestaw testów przechodzi, znane P0/P1 mają testy regresji, a raport wskazuje kolejność napraw. Konto, społeczność, asystent i docelowe odblokowanie skanera otrzymają osobne plany po ustabilizowaniu obecnej bazy.
