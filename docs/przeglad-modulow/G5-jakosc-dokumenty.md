# Przegląd modułów G5 — jakość i dokumenty spawalnicze

Data: 2026-09-26 · gałąź `fix/audyt-2026-08-29` (HEAD `40f254e`) · przegląd tylko do odczytu.
Perspektywa: inspektor spawalniczy / koordynator spawania (ISO 3834-2, ISO 9606-1, ISO 15614-1, ASME IX, ASME B31.3 §341/§344, EN 13480-5, ASME BPE) i inżynier Flutter.

**Jak to sprawdzono.**
- Przeczytałem kod domeny, DAO, ekranów i eksportów wszystkich 10 modułów.
- Uruchomiłem testy modułów: `flutter test --no-pub` na 21 plikach/katalogach → **400 testów, wszystkie zielone**.
- Podejrzenia sprawdziłem skryptem w czystym Dart (`dart --packages=.dart_tool/package_config.json verify_g5.dart`, skrypt w scratchpadzie, nie w repo). Wynik skryptu jest cytowany przy każdym błędzie oznaczonym **[potwierdzone skryptem]**.
- „Potwierdzone” = wynika wprost z kodu albo z uruchomienia. „Opinia” = ocena inspektora, bez twardego dowodu błędu.

---

## weld-journal — Dziennik spoin

- **Cel i dla kogo:** Rejestr spoin (weld log / weld map) dla spawacza, brygadzisty i QC. Z niego powstaje część data booka: identyfikacja złącza, kto spawał (grań i lico), WPS, spoiwo, parametry, NDT, naprawy, PWHT i odbiór.
- **Co zawiera (funkcje, wejście, pliki):**
  - Model spoiny v20, ok. 40 pól: ISO/rewizja, linia, spool, pakiet testowy, typ złącza, W/M, pozycja, wytopy, spoiwo, podgrzanie / temp. międzyściegowa / HI z konwencją EN/ASME, stemple grani i lica, kupon, PWHT, odbiór (`lib/domain/weld_journal/weld_entry.dart`).
  - NDT per metoda VT/PT/MT/RT/UT: zakres (wymagane / wybrane / dodatkowe §341.3.4), wynik, nr raportu, data (`weld_ndt.dart`).
  - Naprawy R1/R2 z zapisem stanu sprzed naprawy (`weld_repair.dart`).
  - Historia zmian pole po polu w tej samej transakcji; miękkie usuwanie i przywracanie (`weld_history.dart`, `lib/database/weld_journal_dao.dart`).
  - Naturalne sortowanie numerów, podpowiedź kolejnego numeru, ostrzeżenie o duplikacie (`weld_numbering.dart`).
  - Filtry, a eksport obejmuje dokładnie to, co widać na liście (`weld_filter.dart`).
  - Statystyki RT/UT i licznik §341.3.4 (`weld_stats.dart`).
  - Kontrola zgodności z WPS i z uprawnieniami, ze znaczkami na liście (`weld_compliance.dart`).
  - Eksport CSV (BOM, `;`, CRLF) i PDF A4 poziomo z dwiema tabelami, legendą i blokiem podpisów (`lib/services/weld_journal_export.dart`).
  - UI: `lib/screens/weld_journal_screen.dart`, `lib/widgets/weld_journal/*`.
- **Stan:** działa, z błędami w dokumentacji odbiorowej (niżej).
- **Błędy potwierdzone:**
  1. **Naprawa nie kasuje odbioru inspektora** — `lib/domain/weld_journal/weld_repair.dart:143-150`. `planWeldRepair` zeruje status i NDT, ale `inspector` / `inspectedAt` zostają. Wejście: spoina NOK z odbiorem „J. Inspektor 2025-10-03” → naprawa R1 → wynik `status=PENDING inspector="J. Inspektor" inspectedAt="2025-10-03"` **[potwierdzone skryptem]**. Oczekiwane: odbiór wyczyszczony, a stary zapisany w rekordzie naprawy. Skutek: PDF (tabela 2, kolumna „Odbiór”) pokazuje przyjęcie spoiny, która czeka na ponowne badanie. To samo dotyczy PWHT i twardości: po naprawie spoiny wymagającej PWHT stary nr wykresu zostaje bez ostrzeżenia.
  2. **Status i odbiór niezależne od NDT** — `lib/widgets/weld_journal/weld_editor_sheet.dart:794-799` (chipy statusu) i `weld_status_dialog.dart` (brak walidacji). Da się zapisać `OK` przy RT = NOK albo przy NDT „czeka na wynik”. Da się też wpisać „Odbiór — data” przy statusie PENDING albo wcześniejszą niż data spawania. Oczekiwane: blokada albo ostrzeżenie z wpisem do historii, tak jak przy WPS.
  3. **Znaczki zgodności fałszywie czerwone po nowym potwierdzeniu ISO 9606-1** — przyczyna i dowód w module certificate-register, pkt 1. Lista dziennika (`weld_journal_screen.dart:137-163`) ocenia stare spoiny na dzień spawania. Po wpisaniu nowszego potwierdzenia spoiny z okresu poprzedniego potwierdzenia dostają „spawacz bez ważnych uprawnień w dniu spawania”. Każda edycja takiej spoiny zapisuje do historii fałszywe „Zapisano mimo ostrzeżeń”.
  4. **Pozycja ASME kontra ISO 6947 daje „poza WPS” (czerwony) zamiast „nie da się porównać”** — `lib/domain/wps/weld_range_check.dart:335-346`. Spoina `5G` przy WPS „PA, PC, PF” → `[position/outOfRange]` **[potwierdzone skryptem]**. Edytor sam podsuwa obie konwencje w jednej liście (`weld_entry.dart:39-44`), więc fałszywy alarm trafia do historii spoiny jako decyzja „mimo ostrzeżeń”.
  5. **Licznik §341.3.4 liczy VT NOK bez zakresu jako odrzut losowy** — `weld_stats.dart:134-141`. VT NOK bez ustawionego zakresu → `rejects=1 toExamine=2` **[potwierdzone skryptem]**. Pusty zakres to „nie wiadomo”, a nie „wyrywkowo”.
  6. **Walidacja dat bez zakresu roku** — `weld_dates.dart:20-42`. `2062-09-01` i `0026-09-01` przechodzą **[potwierdzone skryptem]**. Taka spoina po cichu wypada z ciągłości (`journal_welds.dart:44`) i psuje „Zakres dat” w nagłówku PDF.
  7. **Kalendarz może dostać datę spoza zakresu** — `weld_editor_sheet.dart:535-540`. `initialDate` jest brany z pola, a zakres to −10 / +1 rok, bez przycięcia. Stara spoina (>10 lat) albo literówka 2062 → asercja `showDatePicker` w debug i niepewne zachowanie w release. Zaobserwowane w kodzie, nie odtworzone na urządzeniu.
