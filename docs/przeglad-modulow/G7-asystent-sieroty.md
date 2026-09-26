# G7 — Asystent (tekst/głos) i moduły-sieroty

Przegląd: 2026-09-26, gałąź `fix/audyt-2026-08-29`. Kod tylko odczytywany, nic w nim nie zmieniałem.
Na czym opieram wnioski:
- `flutter test --no-pub test/assistant` → **129/129 zielonych**.
- Własne sondy uruchomione z katalogu tymczasowego (poza repo): skrypt Dart z parserem (33 „brudne” polecenia mówione), test silnika `AssistantEngine` (offline oraz z podstawionym serwerem) i test bazy dla tandemu (prawdziwy SQLite w pamięci, bez atrap).
- Czytanie kodu: `lib/assistant/*`, `lib/screens/ai_chat_screen.dart`, `lib/services/ai_chat_service.dart`, `backend/src/routes/fitterAi.js`, `backend/src/services/fitterIntent.js`, `backend/src/services/fitterAi.js`, `backend/test/intent.test.js`, moduły `welder_tandem`, `welder_pipe`, `new_cut_list_project_screen.dart`, `lib/data/app_database.dart`, `lib/database/db.dart`.

---

## ai-chat — Asystent tekstowy i głosowy („Wykonaj” / „Odpowiedz”)

- **Cel i dla kogo:** spawacz albo monter z brudnymi rękami, w rękawicach i w hałasie. Tryb „Wykonaj” ma zapisać parametr spawania do „Parametry — rury → Moje” albo otworzyć narzędzie z głosu lub krótkiego tekstu. Tryb „Odpowiedz” to pytania branżowe (model na serwerze, RAG nad `piping_knowledge.md`), a bez sieci odpowiada pomoc offline.
- **Co zawiera (funkcje, wejście, pliki):**
  - `assistant_parser.dart` — deterministyczny parser PL/EN. Liczby słownie, kody procesów 141/135/111, gatunki 316L/1.4404, DN→OD, pozycje ISO/ASME, gazy i złącza.
  - `assistant_validator.dart` — biała lista intencji V1 (`save_weld_parameter`, `open_tool`), typy, słowniki, zakresy (prąd 5–500 A, ścianka 0,3–50 mm, przepływ 1–40 l/min…), spójność (MIG/MMA zawsze ze spoiwem). Zadaje jedno pytanie o brakujące pole.
  - `assistant_engine.dart` — najpierw parser lokalny. `POST /ai/intent` idzie tylko po zgodzie i tylko gdy parser nie dał rady. Każdy wynik przechodzi przez ten sam walidator.
  - `assistant_intent_client.dart` — HTTP i mapowanie kodów 401/402/429/503/404.
  - `speech_io.dart` — `speech_to_text` (tryb dyktowania, `pauseFor` 5 s, `listenFor` 45 s) i `flutter_tts`.
  - `assistant_history.dart` — lokalna historia zapisów (SharedPreferences, maks. 100) i przełącznik czytania na głos.
  - `ai_chat_screen.dart` — pole polecenia, mikrofon 72 dp, „Dalej” 72 dp, strona podsumowania „Sprawdź i zapisz” (przyciski 64 dp), SnackBar „Cofnij” (8 s), strona historii, czat „Odpowiedz”.
  - Backend: `/intent` z wyjściem wymuszonym schematem JSON i walidacją zod oraz `/chat` z RAG BM25, limitami i budżetem.
- **Stan:** działa, ale ma błędy. Bezpieczeństwo zapisu jest dobre. Rozpoznawanie „brudnej” mowy wypada słabo, a kontrakt klient ↔ serwer jest rozjechany.

- **Bezpieczeństwo — czy model może cokolwiek zapisać bez potwierdzenia? Nie.**
  - Silnik zwraca tylko `AssistantCheck`.
  - Jedyny zapis to `_dao.insert` w `_save` (`ai_chat_screen.dart:419-436`). Wywołuje go wyłącznie `confirmed == true` z `_SaveSummaryPage`, czyli jawne „Zapisz” (`ai_chat_screen.dart:348-360`, `1196`).
  - Model nie dostaje SQL, kluczy ani identyfikatorów. Pola spoza listy są odrzucane dwa razy: przez zod na serwerze (`fitterIntent.js:141-178`) i przez walidator w aplikacji (`assistant_validator.dart:66-88`).
  - `open_tool` z serwera tylko nawiguje i to wyłącznie do narzędzi z rejestru. To jest OK.
  - Prompt injection: tekst użytkownika jest owinięty w `<polecenie>`, a nawiasy `<>` są zamieniane na inne znaki (`fitterIntent.js:182`). Wolny tekst modelu (pole `question`) nie trafia do klienta, bo pytania pochodzą z szablonu.
  - **Luka względem spec §6 pkt 7:** zapis nie trafia do żadnej kolejki synchronizacji, bo `WeldParamDao.insert` robi goły INSERT. Zgodne z obecnym stanem aplikacji, ale spec tego wymaga.

