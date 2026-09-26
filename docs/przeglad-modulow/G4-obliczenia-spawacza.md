# G4 — Obliczenia spawacza: przegląd modułów

Data: 2026-09-26 · Gałąź: `fix/audyt-2026-08-29` (HEAD `40f254e`, wydanie 0.3.0+17)
Perspektywa: inspektor spawalniczy (IWI/CWI), spawacz rur TIG/MMA (CS, SS, P91, orbital food/pharma) i inżynier Flutter.
Zakres: heat-input, welder-tools (Gaz / O₂ Purge / Timer / Ciśnienie), welder-pipes (AMP / Gazy / Startowe / Moje parametry), welder-tanks, tungsten, orbital-tig, hydrotest (+ eksport PDF), bolt-torque.

Metoda: przeczytany kod domeny i ekranów, ręczne przeliczenia w skrypcie (Python), sprawdzenie wartości w źródłach (lista na końcu). Uruchomione testy grupy — **325/325 zielonych** (`flutter test --no-pub`, 25 plików: `test/domain/{welding,pressure_test,bolting,welder_pipes}`, `test/screens/{heat_input_*,hydrotest_*,bolt_torque_values,tungsten_screen,weld_timer_screen,welder_pipes_*,welder_tools_fixes}`, `test/services/{hydrotest_*,weld_timer_service,material_catalog}`, `orbital_tig_test`, `tungsten_test`, `heat_tint_test`, `welder_journey_test`, `audit/welder_calculations_audit_test`).

Oznaczenia: **[potwierdzone]** — odtworzone z kodu, przeliczone lub sprawdzone w źródle; **[opinia]** — ocena praktyka, bez twardego źródła. Rzeczy naprawione 24–25.09 (gaz 50 L × 200 bar, Seferian z grubością, heat input EN/ASME, ST/S, B1.1/8UN, jedna tabela wolframu, D18.2) nie są powtarzane — sprawdziłem je i liczą dobrze.

---

## heat-input / zakładka „Heat input” — „Heat input i CE”

- **Cel i dla kogo:** spawacz i inspektor na stanowisku: czy parametry łuku mieszczą się w zakresie energii liniowej z WPS.
- **Co zawiera:** proces (SMAW/GMAW/FCAW-G/FCAW-S/GTAW/SAW), U, I, v [mm/min], konwencja EN 1011-1 (z η) albo ASME IX QW-409.1(a) (bez η), η z WPS (opcjonalnie), zakres min–max z WPS, „Wybierz WPS” z Biblioteki WPS, kopiowanie i udostępnianie. Pliki: `lib/screens/heat_input_screen.dart`, `lib/domain/welding/heat_input.dart`.
- **Stan:** działa.
  Przeliczenia ręczne — zgodne z aplikacją:
  - MMA 22 V / 110 A / 200 mm/min: EN (k = 0,8) = 0,581 kJ/mm; ASME = 0,726 kJ/mm.
  - TIG 12 V / 100 A / 90 mm/min: EN (k = 0,6) = 0,480; ASME = 0,800 kJ/mm (tak jak w komentarzu domeny).
  - TIG 12 V / 100 A / 100 mm/min: 0,432 kJ/mm (test audytu tego pilnuje).
  - Współczynniki k zgodne z EN 1011-1 tab. 1 / ISO/TR 17671-1 (SAW 1,0; MMA/MAG/FCAW 0,8; TIG 0,6).
- **Błędy potwierdzone:**
  - `heat_input_screen.dart:419-420` — dla danych, których nie da się policzyć (np. η z WPS = „1,2” albo „abc”), getter zwraca `?? 0`, więc karta wyniku pokazuje dużą liczbę **„0.00 kJ/mm”**, a „Kopiuj wynik” kopiuje „0.00 kJ/mm (…)”. Pod spodem stoi komunikat o błędnym η, ale sama liczba wygląda jak wynik. Oczekiwane: „—” i zablokowane kopiowanie. [potwierdzone, kod]
- **Problemy UX w terenie:**
  - Wynik jest dopiero pod trzema kartami (parametry, norma, zakres WPS). Na 360 dp w rękawicy trzeba przewijać, żeby zobaczyć liczbę po każdej zmianie prądu. [opinia]
  - Brak skrótu „zmierzyłem długość i czas”: spawacz zwykle ma stoper i miarkę, a nie prędkość w mm/min. Timer z welder-tools (tryb „Spawanie”) nie przekazuje czasu jarzenia do heat input. [potwierdzone — brak takiej ścieżki w kodzie]
- **Brakujące funkcje:**
  - Wejście v = L / t (długość ściegu [mm] + czas jarzenia [s]), z możliwością wzięcia czasu ze stopera timera.
  - Jednostki WPS amerykańskich: **J/in i kJ/in** (ASME WPS zwykle podaje J/in). Dziś spawacz przelicza ręcznie (1 kJ/mm = 25,4 kJ/in).
  - ASME IX QW-409.1(b)/(c) — energia/moc chwilowa dla źródeł z przebiegiem sterowanym (pulsy, CMT, STT). Dziś sam wzór (a) daje zaniżony/niewłaściwy wynik dla pulsu.
  - Zapis wyniku do dziennika spoin (spoina / ścieg / U-I-v-HI) — inspektor potrzebuje śladu, nie zrzutu z WhatsAppa.
- **Testy:** dobrze pokryte: `heat_input_test.dart` (EN/ASME, walidacja), `heat_input_fixes_test`, `heat_input_wps_pick_test` (zakres i norma z WPS), audyt 0,43 kJ/mm. Brak: testu, że niepoprawne η nie wyświetla i nie kopiuje „0.00”.
- **Propozycje:**
  - [P2][S] Gdy `heatInputKJPerMm` = null: pokazuj „—”, szary kolor, wyłącz „Kopiuj wynik” i udostępnianie HI.
  - [P2][M] Pole „długość ściegu + czas” (lub przycisk „z timera”) liczące v.
  - [P2][S] Przełącznik jednostek kJ/mm ↔ kJ/in ↔ J/in dla wyniku i zakresu WPS.
  - [P3][M] QW-409.1(b)/(c) dla procesów pulsowych (energia z licznika spawarki / moc chwilowa).

## heat-input / zakładka „Preheat / CE”

- **Cel i dla kogo:** spawacz / technolog przed spawaniem: jaka minimalna temperatura podgrzewania; inspektor: czy temperatura z WPS nie jest poniżej minimum kodowego.
- **Co zawiera:** katalog gatunków (A106 B … Monel 400) z P-No, skład chemiczny (C, Mn, Cr, Mo, V, Ni, Cu), grubość, CE IIW, trzy nazwane źródła: minimum kodowe ASME B31.3-2012 Tab. 330.1.1, Seferian, reguła CE (nienormatywna), typowa max temp. międzyściegowa, wybór DN/SCH. Pliki: `heat_input_screen.dart`, `lib/domain/welding/preheat.dart`, `lib/services/material_catalog.dart`.
- **Stan:** działa, ale z błędami opisanymi niżej.
  Przeliczenia ręczne — zgodne z aplikacją:
  - C 0,20 / Mn 1,00, t = 15: CE = 0,367; Seferian [C]c = 0,311, [C] = 0,334, Tp = 102 °C.
  - P22 (katalog), t = 15: CE = 0,845; Seferian 187 °C.
  - Minimum kodowe B31.3-2012: P-No 1 10/80 °C, P-No 3 10/80 °C, P-No 4 120 °C, P-No 5A/5B/5C 175 °C, P-No 6 i 15E 200 °C — **zgodne z tabelą wydania 2012** (kopia tabeli na pdfcoffee).
