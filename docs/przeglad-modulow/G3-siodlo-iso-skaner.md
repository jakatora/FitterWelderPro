# G3 — Siodło, Zeszyt ISO, Skaner ISO: przegląd modułów

Data: 2026-09-26 · gałąź `fix/audyt-2026-08-29` (HEAD `40f254e`, release 0.3.0+17) · przegląd tylko do odczytu.

Zakres: `saddle-cut`, `saddle-template`, `iso-notebook`, `iso-scanner`, `scan-review`, a także
`lib/services/saddle_*.dart`, `lib/domain/iso_notebook/*`, `lib/screens/iso_notebook_*.dart`,
`lib/services/iso_scanner_ai.dart`, `scan_to_project.dart`, `scan_outputs.dart`, złoty zestaw
`test/golden_iso/` (19 przypadków) i prompt `backend/src/services/fitterScan.js`.

Metoda:
- czytanie kodu;
- niezależne przeliczenie siodła w Pythonie (przecięcie walców, 360 000 próbek) i porównanie z `SaddleGeometry`
  uruchomionym przez `dart run` (skrypt w scratchpadzie);
- sondy `flutter test` w scratchpadzie (`sketch_probe_test.dart`, `scan_probe_test.dart`). Wywołują one prawdziwe
  funkcje domeny (`sketchCutMm`, `planProjectFromSketch`, `planFromScan`, `evaluateReview`) na przypadkach brzegowych;
- ręczne przeliczenie przypadków złotego zestawu.

Uruchomione testy grupy (17 plików / katalogów, w tym `test/golden_iso`, `test/domain/iso_notebook`, testy siodła,
skanera i przeglądu): **228 testów, wszystkie zielone**.

Oznaczenia: **[potw.]** = potwierdzone sondą, przeliczeniem albo jednoznacznie w kodzie; **[opinia]** = ocena
montera/UX. Rzeczy naprawione w serii 24–25.09 (jeden silnik CUT w zeszycie, szczelina w szkicu, blokada niskiej
pewności, zapis częściowy, WN do przylgi w skanerze, B16.11 SW, M trójnika redukcyjnego w skanerze) sprawdziłem.
Działają, więc ich nie powtarzam.

---

## saddle-cut — „Siodło 90° — tabela”
- **Cel i dla kogo:** monter prefabrykujący odgałęzienie 90° (set-on, „fish-mouth”) bez drukarki. Tabela głębokości
  co 15° do odmierzenia taśmą na rurze odgałęzienia.
- **Co zawiera (funkcje, wejście, pliki):** `lib/screens/saddle_cut_screen.dart` (493 l.), geometria w
  `lib/services/saddle_geometry.dart` (wspólna z szablonem). Wejście: OD rury głównej i OD odgałęzienia, zakres
  od >0 do 2000 mm, przecinek dozwolony. Wynik: h_max, tabela 0–90° i pełny obwód 0–360° (25 pkt), kopiowanie do
  schowka, przewodnik obliczeń krok po kroku, ostrzeżenia (DN ≠ OD, bez ścianki, fazy i szczeliny).
- **Stan:** działa.
- **Weryfikacja ręczna [potw.]:** wzór d(φ) = √(R² − r²·sin²φ) − √(R² − r²) (90°) zgadza się z niezależnym
  przecięciem walców co do 0,01 mm:

  | Rura gł. / odg. | h_max | 15° | 30° | 45° | 60° | 75° | 90° | obwód |
  |---|---|---|---|---|---|---|---|---|
  | 114,3 / 60,3 | 8,60 | 8,06 | 6,58 | 4,47 | 2,29 | 0,62 | 0,00 | 189,44 |
  | 88,9 / 88,9 (T równy) | 44,45 | 42,94 | 38,49 | 31,43 | 22,23 | 11,50 | 0,00 | 279,29 |
  | 100 / 60 (wzorzec w kodzie) | 10,00 | 9,39 | 7,70 | 5,28 | 2,72 | 0,75 | 0,00 | 188,50 |

- **Błędy potwierdzone:** brak błędów obliczeniowych.
- **Problemy UX w terenie:**
  - [opinia] Trzeba wpisać OD z pamięci. Nie ma wyboru DN/NPS → OD, choć dane `kPipeWalls` są w aplikacji.
    Ostrzeżenie „OD to nie DN” jest, ale w rękawicach to najczęstsza pomyłka (DN100 → 100 zamiast 114,3 daje
    h_max 10,0 zamiast 8,6).
  - [opinia] Ekran nie odsyła do „Szablonu siodła do druku”, gdy odgałęzienie jest pod kątem. Tekst mówi tylko
    „nie stosuj do ukośnych”.
- **Brakujące funkcje:** grubość ścianki / wariant set-on (profil po ID odgałęzienia) i set-in; szablon otworu
  w rurze głównej; odgałęzienie mimośrodowe; podział obwodu na 8/16 części (praktyka warsztatowa) jako alternatywa
  dla 15°.
