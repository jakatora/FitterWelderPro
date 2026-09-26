# G2 — Kalkulatory montera: przegląd modułów

Data: 2026-09-26 · gałąź `fix/audyt-2026-08-29` (HEAD `40f254e`, release 0.3.0+17) · przegląd tylko do odczytu.

Zakres: `fitter-tools` (8 zakładek), `elbow-takeout`, `dn-mm`, `pipe-schedule`, `rolling-offset`, `pipe-slope`,
`pipe-route-calculator`, `quick-converter`, `support-config`, `sanitary-tube` oraz dane `lib/data/*`
i `lib/services/takeout_catalog.dart`.

Metoda: czytanie kodu, ręczne przeliczenie przykładów (skrypt w scratchpadzie, wyniki podane niżej),
sprawdzenie wartości normowych w źródłach sieciowych (linki w sekcji „Źródła”). Uruchomiono 14 plików
testów tej grupy: **146 testów, wszystkie zielone**.

Oznaczenia: **[potw.]** = błąd potwierdzony przeliczeniem/źródłem; **[opinia]** = ocena montera/UX.
Wartości już naprawione w serii 24–25.09 (Δh = D·tan α, take-outy B16.9 SR/LR/3D, tee DN100 = 105,
zaślepki E, kołnierze C/Y, zawory B16.10, DN20 LR90 = 38) nie są tu powtarzane. Sprawdziłem je
przy okazji i są zgodne.

---

## fitter-tools — „Kalkulatory montera” (kontener 8 zakładek)
- **Cel i dla kogo:** zestaw szybkich kalkulatorów geometrycznych dla montera rur i spawacza na budowie.
- **Co zawiera:** `lib/screens/fitter_tools_screen.dart` (1609 linii), `DefaultTabController` z 8 zakładkami.
  Każda zakładka ma też własny kafelek w `lib/widgets/tool_registry.dart` (`initialTab` 0–7). Pomoc: `kHelpFitterTools`.
- **Stan:** działa. Błędy siedzą w poszczególnych zakładkach, opisanych niżej.
- **Błędy potwierdzone:**
  - [potw.] Pomoc jest nieaktualna: `lib/widgets/help_button.dart:325` mówi „Wstawka — oblicz długość odcinka
    między dwoma kołnierzami/czołami”. Zakładka liczy tymczasem wstawkę między **dwoma kolanami** w odsadzce.
    Linia 324 opisuje „Obrót kolanka” jako „% / ° obrotu dla odejścia bocznego”, a zakładka przelicza obrót
    na długość łuku po obwodzie. W krokach pomocy brakuje zakładek Ciężar, Fazowanie i Dylatacja.
- **Problemy UX w terenie:**
  - [opinia] Nazwy są niespójne: kafelek nazywa się „Cięcie pod spadek”, a zakładka „Spadek”. W aplikacji jest też
    osobny ekran „Spadek rury” (`pipe-slope`), więc monter myli jedno z drugim.
  - [opinia] Wyniki odświeżają się na żywo (dobrze), ale w innych ekranach grupy trzeba nacisnąć OBLICZ.
    Zachowanie jest niespójne w obrębie grupy.
  - [opinia] Etykiety wyników mają 13 px w kolorze `#78909C`, a tekst pomocniczy 11–12 px `#546E7A`. W słońcu
    jest to słabo czytelne; wynik główny (26 px, pomarańczowy) jest w porządku.
  - [opinia] Stan zakładek nie jest zapisywany. Przejście na inny ekran i powrót czyści wszystkie pola.
- **Brakujące funkcje:** [opinia] wspólny wybór „DN + schedule” podpowiadający OD/t w każdej zakładce (dane
  są w `pipe_schedules.dart`); przycisk „Wyczyść” w zakładkach.
- **Testy:** `test/screens/fitter_tools_calcs_test.dart` pokrywa tylko Spadek i Wstawkę. Pozostałe 6 zakładek
  nie ma żadnego testu.
- **Propozycje:**
  - [P2][S] Poprawić `kHelpFitterTools`: Wstawka = między 2 kolanami, Obrót = długość łuku, dopisać 3 brakujące zakładki.
  - [P3][S] Ujednolicić nazwę „Cięcie pod spadek” (kafelek, zakładka, pomoc).
  - [P3][M] Zapamiętywać wpisane wartości per zakładka (jak w `pipe-route`).

## fitter-tools / zakładka 0 — „Spadek” (cięcie pod spadek)
- **Cel i dla kogo:** jedno cięcie końca rury na skos, żeby rura podeszła pod spadek p % (np. do pionowej ścianki lub kołnierza).
- **Co zawiera:** wejście D (OD) i spadek %; wynik α = atan(p/100), „kąt piły” 90° − α, Δh = D·tan α.
  Kod: `slopeCutDeltaMm` (l. 25), `_SlopeTabState` (l. 224–316).
- **Stan:** działa, wzór jest poprawny.
- **Ręczne przeliczenie:** D 114,3, 2 % → α 1,146°, Δh = 2,286 mm, 90 − α = 88,854°. Kod daje to samo.
  D 200, 50 % → 100,00 mm (zgodne z testem).
- **Błędy potwierdzone:** brak błędów w wyniku.
- **Problemy UX w terenie:**
  - [opinia, istotne] „Kąt cięcia na pile (90° − α)” = 88,85°. Na typowej pile taśmowej lub ukośnicy skala ma
    **0° = cięcie prostopadłe**, więc trzeba ustawić **α = 1,15°**, a nie 88,85°. Podpowiedź „utnij na pile 88.85°”
    (l. 267) może skończyć się ustawieniem piły prawie wzdłuż rury albo zupełnie złym cięciem. Bezpieczniej pokazać
    oba zapisy: „odchylenie od prostopadłej α = 1,15° (skala 0°) / 88,85° (skala 90°)”.
  - [opinia] Ujemny spadek jest przyjmowany (formatter bez minusa, ale wklejenie działa); p = 0 daje Δh = 0 bez komentarza. To w porządku.
