# Podgląd bieżącej rozmowy — 2026-10-22

Globalny panel ma przycisk „Bieżąca rozmowa”. Otwiera przewijalny podgląd zapamiętanych wiadomości sesji, zaczynający się od najnowszych. Używa istniejących wiadomości i wyglądu bąbelków; nie tworzy drugiego silnika asystenta. Powrót zachowuje szkic, wybrany kalkulator, jego rzeczywiste dane i oczekujące pytanie/plan. Podgląd służy do czytania; dalsze polecenie podaje się po powrocie do panelu.

Etykiety rozróżniają użytkownika, AI, odpowiedź aplikacji, pomoc offline i informację o dostępności AI. Starsze lokalne pytania, odrzucenia i statusy, które wcześniej nie trafiały do listy wiadomości, są zapisywane jako localDialogue. Nie dodają się do zweryfikowanej historii przekazywanej do modelu ani do interpretacyjnej _aiHistory. Wynik odczytu zapisów ma w takim komunikacie podsumowanie kryteriów i liczby znalezionych pozycji, nie kopię całej bazy. Istniejące limity kontekstu i skróty wiadomości natywnych pozostają bez zmian.

Podgląd jest migawką, a nie archiwum synchronizowanym między urządzeniami. Nie dodano utrwalania rozmów po zamknięciu aplikacji. Przycisk ma cel dotykowy 48 dp i jest niedostępny podczas słuchania, odpowiedzi oraz całego planu AI, również między natywnym przejściem do modułu a następnym oczekującym krokiem.

## Sesja i czyszczenie

Prywatny podgląd i potwierdzenie jego czyszczenia są własnością bieżącej konwersacji, tak jak dotychczasowe podsumowania zapisów. Wylogowanie, nowa sesja lub wyczyszczenie rozmowy usuwa te trasy. Powrót do poprzedniego podglądu nie ujawnia dawnych wiadomości. Czyszczenie wymaga potwierdzenia i korzysta z głównego Navigatora, również przy globalnym panelu poza jego drzewem.

Cytowania są czytelne jako etykiety. W tym podglądzie nie otwierają dodatkowych okien z prywatnej migawki. Pozostałe widoki zachowują wcześniejsze interaktywne cytowania. Nie zmieniono własności zapisów kalkulatorów ani danych w lokalnych tabelach — rozdział tych zapisów między kontami pozostaje osobnym zadaniem.

## Dowody

Dziesięć nowych testów rzeczywistych widżetów obejmuje historię natywnego wyniku i odpowiedzi AI, zachowanie kalkulatora i szkicu, dialog oczekującego planu i późniejszą odpowiedź, lokalne pytanie o prąd oraz odrzucenie nieprawidłowej wartości, wylogowanie z otwartym podglądem lub potwierdzeniem czyszczenia, anulowanie/potwierdzenie czyszczenia, blokadę podczas interpretacji i po nawigacji w wieloetapowym planie oraz ekran 320 px z tekstem 1.3 w PL/EN. Odczyt historii nie zwiększa liczby wywołań kontrolowanego interpretera lub usługi odpowiedzi.

Zestaw obejmujący podgląd, starsze przepływy, sesje, nagłówek konta, prezentację, działanie AI, wszystkie osiem natywnych kalkulatorów i ograniczanie historii: **100 PASS, zero pominięć** (build/assistant-conversation-view-final-test.log). Następnie dodano blokadę _runningAiPlan i jej test nawigacji. Końcowy zestaw podglądu, sesji, zapisów i historii: **27 PASS, zero pominięć** (build/assistant-conversation-view-final-verified-test.log). Cztery zmienione pliki Dart przechodzą analyze --fatal-infos (build/assistant-conversation-view-final-verified-analyze.log). Nie zmieniono Darta po tych kontrolach.

Pierwszy przebieg testu wylogowania oczekiwał na magazyn systemowy między rzeczywistą strefą setUp a testowym zegarem. Zatrzymano tylko ten przebieg i użyto tester.runAsync dla tej operacji, zgodnie z istniejącymi testami izolacji sesji; zachowano sprawdzenie zamknięcia podglądu i usunięcia starych wiadomości. Ponowny przebieg przeszedł.

Testy korzystają z kontrolowanego transportu i mowy. Nie są dowodem działania modelu produkcyjnego ani mikrofonu telefonu. Nie dodano wywołań AI, zmiany modelu Haiku, budżetów, cen, płatności czy backendu. Ostatnie osobne sprawdzenie nowej trasy AI nadal wykazywało 404, a CLI Railway wymagało logowania; w tym etapie nie wykonano wdrożenia.

Pełny cel pozostaje aktywny: kontekst zawodowy modelu, rozdział lokalnych zapisów, pozostałe kontrakty działań i pól, ISO, rzeczywiste AI, wdrożenie i próby urządzeń nadal wymagają ukończenia oraz weryfikacji.