- **Problemy UX w terenie:**
  - Kafel spoiny: cały kafel otwiera edycję; status i menu mają ≥ 48 dp. Status zmienia się tylko przez dialog z potwierdzeniem — dobrze. Przypadkowe dotknięcie otwiera kartę, ale strażnik „Porzucić wpis?” chroni dane.
  - Wiersz „Podgrzanie / Międzyścieg. / kJ/mm” to trzy pola w jednym rzędzie (`weld_editor_sheet.dart:907-912`). Na telefonie ok. 100 dp szerokości, etykiety się ucinają; w rękawicach trafia się w sąsiednie pole. (opinia)
  - Stemple spawaczy to wolny tekst bez podpowiedzi znanych stempli i bez walidacji `kStampRegex`. „jk-14” i „JK-14” w nagłówku PDF są dwoma spawaczami (`weld_journal_export.dart:360-371`, porównanie z rozróżnieniem wielkości liter).
  - Da się edytować spoinę usuniętą (baner jest, zapis przechodzi) — P3.
  - Brak wymogu tożsamości: bez ustawionego stempla historia zapisuje „—” jako autora każdej zmiany. Dla audytu oznacza to zmianę bez autora.
- **Brakujące funkcje:**
  - PDF i CSV **nie zawierają historii zmian ani ostrzeżeń „zapisano mimo ostrzeżeń / poza WPS”**. Inspektor z data booka nie wie, że spoina była poza WPS. Komentarz `weld_history.dart:111` mówi o PDF, ale eksportu historii nie ma.
  - Brak blokady (zamrożenia) spoiny po odbiorze. Po wpisaniu inspektora każdy nadal może zmienić parametry; zmiana trafia do historii, ale nie widać jej w PDF.
  - Brak zdjęć spoiny i załączników (raport RT/UT).
  - Brak znacznika „checklista przed spawaniem wykonana” (patrz pre-weld-checklist).
  - Brak eksportu mapy spoin pod test package (pakiet jest tylko kolumną).
  - Brak wydruku rejestru napraw z odsetkiem napraw na spawacza (jest tylko w arkuszu podsumowania).
  - Czcionka tabel PDF: 6,5 pt, nagłówki 6 pt (`weld_journal_export.dart:948, 1013`). Na wydruku A4 i w kopii skanowanej na granicy czytelności. (opinia)
- **Testy:**
  - Pokryte: DAO z historią, soft delete i naprawami (`test/database/weld_journal_dao_test.dart`); domena — numeracja, filtry, statystyki, historia, naprawy, daty, zgodność; ekran — duplikat, „Zapisz i następna”, kupon, zgodność; CSV i render PDF.
  - Brak testów na: odbiór po naprawie, status OK przy NDT NOK, pozycję 5G vs PF, VT NOK bez zakresu, rok spoza zakresu, obecność historii i ostrzeżeń w PDF.
- **Propozycje:**
  - [P1][S] `planWeldRepair`: wyczyścić `inspector`, `inspectedAt`, `pwhtChart`, `hardness` (albo pytać o PWHT) i zapisać je w `WeldRepair` (nowe pola / JSON jak `prev_ndt`).
  - [P1][M] Reguły spójności przy zapisie i przy zmianie statusu: OK wymaga braku NOK i braku „czeka”; data odbioru ≥ data spawania i ≥ daty NDT. Tryb ostrzeżenia + wpis `CHECK`, jak przy WPS.
  - [P2][S] Pozycje z innego systemu (G/F kontra P*) → `RangeIssueSeverity.cannotCompare`; docelowo tabela odpowiedników ISO 6947 ↔ ASME (5G→PF/PG itd.).
  - [P2][M] PDF: kolumna „Uwagi QC” z ostrzeżeniami zgodności i załącznik „Historia zmian” (opcjonalny) dla wybranych spoin.
  - [P2][S] Stats: nie liczyć NOK bez zakresu do §341.3.4 (albo pokazywać osobno jako „brak zakresu”); grupować per metoda.
  - [P2][S] `normalizeWeldDate`: rok w zakresie 2000..(dziś+1); ostrzeżenie o dacie z przyszłości.
  - [P2][M] Blokada edycji pól wykonawczych po odbiorze (odblokowanie z uzasadnieniem → historia).
  - [P3][S] Podpowiedź stempli (lista znanych), walidacja formatu, porównanie stempli bez rozróżniania wielkości liter w nagłówku PDF.
  - [P3][S] Przycinać `initialDate` kalendarza do zakresu.

## coupon-log — Log kuponów

- **Cel i dla kogo:** Dzienny rejestr kuponów próbnych (orbital, żywność/pharma, ASME BPE MJ-7.3, AWS D18.1/D18.2) dla spawacza orbitalnego i QC.
- **Co zawiera:**
  - Data, spawacz, maszyna/głowica, wymiar, nr i parametry programu, O₂ ppm, przebarwienie 1–10 (AWS D18.2), wynik OK/NOK, uwagi (`lib/domain/weld_journal/coupon_entry.dart`).
  - Edytor ze strażnikiem porzucenia (`lib/widgets/weld_journal/coupon_editor_sheet.dart`).
  - Lista z usuwaniem i „Cofnij” (`lib/screens/coupon_log_screen.dart`).
  - Eksport CSV i PDF (`lib/services/coupon_log_export.dart`).
  - Wybór kuponu do spoiny (`coupon_picker_sheet.dart`). DAO: `lib/database/coupon_dao.dart`.
