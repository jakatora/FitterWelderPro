# Asystent głosowy sterujący modułami — projekt

Data: 2026-10-19. Gałąź: `feat/wyceny-i-moduly` (po wydaniu 0.4.0+18).
Poprzedni projekt asystenta: `2026-08-30-profesjonalna-platforma-spolecznosciowa-i-asystent-design.md` (§2 zasady nienaruszalne i §6 obowiązują dalej).

## 1. Problem

Aplikacja ma ~110 ekranów i 75 narzędzi. Właściciel po uruchomieniu wersji 0.4.0: „chaos — bardzo dużo wszystkiego”.
Spawacz w rękawicach, na budowie, nie będzie szukał w menu kalkulatora, w którym „DN40” zamienia się na milimetry.
Chce zapytać i od razu zobaczyć odpowiedź — tak, jak zapytałby majstra.

## 2. Cel (kryteria odbioru)

1. **Jedno wejście głosowe na każdym ekranie.** Przycisk mikrofonu jest zawsze pod kciukiem, a na ekranie głównym jest pasek „Powiedz, czego potrzebujesz”.
2. **Odpowiedź z wiedzy modułów, na żywo.** „Jaka jest średnica rury DN40?” → „DN40 to 48,3 mm średnicy zewnętrznej (ISO / ASME). W szeregu EN 3: 44,5 mm.”
   - Odpowiedź jest pokazana i przeczytana.
   - Moduł „DN ↔ mm” otwiera się w tle z podświetlonym wierszem.
   - Liczby pochodzą WYŁĄCZNIE z kodu domeny aplikacji, nigdy z modelu językowego.
3. **Sterowanie każdym modułem.**
   - Każde z 75 narzędzi da się otworzyć głosem, a asystent wyjaśni, do czego służy (poziom A).
   - Kalkulatory i tabele są liczone i wypełniane na żywo (poziom B).
   - Moduły z protokołami (np. prace pożarowe) wypełniane są tylko po potwierdzeniu (poziom C).
4. **Rysowanie na żywo.** „Narysuj rura kolanko rura” rysuje w Zeszycie ISO krok po kroku i można to cofnąć.
   - Przyjęte założenia (kierunek kolana, brak długości) asystent mówi głośno.
   - „W górę” albo „cofnij” poprawiają rysunek.
5. **Feedback dla właściciela.** Asystent zbiera, co nie działało, na co użytkownik narzekał i czego asystent nie zrozumiał. Wysyła to po zgodzie użytkownika. Właściciel dostaje zestawienie pogrupowane po modułach.
6. **Działa bez internetu i bez kosztów AI.** Rozpoznawanie intencji i odpowiedzi są lokalne i deterministyczne. Uwaga: samo rozpoznawanie MOWY robi system (Google/Apple) — na części telefonów wymaga sieci; bez sieci zostaje wpisanie tekstu.
   - Model językowy na serwerze jest wyłącznie opcjonalnym dodatkiem na przyszłość, za flagą wyłączoną domyślnie.
   - Powód: kredyty Anthropic są wspólne z PrzetargAI, a decyzja o osobnym limicie należy do właściciela.

### 2.1 Mierniki sukcesu (wersja v2 — po przeglądzie)

- Rozpoznanie zamiaru za pierwszym razem: ≥ 85 % zaplanowanych fraz w ciszy, ≥ 60 % przy hałasie ~85 dB (szlifierka).
- **Zero błędnych liczb.** Każda błędna liczba w odpowiedzi blokuje wydanie.
- Mediana od końca mowy do karty z wynikiem ≤ 1,5 s.
- Odsetek „nie rozumiem” < 20 % (liczniki lokalne; za zgodą wysyłane tylko jako zagregowane liczby).
- Top-10 nierozpoznanych fraz z każdego zestawienia trafia do listy nowych umiejętności.

### 2.2 Uczciwy zakres „każdy moduł” w tej iteracji

Poziom A (otwórz, wyjaśnij, „co tu zrobisz”) obejmuje wszystkie narzędzia. Poziom B (liczy i wypełnia na żywo) obejmuje ok. 21 z 76. Na pytanie liczbowe do modułu poziomu A asystent odpowiada: „Otwieram moduł X — liczenie głosem w tym module jeszcze nie działa”, a nie zgaduje.

## 3. Zasady nienaruszalne (dopisane do §2 z 2026-08-30)

