# Plan poprawy Fitter Welder Pro — po przeglądzie wszystkich modułów

Stan na 2026-09-26. Źródło: 8 raportów w `docs/przeglad-modulow/` (G1–G8), razem
64 moduły + przekrój (baza, backend, build, testy). Znaleziska: ok. 86 × P1,
158 × P2, 119 × P3 (część P1 powtarza się w „Top 5”). Wszystkie P1 potwierdzone
w kodzie, testem-sondą albo ręcznym przeliczeniem ze źródłem normy.

Zasady wykonania: test najpierw, jeden silnik CUT, niepewna wartość nigdy nie
staje się po cichu wynikiem, zero utraty danych (migracje z testem), każda zmiana
normowa ze źródłem. Po każdej fali: `flutter analyze` = 0, pełne testy, `npm test`.

## Co zawiera aplikacja (skrót inwentaryzacji)

| Obszar | Moduły |
|---|---|
| Monter — projekty CUT | lista projektów, nowy projekt, trasa (FitterScreen), kreator segmentu, lista cięć + sztangi + PDF/CSV, lista materiałowa, komponenty i numery wytopów, zdjęcia wytopów, biblioteka komponentów |
| Monter — kalkulatory | 8 zakładek kalkulatorów (cięcie i obrót kolana, wstawka, redukcja, spadek, ciężar, fazowanie, dylatacja), take-outy kolan, DN-MM, schedule, rolling offset, spadek rury, trasa rur, przelicznik, podpory, rury sanitarne |
| Monter — rysunek | siodło (tabela) i szablon siodła 1:1, zeszyt ISO (szkicownik + CUT + projekt), skaner ISO + przegląd skanu (AI) |
| Spawacz — obliczenia | heat input i CE/podgrzewanie, gaz/formowanie/timer/ciśnienie, parametry rur (AMP, gazy, moje, startowe), zbiorniki (tandem), wolfram, orbital TIG, próba ciśnieniowa + protokół, moment śrub |
| Spawacz — jakość | dziennik spoin (NDT, naprawy, historia, PDF), log kuponów, checklista, przebarwienia, pasywacja, rejestr uprawnień + przypomnienia, biblioteka WPS, tożsamość spawacza |
| Konto i społeczność | ekran główny + wyszukiwarka, menu monter/spawacz, pomoc, zasady, zgody, profil + „Usuń moje dane”, czat, asystent tekstowy/głosowy |
| Ukryte / sieroty | premium, praca, dodaj ogłoszenie, rejestracja, tutor, tandem (4 ekrany), parametry rur „welder_pipe” (2), stary „nowy projekt” |
| Zaplecze | SQLite v22 + druga baza `cut_list_app.db`, kopia zapasowa, backend Express (czat, AI, skaner, Stripe, RODO), build Android/iOS/Windows/web, 176 plików testów |

## Fala 1 — poprawność i dane (P1), równolegle wg własności plików

**1A. Projekty CUT** (G1)
- Redukcja z palety kreatora ma długość 0 → pytać o H z podpowiedzią B16.9 i kierunek; biblioteka komponentów: edycja i usuwanie (UNIQUE dziś blokuje poprawkę).
- Numery wytopów: widoczne i edytowalne, przypięte do komponentu (nie do `seq_no`), także dla rur i startu nieciągłej trasy; pole numeru na ekranie „Heat numbers”; eksport do PDF/CSV.
- Ekspander (redukcja odwrotnie) ma zmieniać średnicę trasy; BOM rury w sztangach z rzazem (zgodny z listą cięć); redukcja ze skanu/szkicu nie liczona 2×.
- Odcinek dłuższy od sztangi: podział z odjęciem gapu spoiny łączącej; jedna reguła zaokrąglenia (ekran/PDF/CSV).

**1B. Kalkulatory montera** (G2)
- Podpory: tabela rozstawów wg MSS SP-58/SP-69 i B31.1 Tab. 121.5 (DN20/32 ciecz 2,1 m), bez nienormowego −12 % za izolację; test przypinający tabelę.
- Fazowanie: złącze X (szerokość na stronę), jednoznaczny kąt (kąt rowka ISO 9692-1 vs kąt na stronę ASME B16.25).
- Schedule: kolumny 40S/80S (B36.19), średnica wewnętrzna.
- Wstawka i Trasa: szczelina spoiny; Trasa bez startu z R = 0 i bez podpowiedzi „Wyzeruj R”.
- Wyszukiwanie `2"`; pomoc Wstawki; skala kąta piły; gęstość 316L 8,0; α 304L 16,0.