- **Brakujące funkcje:** spadek wpisywany jako 1:x lub mm/m (w terenie częściej „10 mm/m” niż „1 %”).
- **Testy:** 2 testy (czysta funkcja i widget). Nie ma testu kąta piły.
- **Propozycje:**
  - [P2][S] Kąt piły: pokazać α jako „od prostopadłej (0° = prosto)” i 90 − α tylko z dopiskiem skali.
  - [P3][S] Dodać wejście „mm/m” lub „1:x”.

## fitter-tools / zakładka 1 — „Cięcie kolanka”
- **Cel i dla kogo:** docięcie kolana 90° (lub 45°) do dowolnego kąta przez pomiar taśmą po łuku zewnętrznym i wewnętrznym.
- **Co zawiera:** baza 90/45, długi bok L (extrados), krótki S (intrados), kąt docelowy T. Wynik:
  L·T/θ, S·T/θ, pozostałość i „OD wyliczone” = (L − S)/θ_rad. Kod: l. 326–643.
- **Stan:** działa, geometria łuku jest poprawna.
- **Ręczne przeliczenie:** DN50 LR (R 76, OD 60,3): extrados 166,74, intrados 72,02; cel 60° → L_cut 111,16,
  S_cut 48,01; OD kontrolne 60,30. Kod daje to samo.
- **Błędy potwierdzone:** brak.
- **Problemy UX w terenie:**
  - [opinia] Przykłady w polach „141.4 / 70.7” dają OD 45 mm, czyli żadną typową rurę. Lepiej użyć realnych
    liczb, np. DN50 LR 166,7 / 72,0.
  - [opinia] „OD wyliczone” jest tylko informacyjne. Brakuje pola „OD rury” z ostrzeżeniem, gdy pomiar odbiega
    o więcej niż ok. 3 %. To najczęstsza pomyłka: taśma poszła nie po extradosie.
  - [opinia] Nie ma uwagi o rzazie. Tnie się po stronie odpadu, inaczej kąt wychodzi o ok. 1° za mały przy małych DN.
  - [opinia] Kolana 45° wg B16.9 mają krótkie odcinki proste na końcach: B = 35 mm, a R·tan22,5° = 31,5 dla DN50.
    Proporcja łuku daje wtedy błąd ok. 1 mm. Warto dopisać to do opisu.
- **Brakujące funkcje:** tryb „z tabeli” (wybierz DN/LR/SR → extrados i intrados wyliczone bez taśmy);
  take-out nowego kolana R·tan(θ/2), potrzebny do dalszego liczenia wstawki.
- **Testy:** brak.
- **Propozycje:**
  - [P2][M] Tryb DN + typ kolana (dane `kElbowTakeouts`) zamiast pomiaru. Wynik: extrados, intrados, oś i take-out po cięciu.
  - [P3][S] Pole OD z kontrolą zgodności pomiaru; uwaga o rzazie.
  - [P2][S] Testy jednostkowe (wyciągnąć funkcję czystą jak `insertBetweenElbows`).

## fitter-tools / zakładka 2 — „Obrót kolanka”
- **Cel i dla kogo:** przeliczenie obrotu (w % lub stopniach) na odległość do odmierzenia po obwodzie rury.
- **Co zawiera:** OD lub obwód, % lub °; wynik = obwód·°/360. Kod: l. 702–826.
- **Stan:** częściowo (jeden błąd brzegowy).
- **Ręczne przeliczenie:** OD 60,3, 90° → 47,36 mm; 25 % → to samo. Zgodne.
- **Błędy potwierdzone:**
  - [potw.] `fitter_tools_screen.dart:734–738`: wpisanie **obwodu „0”** przy poprawnym OD daje wynik
    **0,0 mm**, bez błędu. Warunek przepuszcza circ = 0, bo OD jest poprawne, a `circ ??=` nie nadpisuje zera.
    Oczekiwane: obliczenie z OD albo komunikat.
  - [potw., drobny] Kąt powyżej 360° lub % powyżej 100 przechodzi bez ostrzeżenia (np. 400° → 1,11 obwodu).
- **Problemy UX w terenie:**
  - [opinia] Gdy wpisane są % i °, stopnie wygrywają po cichu. Pole %, które jest ignorowane, nie jest wyszarzone.
  - [opinia] Zaraz po wpisaniu OD pojawia się czerwony błąd „Podaj % obrotu albo stopnie”, choć użytkownik jeszcze nie skończył wpisywać.
- **Brakujące funkcje:** powiązanie z Rolling Offset (obrót od pionu → mm po obwodzie jednym dotknięciem);
  podział obwodu na 4/8 znaków (ćwiartki), którymi monter i tak znaczy rurę.
- **Testy:** brak.
- **Propozycje:**
  - [P3][S] Traktować circ ≤ 0 jak puste; ostrzeżenie dla > 360° lub > 100 %.
  - [P3][M] Przycisk „przelicz obrót z Rolling Offset” oraz znaki ćwiartek.

## fitter-tools / zakładka 3 — „Wstawka” (odsadzka na dwóch kolanach)
- **Cel i dla kogo:** długość rury między dwoma jednakowymi kolanami θ w odsadzce (offset).
- **Co zawiera:** tryb 1D/1.5D/3D (ASME B16.9 z `b169ElbowTakeout`) lub ręczne R; OD, θ, offset.
  Travel = offset/sin θ, wstawka = travel − 2T. Kod: l. 835–1198.
- **Stan:** działa, liczy poprawnie. Brakuje szczeliny spoiny.
- **Ręczne przeliczenie:** OD 60,3, 45° LR, offset 300 → T = B = 35, travel 424,26, wstawka 354,26
  (zgodne z testem). Tryb ręczny R 90,45 → 349,3 (test).
- **Błędy potwierdzone:**
  - [potw.] Szczelina spoiny nie jest odejmowana, a w UI nie ma na nią pola. Komentarz w kodzie przyznaje to
    wprost (l. 33–34, „weld gaps not deducted”); na ekranie tej informacji nie ma (l. 1130). Wstawka ma 2 spoiny
    doczołowe, więc przy szczelinie 2–3 mm rura wychodzi o **4–6 mm za długa**. Rolling Offset tę szczelinę
    już odejmuje (`rollingCutLengthMm`), więc dwa ekrany liczą to samo różnie.