1. Asystent nie liczy sam — wywołuje funkcje domeny. Każda liczba w odpowiedzi ma źródło w kodzie modułu, a przy normach podaje normę.
2. Niejednoznaczność → pytanie, nigdy zgadywanie. Przykłady:
   - „DN40” bez kontekstu → wartość główna i druga seria;
   - „ścianka dwa sześćdziesiąt” → dopytanie.
3. Asystent nigdy nie odhacza punktów list bezpieczeństwa i nie zatwierdza gotowości. Dotyczy to prac pożarowych, przestrzeni zamkniętej, zawiesi, szlifierek i dymów. Pomiary i pola może wpisać tylko po podsumowaniu i potwierdzeniu.
4. Zmiana danych: podsumowanie, potwierdzenie (dotknięcie albo „tak, zapisz”, gdy podsumowanie jest na ekranie), zapis i „Cofnij”.
5. Mikrofon tylko po naciśnięciu. Nic nie nasłuchuje w tle.
6. Nic nie wychodzi z telefonu bez zgody. Feedback ma osobną zgodę, domyślnie wyłączoną. Zgłoszenie jawne zawsze pokazuje podgląd przed wysłaniem. Nagrań głosu nie wysyłamy nigdy.
7. Najpierw lokalnie. Polecenie rozpoznane przez umiejętność lokalną nigdy nie idzie na serwer (dziś silnik pyta serwer o nierozpoznane polecenia — kolejność trzeba zmienić).

## 4. Architektura

```
mikrofon/tekst ─► AssistantSession ─► AssistantBrain ─► Skill.match (wszystkie) ─► najlepszy ─► Skill.run
     ▲                 │  (stan, TTS)       │                                                  │
     │                 ▼                    ├─ pytanie w toku / follow-up (AssistantContext)    ├─ AnswerResult ─► karta + mowa
  nakładka         AssistantOverlay         ├─ intencje zapisu (stary parser + walidator)      ├─ ShowInModule ─► ToolBridge ─► strona
  pasek na Start   ekran AiChatScreen       ├─ otwórz / wyjaśnij moduł (rejestr)               ├─ AskResult ─► pytanie + chipy
                                            ├─ wiedza (Pomoc + słownik)                        └─ ConfirmResult ─► podsumowanie
                                            └─ nie rozumiem ─► sygnał feedbacku                       ─► zapis ─► Cofnij
```

### 4.1 Wypowiedź (`Utterance`)
- Normalizacja wspólna z parserem: zwijanie polskich znaków, liczby słownie na cyfry, żargon.
- Wyciąganie wielkości: DN, NPS w calach, mm/cm/m, stopnie, A/V, bar, kg/t, %.
- Odmiany i błędy rozpoznawania mowy: „de en 40”, „dn40”, „d n 40”, „kolanko/kolano/łuk”, „trójnik/trojnik”.
- Funkcje `parseSpokenNumber`, `_fold`, `_odForDn` i `_odForNps` stają się publiczne, w osobnych plikach. Stary parser z nich korzysta.

### 4.2 Umiejętność (`AssistantSkill`)
Jedna umiejętność = jedno zadanie użytkownika, np. „średnica zewnętrzna rury z DN/NPS”. Ma:
- `id`;
- `toolId` (narzędzie w rejestrze);
- przykłady PL/EN, służące jednocześnie jako dokumentacja, test i „co umiesz”;
- `match` (wynik 0–1 i sloty);
- `run` (wynik).

Umiejętności nie znają UI. Mówią tylko, co pokazać w module (`ShowInModule(toolId, pola)`).

### 4.3 Mózg (`AssistantBrain`)
Kolejność:
1. odpowiedź na pytanie w toku;
2. kontynuacja („a dla DN50?”, „a ścianka?”);
3. intencje zapisu ze starego parsera (parametr spawania, dziennik — ich przepływ zostaje bez zmian);
4. umiejętność z najwyższym wynikiem ≥ próg;
5. otwarcie lub wyjaśnienie modułu (`searchTools`);
6. wiedza (`searchHelp`, słownik);
7. „nie rozumiem” z trzema propozycjami i sygnałem feedbacku;
8. opcjonalnie serwer — flaga wyłączona.

Remis dwóch umiejętności z różnych modułów → pytanie „Chodzi o … czy …?”.

### 4.4 Most do modułów (`ToolBridge`, `ToolHandle`)
- Globalny `appNavigatorKey` w `MaterialApp` → otwieranie modułu z nakładki.
- Strona sterowalna implementuje `ToolHandle` (mixin `ToolHandleHost` rejestruje ją w `initState`).
- `apply(pola)` ustawia kontrolery i JAWNIE przelicza wynik. Programowa zmiana `controller.text` nie woła `onChanged`.
- `ToolBridge.whenReady(toolId)` czeka, aż strona skończy wczytywać ustawienia. Część stron nadpisuje pola w `_loadPrefs` po `initState`.

