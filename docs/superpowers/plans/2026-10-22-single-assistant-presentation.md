# Jedna rozmowa przy wejściu z Premium — 2026-10-22

Przycisk „Wypróbuj AI Asystenta” tworzył samodzielny AiChatScreen, podczas gdy globalny panel nadal utrzymywał osobny silnik rozmowy. Przejście do kalkulatora mogło rozdzielić kontekst i plan pomiędzy tymi instancjami.

Przycisk korzysta teraz z openTool. Gdy globalny asystent jest zamontowany, wejście z ekranu, na którym panel jest ukryty, otwiera wyłącznie stronę prezentacji istniejącego panelu. Nie powstaje drugi AiChatScreen. Ekran Premium pozostaje zamontowany, wraz ze swoim stanem i obserwatorem powrotu z płatności. Zwykłe wejście z modułu nadal rozwija panel przy aktualnym narzędziu. Izolowane ekrany bez globalnego asystenta zachowują wcześniejszą implementację awaryjną.

Strona prezentacji powiększa istniejący panel do dostępnej wysokości, uwzględniając klawiaturę i bezpieczne obszary. Drzewo rozmowy pozostaje w tym samym miejscu. Otwarcie kalkulatora przywraca kompaktowy panel; powrót z kalkulatora ponownie rozwija dużą prezentację, aby nie pokazać pustej strony. Zwinięcie dużej prezentacji wraca do poprzedniej strony. Dialogi i formularze konta nadal ukrywają panel. Nagłówek ma wysokość 48 dp.

Nie dodano pełnej historii w widoku osadzonym ani tożsamości profilu w nagłówku. Nie potwierdzono jeszcze wszystkich przekazań planu do ISO. Pozostały zakres pierwotnego celu, w tym własność lokalnych zapisów, kompletne działania modułów oraz test telefonu i iOS, pozostaje otwarty.

## Dowód serwerowy

2026-10-22T00:47:18Z, istniejący izolowany backend Railway: logowanie właściciela 200, GET /account/me 200 i zgodny właściciel z rolą admin, odczyt /account/reports 200. Testowa sesja została wylogowana (200); ponowny odczyt jej profilu zwrócił 401. Nie zapisano tokenu ani hasła w artefakcie, nie zmieniano profilu ani raportów. Wynik: build/assistant-presentation-account-runtime.json. Ten test nie dowodzi izolacji między dwoma różnymi rzeczywistymi użytkownikami ani działania nowej ścieżki AI.

2026-10-22T00:46:34Z: nieprawidłowy pusty POST /api/fitter/ai/assistant nadal 404; /api/fitter/account/login 400. CLI OAuth whoami nadal Unauthorized. Nie wdrożono nowego backendu ani nie uruchomiono nowego parowania. Wyniki: build/assistant-presentation-runtime-probe.json i build/assistant-presentation-railway-auth.log.

## Weryfikacja aplikacji

Cztery nowe testy rzeczywistych widżetów sprawdzają tę samą instancję rozmowy i szkic tekstu po otwarciu/zamknięciu dużej prezentacji, powrót systemowy, prywatny dialog, faktyczny przycisk Premium z zachowaniem jego stanu, przejście do natywnego kalkulatora i powrót bez pustej strony. Dodatkowy kontrolowany dwukrokowy plan AI otwiera kalkulator spadku, wpisuje dane przez jego natywny kontrakt i kontynuuje dopiero po odczycie faktycznych kontrolerów. To nie jest płatne wywołanie modelu ani próba mikrofonu telefonu.

Szersza regresja całego asystenta, rejestru narzędzi i statusu Premium: 2739 PASS, 38 wcześniejszych pominięć brakujących przykładów, zero błędów (build/assistant-presentation-regression.log). Po tej regresji usunięto wyłącznie nieaktualne komentarze Premium i dodano czwarty test planu AI. Końcowy zestaw prezentacji, kont i rejestru: 32 PASS, bez pominięć (build/assistant-presentation-final-test.log). Pierwsza wersja tego dodatkowego testu poprawnie zatrzymała plan z powodu niepełnego kontraktu danych: brakowało obowiązkowego trybu kalkulatora; uzupełniono fixture, bez osłabiania walidacji aplikacji. Pięć zmienionych plików Dart przechodzi analizę z --fatal-infos (build/assistant-presentation-final-analyze.log).

## Ścieżka pieniędzy

Zmiana dotyczy wyłącznie wejścia do rozmowy; model Haiku 5.5, budżety AI, ceny, płatności i przyznawanie Premium pozostają w dotychczasowym kodzie. Test na rzeczywistym widżecie Premium przechwytuje transport i sprawdza, że naciśnięcie CTA nie tworzy żądania checkout ani innego dodatkowego żądania. Nie wykonano płatnego wywołania modelu ani płatności. Nie jest to nowa weryfikacja poprawności płatności produkcyjnych.