- **Sonda parsera — 33 „brudne” polecenia mówione.** Najważniejsze wyniki poniżej. ✅ = poprawnie, ⚠️ = dopyta (strata czasu, ale bez szkody), ❌ = źle.

  | Polecenie (jak z rozpoznawania mowy) | Wynik parsera / silnika | Ocena |
  |---|---|---|
  | „zapisz nierdzewka **dwójka** tig bez drutu sześćdziesiąt **ampów**” | brak ścianki i prądu | ⚠️ „dwójka” (ścianka 2 mm) i „ampów” nieznane |
  | „zapisz tig **na setkę** nierdzewka ścianka 2 mm bez drutu” | brak prądu | ⚠️ żargon „na setkę” = 100 A |
  | „…ścianka **dwa sześćdziesiąt** amper” (także z przecinkiem) | **prąd = 62 A**, ścianki brak | ❌ **cicha zła wartość** (sklejenie liczb) |
  | „…2 mm 60 A **rura 2 cale**” | **odmowa całego polecenia** (średnica 2 mm poza zakresem) | ❌ cale traktowane jak mm |
  | „…ścianka **3/4 cala** 60 A” | **gotowe do zapisu: ścianka 3,0 mm** | ❌ **cicha zła wartość** |
  | „…60 amperow **pozycja pe ef**” (tak STT zapisuje „PF”) | **pozycja PE (pułapowa)** | ❌ cicha zła wartość (widoczna w podsumowaniu) |
  | „…60 A **formowanie 5 litrów** argon 8 litrów” | **przepływ = 5** (formowanie wzięte jako gaz na palnik) | ❌ |
  | „zapisz **tik** bez drutu nierdzewka 2 mm 60 A” | brak procesu | ⚠️ STT myli TIG z „tik” |
  | „zapisz **sześćdziesiąt ampów** tig…” / „**sto dziesięć ampów**” | prąd pominięty | ⚠️ |
  | „…2 mm 60 A **5 G**” (ze spacją) | pozycja pominięta | ⚠️ |
  | „**jaki prąd** na TIG nierdzewka 2 mm” (pytanie) | intencja **zapis**, pyta „z drutem czy bez?” | ❌ pytanie potraktowane jak zapis |
  | „**dopisz spoinę** numer 12 do dziennika” | intencja **zapis parametru**, pyta o materiał | ❌ zła intencja |
  | „zapisz parametry do projektu” | zapis parametru, pyta o materiał | ❌ |
  | „policz cut 1200 minus dwa kolana” | nieznane | ⚠️ brak intencji |
  | „zapisz eee tig **no** bez drutu nierdzewka no dwa milimetry i sześćdziesiąt amperów” | kompletne | ✅ |
  | „zapisz TIG z drutem kwasówka ścianka 2,77 90 ampy” | kompletne | ✅ |
  | „zapisz MAG S355 ścianka 10 180 A” | kompletne, spoiwo = tak | ✅ |
  | „…2 mm 60 A 316 dn 50” | średnica 60,3 | ✅ |
  | „zapisz TIG nierdzewka bez drutu 1 i pół milimetra 45 A” | ścianka 1,5 | ✅ |
  | „…prąd **sześćset**” | odmowa (poza zakresem) | ✅ walidator łapie; ❌ cały kontekst ginie (niżej) |
  | „zapisz TIG bez drutu **czarna nierdzewka**…” | materiał pusty (sprzeczność) | ✅ dopyta |
  | „save tig stainless **two mil** wall sixty amps no filler” | brak ścianki | ⚠️ „mil” nieznane |
  | odpowiedź na pytanie o prąd: „na setkę” / o ściankę: „dwójka” | puste | ⚠️ pytanie wraca w kółko |

