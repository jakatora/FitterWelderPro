# Dłuższe doprecyzowanie poleceń AI — 2026-10-22

## Problem i wymaganie
Po kilku wymianach _aiHistory zachowuje tylko sześć wiadomości i usuwa inicjujące polecenie. Native AiClarification zachowywał userSource, ale model nie dostawał go w request. Widgetowy RED potwierdził brak context.clarification po odpadnięciu root z historii. Backend RED odrzucał nowy kontrakt400. Zachować kolejne wypowiedzi użytkownika bez używania pytań modelu jako uprawnień i bez dodatkowego paid call.

## Kontrakt
AiClarification przechowuje immutable userTurns; userSource jest ich połączeniem wyłącznie do kontroli natywnej. Model dostaje opcjonalne context.clarification.user_turns. Current text jest osobno. Maksymalnie31 wcześniejszych wypowiedzi plus obecna (32 łącznie), każda1–2000 znaków, suma z separatorami16000. Pytanie musi być niepuste, a pole nie współistnieje z native pending_reply. Nie przycinać negacji/literalnych wartości. Starsze klienty mogą pominąć kontekst. Globalny limit64000 bajtów JSON pozostaje.

Prompt uczy zachowywać pierwotny zamiar i odpowiedzi po odpadnięciu krótkiej historii, respektować poprawki, negacje i brakujące fakty. Rozpoznane nowe lokalne polecenie nadal przechodzi lokalnie; nowy naturalny task ma nie odtwarzać starego. Pytania/historia asystenta nie nadają uprawnień. Native matcher/acceptsProposal/źródłowe klauzule/confirm/session guards pozostają obowiązujące. Knowledge answer dispatch i source binding złożonych poleceń wymagają dalszej oceny, nie są przez tę zmianę automatycznie udowodnione.

Po wyczerpaniu rozmiaru/liczby wypowiedzi UI nie robi nowego AI request: usuwa stare clarify i interpreter history, prosi o całe polecenie. Następne pełne żądanie ma czysty kontekst. Widoczna rozmowa nie jest kasowana. Rozpoznane credentials we wcześniejszych userTurns odrzucane lokalnie zarówno w builderze, jak i przy bezpośrednim użyciu AssistantAiClient; test potwierdza zero HTTP i zero identity calls.

## Koszty i dowody
Brak zmiany modelu Haiku low effort, cennika, retry0, daily auth/device limits i monthly budget. Istniejąca rezerwacja oblicza konserwatywną górną granicę z całego JSON, zatem obejmuje nowe pole. Test HTTP potwierdza monthly hard-budget503 przed provider call i zwolnione rezerwacje. Wszystkie modele są injected; zero paid API.

Backend258 PASS/zero skips. Nowe5 testów: exact HTTP context + jedna tania interpretacja, invalid scope/blank/oversize/role injection400 bez modelu, stary klient200, anon401 bez modelu, miesięczny hard limit503 bez modelu. PR19 https://github.com/jakatora/fitter-welder-pro-backend/pull/19 MERGED i przypięty; czysty main4c18ec07b6fb34ba1bd95a155e79139dee047edd, tree-identical z testowanym2e5c117396560e5f7e9df90f5b743d61a8d89a7a. Przed merge exact head, mergeabletrue/clean i brak failed commit status. Statuspending/0entries oraz check-runs403 nie są zielonym hosted CI.

Native197 ai_* PASS, potem broad3433 PASS+37 dawnych field-contract skips. Po broad wyłącznie czyszczenie interpreter history przy limicie i dodatkowy assert świeżej historii: końcowe ai_chat_execution25 PASS. Static6 plików --fatal-infos czyste przed ostatnią linią; końcowy wynik dopisany po zakończeniu. Nowy long widget wymaga root nieobecnego w history, obecnego w user_turns, oraz rzeczywistego przejścia native source guard do wykonania fixture. Limit32 jest sprawdzony w UI z odzyskaniem nowego żądania bez automatycznego retry. To nie pełny live NLU test.

## Wire proof
Dart capture z pełnymi FakeActionsPort/FakeIsoDrawingPort daje katalog80, nie sam default72 bez tych portów. Weryfikator celowo odrzucił zbyt małą pierwszą próbkę; poprawiono generator, nie zmniejszono assertu. tool/verify_assistant_clarification_wire.mjs odczytuje wygenerowany JSON i powtarza przez realny lokalny Express/SQLite. Powtórzony na czystym merged main o2026-10-22T15:00:34.548Z: PL26836B/EN26066B, oba31 prior userTurns, HTTP200, cały body zachowany, jedna injected Haiku low/0retry każda, rezerwacje0. Missing capture file jest błędem, nie skip.

## Granice
Dedykowany FWP_ANTHROPIC_API_KEY nadal nieobecny przy sprawdzeniu; nie użyto klucza PrzetargAI. Brak nowego deploy/APK/physical voice acceptance. Pełny cel pozostaje aktywny. Bieżąca próba pustych invalid unauthenticated request do produkcji jest w build/clarification-turns-production-proof.json; nie jest próbą rzeczywistego modelu lub zapisu profilu.

Końcowa analiza6 plików --fatal-infos bez uwag po zmianie recovery history; diffcheck czysty. Produkcja2026-10-22T15:01:54.251667+00:00: puste invalid unauth POST/ai/assistant404 NOT_FOUND oraz/account/profile/assistant404 NOT_FOUND. Merged main nie jest dowodem Railway deploy. Nie wydano nowego APK.