- **Błędy potwierdzone:**
  1. **Seferian i reguła CE są pokazywane dla P91 (P-No 15E).** Wykrywanie nierdzewnej to wyłącznie Cr ≥ 10,5 % (`preheat.dart:174`), a P91 ma 9 % Cr. Wejście: gatunek „P91 / T91”, t = 15 mm → CE = 2,235 (czerwone „CE ≥ 0.45 — wysoka skłonność…”), **Seferian = 365 °C**, reguła CE 250 °C. Oczekiwane: metody z CE ukryte albo wyszarzone dla P-No 4/5A/5B/5C/15E (tak jak dla nierdzewnej). 365 °C jest powyżej typowej max międzyściegowej P91 z tego samego ekranu. Karta „Stale Cr-Mo: metody z CE nie są do nich przeznaczone” jest, ale na dole, pod dużą liczbą. [potwierdzone, przeliczone]
  2. **Minimum kodowe z wydania zastąpionego.** Ekran liczy wg B31.3-**2012**. Od wydania 2014 B31.3 ujednolicił podgrzewanie z B31.1 (Becht, „Substantive changes to 2014 edition”). W obecnych wartościach (B31.1 §131.4 / B31.3 ≥ 2014) m.in. P-No 5A/5B: 200 °C, gdy Rm > 414 MPa albo Cr > 6 % i t > 13 mm, w pozostałych przypadkach 150 °C. Przykład: P9 (5B, 9Cr), t = 20 mm → aplikacja 175 °C, wydanie aktualne 200 °C, czyli aplikacja pokazuje **mniej**. Etykieta „-2012” jest uczciwa, ale spawacz na projekcie z B31.3-2022 dostaje nieaktualne „minimum”. [potwierdzone co do zmiany wydania; dokładne wartości aktualnej tabeli do sprawdzenia w oryginale normy]
  3. `b313MinPreheatC` jest wołane bez `smtsMpa` (`heat_input_screen.dart` `_preheatView`), więc gałąź „Rm > 490 MPa → 80 °C” nigdy nie działa. Dla gatunków z katalogu to dziś bez skutków (A516-70 ma Rm min 485 MPa), ale przy dodaniu np. X65 albo S355 minimum wyjdzie za niskie. [potwierdzone, kod]
  4. Wybór DN/SCH pokazuje ściankę w podpowiedzi (`heat_input_screen.dart:220`), ale **nie wpisuje jej do pola „Grubość”**, od którego zależą Seferian i minimum kodowe. Spawacz wybiera DN200 Sch 80 (12,7 mm), a liczy się dalej domyślne 15 mm. [potwierdzone, kod]
- **Problemy UX w terenie:**
  - Czip gatunku nadpisuje skład i pokazuje „Cofnij” — dobrze. Ale nie ma pola „CE z atestu 3.1”: inspektor ma CE z atestu i musi odtwarzać skład.
  - Tooltipy na czipach (praktyka WPS) wymagają długiego przytrzymania, w rękawicy praktycznie niedostępne. [opinia]
- **Brakujące funkcje:**
  - EN 1011-2 zał. C metoda A (CE + wodór H5/H10/H15 + energia liniowa + grubość łączna) albo przynajmniej CET (metoda B). Ekran sam je wymienia jako „normatywne”, a ich nie liczy. W Europie to podstawowe narzędzie technologa.
  - Wybór wydania kodu (B31.3-2012 / B31.3 ≥ 2014 = B31.1 §131.4) i pole Rm.
  - Grubość łączna (combined thickness) dla złączy teowych/króćców.
  - Max temp. międzyściegowa z katalogu gatunku (dziś zawsze „250 °C”, `heat_input_screen.dart:1396`, a katalog P91 mówi 250–300 °C, a nierdzewne < 175 °C).
- **Testy:** `preheat_test.dart` (Seferian, CE, B31.3-2012, NaN), `welder_journey_test` (niskowęglowa bez NaN), `heat_input_fixes_test`. Brak: testu „P-No 15E / 5A nie pokazuje Seferiana jako wyniku”, testu „DN/SCH ustawia grubość”, testu gałęzi Rm > 490.
- **Propozycje:**
  - [P1][S] Ukryć albo wyszarzyć Seferiana i regułę CE dla P-No 4/5A/5B/5C/15E (albo Cr > 3 % / Mo > 0,6 %) i pokazać zamiast nich „minimum kodowe + WPS”.
  - [P2][M] Tabela B31.3 ≥ 2014 (= B31.1 Tab. 131.4.1) z wyborem wydania. Domyślnie wydanie aktualne, 2012 jako opcja.
  - [P2][S] DN/SCH → wpisz ściankę do „Grubość” (z Cofnij).
  - [P2][L] EN 1011-2 zał. C (metoda A/B) z wodorem i HI z pierwszej zakładki.
  - [P3][S] Max międzyściegowa z katalogu gatunku zamiast stałego 250 °C.

---

## welder-tools / zakładka „Gaz” — „Gaz, formowanie i timer”

- **Cel i dla kogo:** brygadzista / spawacz: ile gazu i butli zamówić na pakiet spoin.
- **Co zawiera:** liczba spoin, czas na spoinę, Q palnika, pre/post-flow, purge (Q, czas), butla (pojemność wodna, ciśnienie, rezerwa). Pliki: `welder_tools_screen.dart` (`_GasConsumptionTab`), `lib/domain/welding/shielding_gas.dart`.
- **Stan:** działa.
  Przeliczenie: 20 spoin × 5 min × 10 L/min = 1000 L + pre/post 20 × 15 s × 10 L/min = 50 L → 1050 L; butla 50 L × 200 bar = 10 000 L → 0,105 → „1 szt.” (zgodne z testem).
- **Błędy potwierdzone:** brak błędów liczbowych.
- **Problemy UX w terenie:**
  - Gdy wpisze się Q purge, a czas purge zostanie pusty, purge po cichu wynosi 0 L (`shielding_gas.dart` — warunek `purgeLpm > 0 && purgeMinutes > 0`). Brak podpowiedzi „podaj czas purge”. [potwierdzone, kod]
  - Czas purge w minutach, a zakładka O₂ Purge liczy go w sekundach („2m 18s”) — nie da się przenieść wyniku jednym dotknięciem.
- **Brakujące funkcje:** typowe butle PL (20 L/150 bar; 50 L/300 bar; wiązki 12 × 50 L) jako czipy; czas purge z zakładki O₂; mieszanki (Ar/CO₂ inna ściśliwość); podział „gaz palnika / gaz formujący”, gdy formuje się N₂ albo formiergazem z osobnej butli.
- **Testy:** `shielding_gas_purge_test.dart`, `welder_tools_fixes_test` (1050 L → 0,1 butli). Brak: testu „Q purge bez czasu”.
- **Propozycje:** [P3][S] komunikat, gdy podano tylko jedno z pary Q/czas purge; [P3][S] czipy typowych butli; [P3][M] „weź czas z O₂ Purge”.

## welder-tools / zakładka „O₂ Purge”

