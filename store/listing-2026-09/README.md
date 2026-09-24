# Listing sklepowy FitterWelder Pro — wrzesień 2026 (wersja 0.3.0)

Przygotowano 2026-09-24 wg skilla `aso-app-store-optimization`. Tylko pliki tekstowe — nic nie zostało wysłane do sklepów, kod aplikacji nietknięty. Każde pole z limitem ma w nagłówku licznik znaków policzony skryptem (nowa linia = 1 znak). Wszystkie pola sprawdzone: w limicie, bez emoji (tylko punktor `•`), bez zakazanych obietnic.

## Co gdzie wkleić

| Plik | App Store Connect | Google Play Console |
|---|---|---|
| `pl.md` | lokalizacja **Polski** (primary) | **pl-PL** (język domyślny) |
| `en-US.md` | **English (U.S.)** | **en-US** |
| `en-GB.md` | **English (U.K.)** — dodać nową lokalizację | opcjonalnie en-GB: tytuł i krótki opis z `en-US.md`, pełny opis z `en-GB.md` |
| `de-DE.md` | **German** — dodać nową lokalizację | **de-DE** — dodać tłumaczenie |
| `whats-new-0.3.0.md` | „What's New” w każdej lokalizacji wersji 0.3.0 | „Informacje o wersji” (gotowy blok z tagami `<pl-PL>…`) |

App Store Connect:
1. **App Information** → dla każdej lokalizacji (przełącznik języka u góry): **Name**, **Subtitle**. Nowa nazwa i podtytuł wchodzą dopiero razem z zatwierdzoną wersją 0.3.0. Nazwa pod ikoną na telefonie się nie zmienia (`CFBundleDisplayName` = „FitterWelder Pro”).
2. **Wersja 0.3.0** → każda lokalizacja: **Promotional Text**, **Description**, **Keywords**, **What's New**, zrzuty ekranu.
3. **App Information → Category**: Primary **Utilities**, Secondary **Productivity** (dziś: Business).
4. **App Privacy** — według `docs/store/deklaracje-prywatnosci.md` (dziś karta mówi „nie zbieramy danych”, a czat wysyła imię i nazwisko).

Google Play Console:
1. **Główna strona aplikacji** (pl-PL): tytuł, krótki opis, pełny opis. **Zarządzaj tłumaczeniami** → en-US, de-DE (i opcjonalnie en-GB).
2. **Ustawienia sklepu → Kategoria**: **Narzędzia (Tools)**.
3. **Bezpieczeństwo danych** — ten sam plik z deklaracjami.
4. Rozważ zmianę **języka domyślnego** na en-US: użytkownik w kraju bez tłumaczenia (Norwegia, Holandia) zobaczy wtedy angielski zamiast polskiego; Polak z telefonem po polsku i tak dostanie pl-PL.

## Najważniejsze decyzje

**Nazwa = marka + jedno słowo z wyszukiwania.** „FitterWelder” to dla Apple jedno słowo — zapytania „fitter”, „welder”, „monter” go nie trafiają. Dlatego po dwukropku dodane jest słowo zawodu w języku rynku:

| Lokalizacja | Name (≤30) | Subtitle (≤30) |
|---|---|---|
| PL | `FitterWelder Pro: Monter Rur` (28) | `Kalkulator i dziennik spawacza` (30) |
| EN-US | `FitterWelder Pro: Pipe Fitter` (29) | `Cut List, Offsets & Weld Log` (28) |
| EN-GB | `FitterWelder Pro: Pipe Fitter` (29) | `Isometric Cut List & Weld Log` (29) |
| DE | `FitterWelder Pro: Rohrbau` (25) | `Rohrschlosser & Schweißer` (25) |
| Play PL / EN-US / DE | jak Name w App Store (28 / 29 / 25) | krótki opis: 77 / 75 / 78 znaków (limit 80) |

**Słowa kluczowe App Store** (bez spacji, bez słów z Name/Subtitle — Apple i tak łączy te trzy pola):

| Lokalizacja | Pole Keywords | Znaki |
|---|---|---|
| PL | `spawacz,spawanie,lista,cięcia,rurociąg,rury,kolano,izometria,spoina,siodło,wstawka,spadek,kołnierz` | 98 |
| EN-US | `pipefitter,calculator,welder,welding,rolling,takeout,elbow,saddle,heat,input,isometric,torque,tig` | 97 |
| EN-GB | `pipefitter,welder,welding,calculator,offset,rolling,takeout,heat,input,spool,elbow,spawacz,monter` | 97 |
| DE | `zuschnittliste,isometrie,rechner,rohr,etage,rohrbogen,rohrleitung,schweißen,schweißnaht,druckprüfung` | 100 |

