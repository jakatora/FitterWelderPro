# Stabilny start SQLite i izolacja testów

## Zakres i przyczyna

Kontynuacja zatwierdzonej rozbudowy FitterWelder Pro. Nie usunięto modułów, nie zmieniono wersji schematu ani ścieżki bazy w aplikacji. Zmiany pozostają lokalne, bez instalacji i publikacji.

W poprzednim etapie równoległy zestaw testów sporadycznie kończył się błędami `database is locked`; przebieg kolejny nadal generował ostrzeżenia. Odtworzenie 31 sierpnia: 716 testów przeszło, ale ostrzeżenia pozostały.

Odnaleziono dwa źródła:

1. Sześć zestawów testów używało wspólnego pliku cutlist.db, a testy ekranów sztucznie przesuwały czas o 11–15 sekund, zamiast poczekać na natywne operacje SQLite.
2. AppDatabase.get publikowało _db po openDatabase, lecz przed zakończeniem samonaprawy i uzupełnienia danych. Jednoczesne wywołania powielały przygotowanie, błędne przygotowanie zostawiało otwarte połączenie, a zamknięty cache był zwracany bez sprawdzenia.

## Naprawa

- Wspólny Future inicjalizacji; wszystkie równoczesne żądania czekają na kompletną gotowość.
- Cache trafia do czytelników dopiero po przygotowaniu tabel i danych.
- Błąd zamyka częściowe połączenie i pozwala ponowić próbę; zamknięte połączenie jest otwierane ponownie.
- Testy DAO i ekranów korzystają z prywatnego SQLite w pamięci dla danego pliku testowego/izolatu. Nie otwierają współdzielonej bazy.
- Oczekiwanie na rzeczywistą kolejkę SQLite zastępuje sztuczne wygaszanie timerów w testach ekranu głównego, ścieżki użytkownika i przeglądu ekranów.
- Audyt kalkulatorów spawalniczych również ma przygotowaną prywatną bazę do odczytu rejestru prób ciśnieniowych.

## Dowody

Nowy test database/startup_test.dart najpierw zawiódł cztery razy na prawdziwym SQLite: 12 inicjalizacji zamiast jednej, przedwczesny odczyt, połączenie nadal otwarte po błędzie, zamknięte połączenie zwrócone ponownie. Po naprawie 4/4 przeszło. Razem z migracjami: 15/15.

Test widget_test.dart sprawdza, że ekran główny pokazuje zapisany projekt i nie zostawia wskaźnika ładowania. Grupa testów bazy: 26/26 bez blokad; audyt ekranów: 67/67.

Końcowy pełny przebieg: 721/721 przy --concurrency=8 i --test-randomize-ordering-seed=831, bez ostrzeżeń `Warning database`, wyjątków i błędów niezainicjalizowanej bazy. flutter analyze --no-pub: No issues found. Niezależny przegląd: brak ustaleń blokujących.

Powtórzenie przy seed=832: 721/721, exit 0, również bez ostrzeżeń blokady bazy, wyjątków i błędów inicjalizacji. Czasy przebiegów: około 30 s i 28 s.

Suma SHA-256 starego pliku testowego cutlist.db przed i po pełnej weryfikacji identyczna: 68E49B8224F0F6F7892F93DEC13375718A5BA4CE66B41DCD1C41CCCE0C0285FA. Testy startu tworzą i sprzątają wyłącznie własne katalogi fwp-startup-* wewnątrz .dart_tool. Nie usuwano danych użytkownika.

## Ograniczenia i odtworzenie

Prywatna baza jest wspólna dla testów w jednym pliku; testy nadal muszą sprzątać własne rekordy. Nie wykonywano aktualizacji zainstalowanej aplikacji ani próby na telefonie. Wynik nie jest gwarancją braku wszystkich możliwych blokad SQLite.

flutter test --no-pub test/database/startup_test.dart test/database/migration_test.dart

flutter test --no-pub --concurrency=8 --test-randomize-ordering-seed=831 --reporter expanded

flutter analyze --no-pub

Plik db.dart został też sformatowany. Automatyczna kontrola bezpieczeństwa odrzuciła dodatkowe szerokie przywrócenie formatowania jego niezmienianej części z HEAD; zachowano aktualny plik i nie obchodzono odmowy. Naprawa nie wymagała tego przywrócenia.
