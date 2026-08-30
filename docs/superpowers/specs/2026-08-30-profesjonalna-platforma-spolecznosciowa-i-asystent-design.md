# Fitter Welder Pro — profesjonalna platforma pracy, społeczności i asystenta

**Data:** 2026-08-30  
**Status:** zatwierdzony projekt  
**Zakres:** rozwój istniejącej aplikacji bez usuwania jej modułów

## 1. Cel

Fitter Welder Pro ma być profesjonalnym narzędziem pracy i społecznością dla spawaczy oraz monterów. Aplikacja zachowuje wszystkie obecne moduły, poprawia ich niezawodność i użyteczność oraz dodaje konto z synchronizacją, asystenta tekstowego i głosowego, fachowe profile, publikacje i nowoczesną komunikację.

Sukces oznacza, że doświadczony fachowiec pracuje szybciej, a początkujący rozumie, jakie dane wpisać, jak powstaje wynik i kiedy musi odwołać się do WPS, WPQR, dokumentacji projektu lub inżyniera.

## 2. Nienaruszalne zasady

1. Nie usuwamy istniejących modułów ani danych użytkownika.
2. Zmiany danych wymagają zgodnej migracji i zachowania dostępu offline.
3. Model AI nie zapisuje bezpośrednio do bazy danych.
4. Każda operacja przygotowana przez AI jest walidowana przez deterministyczną warstwę aplikacji.
5. Operacja zmieniająca dane wymaga podsumowania i potwierdzenia użytkownika.
6. Niepewna wartość ze skanera ISO nigdy nie staje się po cichu długością cięcia.
7. Wyniki kalkulatorów są pomocą techniczną, nie zamiennikiem zatwierdzonej dokumentacji.
8. Każdy etap przechodzi testy, analizę kodu i przegląd zmian.

## 3. Nawigacja i wygląd

Dolna nawigacja składa się z pięciu obszarów:

1. **Start** — ostatnie projekty, narzędzia, zapisane parametry i szybkie akcje.
2. **Narzędzia** — wszystkie istniejące moduły pogrupowane jako Monter, Spawacz, Projekty i Dokumentacja.
3. **Asystent** — rozmowa tekstowa i głosowa oraz historia zatwierdzonych operacji.
4. **Społeczność** — fachowe posty, pytania, zdjęcia realizacji, komentarze i obserwowane osoby.
5. **Profil** — dane zawodowe, uprawnienia, procesy, parametry, ustawienia i synchronizacja.

Istniejące moduły pozostają dostępne. Użytkownik może je wyszukać po nazwie, zadaniu i słowach branżowych oraz przypiąć do ekranu Start. Interfejs korzysta z jednego systemu typografii, kolorów, odstępów, kart, formularzy, komunikatów i stanów ładowania. Elementy dotykowe są wygodne w warunkach warsztatowych.

## 4. Uproszczenie modułów

Każdy kalkulator otrzymuje dwa poziomy:

- **Szybko** — minimalny zestaw pól i czytelny wynik;
- **Pokaż jak** — znaczenie danych wejściowych, wzór, podstawienie przykładu, jednostki, interpretacja wyniku i najczęstszy błąd.

Pomoc nie zmienia logiki obliczeń. Dla wartości wpływających na bezpieczeństwo ekran wskazuje ograniczenia metody i dokument nadrzędny. Walidacja blokuje wartości fizycznie niemożliwe, nieskończone, ujemne lub spoza jawnego zakresu.

## 5. Konto i synchronizacja

Firebase Authentication zapewnia stabilny identyfikator użytkownika. Obecny lokalny profil zostaje zmigrowany po zalogowaniu, a użytkownik przed wysłaniem danych widzi zakres synchronizacji.

Synchronizowane są profil zawodowy, ustawienia, własne parametry spawania, ulubione narzędzia, treści społecznościowe, relacje oraz rozmowy. Kalkulatory nie wymagają sieci. Projekty, dzienniki i parametry zapisują się najpierw lokalnie, a synchronizacja działa jako osobna kolejka zmian.

