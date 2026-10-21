# Bieżące formularze w kontekście asystenta — 2026-10-22

Asystent potrzebuje aktualnych wartości z ekranu, aby wykonać „zmień tylko prąd” lub „przelicz połowę obecnej temperatury”. Historia rozmowy nie uwzględnia późniejszych ręcznych zmian użytkownika.

## Implementacja

Dodano jawny, tylko do odczytu kontrakt `InputToolHandle` dla ośmiu modułów: moment śrub, t8/5, źródło spawalnicze i przewody, twardość, wolfram, filtr przyłbicy, kolano segmentowe oraz szybki przelicznik. Wartości pochodzą z faktycznych kontrolerów i wybranych trybów. Puste i nieprawidłowe liczby pozostają `null`; dane pomiarów, identyfikatory spoin i pieczątki nie są wysyłane. Tabliczka spawarki jest spłaszczona do trzech par prąd/cykl, zgodnie z istniejącym skalarnym kontraktem kontekstu AI.

Przelicznik publikuje wyłącznie wybraną zakładkę, niezależnie od zachowanych w pamięci pozostałych zakładek. Filtr gazowy nie publikuje ukrytego prądu łuku. t8/5 rozróżnia Q z WPS i parametry łuku; granice okna mają oznaczenie `visible_form_unverified`, nie potwierdzenie zgodności WPS. Kolano z promieniem jako wielokrotnością OD publikuje aktualny promień wyliczony z ręcznie zmienionego OD.

Umiejętności tych kalkulatorów kierują zmiany względne i odwołania do obecnych ustawień do istniejącego interpretera AI. Kontynuacja korzystająca z widocznego formularza również wymaga interpretacji zamiast scalania ze starą historią. Dokładne, kompletne polecenia mogą nadal wykonać się lokalnie. Ułamki wymiarów śrub i oznaczenie t8/5 nie są traktowane jako dzielenie. Pojedyncze angielskie „current” oznaczające prąd nie wymusza AI.

Obliczenie cyklu pracy w bieżącym formularzu zachowuje przewody, a obliczenie przewodów zachowuje tabliczkę. Wewnętrzna, walidowana flaga `preserve_other_inputs` jest dodawana przez natywną umiejętność tylko przy rzeczywistym widocznym formularzu. Nowe obliczenia bez tej flagi zachowują dotychczasową politykę czyszczenia niepodanych danych.

t8/5 może teraz zastosować wynik w natywnym trybie U/I/v, weryfikując zgodność Q z procesem i parametrami przed zmianą formularza. Zmiana samej grubości zachowuje ten tryb przy zgodnym Q. Niestandardowa sprawność, której formularz nie obsługuje jako osobnego pola, nadal daje bezpośrednie Q. Parser prędkości wymaga jednostki minut przy danym wymiarze; minimum okna WPS nie może zamieniać grubości w prędkość. Ujemne słowne minimum jest walidowane, nie pomijane.

## Granice tego etapu

To rozszerzenie kontekstu oraz wybranych kontraktów wykonania, nie dowód obsługi każdego działania aplikacji. Kolano segmentowe nadal stosuje pełny wymiar promienia w mm; nie ma jeszcze uniwersalnego zachowania wszystkich trybów/presetów przy każdej zmianie. Inne moduły wymagają dalszego audytu działań. Własność lokalnych zapisów między kontami, pełne przekazanie wieloetapowych planów do ISO, topologia i fizyczna obsługa mikrofonu/iOS pozostają w zakresie aktywnego celu.

Nie zmieniono klienta dostawcy, cen, budżetów ani limitów. Domyślne ścieżki rozmowy i poleceń używają istniejącego `claude-haiku-5-5`. Oficjalny cennik ponownie sprawdzono 2026-10-22: https://platform.claude.com/docs/en/about-claude/pricing. Testy tego etapu używają kontrolowanego interpretera, nie płatnych wywołań.

## Weryfikacja

Końcowa regresja obejmująca rdzeń, cały korpus i wydajność routera, wykonanie AI, kontrakty modułów, wszystkie dotknięte umiejętności oraz natywne ekrany: **1390 PASS, 38 wcześniejszych pominięć brakujących przykładów, zero błędów** (`build/current-form-inputs-final-regression.log`). 500 wypowiedzi: 751 ms. Pominięcia nie są dowodem kompletności działań. Analiza 25 zmienionych plików Dart jest czysta (`build/current-form-inputs-final-analyze.log`), a końcowe zmiany helpera i testu głosowego także przechodzą `analyze --fatal-infos` (`build/current-form-inputs-fractions-analyze.log`). Po tych kontrolach nie zmieniono Darta.

Nowe testy sprawdzają rzeczywiste ręczne zmiany, wybrane zakładki/tryby, kontekst bez ukrytych i prywatnych pól, zachowanie przewodów/tabliczki i U/I/v, atomowe odrzucenie niezgodnego Q oraz błędnych typów, brak częściowego wykonania bez zgody na AI, zmiany względne PL/EN i odejmowanie, opóźnioną odpowiedź po edycji oraz symulowane polecenie głosowe. Przepełniony promień po pomnożeniu OD jest `null`, nie nieskończonością. Istniejący globalny scenariusz kolana nadal sprawdza cały dialog, korektę liczby spoin, odrzucenie zbyt małego promienia, naprawę wartości i brak fałszywych raportów, teraz z kontrolowanym interpreterem odczytującym rzeczywisty formularz.

Szerszy przebieg wszystkich testów asystenta, wszystkich domen i dotkniętych ekranów zakończył się **5028 PASS / 38 pominięć / 2 błędy** (`build/current-form-inputs-verified-regression.log`): wykrył traktowanie wymiaru śruby `1-1/8` jako odejmowania w PL/EN. Ten przebieg nie jest zielony. Poprawiono rozróżnienie, a końcowy zielony zestaw powyżej obejmuje oba błędne przypadki, pełny router i wszystkie dotknięte umiejętności. Wcześniej testy integracyjne ujawniły błąd parsera „min” oraz brak materiału w przygotowanym poleceniu testowym twardości. Poprawiono parser i polecenie testowe; nie usunięto obowiązku podania materiału. Jedną próbę końcowego polecenia przerwano po wykryciu nieistniejącej nazwy pliku testowego; poprawne polecenie wskazuje istniejący `ai_interpreter_test.dart` i zakończyło się wynikiem powyżej.

Stan infrastruktury z 2026-10-22: istniejąca karta aktywacji Railway nadal wymaga logowania, a ponowny `whoami` potwierdza `Unauthorized`. Bezpłatna próba POST z pustym, nieprawidłowym JSON-em do produkcyjnego `/api/fitter/ai/assistant` nadal zwraca 404 (`build/current-form-production-probe.json`, 2026-10-21T23:23:38Z = 2026-10-22 w Warszawie). Nie rozpoczęto kolejnej wygasającej sesji parowania ani nie zmieniono infrastruktury. Wdrożenie wymaga odzyskania autoryzowanej sesji osobnego projektu Fitter Welder Pro. ADB ponownie potwierdza zero urządzeń; mikrofon telefonu i iOS nie zostały zweryfikowane. Cały cel pozostaje aktywny.
