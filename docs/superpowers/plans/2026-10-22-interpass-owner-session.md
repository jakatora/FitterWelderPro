# Granica konta dla potwierdzania pomiaru temperatury — 2026-10-22

## Luka potwierdzona
InterpassStore nadal używa jednego interpass_log_v1 dla urządzenia. InterpassReadingSkill zapamiętywał przed/po rekordu i domyślną historię guest, bez uchwyconego LocalRecordOwner. Trzy nowe testy RED potwierdziły: podgląd guest dawał zapisać po zmianie konta, historia zapisu konta miała guest zamiast właściciela, opóźniony odczyt dawał ConfirmResult w nowej sesji.

## Zmiana
LocalRecordOwner jest uchwycony przed await store.load. Spóźniony wynik po zmianie sesji daje FailedResult. Confirm i undo sprawdzają tę samą sesję przed operacją oraz po await; historia ma ownerScope. Filtr historii obejmuje teraz interpass.reading obok wcześniejszych parametrów/dziennika.

CAS replaceIfUnchanged ma opcjonalny expectedOwner: sprawdza go wewnątrz _serial na początku, po odczycie i w _write przed/podczas granicy SharedPreferences. Nie wystarczyło sprawdzenie tylko w callbacku asystenta przed wejściem do kolejki. Opcjonalny argument zachowuje dotychczasowe API lokalnego modułu. In-flight plugin write nie jest transakcją z serwerowym logout: nie twierdzimy, że można cofnąć już rozpoczęty zapis systemowy. Po zmianie sesji operacja nie zwraca sukcesu ani undo dla innego konta.

## Weryfikacja
Pięć nowych testów PASS: stary preview nie zapisuje, historia/undo związane z kontem, opóźniony load nie tworzy preview, CAS ze starym owner odmawia, CAS zakolejkowany przed invalidateSession odmawia gdy przychodzi jego kolej. Zapis podstawowy w ostatnim teście pozostaje niezmieniony. 83 testy związane z Interpass/historią PASS przed dodaniem ostatniego przypadku kolejki; potem5 owner tests PASS. Wcześniejszy rzeczywisty chat/ekran potwierdza dotykiem i głosem oraz undo. Analiza5 zmienionych/nowych Dart plików --fatal-infos czysta.

## Cel nadal otwarty
To NIE jest pełna partycja Interpass według kont. Dane SharedPreferences, uszkodzone backupy i otwarte ekrany nadal mają dotychczasową politykę urządzenia. Następny krok wymaga wspólnego wdrożenia kluczy owner/guest legacy, przeładowania listy, ukrycia/odłączenia starego edytora i załączników, powiązania queued manual writes/undo z właścicielem oraz testów kontA/B z kolizją record id. Nie wolno włączyć samych nowych kluczy bez ochrony UI, bo stary formularz mógłby zostać zapisany pod nowym kontem. History retention100 nadal wspólne; filtr nie zapewnia osobnej retencji.

Brak model/pricing/budget/retry/backend zmian, zero paid API, brak nowego Railway deploy/APK/physical voice acceptance. Pełny cel pozostaje aktywny.

Final broad: flutter test --no-pub test/assistant test/features/interpass test/domain/welding/interpass_log_test.dart: 3483 PASS, 37 wcześniejszych field-contract skips, exit0 (1:36). To nie dowód pełnego pokrycia pominiętych modułów ani pełnej partycji danych. git diff --check czysty.

Dalsza implementacja partycji store i UI: patrz 2026-10-22-interpass-owner-isolation.md. Historyczne granice powyżej opisują commit0484ef2.