- **Testy:** `test/screens/saddle_cut_test.dart`, `saddle_cut_values_test.dart`: wartości 100/60, 114/60, 200/100,
  walidacja, kopia, nieaktualny wynik po edycji, duży tekst. Pokrycie dobre. Brak testu, że ekran i PDF szablonu dają
  identyczne liczby dla 90° (wspólna klasa to gwarantuje, test tylko to przypina).
- **Propozycje:**
  - [P2] [S] Pole „wybierz DN/NPS” wypełniające OD z `kPipeWalls` (obok ręcznego OD).
  - [P2] [M] Opcja „set-on (po ID odgałęzienia)” z grubością ścianki. Przykład 219,1 / 114,3×6: h_max po OD
    16,09 mm, po ID 12,67 mm. Różnica 3,4 mm w kroczu to szczelina, której monter się nie spodziewa.
  - [P3] [S] Link „Kąt ≠ 90°? → Szablon do druku”.
  - [P3] [M] Scalić oba narzędzia siodła w jedno z dwoma trybami (tabela / PDF). Dziś to dwa ekrany z różnym
    stylem (Material jasny vs ciemne kolory na sztywno).

## saddle-template — „Szablon siodła do druku”
- **Cel i dla kogo:** szablon 1:1 do owinięcia na rurze odgałęzienia (kąt 15–90°), wydruk A4 z kafelkowaniem.
- **Co zawiera:** `lib/screens/saddle_template_screen.dart` (1148 l.), `lib/services/saddle_template.dart` (PDF),
  `saddle_print_layout.dart` (kafelki 260×140 mm, zakładka 5 mm, limit 100 kartek), `saddle_geometry.dart`.
  Wejście: OD główna i boczna, kąt suwakiem (co 5°) lub chipami 30/45/60/75/90, opis projektu. Wynik: podgląd
  konturu, max głębokość, obwód (mm i cale). PDF zawiera tabelę co 15°, podgląd (nie 1:1) i strony 1:1 z podziałkami
  100 mm w poziomie i pionie.
- **Stan:** działa. Obliczenia poprawne, ale część funkcji brakuje (tabela na ekranie, dowolny kąt).
- **Weryfikacja ręczna [potw.]:** t(φ) = [√(R² − r²sin²φ) + r·cosα·cosφ] / sinα oraz analityczne minimum
  (dla R·cosα ≤ r: t_min = √(R² − r²) przy cosφ = −cosα·√(R² − r²)/(r·sinα); inaczej φ = 180°) sprawdziłem
  wyprowadzeniem. Liczbowo zgadza się z niezależnym przecięciem (Python) i z kodem (`dart run`):

  | Przypadek | max | 0° | 45° | 90° | 135° | 180° | min przy | kafelki |
  |---|---|---|---|---|---|---|---|---|
  | 168,3/88,9 @45° | 88,90 | 88,90 | 67,27 | 26,49 | 4,41 | 0,00 | 180° | 2×1 |
  | 219,1/114,3 @60° | 66,03 | 66,03 | 47,45 | 14,46 | 0,78 | **0,04** | **160,8°** | 2×1 |
  | 200/100 @30° | 173,21 | 173,21 | 134,92 | 59,81 | 12,45 | 0,00 | 180° | 2×2 |

  Przypadek 60° jest subtelny: minimum nie leży na 180°, a kod liczy je analitycznie i poprawnie.
- **Błędy potwierdzone:** brak błędów obliczeniowych.
- **Problemy UX w terenie:**
  - [potw.] Ekran nie pokazuje żadnej tabeli rzędnych, tylko podgląd, 3 metryki i tekst „Znacznik co 5,2 mm
    (krok 5°)” (`saddle_template_screen.dart:~520`). Bez drukarki na budowie monter nie ma liczb dla kąta ≠ 90°.
    Tabela jest tylko w PDF.
  - [potw.] Kąt tylko co 5° (`Slider divisions: 15`, l. ~441). Nie da się ustawić 22,5°, 52° ani 87° z rysunku.
  - [opinia] Metryka „Punktów: 73” nic monterowi nie mówi. Etykiety 10–11 px na ciemnym tle są słabo czytelne
    w słońcu. Chipy „Spróbuj tego” mają ok. 30 dp wysokości (poniżej 48 dp).
  - [opinia] Na stronach 1:1 kontur przy głębokości 0 leży dokładnie na ramce kafla, a jego połowa jest przycięta
    przez clip. Linia bazowa Y=0 nie ma osobnego oznaczenia „BAZA”.
- **Brakujące funkcje:** jak w saddle-cut (ścianka / set-on, otwór w rurze głównej, mimośród). Brak pola
  wpisania kąta liczbą. Brak eksportu samej tabeli (CSV / schowek).