- **Cel i dla kogo:** spawacz SS/duplex/Ti: jak długo przedmuchiwać odcinek do docelowego ppm O₂.
- **Co zawiera:** OD, t, długość, Q, C₀ (210 000 ppm), cel ppm; model pełnego wymieszania C = C₀·e^(−Qt/V). Pliki: `_O2PurgeTab`, `lib/domain/welding/purge.dart`.
- **Stan:** działa.
  Przeliczenie: 60,3 × 2, L = 1000 mm, Q = 10 L/min, cel 20 ppm → V = 2,489 L, N = ln(210 000/20) = 9,26, t = 138 s („2m 18s”). Zgodne.
- **Błędy potwierdzone:** brak.
- **Problemy UX w terenie:**
  - Po obliczeniu nie ma przycisku „Start timera” z tym czasem. Zakładka Timer obok przyjmuje tylko sekundy całkowite, więc trzeba przepisać 138 z pamięci. [potwierdzone]
  - Oceny „Cel < 20 ppm (standard pharma)”, „< 100 ppm (standard przemysłowy)” (`welder_tools_screen.dart:279`) brzmią jak normy. Takich progów nie ma ani w ASME BPE, ani w AWS D18.1/D18.2. D18.2 wiąże próbki barw z ppm, a akceptację ustala specyfikacja. [opinia / terminologia]
- **Brakujące funkcje:** objętość korków/pęcherzy purge (dam) zamiast całej rury; dodatek na węże; model „wypierania” (argon cięższy od powietrza, wpust dołem) jako alternatywa dla pesymistycznego pełnego wymieszania; cele per materiał (Ti, duplex, SS) z jednego źródła.
- **Testy:** `shielding_gas_purge_test.dart`, `welder_tools_fixes_test` (cel 0 / cel ≥ C₀). Pokrycie dobre.
- **Propozycje:** [P2][S] „Start timera purge” z wynikiem (przez `WeldTimerService`); [P3][S] przeredagować oceny na „przykładowy cel — wiąże specyfikacja / WPS”; [P3][M] jedno źródło celów O₂ dla całej aplikacji (patrz „Spójność”).

## welder-tools / zakładka „Timer”

- **Cel i dla kogo:** spawacz pod przyłbicą: stoper spawania, odliczanie chłodzenia międzyściegowego, odliczanie purge.
- **Co zawiera:** 3 tryby, przyciski 64–72 dp, wibracja + dźwięk + komunikat głosowy, blokada wygaszania, powiadomienie w tle, pełnoekranowy alarm, „kolejny ścieg”. Pliki: `_WeldTimerTab`, `lib/services/weld_timer_service.dart`.
- **Stan:** działa. Architektura dobra: zegar liczony z `now()`, a nie z taktów, więc aplikacja w tle nie gubi sekund.
- **Błędy potwierdzone:**
  - `weld_timer_service.dart:228-230` — `setMode()` przy innym trybie **zatrzymuje i zeruje biegnący timer bez pytania**. Przyciski trybów (64 dp) są tuż nad dużym zegarem. Przypadkowe dotknięcie rękawicą „Purge” w trakcie 8-minutowego chłodzenia kasuje odliczanie i nic nie zostaje. [potwierdzone, kod]
- **Problemy UX w terenie:**
  - Czas purge tylko w całkowitych sekundach (`decimal: false`), a chłodzenie w minutach — dwie różne jednostki w jednym narzędziu.
  - Tryb „Chłodzenie” to czysty czas. Pole „Maks. temp. międzyściegowa z WPS” jest tylko przypomnieniem, co jest poprawnie opisane. [opinia: OK]
  - Domyślne 150 °C interpass jest sensowne dla austenitu, dla CS typowo 250 °C. Ekran heat input pokazuje 250 °C „typowo” — dwie różne liczby domyślne.
- **Brakujące funkcje:** licznik ściegów / okrążeń (stoper „lap”) z zapisem czasu jarzenia i przekazaniem do heat input; historia (ile chłodzeń, dla której spoiny); ustawienie purge w min:s.
- **Testy:** `weld_timer_service_test.dart`, `weld_timer_screen_test.dart` (zmiana zakładki, wyjście z ekranu, ≥ 64 dp, zgoda na powiadomienia). Brak: testu, że zmiana trybu podczas biegu wymaga potwierdzenia (dziś jej nie ma).
- **Propozycje:** [P2][S] zmiana trybu przy biegnącym/zapauzowanym odliczaniu → dialog „Przerwać odliczanie?” albo zablokowane czipy trybu do Reset; [P2][M] stoper z „lap” → heat input; [P3][S] purge w min:s.

## welder-tools / zakładka „Ciśnienie”

- **Cel i dla kogo:** przelicznik jednostek (reduktory, manometry, próby).
- **Co zawiera:** bar, MPa, kPa, Pa, PSI, atm, kgf/cm². Plik: `_PressureConverterTab`.
- **Stan:** działa. 1 bar = 14,5038 psi, 1 atm = 1,01325 bar, 1 at = 0,980665 bar — zgodne.
- **Błędy potwierdzone:** brak.
- **Problemy UX w terenie:** brak rozróżnienia nadciśnienia i ciśnienia absolutnego (barg/bara). „atm” i „kgf/cm²” (at) stoją obok siebie bez wyjaśnienia. [opinia]
- **Brakujące funkcje:** **mbar, inH₂O, mmH₂O / mmHg** — ciśnienie formowania i korków purge podaje się w mbar albo calach słupa wody. Tu te jednostki są najważniejsze dla spawacza SS.
- **Testy:** brak dedykowanego testu przelicznika.
- **Propozycje:** [P3][S] mbar, inH₂O, mmH₂O, barg/bara; [P3][S] test tabelaryczny przeliczeń.

---

## welder-pipes / zakładka „AMP” — „Rury - Welder”

- **Cel i dla kogo:** spawacz TIG rur (głównie SS food/pharma): punkt startowy prądu, elektrody, drutu i gazów.
- **Co zawiera:** materiał (SS/CS/Duplex/AL), OD, t ≤ 3 mm, metoda (z drutem / bez), tabela prądu po t + poprawka OD + mnożnik materiału, elektroda z `sizeForCurrent`, drut, gaz palnika, zalecenia purge (HFT WP-269). Plik: `welder_pipes_screen.dart` (`_AmpTab`, `_AmpCalcResult`, `_recommendAmps`).
- **Stan:** częściowo — wyniki niespójne z resztą aplikacji.
  Przeliczenia (odtworzone z kodu):
  | Wejście | Kalkulator AMP | „Startowe” (seed) w tym samym ekranie |
  |---|---|---|
  | SS, bez drutu, Ø60,3 × 2,0 | 50 A (41–59), **Ø1,0 mm** W | Ø60 × 2,0: **80 A, Ø2,4 mm** |
  | SS, z drutem, Ø60,3 × 3,0 | 70 A (60–81) | Ø60 × 3,0: **110 A** |
  | CS, z drutem, Ø60,3 × 3,0 | **66,5 A** (57–77) | Ø60 × 3,0: **120 A** |
  | SS, bez drutu, Ø50,8 × 1,65 | 42 A, Ø1,0 mm | — |
  | Aluminium, Ø60,3 × 2,0 | 54 A | — |