**1C. Zeszyt ISO + skaner** (G3)
- Ekran skanera: lista pokazuje CUT z jednego silnika (dziś ISO jako „CUT”).
- Zeszyt: kołnierz/zawór na końcu domyślnie do przylgi (jak kreator), wybór punktu widoczny i opisany słowami.
- Zeszyt: trójnik redukcyjny — osobne C (przelot) i M (odgałęzienie).
- Nieczytelne odliczenie = blokada, nie ciche pominięcie; skaner: `rawDimension` ≠ `dimensionMm` = blokada.
- Skaner: kołnierz bez typu → ostrzeżenie i potwierdzenie (nie cichy WN).
- P2 w tej samej paczce: ręczny CTE kolana nie „zjada” drugiego; olet w węźle; pewność „medium” wyróżniona; zdjęcie rysunku w przeglądzie; wynik skanu zapisany lokalnie (bez płatnego ponownego skanu).

**1D. Obliczenia spawacza** (G4, G7-tandem)
- Zbiorniki/tandem: poza zakresem danych — jawna informacja zamiast „wyliczone z zatwierdzonych”; brak monotoniczności = ostrzeżenie; nie podpinać ekranów-sierot tandem (zła baza) — decyzja w „Decyzjach”.
- Podgrzewanie: dla P-No 4/5x/15E ukryć metody CE (Seferian), minimum kodowe wg aktualnego B31.3/B31.1 (po weryfikacji w źródle), DN/SCH ustawia grubość.
- AMP / Startowe / Wolfram / gaz palnika: jedno źródło danych + test spójności (CS nie mniej prądu niż SS).
- Próba ciśnieniowa: ostrzeżenie przy PASS, gdy zmierzone < Pt lub pneumatyczna > 1,33·P; słup wody; sprawdzenie Re.
- Moment śrub: B16.5 Class 600/900/1500 dla DN15–65; ponowne dokręcanie wg PCC-1 (min. 4 h).
- Orbital: górna granica ścianki; purge „złoty środek” bez sprzeczności; minutnik purge przez serwis timera; zmiana trybu timera z potwierdzeniem; η niepoprawne ≠ „0.00”; brakujące zdania „wiąże WPS”.
- `welder_pipe`: usunąć fałszywą wysyłkę „pula 100/100” (oznacza jako wysłane bez HTTP).

**1E. Dokumentacja jakości** (G5)
- Ciągłość ISO 9606-1: historia potwierdzeń (nie jedno nadpisywane), potwierdzenie po terminie nie przywraca wygasłego.
- Naprawa R1/R2 kasuje odbiór inspektora, PWHT i twardość (z historią).
- Spójność: OK/odbiór niemożliwy przy NDT NOK; odnośnik kuponu „żywy”; ostrzeżenie przy kuponie NOK.
- Kontrola zgodności bez fałszywych alarmów: pozycje ISO/ASME (5G vs PA/PC/PF → „nie da się porównać”), certyfikat bez stempla nie obejmuje brygady, wersjonowanie/rewizja WPS.
- Log kuponów: historia, miękkie usuwanie, bez domyślnego OK; `PopScope` w formularzach; PDF z historią zmian i ostrzeżeniami; checklista per proces/materiał; przebarwienia poziom 3 spójnie.

**1F. Konto, czat, prywatność** (G6)
- Filtr czatu: „pedał” (TIG) nie jest wyzwiskiem; test żargonu.
- „Usuń moje dane” kasuje zgodę skanera i historię asystenta; stan „nie było czego usuwać” działa (identyfikator nie tworzony przy każdym starcie).
- Duplikaty wiadomości: klucz idempotencji (`Idempotency-Key`) w POST, bez ponawiania POST bez klucza.
- Czat: widoczne Zgłoś/Zablokuj z semantyką, etykieta „Wyślij”, kontrast AA w dymkach.
- Polityka: usunąć sprzeczność o imieniu; Android `allowBackup`/reguły backupu (bez sekretu instalacji); `PrivacyInfo.xcprivacy` wypełniony; treść zgody osobna dla czatu, skanera i asystenta; odświeżanie ekranu głównego; wpisy „Czat/Profil/Usuń dane” w wyszukiwarce.
- Rejestracja (ukryta) ma w kodzie użytkownika demo z hasłem — usunąć dane demo.

