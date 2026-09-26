# Przegląd modułów — grupa G1: projekty i lista cięć (CUT)

- Data: 2026-09-26, gałąź `fix/audyt-2026-08-29` (stan po poprawkach z 24–25.09.2026).
- Zakres: `projects`, `new-project`, `fitter`, `segment-builder`, `cut-list-summary`, `material-list`, `project-components`, `heat-photos`, `component-library`, `new-cut-list-project`.
- Perspektywa: monter rurociągów przemysłowych w prefabrykacji (rękawice, słońce, pośpiech, brak zasięgu) plus inżynier Flutter.
- Testy uruchomione: 32 pliki testów tej grupy (`flutter test --no-pub`), **244/244 zielone**. Dodatkowo dwie sondy w scratchpadzie (poza repo) do przeliczeń. Ich wyniki są cytowane niżej jako „sonda”.
- Oznaczenia: **[K]** = potwierdzone w kodzie albo w sondzie/teście; **[O]** = opinia praktyka lub projektanta, bez dowodu w kodzie.

Stan ogólny: silnik CUT (`PrefabEngine`) jest spójny i dobrze przetestowany. Formuła ISO − take-offy − gap × spoiny przelicza się poprawnie (sonda: 1000 − 152,4 − 76 − 2·3 = 765,6). Słabe punkty grupy leżą gdzie indziej: w **danych wejściowych do silnika** (biblioteka komponentów, redukcja), w **identyfikowalności materiału** (heat) i w **ergonomii terenowej**.

---

## projects — Projekty
- **Cel i dla kogo:** lista projektów cut listy dla montera i brygadzisty. Wejście do każdego projektu, jego ustawienia i usuwanie.
- **Co zawiera:** menu Monter → „Lista cięć” (`tool_registry.dart:147`, id `cut_list`) → `lib/screens/projects_screen.dart`. Jest wyszukiwarka (nazwa, linia, ISO, klient, klasa), usuwanie przeciągnięciem z Cofnij przez 6 s (transakcja `ProjectDao.deleteProjectCascade`) i ikona ustawień (`showProjectSettingsDialog`). „+” prowadzi do `NewProjectScreen`.
- **Stan:** działa (manifest: `passed`).
- **Błędy potwierdzone:**
  - [K] Kolejność listy „ostatnio zmienione” nie odpowiada pracy. Lista jest sortowana po `updated_at DESC` (`project_dao.dart:99`), a dodanie lub edycja segmentu nie zmienia `projects.updated_at` (`fitter_screen.dart:194-203`, `:264-274`). Projekt, w którym monter pracował dziś, zostaje nisko na liście. `updated_at` zmienia się tylko przy ustawieniach albo przy przesunięciu trasy za redukcją (`fitter_screen.dart:129-131`).
  - [K] Projekt bez nazwy pokazuje się jako „Projekt 3f9a1c” (fragment UUID, `projects_screen.dart:216-218`). W terenie taki identyfikator nic nie mówi.
  - [K] Po powrocie z projektu wywoływany jest `_load()` → szkielet ładowania → nowa lista (`projects_screen.dart:37-45`, `:354-356`). Pozycja przewijania ginie przy każdym powrocie.
- **Problemy UX w terenie:** [O] podtytuł pokazuje średnicę początkową, a nie liczbę segmentów, sumę CUT ani datę, więc nie widać, czy projekt jest w toku, czy zamknięty. [K] Wiersz ma cel dotyku OK (ListTile + IconButton 48 dp).
- **Brakujące funkcje:** [O] duplikowanie projektu (ta sama linia na drugim pionie), status projektu (w toku / pocięty / oddany), archiwum, sortowanie po nazwie lub linii, eksport i import projektu (przekazanie koledze bez zasięgu, np. plik przez Bluetooth).
- **Testy:** pokryte: atomowe usuwanie i Cofnij (`data_integrity_audit_test.dart`), wyszukiwanie i identyfikacja (`project_identity_ui_test.dart`), dialog ustawień (`project_settings_dialog_test.dart`). Brak: kolejności listy po pracy w projekcie.
- **Propozycje:**
  - [P3][S] Podbijać `projects.updated_at` przy insert, update i delete segmentu.
  - [P3][S] Fallback nazwy: linia/ISO z identyfikacji albo data utworzenia zamiast UUID.
  - [P3][S] Przeładowywać listę bez szkieletu (zachować przewijanie).
  - [P3][M] Liczba segmentów i suma CUT w podtytule; duplikuj projekt.

## new-project — Nowy projekt
- **Cel i dla kogo:** założenie projektu cut listy: materiał, OD, ścianka, sztanga, rzaz (kerf), gap, identyfikacja z rysunku.
- **Co zawiera:** `lib/screens/new_project_screen.dart`; wejście z „+” na liście projektów. Po zapisie ekran od razu otwiera `FitterScreen` (`pushReplacement`). W tym samym pliku jest dialog ustawień istniejącego projektu, który przelicza CUT po zmianie gapu (`ProjectDao.updateSettings`, jedna transakcja).
- **Stan:** działa.
- **Błędy potwierdzone:**
  - [K] Brak walidacji sensowności: ścianka ≥ OD/2, OD 0,1 mm albo 100 000 mm i gap 50 mm przechodzą (`new_project_screen.dart:58-95` sprawdza tylko > 0 lub ≥ 0).
  - [K] Opis w dialogu „Kerf i gap — wzory” mówi „takeout = wymiar kolanka/redukcji do osi” (`:185`). Redukcja nie ma wymiaru do osi (w builderze ma tylko czoło bliskie lub dalekie), więc tekst wprowadza w błąd.
  - [K] Ustawienia istniejącego projektu nie pozwalają zmienić OD, ścianki ani materiału (`_ProjectSettingsDialog`, `:409-575`). Literówka w OD (114,3 → 144,3) oznacza zakładanie projektu od nowa, nawet gdy nie ma w nim żadnego segmentu.
