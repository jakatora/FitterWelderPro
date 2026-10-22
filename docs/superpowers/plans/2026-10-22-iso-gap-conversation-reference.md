# Naturalne odniesienie do szczeliny ISO — 2026-10-22

Po potwierdzonym ustawieniu szczeliny można kontynuować „zmniejsz ją o 1 mm” albo „decrease it by 1 mm”. To pierwszy jawnie obsługiwany zaimek dla tego ustawienia, nie ogólna zgoda na dowolną zmianę dowolnego pola. AI nadal proponuje kanoniczną komendę, a natywny walidator sprawdza cel, kierunek zmiany i ilość z jednostką. Złożona wypowiedź z dodatkowym modułem lub kolejnym działaniem nie staje się prostą zmianą przez ten skrót.

Odniesienie pochodzi wyłącznie z zakończonej operacji natywnej. Wynik zachowuje lokalny identyfikator szkicu, rewizję, wartość i generację kontekstu. `IsoReferencePort` udostępnia aktualną tożsamość/re-wizję tylko dla aktywnego ISO. Wymagane są zgodność szkicu i rewizji, rzeczywiste widoczne pole oraz ostatnia udana operacja szczeliny w istniejącym dwuminutowym oknie kontynuacji. Ręczna zmiana, inny szkic, brak potwierdzonego kontekstu albo jego wiek uniemożliwiają wykonanie polecenia z samym zaimkiem.

Generacja odniesienia jest oddzielona od dotychczasowych slotów kalkulatorów. Nowa tura natywna, pytanie do odpowiedzi AI, wyjaśnienie/doprecyzowanie modelu lub odrzucenie propozycji unieważniają stare odniesienie. Udana nowa operacja szczeliny zapisuje świeży kontekst po wykonaniu. Nie usuwa się przez to danych formularzy ani ich dotychczasowej historii liczbowej. Zmiana konta i czyszczenie rozmowy nadal wymieniają kontekst zgodnie z wcześniejszym mechanizmem.

Gdy model mimo niejasnego odniesienia proponuje zmianę, aplikacja nie wykonuje jej i prosi o pełne polecenie z nazwą pola, np. „zmniejsz szczelinę w ISO o 1 mm”. To wskazówka do ponownego sformułowania prośby, nie ukryte oczekiwanie na „tak”. Pozostałe błędy propozycji zachowują wcześniejszą obsługę. Opcjonalne `proposalRejectionHint` w kontrakcie umiejętności daje tę wskazówkę bez sprzęgania rdzenia z ISO.

Identyfikator i rewizja służą wyłącznie lokalnej walidacji. Nie są częścią widocznych wejść ani JSON wysyłanego do modelu; nadal przekazuje się tylko `gap_mm` oraz dotychczasowy dozwolony kontekst rozmowy. Osobny test sprawdza brak prywatnego identyfikatora i kluczy odniesienia w żądaniu.

Dowody: 1570 zaliczonych bez pominięć (`build/iso-reference-acceptance-test.log`), router 500 wypowiedzi w 824 ms. Końcowe 90 zaliczonych (`build/iso-reference-final-test.log`) obejmuje dodatkowo główne wykonanie AI, sesje, pytania i widok rozmowy. Analiza ośmiu plików bez uwag (`build/iso-reference-final-analyze.log`). Testy rzeczywistego ekranu/SQLite sprawdzają świeżą kontynuację oraz odmowę po ręcznej zmianie, innym szkicu, odpowiedzi wiedzy i trzech minutach. Jednostkowo sprawdzone są również niepoprawna propozycja, brak kontekstu, nieaktywny arkusz, dodatkowe działanie i PL/EN.

Pierwszy przebieg testu przełączania arkusza utknął na kolejnej operacji kontrolera oczekiwanej w `tester.runAsync` mimo zależności od zegara testowego. Zweryfikowano właściwy proces testów i zatrzymano tylko jego drzewo. Fixture teraz uruchamia tę operację w normalnej strefie testu i pompuje bazę/klatki do potwierdzonego wyniku. Nie zmieniono produkcyjnego kontrolera z powodu tego problemu i zachowano asercję zapisu drugiego arkusza.

Nie wykonano płatnego wywołania modelu ani wdrożenia backendu; transport AI jest kontrolowany w testach. To nie dowodzi jakości rozpoznania dowolnej wypowiedzi przez rzeczywisty Haiku. Nadal potrzebne są dostęp Railway, wdrożenie i testy telefonu, a także dalsze działania, odniesienia do innych pól/elementów i podział pozostałych danych na konta. Pełna wizja pozostaje otwarta.


## Natural requests (2026-10-22)

ISO gap source validation now accepts assistant-directed requests such as "Czy możesz zmniejszyć szczelinę w ISO o 1 mm" and "Could you please decrease the gap in ISO by 1 mm" after AI normalization. Infinitives are normalized only behind an explicit assistant-directed request prefix. Advice, explanation and permission questions remain non-actions. Raw negative signs are checked before folding. Existing scope, numeric, unit and bound-reference checks remain required.

Verification: 53 tests passed, including mounted assistant/real SQLite persistence, unchanged pipe geometry, CUT engine effects and Undo for polite requests, rejection of incorrect model amounts, session isolation and main AI execution. Fatal analysis of three modified Dart files clean. Controlled interpreter fixtures prove execution and guard behavior, not live model language quality. Railway deployment and real provider acceptance remain open.