- **Stan:** częściowo — działa jako notatnik, ale nie spełnia wymogów zapisu jakości (brak historii, twarde usuwanie, rozjazd ze spoinami).
- **Błędy potwierdzone:**
  1. **Odnośnik kuponu w spoinie nie śledzi zmian kuponu.** `weld_editor_sheet.dart:508-516` zapisuje `c.reference` (zawiera wynik, np. „… · OK”) raz, przy wyborze. `CouponDao.update` (`coupon_dao.dart:29-32`) nie aktualizuje spoin. Wejście: kupon OK podpięty do spoin → później zmieniony na NOK. Wynik: w dzienniku i PDF spoin dalej „… · OK”. Oczekiwane: odświeżenie odnośnika albo ostrzeżenie i lista spoin do przejrzenia.
  2. **Można podpiąć kupon NOK bez ostrzeżenia** — `coupon_picker_sheet.dart:85-86`. Kupon NOK wybiera się jednym dotknięciem. Nagłówek pliku (linie 3-6) sam wskazuje to ryzyko jako powód powstania pickera. Brak też ostrzeżenia, gdy data kuponu ≠ data spoiny.
  3. **Twarde usuwanie bez historii** — `coupon_dao.dart:34-37`, `coupon_log_screen.dart:129`. Dialog mówi „usunięty z dziennika audytowego”. „Cofnij” działa tylko do zniknięcia paska. Spoiny zostają z `coupon_id` wskazującym na nieistniejący wiersz, a edytor dalej pokazuje „Powiązany z logiem kuponów” (`weld_editor_sheet.dart:979-988`).
  4. **Nowy kupon startuje z wynikiem OK** — `coupon_log_screen.dart:82`, `coupon_editor_sheet.dart:65`. Domyślne „przyjęte” w rejestrze akceptacji to błąd procesu. Oczekiwane: brak wyniku / „do oceny”.
  5. **Brak spójności przebarwienie–wynik** — `coupon_editor_sheet.dart:136-172`. Poziom 7–10 („Odrzut”) z wynikiem OK zapisuje się bez słowa.
- **Problemy UX w terenie:**
  - Próbki przebarwień 48×48 dp — dobrze.
  - Pola daty i O₂ w jednym rzędzie z innymi; data tylko ręcznie, bez kalendarza (w dzienniku kalendarz jest).
  - Picker pokazuje wszystkie kupony bez filtra dnia / maszyny. Po miesiącu lista ma kilkadziesiąt pozycji.
- **Brakujące funkcje:**
  - Historia zmian i podpis akceptującego (kto przyjął kupon, kiedy); przy BPE przyjmuje zwykle inspektor właściciela.
  - Pola: nr wytopu / partii rury, gaz osłonowy i formujący z partią, wolfram, OD/ID przetopu (boroskop).
  - Zdjęcie kuponu (ID/OD) — w pharma standard.
  - Filtr eksportu (zakres dat, maszyna, spawacz); PDF bez nagłówka projektu i bez bloku podpisów.
  - Lista spoin powiązanych z kuponem.
- **Testy:**
  - Pokryte: edycja i dodanie z O₂/przebarwieniem (`test/screens/coupon_log_screen_test.dart`), eksport (`test/services/coupon_log_export_test.dart`), DAO nowych pól.
  - Brak testów na: usuwanie z podpiętymi spoinami, NOK w pickerze, zmianę wyniku po podpięciu.
- **Propozycje:**
  - [P1][M] Po zmianie wyniku lub usunięciu kuponu: aktualizacja `coupon_ref` spoin (z wpisem historii spoiny) albo przynajmniej ostrzeżenie z listą spoin; miękkie usuwanie kuponu.
  - [P2][S] Picker: kupony NOK wyszarzone z potwierdzeniem „Spoina na kuponie NOK?”; domyślnie kupony z dnia spoiny.
  - [P2][S] Nowy kupon bez wyniku (trzeci stan „do oceny”); ostrzeżenie przy przebarwieniu ≥ 5 i wyniku OK.
  - [P2][M] Tabela historii kuponów (jak `weld_journal_history`) i pole „przyjął / data”.
  - [P3][M] Zdjęcie kuponu, filtr eksportu, nagłówek i blok podpisów w PDF.

## pre-weld-checklist — Checklista przed spawaniem

- **Cel i dla kogo:** Szybka kontrola złącza przed zajarzeniem łuku; dla spawacza, głównie rury nierdzewne higieniczne.
- **Co zawiera:**
  - 11 punktów uniwersalnych + dodatki wg P-No z katalogu materiałów (1, 4, 5A, 15E, 8, 10H, 43).
  - Zaznaczenia zapisywane na dany dzień w SharedPreferences i czyszczone następnego dnia. Po przywróceniu wymagane potwierdzenie „ta sama spoina”.
  - Reset z potwierdzeniem i „Cofnij”; stabilne identyfikatory punktów.
  - Plik: `lib/screens/pre_weld_checklist_screen.dart`.
- **Stan:** działa jako pomoc pamięci. Nie jest zapisem jakości.
- **Błędy potwierdzone:**
  1. **Lista „uniwersalna” jest tylko dla TIG i nierdzewki** — `pre_weld_checklist_screen.dart:135-169`. Gaz formujący, O₂, pre-purge, wolfram, narzędzia tylko do nierdzewki, kupon dnia. Przy P-No 1 / 4 / 5A / 15E (MMA, stal węglowa i Cr-Mo) spawacz musi odhaczyć punkty, które go nie dotyczą, żeby zobaczyć „Gotowe — możesz zajarzać łuk”. To uczy odhaczania bez sprawdzania. Brak opcji „nie dotyczy”.
  2. **Błędne lub mylące treści punktów:**
     - `p1-bevel-clean` (linia 45-47): „kupon poradiowany jeśli >25 mm” — treść bez sensu technicznego. Ukos 30° jest wg ISO 9692-1; rury ASME B16.25 mają 37,5°.
     - `p1-low-h-electrode` (43): „drut ER70S-2 w zamkniętym piecu” — piec dotyczy elektrod, nie drutu.
     - `p8-argon-pure` (99-101): „brak N₂ w gazie formującym” — dla austenitów formowanie N₂+H₂ (ISO 14175 N5) jest powszechne. Sama biblioteka WPS podaje je jako przykład (`wps_record.dart:101`). Wiążąca jest WPS.
     - `p8-passivation` (102-104): na sztywno „kwas azotowy”, a moduł pasywacji podaje też cytrynowy.
     - `p43-argon-pure` (127): „brak Helium” — mieszanki Ar/He są typowe dla stopów Ni. (opinia)
  3. Dodatki są tylko dla P-No `'43'` (komentarz mówi „41-45”); inne stopy Ni nie dostają punktów.