- **Testy:** `test/services/saddle_geometry_regression_test.dart`, `saddle_pdf_test.dart`,
  `saddle_print_layout_test.dart`, `saddle_template_test.dart`, `saddle_export_guard_test.dart`,
  `test/screens/saddle_template_screen_test.dart`. Pokryte: 90°, 45° (różnica 0/180 = 2r·cot α), walidacja,
  kafelki, limit 100 kartek, anulowanie eksportu. Brak: przypadek z minimum wewnątrz przedziału (np. 60°
  powyżej, t_min przy 160,8°) oraz rzędne pośrednie dla kąta ≠ 90/45.
- **Propozycje:**
  - [P2] [S] Na ekranie tabela rzędnych co 15° (albo 16 podziałów), z kopiowaniem, jak w saddle-cut.
  - [P2] [S] Pole liczbowe kąta (15–90, krok 0,5°) obok suwaka.
  - [P2] [M] Set-on po ID / set-in oraz szablon otworu w rurze głównej (te same wzory, zamiana ról).
  - [P3] [S] Test regresji dla 219,1/114,3/60° (min 160,8°, d(180°) = 0,04).
  - [P3] [S] Grubsze etykiety (≥ 12 px), chipy 48 dp, bez metryki „Punktów”.

## iso-notebook — „Zeszyt ISO”
- **Cel i dla kogo:** monter szkicuje palcem izometrię na siatce, wpisuje wymiary, dostaje CUT każdej rury, BOM,
  PDF i (od 25.09) projekt CUT.
- **Co zawiera:** `lib/screens/iso_notebook_screen.dart` (9238 l.), dialogi `iso_notebook_project_dialogs.dart`,
  zapis `iso_notebook_saved_sketches.dart` i `iso_notebook_sketch_codec.dart`, domena
  `lib/domain/iso_notebook/sketch_cut.dart` (jedna formuła CUT przez `PrefabEngine.cutLengthMm`) i
  `sketch_to_project.dart` (plan projektu), zapis `lib/services/iso_sketch_project_writer.dart`.
  Narzędzia: rura / linia / ukryta, 18 symboli, strzałki, tekst, blokada osi, auto-zapis, cofanie, szczelina spoiny,
  kalkulator ISO − odliczenia z paskiem operatorów, DimRef, lista cięć, BOM, „trasa rurociągu”, PDF.
- **Stan:** częściowo. Jeden silnik CUT jest spójny z kreatorem segmentu (test `sketch_to_project_test` „CUT z bazy ==
  CUT zeszytu”). Trzy ścieżki dają jednak błędny wynik bez ostrzeżenia (niżej).
- **Weryfikacja ręczna [potw.]:** kolano–kolano DN100 LR (CTE 152), ISO 2000, szczelina 3 → 2000 − 2·152 − 2·3 =
  1690 (sonda A bez błędnego wiersza). Kolano–kołnierz WN (Y = 76) przy DimRef CTE (oś–koniec) → 1000 − 152 − 76 −
  2·3 = 766. Wynik jest zgodny z propozycją skanera w przypadku golden 06 (bez szczeliny 772).