- **Błędy potwierdzone (plik:linia):**
  1. **Kontrakt klient ↔ serwer rozjechany — model zwraca wartości, które walidator w aplikacji odrzuca.**
     - Prompt serwera każe modelowi zwracać gaz jako tekst („Ar”, „Ar 99.996”, „Ar+2%CO2”) i złącze jako tekst („BW”, „doczołowe”, „SW”) (`backend/src/services/fitterIntent.js:82-85`). Zod przepuszcza dowolny krótki tekst (`fitterIntent.js:106-110`), a backendowy test wręcz tego oczekuje (`backend/test/intent.test.js:61-68`).
     - Aplikacja przyjmuje tylko kody `AR/M21/CO2/…` i `BUTT/FILLET/SOCKET/BRANCH/OTHER` (`lib/assistant/assistant_intents.dart:58-73`, `assistant_validator.dart:107-110`).
     - Sonda: wynik serwera z `gas:'Ar', joint:'BW'` został odrzucony w całości (`remoteRejected=notAllowed`), a dla polecenia nierozpoznanego lokalnie użytkownik zobaczył „Nieznana wartość (gaz). Nic nie zapisano”.
     - Pozycja: serwer przepuszcza dowolny tekst do 10 znaków, aplikacja ma słownik. Przepływ: serwer 0–60, aplikacja 1–40 (`fitterIntent.js:108` vs `assistant_intents.dart:100`).
     - Skutek: pomoc serwera psuje się dokładnie wtedy, gdy spawacz wspomni gaz albo złącze.
  2. **Sklejanie kolejnych liczb słownie.** „ścianka dwa sześćdziesiąt amper” daje 62 A (`assistant_parser.dart:274-298`: `_readNumberWords` sumuje „dwa” i „sześćdziesiąt”). 62 A mieści się w zakresie, więc przechodzi walidację. Użytkownik musi to wyłapać w podsumowaniu.
  3. **Ułamki cali i jednostka „cale” bez obsługi.**
     - „/” jest zamieniane na spację (`assistant_parser.dart:98-108`), więc „3/4 cala” daje ściankę 3,0 mm (gotowe do zapisu).
     - „rura 2 cale”: „cale” nie jest jednostką, słowo-klucz „rura” zamienia 2 w `diameter_mm` (`assistant_parser.dart:479-483`), a walidator odrzuca całe polecenie.
  4. **Pozycja przeliterowana przez STT.** „pozycja pe ef” daje PE, bo regex `p[a-hj]` łapie „pe” (`assistant_parser.dart:589-590`).
  5. **Formowanie brane jako przepływ na palnik.** `putIfAbsent('flow_lpm')` bierze pierwszą liczbę z litrami (`assistant_parser.dart:423-425`), bez rozróżnienia palnik/formowanie. Pole formowania nie istnieje w V1.
  6. **Pytania traktowane jak zapis.** `looksLikeParam` = materiał/proces + prąd/ścianka, bez czasownika (`assistant_parser.dart:36-41`). „Jaki prąd na TIG nierdzewka 2 mm” zamienia się w zapis i dopytywanie.
  7. **Zbyt szeroki czasownik zapisu.** „dodaj/dopisz/add/log/record” (`assistant_parser.dart:631-632`) kieruje każde „dopisz spoinę…” do `save_weld_parameter`.
  8. **Brakujące formy żargonu i STT:** „ampów” / „amp.” (`_isAmpUnit`, `assistant_parser.dart:302-307`, brak `ampow`), „dwójka/trójka/jedynka”, „setka/na setkę”, „tik/tig/cik”, „mil”, „5 G” ze spacją.
  9. **Odmowa w trakcie dopytywania gubi cały kontekst.** Odpowiedź „sześćset” na pytanie o prąd daje `AssistantRejected`, a ekran woła `_resetAct(clearText:false)`, które czyści `_carried` i `_pendingIntent` (`ai_chat_screen.dart:395-404`, `284-295`). W polu zostaje samo „sześćset” i trzeba dyktować wszystko od nowa. „Popraw” w podsumowaniu przywraca `_commandSoFar`, odmowa już nie.
  10. **Tryb „Odpowiedz” offline zablokowany zgodą na serwer.** `_send` najpierw woła `ensureServerConsent` (`ai_chat_screen.dart:609-611`). Kto odmówi zgody albo jest bez sieci i jeszcze jej nie dał, nie dostanie nawet lokalnej pomocy (`offlineReply` jest czysto lokalne, `ai_chat_service.dart:206-229`). Z kolei z zgodą, ale bez zasięgu, czeka do 25 s na timeout (`ai_chat_service.dart:145`), bo nie sprawdza łączności.
  11. **Długa rozmowa po cichu przechodzi w tryb offline.** Klient wysyła całą historię wraz z powitaniem i bieżącym pytaniem (`ai_chat_screen.dart:614`, `622-624`; `ai_chat_service.dart:134-139`). Serwer przyjmuje `history.max(20)` (`backend/src/routes/fitterAi.js:29-32`). Od 11. pytania przychodzi 400, klient mapuje to na `offlineReply`, a użytkownik dostaje „pomoc offline” mimo działającej sieci.
     - Przy okazji: bieżące pytanie trafia do modelu dwa razy (w historii i jako `message`, `fitterAi.js:268-274`).
     - W historii lądują też komunikaty offline i limitów.
     - Historia zaczyna się od wiadomości asystenta (powitanie). Czy API to przyjmie, trzeba sprawdzić, ale okno `slice(-6)` i tak to maskuje po 3 wymianach.
  12. **„Cofnij” bez obsługi błędu.** `deleteById` bez try/catch, a `markUndone` wykonuje się niezależnie od wyniku (`ai_chat_screen.dart:463-468`).
- **Problemy UX w terenie:**
  - Mikrofon: duży (72 dp), stan nasłuchu i stop są widoczne, transkrypcja zostaje. Dobrze. W hałasie (szlifierka, agregat):
    - `pauseFor` 5 s nie wykrywa ciszy, więc nasłuch trwa do 45 s i łapie śmieci;
    - każdy błąd rozpoznawania daje ten sam komunikat „przerwane” (`ai_chat_screen.dart:265-271`), bez wskazówki typu „za głośno — osłoń mikrofon / wpisz”;
    - brak trybu „przytrzymaj i mów” (push-to-talk), który w hałasie jest pewniejszy;
    - brak `onDevice` (rozpoznawanie offline), a bez zasięgu Google STT potrafi odmówić.
  - Ryzyko (niepotwierdzone testem): wynik końcowy STT, który przyjdzie już po „Dalej”, może nadpisać pole odpowiedzi (`onResult` nie sprawdza, czy nasłuch jest nadal aktywny, `ai_chat_screen.dart:255-264`).
  - Podsumowanie da się tylko zatwierdzić albo „Popraw” (powrót do tekstu). W rękawicy nie ma jak poprawić jednej wartości, np. zmienić 62 na 60 A. Brakuje edycji pola w miejscu (np. ±5 A, wybór pozycji z listy).
  - „Cofnij” żyje 8 s tylko w SnackBarze. W historii operacji nie ma cofnięcia, nie da się też przejść do rekordu.
  - Historia rozmowy „Odpowiedz” nie jest zapisywana — znika po wyjściu z ekranu.
- **Brakujące funkcje:**
  - intencja zapytania o własne zapisy offline („jakie mam parametry na nierdzewkę 2 mm”) — dziś to pytanie jest błędnie brane za zapis;
  - dopisanie spoiny do dziennika głosem;
  - „policz CUT” (tylko odczyt, jeden silnik CUT);
  - „jak ostatnio, ale 65 A”;
  - pole gazu formującego i przepływu formowania;
  - konwersja cali (ułamki: 1/2, 3/4, 1 1/4);
  - normalizacja STT („tik”→TIG, „pe ef”→PF);
  - kolejka synchronizacji zapisów.