- **Problemy UX w terenie:**
  - Wiersze punktów ≥ 48 dp — dobrze.
  - Chipy materiału mają czcionkę 11 pt (`linia 548, 562`) — w słońcu i w przyłbicy za małe. (opinia)
  - Materiał wybiera się z poziomego paska kilkunastu chipów bez wyszukiwania.
- **Brakujące funkcje:**
  - Zapis checklisty per spoina (nr spoiny, stempel, godzina) i powiązanie z dziennikiem. Punkt „Numer spoiny naniesiony” nie ma pola na numer.
  - Pola wartości: zmierzone O₂, podgrzanie, szczelina, przesunięcie lic (hi-lo). „O₂ poniżej limitu” bez liczby nic nie dokumentuje.
  - Brak punktów: ważne uprawnienia spawacza, WPS dostępna na stanowisku, identyfikacja spoiwa (partia), osłona od wiatru i wilgoci na montażu, miejsce przyłożenia masy.
  - Brak eksportu.
- **Testy:** Pokryte: liczba punktów, „Gotowe”, reset z cofaniem, zaznaczenia przywrócone, oddzielne PWHT P22/P91 (`test/screens/pre_weld_checklist_values_test.dart`). Brak testów treści punktów i scenariusza MMA na stali węglowej.
- **Propozycje:**
  - [P2][M] Zestawy punktów per proces (TIG orbital / TIG ręczny / MMA / MAG) i materiał; opcja „nie dotyczy” liczona osobno od „sprawdzone”.
  - [P2][S] Poprawić treści p1-bevel-clean, p1-low-h-electrode, p8-argon-pure, p8-passivation (odwołanie do WPS).
  - [P2][M] Zapis wykonanej checklisty do spoiny w dzienniku (pole / wpis historii `CHECKLIST`) z wartościami O₂ i podgrzania.
  - [P3][S] Chipy materiału ≥ 13 pt; wyszukiwarka materiału.

## heat-tint — Przebarwienia

- **Cel i dla kogo:** Karta kolorów przebarwień wewnątrz rury (AWS D18.2, poziomy 1–10) z orientacyjną akceptacją pharma/food; dla spawacza orbitalnego i inspektora wizualnego.
- **Co zawiera:** 10 poziomów z kolorem, nazwą PL/EN i O₂ próbki AWS D18.2 (`lib/data/heat_tint.dart`); ekran statyczny z legendą i zastrzeżeniem (`lib/screens/heat_tint_screen.dart`); `heatTintLevelForO2Ppm` używane w logu kuponów.
- **Stan:** działa (materiał referencyjny).
- **Błędy potwierdzone:**
  1. **Niespójność kryterium** — legenda `heat_tint_screen.dart:241` mówi „Pharma zwykle do poz. 2–3”, a poziom 3 ma werdykt „OK spożywczy”, nie pharma (`heat_tint.dart:57-58`). Ten sam poziom 3 dostaje dwie różne oceny na jednym ekranie.
  2. Kolory werdyktu różnią się między ekranem (food = niebieski, `heat_tint_screen.dart:85`) a edytorem kuponu (food = zielony `kPass`, `coupon_editor_sheet.dart:37-42`). Drobne.
- **Problemy UX w terenie:**
  - Porównanie koloru z ekranem telefonu jest z natury zawodne (jasność, balans bieli, słońce). Ekran nie ostrzega, że wiążący jest drukowany wzornik AWS D18.2 albo fizyczne próbki odbioru. (opinia)
  - Kafle 64 dp — czytelne.
- **Brakujące funkcje:**
  - Konfigurowalny limit akceptacji per projekt: ASME BPE ma osobne kryteria dla powierzchni elektropolerowanych i szlifowanych mechanicznie; 3-A/EHEDG też. Dziś werdykt jest na sztywno.
  - Brak rozróżnienia ID/OD i strefy HAZ.
  - Brak przejścia „oceń spoinę” → zapis do spoiny lub kuponu (poziom jest tylko w kuponie, nie w spoinie dziennika).
  - Brak zdjęcia porównawczego.
- **Testy:** `test/heat_tint_test.dart` — 7 testów danych (liczba poziomów, monotoniczność werdyktu, O₂, nazwy). Brak testu widżetu ekranu.
- **Propozycje:**
  - [P2][S] Ujednolicić werdykt poziomu 3 z legendą (albo legenda „pharma do 2, food do 4”) i kolory werdyktu.
  - [P2][M] Limit akceptacji ustawiany w ustawieniach projektu (BPE EP / BPE MP / 3-A / własny) i użyty w kuponie i w spoinie.
  - [P3][S] Wyraźna uwaga: „kolor na ekranie jest orientacyjny — porównuj z fizycznym wzornikiem”.
  - [P3][M] Pole „przebarwienie ID” w karcie spoiny (NDT VT).

## passivation — Trawienie i pasywacja

