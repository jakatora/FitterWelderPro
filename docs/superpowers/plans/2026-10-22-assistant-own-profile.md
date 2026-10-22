# Własne konto w nagłówku asystenta — 2026-10-22

Globalny panel pokazuje teraz nazwę zalogowanego użytkownika i jego zawód z AccountService, czyli z konta Railway. To nie jest starszy lokalny profil społecznościowy. Naciśnięcie nagłówka otwiera istniejący ekran konta; trasa formularza nadal ukrywa panel asystenta podczas wpisywania danych.

Przy montowaniu nagłówka odtwarzana jest istniejąca sesja z magazynu systemowego. Pusty magazyn nie tworzy identyfikatora urządzenia i nie powoduje żądania HTTP. Zapisana sesja jest sprawdzana przez istniejące /account/me, a odczyt nie jest powtarzany przy przebudowie interfejsu. Awaria magazynu nie blokuje kalkulatorów; ekran konta zachowuje własną obsługę ponowienia i błędów. Podczas sprawdzania sesji widoczny jest tekst statusu.

Po błędzie sieci zachowany token nie jest przedstawiany jako potwierdzone konto ani jako wymóg ponownego logowania. Nagłówek kieruje do ponowienia profilu. Ekran konta ponawia GET/me; przy kolejnym błędzie pokazuje przycisk ponowienia zamiast żądać hasła. Udany odczyt nie zmienia rewizji sesji i nie czyści rozmowy. Odpowiedź 401 unieważnia wygasłą sesję i przywraca formularz logowania. Odpowiedzi ze starej rewizji nie mogą zmienić nowszego konta lub jego tokenu w magazynie systemowym.

Właściciel widzi własną nazwę i zawód również przy publicProfile=false. Nagłówek nie pokazuje e-maila, hasła, tokenu ani kwalifikacji; nie dopisuje tych danych do kontekstu modelu i nie nadaje uprawnień. Zmiana profilu aktualizuje etykietę, zachowując szkic i rozmowę. Zmiana sesji uruchamia dotychczasowe czyszczenie konwersacji; stara nazwa i szkic nie wracają po wylogowaniu.

Styl pochodzi z istniejącego motywu. Dwa wiersze mają ograniczenie do dostępnej szerokości, a wysokość nagłówka rośnie wraz ze skalą tekstu. Cały obszar profilu jest celem dotykowym co najmniej 48 dp; ma opis dla czytnika ekranu i tooltip PL/EN.

## Sprawdzenie

Osiem nowych przypadków widżetowych sprawdza pustą instalację bez HTTP, prywatny formularz konta, odtwarzanie zapisanej sesji i pojedynczy GET/me, wyświetlenie własnego niepublicznego zawodu bez prywatnych pól, zmianę profilu bez utraty szkicu, czyszczenie po zmianie sesji, długi profil w PL/EN przy skali 2 oraz rzeczywisty panel o szerokości 320 px ze skalą 2 i nagłówkiem wysokości 80 dp. Obejmują także dwa błędy sieci i jawne ponowienie bez ponownego logowania oraz usunięcie wygasłego tokenu po 401. Dwa nowe testy serwisu sprawdzają spóźnione 200 i 401 po zalogowaniu na nowe konto, włącznie z tokenem zapisanym w systemie.

Regresja całego asystenta, wyścigów sesji konta i prywatnych raportów: 2729 PASS, 38 wcześniejszych pominięć brakujących przykładów, zero błędów (build/assistant-account-header-regression.log). Następnie dodano jawne ponowienie po błędzie sieci i jego testy. Końcowy zestaw nagłówka, prezentacji rozmowy, izolacji AI, wyścigów konta, formularzy i raportów: 42 PASS bez pominięć (build/assistant-account-header-final-verified-test.log). Sześć zmienionych plików Dart przechodzi analyze --fatal-infos (build/assistant-account-header-final-verified-analyze.log). Nie zmieniano Darta po tych kontrolach.

To testy z kontrolowanym transportem, a nie nowa próba produkcyjnego logowania z telefonu. Dowód rzeczywistego logowania administratora i odczytu raportów z poprzedniego etapu jest w [jednej prezentacji rozmowy](2026-10-22-single-assistant-presentation.md). Nie wykonano nowego płatnego wywołania AI ani zmiany backendu, cen lub budżetów.

Pełny cel pozostaje otwarty: widoczna historia konwersacji, zawodowy kontekst modelu, własność lokalnych zapisów między kontami, pozostałe kontrakty działań, przekazanie planów do ISO, wdrożenie nowego sterowania AI i próby urządzeń. Sam nagłówek nie dowodzi ukończenia tych części.