- **Testy: co pokryte, czego brak.**
  - Pokryte: tabela ok. 39 zdań PL i 13 EN, liczby słownie, odpowiedzi na jedno pole, walidator (typy, zakresy, sprzeczności, wersjonowanie), klient HTTP (kody, zniekształcony JSON, łączenie wyników), przepływ na ekranie (bez „Zapisz” nic się nie zapisuje, jedno pytanie, 5000 A, mikrofon, brak zgody, TTS tylko po włączeniu, `open_tool`).
  - Brak:
    - zestawu „brudnej mowy” i poleceń adwersaryjnych (sklejone liczby, cale, żargon, pytania wyglądające jak zapis);
    - **testu kontraktu backend ↔ aplikacja** (backend testuje `'Ar 99.996'`, aplikacja `'AR'` — oba zestawy zielone, integracja zepsuta);
    - testu odmowy w trakcie dopytywania;
    - testu limitu historii czatu i trybu offline bez zgody.
- **Propozycje:**
  - [P1][S] **Wyrównać kontrakt V1:** serwer ma zwracać kody z tych samych słowników co aplikacja (enum w schemacie JSON dla `gas/joint/position`, przepływ 1–40), a aplikacja przy odrzuceniu pojedynczego pola ma je pominąć zamiast całej odpowiedzi. Dodać wspólny plik z kontraktem (JSON), czytany w testach obu stron.
  - [P1][S] **Parser liczb:** nie sklejać dwóch pełnych liczb słownie („dwa sześćdziesiąt” to dwie liczby). Suma tylko przy rosnącej randze (dziesiątki + jedności, setki + reszta).
  - [P1][S] Obsłużyć „cal/cale/cala/inch/"” i ułamki `a/b`; do tego czasu **„/” i cale mają dawać odmowę albo pytanie, nie 3,0 mm**.
  - [P1][S] Odmowa w trakcie dopytywania ma zachować `_carried` i ponowić to samo pytanie z komunikatem o zakresie.
  - [P1][S] „Odpowiedz” offline bez bramki zgody; przy braku łączności od razu pokazać pomoc offline. Klient ma przycinać historię do ostatnich 6 wiadomości bez powitania, bieżącego pytania i komunikatów systemowych.
  - [P2][M] Słownik żargonu i STT: „ampów”, „dwójka/trójka”→ścianka tylko przy kontekście ścianki, „na setkę”→100 A, „tik/tig/cik”→TIG, „pe ef”→PF, „5 G”→5G, „mil”→mm, „formowanie/formujący/purge” jako osobne pole (V2).
  - [P2][M] Rozróżnić pytanie od polecenia: słowa pytające („jaki, ile, czy, what, how”) bez czasownika zapisu dają nową intencję `query_my_params` (odczyt lokalny) zamiast zapisu.
  - [P2][M] Edycja pól w miejscu na stronie podsumowania (duże przyciski ±, listy wyboru) i „Cofnij” w historii operacji.
  - [P2][S] Hałas: mapować kody błędów STT na konkretne podpowiedzi, dodać opcjonalny tryb „przytrzymaj i mów” i `onDevice`, gdy jest dostępny.
  - [P2][M] Nowe intencje (V2, każda z podsumowaniem i „Zapisz”):
    - `add_weld_log_entry` — dziennik spoin: numer spoiny, ISO/linia, WPS, stempel spawacza, proces, data; brakujące pola dopytuje po jednym;
    - `calc_cut` — tylko odczyt: wynik z tego samego silnika CUT, z formułą i odjęciami, zapis do projektu dopiero po potwierdzeniu;
    - `query_my_params` — wyszukiwanie w `weld_params` i tandemach po materiale, ściance i procesie, czysto offline.
  - [P3][S] „Jak ostatnio, ale …” (kopia ostatniego zapisu z nadpisaniem jednego pola); zapis historii czatu „Odpowiedz”; kolejka synchronizacji dla zapisów asystenta.

---

## tandem-menu — Tandem TIG: menu (Poziom/Pion)

- **Cel i dla kogo:** spawacze zbiorników ze stali nierdzewnej, spawanie dwustronne w dwie osoby (palnik wewnętrzny i zewnętrzny). Menu prowadzi do kalkulatora, biblioteki i „moich” parametrów dla pozycji HORIZONTAL albo VERTICAL.
- **Co zawiera:** `lib/modules/welder_tandem/ui/tandem_menu_screen.dart` — siatka 3 kafli, parametr `position` z konstruktora (nie da się go wybrać na ekranie).
- **Stan:** ukryty (brak wejścia w `tool_registry.dart:52-55`, świadomie). Samo menu się renderuje, ale wszystkie trzy ekrany docelowe są niesprawne (poniżej).
- **Błędy potwierdzone:** menu samo w sobie nie ma błędów. Pozycję trzeba podać z zewnątrz, bo nie ma przełącznika Poziom/Pion.
- **Problemy UX w terenie:** kafle są OK (duże). Brak informacji, czym to się różni od „Parametry — zbiorniki”.
- **Brakujące funkcje:** wybór pozycji w menu.
- **Testy:** `test/audit/module_smoke_test.dart` — sam render przy skali tekstu 1,3.
- **Propozycje:** [P2][S] **Zostawić ukryte i docelowo usunąć** po przeniesieniu wartościowych elementów (tempo, zapis estymaty jako „moje”) do żywego modułu `welder_tanks` („Parametry — zbiorniki” → Tandem). Moduł dubluje `WelderTanksScreen`, który ma pełniejszy model: materiał, typ złącza, land, szczelinę i tabelę `tandem_tig_params` w głównej bazie. Dwa „tandemy” w menu tylko myliłyby ludzi.