Każdy rekord ma identyfikator, czas modyfikacji i wersję. Dla prostych ustawień wygrywa najnowsza potwierdzona zmiana. Konflikt parametrów, projektów lub dzienników tworzy dwie wersje do wyboru zamiast nadpisania danych.

## 6. Asystent tekstowy i głosowy

Asystent ma dwa tryby:

- **Odpowiedz** — wiedza branżowa, wyjaśnienia modułów i prowadzenie przez obliczenia;
- **Wykonaj** — przygotowanie dozwolonej operacji na danych aplikacji.

Przykład: „Zapisz, że spawam stal nierdzewną, ściankę 2 mm, TIG bez drutu na 60 amperach”.

1. Mowa zostaje zamieniona na tekst i pokazana użytkownikowi.
2. Asystent klasyfikuje intencję jako `save_weld_parameter`.
3. Zwraca ustrukturyzowane pola, nie polecenie bazodanowe.
4. Walidator sprawdza typy, jednostki, zakresy i kompletność.
5. Brakująca istotna informacja powoduje jedno krótkie pytanie.
6. Ekran pokazuje dokładne podsumowanie zapisu.
7. Potwierdzenie zapisuje rekord lokalnie i dodaje go do kolejki synchronizacji.
8. Użytkownik otrzymuje potwierdzenie oraz możliwość cofnięcia.

Minimalny zapis zawiera materiał, proces, tryb z drutem lub bez, grubość ścianki, prąd i notatkę źródłową. Średnica, pozycja, gaz, przepływ, elektroda i rodzaj złącza są opcjonalne, ale asystent pyta o nie, gdy brak uniemożliwia bezpieczne wykorzystanie parametru.

Model może zwrócić wyłącznie wersjonowany zestaw intencji z listy dozwolonej. Router odrzuca nieznaną intencję, dodatkowe pola, błędne typy, wartości spoza zakresu i próbę operacji bez ważnego potwierdzenia. Model nie otrzymuje kluczy, SQL ani bezpośredniego uchwytu do usług zapisujących.

Rozpoznawanie mowy wymaga jawnego naciśnięcia mikrofonu. Interfejs pokazuje stan nasłuchiwania, umożliwia zatrzymanie i edycję transkrypcji. Odczyt odpowiedzi jest ustawieniem użytkownika i nie działa automatycznie w tle.

## 7. Społeczność zawodowa

Sercem społeczności jest tablica fachowych publikacji. Post może być oznaczony jako pytanie, realizacja, porada, problem techniczny lub oferta współpracy. Obsługuje tekst, zdjęcia, komentarze, reakcje, zapisanie i obserwowanie autora.

Profil zawodowy może zawierać doświadczenie, procesy, materiały, specjalizacje i region. Uprawnienia deklarowane przez użytkownika są oznaczone jako niezweryfikowane do czasu wdrożenia osobnego procesu kontroli dokumentów.

System zawiera blokowanie użytkowników, zgłaszanie treści, limity częstotliwości, moderację oraz możliwość usunięcia własnych treści i eksportu danych.

## 8. Profesjonalny komunikator

Obecny czat zostaje przebudowany bez utraty funkcji. Docelowo obejmuje listę rozmów z ostatnią wiadomością i liczbą nieprzeczytanych, rozmowy branżowe, prywatne i grupy projektowe, odpowiedzi, reakcje, zdjęcia, stany wysyłania i ponawiania, szkice, profile autorów, blokowanie, zgłaszanie, paginację i brak dublowania wiadomości.

## 9. Skaner ISO i lista cięć

Skaner ma trzy niezależne warstwy:

1. **Odczyt AI** — rozpoznaje opis rysunku, segmenty, komponenty, wymiary i poziom pewności.
2. **Deterministyczny planista** — normalizuje jednostki, klasyfikuje komponenty, dobiera take-outy z tabel i przekazuje kompletne dane do jednego silnika CUT.
3. **Kontrola użytkownika** — pokazuje wartości źródłowe, założenia, ostrzeżenia i blokujące braki przed zapisem projektu.

Formuła i każde odjęcie są widoczne. Nieznany typ zaworu, niejednoznaczny punkt wymiarowania, brak średnicy lub schedule, rozgałęzienie albo niska pewność blokują automatyczny zapis odpowiedniego cięcia.

