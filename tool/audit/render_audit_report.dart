import 'dart:io';

import 'module_manifest.dart';

String _cell(String value) => value
    .replaceAll('|', '&#124;')
    .replaceAll('\r\n', '\n')
    .replaceAll('\n', '<br>');

/// A report of evidence, not a certification of whole-module correctness.
String renderAuditReport(List<ModuleAuditEntry> entries) {
  final out = StringBuffer('''# FitterWelder Pro — AUDYT CZĘŚCIOWY

Data: 2026-08-30. Pełny audyt pozostaje nieukończony.
Raport rozdziela dowody testowe, naprawione usterki i brakującą weryfikację.
Nie usunięto żadnego modułu. Zakres inwentaryzacji: publiczne klasy Screen
w lib/screens oraz lib/modules/*/ui, nie każdy wewnętrzny serwis aplikacji.

## Podsumowanie manifestu

''');
  out.writeln('Moduły: ${entries.length}');
  out.writeln('\n| Status | Liczba |\n|---|---:|');
  for (final status in AuditStatus.values) {
    final count = entries.where((entry) => entry.status == status).length;
    out.writeln('| ${status.name} | $count |');
  }
  out.writeln();
  out.writeln('''
`passed` oznacza wyłącznie zakres wskazanego dowodu, nie certyfikację całego
modułu, wszystkich danych wejściowych ani poprawności branżowej. `unverified`
oznacza brak pełnego dowodu scenariusza, nie potwierdzony błąd. `domainReview`
wymaga rozstrzygnięcia pojęć domenowych. `broken` i `simplify` są zarezerwowane
dla udokumentowanych usterek i problemów obsługi; zerowe liczniki nie dowodzą
ich nieobecności w niesprawdzonych funkcjach.

## Inwentaryzacja i dowody

Tabela zachowuje statusy, scenariusze i dowody źródłowego manifestu bez
podnoszenia statusu na podstawie renderowania. Wspólny smoke test to
`test/audit/module_smoke_test.dart`: 60 ekranów renderowanych offline przy
skali tekstu 1,3 oraz 7 kontroli przekrojowych. Nie zastępuje scenariuszy
biznesowych. Puste pole dowodu niżej oznacza brak dowodu scenariusza, mimo
przejścia renderowania. W Task 6 doprecyzowano wyłącznie opisy, bez zmian
statusów: pipe-slope dotyczy 1%/10 m = 100 mm, elbow-takeout testu danych
(nie wyświetlania), a heat-input, saddle, orbital TIG i tungsten dokładnych
wejść lub próbkowania istniejącego testu. Saddle i orbital TIG sprawdzają
własności wyników, a nie zgodność z zatwierdzonym projektem/WPS.

| ID | Punkt wejścia | Plik | Kategoria | Ryzyko | Status | Scenariusz | Dowód |
|---|---|---|---|---|---|---|---|''');
  for (final entry in entries) {
    final evidence = entry.evidence.isEmpty
        ? 'Brak dowodu scenariusza'
        : entry.evidence.map(_cell).join('<br>');
    out.writeln('| `${_cell(entry.id)}` | ${_cell(entry.entryPoint)} | '
        '${_cell(entry.sourcePath)} | ${entry.category.name} | '
        '${entry.risk.name} | ${entry.status.name} | '
        '${_cell(entry.scenario)} | $evidence |');
  }
  out.writeln();
  out.writeln('''
## Naprawione usterki — nie są otwartym backlogiem

Poniższe naprawy pochodzą z bieżącej gałęzi audytu. Każda ma opis objawu
przed naprawą i regresję; wpisy nie obejmują wszystkich możliwych awarii.

| Naprawa | Objaw przed naprawą → sprawdzony wynik | Dowód testowy |
|---|---|---|
| Ułamki mieszane cali | `1 1/2 in` dawało null → 38,1 mm; mianownik zero odrzucony | test/audit/fitter_calculations_audit_test.dart: `1 in = 25.4 mm, a 1 1/2 in = 38.1 mm`, `ułamek cala z mianownikiem 0 jest odrzucany` |
| Walidacja heat input | Prędkość 0 przechodziła walidację → 0 i -1 odrzucane | test/audit/welder_calculations_audit_test.dart: `heat input rejects travel speed 0`, `heat input rejects travel speed -1` |
| Bilans rzazu | Rzaz dopisywany jako odcinek oraz pomijane cięcie odpadu → 3000+2000+900/6000 mm: 3 cięcia, rzaz 9 mm, użyte 5909 mm, reszta 91 mm | test/audit/welder_calculations_audit_test.dart: `rod optimizer preserves pieces and never returns negative remainder`, `rod optimizer keeps n-1 cuts for fully consumed stock`, `tracked rod plan keeps kerf out of its piece list` |
| Usunięcie projektu i Cofnij | Osobne usuwanie segmentów i niepełne Undo → transakcyjny snapshot/delete/restore projektu, segmentów, zdjęć i numerów wytopów | test/audit/data_integrity_audit_test.dart: `usunięcie projektu atomowo usuwa tylko jego dane zależne`, `błąd ograniczenia cofa niepełne usunięcie projektu`, `snapshot Cofnij odtwarza projekt i wszystkie zależności` |
| Ponowne otwarcie bazy | Singleton oddawał zamknięty uchwyt (`database_closed`) → produkcyjne otwarcie po migracji v3–v5 zachowuje rekordy i seedy | test/audit/data_integrity_audit_test.dart: `migracja v3-v5 zachowuje rekord po restarcie produkcyjnej bazy` |
| Cykl życia projektów | `setState` po zamknięciu ekranu → kontrola mounted przed zmianą stanu i po odczycie | test/audit/module_smoke_test.dart: `ProjectsScreen nie aktualizuje stanu po zamknięciu podczas load`; dodatkowy kontrakt źródłowy kolejności zabezpieczeń |
| Start listy parametrów rur | Odczyt inherited zależności w initState → ich pobranie dopiero w obsługiwanej gałęzi błędu | test/audit/module_smoke_test.dart: `WelderPipeParamsListScreen renderuje przy skali tekstu 1,3` |

DAO delete/restore jest testowane na prawdziwym SQLite z wymuszeniem rollbacku
przez trigger. Podłączenie usunięcia/Cofnij przez ekran sprawdza kontrakt
źródłowy, nie pełna interakcja gestem i SnackBarem. Test migracji uruchamia
produkcyjne onUpgrade v3–v5, a potem zwykłe ponowne otwarcie aktualnej bazy;
nie udowadnia ponownego wykonania callbacku migracji na bazie v5.

## Potwierdzone otwarte usterki

W wykonanym zakresie nie pozostała odtworzona, nienaprawiona usterka z testem
reprodukującym. Nie nadajemy nieznanym zachowaniom etykiety „błąd P0/P1”.
To nie jest zapewnienie, że aplikacja jest wolna od usterek. Ostrzeżenia
blokady SQLite w istniejących testach regresji wymagają osobnej diagnostyki;
sam warning bez potwierdzonej utraty danych nie jest dowodem błędu P0.

## Kolejka brakującej weryfikacji — osobna od usterek

P0–P3 poniżej oznaczają pilność zdobycia dowodu, nie potwierdzoną wagę błędu:
P0 — bezpieczeństwo/CUT; P1 — pozostałe wysokie ryzyko (wyniki, dane,
konto/AI/płatności); P2 — średnie ryzyko obsługi i przepływów; P3 — niższe
ryzyko nawigacji/pomocy. W każdej grupie należy wykonać dokładny scenariusz
z tabeli, dodać niezależne oczekiwania i przypadki błędne, a dopiero potem
zmienić status. Nie kupować ani nie publikować w ramach testu.
''');
  for (var priority = 0; priority <= 3; priority++) {
    out.writeln('### P$priority — weryfikacja\n');
    final pending = entries.where((entry) =>
        entry.status == AuditStatus.unverified &&
        _verificationPriority(entry) == priority);
    if (pending.isEmpty) out.writeln('Brak wpisów w tej grupie.');
    for (final entry in pending) {
      out.writeln('- [unverified] `${entry.id}`: ${_cell(entry.scenario)} '
          '(ryzyko: ${entry.risk.name}).');
    }
    out.writeln();
  }
  out.writeln('### Rozstrzygnięcia domenowe\n');
  for (final entry
      in entries.where((e) => e.status == AuditStatus.domainReview)) {
    out.writeln('- [domainReview] `${entry.id}`: ${_cell(entry.scenario)} '
        'Priorytet weryfikacji P${_verificationPriority(entry)}; bez '
        'automatycznego utożsamiania inside/outside z lead/trail.');
  }
  out.writeln('''

## Granice audytu i dalsza rozbudowa

- Konto i synchronizacja na żywo między urządzeniami pozostają niezweryfikowane;
  lokalny profil oraz test rejestracji nie dowodzą synchronizacji ani auth.
- Społeczność, czat i oferty: testy retry korzystają z kontrolowanych loaderów;
  nie sprawdzono serwera na żywo, moderacji, prywatności ani publikowania.
- Asystent AI, wejście/odpowiedź głosowa i zapis parametrów do profilu po
  potwierdzeniu wymagają osobnej implementacji lub weryfikacji istniejących
  ścieżek. Ten etap nie uruchamiał płatnego AI i nie dodał modułu głosowego.
- ISO: brak walidacji OCR i list CUT na prawdziwych rysunkach referencyjnych.
  Skanera nie odblokowano produkcyjnie; bez tej walidacji nie można obiecać
  bezbłędnej listy cięć. Istniejące testy czystych obliczeń nie zastępują OCR.
- Weld Journal: zgodność aktywnego filtra ekranu z oboma eksportami CSV/PDF
  pozostaje niezweryfikowana; test samego helpera eksportu nie wystarcza.
- Premium renderuje offline, ale zakup, powrót z Checkout i webhook nie są
  pokryte tym audytem. Nie wykonywano realnych operacji pieniężnych.
- Smoke nie jest pełnym audytem dostępności: semantyka obejmuje główne CTA
  trzech formularzy; nie przetestowano każdego kontrolera ani urządzenia.
- Szersze uproszczenie UX, profesjonalny wygląd czatu i instrukcje krok po
  kroku pozostają kolejnym etapem. Ten etap stabilizuje istniejącą bazę.

## Odtworzenie raportu i bramki weryfikacji

```text
dart run tool/audit/render_audit_report.dart --output docs/audits/2026-08-30-module-audit.md
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

Raport jest deterministycznie generowany z manifestu; nie uruchamia testów
ani nie nadaje sobie statusu PASS. Dokładne wyniki końcowego uruchomienia
kontroler zapisuje w raporcie wykonania Task 6. Zielony zestaw testów nie
zamyka brakujących scenariuszy wymienionych powyżej.
''');
  return '${out.toString().trimRight()}\n';
}

int _verificationPriority(ModuleAuditEntry entry) {
  if (entry.risk == AuditRisk.safetyCritical ||
      const {'iso-scanner', 'scan-review', 'cut-list-summary'}
          .contains(entry.id)) {
    return 0;
  }
  return switch (entry.risk) {
    AuditRisk.high => 1,
    AuditRisk.medium => 2,
    AuditRisk.low => 3,
    AuditRisk.safetyCritical => 0,
  };
}

void main(List<String> args) {
  if (args.length != 2 || args.first != '--output') {
    stderr.writeln(
        'Usage: dart run tool/audit/render_audit_report.dart --output <path>');
    exitCode = 64;
    return;
  }
  final file = File(args[1]);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(renderAuditReport(moduleManifest));
  stdout.writeln(
      'Raport częściowy: ${file.path} (${moduleManifest.length} modułów)');
}