### 4.4a Polityka nawigacji (v2)

- **Narzędzie widoczne** (bieżąca trasa) → `apply` w miejscu.
- **Na wierzchu trasa otwarta wcześniej przez asystenta** → `pushReplacement`, żeby stos nie rósł.
- **Użytkownik na ekranie Start albo w asystencie** → otwarcie modułu automatycznie.
- **Użytkownik w innym module** → karta z odpowiedzią i chip „Pokaż w module”, bez porywania nawigacji.
- **Na wierzchu dialog albo arkusz** (`PopupRoute`) → nakładka nic nie otwiera.
- **Trasy narzędzi** mają nazwy `tool:<id>` (`RouteSettings`). `AppRouteObserver` wie, co jest na wierzchu.
- **Nakładka** w `MaterialApp.builder` leży NAD Navigatorem, więc ma własny `Overlay` i `Material`. Arkusze i dialogi otwiera przez `appNavigatorKey`. Alarm timera zostaje nad nią.
- **W spoczynku nakładka nic nie animuje** (`pumpAndSettle` w testach z pełną aplikacją).

### 4.5 Rysowanie ISO (`IsoNotebookController`)

**Korekta v2 — model zeszytu dyktuje API:**
- Kolano powstaje tylko na styku dwóch rur (`_maybeInsertElbows`). „Kolano” w poleceniu to zamiar skrętu stosowany do NASTĘPNEJ rury. Kolano na końcu zdania → „powiedz, dokąd idzie rura po kolanie”.
- Zawrócenie (kierunek przeciwny) albo ten sam kierunek po kolanie → pytanie.
- Kolano 45° i trójnik w sekwencji są poza zakresem tej iteracji. Asystent mówi to głośno i proponuje narysowanie palcem.
- DN wpisywany jest w kolana i w pamięć ostatniego DN.
- Współrzędne liczone są wprost z kierunku siatki. Start jest przesunięty tak, żeby rysunek nie wyszedł nad górę siatki. Po poleceniu widok dopasowuje się, żeby cały rysunek był widoczny.
- Podgląd animacji ma osobne pole (`_ghost`), nie miesza się z gestem palca.
- Polecenia idą przez kolejkę.
- `ready` obejmuje wczytanie ustawień, ostatniego szkicu i pierwszy układ płótna.
- **Zeszyt zamknięty, a ostatni szkic niepusty i świeży (< 12 h)** → pytanie „Dorysować do «X» czy nowy rysunek?”. Nowy rysunek dostaje nazwę dopiero przy pierwszym elemencie, więc nie zostaje pusty wpis.
- Kierunki zdefiniowane indeksem kierunku siatki:
  - `w prawo` = 0, `w lewo` = 3;
  - `w górę` = 1, `w dół` = 4 (oś III = pion w domyślnym odwzorowaniu);
  - `do przodu` = 5, `do tyłu` = 2.
  - Przy strzałce północy działają północ, południe, wschód i zachód (`_AxisMapping`). Zgodność z etykietami w UI sprawdza test.

### 4.5a Rysowanie ISO — szkic pierwotny
- Kontroler jest `part` pliku `iso_notebook_screen.dart`, bo model szkicu jest prywatny.
- Udostępnia API na prymitywach:
  - `startNew`, `addPipe(dir, lengthMm?)`, `addElbow(toDir, angle)`, `addComponent(tool, dn…)`, `addNote`, `undo`;
  - `ready`, kursor.
- Jedno polecenie głosowe to jeden krok cofania (`_push()` raz).
- Kolejne kroki są animowane podglądem linii co ~300 ms.
- Kolano 90° wstawia się samo na styku dwóch rur (`_maybeInsertElbows`).
- Kierunki: w prawo/lewo = oś I, do przodu/do tyłu = oś II, w górę/w dół = oś III (pion).
- Domyślny skręt kolana bez kierunku: z poziomej I na II, z II na I, z pionu na I. Asystent mówi, co przyjął.
- Długość w mm trafia do wymiaru (`_CutCalc`). Bez długości — rysunek bez wymiaru, a w odpowiedzi „długość do uzupełnienia”.