- **Błędy potwierdzone:**
  1. **Mnożnik materiału ma zły kierunek dla CS:** `welder_pipes_screen.dart:1088` `'CS' => 0.95`, czyli stal węglowa dostaje o 5 % *mniej* prądu niż nierdzewna. Stal nierdzewna ma niższą przewodność cieplną i wymaga ok. 10–20 % mniej prądu niż stal węglowa tej samej grubości (tabele TIG: mig-welding.co.uk, weld.blog i inne). Oczekiwane: CS ≈ 1,10–1,20 × SS. Seed „Startowe” w tej samej aplikacji ma CS wyżej (120 A vs SS 110 A). [potwierdzone — źródła + wewnętrzna sprzeczność]
  2. **AMP kontra „Startowe” różnią się o 40–80 %** przy tych samych wymiarach (tabela wyżej). Spawacz przełącza zakładkę i dostaje 50 A albo 80 A dla tej samej rury. Komentarze w kodzie też sobie przeczą: `_recommendAmps` mówi „Ø60.3 × 2 … real practice ~70–90 A / 80–110 A”, a tabela `_startTablePoints` daje 45–50 A „z fotografii od spawacza”. [potwierdzone]
  3. **Elektroda Ø1,0 mm dla rury Ø60,3 × 2** — `sizeForCurrent(50)` wybiera *najmniejszą* elektrodę, której pasmo obejmuje prąd (1,0 mm: 15–80 A). Seed „Startowe” dla tej rury podaje Ø2,4. W ręcznym TIG rur 1,0 mm stosuje się rzadko (cienkie rurki, blacha < 1 mm). [potwierdzone co do niespójności; ocena praktyki — opinia]
  4. **Gaz palnika niespójny z ekranem Wolfram:** `welder_pipes_screen.dart:1110` `(8 + 3·Ø).clamp(12, 30)`. Dla Ø1,0–1,6 wychodzi 12–13 L/min, a ekran Wolfram dla tych średnic podaje 6–8 i 8–10 L/min, seed „Startowe” 7–9 L/min. [potwierdzone]
  5. Martwa gałąź `welder_pipes_screen.dart:986` `_material == "AL" ? "Ar 100%" : "Ar 100%"`. Nieszkodliwa, ale sugeruje zapomnianą logikę (np. Ar + N₂ dla duplexu). [potwierdzone]
- **Problemy UX w terenie:** wynik na karcie, 14–18 pt — czytelny. Metoda (z drutem / bez) jest wspólna dla trzech zakładek, a nad listą „Moje parametry” nic nie filtruje (lista pokazuje wszystkie metody) — mylące.
- **Brakujące funkcje:** pozycja (5G/6G / pion / sufit) i rola ściegu (grań / wypełnienie / lico) jako osobne wyjścia zamiast „niższa wartość = grań”; prąd pulsowy (szczyt / tło / f) — standard w SS food; napięcie + prędkość → od razu HI (spójność z heat input); duplex: gaz Ar + 2 % N₂ i formowanie N₂ / formiergaz.
- **Testy:** `welder_pipes_screen_test.dart` (WPS, ISO 6848 dla Al, purge ≤ 5 L/min). **Brak testów liczb prądu**: kierunku mnożnika materiału, zgodności ze „Startowymi”, wyboru elektrody.
- **Propozycje:**
  - [P1][M] Jedno źródło prądu startowego: albo kalkulator skalibrowany do seedów, albo seedy jako punkty interpolacji. Mnożnik CS ≥ 1,1 × SS. Test tabelaryczny „AMP ≈ Startowe ± 15 %”.
  - [P2][S] Elektroda: preferencja 1,6/2,4 dla rur (np. najmniejsza średnica z `minA ≤ I` i z uwzględnieniem „mam w magazynie” z ekranu Wolfram).
  - [P2][S] Gaz palnika z tej samej tabeli co ekran Wolfram (`_kExtrasByDia` przenieść do `lib/data/tungsten.dart`).

## welder-pipes / zakładka „Gazy”

- **Cel i dla kogo:** spawacz SS: czas przedmuchu odcinka, szacunkowy O₂, otwory wylotowe.
- **Co zawiera:** OD, t, L, Q, średnica i liczba otworów, N wymian, tryb Pharma, „Ustaw Q (złoty środek)”, szac. ppm i poziom AWS D18.2, wskaźnik prędkości na wylotach, lokalny minutnik. Plik: `_GasTab`, `lib/domain/welder_pipes/purge_estimate.dart`.
- **Stan:** częściowo — przycisk „złoty środek” przeczy sam sobie.
- **Błędy potwierdzone:**
  1. **„Ustaw Q (złoty środek)” zawsze wywołuje ostrzeżenie o back-pressure.** Q na otwór skaluje się z polem otworu (`welder_pipes_screen.dart:1384`, 0,75 L/min dla Ø1,2), więc prędkość na wylocie jest stała: 0,75 L/min / 1,131 mm² = **11,05 m/s** (Pharma: 14,7 m/s). Próg ostrzeżenia to 6 m/s (`:1600`). Wejście: 2 otwory Ø2,4, „Ustaw Q” → Q = 6,0 L/min → „Uwaga: duże obciążenie wylotu… Ryzyko back-pressure → dodaj otwory lub zmniejsz Q”. Rekomendacja i ostrzeżenie pochodzą z tego samego ekranu. [potwierdzone, przeliczone]
  2. **Lokalny minutnik pre-purge** (`:1612`, `Timer.periodic`) dubluje `WeldTimerService`. Na koniec pokazuje tylko SnackBar: bez wibracji, dźwięku i pełnego ekranu. Ginie przy zmianie zakładki (TabBarView niszczy stan, `dispose` kasuje `_timer`) i przy wyjściu z ekranu. Pod przyłbicą koniec purge przechodzi niezauważony. [potwierdzone, kod]
  3. Domyślne Q = 2 L/min (`:1298`) i N = 6 stoją obok tekstu „przedmuch typowo 15–20 L/min, ok. 5 wymian”. Model tego samego ekranu mówi jednocześnie, że 5 wymian daje ≈ 1415 ppm, a 6 wymian ≈ 521 ppm. Porada „ok. 5 wymian, aż analizator pokaże wymagany poziom” i model pełnego wymieszania się rozjeżdżają. [potwierdzone — sprzeczność komunikatów]
- **Problemy UX w terenie:** siedem pól tekstowych i przełącznik w jednej kolumnie; wynik na końcu przewijanej listy; minutnik 18 pt z małymi IconButtonami.
- **Brakujące funkcje:** objętość między korkami purge zamiast całej długości; ciśnienie formowania (mbar) i jego związek z wklęsłą granią; wybór gazu (Ar / N₂ / formiergaz 95/5 z ostrzeżeniem H₂ dla duplexu i ferrytu).
- **Testy:** `welder_pipes_screen_test` (N = 6 → ≈ 521 ppm, etykiety wylotów), `purge_estimate_test`. Brak: testu „złoty środek nie wywołuje ostrzeżenia”.
- **Propozycje:**
  - [P2][S] Złoty środek wg prędkości docelowej (np. 2–4 m/s) albo próg ostrzeżenia spójny z rekomendacją.
  - [P2][S] Minutnik → `WeldTimerService` w trybie purge (alarm, tło, pełny ekran); lokalny `Timer` usunąć.
  - [P3][S] Domyślne Q/N spójne z poradą HFT; opis modelu jako „pesymistyczny (pełne wymieszanie)”.

## welder-pipes / zakładka „Startowe”