- **Problemy UX w terenie:** [K] OD wpisuje się ręcznie. Nie ma wyboru DN/NPS ani harmonogramu (schedule), choć aplikacja ma tabele (`lib/data/pipe_schedules.dart`, `nps_dn_od_r.dart`). Stary, osierocony ekran (`new_cut_list_project_screen.dart:35-51`) miał chociaż listę OD. [K] Pola nie mają `textInputAction: next`, więc każde przejście do kolejnego pola to tapnięcie. [K] Brak ochrony przed wyjściem z częściowo wypełnionego formularza.
- **Brakujące funkcje:** [O] wybór DN + schedule → OD i ścianka automatycznie; materiały poza SS/CS (duplex, Cu-Ni, stopy niklu); domyślny kerf i gap zapamiętany z poprzedniego projektu.
- **Testy:** `new_project_test.dart` i `new_project_opens_test.dart` (tworzenie, przejście do projektu), `project_settings_update_test.dart` (przeliczenie gapu, rollback). Brak testu granic wartości.
- **Propozycje:**
  - [P2][M] Pickery DN/NPS + schedule wypełniające OD i ściankę (z tabel już obecnych w `lib/data`).
  - [P2][S] Edycja OD, ścianki i materiału w ustawieniach, przynajmniej gdy projekt nie ma segmentów.
  - [P3][S] Walidacja sensowności (t < OD/2, gap ≤ 10 mm z ostrzeżeniem).
  - [P3][S] Poprawić tekst o redukcji w dialogu wzorów.

## fitter — Projekt / segmenty (FitterScreen)
- **Cel i dla kogo:** główny widok projektu. Lista segmentów z ISO i CUT, dodawanie, edycja i usuwanie segmentów, bieżąca średnica trasy (za redukcją), wejścia do BOM, heat, zdjęć i listy cięć.
- **Co zawiera:** `lib/screens/fitter_screen.dart`; FAB „Dodaj segment” → `SegmentBuilderScreen`. Tap na wiersz otwiera edycję, przeciągnięcie usuwa. AppBar ma 5 ikon: pomoc, ustawienia, BOM, komponenty/heat, zdjęcia. Na dole „Zakończ CUT LIST”. Średnicę dalszej trasy wylicza `routeAfterSegments`.
- **Stan:** częściowo (działa dla liniowej trasy redukującej; błędy przy ekspanderze i przy etykietach projektów ze skanu).
- **Błędy potwierdzone:**
  - [K] **Ekspander nie zmienia średnicy trasy.** `fitter_screen.dart:77-84` przesuwa trasę tylko wtedy, gdy wlot redukcji = średnica segmentu. Redukcja 114,3→60,3 wybrana na końcu rury Ø60,3 (biblioteka ją podaje, bo pasuje wylot, `component_library_dao.dart:44`) to fizycznie rozszerzenie na Ø114,3. Sonda: trasa zostaje na Ø60,3, oczekiwane Ø114,3 i pytanie o nową ściankę. Test `fitter_route_test.dart:154` utrwala to zachowanie jako poprawne.
  - [K] Segmenty ze skanu i ze szkicu ISO (bez `library_id`, ale z rodzajem `axial`/`nonAxial`) mają w liście etykietę „OPEN END/LOGICAL” (`_compLabel`, `:326-330`). Kolano ze skanu wygląda jak koniec otwarty.
  - [K] Każde przeładowanie (dodanie, edycja, usunięcie segmentu, ustawienia) ustawia `_loading = true` → cała lista zamienia się w spinner (`:110-112`, `:386-387`). Pozycja przewijania ginie. Przy 40 segmentach po każdej poprawce trzeba przewijać od początku.
  - [K] Usunięcie segmentu jest nieodwracalne (dialog „Tej operacji nie można cofnąć”, `:426-429`). Projekt ma za to Cofnij, więc zachowanie jest niespójne. Numer `seq_no` usuniętego OSTATNIEGO segmentu wraca do użytku przy następnym dodaniu (`segment_dao.dart:93-101`: MAX+1). Heat przypisane do `S00n_END` przechodzą wtedy na inny komponent (szczegóły w `project-components`).
  - [K] Tytuł zastępczy „Projekt” jest wpisany na sztywno bez `context.tr` (`:379`).
- **Problemy UX w terenie:**
  - [K] Pięć ikon akcji w AppBar (`:342-377`) plus „wstecz” zajmuje około 300 dp. Na telefonie 360 dp nazwa projektu obcina się do kilku liter. Ikony nie mają podpisów (tooltip działa tylko po przytrzymaniu). Dwie różne ikony prowadzą do dwóch różnych mechanizmów heat (komponenty/heat i zdjęcia).
  - [K] Każdy wiersz uruchamia `FutureBuilder` z dwoma zapytaniami do biblioteki przy każdym przebudowaniu (`:448-452`). Przy dużej liście etykiety migają „...”.
  - [O] Brak sumy CUT i liczby sztang na ekranie projektu; trzeba wejść w „Zakończ CUT LIST”.