- **Problemy UX w terenie:**
  - [opinia] Podpowiedź „np. 60.3” nie jest tłumaczona (l. 1050); drobiazg.
  - [opinia] Brak wyniku „run / setback” (offset/tan θ), czyli gdzie wzdłuż rury stoi drugie kolano. Monter potrzebuje go do trasowania.
- **Brakujące funkcje:** pole szczeliny; run; wybór DN z listy zamiast wpisywania OD.
- **Testy:** dobre, 6 przypadków (tabele A/B, segment, OD spoza serii, SR DN15, tryb ręczny).
- **Propozycje:**
  - [P1][S] Dodać pole „Szczelina spoiny” (domyślnie 0, jak w Rolling Offset) i wynik „do cięcia = travel − 2T − 2g”.
  - [P2][S] Pokazać run = offset / tan θ.

## fitter-tools / zakładka 4 — „Redukcja” (skracanie redukcji)
- **Cel i dla kogo:** gdzie uciąć redukcję koncentryczną, żeby uzyskać pośrednią średnicę.
- **Co zawiera:** D1, D2, L, D docelowe; x = L·(D_duże − D)/(D_duże − D_małe). Kod: l. 1207–1310.
- **Stan:** działa matematycznie, ale model jest uproszczony.
- **Ręczne przeliczenie:** 114,3 × 60,3, H = 102 (B16.9 DN100×50), cel 88,9 → 47,98 mm od dużego końca. Zgodne z kodem.
- **Błędy potwierdzone:** brak błędu obliczenia.
- **Problemy UX w terenie:**
  - [opinia, istotne] Model zakłada stożek na **całej** długości L. Redukcje B16.9 i EN 10253 mają na obu końcach
    krótkie odcinki cylindryczne (pod fazę), a producenci różnią się ich długością. Wynik bywa przesunięty
    o kilka mm. Warto dodać ostrzeżenie „zmierz długość części stożkowej”.
  - [opinia] Nie wiadomo, czy średnice to OD czy ID. Przy docinaniu liczy się OD pod fazę; trzeba to napisać.
  - [opinia] Brak opisu zakładki (`_SectionDesc`) i brak rysunku.
- **Brakujące funkcje:** pole „długość części stożkowej”; redukcja mimośrodowa (wynik jest ten sam, ale warto to napisać).
- **Testy:** brak.
- **Propozycje:**
  - [P2][S] Ostrzeżenie o częściach cylindrycznych i opcjonalne pole długości stożka; etykiety „OD”.
  - [P3][S] Test jednostkowy.

## fitter-tools / zakładka 5 — „Ciężar rury”
- **Cel i dla kogo:** kg/m, masa odcinka i partii (dźwig, transport, podpory).
- **Co zawiera:** SS 7930 / CS 7850 / Al 2700 kg/m³, OD, t, długość, ilość; m = ρπ(OD − t)t. Kod: l. 1320–1407.
- **Stan:** działa. Gęstość SS jest przypisana niewłaściwemu gatunkowi.
- **Ręczne przeliczenie:** CS 60,3 × 3,91 → 5,437 kg/m (B36.10 / tabela PHD: 5,43–5,44). Zgodne.
- **Błędy potwierdzone:**
  - [potw., drobny] `l. 1332, 1367`: „SS 316L: ρ = 7 930 kg/m³”. Dla 1.4404 / 316L EN 10088-1 i karty
    producentów podają **8,0 kg/dm³**; 7,93 to wartość dla 304. Masa dla 316L wychodzi o ok. 0,9 % za niska
    (60,3 × 3,91: 5,49 zamiast 5,54 kg/m).
  - [potw., drobny] Puste pole długości lub ilości daje po cichu 1000 mm / 1 szt., a etykieta pokazuje surowy tekst
    („Odcinek  mm”, l. 1398). Można też wpisać ułamkową ilość sztuk.
- **Problemy UX w terenie:** [opinia] trzeba ręcznie wpisać OD i t, chociaż tabela schedule jest w aplikacji.
- **Brakujące funkcje:** wybór DN + Sch; masa z wodą (próba ciśnieniowa, podpory); 304 i 316 osobno.
- **Testy:** brak.
- **Propozycje:**
  - [P3][S] Rozdzielić „SS 304 7,93” i „SS 316/316L 8,00”.
  - [P2][M] Wybór DN/Sch (z `kPipeWalls`) i dodatkowy wynik „z wodą”.

## fitter-tools / zakładka 6 — „Fazowanie”
- **Cel i dla kogo:** geometria fazy V lub X: głębokość, szerokość na powierzchni, szerokość rowka.
- **Co zawiera:** t, α (domyślnie 37,5), próg b (1,0), szczelina g (0), typ V/X; h = t − b, w = h·tan α.
  Kod: l. 1417–1502.
- **Stan:** **błędy.**
- **Ręczne przeliczenie:** t 20, b 2, α 30 → V: h 18, w 10,39 mm (kod zgodny).
- **Błędy potwierdzone:**
  - [potw.] **Złącze X: szerokość fazy jest 2× za duża.** `l. 1447` liczy w = (t − b)·tan α także dla X.
    W złączu X każda strona ma głębokość (t − b)/2, a kod sam to wypisuje w l. 1493. Dla t 20, b 2, α 30:
    ekran pokazuje **10,39 mm** jako wynik główny, poprawnie jest **5,20 mm** na stronę. „Szerokość otworu złącza”
    (l. 1492) jest przez to także 2× za duża.
  - [potw.] **Kąt α jest niejednoznaczny względem powołanej normy.** Opis „Geometria fazy wg EN ISO 9692” (l. 1456,
    oraz kafelek) zestawiony z „Kąt α, typowo 30–37.5°” (l. 1471). W EN ISO 9692-1 dla złącza V podaje się
    **kąt rowka (całkowity)**, typowo 60° ±5°. 37,5° na stronę (75° całkowity) to konwencja ASME B16.25.
    Monter, który przepisze z WPS „α = 60°”, dostanie szerokość **3× za dużą** (t 10, b 1: 15,59 zamiast 5,20 mm).
  - [potw., drobny] Czyszczenie pól daje ciche wartości domyślne: pusta szczelina daje g = **2** w szerokości
    rowka (l. 1492), chociaż pole domyślnie ma „0”. Puste α daje 37,5, pusty próg daje 1,0.
  - [potw., drobny] α ≥ 90° nie jest walidowane (tan → ogromna lub ujemna liczba).
  - [potw., drobny] Etykiety listy „V — jednofazowe (typowe TIG)”, „X — dwustronne” są tylko po polsku (l. 1461–1462).