- **Cel i dla kogo:** Przewodnik procesowy obróbki powierzchni po spawaniu nierdzewki (kolejność kroków, BHP); dla spawacza i montera.
- **Co zawiera:** Dwie zakładki: trawienie (6 kroków) i pasywacja (5 kroków), ostrzeżenie HF i SDS, adnotacja „wiążące parametry: karta produktu + specyfikacja” (`lib/screens/passivation_screen.dart`).
- **Stan:** działa (treść statyczna).
- **Błędy potwierdzone:** brak błędów w logice (moduł nie ma logiki). Treść (opinia):
  - „Wykonaj po piklingu” sugeruje, że pasywacja zawsze następuje po trawieniu. Pasywację robi się też bez trawienia, np. po obróbce mechanicznej albo przez obieg chemiczny instalacji BPE.
  - Test ferroxylowy na powierzchniach produktowych pharma bywa niedopuszczalny (pozostałości); brak tego zastrzeżenia.
- **Problemy UX w terenie:** Tekst 13 pt, karty czytelne. Nie ma elementów dotykowych poza zakładkami.
- **Brakujące funkcje:**
  - Odwołania normatywne: ASTM A380/A967, ASME BPE (procedura pasywacji i jej kwalifikacja), EN 2516, jakość wody (DI/WFI, chlorki).
  - Rejestr wykonania do data booka: obszar/linia, środek i partia, czas, temperatura, płukanie (konduktywność), test, kto i kiedy. Dziś nic się nie zapisuje.
  - Wariant „pasywacja obiegowa instalacji”.
  - Checklisty z odhaczaniem.
- **Testy:** brak dedykowanych testów; tylko smoke (`test/audit/module_smoke_test.dart`, `test/widgets/tool_registry_test.dart`).
- **Propozycje:**
  - [P2][M] Prosty rejestr zabiegu (formularz + eksport PDF) powiązany z linią lub pakietem testowym.
  - [P3][S] Dopisać odwołania normowe i zastrzeżenia (ferroxyl, woda DI, pasywacja bez trawienia).
  - [P3][S] Test widżetu: obie zakładki i ostrzeżenie HF.

## certificate-register — Uprawnienia spawacza (rejestr)

- **Cel i dla kogo:** Rejestr certyfikatów EN ISO 9606-1 i ASME IX WPQ, status na dziś (ważność i ciągłość 6 mies.), przypomnienia 30 i 7 dni. Dla spawacza i koordynatora; zasila kontrolę spoin w dzienniku.
- **Co zawiera:**
  - Ocena certyfikatu: ISO — potwierdzenie co 6 mies.; ASME — łańcuch spoin QW-322.1; inna norma — tylko ważność (`lib/domain/qualification/certificate_status.dart`).
  - Daty kalendarzowe z przycięciem końca miesiąca (`qualification_dates.dart`).
  - Odczyt dziennika do ciągłości (`journal_welds.dart`) i plan przypomnień (`reminder_plan.dart`).
  - Serwis z migracją starych pól WPQR (`lib/services/welder_qualification_service.dart`).
  - Ekran z wpisem potwierdzenia, usuwaniem i kartą zasad (`lib/features/qualification/certificate_register_page.dart`).
- **Stan:** działa, z dwoma błędami reguły ISO 9606-1, które fałszują status (P1).
- **Błędy potwierdzone:**
  1. **Nowe potwierdzenie ISO „unieważnia” wstecz poprzednie okresy** — `certificate_status.dart:197-216` + `certificate_register_page.dart:199-202`. Rejestr trzyma tylko OSTATNIE potwierdzenie (nadpisywane). Przy ocenie na dzień spoiny potwierdzenie „z przyszłości” jest odrzucane, a kotwicą zostaje data egzaminu. Wejście: egzamin 2025-01-10, rzeczywiste potwierdzenia 2025-07-05 i 2026-01-05 (zapisane tylko drugie), spoina 2025-10-01 → `state=lapsed deadline=2025-07-10`, `covered=false`, issue „Ciągłość 6 mies.” **[potwierdzone skryptem]**. Oczekiwane: ważne (potwierdzenie z 2025-07-05). Skutek: fałszywe czerwone znaczki na starych spoinach i fałszywe wpisy „mimo ostrzeżeń” w historii.
  2. **Spóźnione potwierdzenie ISO „wskrzesza” wygasłe uprawnienie** — ta sama funkcja (`certificate_status.dart:202-211`). Dialog blokuje tylko datę z przyszłości (`certificate_register_page.dart:189`), nie sprawdza terminu. Wejście: egzamin 2025-01-10, brak potwierdzenia do 2025-07-10, potwierdzenie wpisane 2025-09-01 → na 2025-10-01 `state=valid deadline=2026-03-01` **[potwierdzone skryptem]**. Oczekiwane: `lapsed` od 2025-07-11. Wg ISO 9606-1 §9.2 brak potwierdzenia w terminie unieważnia certyfikat, a późniejszy podpis go nie przywraca. Gałąź ASME ma to poprawnie (`linia 236`).
  3. **Certyfikat bez stempla obejmuje każdego spawacza** — `lib/domain/weld_journal/weld_compliance.dart:288-300` (i `welder_qualification_service.dart:311-316`). Stempel ustawia się z tożsamości tylko wtedy, gdy ona istnieje (`certificate_edit_page.dart:153-154`). Wejście: certyfikat właściciela bez stempla, spoina kolegi „XY” → `welderNotQualified=false covered=true` **[potwierdzone skryptem]**. Oczekiwane: „brak certyfikatów XY”. Cichy fałszywy wynik „w porządku” dla brygady.
  4. **Zmiana stempla w tożsamości odcina certyfikaty** — certyfikaty zapisane ze starym stemplem nie pasują do nowego (`weld_compliance.dart:294-298`). Spoiny pokazują wtedy tylko „brak certyfikatów” (informację, nie ostrzeżenie). `refresh()` liczy ciągłość ASME dla wszystkich certyfikatów ze spoin bieżącego stempla (`welder_qualification_service.dart:203-209`). Ekran tożsamości nie ostrzega o tym (`welder_identity_setup_screen.dart:78-119`).
- **Problemy UX w terenie:**
  - Karta certyfikatu ma przyciski tekstowe 48 dp i usuwanie ikoną z domyślnym celem 48 dp — OK.
  - Usunięcie certyfikatu jest nieodwracalne (bez „Cofnij”) i kasuje skan (`welder_qualification_service.dart:231-235`).
  - „Potwierdzenie 6 mies.” pyta tylko o datę. Nie ma pola „kto potwierdził”, więc wpis to deklaracja spawacza, nie ślad podpisu koordynatora.