- **Brakujące funkcje:** [O] mnożnik ilości segmentu (10 identycznych odcinków lub spooli); duplikuj segment; wstaw segment między istniejące; zmiana kolejności; odgałęzienie od trójnika (trasa jest tylko liniowa, ostatni segment wyznacza średnicę).
- **Testy:** `fitter_route_test.dart` (trasa za redukcją, ścianka), `segment_label_test.dart`, `segment_edit_test.dart`, `scan_segment_edit_test.dart`, smoke. Brak testów: ekspandera (test utrwala błąd), etykiet segmentów ze skanu, zachowania przewijania.
- **Propozycje:**
  - [P2][S] `routeAfterSegments`: gdy wylot redukcji = średnica segmentu, trasa przechodzi na wlot (ekspander) i pyta o ściankę. Poprawić test `:154`.
  - [P2][S] Etykieta końca z `start_kind`/`end_kind`, gdy brak `library_id` („Kształtka (skan)”, jak w builderze `_Picked.chipLabel`).
  - [P2][S] Przeładowanie bez spinnera na całą listę; Cofnij dla usunięcia segmentu (snapshot jak przy projekcie).
  - [P2][S] Nie używać ponownie `seq_no` (licznik w projekcie) albo kasować lub przenosić `component_heats` razem z segmentem.
  - [P3][S] Przenieść rzadkie akcje do menu „⋮”, a w AppBar zostawić najwyżej dwie ikony.
  - [P3][S] Pasek sumy (liczba segmentów, Σ CUT, sztangi) nad listą.

## segment-builder — Nowy segment / Popraw segment
- **Cel i dla kogo:** budowa jednego segmentu KOMPONENT → RURA → KOMPONENT (albo OPEN END), wybór punktu odniesienia wymiaru ISO po każdej stronie, wpisanie ISO (z wyrażeniami) i wyliczenie CUT przez `PrefabEngine.anchoredCutMm`.
- **Co zawiera:** `lib/screens/segment_builder_screen.dart`, wywoływany z `FitterScreen` (nowy segment lub edycja). Paleta: Kolano 90, Kolano 45, Trójnik, Rura, Redukcja, Kołnierz, Zawór, Inne, Open end. Arkusz punktu odniesienia z domyślnym wyborem (oś dla kolan i trójników, czoło dalekie dla kołnierza, czoło bliskie dla pozostałych). Rozbicie obliczeń, oznaczenie spoola (piece mark), ochrona przed porzuceniem zmian, Cofnij po usunięciu elementu.
- **Stan:** częściowo. Silnik działa poprawnie, ale dane dla redukcji i dla elementów spoza biblioteki są niepełne.
- **Błędy potwierdzone:**
  - [K] **P1: redukcja zakładana z palety ma długość 0.** `_createMissingComponent('REDUCER')` pyta tylko o średnicę wyjścia i zapisuje `lengthMm: 0` (`segment_builder_screen.dart:776-790`). Arkusz dla redukcji proponuje „czoło dalekie” (`:70-72`, spec „ISO do końca redukcji”), a `_calcOffset(faceFar)` odejmuje wtedy `lengthMm` = 0 (`:138-140`). Sonda: ELB DN100 (152,4) → rura → redukcja 4"×2" do końca, ISO 1000, gap 0 daje **CUT 847,6 mm; poprawnie 1000 − 152,4 − 102 (B16.9 H) = 745,6**. Rura wychodzi **102 mm za długa**. Nie da się tego poprawić z aplikacji (patrz `component-library`: brak edycji, a UNIQUE blokuje drugą redukcję o tych samych średnicach).
  - [K] Redukcja zakładana, gdy jest POCZĄTKIEM segmentu, dostaje wlot = bieżąca średnica (`:783-786`). W tej pozycji bieżąca średnica to jej wylot, więc w bibliotece powstaje wpis odwrócony, np. „REDUCER Ø60,3 → OUT Ø114,3” zamiast 114,3 → 60,3.
  - [K] Nieprawidłowa wartość w dialogu wymiaru („0”, „abc”) zamyka dialog bez komunikatu i bez dodania elementu (`_askValue`, `:849-852`); monter nie wie, co się stało.
  - [K] Pole ISO wyczyszczone po wpisaniu pokazuje surowy wyjątek: „Błąd: FormatException: empty”. Dla „1.234,5” pokazuje „Błąd: FormatException: bad number "1.234.5"” (`:656-657`; sonda parsera).
  - [K] Po usunięciu chipu START sekwencji nie da się naprawić dodaniem nowego startu. Nowy element trafia zawsze na koniec (`:720-770`), więc [RURA, KONIEC] + X daje [RURA, KONIEC, X], a to nie jest segment. Trzeba usunąć wszystkie chipy. Cofnij wykonane po dodaniu nowego elementu wstawia stary na pozycję 0 i przywraca stary CUT bez `_recalc` (`:955-965`).
- **Problemy UX w terenie:**
  - [K] Cele dotyku: „X” na chipie sekwencji to `GestureDetector` z ikoną 14 px (`:1183-1186`), a przyciski palety mają około 34 dp wysokości (padding 8 + ikona 18, `:1797-1818`). Oba są poniżej 48 dp i w rękawicach trudne do trafienia.
  - [K] Małe czcionki na kluczowych liczbach i opisach: etykiety diagramu 7 px (`:1782`), 8–9 px w schemacie (`:1342-1347`), 10–11 px w rozbiciu i w offsetach (`:1286-1294`, `:1462-1463`). Wynik „CUT = …” ma 24 px (OK), reszta jest nieczytelna w słońcu.
  - [K] Opcje punktu odniesienia to `GestureDetector` bez efektu naciśnięcia (`:1625`), więc w rękawicach nie ma potwierdzenia trafienia.
  - [O] Każdy kolejny segment trzeba zaczynać od ponownego wybrania komponentu, na którym skończył się poprzedni. Automatyczne podstawienie START = END poprzedniego segmentu (z tym samym punktem odniesienia) oszczędziłoby 2–3 tapnięcia na segment.