### 4.6 Nakładka i ekran główny
- **Przycisk mikrofonu na wszystkich ekranach** (`MaterialApp.builder`, jak `WeldTimerAlarmOverlay`):
  - 64 dp, w rogu, przeciągalny, z zapamiętaną pozycją;
  - nie zasłania pól: panel ma do 40% wysokości i zwija się do paska z ostatnią odpowiedzią.
- **Panel:**
  - transkrypcja na żywo (wyniki częściowe), wynik w karcie i chipy kontynuacji („a DN50”, „pokaż w module”);
  - podsumowanie zapisu z „Zapisz / Popraw”;
  - „Zgłoś problem”.
- **Ekran Start:** u góry pasek asystenta (mikrofon + pole „Powiedz albo wpisz, czego potrzebujesz”) z przykładami „Co umiem”.
- **`AiChatScreen` staje się pełnym widokiem tej samej sesji** (historia, tryb Odpowiedz). Jeden stan: `AssistantSession`.

### 4.7 Mowa

**Świadoma zmiana względem §6 z 2026-08-30.** W nakładce odpowiedź jest czytana na głos domyślnie, gdy pytanie zadano głosem (tego chce właściciel: „asystent odpowiada…”). Przełącznik w panelu, ustawienie trwałe `assistant_overlay_speak_v1`. Ekran `AiChatScreen` zachowuje swoje dotychczasowe ustawienie (domyślnie wyłączone). Transkrypcję zawsze można poprawić przed wysłaniem.

- Jedna współdzielona instancja `SpeechInput`/`SpeechOutput` w całej aplikacji. `speech_to_text` jest singletonem i druga instancja nie dostaje `onDone`.
- Alternatywy rozpoznania (N-best z pewnością). Mózg wybiera alternatywę z najwyższym wynikiem umiejętności, co jest najtańszą poprawą w hałasie.
- Rozpoznawanie na urządzeniu najpierw, a przy błędzie języka ponowienie z rozpoznawaniem w sieci.
- „Dopowiedzenie”: wypowiedź do 8 s po turze, bez własnego zamiaru, dokleja się do poprzedniej umiejętności (chip „Dopowiedz”).
- Błędy `no_match`, `speech_timeout` i `network` dają komunikat „Nie usłyszałem — powtórz albo wpisz”. To NIE są sygnały feedbacku.
- iOS: kategoria audio `playback` + `defaultToSpeaker`, `awaitSpeakCompletion(true)`, 250 ms przerwy między TTS a nasłuchem.
- Windows i web bez mikrofonu: przycisk otwiera wpisywanie.
- Wibracja na start i stop nasłuchu (rękawice).

### 4.7a Mowa — szczegóły pierwotne
- `speech_to_text` (wyniki częściowe, `pl_PL`, preferencja rozpoznawania na urządzeniu, gdy dostępne).
- Odpowiedź czytana na głos (`flutter_tts`), gdy pytanie zadano głosem. Przełącznik w panelu, ustawienie trwałe.
- Przed nasłuchem TTS milknie.

### 4.8 Feedback
- **Sygnały:**
  - jawne zgłoszenie („zgłoś problem: …”, przycisk);
  - narzekanie wykryte w wypowiedzi („nie działa”, „gdzie jest…”, „głupie”, „nie mogę znaleźć”, „bez sensu”);
  - polecenie nierozpoznane (dwa razy z rzędu = jeden sygnał);
  - błąd wyłapany przez asystenta.
- **Zawartość sygnału:** rodzaj, tekst wypowiedzi (do 500 znaków), moduł, wersja aplikacji, platforma, język, czas.
- **Ochrona prywatności:**
  - nie ma nagrania, nazwiska ani położenia;
  - numery telefonów i adresy e-mail są maskowane przed wysłaniem.
- **Kolejka lokalna:**
  - limit 300; przy przepełnieniu najstarsze sygnały automatyczne wypadają z licznikiem, jawne zgłoszenia nigdy;
  - wysyłka partiami tylko przy zgodzie „Pomóż ulepszać aplikację”.
- **Narzekanie:** przy wykryciu asystent proponuje „Chcesz to zgłosić twórcy? Powiedz, co nie działa”.
- **Backend** (osobne repo `backend/`, Railway `fitter-welder-pro-backend`):
  - `POST /api/fitter/feedback`: partia ≤ 20, limity dzienne, Zod `.strict()`;
  - tabela `fitter_feedback`, retencja 180 dni;
  - `GET /api/fitter/feedback/admin` z `x-admin-token`;
  - „Usuń moje dane” kasuje też feedback.