- **Brakujące funkcje:**
  - **Historia potwierdzeń** (data, kto: koordynator / egzaminator, nr pozycji na certyfikacie). Bez niej punkty 1 i 2 są nie do naprawienia.
  - Eksport rejestru uprawnień i „welder continuity log” (PDF/CSV) — typowy dokument dla QC i klienta.
  - Rejestr całej brygady: stempel edytowalny w certyfikacie, filtr po spawaczu.
  - Ostrzeżenie o przedłużeniu §9.3 b (dwie spoiny RT/UT z ostatnich 6 mies.) na podstawie NDT z dziennika.
  - Załącznik PDF certyfikatu (dziś tylko zdjęcie).
- **Testy:**
  - Pokryte: tabelaryczne statusy (`test/domain/qualification/certificate_status_test.dart`), daty, procesy, migracja i serwis (`test/services/welder_qualification_service_test.dart`), przypomnienia, baner, ekrany (`test/features/qualification_pages_test.dart`).
  - Brak testów na: ocenę na dzień przeszły przy nowszym potwierdzeniu, potwierdzenie po terminie, certyfikat bez stempla przy spoinie innego stempla, zmianę stempla.
- **Propozycje:**
  - [P1][M] Tabela `welder_cert_confirmations` (data, kto, uwagi). Ocena ISO na dzień D z łańcucha potwierdzeń jak w ASME (przerwa > 6 mies. przerywa łańcuch); migracja: obecne `last_confirmed_date` jako jedyny wpis.
  - [P1][S] Do czasu migracji: w `_recordConfirmation` odrzucać albo ostrzegać przy dacie późniejszej niż bieżący termin („uprawnienie wygasło — potrzebny nowy egzamin”).
  - [P2][S] Certyfikat bez stempla liczyć tylko dla stempla właściciela (`defaultStamp`), nie dla każdego; w formularzu pole „Stempel spawacza” (domyślnie z tożsamości).
  - [P2][S] Przy zmianie stempla w tożsamości: dialog „przepisać stempel w N certyfikatach?”.
  - [P2][M] Eksport PDF rejestru i logu ciągłości (per spawacz, z ostatnimi spoinami procesu).
  - [P3][S] „Cofnij” przy usuwaniu certyfikatu (skan kasowany dopiero po zniknięciu paska).

## certificate-edit — Formularz certyfikatu

- **Cel i dla kogo:** Wpis i edycja jednego certyfikatu ISO 9606-1 / ASME WPQ / innej normy: daty, zakres, zdjęcie.
- **Co zawiera:**
  - Norma i numer, egzaminator, data egzaminu, ważność, ostatnie potwierdzenie, przedłużanie §9.3 (a/b/c).
  - Zakres: procesy, grupa, t, D, pozycje, spoiwo, BW/FW; uwagi; zdjęcie (kopia do `heat_photos`).
  - Walidacja: min ≤ max, ważność ≥ egzamin.
  - Plik: `lib/features/qualification/certificate_edit_page.dart`, pola w `form_bits.dart`.
- **Stan:** działa, z lukami walidacji i UX.
- **Błędy potwierdzone:**
  1. **Brak ochrony przed utratą danych** — plik nie ma `PopScope` (grep: `PopScope` występuje tylko w edytorach dziennika i kuponu). Gest „wstecz” po wpisaniu kilkunastu pól certyfikatu porzuca wszystko bez pytania.
  2. **Stempel nie do ustawienia** — `certificate_edit_page.dart:153-154`. Stempel jest brany z tożsamości albo `null`, bez pola w formularzu. Skutki opisano w certificate-register, pkt 3–4.
  3. **Brak walidacji dat względem siebie i dnia dzisiejszego:**
     - Ostatnie potwierdzenie może być wcześniejsze niż egzamin albo z przyszłości. Ocena je po cichu ignoruje (`certificate_status.dart:202-205`), a formularz nic nie mówi.
     - Data egzaminu z przyszłości przechodzi.
  4. **Kalendarz może dostać datę spoza zakresu** — `form_bits.dart:120-125`. `initialDate = value` bez przycięcia do [dziś−15 lat, dziś+10]. Stary certyfikat (np. egzamin 2009 z migracji) → asercja `showDatePicker` w debug.
- **Problemy UX w terenie:**
  - Daty tylko z kalendarza (bez wpisania z klawiatury) — przy przepisywaniu certyfikatu z 2019 to wiele dotknięć.
  - „Dodaj zdjęcie certyfikatu” ma ikonę aparatu, ale otwiera wybór pliku z galerii (`linia 100-101`, `FileType.image`); brak aparatu i PDF.
  - Anulowanie po wybraniu zdjęcia zostawia osierocony plik w `heat_photos`.
- **Brakujące funkcje:** Pole stempla i nazwiska spawacza. Pole „pozycja/grubość próbki” (dziś tylko zakres — słusznie, ale inspektor porównuje też próbkę). Typ produktu P/T (blacha/rura) i BW/FW z podziałem (ISO 9606-1 ma zakres osobno dla rur i blach). Załącznik PDF.
- **Testy:** Pokryte: zapis nowego certyfikatu, min > max (`test/features/qualification_pages_test.dart`). Brak testów na porzucenie formularza, daty sprzeczne, zdjęcie.
- **Propozycje:**
  - [P2][S] `PopScope` ze strażnikiem „Porzucić zmiany?” (wzorzec z `coupon_editor_sheet.dart`).
  - [P2][S] Pole „Stempel spawacza” (wymagane przy więcej niż jednym stemplu w dzienniku).
  - [P2][S] Walidacja: potwierdzenie ∈ [egzamin, dziś], egzamin ≤ dziś, ostrzeżenie przy potwierdzeniu po terminie.
  - [P3][S] Przycięcie `initialDate`; wpis daty z klawiatury (`normalizeWeldDate`); aparat i PDF jako załącznik.

## wps-library — Biblioteka WPS