- **Brakujące funkcje (praktyk):**
  - [K] Builder nie korzysta z `TakeoutCatalog` (ASME B16.9/B16.5/B16.10, `lib/services/takeout_catalog.dart`). Używa go notatnik ISO i skaner, a tutaj monter wpisuje take-off z pamięci.
  - [K] Trójnik ma jeden wymiar do osi (`LibraryComponent.axisMm`). Nie ma stron RUN/BRANCH ani różnego C-E dla trójnika redukcyjnego, czego wymaga spec (`docs/CUT_LIST_USER_SPEC.md` pkt 4).
  - [O] Brak grubości uszczelki na złączu kołnierzowym (typowo 2–3 mm na złącze) i naddatku na spoinę montażową (field weld, +50/100 mm) na OPEN END.
  - [O] Brak kolana o dowolnym kącie (cięte kolano / segmentowe).
- **Testy:** szeroko: `segment_builder_test.dart`, `segment_weld_count_test.dart`, `segment_flange_reference_test.dart`, `segment_edit_test.dart`, `scan_segment_edit_test.dart`, `builder_cut_offline_test.dart`, `prefab_engine_test.dart`. Brak: redukcji z palety (długość), redukcji jako START, komunikatu dla błędnego `_askValue`, naprawy sekwencji po usunięciu START.
- **Propozycje:**
  - [P1][S] Przy zakładaniu redukcji pytać o długość H (podpowiedź z `TakeoutCatalog.reducer…` dla DN) i o kierunek; blokować „czoło dalekie” przy L = 0 z czytelnym ostrzeżeniem.
  - [P2][M] Podpowiedź take-offu z katalogu B16.9/B16.5 w dialogu `_createMissingComponent` (DN wyliczone z OD).
  - [P2][S] Cele dotyku ≥ 48 dp (chip X jako `IconButton`, paleta `minHeight: 48`), czcionki ≥ 12–14 px na liczbach.
  - [P2][M] „Kontynuuj od …”: nowy segment startuje od END poprzedniego.
  - [P3][S] Czytelne komunikaty parsera zamiast `FormatException`; komunikat przy odrzuconej wartości w `_askValue`.
  - [P2][L] Trójnik ze stronami run/branch i osobnym C-E; uszczelka i naddatek FW jako parametry projektu.

## cut-list-summary — CUT LIST (plan cięcia sztang)
- **Cel i dla kogo:** plan cięcia dla piły: grupy Ø×t, sztangi z odcinkami (S01 …), rzaz, pozostałość, ostrzeżenie o odcinku dłuższym niż sztanga. Eksport do PDF, CSV i tekstu.
- **Co zawiera:** `lib/screens/cut_list_summary_screen.dart` (z `FitterScreen` → „Zakończ CUT LIST”, z przeglądu skanu), `lib/services/cut_list_summary.dart` (`summarizeCutList`), `bar_nesting.dart` (FFD + best fit, rzaz na cięcie), `cut_list_csv.dart`, `pdf_export_service.dart`. Ekran, PDF i CSV liczą z jednej funkcji.
- **Stan:** działa (liczby są spójne między ekranem, PDF i CSV).
- **Błędy potwierdzone:**
  - [K] **Odcinek dłuższy niż sztanga jest dzielony bez gapu dodatkowej spoiny.** `bar_nesting.dart:411-427`: 7000 na sztangach 6000 daje 6000 + 1000 (sonda). Po zespawaniu z gapem g spool jest o g za długi. Ostrzeżenie tylko każe „uwzględnić gap”, a projekt zna `gap_mm`.
  - [K] Zaokrąglenia na jednym arkuszu PDF są niespójne. Tabela sztang pokazuje 0 miejsc (`cut_list_summary.dart:167`), tabela segmentów 1 miejsce (`pdf_export_service.dart:409`). CUT 1234,5 widnieje raz jako „1235”, raz jako „1234.5” (sonda). Na ekranie jest podobnie (chipy 0 miejsc, builder 1).
  - [K] Grupa Ø×t jest kluczowana dokładnym zapisem double (`cut_list_summary.dart:120`). 114,3 i 114,30000000000001 dają 2 grupy i 2 sztangi zamiast 1 (sonda). DAO biblioteki ma już tolerancję 0,05 mm; tu jej brak.
  - [K] Nesting rezerwuje rzaz także za ostatnim kawałkiem, gdy ten kończy się na końcu sztangi (`bar_nesting.dart:448-453`). 3000 + 2999 z 6000 przy rzazie 1 mm daje 2 sztangi (sonda), choć 3000 + 1 + 2999 = 6000. [O] To podejście konserwatywne i akceptowalne (końce sztang się planuje), ale trzeba to napisać wprost.
- **Problemy UX w terenie:**
  - [K] Czcionki 9–12 px dla etykiet segmentów, „Cięcia / Zostaje” i pozostałości (`:1004-1007`, `:1127-1132`, `:1273`). Tylko długości na sztandze mają 14 px.
  - [O] „Odpad %” liczy także przydatne ścinki > 200 mm (oznaczone „nadaje się na spady”). Czerwony procent odpadu straszy, choć materiał wraca do magazynu.
  - [K] Kopiowanie jednej sztangi wymaga długiego przytrzymania (w rękawicach działa, ale tylko z podpowiedzią 10 px).