Uzasadnienie:
- **Zawód** (spawacz, pipefitter, welder, Rohrschlosser) — tak monter i spawacz szukają narzędzia dla siebie. „pipefitter” pisane razem i „pipe fitter” osobno to dla Apple różne słowa, więc jedno jest w nazwie, drugie w Keywords. „spawacza” w podtytule czyta się naturalnie, a „spawacz” w Keywords łapie mianownik, który ludzie wpisują.
- **Główne zadania** (lista cięcia, kolano/elbow/Rohrbogen, rolling offset/Etage, takeout, siodło/saddle, izometria/isometric, Zuschnittliste) — to są funkcje, od których zaczyna się praca z aplikacją, i te same słowa są w nazwach konkurentów (Pipe Trades Pro Calc, PipeFit Pro, Pipe Calc Elite, Pipefitter T. Szymańskiego).
- **Spawacz** (heat + input, tig, spoina, spawanie, Schweißnaht, Druckprüfung) — druga grupa użytkowników; „heat input” to popularne zapytanie spawaczy i inspektorów, a mało aplikacji monterskich je pokrywa.
- **EN-GB jako drugie pole na Europę.** Apple indeksuje English (U.K.) także w innych europejskich sklepach, m.in. w Polsce, Niemczech, Holandii i krajach nordyckich (sprawdź aktualną tabelę Apple „App Store localizations”, zanim na tym oprzesz decyzję). Dlatego PL i DE nie powtarzają angielskich słów, a EN-GB ma angielskie terminy, których używają też Polacy na prefabrykacji (spool, takeout, rolling offset), plus `spawacz,monter` dla Polaków w krajach bez polskiej lokalizacji.
- **Pominięte celowo:** nazwy norm i organizacji (ASME, AWS — znaki towarowe; Apple 2.3.7), nazwy konkurentów, „free”, „app”, „pro” (jest w nazwie), liczba mnoga obok pojedynczej.

**Google Play** nie ma pola Keywords, ale indeksuje pełny opis — główne frazy (monter / spawacz / lista cięć / kalkulator; pipe fitter / welder / cut list / calculator; Rohrschlosser / Schweißer / Zuschnittliste / Rechner) występują w nim 3–5 razy, naturalnie, bez upychania.

**Opis PL/EN/DE ma ten sam układ:** obietnica w 2 pierwszych liniach (widoczne przed „więcej”), zdanie o Internecie, sekcje Monter / Spawacz / Czat / Na co dzień / Twoje dane, na końcu zastrzeżenie „wyniki pomocnicze, sprawdzaj z WPS i normami” i informacja, że aplikacja nie jest powiązana z ASME/AWS/EN/DIN/MSS. W DE zdanie „Die App-Oberfläche gibt es auf Polnisch und Englisch, nicht auf Deutsch” jest w drugim akapicie, żeby było widoczne bez rozwijania.

## Zrzuty ekranu

- **App Store przyjmuje tylko** `1242×2688`, `1284×2778` (pion) albo `2688×1242`, `2778×1284` (poziom). Zrzut z Androida `1080×2400` **App Store odrzuca** — trzeba go wpasować z marginesem (letterbox) w 1284×2778 albo 1242×2688.
- **Google Play:** dłuższy bok może być najwyżej 2× dłuższy od krótszego. `1080×2400` (2,22:1) i `1242×2688` (2,16:1) przekraczają tę proporcję — do Play daj `1080×1920` (9:16). Sprawdź przy wgrywaniu.
- **Obecne pliki są nieaktualne i nie nadają się do 0.3.0:**
  - `store/app_store/screenshots/*.png` to makiety z pustymi paskami zamiast treści, a nie prawdziwy ekran aplikacji (Apple 2.3.3 wymaga zrzutów z działającej aplikacji);
  - `test_screenshots/shots/*.png` pokazują stary ekran główny (kafel POMOC, znaczek „Aktywny”) i zepsute znaki: w tytule są kwadraty zamiast liter, w powitaniu „Witaj, Spawaczu” jest brakujący znak.
  - Wygeneruj je od nowa z wersji 0.3.0: `C:\Users\Startklaar\flutter\bin\flutter.bat test test_screenshots --update-goldens` (Flutter 3.47.5; ten z PATH nie zbuduje projektu), potem popraw fonty, żeby zniknęły kwadraty.
- **Kolejność i podpisy (3–5 słów, słowo kluczowe w podpisie).** Pierwsze 3 zrzuty decydują o instalacji. Czatu nie pokazuj na pierwszych trzech.