- **Cel i dla kogo:** Lista WPS przepisanych z dokumentów zakładu (zakresy, WPQR/PQR, plik); wymiana w brygadzie jako JSON; źródło kontroli „poza WPS” w dzienniku.
- **Co zawiera:**
  - Lista z wyszukiwaniem, import z pliku i schowka z wyborem „zastąp / kopia”, eksport JSON i kopiowanie, otwieranie pliku WPS, usuwanie (`lib/features/wps/wps_library_page.dart`).
  - Picker dla dziennika (`wps_picker_sheet.dart`).
  - Format JSON v1 z walidacją (`lib/domain/wps/wps_record.dart`), DAO `lib/database/wps_dao.dart`.
- **Stan:** działa. Brak kontroli wersji, a to jest dokument nadzorowany.
- **Błędy potwierdzone:**
  1. **Stary wpis WPS bez rewizji porównywany z najnowszą rewizją** — `weld_compliance.dart:134-156`. Spoina z `wps_ref` „WPS-9”, w bibliotece rev. A (stara) i rev. B (nowsza, węższy zakres) → porównanie z „WPS-9 rev. B” **[potwierdzone skryptem]**, także gdy rev. B powstała po dacie spoiny.
  2. **Edycja lub „Zastąp” zmienia ocenę spoin już wykonanych** — `wps_library_page.dart:185-194` (zastąpienie tego samego ID), `wps_edit_page.dart:126-163` (nadpisanie). Zgodność liczy się przy każdym otwarciu listy z bieżącej treści WPS (`weld_journal_screen.dart:137-163`). Brak historii zmian WPS. Poprawka zakresu w rev. B „cicho” zmienia werdykt dla spoin rev. B sprzed poprawki.
  3. **Usunięcie WPS bez śladu** — `wps_library_page.dart:251-280`. Twarde usunięcie i skasowanie pliku, bez „Cofnij”. Spoiny tracą kontrolę; zostaje tylko informacja „nie ma w bibliotece”.
- **Problemy UX w terenie:**
  - Karta WPS ma 4 przyciski tekstowe w `Wrap` (Edytuj / Udostępnij / Kopiuj JSON / Plik WPS) — gęsto, ale ≥ 48 dp.
  - Import z pliku `.txt` czytany `readAsString()` (UTF-8). Plik zapisany w ANSI da tylko komunikat ogólny.
- **Brakujące funkcje:**
  - Status dokumentu (pWPS / zatwierdzona / wycofana), kto zatwierdził i kiedy, data obowiązywania.
  - Ostrzeżenie w dzienniku przy WPS wycofanej lub pWPS.
  - Parametry, o które pyta inspektor przy audycie stanowiska: zakres prądu, napięcia i prędkości, przepływ gazów, wolfram, F-No / A-No, specyfikacja materiału, PWHT liczbowo.
  - Podgląd PDF WPS w aplikacji (dziś tylko udostępnienie pliku).
  - Import JSON bez żadnej informacji o pochodzeniu. (opinia: w brygadzie łatwo o „krążącą” nieaktualną WPS)
- **Testy:**
  - Pokryte: format JSON i walidacja (`test/domain/wps/wps_record_test.dart`), kontrola zakresu (`test/domain/wps/weld_range_check_test.dart`), import ze schowka i błędny import (`test/features/qualification_pages_test.dart`).
  - Brak testów na: rozwiązywanie „bez rewizji”, zastąpienie przy imporcie, usunięcie WPS przypiętej do spoin.
- **Propozycje:**
  - [P2][M] Wersjonowanie WPS: edycja zapisanej WPS tworzy wpis historii (albo zamrożoną kopię); spoina zapamiętuje `wps_id` i `updated_at` z dnia zapisu. Kontrola używa wersji z dnia spawania.
  - [P2][S] Status dokumentu (pWPS / zatwierdzona / wycofana) z ostrzeżeniem w dzienniku.
  - [P2][S] `resolveWpsRef` dla tekstu bez rewizji: gdy w bibliotece jest więcej rewizji → `cannotCompare` z prośbą o wybór.
  - [P3][S] Miękkie usuwanie lub „Cofnij”; ostrzeżenie „N spoin wskazuje tę WPS”.

## wps-edit — Formularz WPS

- **Cel i dla kogo:** Wpis i edycja WPS: numer, rewizja, norma, WPQR/PQR, procesy, grupa, t, D, pozycje, BW/FW, spoiwo, gazy, podgrzanie min, międzyściegowa max, energia liniowa min–max z konwencją EN 1011-1 / ASME IX, PWHT, uwagi, załącznik PDF/JPG.
- **Co zawiera:** `lib/features/wps/wps_edit_page.dart`; walidacja `validateWps` (numer wymagany, wartości nieujemne, min ≤ max).
- **Stan:** działa.
- **Błędy potwierdzone:**
  1. **Brak ochrony przed utratą danych** — plik nie ma `PopScope`. Gest „wstecz” porzuca ok. 20 pól bez pytania.
  2. **Brak kontroli duplikatu numeru i rewizji** — `wps_edit_page.dart:121-163`. Można zapisać drugą „WPS-141-01 rev. B” (inne ID). Dziennik weźmie wtedy tę o nowszym `updated_at` (`weld_compliance.dart:146-155`), bez wiedzy spawacza.
  3. Anulowanie po wybraniu załącznika zostawia osierocony plik w `heat_photos` (kopiowany od razu, linia 108).
- **Problemy UX w terenie:**
  - Długi formularz z przyciskiem zapisu na górze (✓) i na dole — OK.
  - Pola „od–do” parami, klawiatura numeryczna z przecinkiem — dobrze.
- **Brakujące funkcje:** Jak w wps-library (status, parametry elektryczne, gazy z przepływem). Brak pola „zakres pozycji w systemie” (ISO / ASME) jako wyboru zamiast tekstu — źródło fałszywych alarmów z weld-journal, pkt 4.
- **Testy:** Pokryte: brak numeru blokuje zapis, zakres HI zapisany z konwencją. Brak testów na duplikat i porzucenie formularza.
- **Propozycje:**
  - [P2][S] `PopScope` ze strażnikiem porzucenia.
  - [P2][S] Ostrzeżenie o duplikacie numeru i rewizji („Zastąp istniejącą / zapisz jako nową rewizję”).
  - [P3][M] Pozycje jako chipy w wybranym systemie (ISO 6947 albo ASME), a nie wolny tekst.