- **Brakujące funkcje:** [O] **odhaczanie uciętych kawałków** (stan „ucięte” per odcinek, zapis offline): najważniejsza funkcja przy pile. Do tego: kolejność „po segmentach” obok „po długości”, wykorzystanie ścinków z magazynu jako sztang, martwa strefa imadła lub minimalny chwyt, kolumna na podpis albo odhaczenie w PDF.
- **Testy:** bogate: `cut_list_summary_test.dart`, `cut_list_labels_test.dart`, `cut_list_csv_test.dart`, `cut_list_pdf_test.dart`, `cut_summary_offline_test.dart`, `cut_list_summary_screen_test.dart`, `cut_list_global_summary_test.dart`, `bar_nesting_test.dart`, `bar_nesting_labels_test.dart`. Brak: tolerancji grupowania, gapu na spoinie łączącej, spójności zaokrągleń.
- **Propozycje:**
  - [P2][S] Części dzielonego odcinka pomniejszać o gap spoiny łączącej: ostatnia część = reszta − gap × (n − 1). W ostrzeżeniu pokazać wynik zamiast polecenia.
  - [P2][M] Stan „ucięte” per kawałek (tabela lub kolumna, offline) z paskiem postępu; kratki do odhaczania w PDF.
  - [P3][S] Grupowanie z tolerancją 0,05 mm; jedna reguła zaokrąglenia (np. 0,5 mm w dół) wszędzie.
  - [P3][S] Rozdzielić „odpad” i „ścinki do magazynu”; czcionki ≥ 12 px.

## material-list — Lista materiałowa (BOM)
- **Cel i dla kogo:** zestawienie rur (metry) i kształtek (sztuki) do zamówienia w magazynie.
- **Co zawiera:** `lib/screens/material_list_screen.dart` (ikona listy w AppBar `FitterScreen`), `lib/services/material_list_builder.dart`. Kształtki liczy topologia złączy (`countFittings`: złącze n/n+1 = 1 sztuka, trójnik 3 porty, kołnierz 1 port). Jest „Kopiuj całość”, „Udostępnij” i odświeżanie przeciągnięciem.
- **Stan:** częściowo (kształtki z biblioteki liczone dobrze; rura i projekty ze skanu słabiej).
- **Błędy potwierdzone:**
  - [K] **Rura w BOM to suma CUT netto** (`material_list_builder.dart:77-81`), bez rzazu, bez liczby sztang i bez resztek. Lista cięć tego samego projektu mówi „N sztang”. BOM dla magazynu zaniża zamówienie i jest niespójny z listą cięć.
  - [K] Projekty ze skanu i szkicu ISO: kształtka z korpusem jest kluczowana średnicą segmentu (`:231-234`). Redukcja między Ø114,3 a Ø60,3 liczy się jako **2 sztuki** (sonda: `nonAxial 114.3: 1, nonAxial 60.3: 1`). Kolano zapisane „do osi” z jednej strony i „do czoła” (wartość 0) z drugiej też liczy się dwa razy (sonda).
  - [K] Ilość kształtki pojawia się w wierszu dwa razy: `qtyText = trailingText` (`material_list_screen.dart:556-567`, `:697`).
  - [K] Podpowiedź przy pustej liście każe „Otwórz ISO/Notatnik w projekcie” (`:509-512`). W projekcie cut listy segmenty dodaje się przyciskiem „Dodaj segment”, a notatnika tam nie ma.
  - [K] Martwy kod: `_staleCache` (`:174-175`, `// ignore: unused_field`) i odzyskiwanie `projectId` z SharedPreferences (`:279-283`). Każde wejście przekazuje niepusty id, a przycisk „Wyczyść filtr” nie ma nic wspólnego z filtrem.
- **Problemy UX w terenie:** [K] tap w wiersz daje tylko wibrację (`:630-632`) i sugeruje akcję, której nie ma. [O] Opis z biblioteki to surowy kod („ELB90 Ø114.3 x 3.6 | A=152.4”, „REDUCER … L=0.0 | OUT Ø60.3”), niezrozumiały dla magazyniera.
- **Brakujące funkcje:** [O] liczba sztang do zamówienia (z nestingu) albo metry z naddatkiem; liczba spoin i cale-średnica (inch-dia) na grupę; uszczelki i komplety śrub do par kołnierzy; zapis typu kształtki dla projektów ze skanu i szkicu.
- **Testy:** `material_list_builder_test.dart`, `material_list_topology_test.dart`, `material_list_screen_test.dart`. Brak: redukcji skanowanej (obecne zachowanie ×2), zgodności metrów rury z listą cięć.
- **Propozycje:**
  - [P2][S] Rura w BOM: netto + liczba sztang z `summarizeCutList` (jedna funkcja z listą cięć).
  - [P2][M] Zapisywać typ kształtki (ELB/TEE/RED/FLG/VLV) przy imporcie ze skanu i szkicu; do tego czasu łączyć kształtkę z korpusem na złączu niezależnie od średnicy.
  - [P3][S] Usunąć zdublowaną ilość, martwe `_staleCache` i gałąź SharedPreferences, poprawić podpowiedź.
  - [P3][M] Liczba spoin i inch-dia; uszczelki i śruby do par kołnierzy.