## tandem-calculator — Tandem TIG: kalkulator prądów wew./zew.

- **Cel i dla kogo:** dobór prądu dla palnika wewnętrznego (bez drutu) i zewnętrznego (z drutem) z grubości ścianek t1/t2 i tempa. Źródło wyniku: najpierw wpis zatwierdzony, potem „moje”, na końcu estymata.
- **Co zawiera:** `tandem_calculator_screen.dart`, `tandem_calc.dart`, DAO `lib/database/tandem_amp_param_dao.dart`, model `lib/models/tandem_amp_param.dart`. Wejście: t1, t2 [mm] i tempo. Wynik: prąd wew./zew., status APPROVED/MY/ESTIMATE i przycisk „Zapisz do moich parametrów” przy estymacie.
- **Stan:** **nie działa** (błąd bazy), a przy tym jest ukryty.
- **Błędy potwierdzone (plik:linia):**
  1. **Zła baza — tabeli nie ma.** `TandemAmpParamDao` importuje `db.dart` i otwiera `cutlist.db` (`tandem_amp_param_dao.dart:3,7`). Tabela `tandem_amp_params` istnieje tylko w drugiej bazie `cut_list_app.db` (`lib/data/app_database.dart:164-180`). Sonda na prawdziwym SQLite: `cutlist.db` ma tylko `tandem_tig_params`, a `calculate()` rzuca `no such table: tandem_amp_params`.
  2. **Nawet we właściwej bazie zapis się nie uda.** Kolumna `variant TEXT NOT NULL` (`app_database.dart:174`), a `TandemAmpParam.toRow()` jej nie zawiera (`lib/models/tandem_amp_param.dart`, `toRow`). Sonda: `NOT NULL constraint failed: variant`.
  3. **Błąd `FutureBuilder` ukrywa awarię.** Przy błędzie `snap.data == null`, więc ekran pokazuje „Liczenie...” w nieskończoność (`tandem_calculator_screen.dart:101-114`). Future jest tworzony w `build()`, więc każdy znak w polu uruchamia nowe zapytanie.
  4. **Dane startowe sprzeczne i z duplikatami** (`app_database.dart:186-221`):
     - dla 3/3 NORMAL zatwierdzone są trzy różne pary (72/140, 72/170, 80/150);
     - dla 4/4 cztery (100/190, 170/180, 170/170, 180/190);
     - dla 5/6 dwie (75/140 i 107/210);
     - wiersze `variant='TI'` są mieszane z NORMAL, bo DAO ignoruje `variant`;
     - Pion ma identyczne liczby co Poziom (kopia).
     - `getExact` z `LIMIT 1` bez `ORDER BY` zwraca przypadkowy wiersz, a interpolacja (`tandem_calc.dart:45-51`) bierze przypadkowego sąsiada.
  5. **Estymata „pierze się” na „moje”.** „Zapisz do moich” zapisuje estymatę z `approved=false` (`tandem_calculator_screen.dart:151-172`), a przy następnym liczeniu wraca ze statusem **MY — „Z moich parametrów”** (`tandem_calc.dart:28-30`). Heurystyka `20+avg·20 / 40+avg·35` staje się wyglądającym na sprawdzony „moim” parametrem.
- **Problemy UX w terenie:** brak wyboru pozycji na ekranie; odznaka pokazuje surowe `APPROVED/MY/ESTIMATE`; brak wskazania, który palnik prowadzi i jakie jest przesunięcie; brak materiału (tylko SS domyślnie), złącza, landu i szczeliny, które ma żywy moduł.
- **Brakujące funkcje:** materiał, typ złącza, land, szczelina, gaz, przepływ, wolfram, drut; ostrzeżenie „estymata — sprawdź na próbce / WPS”.
- **Testy:** `test/audit/welder_calculations_audit_test.dart:39-125` testuje logikę na **podstawionym DAO** (`_ExactTandemDao`). Test jest zielony, ale ukrywa brak tabeli. `module_smoke_test.dart` sprawdza sam render. Brak testu z prawdziwą bazą.
- **Otwarte pytanie „inside/outside = lead/trail?” — analiza:**
  - *Co mówi kod:*
    - w obu modułach inside/outside to **strona ścianki zbiornika**, nie kolejność: `inside_amps -- wewnętrzny (bez drutu)`, `outside_amps -- zewnętrzny (z drutem)` (`app_database.dart:171-172`, `tandem_amp_param.dart`);
    - żywy moduł: „Tandem TIG (SS) - 2 osoby” i „Zewn. = palnik zewnętrzny z drutem (większy prąd). Wewn. = palnik wewnętrzny bez drutu (mniejszy)” (`lib/screens/welder_tanks_screen.dart:12`, `117`, `563-571`);
    - wejście to dwie grubości t1/t2 (zmiana grubości blach na styku carg, które ku górze są cieńsze) oraz złącze, land i szczelina — to parametry przetopu przez całą grubość z dwóch stron, nie parametry dwóch łuków jeden za drugim;
    - wartości (zewnętrzny ≈ 2× wewnętrzny) pasują do schematu „strona bez drutu przetapia i formuje grań, strona z drutem wypełnia i robi lico”.
  - *Praktyka:*
    - w spawaniu dwustronnym jednoczesnym (dwóch spawaczy, palniki naprzeciw siebie po obu stronach blachy) palniki stoją **współosiowo**, ewentualnie jeden kilka mm z przodu;
    - „lead/trail” to pojęcie z tandemu **jednostronnego** (dwa łuki w linii po tej samej stronie, zwykle zmechanizowane), gdzie lead zwykle daje przetop, a trail wypełnia albo wygładza;
    - utożsamienie inside=lead i outside=trail jest więc błędem kategorii: to inna konfiguracja z innymi prądami;
    - w praktyce dwustronnej często ustala się, kto „prowadzi” (np. wewnętrzny, bez drutu, lekko z przodu, żeby otworzyć jeziorko), ale to **dodatkowa informacja o przesunięciu**, a nie zamiana nazw pól.
  - *Anomalie w danych:* wiersze 4/4 mm 170/180, 170/170, 180/190 A (prawie równe prądy) i `variant='TI'` nie pasują do schematu dwustronnego. Mogą pochodzić z innej techniki (np. jednostronny tandem albo inna grubość) — **trzeba je potwierdzić u źródła danych**, zanim cokolwiek zostanie podpięte.
  - *Rekomendacja:* **nie** zmieniać nazw na lead/trail. Pozostać przy „wewnętrzny (bez drutu)” i „zewnętrzny (z drutem)” jako stronie zbiornika. Jeśli potrzebny jest układ jednostronny, dodać osobne pole `arrangement` (`dwustronny` / `jednostronny_w_linii`) i dla dwustronnego opcjonalnie „kto prowadzi” oraz przesunięcie [mm]. Wpisy 4/4 170–180 A i TI zweryfikować z autorem danych.
