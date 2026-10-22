# Natywne działania kalkulatorów montera — 2026-10-22

Asystent i przyciski ekranu używają tego samego kontraktu wykonania dla ośmiu zakładek: cięcie pod spadek, cięcie kolanka, obrót kolanka, wstawka, redukcja, ciężar rury, fazowanie i dylatacja.

## Zachowanie

- `calculator.action` obsługuje kopiowanie wyników i czyszczenie wpisanych pól bieżącego kalkulatora. Proste polecenia PL/EN są lokalne. Nazwane lub swobodne polecenia trafiają do istniejącego interpretera AI, zamiast uruchamiać pytania o wymiary w parserze obliczeń.
- Wyniki do schowka pochodzą z ponownie przeliczonych natywnych danych; są podpisane i mają jednostki. Błędne dane, brak wyników i przepełnienia nie kopiują starego rezultatu. Nie dodano wzorów ani obliczeń modelu.
- Czyszczenie opróżnia kontrolery liczbowe, usuwa stare wyniki i komunikaty brakujących danych. Zachowuje wybory trybu, materiału, konwencji oraz kąta bazowego. Czyści również schowane pola tego samego kalkulatora, np. ręczny promień wstawki.
- Dwa przyciski paska narzędzi wykonują te same funkcje co czat. Przyciski mają etykiety PL/EN. Sprawdzono angielski ekran 320×640 z tekstem ×1,3 i cele dotyku co najmniej 48 dp.
- Osiem zakładek zachowuje własny stan w pamięci otwartej trasy. Szybka zmiana zakładki nie odtwarza pustego formularza. Odczyt i działania nadal dotyczą wyłącznie wybranej zakładki; to nie jest zapis formularzy na dysk ani przypisanie ich do konta.

## Zgodność polecenia i wykonania

Port `ModuleActionHandle` jest jawny. Nie wyszukuje widżetów ani dowolnego tekstu. `ToolBridge` odrzuca niewłaściwy cel, ukrytą trasę i otwarty dialog; ekran ponownie sprawdza wybraną zakładkę i gotowość przed wykonaniem. Anulowane działanie oczekujące na montaż nie czyści innego formularza.

Model nie może zamienić kopiowania w czyszczenie. Jawnie nazwany kalkulator jest sprawdzany przez istniejący rejestr narzędzi; słabe dopasowanie słowa w podtytule nie oznacza wyboru celu. Poprawny plan może otworzyć wskazaną redukcję i wyczyścić ją, zachowując ciężar rury. Polecenia o koncie, haśle lub usuwaniu zapisów nie są czyszczeniem pól kalkulatora. Prośba o pojedyncze pole nie może zostać wykonana jako wyczyszczenie całego formularza.

Rozpoznawanie sekwencji obejmuje teraz `i`, `oraz`, `and` oraz czasowniki kopiowania i czyszczenia. „Oblicz…, potem skopiuj wyniki i wyczyść pola” wykonuje natywne kroki po kolei. Bez zgody na AI nie wykonuje części obliczeniowej takiego polecenia. Nieudane kopiowanie lub odmowa wykonania kasuje pozostały plan.

Kopiowanie może czekać na odpowiedź systemowego schowka. Stan narzędzia, trasy i danych jest wtedy porównywany po wykonaniu i prezentacji wyniku, zanim plan przejdzie dalej. Zmiana zakładki lub ręczna edycja zatrzymuje późniejsze czyszczenie, zachowując informację o już wykonanej kopii. Zmiana zgody na AI zatrzymuje kolejne kroki planu.

## Weryfikacja

32 nowe przypadki na rzeczywistych widżetach obejmują wszystkie osiem zakładek, ręczne edycje, ten sam przycisk i port, błędy danych, awarię schowka, odświeżenie obliczeń po wypełnieniu kontrolera, przepełnienie, schowany promień, ukrytą trasę/dialog, zmianę zakładki w oczekującym działaniu, poprawny i błędny cel modelu, etykiety PL/EN i wąski ekran EN, kolejność działań, odmowę częściowego wykonania bez zgody, opóźnioną interpretację oraz symulowane polecenie głosowe. Kontrolowane opóźnienie schowka sprawdza oddzielnie zmianę zakładki, danych i zgody.

Końcowa szersza regresja: **2959 PASS, 38 wcześniejszych pominięć brakujących przykładów, zero błędów** (`build/fitter-native-actions-regression.log`). Obejmuje cały asystent, domeny montera i natywne testy zakładek/obliczeń ekranu. Router: 500 wypowiedzi w 714 ms. Pominięcia nie potwierdzają kompletności działań. Sześć zmienionych plików przechodzi `dart analyze --fatal-infos` (`build/fitter-native-actions-verified-analyze.log`). Po tych kontrolach nie zmieniono Darta. Wcześniejszy zestaw 978 PASS bez pominięć z pełnym korpusem routera jest w `build/fitter-native-actions-source-test.log` (500 wypowiedzi w 683 ms).

Pierwsze czerwone testy ujawniły utratę stanu zakładki oraz przechwytywanie nazwanych działań przez parsery obliczeń. Poprawiono implementację, zachowując sprawdzenie rzeczywistego stanu. W ośmiu testach poprawiono lokalizator pola: po przebudowie wskazuje aktualny widżet przez tożsamość kontrolera, zamiast szukać starej instancji widżetu.

## Dalszy zakres i infrastruktura

Ten etap obejmuje pełne wyniki i całe wpisane formularze tych ośmiu kalkulatorów w globalnym panelu asystenta. Pozostałe działania, wybór konkretnego wyniku, czyszczenie pojedynczych pól, tryby i presety wymagają dalszych jawnych kontraktów. Pełny cel nadal obejmuje własność lokalnych zapisów między kontami, spójne przekazanie planów między samodzielnym czatem a panelem globalnym, dalsze przekazanie planów do ISO i topologię, rzeczywisty model, wdrożenie oraz próbę mikrofonu telefonu i iOS.

Nie zmieniono dostawcy, modelu, limitów ani budżetów. Pozostaje istniejący Haiku 5.5; ten etap nie wywoływał płatnego API. Testy używają kontrolowanego interpretera i symulacji mowy. Karta Railway sprawdzona ponownie 2026-10-22 nadal wymaga logowania, a CLI `whoami` zwraca `Unauthorized` (`build/fitter-native-actions-railway-auth.log`). Nie rozpoczęto kolejnej sesji parowania ani nie zmieniono infrastruktury. Cały cel pozostaje aktywny.

Ponowna próba nieprawidłowego pustego POST do produkcyjnego `/api/fitter/ai/assistant` nadal zwróciła 404: 2026-10-22T00:22:45Z. ADB potwierdza zero urządzeń gotowych, nieautoryzowanych i offline (`build/fitter-native-actions-runtime-probe.json`). Nie jest to dowód nowego działania modelu ani wykonania na telefonie.
