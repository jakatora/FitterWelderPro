# QA-COCKPIT — FitterWelderPro

## Aktualna weryfikacja — 2026-11-02

Kod aplikacji: `f0c8b8376d3dd6b0c613d504470bde6a93b7f641`.

- Pełne `flutter test --no-pub --reporter json`: **10 267 testów zaliczonych, 660 zestawów, 0 błędów**, zakończenie `success: true`, 298,083 s.
- Pełne `flutter analyze --no-pub`: **No issues found**, 35,0 s. Log: `full-analyze-f0c8b83.log` w katalogu artefaktów poniżej.
- Przebieg obejmuje poprawki głosu i lokalnych obliczeń, zachowania kontekstu po błędach AI, treści pomocy oraz trafności wyszukiwania offline i rozróżnienia DN/NPS/NPSH.
- Raport maszynowy: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/full-suite-f0c8b83-summary.json`; surowy zapis: `full-suite-f0c8b83.jsonl` w tym samym katalogu.
- Testy uruchomiono na Windows, z atrapami wywołań platformowych i sieciowych. Wynik nie dowodzi poprawności dowolnej odpowiedzi AI, aktualności całej wiedzy technicznej ani działania mikrofonu na fizycznym telefonie.
- APK **0.5.16 (2035)**: automatyczny test na fizycznym Pixelu 8 / Android 15 / PL zakończył się powodzeniem (`matrix-3vlr480ryihjb`, jedna próba, 134 s). W logu brak FATAL EXCEPTION, błędów Fluttera i ANR aplikacji. Obejrzane kadry obejmują listę projektów, pomoc formularza i walidację brakującej średnicy. Nie potwierdza to rozmowy AI ani mikrofonu. [Wynik Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/6021048068351313166).
- Osobny **build diagnostyczny** oparty na 0.5.16 przeszedł test rzeczywistej odpowiedzi AI na fizycznym Pixelu 8: jedno żądanie HTTP200, odpowiedź widoczna na ekranie i sprzątanie HTTP200/ok; jeden testcase, zero błędów i pominięć. [Test Lab](https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/7979772547584698356). Kod testu jest na osobnej gałęzi `qa/device-assistant-0516`; wynik nie obejmuje mikrofonu, wielu tur ani zachowania rozmowy w release AOT/R8.
- iOS **0.5.15 (1082)**: ostatnia potwierdzona kontrola Apple z 2026-11-01T23:54:24Z wykazała `VALID`, wewnętrznie `IN_BETA_TESTING`, zewnętrznie `READY_FOR_BETA_SUBMISSION`. Zgłoszenie zewnętrznej bety odrzucono limitem zgłoszeń (422). Ta binarka nie zawiera późniejszych zmian kontekstu/pomocy/offline.
- Osobny [raport rzeczywistych zapytań backendu](docs/audits/2026-11-02-live-assistant.md) opisuje trzy odpowiedzi AI, ich ograniczenia i kolejne poprawki wyszukiwania.

Poniższy raport z 2026-06-16 jest archiwalny. Jego liczby, lista brakujących testów i wersje narzędzi opisują ówczesny stan; nie stanowią oceny aktualnego kodu.

---


**Data audytu:** 2026-06-16
**Cel biznesowy:** mniej błędów → lepsze oceny w sklepach i niższy churn → wyższy przychód.
**Zakres tej tury:** wyłącznie DIAGNOZA (`flutter analyze` + `flutter test`). Kod aplikacji NIE był zmieniany.

---

## 1. Wynik na zielono (TL;DR)

| Kontrola | Wynik |
|---|---|
| `flutter analyze` | ✅ **No issues found** (44.9 s) |
| `flutter test` | ✅ **All tests passed** — 171 testów w 16 plikach |
| `print(` w `lib/` | ✅ 0 (brak logów debugowych w produkcji) |
| Realne znaczniki TODO/FIXME/HACK | ✅ 0 (jedyny trafiony „XXXX" to fallback nicku) |
| Wersja toolchain | Flutter 3.38.7 (stable) • Dart 3.10.7 |

**Wniosek:** baza jest zdrowa statycznie — żadnych błędów ani ostrzeżeń kompilatora/lintera, pełna logika obliczeniowa (kalkulatory, parsery, katalogi) przetestowana. To dobra wiadomość dla ocen: rdzeń liczący (cut list, ISO parser, prefab, harmonogramy rur) ma siatkę bezpieczeństwa.

**Ale** — przy 146 plikach w `lib/` (49 ekranów, 25 serwisów) testy pokrywają głównie czystą logikę. Najbardziej „crashogenne" warstwy (sieć, PDF, AI, paywall) nie mają testów. Tam siedzi realne ryzyko 1-gwiazdkowych recenzji. Poniżej priorytety napraw nakierowane na stabilność, oceny i konwersję.

---

## 2. Sygnały do uwagi (z analizy statycznej, nie-blokujące)

Brak błędów/ostrzeżeń, ale w kodzie są celowo wyciszone linty — każdy to potencjalny dług:

| Plik | Wyciszenie | Ryzyko |
|---|---|---|
| `lib/screens/iso_notebook_screen.dart:4314, 4353` | `// ignore: deprecated_member_use` → `SemanticsService.announce(...)` | **Średnie** — deprecated API. Przy kolejnym podbiciu Fluttera może zniknąć i zerwać build / dostępność. |
| `lib/screens/material_list_screen.dart:71` | `// ignore: unused_field` | Niskie — martwy kod, do usunięcia. |
| `lib/services/iso_parser.dart:75` | `// ignore: text_direction_code_point_in_literal` | Niskie — celowe (obsługa znaków RTL/Unicode w parserze). Zostawić. |
| 9 plików (ekrany + `help_entries.dart`) | `// ignore_for_file: prefer_const_constructors` | Niskie — kosmetyka/mikro-perf. Wyłącza lint dla całego pliku. |

---

## 3. Luki w pokryciu testami (główne źródło ryzyka)

171 testów to dużo, ale rozkładają się nierówno. **Przetestowane** (pure logic, świetnie): `cut_calculator`, `iso_parser`, `prefab_engine`, `unit_parser`, `bar_nesting`, `cut_packing_service`, `orbital_tig`, `tungsten`, `pipe_schedules`, `sanitary_tube`, `support_spacing`, `heat_tint`, `elbow_takeouts`, `premium_status`, `welder_identity`, `rolling_offset` + smoke test home menu.

**Serwisy BEZ testów (15):**
`ai_chat_service`, `api_client`, `auth_service`, `backend_service`, `chat_service`, `component_classification`, `flange_catalog`, `help_search`, `iso_pdf_export`, `iso_scanner_ai`, `jobs_service`, `material_catalog`, `material_list_builder`, `pdf_export_service`, `saddle_template`.

**Ekrany:** 49 ekranów, a testy widgetów obejmują tylko 2 (`widget_test` smoke + `rolling_offset`). Ścieżki sieciowe, eksport PDF, AI-scan i paywall nie są weryfikowane automatycznie.

---

## 4. Propozycje napraw — priorytetyzowane pod przychód

> Kolejność = wpływ na oceny/konwersję × prawdopodobieństwo awarii. To rekomendacje; wdrożenie w osobnej turze (to zadanie = diagnoza).

### P0 — Stabilność warstwy sieciowej (największy wpływ na oceny)
Awarie sieci to najczęstsza przyczyna 1★. Dziś `api_client`, `backend_service`, `chat_service`, `ai_chat_service` nie mają żadnych testów.
- **Akcja:** dodać testy jednostkowe na: brak sieci / timeout / HTTP 500 / niepoprawny JSON → aplikacja pokazuje komunikat, **nie crashuje**. Mockować `http.Client`.
- **Dlaczego płaci:** monter często pracuje offline (hala, plac budowy). Czytelny fallback zamiast wysypki = utrzymany użytkownik zamiast odinstalowania + złej recenzji.

### P0 — Eksport PDF (paying users)
`pdf_export_service` i `iso_pdf_export` bez testów. Eksport to funkcja, dla której monter płaci (raporty WPQR, listy cięć, izometryki).
- **Akcja:** test generujący PDF dla pustych / skrajnych danych (0 pozycji, bardzo długie nazwy, znaki Unicode/PL) — ma nie rzucać wyjątku.
- **Dlaczego płaci:** crash przy eksporcie = bezpośrednia utrata zaufania klienta premium → zwrot/churn.

### P1 — Usunąć deprecated API zanim zerwie build
`SemanticsService.announce` (2×) jest deprecated.
- **Akcja:** zastąpić rekomendowanym odpowiednikiem (np. `SemanticsService.announce` → kanał `Semantics`/`announce` wg aktualnego API Fluttera) i usunąć `// ignore`.
- **Dlaczego płaci:** chroni przed nagłym zerwaniem buildu iOS na Codemagic przy następnym SDK bump → brak przestoju w wydaniach.

### P1 — Podbicie krytycznych zależności (zgodność z Androidem 14/15)
`flutter analyze` zgłosił **43 paczki z nowszymi, niekompatybilnymi wersjami**. Krytyczne pod stabilność na nowych telefonach:
- `file_picker 8.0.7 → 11.0.2` (major) — poprawki photo-picker / scoped storage na Android 14/15.
- `share_plus 9.0.0 → 13.1.0` (major) — naprawy crashy share-sheet.
- `sqflite` / `sqflite_common_ffi` — drobne bump (stabilność bazy lokalnej = dane montera).
- `flutter_lints 5 → 6` — nowsze reguły wyłapią więcej zanim trafi do użytkownika.
- **Akcja:** podbić w osobnej gałęzi + przejść pełny `flutter test` i smoke na realnym urządzeniu (major bumpy mają breaking changes).
- **Dlaczego płaci:** crash na nowym Samsungu/Pixelu = recenzja „nie działa na moim telefonie". Aktualne pluginy = mniej takich raportów.

### P2 — Test ścieżki płatności (bezpośrednio konwersja/przychód)
Logika `premium_status` jest przetestowana, ale **ekran paywall i flow zakup/restore — nie**.
- **Akcja:** test widgetu `premium_screen`: poprawne renderowanie planów, stan po zakupie, działanie „Przywróć zakupy".
- **Dlaczego płaci:** zepsuty paywall = 100% utraconej sprzedaży na tej ścieżce. To najwyższy ROI z testów.

### P3 — Higiena (niski priorytet, szybkie)
- Usunąć `unused_field` w `material_list_screen.dart:71` (martwy kod).
- Rozważyć włączenie `prefer_const_constructors` (usunąć `ignore_for_file` z 9 plików, dodać `const`) — mikro-optymalizacja renderu + spójność.

---

## 5. Komendy do odtworzenia audytu

```bash
flutter analyze        # oczekiwane: No issues found
flutter test           # oczekiwane: All tests passed (171)
flutter pub outdated   # szczegóły przeterminowanych 43 paczek
```

---

### Podsumowanie dla właściciela
Aplikacja przechodzi diagnozę **bez błędów i bez ostrzeżeń**, a cały rdzeń obliczeniowy jest objęty testami — to fundament dobrych ocen. Największe ukryte ryzyko (a więc i największy potencjał wzrostu ocen/przychodu) leży **poza** logiką liczącą: w warstwie sieciowej, eksporcie PDF i paywall, które dziś nie mają automatycznych testów, oraz w przeterminowanych pluginach mogących crashować na najnowszych Androidach. Rekomendacje P0–P2 adresują dokładnie te punkty.