## project-components — Komponenty / Heat
- **Cel i dla kogo:** przypisanie numerów wytopu (heat) i zdjęć atestu do komponentów projektu (identyfikowalność materiału, QC).
- **Co zawiera:** `lib/screens/project_components_screen.dart` (ikona pudełka w AppBar `FitterScreen`), `lib/database/component_heat_dao.dart` (tabela `component_heats`). Lista: START pierwszego segmentu + END każdego segmentu, klucz `S001_END`. Dialog: numer heat, notatka, zdjęcie (kopiowane do `<documents>/heat_photos`).
- **Stan:** błędy (dane się zapisują, ale nie da się ich odczytać).
- **Błędy potwierdzone:**
  - [K] **Wpisanych numerów heat nie da się nigdzie zobaczyć.** Ekran pokazuje tylko licznik „Heat: 2” (`:219-225`). `ComponentHeatDao.listForComponent` nie jest wywoływane nigdzie w `lib/`; `heat_no` z `component_heats` nie trafia do żadnego widoku, PDF, CSV ani BOM. Nie ma edycji ani usuwania. Dla QC dane są martwe.
  - [K] Klucz heat opiera się na `seq_no` (`:62`, `:74`), a usunięcie segmentu nie rusza `component_heats` (`segment_dao.dart:163-166`). Po usunięciu ostatniego segmentu nowy dostaje ten sam numer (`nextSeqNo` = MAX+1), więc **heat starego komponentu „przechodzi” na nowy**. To błędna identyfikowalność. Po edycji segmentu (zmiana komponentu END) heat też zostaje przy kluczu.
  - [K] Lista zakłada ciągłą trasę: pokazuje START tylko dla pierwszego segmentu (`:58-68`). START każdego segmentu, który nie zaczyna się od END poprzedniego (odgałęzienie, drugi spool, OPEN END), nie ma wiersza, więc heat tej kształtki nie da się wpisać.
  - [K] **Brak rur**: heat rury (najważniejszy atest) nie ma gdzie trafić.
  - [K] Kształtki ze skanu i szkicu (brak `library_id`) mają etykietę „OPEN END” i ikonę końca otwartego (`:217`, `:223`).
  - [K] Pusty numer heat po „Zapisz” niczego nie zapisuje i niczego nie komunikuje; wybrane zdjęcie przepada (`:143-145`).
  - [K] Zdjęcia heat są od niedawna kopiowane do katalogu aplikacji (`:151-164`), ale `DeletedProject.ownedPhotoPaths` bierze tylko `heat_photos` (`project_dao.dart:37-47`; komentarz „never copied anywhere” jest już nieaktualny). Po usunięciu projektu pliki zdjęć heat zostają osierocone na dysku.
  - [K] `_load` bez sprawdzenia `mounted` (`:37-46`) kończy się `setState` po `dispose` przy szybkim wyjściu.
- **Problemy UX w terenie:** [O] dwa osobne ekrany heat („Komponenty / Heat” i „Zdjęcia certyfikatów / heat”) z innym modelem danych mylą użytkownika. [K] Pole heat nie ma `textCapitalization.characters`; każdy wiersz robi 2 zapytania `FutureBuilder`.
- **Brakujące funkcje:** [O] lista heat per komponent z podglądem zdjęcia, edycja i usuwanie; heat rury per segment; eksport raportu identyfikowalności (segment/spoina → heat, PDF/CSV); skan kodu z etykiety.
- **Testy:** tylko smoke i przypadek zdjęcia z aparatu w `heat_photo_camera_test.dart`. Brak testów listy instancji, kluczy po usunięciu segmentu i odczytu heat.
- **Propozycje:**
  - [P1][M] Widok i edycja wpisów heat (lista pod komponentem, usuwanie z potwierdzeniem) oraz heat w PDF i CSV listy cięć.
  - [P1][M] Klucz heat oparty na stabilnym id (segment.id + strona albo osobna encja „kształtka”), nie na `seq_no`; kasowanie lub przenoszenie przy usunięciu segmentu.
  - [P2][M] Wiersze dla każdego START i END (bez założenia ciągłości) i dla rury każdego segmentu.
  - [P2][S] Etykiety z `*_kind`; `ownedPhotoPaths` uwzględnia zdjęcia z `component_heats` (z kontrolą `isWithin`).
  - [P2][L] Scalić z `heat-photos` w jeden moduł „Identyfikowalność materiału”.

## heat-photos — Heat numbers (zdjęcia atestów)
- **Cel i dla kogo:** galeria zdjęć etykiet i atestów (MTR) projektu z opcjonalnym przypisaniem do komponentu z biblioteki.
- **Co zawiera:** `lib/screens/heat_photos_screen.dart` (ikona aparatu w AppBar `FitterScreen`), `HeatPhotoDao`, `heat_photo_capture.dart` (aparat, galeria, odzysk zdjęcia po zabiciu aplikacji przez Androida), `heat_photo_storage.dart` (kopia do `<documents>/heat_photos`, objętego backupem).
- **Stan:** częściowo.
- **Błędy potwierdzone:**
  - [K] Ekran nazywa się „Heat numbers”, a dialog „Dodaj HEAT number”, ale **nie ma pola na numer wytopu**: jest tylko komponent i notatka (`:92-133`). Tabela `heat_photos` nie ma kolumny `heat_no` (`db.dart:592-600`). Numer da się zapisać tylko jako wolny tekst w notatce, więc nie da się po nim wyszukiwać ani go eksportować.
  - [K] Wybrany komponent (`library_component_id`) zapisuje się, ale nie jest nigdzie wyświetlany. Karta pokazuje tylko notatkę i zdjęcie (`:259-292`).
  - [K] Lista komponentów w dialogu pochodzi z `listFor(p.diameterMm)` (`:42-46`), czyli ze średnicy początkowej projektu. Kształtek za redukcją (inna średnica) nie da się wybrać.
  - [K] Usunięcie zdjęcia kasuje plik z `item.imagePath` bez sprawdzenia, czy leży w katalogu aplikacji (`:194-199`). Wiersze sprzed kopiowania wskazują plik w galerii użytkownika, więc aplikacja skasuje jego prywatne zdjęcie. `ProjectDao.purgePhotoFiles` robi to poprawnie, z `p.isWithin` (`project_dao.dart:238-240`).
  - [K] Każda karta ma dolny padding powiększony o `MediaQuery.viewPaddingOf(context).bottom` (`:255`). Na iPhonie to +34 px pustego miejsca pod każdym zdjęciem (miało być tylko na końcu listy).
  - [K] `_load` bez sprawdzenia `mounted` (`:37-55`); `file.existsSync()` w `build` (`:277`).