- **Propozycje:**
  - [P1][S] Jeśli moduł ma zostać w repo: DAO na `lib/data/app_database.dart` (`AppDatabase.instance.db`) albo przeniesienie tabeli do `db.dart` z migracją; `variant` w modelu; test na prawdziwej bazie.
  - [P1][S] Estymata nigdy nie może zmieniać się w MY — osobny status `MY_ESTIMATE` albo zapis dopiero po ręcznej edycji.
  - [P2][M] **Scalić z `welder_tanks`** (dodać tam tempo i „zapisz jako moje”), oczyścić seed. **Nie podpinać** tego modułu w obecnej postaci.

## tandem-library — Tandem TIG: biblioteka zatwierdzonych

- **Cel i dla kogo:** podgląd zatwierdzonych par prądów dla pozycji, z filtrem tempa.
- **Co zawiera:** `tandem_library_screen.dart` — dropdown tempa i lista `t1/t2 mm • wew/zew A`.
- **Stan:** nie działa (ta sama zła baza). Błąd jest połknięty: `FutureBuilder` z błędem pokazuje „Brak rekordów w bibliotece dla tych filtrów.” (`tandem_library_screen.dart:51-60`).
- **Błędy potwierdzone:**
  - `tandem_amp_param_dao.dart:3,7` — brak tabeli, jak wyżej;
  - `t1Mm.toStringAsFixed(0)` pokazuje 2,5 mm jako „3” (`tandem_library_screen.dart:66`);
  - duplikaty i sprzeczności z danych startowych byłyby widoczne jako kilka różnych wyników dla tej samej grubości.
- **Problemy UX w terenie:** brak źródła i notatki przy wpisie; brak wyszukiwania; brak oznaczenia wariantu TI.
- **Brakujące funkcje:** źródło danych (kto, kiedy, WPS), wariant, eksport.
- **Testy:** brak (poza manifestem).
- **Propozycje:** [P2][S] Zostawić ukryte; zakładka „Zatwierdzone” w `welder_tanks` pełni tę funkcję.

## tandem-my-params — Tandem TIG: moje parametry

- **Cel i dla kogo:** własne pary prądów wew./zew. użytkownika (dodawanie, edycja, usuwanie).
- **Co zawiera:** `tandem_my_params_screen.dart` — lista, FAB „+”, dialog z t1, t2, A wew., A zew., tempem i notatką.
- **Stan:** nie działa.
- **Błędy potwierdzone:**
  - lista połyka błąd bazy i pokazuje „Brak moich parametrów” (`tandem_my_params_screen.dart:36-45`);
  - zapis `_dao.insert(p)` (`:194`) rzuca `no such table` bez try/catch — nieobsłużony wyjątek i brak komunikatu;
  - `toStringAsFixed(0)` na grubości (`:51`);
  - kontrolery w dialogu nie są zwalniane (`:107-112`);
  - brak górnych limitów: `vInt` przyjmuje np. 9999 A (`:120-124`).
- **Problemy UX w terenie:** dialog z 6 polami w rękawicach jest ciasny; brak kopiowania wpisu.
- **Brakujące funkcje:** materiał, złącze, źródło.
- **Testy:** brak.
- **Propozycje:** [P2][S] Zostawić ukryte; funkcję „moje” przenieść do `welder_tanks` (tabela `tandem_tig_params` ma już `approved`).

---

## welder-pipe-params-list — „Moje parametry – Welder (Rury)” (druga implementacja)