- **Problemy UX w terenie:** [opinia] brak rysunku z oznaczeniem α, b, g; brak informacji, że dla ścianki
  powyżej 22 mm B16.25 wymaga fazy złożonej (37,5° / 10°).
- **Brakujące funkcje:** faza złożona (J lub 37,5/10°); szacunek objętości spoiny i masy spoiwa (w aplikacji są inne
  kalkulatory spawacza, można je podlinkować).
- **Testy:** brak. Błąd X przeszedłby niezauważony.
- **Propozycje:**
  - [P1][S] X: w = (t − b)/2 · tan α na stronę; szerokość rowka = g + 2w (liczone na stronę).
  - [P1][S] Jawny wybór konwencji: „kąt fazy na stronę (ASME B16.25, 37,5°)” albo „kąt rowka całkowity (ISO 9692-1, 60°)”.
    Liczyć z właściwej połowy.
  - [P3][S] Walidacja 0 < α < 60, brak cichych wartości domyślnych, tłumaczenie etykiet; testy V/X.

## fitter-tools / zakładka 7 — „Dylatacja”
- **Cel i dla kogo:** wydłużenie cieplne ΔL = α·L·ΔT.
- **Co zawiera:** materiały 316L 16,0 / 304L 17,2 / CS 12,0 / CuNi 17,0 / Al 23,6 ×10⁻⁶; L w m; T1/T2 (ze znakiem)
  lub ΔT. Kod: l. 1512–1608.
- **Stan:** działa. Współczynnik dla 304L pochodzi z innej konwencji niż dla 316L.
- **Ręczne przeliczenie:** CS, 50 m, ΔT 100 → 60,0 mm. Zgodne.
- **Błędy potwierdzone:**
  - [potw., drobny] `l. 1524`: 304L = 17,2 ×10⁻⁶, a 316L = 16,0. Dla 1.4307 (304L) karty EN 10088 podają
    **16,0 ×10⁻⁶ /K (20–100 °C)**, tak samo jak dla 316L. 17,2 to wartość z danych amerykańskich (0–100 °C).
    Dla 50 m i ΔT 100 wynik to 86 zamiast 80 mm (+7,5 %; błąd bezpieczny, ale niespójny).
- **Problemy UX w terenie:**
  - [opinia] L jest w **metrach**, a we wszystkich innych zakładkach w mm. Sufiks „m” jest widoczny, ale łatwo się pomylić.
  - [opinia] „> 30 mm, wymagana kompensacja” to reguła kciuka, a nie norma. Lepiej: „sprawdź z projektem lub stress engineerem”.
  - [opinia] Współczynnik średni rośnie z temperaturą (CS przy ok. 300 °C to ok. 13 ×10⁻⁶). Dla pary i gorących linii wynik jest zaniżony; brak takiej uwagi.
- **Brakujące funkcje:** α zależne od temperatury (tabela ASME B31.3 App. C lub EN 13480); wstępny naciąg
  (cold pull, 50 %); długość ramienia kompensacyjnego L-bend lub liry.
- **Testy:** brak.
- **Propozycje:**
  - [P3][S] 304L = 16,0 (EN 10088) albo jawny opis źródła „ASTM, 0–100 °C”.
  - [P3][M] α(T) z tabeli i uwaga o temperaturze pracy.

---

## elbow-takeout — „Wymiary kolan (centre–face)”
- **Cel i dla kogo:** ściąga take-outów kolan doczołowych B16.9 (LR 90°, SR 90°, LR 45°).
- **Co zawiera:** `lib/screens/elbow_takeout_screen.dart`, dane `lib/data/elbow_takeouts.dart` (DN15–DN600, także
  kolumny 3D), wyszukiwarka, kopiowanie przytrzymaniem.
- **Stan:** dane poprawne. Wyszukiwarka ma błąd.
- **Wartości sprawdzone:** LR90, SR90 (od NPS 1), LR45 zgodne z B16.9 (np. DN50: 76 / 51 / 35; DN100: 152 / 102 / 64).
- **Błędy potwierdzone:**
  - [potw.] **Szukanie „2"” nic nie znajduje**, choć podpowiedź w polu brzmi „Szukaj: DN50, 2", 100…” (l. 73).
    Filtr (l. 45–48) porównuje z `e.nps = '2'` bez znaku cala. To samo dotyczy „1 1/2"” i „DN 50” ze spacją.
  - [potw., drobny] Gdy nic nie pasuje, lista jest po prostu pusta. Nie ma komunikatu „brak wyników”.
- **Problemy UX w terenie:** [opinia] 4 kolumny po 16 px są czytelne. Kolumny 3D są w danych, ale ekran ich nie pokazuje.
- **Brakujące funkcje:** kolumny 3D 90°/45°; kolano 180° (return, wymiar O/K); kolana kielichowe B16.11
  (dane `socketWeld90A3000` itd. już są w `takeout_catalog.dart`).
- **Testy:** dane dobrze pokryte (`elbow_takeouts_test.dart`, `takeout_catalog_test.dart`); ekran i wyszukiwarka bez testu.
- **Propozycje:**
  - [P2][S] Normalizować zapytanie: usuwać `"`, spacje i przedrostek „dn”. Dodać komunikat „brak wyników”. Dodać test widgetu.
  - [P3][S] Pokazać kolumny 3D i B16.11 SW.

## dn-mm — „DN-MM”
- **Cel i dla kogo:** przelicznik DN ↔ NPS ↔ OD (ASME i EN 10220 serie 1/2/3) i promień kolana LR.
- **Co zawiera:** `lib/screens/dn_mm_screen.dart`, dane `lib/data/nps_dn_od_r.dart`; pola DN (całkowite), OD (±0,25 mm), szukaj.
- **Stan:** działa.
- **Ręczne przeliczenie:** DN100 → 114,3, R 152,4, „ASME / EN s.1” (test); OD 101,6 → DN90; OD 26,9 pokazuje
  26,7 (ASME) i 26,9 (EN). Przy tolerancji 0,25 to akceptowalne i nawet pomocne.