- **Cel i dla kogo:** gotowe punkty startowe (tylko do odczytu) dla SS/CS/Duplex/AL.
- **Co zawiera:** seedy z `lib/database/db.dart` (`approvedList`, `ssAutogen`, `ssWire`, `csWire`, …) — prąd, elektroda, gaz palnika, „Purge”. Plik: `_ApprovedAmpTab`.
- **Stan:** częściowo.
- **Błędy potwierdzone:**
  - Niespójność z kalkulatorem AMP (tabela wyżej) i z tabelą wolframu: seed używa Ø2,4 od 55–60 A, a `kTungstenSizes` podaje Ø2,4 dla 150–250 A. [potwierdzone]
  - Kolumna „Purge” to 10–18 L/min (`db.dart` — `purge: d ≤ 50 ? 10 : 15`, SS_WIRE 18), a AMP i Gazy w tym samym ekranie mówią „podczas spawania ≤ 5 L/min (za duży → wklęsła grań)”. Etykieta nie mówi, czy to przedmuch, czy formowanie w trakcie spawania. [potwierdzone]
  - Wpisy SS z drutem t = 6 mm → **310 A, Ø4,0**; CS t = 8 → **330 A, Ø4,8** („ręczny TIG rur”). To wartości spoza praktyki ręcznego TIG rur (wieloprzejściowe złącze 6–8 mm spawa się ~90–180 A na ścieg). Pochodzenie: komentarz „field experience and welding forums”. [opinia — mocna]
  - Elektrody Ø4,0/4,8 nie istnieją w `kTungstenSizes`, więc ekran Wolfram ich nie zna. [potwierdzone]
- **Problemy UX w terenie:** nazwa zmieniona na „Startowe” — dobrze. Ikona `Icons.verified` przy każdym wpisie sugeruje „zatwierdzone / kwalifikowane”, choć to nie WPS. [opinia]
- **Brakujące funkcje:** pozycja, rola ściegu, źródło wartości; kopiowanie do „Moich parametrów”.
- **Testy:** brak testów zawartości seedów.
- **Propozycje:** [P2][M] przegląd seedów przez praktyka (usunąć > 200 A dla ręcznego TIG rur albo oznaczyć jako zmechanizowane); „Purge przedmuch / w trakcie” jako dwie kolumny; [P3][S] ikona neutralna zamiast „verified”; [P3][S] „Kopiuj do Moich”.

## welder-pipes / zakładka „Moje parametry”

- **Cel i dla kogo:** osobna książka parametrów spawacza (z asystentem głosowym).
- **Co zawiera:** CRUD `weld_params`: materiał, metoda, OD, t, elektroda, gaz palnika, purge, spawarka, dysza, A, otwory, tempo, notatka. Plik: `_MyParamsTab`.
- **Stan:** działa.
- **Błędy potwierdzone:**
  - Dodawanie wymaga gazu palnika i purge (`reqNum`), edycja ich nie wymaga (`optNum`) — reguły niespójne. Dla CS bez formowania trzeba wpisać „0”. [potwierdzone]
  - Brak polskich znaków: „Nie udalo sie wczytac zapisanych parametrow”, „Sprobuj ponownie”. [potwierdzone]
- **Problemy UX w terenie:** brak wyszukiwania i filtra (lista rośnie); dropdown „Metoda” nad listą nic nie filtruje.
- **Brakujące funkcje:** napięcie, prędkość → HI; pozycja; typ wolframu; puls; powiązanie z WPS z Biblioteki WPS; eksport/udostępnienie wpisu.
- **Testy:** `welder_pipes_my_params_test.dart`.
- **Propozycje:** [P3][S] wspólne reguły walidacji Dodaj/Edytuj (purge opcjonalny); [P3][S] polskie znaki; [P3][M] wyszukiwarka + filtr metody; [P3][M] U/v/HI w rekordzie.

> Martwy kod: `_ParamsLibraryTab` (`welder_pipes_screen.dart:1812`) nie jest w zakładkach, zawiera „przykład Ø60.3 t=2.0 → 80–110 A”, na który powołują się komentarze kalkulatora AMP. [P3][S] usunąć.

---

## welder-tanks / zakładka „Tandem” — „ZBIORNIKI”

- **Cel i dla kogo:** dwóch spawaczy TIG na zbiorniku SS (zewnętrzny z drutem, wewnętrzny bez) — prądy OUT/IN.
- **Co zawiera:** pozycja (pion/poziom), t1/t2, złącze (styk / szczelina / faza + land), interpolacja z zatwierdzonych punktów, skalowanie pion/poziom, fallback liniowy, clamp 15–260 A. Plik: `welder_tanks_screen.dart`, seedy `tandem_tig_params` w `db.dart`.
- **Stan:** częściowo — wyniki poza zakresem danych są błędne.
- **Błędy potwierdzone:**
  1. **Brak ekstrapolacji — wartości „przyklejają się” do skrajnych punktów**, choć dokumentacja mówi „interpolation / extrapolation” (`_interpByEff`, `welder_tanks_screen.dart:314-345`). Poziom, na styk: dane 3/3 → 140/72, 4/4 → 190/100, 3/5 → 180/90.
     - t = 1,5/1,5 → **140/72 A** (jak dla 3 mm) — na blasze 1,5 mm to przepalenie.
     - t = 8/8 → 180/90 A (jak 3/5).
     Źródło opisane jako „wyliczone z zatwierdzonych (interpolacja…)”. [potwierdzone, prześledzone w kodzie]
  2. **Wynik niemonotoniczny:** grubość efektywna = max(t1, t2), więc punkt 3/5 (eff 5) = 180/90 leży „nad” 4/4 = 190/100. Wejście 5/5 → **180/90 A, mniej niż dla 4/4**; 4,5/4,5 → 185/95. Dla złącza niesymetrycznego o przepaleniu decyduje cieńsza ścianka, a nie max. [potwierdzone]
  3. Faza land 3 + szczelina 3: jeden punkt (8,7/10 → 175/105), więc **każda grubość** (5 mm czy 20 mm) dostaje 175/105 A z opisem „Tylko 1 punkt zatwierdzony”. [potwierdzone]
  4. Stałe odniesienia niespójne z danymi: `hRefOut = 138`, `hRefIn = 68` (`:286`) i fallback 137,5/67,5 (`:414`), a zatwierdzony punkt poziomy 3/3 to **140/72**. Pion 4/4 = 190·70/138 = 96,4 / 100·40/68 = 58,8 A (przy 140/72: 95,0 / 55,6). [potwierdzone]
- **Problemy UX w terenie:** dialog „Skąd wynik?” po polsku bez polskich znaków („grubosc”, „Jesli”, „pradow”, `:564`). Przy wyniku brak ostrzeżenia „poza zakresem danych”.
- **Brakujące funkcje:** ostrzeżenie „ekstrapolacja poza zatwierdzone punkty”; prędkość i HI dla obu palników; gaz osłonowy / formujący; pozycja 2G vs 3G opisana normowo (PA/PC/PF wg ISO 6947).
- **Testy:** tylko `welder_calculations_audit_test` („tandem preserves inside and outside arcs”). Brak testów interpolacji, monotoniczności i zakresu.
- **Propozycje:**
  - [P1][S] Poza zakresem danych: nie zwracać skrajnego punktu jako „wyliczonego”. Pokazać „brak danych dla t < 3 mm — ustal na próbce” albo jawną ekstrapolację z czerwonym ostrzeżeniem.
  - [P2][M] Grubość efektywna dla t1 ≠ t2 (np. min albo średnia z wagą) i monotoniczność po t; test tabelaryczny.
  - [P3][S] Stałe odniesienia liczone z punktów w bazie (140/72), polskie znaki w dialogu.