- **Cel i dla kogo:** lista własnych zestawów parametrów TIG na rury: materiał, OD×WT, A, metoda WTC/free hand, porcelanka, wolfram, otwory wylotowe, tempo, drut, formowanie.
- **Co zawiera:** `lib/modules/welder_pipe/ui/welder_pipe_params_list_screen.dart`, repozytorium `local_repo.dart` (baza `cut_list_app.db`, tabela `welder_pipe_params`), odświeżanie przeciągnięciem, usuwanie z potwierdzeniem.
- **Stan:** ukryty. Technicznie działa: tabela istnieje we właściwej bazie, migracja v3–v5 jest przetestowana.
- **Błędy potwierdzone:** brak twardych. Wyświetla surowe kody: `CARBON_STEEL`, `SS316L`, `NORMAL`, „AMP: 90.0” (`welder_pipe_params_list_screen.dart:136-148`).
- **Problemy UX w terenie:** tytuł „Welder (Rury)” po angielsku w polskiej wersji; długi podpis w jednej linii z „•”; brak filtra po materiale i grubości (repo to umie: `local_repo.dart:37-63`).
- **Brakujące funkcje:** wyszukiwanie; powiązanie z WPS; eksport.
- **Testy:** `test/audit/data_integrity_audit_test.dart` (migracja v3–v5, restart), `module_smoke_test.dart` (render). Brak testów CRUD na ekranie.
- **Propozycje:** [P1][M] **Nie podpinać — scalić.** To **dubel** zakładki „Parametry — rury → Moje” (`weld_params` w `cutlist.db`), do której pisze też asystent. Dwa różne magazyny „moich parametrów rur” w dwóch bazach oznaczają pewne rozjechanie danych. Plan:
  1. przenieść unikalne pola do `WeldParam`: metoda WTC/free hand (np. `nozzle_type`), średnica drutu (nowa kolumna), gaz formujący Ar/N₂ (nowa kolumna), przełącznik formowania dla CS;
  2. jednorazowa migracja istniejących wierszy `welder_pipe_params` do `weld_params`, z raportem;
  3. zostawić tabelę tylko do odczytu (kopia zapasowa `data_backup.dart` już ją obejmuje).

## welder-pipe-param-edit — dodawanie/edycja zestawu (druga implementacja)

- **Cel i dla kogo:** formularz zestawu parametrów rury z opcją „Dodaj do puli 100/100 (społeczność)”.
- **Co zawiera:** `welder_pipe_param_edit_screen.dart`, `community_sync_service.dart`, `param_signature.dart` (SHA-256 z normalizowanego payloadu), `device_id.dart`.
- **Stan:** ukryty. Zapis lokalny działa. **Funkcja społecznościowa to atrapa.**
- **Błędy potwierdzone (plik:linia):**
  1. **Fałszywa wysyłka.** `syncOutboxOnce()` oznacza wpisy jako `sent` bez żadnego żądania HTTP (`community_sync_service.dart:14-21`). Użytkownik widzi przełącznik „jeśli 100 osób doda identyczne — trafi do zatwierdzonych” (`welder_pipe_param_edit_screen.dart:457-462`), a nic nigdzie nie wychodzi.
  2. **Przełącznik udostępniania domyślnie włączony** (`_sendToCommunity = true`, `:50`). Jeśli wysyłka kiedyś zacznie działać, to będzie udostępnianie bez zgody (opt-out).
  3. **Dwie różne sygnatury dla tego samego zestawu.** Ekran liczy sygnaturę do kolejki z payloadu **bez** `outlet_holes_count` i `weld_tempo` (`:157-174`), a repozytorium liczy sygnaturę wiersza z `toCommunityPayload()` **z** tymi polami (`local_repo.dart:15-16`, `welder_pipe_param.dart`). Zasada „100 identycznych” nie ma szans się zgadzać.
  4. **Walidacja tylko „niepuste”.** Brak zakresów dla A, OD, WT, porcelanki, wolframu i przepływu (`:255`, `266`, `294`, `307`, `318`, `374-377`). Wartości 0 A czy 9999 mm przechodzą.
  5. **Surowy wyjątek w komunikacie** („Nie udało się zapisać: FormatException…”, `:210`).
  6. `DeviceIdProvider` (`device_id.dart`) jest martwym kodem — drugi, niezależny identyfikator urządzenia obok `PremiumService`.
- **Problemy UX w terenie:** długi formularz; nazwy „Walking the Cup / Free Hand”, „Nitrogen”, „AMP” niespolszczone; brak średnicy DN z listy.
- **Brakujące funkcje:** zakresy; wybór z tablicy DN; WPS; kopiowanie zestawu.
- **Testy:** `module_smoke_test.dart` (render i przycisk „Zapisz”). Brak testów zapisu, sygnatury i kolejki.
- **Propozycje:**
  - [P1][S] **Usunąć albo ukryć atrapę „puli 100/100”** (nie może udawać wysyłki).
  - [P1][M] Scalić formularz z „Parametry — rury → Moje” (patrz wyżej). **Nie podpinać** osobno.
  - Jeśli pula społecznościowa ma wrócić: [P2][L] prawdziwy endpoint `/api/fitter/...` na istniejącym backendzie Railway, zgoda opt-in, jedna funkcja sygnatury, deduplikacja po urządzeniu na serwerze.

## new-cut-list-project — „Nowy projekt” listy cięcia (stara wersja)