- **Problemy UX w terenie:** [K] tap na zdjęciu nic nie robi, więc numeru z etykiety nie da się powiększyć. [O] Brak daty zdjęcia i przypisania do segmentu.
- **Brakujące funkcje:** [O] pole heat i nr atestu (MTR) z wyszukiwarką, podgląd pełnoekranowy z zoomem, przypisanie do segmentu lub rury, eksport paczki (PDF z miniaturami).
- **Testy:** `heat_photo_camera_test.dart` (aparat, galeria, Windows, odzysk zdjęcia, brak zgody), `heat_photo_dao_test.dart`. Brak: usuwania wiersza ze ścieżką spoza katalogu, wyświetlania komponentu.
- **Propozycje:**
  - [P2][S] Usuwać plik tylko w obrębie `heatPhotosDirectory()` (ta sama reguła co `purgePhotoFiles`).
  - [P2][M] Pole `heat_no` (migracja v23) i wyszukiwarka; pokazywać komponent na karcie; lista kształtek ze wszystkich średnic projektu.
  - [P2][S] Podgląd pełnoekranowy (`InteractiveViewer`).
  - [P3][S] Padding tylko na końcu listy; sprawdzenie `mounted` w `_load`.

## component-library — Biblioteka komponentów
- **Cel i dla kogo:** własny katalog take-offów montera (kolana, trójniki: wymiar do osi; redukcje, zawory, kołnierze: długość) dla SS i CS, używany przez builder do wyliczania CUT.
- **Co zawiera:** `lib/screens/component_library_screen.dart` (menu Monter → „Biblioteka komponentów”), `lib/database/component_library_dao.dart` (`listFor` z tolerancją 0,05 mm, `insert`, `listAll`, `getById`). Wpisy tworzy też builder przez `_createMissingComponent`.
- **Stan:** błędy (biblioteka tylko przyrasta; źle wpisanej wartości nie da się poprawić).
- **Błędy potwierdzone:**
  - [K] **Brak edycji i usuwania wpisu.** DAO nie ma `update` ani `delete` (`component_library_dao.dart:25-88`), a ekran pokazuje tylko listę z kopiowaniem (`:85-104`). Błędny take-off (762 zamiast 76,2) zostaje na zawsze. Gdy jest jedynym dopasowaniem, builder wybiera go automatycznie bez pytania (`segment_builder_screen.dart:741-742`), a od niego zależy każdy następny CUT.
  - [K] UNIQUE (`material_group, type, diameter_mm, wall_thickness_mm, diameter_out_mm`) (`db.dart:548`) **blokuje dodanie poprawionej redukcji** o tych samych średnicach („Nie udało się zapisać (możliwy duplikat)”). Razem z długością 0 z buildera daje to trwały błąd CUT (zob. `segment-builder`). Dla kolan i trójników `diameter_out_mm` jest NULL, więc SQLite nie wymusza UNIQUE i powstają duplikaty w pickerze.
  - [K] **Pomoc ekranu obiecuje funkcje, których nie ma:** „Dotknij komponentu aby edytować”, „Przesuń w lewo aby usunąć”, „Filtruj … w polu wyszukiwania” (`help_button.dart:285-289`). Filtra też nie ma (scenariusz manifestu „filtruje po 100 mm” jest niewykonalny).
  - [K] Pole „Tryb długości FACE/AXIS/END” (`:277-287`) zapisuje `measurement_mode`, którego nic nie czyta. `LibraryComponent.supportsIsoRef` i `calcValueMm` są martwe; builder pyta o punkt odniesienia osobno. Warunek `_type != 'OPEN_END'` (`:172`) jest martwy, bo takiego typu nie ma w liście. Typu „Inne” z palety buildera nie ma w dialogu.
  - [K] Błędy pokazują surowy wyjątek `$e` (`:41-42`, `:213`). Podtytuł wiersza to „ID: 3f9a1c2b” (`:93`).
- **Problemy UX w terenie:** [O] lista płaska, sortowana tylko po typie; przy 50+ wpisach bez grupowania po materiale i średnicy trudno coś znaleźć. [K] Pole średnicy redukcji to tylko „Średnica (mm)”, bez wskazania, że to wlot.
- **Brakujące funkcje:** [O] wczytanie wartości z katalogu B16.9/B16.5/B16.10 (`TakeoutCatalog`) jednym tapnięciem; odmiany kolan LR/SR/3D; strony trójnika; import i eksport biblioteki (przekazanie w brygadzie).
- **Testy:** `component_library_dao_test.dart` (tolerancja, reduktory wlot/wylot, grupa materiału) oraz smoke. Brak testów ekranu (walidacja, duplikat redukcji).
- **Propozycje:**
  - [P1][M] Edycja i usuwanie wpisu (usuwanie z ostrzeżeniem, gdy wpis jest używany w segmentach; edycja pokazuje, które segmenty przeliczyć).
  - [P2][S] Filtr po typie, średnicy i materiale; grupowanie; czytelny opis zamiast ID.
  - [P2][M] „Dodaj z katalogu ASME” (DN → wartości z `TakeoutCatalog`).
  - [P3][S] Usunąć `measurement_mode` z UI (albo zacząć go używać jako domyślnego punktu odniesienia), usunąć martwe metody; poprawić teksty pomocy.