## welder-tanks / zakładka „Zatwierdzone”

- **Cel i dla kogo:** podgląd punktów tandem (tylko odczyt).
- **Co zawiera:** lista `tandem_tig_params` z wyszukiwarką.
- **Stan:** działa.
- **Błędy potwierdzone:** brak.
- **Problemy UX w terenie:** nazwa „Zatwierdzone” sugeruje kwalifikację WPS, a to dane startowe użytkownika. Pipes zmieniły nazwę na „Startowe”, tanks nie — niespójność. [potwierdzone]
- **Brakujące funkcje:** dodawanie własnych punktów (jak „Moje parametry” w rurach), bez nich interpolacja nie ma z czego się uczyć.
- **Testy:** brak.
- **Propozycje:** [P3][S] zmiana nazwy na „Startowe”; [P2][M] własne punkty tandem.

---

## tungsten — „Elektroda wolframowa (DC-)”

- **Cel i dla kogo:** dobór średnicy i typu elektrody do prądu DC−.
- **Co zawiera:** prąd → średnica (`sizeForCurrent`), tabela 1,0–3,2 mm, typy ISO 6848 (WL20, WL15, WC20, WT20, WP, WZ8), dysza/gaz/kąt szlifu per średnica, nadpisanie z powodem, „w magazynie”, nr złącza/stempel. Pliki: `lib/data/tungsten.dart`, `lib/screens/tungsten_screen.dart`.
- **Stan:** działa.
  Pasma DC− 1,0: 15–80; 1,6: 70–150; 2,4: 150–250; 3,2: 250–400 A — zgodne z typowymi tabelami (AWS A5.12, informacyjnie). Kolory końcówek zgodne z ISO 6848.
- **Błędy potwierdzone:**
  - Gaz palnika na tym ekranie (1,6 mm → 8–10 L/min) ≠ AMP w Rurach (12–13 L/min) ≠ „Startowe” (7–9 L/min) — trzy liczby dla tej samej elektrody. [potwierdzone]
  - Brak Ø0,5, 4,0 i 4,8 mm, choć seedy „Startowe” używają 4,0 i 4,8 (`db.dart`). [potwierdzone]
- **Problemy UX w terenie:** dobre (duże wiersze, kopiowanie, przytrzymanie = magazyn). Oznaczenia ISO 6848:2015 to WLa20 / WCe20 / WTh20 / WZr8 — aplikacja używa starych (WL20…). Spawacz z pudełkiem nowego typu może nie skojarzyć. [potwierdzone co do nazewnictwa]
- **Brakujące funkcje:** pasma AC (Al) — ekran AMP odsyła „do tabeli producenta”; kąt szlifu z prądu (nie tylko ze średnicy); wysięg elektrody.
- **Testy:** `tungsten_test.dart`, `tungsten_screen_test.dart`, audyt „brak niepokrytych wartości”. Uwaga: test „current bands are ordered and non-overlapping going up” przechodzi, choć pasma się nakładają (70–80 A) — nazwa testu myląca.
- **Propozycje:** [P2][S] tabela dysza/gaz/kąt do `lib/data/tungsten.dart` jako jedno źródło dla Wolframu i AMP; [P3][S] nazwy ISO 6848:2015 w nawiasie; [P3][S] 0,5/4,0/4,8 mm; [P3][M] pasma AC.

---

## orbital-tig — „Orbital TIG”

- **Cel i dla kogo:** operator głowicy orbitalnej (rurki SS food/pharma): parametry startowe kuponu.
- **Co zawiera:** OD, ścianka, U łuku, stempel/WPS; wynik: prąd na 4 poziomach, prędkość, czas obrotu, liczba przejść, HI. Pliki: `lib/services/orbital_tig.dart`, `lib/screens/orbital_tig_screen.dart`.
- **Stan:** częściowo.
  Przeliczenie: 2" (50,8 × 1,65), 10 V → prąd bazowy 48·1,65 + 0,12·50,8 = **85 A**, poziomy 85/78/71/66, v = 100 mm/min, czas 95,6 s, HI (η = 0,6) = 0,306 kJ/mm. Dla prądu szczytowego pulsu wiarygodne. [opinia]
- **Błędy potwierdzone:**
  1. **Brak górnej granicy ścianki dla modelu autogenicznego.** Walidacja przepuszcza ścianki do 25 mm i OD do 1000 mm (`orbital_tig_screen.dart:148,160`). Wejście 168,3 × 6,0 → **308 A**, „2 przejścia”, HI 1,59 kJ/mm; 273 × 10 → **513 A**. Autogeniczny orbital (bez drutu) sensownie obejmuje ~0,5–3 mm; powyżej potrzeba fazy i drutu (głowica z podajnikiem, wieloprzejściowo). Dostaje się liczbę, a nie ostrzeżenie. [potwierdzone, przeliczone; granica ~3 mm — opinia praktyka]
  2. HI podpisane „Energia liniowa (orient.)” bez konwencji. Liczone z η = 0,6 (EN), więc dla WPS wg ASME IX spawacz porówna liczbę o 40 % za niską. Ekran heat input robi to rozróżnienie wyraźnie. [potwierdzone]
- **Problemy UX w terenie:** nazwy poziomów „Płasko / Pionowo w dół / Pionowo w górę / Pułapowo” sugerują, że poziomy to pozycje. W praktyce poziomy orbitalne kompensują głównie nagrzewanie rury w czasie (start → koniec), a kolejność pozycji zależy od punktu startu. [opinia]
- **Brakujące funkcje:** **prąd pulsowy** (szczyt / tło / częstotliwość / % czasu), bo w orbitalu food/pharma to standard; downslope, zakładka (overlap), pre/post-purge głowicy, prędkość obrotu w obr/min; zapis harmonogramu do Moich parametrów.
- **Testy:** `orbital_tig_test.dart` (obwód, malejące poziomy, grubsza ścianka = większy prąd, przejścia, HI > 0), audyt. Brak testu górnej granicy ścianki.
- **Propozycje:** [P1][S] dla t > 3 mm (albo > 3,5) zamiast wyniku komunikat „poza zakresem autogenicznego orbitalu — faza + drut / WPS”; [P2][S] HI z etykietą „EN 1011-1, η 0,6” + wartość ASME; [P2][M] parametry pulsu; [P3][S] nazwy poziomów „Poziom 1–4 (sektory)”.

---

## hydrotest — „Próba ciśnieniowa” (+ protokół PDF, rejestr)

- **Cel i dla kogo:** inspektor / QC i brygada prób: ciśnienie próby, objętość wody, czas napełniania, protokół z pomiarami i PDF.
- **Co zawiera:** geometria (DN/SCH), 5 presetów (B31.3 hydro/pneu, B31.1 hydro, EN 13480-5/PED, ASME VIII-1), ST/S / f_test/f / LSR, opcjonalny test Re (§345.2.1(a)), pompa, arkusz zapisu (pomiary puste, kalibracja, zawór, świadek, PASS/FAIL), rejestr, PDF. Pliki: `hydrotest_screen.dart`, `lib/domain/pressure_test/*`, `lib/services/hydrotest_export.dart`.
- **Stan:** działa. To najlepiej dopracowany moduł w grupie.
  Przeliczenia:
  - B31.3 hydro P = 10 bar, ST/S = 1,2 → Pt = 18,0 bar. ST/S = 8 → przycięte do 6,5.
  - EN 13480-5, PS = 10, f_test/f = 1,0 → max(12,5; 14,3) = **14,3 bar** (decyduje 1,43·PS). Czas trzymania 30 min potwierdzony w EN 13480-5:2017 §9.3.2.
  - B31.3 pneu → 1,1·P, maks. 1,33·P; B31.1 → 1,5·P; VIII-1 → 1,3·MAWP·LSR.