- **Błędy potwierdzone:**
  - **[P1] Kołnierz / zawór na końcu: domyślnie „oś-oś”, wybór ukryty.** `iso_notebook_screen.dart:1926`
    (`refLocal = current?.ref ?? DimRef.centreToCentre`). Wybór DimRef jest w zwiniętych „Opcjach zaawansowanych”
    (l. ~2384–2491) i pokazuje same kody CTC/CTF/FTF/FTE/CTE bez opisu. Sonda G: kolano (152) → kołnierz WN
    (L = 76), ISO 1000, szczelina 3:
    CTC = **842**, CTF = **842**, FTF = 994, FTE = 918, CTE = **766**. Wymiar na izometrii do przylgi kołnierza
    to CTE (oś–koniec), więc domyślny wynik jest **o 76 mm za długi**. `planProjectFromSketch` zapisuje go do
    projektu bez uwagi. Skaner w tej samej sytuacji blokuje cięcie do potwierdzenia (propozycja 772/766).
    Dochodzi pułapka słownictwa: w zeszycie „czoło” = bliższe czoło (koniec piasty), w prompcie skanera
    FACE = przylga, a kod „CTE” znaczy tu „oś–koniec”, a w innych miejscach aplikacji „centre-to-end kształtki”.
    `PrefabEngine.needsDimRefPicker` („każdy fizyczny koniec wymusza wybór”) nie jest w zeszycie użyty.
  - **[P1] Nieczytelny wiersz odliczenia ręcznego znika po cichu.** `sketch_cut.dart:429–436` pomija wiersz,
    którego nie da się sparsować. Dialog zapisuje go mimo to (l. 2519–2531), a `sketch_to_project.dart` nie
    sprawdza tego przy tworzeniu projektu. Sonda A: odliczenie „Uszczelka 3+” (operator z paska na końcu) →
    CUT **1690** zamiast 1687, projekt utworzony z 1690, `skipped = []`. Z wierszem „76+” rura wychodzi 76 mm za
    długa. Lista cięć wypisuje „− Uszczelka: 3+”, a wynik go nie odejmuje. Łamie to §2 p. 6 / §9. Legacy skaner
    ma na to licznik `deductParseErrors`, zeszyt nie ma.
  - **[P1] Trójnik redukcyjny niemożliwy do opisania — odgałęzienie liczone z C.** Komponent ma jedno `cteMm`, a
    `sketchAxialTakeoutOf` (l. 131–141) bierze `TakeoutCatalog.tee[dn]` = C dla każdej odnogi. Brak narzędzia
    trójnika redukcyjnego / DN odgałęzienia (`enum _Tool`, l. 51–60). Sonda C: trójnik DN150, odgałęzienie DN80,
    kolano DN80 (114), ISO 1000 → **743**. Przy M = 130 (B16.9 6×3) powinno być **756**, więc rura jest **13 mm za
    krótka** (złom). Dla 12×6 (C = 254, M ≈ 219) różnica wynosi ok. 35 mm. Skaner robi to dobrze (golden 12:
    M = 98), więc moduły są niespójne.
  - [P2] Ręczny CTE kolana „zjada” automatyczny CTE innego kolana. `sketch_cut.dart:230–235`: komponent bez
    CTE trafia do `missing` **przed** sprawdzeniem `claimedByHand`, więc wiersz „Kolano 90° LR (CTE)” wpisany
    za kolano bez specyfikacji odbiera odliczenie drugiemu kolanu. Sonda B: E1 bez CTE + wiersz ręczny 152, E2 z CTE
    152, ISO 2000, szczelina 3 → CUT **1842** zamiast 1690 (**152 mm za długa**). Lista pokazuje przy tym
    „Kolano 90°: brak wymiaru (CTE) — NIE odjęto”, choć monter je odjął. Projekt tej rury nie utworzy (skip),
    więc szkoda zostaje na ekranie, w PDF i w schowku.
  - [P2] Olet w węźle dwóch rur przelotu odejmuje swój take-out i 2 szczeliny od rury głównej. Sonda D: kolana
    229, olet (60) w środku, 2 × 1500 → każda **1205**, razem 2410. Jedną linią wychodzi 2536. Rura główna przy
    olecie nie jest cięta (skaner: golden 13 „rura nie jest cięta na olecie”). W zeszycie monter, który naturalnie
    rysuje dwie kreski do punktu oletu, dostaje dwie za krótkie rury bez ostrzeżenia.
  - [P3] Kropka spoiny między dwiema rurami nie daje szczeliny (`sketchEndIsWelded`, l. 331–346, świadomie
    „weld dot = OPEN_END”). Sonda E: 1345 + 1345, razem 3 mm za dużo przy szczelinie 3. Błąd jest bezpieczny
    (za długo), ale niespójny z tym, co się fizycznie spawa.
  - [P3] `_totalMm` i „Sztangi” sumują też rury z brakującym CTE (liczba skończona, tylko oznaczona „!”).
- **Problemy UX w terenie:**
  - [potw.] Brak pinch-zoom. Powiększenie i przesuwanie są tylko w menu „Widok” (`_zoomBy` wywoływane wyłącznie
    z PopupMenu, l. 5296–5302; przesuwanie wymaga przełączenia trybu). Na telefonie 360 dp w rękawicach to 2–3
    dotknięcia na każde przybliżenie.
  - [potw.] Chipy paska narzędzi mają ok. 26–28 dp wysokości (padding 5, ikona 15, tekst 11; `_Toolbar`,
    l. ~5775). Norma to ≥ 48 dp. Siatka ma 32 px, a tolerancja „komponent na końcu” wynosi 0,45 kratki (ok. 14 px),
    więc palec w rękawicy łatwo przypnie kolano obok końca rury i take-out się nie odejmie. Wtedy zostaje
    tylko przerywany marker.
  - [potw.] Etykiety CUT na płótnie mają 11,5 px, a większość napisów 9–11 px.
  - [opinia] „Szczelina spoiny” i „Utwórz projekt CUT” są schowane w menu przepełnienia. Nowy szkic ma szczelinę 0,
    więc projekt powstaje z 0 i rury wychodzą o 2 × szczelinę za długie, dopóki monter nie znajdzie opcji.
  - [opinia] Długie przytrzymanie usuwa element od razu. Cofnij jest w SnackBarze przez 4 s, co jest OK,
    ale nie ma „Ponów”.
- **Brakujące funkcje:** trójnik redukcyjny (DN przelotu / odgałęzienia, C i M); wymuszony wybór DimRef przy
  kołnierzu / zaworze z opisem słownym i podglądem CUT każdej opcji (jak w przeglądzie skanu); kołnierze SO/LJ
  (wsunięcie); kolana SW/THD (luz 1,6 mm zamiast szczeliny); domyślna szczelina z ustawień; pinch-zoom;
  „otwórz skan jako szkic” (weryfikacja wizualna odczytu AI).