- **Błędy potwierdzone:**
  - [potw., drobny] Kolumna R pokazuje przeliczenie calowe (38,1 / 57,15 / 95,25 / 228,6 / 304,8 / 457,2),
    a ekran „Wymiary kolan” i B16.9 (kolumny metryczne) podają 38 / 57 / 95 / 229 / 305 / 457. Ta sama wielkość
    ma w aplikacji dwie wartości (różnica ≤ 0,4 mm).
  - [potw., drobny] Pole „Szukaj” porównuje `odMm.toString()`, więc wpisanie „60,3” (z przecinkiem) nie znajduje rury.
    Pole OD przecinek obsługuje.
- **Problemy UX w terenie:** [opinia] DataTable z 5 kolumnami ma domyślną wysokość wiersza, jest czytelna.
  W polu DN nie da się wpisać „DN50” (filtr cyfr), co jest w porządku.
- **Brakujące funkcje:** grubości ścianek EN 10220 dla serii 1 (typowe 2,6 / 2,9 / 3,6 w Europie), bo dziś jest tylko ASME Sch.
- **Testy:** `dn_mm_screen_test.dart` (2), `nps_dn_od_r_test.dart` (10). Brak testu przecinka w szukaniu.
- **Propozycje:**
  - [P3][S] R z B16.9 metrycznej (`kElbowTakeouts.lr90`) dla serii ASME/EN1; przecinek w szukaniu przez `parseDecimal`.

## pipe-schedule — „Grubości ścianek / Sch”
- **Cel i dla kogo:** grubość ścianki i kg/m wg ASME B36.10M/B36.19M dla odczytu z ISO („DN50 Sch80”).
- **Co zawiera:** `lib/screens/pipe_schedule_screen.dart`, `lib/data/pipe_schedules.dart` (DN15–DN600; 10S, STD,
  40, 80, 160, XS, XXS), przełącznik mm ↔ kg/m, CS ↔ SS, zapamiętywany.
- **Stan:** częściowo. Wartości, które są, sprawdziłem wyrywkowo (10S, 40, 80, 160, XXS dla wszystkich DN): **zgodne**.
  Brakuje jednak kolumn stali nierdzewnej i średnicy wewnętrznej.
- **Błędy potwierdzone:**
  - [potw.] **Brak 40S/80S przy przełączniku „SS”.** Dla NPS 10 i 12 B36.19M różni się od B36.10M:
    **40S NPS 12 = 9,53 mm** (Sch 40 = 10,31), **80S NPS 10 i 12 = 12,70 mm** (Sch 80 = 15,09 / 17,48).
    Dla NPS 14–24 40S = 9,53. Nierdzewkowiec, który czyta „40” przy włączonym SS, dostaje ściankę i masę
    stali węglowej: 12" 80,5 zamiast 74,6 kg/m (+8 %), a ścianka jest o 0,8 mm za gruba (faza, dobór prądu).
  - [potw.] **Brak ID.** Scenariusz manifestu brzmi „NPS 2 Sch 40 pokazuje grubość ścianki i średnicę wewnętrzną”.
    Ekran pokazuje tylko ściankę albo kg/m, ID nigdzie się nie pojawia.
  - [potw.] **Szukanie „2"” zwraca „Brak wyników”**, a komunikat pustego wyniku sam radzi „Spróbuj: DN50, 2", 100”
    (l. 69–72, 94, 161). Przyczyna jak w `elbow-takeout`.
  - [potw., drobny] Gęstość SS 7,93 jest za niska dla 316/316L (8,0), patrz „Ciężar rury”.
  - [potw., drobny] Kolumna „10S” jest liczona i pokazywana także w trybie CS, a to oznaczenie istnieje tylko dla stali nierdzewnej.
- **Problemy UX w terenie:** [opinia] 7 kolumn + 70 px na telefonie 360 dp daje ok. 34 px na kolumnę przy tekście
  12 px. W słońcu i w rękawicach trudno trafić przytrzymaniem w komórkę. Chip „CS/SS” pokazuje zawsze stan bieżący i nie
  wiadomo, że to przełącznik.
- **Brakujące funkcje:** Sch 5S, 20, 30, 60, 100, 120, 140; 40S/80S; ID i pojemność L/m; EN 10220 (ścianki metryczne);
  widok „jeden DN, wszystkie Sch” w pionie dla dużej czcionki.
- **Testy:** `pipe_schedules_test.dart` sprawdza tylko spójność (monotoniczność, t < OD/2). **Nie ma testu wartości względem
  normy** (poza DN100 Sch40 w `fitter_calculations_audit_test`). Ekran bez testu.
- **Propozycje:**
  - [P1][M] Dodać 5S/40S/80S (B36.19M) i przy przełączniku SS pokazywać kolumny „S”. Przypiąć wartości testem.
  - [P2][S] Kolumna lub tryb „ID” (OD − 2t); naprawić wyszukiwanie `"`.
  - [P2][M] Widok karty jednego DN z dużą czcionką (wszystkie Sch w pionie: t, ID, kg/m).

## rolling-offset — „Rolling Offset”
- **Cel i dla kogo:** odsadzka przestrzenna (rise + spread): true offset, travel, run, obrót kolan, opcjonalnie długość cięcia z B16.9 LR i szczeliną.
- **Co zawiera:** `lib/screens/rolling_offset_screen.dart`; kąty 45/60/30/inny (5° < θ < 89° lub 90°); DN (LR),
  szczelina; ostrzeżenie przy mnożniku > 10; przewodnik obliczeń; ochrona przed przypadkowym wyjściem.
- **Stan:** działa, wzory poprawne.
- **Ręczne przeliczenie:** 300/400/45° → 500 / 707,1 / 500, obrót od pionu 53,1°. DN100, 45°, g 3 → 707,11 − 128 − 6
  = **573,1**. DN100, 30° → T = 152·tan15° = 40,7. Wszystko zgodne z kodem i testami.