- **Błędy potwierdzone:**
  - Brak kontroli **zmierzonego ciśnienia początkowego względem Pt**. W arkuszu zapisu obliczone Pt jest tylko podpowiedzią (`hydrotest_screen.dart:2199`). Wpisanie start = 12 bar przy Pt = 15 bar i wyniku PASS nie daje żadnego ostrzeżenia ani adnotacji na protokole (jest tylko ostrzeżenie o spadku ciśnienia i krótkim czasie). Dla pneumatycznej nie ma też ostrzeżenia przy start > 1,33·P. [potwierdzone, kod — grep bez wyników]
  - Test Re (§345.2.1(a)) jest tylko dla B31.3 hydro. Dla **EN 13480-5** norma też ogranicza Pt naprężeniem dopuszczalnym w warunkach próby wg EN 13480-3 („the test pressure shall be limited…”), a dla **B31.3 pneumatycznej** górną granicą jest ciśnienie dające 90 % Re. Tekst o 90 % Re jest, obliczenia nie ma. [potwierdzone co do braku; wymóg — źródło EN 13480-5 / B31.3 §345.5.4]
- **Problemy UX w terenie:** dużo pól w jednej kolumnie, ale z sensowną kolejnością i banerem BHP. Test Re liczy się na ściance wpisanej, a nie minimalnej — jest na to uczciwa uwaga, ale nie ma przycisku „−12,5 % (tolerancja walcownicza)”.
- **Brakujące funkcje:**
  - **Poprawka na słup wody** (0,0981 bar/m): Pt dotyczy konkretnego punktu (B31.1 „at any point”), a manometr bywa na dole pionu. Brak pól „wysokość manometru / najwyższy punkt”.
  - Kontrola zakresu manometru (typowo 1,5–4 × Pt, np. ASME VIII UG-102) i nastawy zaworu bezpieczeństwa względem Pt (B31.3 §345.5.1 dla pneumatycznej: ≤ Pt + mniejsza z 345 kPa i 10 % Pt).
  - Rating kołnierzy B16.5 (1,5 × rating przy 38 °C) jako gotowy test „komponent ogranicza Pt”.
  - Ostrzeżenie o temperaturze metalu (kruche pękanie, zamarzanie) przy temperaturze < 5 °C.
- **Testy:** bogate: `test_pressure_test.dart`, `hydrotest_protocol_meta_test`, `hydrotest_screen_test` (360 dp, puste pomiary, §345.2.1(a)), `hydrotest_pressure_test`, `hydrotest_export_test`, `hydrotest_pdf_render_test`, `hydrotest_dao_test`, `hydrotest_protocol_columns_test`. Brak: „start < Pt przy PASS”.
- **Propozycje:**
  - [P1][S] Ostrzeżenie w arkuszu i na PDF: „ciśnienie początkowe < Pt (obliczone)” oraz (pneu) „> 1,33·P”. PASS bez uzasadnienia → adnotacja jak przy spadku.
  - [P2][M] Słup wody: Pt w najwyższym punkcie + odczyt manometru na wysokości h.
  - [P2][S] Test Re / 90 % Re także dla pneumatycznej i EN (z f_test wg EN 13480-3).
  - [P3][S] Zakres manometru i nastawa zaworu vs Pt — ostrzeżenia.

---

## bolt-torque — „Moment dokręcania”

- **Cel i dla kogo:** monter / inspektor połączeń kołnierzowych: moment na śrubę z preloadu.
- **Co zawiera:** preset B16.5 (DN × klasa → liczba i rozmiar śrub), rozmiar 1/2"–2", gatunek A193 (B7/B7M/B16/B8M), smar (K), % SMYS 30–75 %, T = K·F·d, A_s wg ASME B1.1, procedura, udostępnianie. Pliki: `lib/domain/bolting/bolt_torque.dart`, `lib/screens/bolt_torque_screen.dart`, `lib/services/flange_catalog.dart`.
- **Stan:** działa dla obsługiwanych kombinacji.
  Przeliczenia (B7, 50 % SMYS, K = 0,16): 5/8"-11 → A_s 145,8 mm², F 52,8 kN, **134 N·m**; 3/4"-10 → 215,8 mm², 238 N·m; 1"-8 → 390,8 mm², 575 N·m — zgodne z testami.
  Katalog B16.5 dla klas 150/300 oraz 600 od DN50 — zgodny z tablicami (wermac.org, Class 600).
- **Błędy potwierdzone:**
  1. **Luki w katalogu B16.5 opisane jako „nie ma w B16.5”.** `flange_catalog.dart:52-76` nie ma: Class 600 DN15–DN40 (B16.5: np. NPS 1 = 4 × 5/8", NPS 1½ = 4 × 3/4" — wermac.org), Class 900 DN15–DN40 i DN65, Class 1500 DN15–DN40 i DN65 (w B16.5 istnieją; dla NPS ½–2½ wymiary 900 = 1500). Ekran pokazuje wtedy „Brak DN25 × Class 600 **w B16.5** — wybierz inną kombinację” (`bolt_torque_screen.dart:89`) — nieprawda. Test `bolt_torque_values_test.dart:122` „katalog B16.5 odrzuca DN15 × Class 1500” **utrwala błąd**. [potwierdzone, źródło]
  2. **Czas ponownego dokręcenia sprzeczny z ASME PCC-1.** Krok 8: „Relaxation pass po 20 min – 4 h” (`:621`) i w udostępnianej notatce „re-torque po 20min-4h” (`:551`). PCC-1 (procedura Legacy, runda 5): „time permitting, wait a **minimum of 4 h** and repeat Round 4”. [potwierdzone, źródło]
  3. Zdanie „ASME PCC-1 zaleca 50 % SMYS dla flange średniego ryzyka, 60-70 % dla krytycznego” (`:409`) nie jest cytatem PCC-1. PCC-1 (App. O) każe dobrać naprężenie docelowe z ograniczeń kołnierza i uszczelki, a nie z „ryzyka”. [opinia — do przeredagowania]