## new-cut-list-project — Nowy projekt (stary ekran, osierocony)
- **Cel i dla kogo:** historyczny formularz zakładania projektu z listą typowych OD.
- **Co zawiera:** `lib/screens/new_cut_list_project_screen.dart`. **Brak wejścia w aplikacji**: `tool_registry.dart:52-56` wprost wymienia go jako sierotę; odwołują się do niego tylko `module_smoke_test.dart` i `tool_registry_test.dart`.
- **Stan:** martwy kod z błędami (gdyby ktoś go podłączył, traci dane).
- **Błędy potwierdzone:**
  - [K] Po utworzeniu projektu ekran robi `pushReplacement` do `SegmentBuilderScreen`, a jego wynik (zbudowany segment) jest **odrzucany** i nic nie zapisuje się do `segments` (`:117-133`).
  - [K] Walidator rzazu dopuszcza tylko 1–2 mm (`:295`), więc plazma CNC (2–3,5 mm) nie przejdzie. Gap jest na sztywno 0 (`:101`). Niepoprawna długość sztangi lub rzaz po cichu zamieniają się na 6000 / 1,5 (`:72-75`), a sztanga 0 lub ujemna przechodzi.
  - [K] `.then()` bez `await` po `insert` (`:117`), a błąd pokazuje surowy wyjątek.
- **Problemy UX w terenie:** nie dotyczy (ekran niedostępny).
- **Brakujące funkcje:** jedyna rzecz warta przeniesienia do `new-project` to lista typowych OD (`:35-51`).
- **Testy:** tylko smoke (renderowanie).
- **Propozycje:**
  - [P3][S] Usunąć ekran i jego wpisy w teście smoke i w manifeście; listę OD (lepiej: DN + schedule) przenieść do `NewProjectScreen`.

---

## Obserwacje przekrojowe (grupa G1)
- [K] **Martwy kod** poza ekranami: `lib/models/component_library.dart` (`ComponentLibraryItem`), `segment_item.dart`, `pipe_run.dart`, `models/index.dart`; `lib/services/cut_packing_service.dart` i `cut_calculator.dart` (używane tylko w testach; `CutPackingService` pakuje bez rzazu, czyli drugi, rozbieżny algorytm); `SegmentDao.sumCutForProject` (w dodatku z dokładnym `=` na REAL), `ProjectDao.updateName`, `LibraryComponent.calcValueMm` i `supportsIsoRef`.
- [K] **Pomoc ekranów rozjeżdża się z UI:** builder obiecuje „Przeciągaj komponenty aby zmienić kolejność” i „przycisk +” (`help_button.dart:263-264`), projekt obiecuje „+ lub FAB” (`:242`), biblioteka obiecuje edycję, usuwanie i filtr (`:285-289`).
- [K] **Offline:** cała grupa działa lokalnie (SQLite, pliki); udostępnianie idzie przez systemowy arkusz. Brak ryzyk sieciowych.
- [O] **Dwa modele identyfikowalności** (`component_heats` i `heat_photos`) plus heat w dzienniku spoin (`weld_journal.heat_no1/2`) nie są ze sobą powiązane. Monter wpisuje ten sam wytop w trzech miejscach.

## Top 5 w grupie
1. **[P1][M] Biblioteka komponentów + redukcja:** dodać edycję i usuwanie wpisów; przy zakładaniu redukcji w builderze pytać o długość H (z podpowiedzią B16.9) i kierunek. Dziś redukcja z palety ma L = 0, więc „ISO do końca redukcji” daje rurę za długą o całą redukcję (sonda: 847,6 zamiast 745,6 mm). UNIQUE blokuje poprawkę, a pomoc obiecuje edycję, której nie ma.
2. **[P1][M] Numery wytopów:** wpisy `component_heats` są niewidoczne (tylko licznik), przypięte do `seq_no` (po usunięciu segmentu przechodzą na inny komponent), bez wierszy dla rur i dla START-ów nieciągłej trasy. Ekran „Heat numbers” nie ma pola na numer. Potrzebny jeden moduł identyfikowalności z odczytem, edycją i eksportem do PDF/CSV.
3. **[P2][S] Poprawność trasy i BOM:** ekspander (redukcja odwrotnie) ma przestawiać średnicę trasy (test `fitter_route_test.dart:154` utrwala błąd). BOM ma liczyć rurę w sztangach lub z rzazem, spójnie z listą cięć, a nie jako CUT netto. Kształtki ze skanu i szkicu (redukcja) nie mogą liczyć się podwójnie.
4. **[P2][M] Lista cięć przy pile:** stan „ucięte” per kawałek (offline) i kratki w PDF; odcinek dłuższy niż sztanga dzielony z odjęciem gapu spoiny łączącej; jedna reguła zaokrąglenia na ekranie, w PDF i w CSV.
5. **[P2][M] Ergonomia terenowa segmentów:** cele dotyku ≥ 48 dp (X na chipie 14 px, paleta ok. 34 dp), czcionki ≥ 12–14 px (dziś 7–11 px), przeładowanie listy segmentów bez utraty przewijania, Cofnij dla usunięcia segmentu, „kontynuuj od ostatniego komponentu” i podpowiedzi take-offów z `TakeoutCatalog`.