- **Błędy potwierdzone:** brak.
- **Problemy UX w terenie:**
  - [opinia] Wymagane są Rise > 0 **i** Spread > 0, więc zwykłej odsadzki płaskiej (spread 0) nie da się tu policzyć.
    Monter musi przejść do „Wstawki”, która liczy inaczej (bez szczeliny).
  - [opinia] Tylko kolana LR. Nie ma SR ani 3D, choć `b169ElbowTakeout` je obsługuje.
  - [opinia] Błędy pokazywane są w SnackBarze na 3 s. W rękawicach łatwo przeoczyć; lepiej błąd przy polu.
- **Brakujące funkcje:** obrót przeliczony na mm po obwodzie (znak na rurze); wybór SR/3D; zapis ostatnich danych.
- **Testy:** dobre (`rolling_offset_values_test.dart` 6, `rolling_offset_test.dart` 2, audyt 1).
- **Propozycje:**
  - [P3][S] Dopuścić spread = 0 (lub rise = 0) jako odsadzkę płaską; wybór 1D/1.5D/3D.
  - [P3][S] „Obrót na obwodzie = π·OD·φ/360” pod wynikiem obrotu.

## pipe-slope — „Spadek rury”
- **Cel i dla kogo:** spadek linii: wznios z długości i %, długość z wzniosu, % z długości i wzniosu.
- **Co zawiera:** `lib/screens/pipe_slope_screen.dart`, 3 tryby, skróty 0,5 / 0,67 / 1 / 2 %, przewodnik.
- **Stan:** działa.
- **Ręczne przeliczenie:** 6000 mm, 1 % → 60,0 mm, 0,573°, 10 mm/m; 10 m, 1 % → 100 mm (test audytu).
  Wznios 60 przy 1 % → 6000.
- **Błędy potwierdzone:** brak.
- **Problemy UX w terenie:**
  - [opinia] Długość i wznios tylko w mm. Monter mierzy linie w metrach, więc wpisuje „12000” i łatwo o zero za dużo.
    Sufiks „mm” jest, ale przydałby się przełącznik m/mm.
  - [opinia] Wynik ma 1 miejsce po przecinku, co jest w porządku. Kopiowanie skopiuje „60.0” bez jednostki.
- **Brakujące funkcje (realnie potrzebne):** **rzędne w punktach podpór**: przy spadku i rozstawie podpór
  (np. co 3 m) lista wysokości TOS/BOP w każdym punkcie od rzędnej startowej. Tak monter faktycznie ustawia
  linię. Dalej: rzędna startowa i końcowa; wejście 1:x oraz mm/m.
- **Testy:** 1 test audytu (1 %/10 m) i przewodnik w `calculation_guidance_test`.
- **Propozycje:**
  - [P2][M] Tryb „Rzędne podpór”: start H0, spadek, rozstaw, długość → tabela Hn (kopiowalna).
  - [P3][S] Przełącznik jednostek m/mm.

## pipe-route-calculator — „Trasa rur – 2 kolana 90°”
- **Cel i dla kogo:** trasa poziomo X → pion |H1 − H2| → poziomo Y na dwóch kolanach 90°: długości 3 odcinków.
- **Co zawiera:** `lib/screens/pipe_route_calculator_screen.dart`, `computePipeRoute`; R = take-out (domyślnie 0);
  separator i liczba miejsc po przecinku; zapis danych w SharedPreferences; szkic.
- **Stan:** działa matematycznie. Domyślne R = 0 i akcja „Wyzeruj R” prowadzą do złego cięcia.
- **Ręczne przeliczenie:** H1 2000, H2 500, X 1000, Y 800, R 152 → 848 / 1196 / 648, suma 2692. Zgodne.
- **Błędy potwierdzone:**
  - [potw.] **Brak szczeliny spoiny.** Trasa ma 4 spoiny doczołowe (ekran sam to pisze, l. 550), a odcinki nie
    uwzględniają 2 × g. Przy g = 3 mm każdy odcinek jest za długi o 3–6 mm, cała suma o 12 mm.
  - [potw.] **Puste H1 i H2 liczą się jako 0** (l. 122, 136–137). Przy R = 0 ekran pokazuje odcinek pionowy
    „0,0” bez ostrzeżenia, chociaż trasa „2 kolana 90° z pionem 0” nie istnieje.
- **Problemy UX w terenie:**
  - [opinia, istotne] Domyślne **R = 0** oznacza wymiary C-C. Jeśli monter nie zauważy pola R, przytnie każdą rurę
    o take-out za długą (DN100: +152 mm na końcu przy kolanie). Akcja w SnackBarze „Wyzeruj R” (l. 166–178) wręcz
    podsuwa „naprawę” przez wyzerowanie take-outu, a to daje fizycznie niemożliwą trasę i złe cięcie.
  - [opinia] Nie ma wyboru DN, więc R trzeba znać lub przepisać z innego ekranu (Rolling Offset ma DN).
  - [opinia] Ustawienia separatora i liczby miejsc są tylko na tym ekranie. Zajmują pół ekranu nad przyciskiem OBLICZ.
- **Brakujące funkcje:** DN + typ kolana, R z B16.9; szczelina; więcej niż 2 kolana (trasa dowolna). W aplikacji jest Zeszyt ISO; można podlinkować.
- **Testy:** `pipe_route_calculator_test.dart` (funkcja + treść wzoru). Brak testu pustych H i R = 0.
- **Propozycje:**
  - [P1][S] Wybór DN (R z `b169ElbowTakeout`) i ostrzeżenie „R = 0 → wymiary osiowe, NIE długość cięcia”. Usunąć „Wyzeruj R”.
  - [P2][S] Pole szczeliny (odcinki − 2g, dla odcinka od referencji wg typu złącza); walidacja H1 ≠ H2, puste H jako błąd.
  - [P3][S] Ustawienia wyświetlania schować pod ikonę.

## quick-converter — „Konwerter jednostek”
- **Cel i dla kogo:** długość, temperatura, ciśnienie, przepływ gazu osłonowego.
- **Co zawiera:** `lib/screens/quick_converter_screen.dart`; mm/cm/m/in/ft; °C/°F/K; bar/MPa/kPa/psi/atm;
  l/min ↔ cfh i slpm ↔ scfh osobno.
