# Nowe lokalne polecenie podczas pytania AI — 2026-10-22

Testy na źródle837d69b: wpisane i głosowe jednoznaczne polecenie Rolling offset podczas ogólnego clarify powodowało drugie wywołanie modelu zamiast natywnego obliczenia. Dwa widgetowe RED: oczekiwane1 request, rzeczywiste2. Nie jest to deklaracja błędu dowolnego polecenia głosowego.

Zmiana: gdy nie ma pytania natywnego, bounded task switch ani compound, wyraźne nowe polecenie rozpoznane przez recognizesNewCommand i gotowe do lokalnej obsługi recognizesLocalRequest może przerwać ogólne pytanie AI. Czyści AiClarification i dawną kolejkę. Słabe dopowiedzenia nadal używają kontekstu pytania; polecenia wymagające AI nadal przechodzą przez interpretację. Sam wysoki match bez lokalnej gotowości nie wystarcza.

Weryfikacja: pełne ai_chat_execution23 PASS, w tym oba nowe przypadki z rzeczywistym kalkulatorem rolling offset (wynik573.1), jeden interpreter request i późniejsze nowe zapytanie z pending_question=null. Voice wykorzystuje kontrolowany final transcript, nie mikrofon sprzętowy. Wcześniejsze testy source binding/cancel/outage i native question/confirm/ISO też PASS.

Nie zmieniono modelu Haiku, cen, limitów, budżetu ani retry. Zmiana usuwa zbędne płatne wywołanie w tym scenariuszu; dowód liczby wywołań to transport widgetowy, nie odczyt rachunku Anthropic. Brak paid API/deploy/nowego APK. Pełna wizja i rzeczywiste live acceptance nadal otwarte.

Końcowy przebieg wszystkich ai_*_test.dart: 191 PASS, zero skips, exit0. Analiza obu zmienionych plików --fatal-infos czysta. git diff --check czysty.
