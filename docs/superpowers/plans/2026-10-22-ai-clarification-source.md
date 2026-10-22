# Natywne źródło po doprecyzowaniu AI — 2026-10-22

Przed zmianą _aiQuestion przechowywał tylko tekst pytania, a wykonanie propozycji było związane z ostatnią odpowiedzią. Model widział krótką historię, ale acceptsProposal nie dostawał pierwotnego zamiaru. To odrzucało poprawne doprecyzowanie w capability ze ścisłą kontrolą źródła.

AiClarification przechowuje osobno pytanie i userSource. Tylko pierwotny tekst użytkownika i kolejne odpowiedzi na to pytanie trafiają do źródła kontroli natywnej. Pytanie modelu pozostaje danymi wyświetlania/kontekstu. Rozpoznane nowe polecenie i bounded task switch używają nowego źródła. Reset/anulowanie/zmiana konta czyszczą obiekt tymi samymi ścieżkami, które wcześniej czyściły pytanie. ExecuteProposal nadal sprawdza natywny matcher, negację, instrukcje i acceptsProposal; potwierdzenia zapisu i kolejka pozostają obowiązujące.

Nie przycinać źródła: powyżej16000 znaków dalsza interpretacja jest zatrzymana, aby nie utracić negacji/literalnych danych. Nie zmieniono request JSON, modeli Haiku, cennika, retry ani bramek budżetu. Nie wykonano płatnego API.

Dowody: nowy widgetowy przypadek ze SourceBoundFixtureSkill jest RED na źródle cfa41bf (run0 zamiast1), a z poprawką wykonuje1. Kontrola wymaga oryginalnego zamiaru i krótkiej odpowiedzi, odrzuciłaby tekst uprawnienia pochodzący z pytania modelu. Pełny ai_chat_execution20 PASS zawiera też dawny rzeczywisty ekran rolling offset/ISO i testy anulowania/opóźnień, nie wyłącznie nową fixture. Dwa unit tests sprawdzają literalne źródło, znaki, kolejność, brak promptu i limit bez obcięcia. Analiza4 plików --fatal-infos czysta.

Granice: źródło użytkownika nie dowodzi semantycznej poprawności dowolnej propozycji modelu. Każdy skill nadal wymaga odpowiednich własnych guardów. Model nadal widzi dotychczasową ograniczoną historię, a nie całe sourceText; wieloturnowe rozumienie i przypisanie odpowiedzi do klauzul planu złożonego wymagają dalszej weryfikacji. Brak dowodu live Anthropic, Railway i telefonu w tej zmianie. Pełny cel pozostaje aktywny.

Final: 189 testów ai_*_test.dart PASS, zero pominięć, exit0 (23s). Obejmuje wariant anulowania przed odpowiedzią: brak wykonania i brak odtworzenia dawnego źródła. Końcowa analiza4 plików --fatal-infos czysta. Bez nowego backendu/deploy/APK.