- **Stan:** działa. Współczynniki są zgodne z NIST: psi 0,0689476 bar, cfh 0,4719474 l/min, in 25,4, ft 304,8.
- **Ręczne przeliczenie:** 25,4 mm → 1,000 in; 100 psi → 6,895 bar; 20 l/min → 42,38 cfh. Zgodne.
- **Błędy potwierdzone:** brak.
- **Problemy UX w terenie:**
  - [opinia] Wyniki zawsze z kropką („25.400”), także w wersji PL. Inne ekrany używają przecinka.
  - [opinia] 3 miejsca po przecinku dla mm to fałszywa precyzja („1219.200 mm”).
- **Brakujące funkcje:** ułamki cala na wejściu i wyjściu (2 3/8", 1/16"), bo rysunki US są w ułamkach;
  ciśnienie **kgf/cm² (at)** i **mbar** (stare manometry, próby gazowe); moment N·m ↔ ft·lb; masa kg ↔ lb.
- **Testy:** bardzo dobre (15 testów widgetów, także ujemne i graniczne wartości).
- **Propozycje:**
  - [P2][M] Ułamki cala (wejście „2 3/8” i wynik do 1/16"). Parser ułamków już jest (test audytu „1 1/2 in = 38,1”).
  - [P3][S] kgf/cm², mbar; separator zgodny z językiem.

## support-config — „Konfiguracja podpór”
- **Cel i dla kogo:** maksymalny rozstaw podpór rur stalowych (ciecz / gaz), liczba podpór na odcinku, typy podpór i zasady.
- **Co zawiera:** `lib/screens/support_config_screen.dart` (4 zakładki), `lib/data/support_spacing.dart`
  (tabela DN15–DN600, izolacja −12 %, ⌈L/s⌉ + 1).
- **Stan:** **błędy danych** (część wierszy ponad normą, część mocno poniżej), mimo że ekran powołuje MSS SP-69.
- **Porównanie z źródłem** (ANSI/MSS SP-58/SP-69, tabela „Spacing of hangers for steel pipe”, woda; ASME B31.1
  Tab. 121.5, para/gaz/powietrze):

  | DN | app ciecz | norma ciecz | app gaz | norma gaz (B31.1) |
  |---|---|---|---|---|
  | 20 | **2400** | 2130 (7 ft) | 2400 | — |
  | 32 | **2400** | 2130 (7 ft) | 3000 | — |
  | 25 | 2100 | 2130 | 2700 | 2700 |
  | 50 | 3000 | 3050 | 4000 | 4000 |
  | 100 | 4300 | 4270 | 5200 | 5200 |
  | 150 | 5200 | 5180 | **5800** | 6400 |
  | 200 | 5800 | 5790 | **6400** | 7300 |
  | 250 | **6400** | 6710 | 6700 | — |
  | 300 | 7000 | 7010 | **7000** | 9100 |
  | 400 | **7600** | 8230 | **7600** | 10700 |
  | 500 | **8200** | 9140 | **8800** | 11900 |
  | 600 | **9100** | 9750 | **10000** | 12800 |

- **Błędy potwierdzone:**
  - [potw.] **DN20 i DN32 dla cieczy: 2,4 m zamiast 2,1 m** (`support_spacing.dart:27, 29`), czyli ok. 13 % ponad
    tabelą. To jedyne wiersze, które błądzą w **niebezpieczną** stronę.
  - [potw.] Od DN250 kolumna cieczy jest przesunięta o jeden wiersz w dół (DN250 = 6,4 zamiast 6,7; DN600 = 9,1
    zamiast 9,8). Od DN150 kolumna gazu jest 10–40 % niższa niż w B31.1. Błąd jest zachowawczy, ale ekran obiecuje
    „wartości referencyjne MSS SP-69” (`support_config_screen.dart:268`), a na rurociągu DN400 daje np. o 40 % więcej podpór, niż trzeba.
  - [potw., opinia co do skali] Dodatkowe −12 % „za izolację” (`support_spacing.dart:71`): tabela B31.1 121.5 jest
    już liczona **dla rury izolowanej** wypełnionej wodą. Obniżka jest podwójna, nie wynika z normy i jest opisana jako reguła.
  - [potw., drobny] Nagłówki tabeli „GAZ / PARA”, „CIECZ” są na sztywno po polsku (l. 386, 395).
- **Problemy UX w terenie:**
  - [opinia, istotne] Tabela dotyczy rury stalowej o ściance standardowej. Rury cienkościenne (10S, sanitarne) i
    tworzywa wymagają znacznie mniejszego rozstawu, a na ekranie kalkulatora nie ma takiego ostrzeżenia
    (jest tylko pośrednio w zakładce Zasady).
  - [opinia] Zasada „prowadnice w pionie co 2× rozstaw” nie ma źródła.
- **Brakujące funkcje:** DN65 jest, ale nie ma DN90/DN125 (przy braku dokładnego DN brany jest najbliższy wiersz,
  przy remisie mniejszy, czyli zachowawczo). Brak uwagi o obciążeniach skupionych (zawory, kołnierze), którą norma zawiera.
- **Testy:** `support_spacing_test.dart` i `support_config_values_test.dart` testują arytmetykę i monotoniczność,
  **żaden nie przypina wartości do normy**. Dlatego DN20/DN32 przeszły.
- **Propozycje:**
  - [P1][S] Poprawić tabelę na wartości MSS SP-58/SP-69 (metr.) i B31.1 121.5; przypiąć testem z odnośnikiem.
  - [P2][S] Usunąć −12 % albo opisać jako „zapas własny”, nie normowy; ostrzeżenie o cienkościennych, SS i zaworach.
  - [P3][S] Tłumaczenie nagłówków.

## sanitary-tube — „Rury sanitarne (tube)”
- **Cel i dla kogo:** OD, ścianka, ID, kg/m, L/m dla ASME BPE / ASTM A270 i DIN 11850 seria 2 (spożywka, farmacja; L/m do formowania gazem).
- **Co zawiera:** `lib/screens/sanitary_tube_screen.dart`, `lib/data/sanitary_tube.dart`.
- **Stan:** dane poprawne, jedna nieścisłość w gęstości.
- **Wartości sprawdzone:** BPE 0,035" / 0,065" / 0,083" / 0,109" (0,89 / 1,65 / 2,11 / 2,77 mm) i OD 1/4"–6" zgodne;
  DIN 11850 s.2 (13 × 1,5 … 53 × 1,5; 70/85/104/129/154 × 2) zgodne. 38,10 × 1,65 → ID 34,80, 0,951 L/m.
- **Błędy potwierdzone:**
  - [potw., drobny] ρ = 7,93 „(stal 316L)” (`sanitary_tube.dart:30–32`, okno źródła l. 33). Dla 316L jest to
    8,0 kg/dm³, więc kg/m wychodzi o ok. 0,9 % za mało.
  - [potw., drobny] Zapytanie bez wyniku (np. „DN50” w zakładce BPE) daje pustą listę bez komunikatu.
  - [potw., drobny] Nagłówki „SIZE/OD/WALL/ID” są po angielsku także w PL.
- **Problemy UX w terenie:** [opinia] 6 kolumn po 12 px. Gęsto, ale do przyjęcia.
- **Brakujące funkcje:** DIN 11866 / EN 10357 serie A/B/C (ISO 1127: 33,7; 42,4; 48,3 …), SMS 3008
  (25/38/51/63,5/76,1). Na liniach skandynawskich i w farmacji UE to codzienność. Brak też tolerancji i klasy powierzchni Ra (BPE SF1…).
- **Testy:** `sanitary_tube_test.dart` sprawdza geometrię i spójność. Nie ma przypięcia wartości do normy ani testu ekranu.
- **Propozycje:**
  - [P3][S] ρ = 8,0 dla 316L; komunikat „brak wyników”; tłumaczenie nagłówków.
  - [P2][M] Dodać DIN 11866 A/B/C i SMS 3008.

---

## Top 5 w grupie

1. **[P1] Podpory: tabela rozstawów niezgodna z MSS SP-69/B31.1.** DN20 i DN32 dla cieczy 2,4 m zamiast 2,1 m
   (niebezpieczna strona). Od DN150–250 kolumny zaniżone o 10–40 %, do tego nienormowe −12 % za izolację.
   Test nie przypina wartości (`lib/data/support_spacing.dart:26–44, 71`).
2. **[P1] Fazowanie: złącze X ma 2× za dużą szerokość fazy, a kąt α jest niejednoznaczny** (ISO 9692-1 podaje
   kąt rowka 60°, aplikacja liczy kąt na stronę 37,5°). Wpisanie 60° z WPS daje 3× za szeroki rowek
   (`fitter_tools_screen.dart:1447, 1456, 1471, 1492`).
3. **[P1] Tabela Sch bez 40S/80S i bez ID.** Przy przełączniku SS NPS 10/12 pokazuje ścianki i masy stali węglowej
   (12" „40” 10,31 zamiast 9,53 mm; 80S 12,70 zamiast 17,48). Scenariusz manifestu (ID) nie jest spełniony.
4. **[P1] Brak szczeliny spoiny i ryzyko R = 0 w „Wstawce” i „Trasie rur”.** Rolling Offset odejmuje 2g, Wstawka
   i Trasa nie. Trasa startuje z R = 0 (wymiary C-C), a SnackBar podsuwa „Wyzeruj R”, co daje rury za długie o take-out
   (`fitter_tools_screen.dart:990`, `pipe_route_calculator_screen.dart:85, 166–178`).
5. **[P2] Wyszukiwarki „2"” nic nie znajdują** w `elbow-takeout` i `pipe-schedule`, chociaż podpowiedź i komunikat
   pustego wyniku zalecają dokładnie taki zapis. Do tego nieaktualna pomoc „Kalkulatorów montera” (Wstawka opisana
   jako „między kołnierzami”) i kąt piły 90 − α bez opisu skali w „Cięciu pod spadek”.

Dodatkowo (P3, szybkie): gęstość 316L 8,0 (Ciężar, Sch, Sanitarne); α 304L 16,0 (Dylatacja); obwód „0” w Obrocie
kolanka; ciche wartości domyślne w Fazowaniu i Ciężarze; brak testów dla 6 z 8 zakładek „Kalkulatorów montera”.

## Źródła
- Rozstaw podpór, woda, ANSI/MSS SP-58: [PHD Mfg — Steel Pipe Data / Spacing of hangers](https://phd-mfg.com/wp-content/uploads/2018/06/6-Steel-Pipe_6-1-18.pdf);
  [HardHat Engineer — MSS SP-69](https://hardhatengineer.com/pipe-support-span-chart/)
- ASME B31.1 Tab. 121.5 (woda / para-gaz-powietrze, rura izolowana): [wermac.org — pipe support spacing](https://www.wermac.org/steel/pipesupports_spacing.html)
- B36.19M 40S/80S: [Wikipedia — Nominal Pipe Size](https://en.wikipedia.org/wiki/Nominal_Pipe_Size);
  [projectmaterials — B36.10/B36.19 różnice NPS 10/12](https://blog.projectmaterials.com/pipes/pipe-dimensions-asme-36-10-19/)
- Fazowanie ISO 9692-1 (kąt rowka V 60° ±5°) vs ASME B16.25 (37,5° ±2,5° na stronę, 75° całkowity):
  [Kedes Machine — bevel standards](https://kedesmachine.com/guide/welding-bevel-standards-overview/);
  [Therness — joint design ISO](https://www.therness.com/blog/weld-joint-design-types-sizing-iso-acceptance-criteria/)
- Gęstość 1.4404 (316L) 8,0 kg/dm³: [TEAM EDELSTAHL 1.4404](https://www.teamedelstahl.de/en/materials/1-4404/)
- α 1.4307 (304L) 16 ×10⁻⁶/K (20–100 °C): [Industeel UR 304L](https://industeel.arcelormittal.com/fichier/ur-304l/)
- Ręczne przeliczenia: skrypt `g2_check.py` w scratchpadzie sesji (nie w repo).