- **Problemy UX w terenie:** gdy preset nie jest ustawiony, dropdowny DN/klasa pokazują „DN50 / #150”, jakby preset był aktywny. Wybór tej samej wartości nic nie robi. Brak polskich znaków: „Reczne” (`:312`), „Udostepnij”, „Sruba”, „Moment dokrecania”. Brak momentów pośrednich (25/50/75 %) w N·m — monter liczy w głowie.
- **Brakujące funkcje:** Class 2500 i DN > 300 (B16.5 do NPS 24, B16.47); śruby > 2" (Class 900/1500 dla dużych DN mają 2½"–3½"); B7 > 2½" (SMYS 95 ksi); B8M klasa 2 (utwardzana, wyższe SMYS); sprawdzenie naprężenia uszczelki (min. osadzenie / max zgniecenie); ciśnienie klucza hydraulicznego / siła napinacza; nakrętki metryczne (EN 1092-1, śruby M).
- **Testy:** `bolt_torque_test.dart` (A_s wg B1.1 dla wszystkich rozmiarów, 8UN, B8M, walidacja), `bolt_torque_values_test.dart` (134/168/38 N·m, preset DN100 #150, DN300 #300). Test DN15 × #1500 do odwrócenia.
- **Propozycje:**
  - [P1][S] Uzupełnić katalog B16.5 (600/900/1500 dla DN15–65) i zmienić komunikat na „brak w katalogu aplikacji”; odwrócić test.
  - [P2][S] Krok 8 i notatka: „po min. 4 h (PCC-1, runda 5)”.
  - [P2][S] Pokazać 25/50/75/100 % w N·m i ft·lb.
  - [P3][S] Polskie znaki; przeredagować zdanie o PCC-1.
  - [P3][L] Class 2500, B16.47, śruby do 4", B7 > 2½", sprawdzenie uszczelki.

---

## Spójność między modułami (zbiorczo)

| Wielkość | Gdzie | Wartości | Status |
|---|---|---|---|
| Prąd dla Ø60 × 2 SS bez drutu | AMP / Startowe | 50 A / 80 A | [potwierdzone] niespójne |
| Mnożnik CS vs SS | AMP / Startowe / źródła | 0,95 / ~1,1 / 1,1–1,2 | [potwierdzone] AMP odwrotnie |
| Elektroda dla ~50–80 A | AMP / Startowe / Wolfram | 1,0 / 2,4 / 1,0 lub 1,6 | [potwierdzone] niespójne |
| Gaz palnika Ø1,6 | Wolfram / AMP / Startowe | 8–10 / 12–13 / 7–9 L/min | [potwierdzone] niespójne |
| Purge w trakcie spawania | AMP i Gazy / Startowe | ≤ 5 / 10–18 L/min | [potwierdzone] niespójne |
| Cel O₂ | O₂ Purge / Orbital / katalog duplex | < 20 „pharma”, < 100 „przem.” / < 50 / < 100, < 50 | [opinia] brak jednego źródła |
| Max międzyściegowa | Heat input / Timer / katalog | 250 °C / 150 °C / 175–300 °C | [potwierdzone] różne domyślne |
| HI | Heat input / Orbital | EN lub ASME jawnie / EN bez podpisu | [potwierdzone] |
| Minutnik purge | Timer (serwis, alarm) / Rury → Gazy (lokalny, SnackBar) | — | [potwierdzone] dwa różne |
| Nazwa „Zatwierdzone” | Rury („Startowe”) / Zbiorniki („Zatwierdzone”) | — | [potwierdzone] |

Disclaimery „wiąże WPS / specyfikacja”: obecne w heat input (obie zakładki), welder-tools (każda zakładka), AMP, orbital (dobrze widoczny na górze), hydrotest (BHP + procedura QC), bolt-torque („orientacyjna… manufacturer chart”). **Brak** w: welder-pipes „Gazy” (jest tylko „zweryfikuj analizatorem”), „Startowe”, welder-tanks (żadnego zdania o WPS przy prądach tandemu), tungsten. [potwierdzone, przegląd tekstów]

---

## Top 5 w grupie

1. **[P1] Tandem (zbiorniki) podaje prądy spoza danych jako „wyliczone z zatwierdzonych”:** 1,5 mm → 140/72 A (jak 3 mm), 5/5 mm → mniej niż 4/4, jeden punkt fazy → ta sama wartość dla każdej grubości. `welder_tanks_screen.dart:314-345`. Ryzyko przepalenia i fałszywego zaufania.
2. **[P1] Preheat dla P91/Cr-Mo: Seferian 365 °C i czerwone ostrzeżenie CE 2,2** na tym samym ekranie, co minimum kodowe 200 °C. Metody z CE trzeba ukryć dla P-No 4/5x/15E. Przy okazji: minimum kodowe z B31.3-**2012** (aktualne wydania: wartości jak w B31.1, np. 5A/5B do 200 °C) i DN/SCH, które nie ustawia grubości.
3. **[P1] Rury → AMP sprzeczne z „Startowymi”, Wolframem i fizyką:** CS dostaje mniej prądu niż SS (×0,95), ta sama rura daje 50 A albo 80 A, elektroda Ø1,0 kontra Ø2,4, gaz 8–10 kontra 12–13 L/min. Potrzebne jedno źródło danych i test spójności.
4. **[P1] Próba ciśnieniowa: brak ostrzeżenia, gdy zmierzone ciśnienie początkowe < Pt** (albo > 1,33·P dla pneumatycznej) przy wyniku PASS. PDF może przejść z próbą wykonaną poniżej wymaganego ciśnienia. Dalej: słup wody, test Re dla pneu/EN.
5. **[P1/P2] Moment śrub: fałszywe „brak w B16.5”** dla Class 600/900/1500 DN15–65 (utrwalone testem) i re-torque „po 20 min – 4 h” wbrew PCC-1 (min. 4 h). Blisko w kolejce: orbital bez górnej granicy ścianki (6 mm → 308 A autogenicznie), „złoty środek” Q w Rurach → Gazy zawsze wywołujący ostrzeżenie back-pressure, minutnik purge bez alarmu, zmiana trybu timera kasująca odliczanie.

---

## Źródła

- EN 1011-1 tab. 1 / TWI FAQ „heat input vs arc energy” — współczynniki k (powołane w kodzie; wartości zgodne).
- ASME B31.3-2012 Table 330.1.1 (kopia): https://pdfcoffee.com/p-number-table-of-b313-pdf-free.html
- Becht, „ASME B31.3 – Substantive Changes to 2014 Edition” (podgrzewanie ujednolicone z B31.1; 95 °C > 25 mm dla zwolnienia z PWHT P-1): https://becht.com/becht-blog/entry/asme-b31-3-substantive-changes-to-2014-edition/
- B31.1 §131.4 (P-No 5A/5B 200/150 °C; P-No 1 80 °C) — wyniki wyszukiwania, m.in. https://www.eng-tips.com/threads/preheat-in-asme-9.293266/ , https://www.nrc.gov/docs/ML0314/ML031470601.pdf
- EN 13480-5:2017 §9.3.2 (30 min, ograniczenie Pt naprężeniem wg EN 13480-3): https://pdfcoffee.com/bs-en-13480-5-2017-pdf-free.html
- ASME B16.5 Class 600 — śruby: https://www.wermac.org/flanges/dimensions_weldneck_in_asme-b16-5_600.html ; 900 = 1500 dla NPS ½–2½: http://www.metalspiping.com/asme-b16-5-class-900-flange.html , https://www.engineeringtoolbox.com/flanges-bolts-dimensions-d_464.html
- ASME PCC-1 Legacy (rundy 20–30 / 50–70 / 100 %, runda 5 po min. 4 h): https://www.kaskomakine.com/blogs/flange-bolt-torque-assembly-asme-pcc-1 , https://pdfcoffee.com/pcc-12019-pdf-free.html
- TIG SS vs CS (SS ~10–20 % mniej prądu): https://www.mig-welding.co.uk/tig-calculator.htm , https://weld.blog/tig-welding-amperage-chart
- HFT WP-269 (przepływy purge) — powołane w `purge_estimate.dart`.