## welder-identity-setup — Tożsamość spawacza

- **Cel i dla kogo:** Jednorazowe ustawienie stempla spawacza (ISO 3834 / ISO 9606 / ASME IX QW-301), imienia, e-maila, zgody RODO i oświadczenia o kwalifikacjach. Stempel to domyślny spawacz w dzienniku i autor wpisów historii.
- **Co zawiera:**
  - Formularz ze stemplem `^[A-Z0-9-]{2,12}$`, znaczniki czasu zgód zachowane przy edycji, link do rejestru uprawnień (`lib/screens/welder_identity_setup_screen.dart`).
  - Magazyn w SharedPreferences (`lib/services/welder_identity.dart`).
  - „Usuń moje dane” czyści też rejestr certyfikatów.
- **Stan:** działa.
- **Błędy potwierdzone:**
  1. **Zmiana stempla bez ostrzeżenia i bez skutków ubocznych** — `welder_identity_setup_screen.dart:78-119`. Certyfikaty ze starym stemplem przestają pasować (certificate-register, pkt 4). Spoiny zapisane starym stemplem przestają liczyć się do ciągłości ASME (`journal_welds.dart:34-42` filtruje po stemplu). Historia ma dwa różne „by”. Nic tego nie mówi użytkownikowi.
  2. **Stempel nie wchodzi do kopii zapasowej** — `lib/services/data_backup.dart:82-89`, świadomie i opisane. Po odtworzeniu na nowym telefonie (bez ponownego wpisania stempla) `refresh()` nie czyta spoin z dziennika (`welder_qualification_service.dart:202-204` → stempel `null` → pusta lista). WPQ ASME utrzymywane spoinami pokaże się jako przeterminowane, a nowe spoiny i wpisy historii nie mają autora.
  3. Pola `wpqrExpiringSoon` / `wpqrExpired` (`welder_identity.dart:117-128`) liczą dni przez `Duration.inDays` — przypadek DST opisany w `qualification_dates.dart:3-9`. Pola są legacy, ale nadal publiczne. Drobne.
- **Problemy UX w terenie:**
  - Checkboxy zgód są `dense: true` (`linia 266-300`) z tekstem 12 pt — mały cel w rękawicy. (opinia)
  - `autofocus` na stemplu od razu otwiera klawiaturę i zasłania opis.
- **Brakujące funkcje:**
  - Rola (spawacz / monter / brygadzista / QC). Dziś każda zmiana w dzienniku, także „odbiór — inspektor”, jest podpisana stemplem właściciela telefonu, więc historia nie odróżnia wpisu inspektora od wpisu spawacza.
  - Wiele osób na jednym urządzeniu (tablet brygady).
  - Po „Zapisz” brak podpowiedzi „dodaj certyfikat” przy pustym rejestrze.
- **Testy:** `test/screens/welder_identity_setup_test.dart` (1 test widżetu), `test/services/welder_identity_test.dart`. Brak testów na zmianę stempla i jej skutki.
- **Propozycje:**
  - [P2][S] Przy zmianie stempla: dialog z liczbą certyfikatów i spoin starego stempla; opcja przepisania stempla w certyfikatach (spoin nie ruszać — to dowód).
  - [P2][S] Po odtworzeniu kopii: baner „ustaw stempel — bez niego ciągłość ASME i autor zmian nie działają” (stempel można podpowiedzieć z najczęstszego w dzienniku).
  - [P3][S] Większe cele checkboxów (bez `dense`), bez `autofocus`.
  - [P3][M] Rola użytkownika w historii zmian (np. „JK-14 (spawacz)” / „QC”).

---

## Top 5 w grupie

1. **[P1][M] Ciągłość ISO 9606-1 liczona z jednego, nadpisywanego potwierdzenia** (`certificate_status.dart:197-216`, `certificate_register_page.dart:199-202`). Nowe potwierdzenie robi z dawnych spoin „spawacz bez uprawnień”, a potwierdzenie wpisane po terminie przywraca wygasły certyfikat. Oba przypadki potwierdzone skryptem. Naprawa: historia potwierdzeń i łańcuch jak w ASME.
2. **[P1][S] Naprawa R1/R2 zostawia odbiór inspektora (i PWHT/twardość) na spoinie PENDING** (`weld_repair.dart:143-150`). PDF data booka pokazuje przyjęcie spoiny, która czeka na ponowne NDT.
3. **[P1][M] Spójność dokumentu odbiorowego:**
   - status OK i data odbioru niezależne od wyników NDT i dat (`weld_editor_sheet.dart:794-799`);
   - odnośnik kuponu w spoinie „zamrożony” jako OK mimo zmiany kuponu na NOK lub jego usunięcia (`weld_editor_sheet.dart:508-516`, `coupon_dao.dart:29-37`);
   - kupon NOK podpina się bez ostrzeżenia.
4. **[P2][M] Fałszywe wyniki kontroli zgodności:**
   - pozycja 5G kontra „PA, PC, PF” = „poza WPS” (`weld_range_check.dart:335-346`);
   - certyfikat bez stempla obejmuje każdego spawacza brygady (`weld_compliance.dart:288-300`);
   - WPS bez rewizji porównywana z najnowszą rewizją i ocena zmieniająca się po edycji WPS (brak wersjonowania).

   Ostrzeżenia trafiają do historii spoin jako „decyzje”, więc to też psuje dokumentację.
5. **[P2][M] Luki w zapisach jakości poza dziennikiem:**
   - log kuponów bez historii, z twardym usuwaniem i domyślnym „OK”;
   - checklista i pasywacja niczego nie zapisują per spoina / linia;
   - formularze certyfikatu i WPS bez strażnika porzucenia (`PopScope`);
   - PDF dziennika bez historii zmian i bez ostrzeżeń „zapisano mimo ostrzeżeń”.