- **Właściciel:** `dart run tool/feedback_digest.dart` pobiera zgłoszenia (token z vaulta) i tworzy raport Markdown pogrupowany po modułach i rodzajach, z najczęstszymi frazami.
- **Decyzje prawne v2 (po przeglądzie):**
  - Identyfikator: osobny losowy `feedback_install_id` (nie identyfikator urządzenia czatu). Umożliwia kasowanie i limity. W deklaracjach sklepów zgłoszony zachowawczo jako „powiązany z urządzeniem, opcjonalny, nie do śledzenia”.
  - Polityka mówi wprost: „treść zgłoszenia może zawierać dane, które sam podasz”.
  - Bez podnoszenia `kLegalVersion`: zgoda na feedback jest osobna, pokazuje własny tekst i zapisuje datę polityki. Podniesienie wersji zablokowałoby czat i skaner wszystkim do ponownej akceptacji.
  - Surowe teksty zgłoszeń NIGDY nie trafiają do repozytorium (repo GitHub jest publiczne). Raport właściciela jest zapisywany poza repo albo wysyłany mailem.
  - Lokalne „Usuń moje dane” czyści kolejkę i zgodę, a na serwerze kasuje zgłoszenia tego `feedback_install_id`.
- **Dodatkowe źródła sygnałów v2:**
  - globalne `FlutterError.onError` i `PlatformDispatcher.onError` dają sygnał „błąd” (typ błędu + moduł, bez treści);
  - „Zgłoś problem z tym modułem” w arkuszu pomocy `HelpButton`;
  - narzekanie liczone tylko z odniesieniem do aplikacji albo po nieudanej turze („nie działa” bywa o spawarce);
  - „gdzie jest…” to osobny rodzaj „nie mogę znaleźć”;
  - propozycja „Chcesz zgłosić?” najwyżej raz na sesję i raz na dobę, nigdy po udanej odpowiedzi.
- **Prawo (pierwotnie):**
  - `kLegalVersion` 3 → 4;
  - tekst polityki (sekcja „Zgłoszenia problemów”);
  - strony `/privacy` w backendzie;
  - deklaracje sklepów (App Privacy, Data Safety: „App interactions / Other user content — diagnostics, not linked, optional”).

## 5. Poziomy pokrycia modułów

| Poziom | Co umie asystent | Moduły |
|---|---|---|
| A | otwórz + wyjaśnij + „co tu zrobisz” + pytania z Pomocy | wszystkie 75 (automatycznie z rejestru i Pomocy) |
| B | policz i odpowiedz + wypełnij moduł na żywo | dn_mm, wall_thickness, pipe_weight, steel_weight, unit_converter, elbow_takeouts, pipe_slope, rolling_offset, bevel, thermal_expansion, elbow_cut, insert, reducer, heat_input (+CE/podgrzanie), cooling_time, shade, power_source, bolt_torque, glossary, tungsten, timer (start/stop/minuty) |
| C | przygotuj rekord, pokaż podsumowanie, po potwierdzeniu zapisz i otwórz | weld_journal, parametry spawania (już są), hot_work, confined_space, interpass, hardness, spool_check, ferrite_pmi, weld_quotes |
| D | rysuj na żywo | iso_notebook |

Każde narzędzie ma wpis w manifeście pokrycia (`assistant_coverage.dart`). Test pilnuje, że:
- każde id rejestru ma co najmniej poziom A;
- moduły z poziomu B mają umiejętność z przykładami, które się liczą.

## 6. Testy i odbiór

1. **Korpus wypowiedzi** dla każdej umiejętności (PL i EN), zawierający:
   - przykłady;
   - odmiany z rozpoznawania mowy;
   - pułapki, czyli wypowiedzi, które NIE mogą trafić w tę umiejętność.
2. **Test pokrycia** rejestru (poziomy A i B).
3. **Testy widżetów:**
   - nakładka z atrapą mowy;
   - pytanie DN40 → karta i wiersz w module;
   - „narysuj rura kolanko rura” → 2 odcinki i kolano;
   - Cofnij.
4. **Testy feedbacku:** detektor, maskowanie, kolejka i zgoda; backend `node:test` (walidacja, limity, admin, kasowanie).
5. **Ręczny test na telefonie** (lista w planie). Build wysyłany przez Firebase App Distribution.

## 7. Poza zakresem tej iteracji

- słowo-budzik i nasłuch ciągły;
- model językowy (architektura gotowa, flaga wyłączona);
- sterowanie rozmową wieloetapową dłuższą niż jedno pytanie dopytujące;
- przebudowa menu (asystent ma zmniejszyć chaos; porządki w menu — osobna decyzja).
