# Jawny zakres działań dla modelu — 2026-10-22

Ogólna umiejętność calculator.action miała tool_id=null i przykłady kopiowania/czyszczenia, ale nie opisywała zakresu natywnego wykonania. Model nie widział, że dotyczy ona wyłącznie ośmiu kalkulatorów i całych wyników/formularzy. Dodano opcjonalny SkillActionScope z typowanym NativeActionTarget. Żądanie wysyła action_scope z listą narzędzi pochodzącą z tej samej stałej co natywna umiejętność oraz mapą copy=all_results, clear=all_inputs. Inne umiejętności nie dostają dodatkowych pól.

Zakres obejmuje slope_cut, elbow_cut, elbow_rotation, insert, reducer, pipe_weight, bevel i thermal_expansion. To opis obsługi, nie uprawnienie do wykonania. Dotychczasowe kontrole źródłowego polecenia, jawnego modułu, widocznego uchwytu, zmiany danych, zgody, błędu schowka i kolejności planu pozostają autorytatywne. Nie dodano czyszczenia pojedynczego pola ani kopiowania wybranego wyniku.

Backend przyjmuje action_scope opcjonalnie: 1–32 unikatowych identyfikatorów, co najmniej jedno znane działanie z dokładnym celem i brak dodatkowych pól. Odrzuca niespójność tool_id z zakresem oraz nadal ogranicza całe żądanie do 64 KB. Instrukcja modelu każe zachować nazwany moduł, w razie potrzeby najpierw go otworzyć oraz nie rozszerzać działania na inne moduły, pojedyncze pola, zapisy i dane konta. Nie jest to dowód, że rzeczywisty model zawsze wykona taką interpretację poprawnie.

## Zgodność i wdrożenie

Zmiana backendu została połączona przez [PR #7](https://github.com/jakatora/fitter-welder-pro-backend/pull/7), main 1e78fa5b875a2e0c6940544be7280e8f4fbfc8c7. Kanoniczna gałąź implementacji 79d8dab2ead264494479e3108f2e1710412ae255 ma identyczne drzewo źródeł jak przetestowany commit przed rebase. Lokalny backend/main w aplikacji zaktualizowano fast-forward do połączonej wersji.

Stary klient działa z nowym serwerem, bo pole jest opcjonalne. Nowy katalog wymaga wdrożenia nowego parsera po stronie serwera; stary ścisły parser nie przyjmie action_scope. Wersja koperty pozostaje 1. Nie dodano automatycznego ponawiania żądania bez metadanych.

2026-10-22T01:13:27Z: pusty nieprawidłowy POST do produkcyjnego /api/fitter/ai/assistant nadal zwraca 404 (build/assistant-action-scope-runtime-probe.json), a CLI OAuth nadal Unauthorized (build/assistant-action-scope-railway-auth.log). Nie rozpoczęto nowego parowania ani wdrożenia. Ta zmiana nie jest jeszcze potwierdzona w działającym modelu produkcyjnym.

## Weryfikacja i koszt

1032 testy aplikacji PASS, zero pominięć (build/assistant-action-scope-regression.log): rzeczywisty katalog PL/EN, serializacja metadanych, natywne kopiowanie/czyszczenie wszystkich ośmiu kalkulatorów, blokady źródła i pojedynczych pól, plany AI, dialogi, konta i pełny korpus routera. Router: 500 wypowiedzi w 750 ms. Cztery zmienione pliki przechodzą analyze --fatal-infos (build/assistant-action-scope-analyze.log). Nie zmieniono Darta po tych kontrolach.

Pełny backend: 204 PASS, zero pominięć (build/assistant-action-scope-backend-regression.log). Lokalne rzeczywiste HTTP do aplikacji sprawdza przeniesienie zakresu do kontrolowanego dostawcy i odrzucenie błędnego/pustego/zbyt dużego zakresu przed wywołaniem modelu. Nie jest to test semantycznej trafności prawdziwego Haiku ani dowód produkcyjnych opłat.

Ścieżka pieniędzy: bez zmiany modelu Haiku 5.5, niskiego poziomu effort, cen, limitów i ponowień. Nowe metadane wchodzą do istniejącej konserwatywnej rezerwacji budżetu przed płatnym wywołaniem. Pełny zestaw backendu obejmuje wspólne limity, twardą bramkę budżetu, nieznany model, rozliczenie niepewnej odpowiedzi i maxRetries=0. W tym etapie nie wykonano płatnego wywołania ani produkcyjnej płatności; nie można jeszcze ocenić rzeczywistej poprawy rozmowy ani jej kosztu na modelu.

Pełny cel pozostaje aktywny: dokładne kontrakty pozostałych działań/pól, widoczna historia rozmowy, kontekst zawodowy AI, własność lokalnych zapisów, ISO, wdrożenie i próby urządzeń nadal wymagają pracy.