- **Testy:** `test/domain/iso_notebook/sketch_to_project_test.dart` (kolano–kolano, WN oś–koniec, trójnik, redukcja,
  gwint, niepewne odliczenia, CUT z bazy = CUT zeszytu, kolejność trasy),
  `test/screens/iso_notebook_create_project_test.dart`, `_takeouts_test`, `_sketch_codec_test`, `_autosave_test`.
  Brak testów dla: nieczytelnego wiersza odliczenia, ręcznego CTE przy kolanie bez specyfikacji, trójnika
  redukcyjnego, oletu w węźle, domyślnego DimRef przy kołnierzu.
- **Propozycje:**
  - [P1] [S] Przy fizycznym końcu (kołnierz / zawór / redukcja / zaślepka) wymusić wybór DimRef poza
    „Opcjami zaawansowanymi”, z opisem słownym („oś kolana → przylga kołnierza”) i CUT każdej opcji. Domyślnie
    proponować jak skaner (kołnierz → oś–koniec).
  - [P1] [S] Dialog: „OK” zablokowany, gdy którykolwiek wiersz odliczenia się nie parsuje. `_planOne`: skip
    z powodem „nieczytelne odliczenie”. Czerwony chip na liście.
  - [P1] [M] Trójnik: pole DN odgałęzienia (+ C/M z B16.9). Odnogę rozpoznawać geometrycznie (rura niewspółliniowa
    z pozostałymi dwiema = odgałęzienie → M).
  - [P2] [S] `sketchAxialTakeoutsFor`: najpierw rozliczyć wiersze ręczne z komponentami BEZ CTE, dopiero potem
    z automatycznymi.
  - [P2] [S] Olet w węźle dwóch współliniowych rur: bez odliczenia i bez szczeliny na przelocie (albo blokada
    z komunikatem „narysuj przelot jedną linią”).
  - [P2] [M] Pinch-zoom / dwupalcowe przesuwanie na płótnie. Pasek narzędzi 48 dp. Etykiety CUT ≥ 13 px.
  - [P3] [S] Szczelina i „Utwórz projekt CUT” jako widoczne przyciski w panelu statusu.

## iso-scanner — „Skaner izometryku”
- **Cel i dla kogo:** zdjęcie izometrii → odczyt AI (Claude) → przegląd → projekt CUT, mapa spoin, BOM, spoole,
  dziennik.
- **Co zawiera:** `lib/screens/iso_scanner_screen.dart` (2151 l.): wybór zdjęcia, zgoda i limit dzienny
  (`_ScanBudget`), wysyłka, pasek tabelki, stara lista odcinków z odliczeniami, kopiowanie, przejście do przeglądu.
  Dalej `lib/services/iso_scanner_ai.dart` (klient, model `AiScanResult`, parser tolerancyjny v1/v2) i backend
  `backend/src/services/fitterScan.js` (prompt schematu v2, 16k tokenów wyjścia, adaptacyjne myślenie, budżet).
- **Stan:** błędy. Ścieżka „projekt z przeglądu” jest poprawna, ale sam ekran skanera pokazuje drugi,
  nieuprawniony „CUT”.
- **Błędy potwierdzone:**
  - **[P1] Druga formuła CUT na ekranie skanera: ISO pokazane jako CUT.** Po odczycie AI `_applyAiResult`
    (l. 637–700) wpisuje wymiar każdego odcinka do starej listy `_Segment`. `_Segment.cutMm` (l. 157–173) = ISO −
    ręczne odliczenia, bez take-outów, szczeliny i silnika. Karta pokazuje pomarańczową pigułkę **„CUT 1200.0 mm”**
    (l. 1956–1966, 2127), nagłówek „Suma CUT”, a „Kopiuj zestawienie” wysyła do schowka „CUT LIST … 1200 = 1200.0 mm”
    (l. 1057–1095). Dla odcinka kolano–kolano z golden 01 prawdziwy CUT to 892 (przegląd), a ekran i schowek mówią
    1200. Wartości o niskiej pewności też są tam wpisywane (filtr tylko 0 < x < 100000). Łamie to „CUT liczy jeden
    silnik” i §2 p. 6.
  - [P2] Wynik skanu żyje tylko w pamięci (`_lastScan`, l. 202). Zabicie aplikacji albo powrót z „Odrzuć” oznacza
    utratę płatnego odczytu. Ponowny skan zużywa limit dzienny.
  - [P3] [opinia/ryzyko] `_jNum` → `parseDecimal` zamienia przecinek na kropkę. Gdyby model zwrócił
    `"dimensionMm": "1,500"` (separator tysięcy) albo `rawDimension` „1,500”, wyjdzie 1,5 mm. Przy odcinku
    otwarty–otwarty to dodatnie cięcie 1,5 mm. Brak progu „wymiar < 10 mm → blokada”.
