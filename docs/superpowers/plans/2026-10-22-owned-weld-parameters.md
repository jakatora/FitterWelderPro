# Parametry spawania przypisane do konta — 2026-10-22

## Wdrożony zakres

SQLite v29 dodaje `weld_params.owner_scope`. Istniejące wpisy pozostają w zakresie gościa; pierwsze logowanie nie przejmuje danych urządzenia. DAO filtruje odczyty, zapis, edycję, usuwanie, zapis idempotentny i cofnięcie po właścicielu. Operacje przechwytują sesję przed I/O i odrzucają zmianę sesji. Formularze zamykają się i lista odświeża po zmianie konta.

Historia operacji `save_weld_parameter` zapisuje ten sam zakres co rekord i filtruje go przy odczycie. Stare wpisy historii należą do gościa. Pozostałe typy historii nadal dotyczą danych urządzenia.

Identyfikator zweryfikowanego konta jest opcjonalnie przechowywany w bezpiecznym magazynie telefonu, powiązany z dokładnym tokenem sesji. Służy wyłącznie do lokalnego zakresu danych, nigdy do autoryzacji serwera ani uprawnień administratora. Brak możliwości zweryfikowania starej sesji bez tej pamięci nie przełącza automatycznie na gościa. Ekran konta umożliwia jawne wylogowanie na tym telefonie i powrót do danych gościa. Zimny start offline może nadal czekać na istniejący timeout odczytu profilu.

## Kopie zapasowe

Kopia robocza SQLite jest oczyszczana z parametrów innych kont, z `secure_delete` i `VACUUM`, bez zmiany bazy źródłowej. Przywracanie zastępuje wyłącznie parametry bieżącego właściciela. Konflikt UUID z rekordem innego konta tworzy nowy UUID importowanego rekordu. Rollback zachowuje pierwotnego właściciela. Zgoda na przywrócenie i przygotowany plik udostępnienia są powiązane z sesją; zmiana konta je unieważnia.

To nie jest podział całej kopii zapasowej na konta: dziennik, ISO, wyceny, zdjęcia i pozostałe tabele nadal mają wcześniejszy zakres urządzenia. Komunikat przywracania rozróżnia ten zakres.

## Weryfikacja i dalsze prace

Rzeczywiste lokalne SQLite i ZIP, kontrolowany transport kont: migracja v28→v29, gość/A/B, obce UUID, opóźnione operacje, cache sesji, zamykanie formularzy, jawny powrót offline do gościa, oczyszczenie surowych bajtów kopii, import i rollback oraz historia parametrów po ponownym odczycie. Wynik końcowego zestawu: 151 testów zaliczonych (`build/owner-history-regression.log`). Wcześniejszy szerszy zestaw przed rozszerzeniem historii: 267 zaliczonych.

Pełna wizja pozostaje w realizacji: własność pozostałych rekordów, kontekst zawodowy AI, kolejne działania i pola, współpraca ISO, rzeczywiste wdrożenie taniego Haiku oraz testy na telefonie. Lokalny test transportu nie dowodzi działania modelu ani wdrożenia Railway.