Odblokowanie produkcyjne wymaga uwierzytelnienia żądań, serwerowego limitu użycia i budżetu, zestawu referencyjnych rysunków, testów kolan 45°/90° LR/SR, trójników, redukcji, kołnierzy, zaworów, odgałęzień i różnych referencji wymiarowych, jednego źródła CUT oraz ręcznej kontroli wartości niepewnych.

## 10. Audyt wszystkich modułów

Każdy moduł trafia do inwentaryzacji z ekranem wejścia, przypadkami użycia, właścicielem danych i istniejącymi testami. Ocena obejmuje:

1. poprawność techniczną — uruchomienie, zapis, eksport, nawigację i błędy;
2. poprawność branżową — wzory, tabele, jednostki, tolerancje i zaokrąglenia;
3. użyteczność — zrozumiałość pól, wyniku i następnego kroku;
4. dostępność — rozmiary dotyku, kontrast, skalowanie tekstu i błędne dotknięcia;
5. odporność danych — migracje, brak utraty danych, eksport i działanie offline.

Status modułu: działa prawidłowo; działa, ale wymaga uproszczenia; zawiera błąd wymagający naprawy; wymaga potwierdzenia danych branżowych. Raport podaje dowód w postaci testu, przykładu obliczenia lub wskazania braku danych. Samo otwarcie ekranu nie oznacza zaliczenia.

## 11. Obsługa błędów

- Brak sieci nie blokuje lokalnych narzędzi ani zapisanych danych.
- Błąd synchronizacji zachowuje lokalną zmianę i pokazuje ponowienie.
- Błąd AI nie jest przedstawiany jako wiarygodna odpowiedź.
- Przerwane rozpoznawanie mowy zachowuje transkrypcję.
- Nieudany skan nie uruchamia płatnej próby ponownie bez wiedzy użytkownika.
- Operacje bazodanowe są atomowe; częściowy zapis nie tworzy niekompletnego rekordu.
- Komunikaty wyjaśniają zdarzenie i następny krok.

## 12. Testowanie i odbiór

Każda funkcja powstaje w cyklu test najpierw, implementacja, refaktoryzacja. Wymagane są testy jednostkowe parserów, walidatorów, obliczeń i konfliktów; testy widżetów; testy integracyjne konta, synchronizacji, asystenta, czatu i skanera; testy migracji, pracy offline, synchronizacji, poleceń adwersaryjnych oraz złoty zestaw rysunków ISO z oczekiwanymi listami cięć.

Po każdej partii muszą przejść `flutter analyze` i pełny `flutter test --no-pub`. Moduł jest zaliczony tylko wtedy, gdy ma udokumentowane przypadki, przechodzi właściwe testy i nie powoduje regresji.

## 13. Etapy wdrożenia

1. Inwentaryzacja i pełny audyt istniejących modułów.
2. Fundament konta, migracji i synchronizacji.
3. Asystent tekstowy i głosowy z bezpiecznym zapisem parametrów.
4. System wyglądu, nawigacja i uproszczone wejścia do modułów.
5. Profesjonalny komunikator i społeczność zawodowa.
6. Weryfikacja, zabezpieczenie i produkcyjne odblokowanie skanera ISO.
7. Tryb „Pokaż jak” i poprawki wykryte w kalkulatorach.
8. Końcowy audyt regresji, dostępności, danych i wydania.

Każdy etap dostarcza działającą, testowalną zmianę. Kolejny nie rozpoczyna się, jeśli poprzedni pozostawia błędy krytyczne albo niezweryfikowane migracje.

## 14. Poza bieżącym zakresem

- automatyczne potwierdzanie autentyczności uprawnień;
- publiczne rankingi fachowców;
- automatyczne publikowanie treści przez AI;
- operacje asystenta bez potwierdzenia;
- gwarantowanie bezbłędnego wyniku z nieczytelnego lub niejednoznacznego ISO.

Te funkcje mogą otrzymać osobne projekty po ustabilizowaniu podstawowej platformy.