- **Prompt (`fitterScan.js`) — uwagi:**
  - [opinia] `MAX_OUTPUT_TOKENS = 16 000` razem z myśleniem adaptacyjnym. Gęsty rysunek (30+ spoin, BOM) może
    przerwać JSON na `max_tokens`. Kod nie sprawdza `stop_reason === 'max_tokens'` i zwraca ogólne „parse_failed”,
    a limit zużyty.
  - [opinia] Brak wymuszonego schematu (structured outputs / tool). Parser jest tolerancyjny, ale to dodatkowa
    warstwa ryzyka.
  - [opinia] Prompt nie każe odczytać tabeli „CUT PIECES / cut lengths” z rysunków Isogen/SpoolGen. To najlepszy
    niezależny sprawdzian CUT, jaki monter ma na kartce.
  - [potw.] Słowo „FACE = czoło (przylga kołnierza)” w prompcie znaczy co innego niż „czoło” w pickerze
    (bliższe czoło). Patrz iso-notebook i scan-review.
- **Problemy UX w terenie:** [opinia] czcionki 10–11 px w większości etykiet ekranu. Dwie ścieżki wyjścia (kopiuj
  starą listę vs „Utwórz projekt z tego skanu” jako ikona w AppBarze) są mylące: najlepsza ścieżka jest najmniej
  widoczna. Jedno zdjęcie na skan, bez arkuszy 1/2, 2/2.
- **Brakujące funkcje:** zapis skanu (JSON + miniatura) przy projekcie; wieloarkuszowe ISO; odczyt tabeli cięć
  z rysunku i porównanie z CUT; „otwórz jako szkic w Zeszycie”.
- **Testy:** `test/services/iso_scanner_upload_test.dart`, `iso_scanner_ai_values_test.dart`,
  `iso_scan_schema_v2_test.dart`, `test/welder_journey_test.dart`. Brak testu widżetu, który po odczycie AI sprawdza,
  że ekran skanera NIE pokazuje ISO jako CUT. Brak testu liczb jako stringów z separatorem.
- **Propozycje:**
  - [P1] [M] Usunąć pigułkę „CUT” i „Suma CUT” ze starej listy po odczycie AI (albo przemianować na „ISO”).
    Kopiowanie zestawienia generować z planu `planFromScan` (te same CUT i blokady co przegląd). Przycisk
    „Sprawdź i utwórz projekt” jako główny, duży.
  - [P2] [S] Zapisywać ostatni `AiScanResult` (SharedPreferences / plik) i przywracać go po restarcie.
  - [P2] [S] Backend: przy `stop_reason === 'max_tokens'` zwrócić czytelny błąd („rysunek zbyt gęsty — przytnij
    do jednego spoola”) i nie liczyć go jak zwykłego skanu. Ewentualnie podnieść limit.
  - [P3] [S] `_jNum`: odrzucać stringi z przecinkiem i trzema cyframi po nim („1,500”) jako niejednoznaczne.
    Planista: wymiar < 10 mm → blokada `lowConfidence`.

## scan-review — „Sprawdź skan”
- **Cel i dla kogo:** ostatnia bramka między odczytem AI a projektem. Monter widzi każde cięcie z formułą,
  założeniami i blokadami, poprawia wymiary, DN, take-outy i odniesienia, a potem zapisuje projekt (i dziennik
  spoin).
- **Co zawiera:** `lib/screens/scan_review_screen.dart` (2461 l., zakładki), planista
  `lib/services/scan_to_project.dart` (3383 l.): graf trasy, DN per odcinek, take-outy B16.9/B16.11/B16.5/B16.10,
  offsety 3D, zamknięcia wymiarów. Do tego `scan_outputs.dart` (bramka `evaluateReview`, mapa spoin, BOM,
  spoole, dziennik), `scan_graph.dart`, `scan_geometry.dart`. Zapis przez `segmentRowFor` z wycofaniem przy błędzie.
- **Stan:** działa, z jednym poważnym założeniem (kołnierz bez typu). Logika blokad jest najstaranniejszą częścią
  grupy.