**1G. Asystent** (G7, G8)
- Wspólne kody gazu/złącza w backendzie i aplikacji + test kontraktu po obu stronach.
- Historia do `/ai/chat`: ostatnie wpisy bez bieżącego pytania (dziś po 10 pytaniach 400 i cichy offline).
- Parser „brudnej mowy”: „dwa sześćdziesiąt” ≠ 62 A, cale ≠ ścianka, „pe ef” = PF, formowanie ≠ gaz palnika, żargon („ampów”, „dwójka”, „na setkę”, „tik”); zestaw testów.
- Pytanie („jaki prąd na…”) ≠ zapis; odmowa w dopytywaniu nie kasuje polecenia; „Odpowiedz” offline bez zgody na serwer.
- Nowe intencje (P2): dopisanie spoiny do dziennika, odczyt moich parametrów.

**1H. Backend, build, dane przekrojowe** (G8)
- Wdrożenie: baza wiedzy poza wolumenem (albo wolumen na `/data`), brak bazy wiedzy = błąd startu; Node ≥ 22.13 (najlepiej 24).
- Stripe (przed włączeniem płatności): druga subskrypcja nie nadpisuje pierwszej, stare zdarzenie nie anuluje nowej.
- Limity: `limit` ograniczony, skaner z limitem równoległości i timeoutem, limity IPv6 po /64, idempotencja czatu (kontrakt z 1F).
- Android: podbić Gradle/AGP/Kotlin ponad minima Fluttera 3.47; release bez `key.properties` = błąd, nie podpis debug; CI buduje Androida.
- Dane: PDF dziennika w izolacie; przywracanie kopii atomowe dla obu baz; test przywracania kopii ze starszej wersji; klucze obce tam, gdzie bezpieczne.

## Fala 2 — obsługa w terenie (P2)
- Kreator segmentu i lista: cele ≥ 48 dp, czcionki ≥ 12–14 px, lista bez skoku przewijania, Cofnij usunięcia segmentu, „kontynuuj od ostatniego komponentu”, podpowiedzi take-outów.
- Lista cięć przy pile: odhaczanie uciętych kawałków (offline) i kratki w PDF.
- Zeszyt ISO: pinch-zoom, pasek narzędzi ≥ 48 dp.
- Siodło: tabela głębokości na ekranie, dowolny kąt, grubość ścianki (set-on/set-in), szablon otworu w rurze głównej.
- Pomoc i nazewnictwo po zmianach fali 1; brakujące testy zakładek kalkulatorów.

## Fala 3 — dług i obserwowalność (P3)
- Lokalny rejestr błędów + „Wyślij raport” (bez zmiany polityki), raporty awarii ze sklepów, alerty backendu.
- Testy odporne na zmianę tekstów (klucze zamiast polskich napisów, mniej testów czytających źródła).
- Jeden mechanizm tłumaczeń (gotowość na DE), podział `iso_notebook_screen.dart`.

## Decyzje właściciela (nie blokują fali 1)
1. Moduły ukryte i niedziałające: praca, dodaj ogłoszenie, rejestracja, tutor, stary „nowy projekt”, 4 ekrany tandem, 2 ekrany „welder_pipe” — usunąć czy zostawić ukryte (reguła projektu: bez usuwania modułów bez Twojej zgody). Rekomendacja przeglądu: usunąć niedziałające, tandem scalić ze „Zbiornikami”.
2. Premium: ekran w obecnej formie naruszałby Apple 3.1.1/3.1.2 — przy włączaniu płatności przebudować na zakupy w aplikacji.
3. Dane tandem (4/4 mm, 170–180 A, wariant TI) — potwierdzić u autora danych.
4. Próg przebarwień (poziom 3–4 w spożywce).
5. Wartości podgrzewania z aktualnego B31.3 — potwierdzić w oryginale normy.
