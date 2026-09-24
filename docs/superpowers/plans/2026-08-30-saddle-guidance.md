# Saddle cut — aktualny profil i trasowanie

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Kontynuacja w bieżącej gałęzi roboczej; zachować wcześniejsze niezatwierdzone zmiany kalkulatorów. Nie tworzyć wydania ani usuwać modułów.

**Goal:** Wyeliminować nieaktualny eksport siodła i uprościć trasowanie centralnego połączenia 90°.

**Architecture:** Ekran zachowuje walidowany, niezmienny wynik wraz ze średnicami. Zmiana tekstu wejścia unieważnia cały wynik. Ten sam profil zasila tabelę i schowek. Istniejący CalculationGuide dostarcza instrukcję opcjonalną.

**Tech Stack:** Flutter / Dart; bez nowych pakietów.

**Spec:** ../specs/2026-08-30-profesjonalna-platforma-spolecznosciowa-i-asystent-design.md, sekcje 2, 4, 12.

## Global Constraints

- Nie usuwamy istniejących modułów ani danych użytkownika.
- Wyniki kalkulatorów są pomocą techniczną, nie zamiennikiem zatwierdzonej dokumentacji.
- Każdy etap przechodzi testy, analizę kodu i przegląd zmian.
- Pomoc nie zmienia logiki obliczeń.
- UI PL/EN, obecny motyw aplikacji; bez zmian w osobnym generatorze szablonów PDF.

## Zadanie 1 — spójny wynik i pełny profil

Pliki: lib/screens/saddle_cut_screen.dart, lib/widgets/help_button.dart (tylko kHelpSaddleCut), test/screens/saddle_cut_test.dart.
Interfejs: zachować const SaddleCutScreen({super.key}); wykorzystać CalculationGuide(inputs, steps, caution, hasResult).

- [x] Testy regresji: oblicz 100/60, zmień każde pole, sprawdź brak CopyOnLongPress h_max i wyłączone kopiowanie. Dla każdego pola odrzuć NaN, Infinity, 1e309, 0, -1, 2000.1, abc, pusty tekst. Odrzuć branch >= header. Referencja 2000/1200 daje 200 mm.

```dart
await _calculate(tester, '100', '60');
expect(tester.widget<CopyOnLongPress>(_result).value, '10.0');
await tester.enterText(find.byType(TextField).first, '200');
await tester.pumpAndSettle();
expect(_result, findsNothing);
expect(_copy(tester).onPressed, isNull);
```

- [x] Uruchom testy RED: flutter test --no-pub test/screens/saddle_cut_test.dart --reporter expanded. Potwierdź błąd zachowanego wyniku i NaN.
- [x] Walidator: double.tryParse(trim.replaceAll(',', '.')); odrzuć null, !isFinite, <=0, >2000. Sprawdź branch < header i skończoność wyniku. Listener kontrolerów unieważnia wynik tylko przy zmianie tekstu, nie przy zmianie kursora.
- [x] Przechowaj wynik wraz z wejściem. Generuj profil 0..360 co15°. Odległość na obwodzie to pi * branchOd * deg /360. Po weryfikacji geometrii skorygowano plan: d(alpha)=sqrt(R*R-(r*sin(alpha))^2)-sqrt(R*R-r*r). Zero w90/270, maksimum0/180/360. Referencja100/60: 10/0/10/0/10 mm; obwód188.49556mm. Punkt45°:5.27692569mm, a nie4.72307431mm.
- [x] Zachowaj szybki profil0..90, dodaj rozwijany pełny obwód25punktów (360zamyka0). Eksportuj wszystkie25punktów TSV z wymiarami ze snapshotu, jednostkami, orientacją i ograniczeniami.
- [x] Pokaż jak: OD a nie DN; R=ODgłównej/2, r=ODodgałęzienia/2; podstawienie aktualnego wyniku albo jawny przykład100/60; łuk taśmą, głębokość osiowo od płaszczyzny najdłuższychpunktów. Popraw zgodnie z tym pomoc.
- [x] Pola pionowo na telefonie/powiększonym tekście, tabela przewijana poziomo jeśli potrzebne. Kolory i typografia z Theme.of(context), zachować istniejącą identyfikację.
- [x] GREEN: powtórz testy ekranu; sprawdź25wierszy schowka i symetrie, pomoc oraz PL/EN375px przy skali2 jasny/ciemny.

## Zadanie 2 — odbiór

**Korekta diagnozy, 2026-08-30:** początkowo uznano wzór za poprawny i odwrócono opisy. Niezależne wyprowadzenie oraz przegląd wykazały, że R−sqrt(...) opisuje obniżenie od wierzchu rury głównej, nie osiową głębokość wycięcia od najdłuższych końców w kierunku korpusu. Naprawa błędu obliczeń jest osobną zmianą funkcjonalną, nie zmianą powodowaną samą pomocą. Dla osi głównej x i odgałęzienia z(+ w korpus) zachodzi y=r sin(alpha), z=sqrt(R²−y²), z_min=sqrt(R²−r²), cutback=z−z_min. Parametryzacja walca: https://mathworld.wolfram.com/Cylinder.html; wyprowadzenie przecięcia i punktu odniesienia własne, potwierdzone niezależnym przeglądem. Generator PDF jest osobnym modułem i nie jest objęty tym odbiorem.

Plik: test_screenshots/saddle_shots_test.dart, test renderowania poza domyślną suite.

- [x] Wykorzystaj sposób ładowania fontów i motywu z converter_shots_test.dart. Zapisz podgląd aktualnego ekranu przez matchesGoldenFile do katalogu outputs bieżącego zadania. Obejrzyj obraz.
- [x] flutter analyze --no-pub; flutter test --no-pub; git diff --check.
- [x] Niezależny przegląd: tylko ekran, pomoc siodła, testy i zależność CalculationGuide. Nie nadpisywać wcześniejszych zmian innych modułów.
- [x] Przekaż wyniki i ograniczenia użytkownikowi. Pozostaw zmiany lokalnie bez automatycznego wydania/instalacji.

## Wynik odbioru — 2026-08-30

- 34 testy ekranu siodła; pełna suite: 677/677, exit 0.
- flutter analyze --no-pub: No issues found, exit 0.
- Testy RED odtworzyły pozostawienie starego wyniku, akceptację NaN i błędny punkt45° (4.7 zamiast5.3). Po poprawce przechodzą.
- Kontrola PL/EN, jasny/ciemny motyw,375px i skala2 oraz poziomy812×375. Dwa podglądy rzeczywistego ekranu Fluttera obejrzane.
- Niezależny przegląd po korekcie: brak blokujących uwag. git diff --check: bez błędów białych znaków.
- Zmiany pozostawione w bieżącej gałęzi roboczej. Bez commit/push/build/instalacji. Wcześniejsze zmiany innych kalkulatorów zachowane.
- Osobny generator szablonów PDF (SaddleTemplate) nie jest objęty tym odbiorem; jego własny wzór i kierunek konturu wymagają kolejnej kontroli. Nie należy traktować testów tego ekranu jako zatwierdzenia szablonów PDF ani wszystkich pozostałych modułów.