- **Weryfikacja ręczna złotego zestawu [potw.]** (wartości normowe B16.9: 90° LR NPS4 6,00" = 152,4;
  SR 4,00" = 101,6; 45° LR 2,50" = 63,5; tee C 4,12" ≈ 105; red. tee 4×3 M 3,88" = 98,6; red. H 4,00" = 101,6;
  WN Cl150 Y 3,00" = 76,2; zasuwa B16.10 9,00" = 228,6; B16.11 SW 3000 NPS1 A = 0,88" ≈ 22,4):
  - 01: 1500 − 152 − 2 = **1346**; 1200 − 304 − 4 = **892**; 700 − 152 − 2 = **546** ✓
  - 12: przelot 800 − 105 = **695**; odgałęzienie 500 − 98 = **402** ✓ (M 98,55 zaokrąglone w dół; 0,5 mm na
    bezpieczną stronę)
  - 16: √(500² + 300² + 400²) = 707,1; − 2 × 64 = **579,1**; kąt z kierunków 45° ✓
  - 19: 500 − (22,5 + 1,6) = **475,9**; 400 − 2 × 24,1 = **351,8** ✓
  - 06 / 15: 1000 − 152 − 76 = **772** (WN do przylgi) ✓; 08: 4'-6" = 1371,6 − 152 = **1219,6** ✓
- **Spójność między modułami (ta sama geometria):**

  | Geometria (DN100, szczelina 3) | Kreator segmentu | Zeszyt | Przegląd skanu | Ekran skanera |
  |---|---|---|---|---|
  | kolano–kolano, ISO 1200 CTC | 890 | 890 | 890 | **1200** (P1) |
  | kolano → WN do przylgi, ISO 1000 | 766 (FACE_FAR domyślnie, wg komentarza `scan_to_project.dart:2820`; nie sondowane) | **842** domyślnie (P1) | 766 po potwierdzeniu | **1000** |
  | trójnik 150×80 → odgał. DN80 + kolano, ISO 1000 | — (poza zakresem G3) | **743** (P1) | 756 (M) | **1000** |
  | kolano bez LR/SR | — | brak CTE → blokada projektu | LR 152 + ostrzeżenie | — |

  Kolumna „Kreator segmentu” pochodzi z testu `sketch_to_project_test` („CUT z bazy == CUT zeszytu”) i komentarzy
  w kodzie. Kreatora nie sondowałem osobno (grupa G1).

- **Błędy potwierdzone:**
  - **[P1] Kołnierz bez `flangeType` przyjmowany po cichu jako WN (−Y).** `_endpoint` (l. 2817):
    `tool == 'flange' && !_isSlipOnLike` → `proposedStop = end`, więc `isWeldNeckFlange == true` (l. 414).
    W `_drawingStop` (l. 1549–1553) FACE na takim kołnierzu daje od razu stop „end” z Y z tabeli, bez
    potwierdzenia i bez ostrzeżenia. Sonda `scan_probe_test`: golden 15 z usuniętym `flangeType` i etykietą
    „FLG RF 150#” → s1 = **772**, s2 = **472**, `needsConfirm=false`, `gaps=[]`, brak ostrzeżenia o założeniu
    (dla porównania trójnik ma `teeAssumedEqual`, kolano `takeoutAssumedLongRadius`). Jeśli to w rzeczywistości
    kołnierz SO (wsuwany), rura wychodzi o ok. 76 − (wsunięcie) ≈ **55–65 mm za krótka**. Z jawnym `SO` planista
    poprawnie blokuje (sonda „15 SO”).
  - **[P1] Rozbieżność `rawDimension` ↔ `dimensionMm` jest ignorowana.** `scan_to_project.dart:1216–1230`: tekst
    z rysunku parsuje się tylko wtedy, gdy liczby brak. Sonda: s2 `dimensionMm 1200`, `rawDimension "1250"`,
    pewność high → CUT **892** (z 1200), bez żadnej blokady. Prompt każe modelowi samemu przeliczać stopy i cale
    (golden 08), więc błędne przeliczenie przy poprawnym `rawDimension` przejdzie po cichu. To dokładnie ten
    przypadek, który deterministyczna warstwa (§2 p. 4) powinna złapać.
  - [P2] Pewność „medium” nigdy nie blokuje ani nie jest wyróżniona. Blokada jest tylko dla low / unknown
    (l. ~1300). W `scan_review_screen.dart` nie ma żadnej obsługi `medium`, a prompt definiuje medium jako
    „lekko nieczytelna”. Sonda: s2 medium → CUT 892 zapisywalne bez śladu.
- **Problemy UX w terenie:**
  - [potw.] Ekran przeglądu nie pokazuje zdjęcia rysunku (brak `Image`/`InteractiveViewer` w
    `scan_review_screen.dart`). Komunikaty każą „sprawdzić na rysunku”, więc trzeba wracać do poprzedniego ekranu.
  - [opinia] W pickerze „Jak zmierzono wymiar?” są etykiety `oś-czoło` / `oś-koniec` z CUT każdej opcji (dobrze).
    Dla kołnierza „oś-czoło” znaczy jednak „do końca piasty”, a monter czyta „czoło kołnierza” = przylga.
    Trzeba to opisać słowami przy kołnierzu: „do przylgi (−Y)”, „do spoiny (bez Y)”.
  - [opinia] Czcionki 12–12,5 px dla większości treści. Blokady są czytelne kolorem.
- **Brakujące funkcje:** podgląd zdjęcia z przybliżeniem na wymiar; zapis zdjęcia / odczytu przy projekcie
  (identyfikowalność QC); kołnierze SO/LJ z wpisem wsunięcia; porównanie z tabelą cięć z rysunku.
- **Testy:** `test/golden_iso/golden_iso_test.dart` (19 przypadków, zapis do bazy i ponowne przeliczenie z wiersza),
  `test/services/scan_to_project_test.dart`, `scan_outputs_test.dart`, `scan_graph_test.dart`,
  `scan_geometry_test.dart`, `material_list_topology_test.dart`, `test/screens/scan_review_*_test.dart` (6 plików).
  Pokrycie bardzo dobre dla scenariuszy „szczęśliwych” i blokad. Braki:
  - kołnierz bez typu;
  - rozbieżność raw/dim;
  - pewność medium;
  - separator tysięcy;
  - wszystkie przypadki są ręcznie pisanymi kopertami, nie ma ani jednego prawdziwego zdjęcia (znane ograniczenie
    z audytu 08-30, nadal otwarte).
- **Propozycje:**
  - [P1] [S] Kołnierz bez `flangeType` (i bez WN/SO w etykiecie): ostrzeżenie `flangeAssumedWeldNeck` oraz blokada
    `dimensionReferenceUnknown`, także gdy model podał FACE z wysoką pewnością. WN jest najczęstszy, ale różnica
    SO/WN to kilkadziesiąt mm na minus.
  - [P1] [S] Gdy `rawDimension` daje się sparsować (UnitParser / parseIsoExpression) i różni się od
    `dimensionMm` o więcej niż 0,5 mm → blokada `lowConfidence` z obiema wartościami do wyboru.
  - [P2] [S] Pewność medium: co najmniej żółte podświetlenie wymiaru i licznik „do rzutu oka”. Rozważyć blokadę
    zgodnie z §2 p. 6.
  - [P2] [M] Panel ze zdjęciem (InteractiveViewer) nad listą, z możliwością zwinięcia.
  - [P2] [M] Golden set: dodać co najmniej 3 prawdziwe zdjęcia izometrii (od właściciela) z oczekiwaną listą cięć.
    Dodać przypadki kołnierza bez typu, raw ≠ dim i medium.

---

## Top 5 w grupie
1. **[P1] Ekran skanera pokazuje ISO jako „CUT”** i kopiuje „CUT LIST” bez take-outów i szczeliny (druga formuła,
   `iso_scanner_screen.dart:157–173, 637–700, 1057–1095, 1956–1966`). Kolano–kolano 1200 ISO: ekran 1200,
   przegląd 892. [M]
2. **[P1] Zeszyt: kołnierz / zawór na końcu liczony domyślnie „oś-oś”, wybór DimRef schowany** w „Opcjach
   zaawansowanych” i opisany samymi kodami. Kolano → WN do przylgi daje 842 zamiast 766 (+76 mm), a projekt CUT
   powstaje bez uwagi. Skaner w tej samej sytuacji blokuje. [S]
3. **[P1] Planista skanera: kołnierz bez typu = WN po cichu**, a FACE z wysoką pewnością odejmuje Y bez
   potwierdzenia. Przy kołnierzu SO rura wychodzi ok. 60 mm za krótka. Dodać ostrzeżenie i blokadę. [S]
4. **[P1] Zeszyt: trójnik ma jeden CTE, więc odgałęzienie trójnika redukcyjnego jest liczone z C zamiast M.**
   DN150×80: 743 zamiast 756 (−13 mm, złom). Skaner liczy M poprawnie. [M]
5. **[P1] Niepewne liczby przechodzą w CUT bez sygnału:** nieczytelny wiersz odliczenia w zeszycie znika
   („3+” → CUT bez odliczenia, projekt tworzony), a w skanerze `rawDimension` ≠ `dimensionMm` nie jest
   porównywane (1250 vs 1200 → CUT z 1200). Oba łamią §2 p. 6. [S + S]

Dalej w kolejce (P2): ręczny CTE kolana „zjada” automatyczny CTE drugiego kolana (+152 mm); olet w węźle
przelotu skraca rurę główną; pinch-zoom i 48 dp w zeszycie; skan tylko w pamięci; tabela rzędnych i dowolny kąt
w szablonie siodła; set-on po ID oraz otwór w rurze głównej w obu narzędziach siodła.

## Źródła i artefakty
- ASME B16.9 (kolana LR/SR, trójniki C/M, redukcje H), B16.5 (WN Y), B16.10 (zasuwa FTF), B16.11 (SW A): wartości
  jak w polu `drawing` złotego zestawu i w `lib/services/takeout_catalog.dart`, sprawdzone w calach (patrz wyżej).
- Siodło: wyprowadzenie w komentarzu `saddle_geometry.dart:15–20`, sprawdzone niezależnie (`saddle2.py`,
  `saddle_check.dart` w scratchpadzie sesji).
- Sondy: `sketch_probe_test.dart` (A–G) i `scan_probe_test.dart` w scratchpadzie sesji (nie w repo). Uruchamiane
  `flutter test --no-pub <plik>` z katalogu projektu.
