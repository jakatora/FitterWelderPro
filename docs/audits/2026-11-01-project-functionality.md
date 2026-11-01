# Projekty CUT — uzupełnienie audytu funkcjonalnego

Data: 2026-11-01. Cel pełnej funkcjonalności aplikacji pozostaje aktywny.
Ten zapis nie oznacza zakończenia audytu wszystkich modułów.

## Potwierdzone usterki i zmiany

- Lista projektów pozostawała w stanie ładowania po błędzie SQLite. Teraz
  pokazuje komunikat i przycisk ponowienia. Nie przedstawia błędu jako pustej
  listy. Kolejna nieudana próba nadal pozwala ponowić odczyt. Starszy wynik
  równoległego odczytu nie zastępuje nowszego stanu.
- Nagłówki projektu i segmentów zaokrąglały zapisane wymiary. W działającej
  aplikacji wpisana ścianka 2,77 mm była wyświetlana jako 2,8 mm. Teraz średnica,
  ścianka i gap korzystają z istniejącego bezstratnego formatowania liczb.
  Wzory i wartości zapisane w bazie nie zostały zmienione.

## Dowody

- `test/screens/projects_load_recovery_test.dart`: rzeczywista testowa baza
  SQLite, błąd odczytu i ponowny błąd, następnie odzyskanie istniejącego
  projektu; PL i EN. Przed naprawą oba scenariusze nie przechodziły.
- `test/screens/fitter_dimension_precision_test.dart`: zapisane średnica
  60,325 mm, ścianka 2,77 mm i gap 0,25 mm pozostają dokładne na ekranie;
  obejmuje również tytuł segmentu, PL i EN. Przed naprawą oba scenariusze
  nagłówka nie przechodziły.
- 45 testów dotyczących projektów, edycji segmentów, trasy, ustawień i
  izolacji kont przeszło. Analiza statyczna zmienionych ekranów i testów
  bez uwag. Zakres nie zastępuje testów pozostałych modułów.
- Rzeczywista aplikacja Windows, Flutter Driver i SQLite: menu montera →
  lista cięć → formularz projektu → zapis → automatyczne otwarcie projektu.
  Potwierdzono zapis jednego rekordu i dokładne wartości w nagłówku.
- W tej samej aplikacji Windows włączono kontrolowaną awarię wyłącznie
  testowej bazy: dwie nieudane próby odczytu → przywrócenie odczytu →
  „Ponów” → ten sam istniejący projekt, nadal jeden rekord.

Raporty i zrzuty znajdują się poza repo, w
`G:/Projekty/FitterWelderPro-artifacts/2026-11-01`:
`windows-project-flow.json`, `windows-retry-runtime.json`,
`windows-project-recovery.png`, `windows-retry-error.png`,
`windows-retry-recovered.png`, `project-functionality-regressions.log`.

## Ograniczenia i dalszy zakres

Windows QA używa pamięciowej bazy oraz osobnych preferencji i magazynu
poświadczeń testowych. Potwierdza działanie interfejsu i SQLite w jednym
uruchomieniu, nie trwałość po restarcie ani zachowanie iOS/Android.
Izolowane uruchomienie do kolejnych testów:
`flutter run -d windows -t test_driver/isolated_app.dart`.
Komendy `failProjectReads` / `restoreProjectReads` rozszerzenia Flutter Driver
dotyczą wyłącznie pamięciowej bazy tego uruchomienia QA.

Pośrednie skrypty QA miały błędy kodowania polskich etykiet oraz używały
angielskiego selektora `pageBack()` na polskim interfejsie. Nie są dowodem
awarii aplikacji ani udanego przebiegu. Końcowy raport
`windows-retry-runtime.json` zawiera wynik ukończonego scenariusza.

Nadal wymagane: aktualne wydanie mobilne z tymi poprawkami, testy na
działającym urządzeniu Android/iOS, dalsza weryfikacja kluczowych modułów,
przeliczeń i eksportów. Historyczny audyt z 2026-08-30 nie został oznaczony
jako ukończony ani zastąpiony samymi wynikami renderowania ekranów.