- **Cel i dla kogo:** monter zakłada projekt listy cięcia: nazwa, SS/CS, OD, t, długość sztangi, kerf.
- **Co zawiera:** `lib/screens/new_cut_list_project_screen.dart`, `ProjectDao`, szybka lista typowych OD (popup), po zapisie przejście do `SegmentBuilderScreen`.
- **Stan:** ukryty. Częściowo działa: projekt się zapisuje, ale dalszy przepływ jest zepsuty.
- **Błędy potwierdzone (plik:linia):**
  1. **Segment trafia donikąd.** Po zapisie `pushReplacement` do `SegmentBuilderScreen` bez identyfikatora projektu (`new_cut_list_project_screen.dart:117-133`). Kreator oddaje wynik `Navigator.pop(context, {...})` (`segment_builder_screen.dart:1113`) do trasy, która go nie odbiera, więc pierwszy zbudowany segment przepada. Żywy `NewProjectScreen` przechodzi do `FitterScreen(projectId:)` (`new_project_screen.dart:127-131`).
  2. **Kerf ograniczony do 1–2 mm** (`:291-297`), sprzecznie z pomocą w żywym module (plazma 2,0–3,5 mm, `new_project_screen.dart:187-188`).
  3. **Brak walidacji długości sztangi** — 0 albo wartość ujemna przechodzą (`:268-278`, `:72-73`).
  4. **Tylko SS/CS** (`:34`); brak gapu i identyfikacji (linia, ISO, rev, klient, spec), które ma żywy formularz.
  5. **Surowy wyjątek w komunikacie** (`:137`); `.then` bez obsługi błędu (`:117`).
- **Problemy UX w terenie:** podsumowanie usunięte; lista OD tylko w mm bez DN/NPS.
- **Brakujące funkcje:** wszystko, co ma `NewProjectScreen` (gap, identyfikacja, mapowanie błędów).
- **Testy:** `module_smoke_test.dart` (render i przycisk „UTWÓRZ PROJEKT”). Brak testu przepływu.
- **Propozycje:** [P2][S] **Zostawić ukryte i usunąć.** To starsza wersja `NewProjectScreen`. Jedyny unikalny element, szybka lista średnic, warto przenieść do żywego formularza jako przyciski DN z `kNpsTable` (DN/NPS/OD). Podpięcie w obecnej postaci wprowadziłoby utratę segmentów.

---

## Ryzyko drugiej bazy (`lib/data/app_database.dart`)

- W aplikacji są dwie bazy SQLite z klasą o **tej samej nazwie** `AppDatabase`:
  - `lib/database/db.dart` → `cutlist.db` (`getDatabasesPath()`), wersja ~17, z testami migracji;
  - `lib/data/app_database.dart` → `cut_list_app.db` (`getApplicationDocumentsDirectory()`), wersja 5.
- Pomyłka importu nie daje błędu kompilacji, tylko `no such table` w działaniu. Dokładnie to się stało w `tandem_amp_param_dao.dart:3` (potwierdzone sondą).
- Druga baza zawiera też tabele `projects` i `heat_numbers` (`app_database.dart:57-83`), zdublowane nazwami z główną bazą. Kod modułów ich nie używa, ale kopia zapasowa i przywracanie obejmują obie bazy (`data_backup.dart:1061-1082`), a więc i te puste dublety.
- Rekomendacja: [P2][M] docelowo jedna baza. Tabele `welder_pipe_params`, `community_outbox`, `app_kv` i `tandem_amp_params` przenieść do `db.dart` przez migrację (z testem w `test/database/migration_test.dart`), a `lib/data/app_database.dart` zostawić tylko jako źródło importu starych danych. Do tego czasu klasę przemianować (np. `ModuleDatabase`), żeby pomyłka importu była widoczna.

---

## Top 5 w grupie

1. **[P1] Kontrakt `/ai/intent` rozjechany z walidatorem w aplikacji.** Serwer uczy model zwracać `gas:"Ar"` i `joint:"BW"`, a aplikacja wymaga `AR` i `BUTT`, więc cała pomoc serwera jest odrzucana, gdy spawacz wspomni gaz albo złącze (`fitterIntent.js:82-85`, `106-110` vs `assistant_intents.dart:58-73`). Potrzebne wspólne enumy i wspólny test kontraktu.
2. **[P1] Cicho błędne liczby w parserze mowy.** „dwa sześćdziesiąt” daje 62 A, „3/4 cala” daje ściankę 3 mm, „pozycja pe ef” daje PE, „formowanie 5 l” staje się przepływem na palnik (`assistant_parser.dart:274-298`, `98-108`, `589`, `423`). Podsumowanie chroni przed zapisem, ale spawacz w terenie tego nie wyłapie. Trzeba poprawić parser i dodać zestaw testów „brudnej mowy”.
3. **[P1] Moduł tandem pisze do złej bazy.** `TandemAmpParamDao` otwiera `cutlist.db`, a tabela jest w `cut_list_app.db`, do tego model nie ma `variant NOT NULL`. Kalkulator wisi na „Liczenie...”, lista udaje pustą, a zapis rzuca wyjątek. Test audytu jest zielony tylko dzięki podstawionemu DAO. Nie podpinać; scalić z `welder_tanks`. Pytania lead/trail nie rozstrzygać zmianą nazw (inside/outside to strona zbiornika).
4. **[P1] UX asystenta w terenie:**
   - odmowa podczas dopytywania kasuje całe polecenie (`ai_chat_screen.dart:395-404`);
   - pytania („jaki prąd na…”) i „dopisz spoinę” są brane za zapis parametru;
   - „Odpowiedz” offline jest zablokowane zgodą na serwer;
   - po 10 pytaniach czat po cichu przechodzi w tryb offline (historia > 20 → 400).
5. **[P1] `welder_pipe` to dubel „Parametry — rury → Moje” z fałszywą wysyłką społecznościową** (oznacza wpisy jako wysłane bez HTTP, przełącznik domyślnie włączony, dwie różne sygnatury). Scalić pola z `weld_params`, usunąć atrapę. `new-cut-list-project` usunąć, bo gubi pierwszy segment; szybką listę średnic przenieść do żywego formularza.
