# Dziennik asystenta i właściciel danych — 2026-10-22

## Problem potwierdzony wykonaniem
Nowy test na rzeczywistym lokalnym SQLite zapisał wpis gościa, zalogował kontoA i oczekiwał pustego dziennika. Otrzymał wpis gościa (RED). Wcześniej WeldJournalDao i niektóre odczyty kontroli uprawnień używały całej tabeli. Stempel spawacza nie jest granicą konta: dwa konta mogą mieć taki sam stempel.

## Zmiana
- Lokalny schemat31: owner_scope na weld_journal, weld_journal_history, weld_repairs i weld_journal_projects. Istniejące dane zostają u gościa. Nagłówki mają złożony klucz właściciel/projekt zamiast globalnej nazwy projektu. Migracja zachowuje istniejące kolumny i ich wartości, również rozszerzenia. Nie przypisuje danych urządzenia do aktualnie zalogowanego konta.
- DAO przechwytuje LocalRecordOwner przed I/O, sprawdza sesję przed i po odczycie oraz na początku/końcu transakcji zapisu. Wszystkie CRUD, historia/PDF, naprawy, checklist history i ustawienia sprawdzają właściciela. UUID obcego wpisu nie może zostać użyty jako nowy wpis bieżącego konta. Numer spoiny/projekt może występować niezależnie na obu kontach.
- Przygotowanie i zapis asystenta oraz Cofnij są związane z oryginalnym właścicielem, także po utraconym potwierdzeniu i przy ponowieniu. Podsumowanie operacji dziennika dostaje ownerScope; widok historii filtruje je tak samo jak parametry spawania. Zapamiętany projekt i wartości ostatniej spoiny są w osobnych kluczach preferencji dla konta/gościa.
- Czytelnicy dziennika w kontroli uprawnień i zgodności korzystają z odczytu właściciela. Propagacja zmiany wspólnego kuponu nie odczytuje ani nie aktualizuje dziennika innego konta i zapisuje właściwego właściciela historii.
- Snapshot kopii usuwa obce wiersze z tych czterech tabel i ich bajty przez secure_delete/VACUUM, tak jak ISO i parametry. Import jawnie kopiuje rekordy do bieżącego właściciela. Kolizja z UUID obcego dziennika dostaje nowy UUID wraz z przepięciem historii i napraw. Obcy wiersz nie jest nadpisywany. Próba podpięcia historii do obcego, nieprzywracanego rodzica kończy się rollbackiem.
- Lista ekranu jest odtwarzana dla nowej sesji: stare wpisy, filtry, nagłówki i spóźnione wyniki nie zostają na ekranie. DAO listy/formularzy jest związane z tą sesją. Formularz przed zapisem i przed zapamiętaniem wartości sprawdza sesję.
- Modale dziennika i powiązanych kuponów blokują zwykłą zmianę konta do zamknięcia okna. Wymuszone unieważnienie sesji ukrywa stare dane i usuwa stary formularz z drzewa; nie jest to gwarancja bezstratnego zachowania szkicu przy przymusowym unieważnieniu. Normalna zmiana nie wyrzuca otwartego szkicu.
- CSV/PDF mają walidację właściciela przed I/O i po asynchronicznych etapach, przed udostępnieniem. Plik ma osobny losowy katalog tymczasowy, aby równoległy eksport nie nadpisał załącznika innej operacji. Nie twierdzimy, że wykonano prawdziwe systemowe udostępnienie na telefonie.

## Weryfikacja
- Pierwszy RED opisany wyżej; następnie rzeczywisty SQLite potwierdził rozdzielenie guest/A/B, również dla powtarzającego się stempla.
- Pierwszy zestaw66 testów zapisu, migracji, starego DAO, natywnych działań i wartości domyślnych PASS po naprawie kolejności indeksów. createSchema może uzupełniać stary plik przed migracją; nowe indeksy powstają dopiero, gdy istnieje kolumna owner_scope. Testy wykryły brak tej kolumny na czterech starszych ścieżkach — poprawiono produkcyjny kod, nie pominięto testów.
- Zestaw17 nowych testów SQLite/UI/eksportu PASS: własność, wszystkie obce mutacje, historia/naprawy, opóźnione I/O, sesja przygotowania i undo, historia operacji, prefs, import kolizji, rollback podpięcia obcego rodzica, migracja kolumn rozszerzeń, realne bajty snapshotu, przełączenie listy, blokada modalnego logowania i ukrycie danych po invalidateSession, odmowa eksportu po zmianie właściciela. Następnie dodano dwa testy propagacji kuponów i odczytów ciągłości; wynik pełnego przebiegu poniżej.
- Widżetowe oczekiwanie czeka na zakończenie rzeczywistego SQLite z ograniczoną liczbą pump/flush; nie ukrywa trwającego I/O samym przesuwaniem fake-clock w pumpAndSettle.
- Analiza zmienionych plików z --fatal-infos była czysta przed dwoma ostatnimi przypadkami (tylko testy); końcowy wynik i pełny test suite zostaną zapisane poniżej.

## Granice i dalszy pełny cel
To rozdzielenie dziennika i jego konsumentów, nie deklaracja prywatności wszystkich historycznych tabel urządzenia. Rejestry certyfikatów/WPS/kuponów, globalna WelderIdentity i InterpassStore wymagają dalszej oceny polityki właściciela i spójności kont. Nie kopiować automatycznie deklaratywnego profile.stamp do podpisującej WelderIdentity (inna walidacja i deklaracje zawodowe). Inne rodzaje historii operacji nadal mają dotychczasową politykę; zmieniono tylko dziennik i wcześniejsze parametry.

Brak zmian modeli, cenników, budżetów AI lub backendu. Tani Haiku pozostaje bez zmian. Backend main9a78d434d2cd1eba6b9ac61321ad375ce2a10f00, Railway/logowanie i dedykowany klucz FWP nadal wymagają zewnętrznego dostępu. Nie wydawać APK ani nie oznaczać pełnej wizji ukończoną na podstawie lokalnego zestawu testów.

## Końcowy wynik 2026-10-22
Pełny `flutter test --no-pub`: 8824 PASS, 37 wcześniejszych pominięć field-contract, zero failures (3:56). Analiza wszystkich 41 zmienionych/nowych plików Dart z --fatal-infos: bez uwag. git diff --check czysty. Pierwszy pełny przebieg wykrył brak delegacji transaction w proxy startup, brak jawnego guest fixture i stare oczekiwania kontraktów auth/legal/budget; poprawiono testy. Wspólny parseDecimal zastępuje dziewięć lokalnych konwersji przecinka; dodatkowy test zapobiega sklejeniu odpowiedzi „2 4” w numer przejścia 24. Nie wykonano płatnych wywołań AI ani wdrożenia Railway.
Preferencja użytkownika 2026-10-22: tani model asystenta. Istniejące AI_CHAT_MODEL i AI_INTENT_MODEL pozostają claude-haiku-5-5, low effort, bez płatnych retry; konfiguracja produkcji niepotwierdzona.