| # | Ekran | PL | EN | DE |
|---|---|---|---|---|
| 1 | Lista cięć z take-outami | Lista cięć z izometrii | Cut list from the ISO | Zuschnittliste aus Isometrie |
| 2 | Zeszyt ISO ze szkicem | Szkic ISO z długością cięcia | ISO sketch with cut lengths | ISO-Skizze mit Zuschnitt |
| 3 | Rolling offset / wymiary kolan | Rolling offset z kątem obrotu | Rolling offset with roll angle | Etage mit Verdrehwinkel |
| 4 | Szablon siodła 1:1 | Szablon siodła do druku | Printable saddle template | Sattelschablone zum Drucken |
| 5 | Heat input i podgrzewanie | Heat input i podgrzewanie | Heat input and preheat | Streckenenergie und Vorwärmen |
| 6 | Próba ciśnieniowa + PDF | Próba ciśnieniowa z protokołem | Pressure test with PDF report | Druckprüfung mit PDF-Protokoll |

Na zrzutach nie może być Premium, AI, skanera ISO ani ogłoszeń pracy.

## Czego NIE obiecywać (Apple 2.3, Google Play „Wprowadzanie w błąd”)

- „działa w pełni offline” / „works fully offline” / samo słowo „offline”. Poprawnie: **kalkulatory, projekty i dziennik spoin działają bez Internetu; Internet jest potrzebny tylko do czatu**.
- „nie zbieramy danych”, „bez konta”, „bez rejestracji”, „no tracking”. Czat wysyła treść wiadomości, imię i nazwisko oraz identyfikator instalacji.
- AI, asystent, skaner rysunków, Premium, subskrypcja, ogłoszenia pracy, „wkrótce” — są wyłączone w kodzie.
- Tryb wyników w ułamkach cala. Aplikacja **przyjmuje** cale (`76"`, `4 1/2"`) i liczy w mm; przelicznik obsługuje mm, cale i stopy — tylko tyle wolno napisać.
- Niemiecki interfejs — nie istnieje.
- Zgodność, certyfikację albo „zatwierdzenie” przez ASME/AWS/EN. Wolno pisać „wg tabel/wzorów z …”.
- „Zbudowane przez montera dla monterów”, „najlepsza”, „nr 1”, opinie i oceny w opisie — nie mamy na to dowodu, a Google zabrania rankingów i opinii w opisie.
- Usuwanie danych z serwera — dopiero gdy nowy backend działa (patrz niżej).

## Przed wysłaniem 0.3.0 (poza tymi plikami)

1. **Backend.** Żywy backend nie ma jeszcze stron `/privacy` i `/data-deletion` (2026-09-24: HTTP 404), więc nie działa też `DELETE /api/fitter/me`. Bez wdrożenia: brak URL polityki prywatności dla obu sklepów i nieprawdziwy punkt o usuwaniu danych w What's New (instrukcja w `whats-new-0.3.0.md`). Sprawdź też, czy 0.3.0 (sekret instalacji) rozmawia ze starym backendem, jeśli wydasz ją przed wdrożeniem.
2. **Czat do posprzątania.** Pokój „Ogólny” ma testowe i wulgarne wpisy („dupa”, „tggyu”, „xjdjd”), pozostałe pokoje są prawie puste. Recenzent Apple otworzy czat (UGC, wytyczna 1.2) — ukryj te wpisy panelem moderacji przed wysłaniem.
3. **App Privacy / Data Safety** — wypełnić zgodnie z `docs/store/deklaracje-prywatnosci.md`.
4. **Stare pliki z nieprawdziwymi zdaniami** — nie używać, zastąpione przez ten katalog:
   - `appstore_metadata.md`: „Calculators and projects work offline. No ads, no tracking.” / „Kalkulatory i projekty działają offline. Bez reklam i śledzenia.”; polityka „does not request access to … camera” (nieprawda: aparat i zdjęcia służą do zdjęć wytopów); „Pipe route — 3 × 90°” (jest 2 × 90°); „Route measurement” (takiego narzędzia nie ma); „Component library — standard dimensions” (to Twoja własna biblioteka); „Built by a pipe fitter” (niezweryfikowane); What's New „Initial release”.
   - `PLAY_RELEASE_NOTES_PL_EN.md` — notatki z wersji 0.1.2.
   - `store/app_store/APP_STORE_METADATA_PL_EN.md` — starsza kopia metadanych.
   - Tekst na obecnej karcie App Store (EN) kończy się „…even offline.” — zastąp go nowym Promotional Text.
5. **Oceny.** Karta App Store ma 0 ocen. Prośba o ocenę w aplikacji po udanym momencie (np. po eksporcie PDF listy cięć), nie na starcie, podniesie konwersję bardziej niż kolejne słowa kluczowe. To zmiana w kodzie — osobne zadanie.
6. **Po 4–6 tygodniach:** sprawdź pozycje na słowa z tabeli, podmień 2–3 najsłabsze słowa w Keywords; A/B zrzutów przez Product Page Optimization (Apple) i eksperymenty na stronie sklepu (Google). Zmieniaj jedną rzecz naraz.
