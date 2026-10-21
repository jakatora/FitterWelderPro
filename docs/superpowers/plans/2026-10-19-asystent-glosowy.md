# Asystent głosowy sterujący modułami — plan wdrożenia (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jeden asystent głosowy dostępny na każdym ekranie, który:
- odpowiada liczbami z modułów aplikacji;
- steruje modułami;
- rysuje izometrię na żywo;
- zbiera dla właściciela feedback o problemach.

**Architecture:**
- Lokalny, deterministyczny mózg wybiera umiejętność (`AssistantSkill`) z katalogów grupowych.
- Umiejętność liczy funkcją domeny i zwraca: odpowiedź, pokazanie w module, pytanie albo potwierdzenie.
- Moduły odbierają polecenia przez `ToolBridge`, Zeszyt ISO przez `IsoNotebookController`.
- Nakładka nad Navigatorem ma własny `Overlay` i trzyma się polityki nawigacji, która nie porywa użytkownika.
- Feedback trafia do lokalnej kolejki, a po zgodzie do nowego endpointu backendu Fittera.

**Tech Stack:**
- Flutter 3.47.5 (`C:\Users\Startklaar\flutter\bin\flutter.bat`), Dart 3;
- `speech_to_text` 7.5, `flutter_tts` 4.2, `vibration` 3.2;
- SharedPreferences, sqflite;
- backend: Node 24, Express 5, `node:sqlite`, Zod (osobne repo `backend/`, Railway).

**Spec:** `docs/superpowers/specs/2026-10-19-asystent-glosowy-sterujacy-design.md` (v2: §2.1 mierniki, §2.2 zakres, §4.4a nawigacja, §4.5 ISO, §4.7 mowa, §4.8 feedback).

## Global Constraints

- UI dwujęzyczne `context.tr(pl:, en:)`, domyślnie PL, polskie znaki poprawnie.
- Liczby w odpowiedziach tylko z funkcji domeny. Asystent nie ma własnych tabel liczb. Źródła norm wg domeny, np. DN→OD: „EN 10220 / ISO 4200 seria 1, ASME B36.10M”, NIE „ISO 6708”.
- Bez nowych pakietów w `pubspec.yaml`.
- Mikrofon tylko po naciśnięciu. TTS milknie przed nasłuchem (przerwa 250 ms).
- Zmiana danych = podsumowanie → potwierdzenie → zapis → Cofnij.
- Moduły bezpieczeństwa (prace pożarowe, przestrzeń zamknięta, zawiesia, szlifierki, dymy):
  - asystent nie ustawia `checked`, `na` ani żadnego pola gotowości;
  - potwierdzenie tylko dotykiem, bez głosowego „tak”.
- Nic nie wychodzi z telefonu bez zgody. Zgoda na feedback jest osobna i domyślnie wyłączona. Nie wysyłamy nagrań.
- `kLegalVersion` zostaje 3 (zgoda na feedback jest osobna, z datą polityki).
- Polecenie rozpoznane lokalnie nigdy nie idzie na serwer. `kAssistantRemoteLlm = false`. Kontrakt V1 `/ai/intent` bez zmian.
- `match()` umiejętności jest synchroniczne i bez I/O.
- Singletony (`ToolBridge.instance`, `AssistantSession.instance`, mowa) mają `@visibleForTesting reset()`. Przy starcie aplikacji zero wywołań platformy.
- Konwencje repo:
  - `flutter analyze` czysty;
  - testy bez sieci (`MockClient`, atrapy mowy, `useTestDatabase()`, `seedFreshInstall()`);
  - commit z pliku przez `git commit -F`;
  - nie commitować `macos/Flutter/GeneratedPluginRegistrant.swift`, `pubspec.lock`, `.atlas/`, `linux|windows/flutter/*`.
- Agenci w worktree: najpierw `git merge feat/wyceny-i-moduly`. NIE ruszają:
  - `lib/widgets/tool_registry.dart` (poza zadaniem 1.4);
  - `tool/audit/*`, `test/audit/*`;
  - `lib/assistant/skills/skill_catalog.dart` (integruje koordynator).
  Każda grupa rejestruje umiejętności we własnym `lib/assistant/skills/<grupa>/catalog.dart`.
- Repo GitHub jest PUBLICZNE: żadnych surowych zgłoszeń, tokenów ani zrzutów danych w repo.

## Review Focus

1. **Hałas i błędy rozpoznawania mowy.**
   - „de en 40”, „dn czterdzieści”, „d n 40” → DN40;
   - „dn 4 0” → pytanie;
   - z N-best wybierana alternatywa z najwyższym wynikiem.
   - Pin: korpus 1.1 i 1.3, test alternatyw w 1.5.
2. **„Kradzież” zamiaru między umiejętnościami.**
   - „dodaj zawór kulowy dn50” nie może trafić w zapis parametru spawania;
   - „ile waży rura” nie może trafić w rysowanie.
   - Pin: globalny test routera 1.3 (rozszerzany przez koordynatora po każdym scaleniu).
3. **Strona wczytuje ustawienia po otwarciu i nadpisuje pola asystenta.** Pin: `whenReady` + `markReady` w 1.4.
4. **Rysowanie przy niepustym szkicu, zawrócenie, kolano na końcu, góra siatki.** Pin: 3.1 / 3.2.
5. **Feedback bez zgody, z danymi osobowymi albo spamujący.**
   - bez zgody 0 żądań;
   - telefon i e-mail zamaskowane;
   - propozycja zgłoszenia maks. raz na sesję i dobę.
   - Pin: 5.1a / 5.1b.

## Przegląd planu v1 → v2 (co poprawiono i dlaczego)

| # | Problem w v1 | Poprawka w v2 | Zadanie |
|---|---|---|---|
| 1 | Nakładka w `MaterialApp.builder` nie ma Overlay ani Navigatora: TextField, Tooltip i arkusze się wywrócą | Własny `Overlay` + `Material`; `appNavigatorKey`; `AppRouteObserver`; trasy `tool:<id>` | 1.4, 1.5 |
| 2 | Każde pytanie otwierało moduł, więc stos tras rósł (10× „Wstecz” = nowy chaos) | Polityka nawigacji §4.4a: `apply` w miejscu / `pushReplacement` / chip zamiast porywania | 1.4 |
| 3 | Stary parser („dodaj…” = zapis parametru) przechwyciłby polecenia rysowania | Adapter starego parsera jako umiejętność z oceną według dowodów i premią kontekstu; globalny test routera | 1.3 |
| 4 | `speech_to_text` to singleton, więc druga instancja wisi na „słucham” | Jedna współdzielona mowa z dyspozytorem; N-best; ponowienie przy błędzie rozpoznawania na urządzeniu | 1.5 |
| 5 | API kontrolera ISO nie pasowało do modelu (kolano tylko z dwóch rur, 45° i trójnik niemożliwe, wiersze < 0, kolizja z gestem) | Kolano = zamiar skrętu; pytania przy zawróceniu; 45°/trójnik poza zakresem; `_ghost`; dopasowanie widoku; kolejka; pytanie „dorysować czy nowy” | 3.1, 3.2 |
| 6 | Przepięcie `AiChatScreen` (2200 linii, ~20 testów) na nową sesję | Zadanie 1.0: wyciągnąć zapisy do `AssistantActions`; ekran zostaje, mózg tylko jako pierwszy krok przed serwerem | 1.0, 1.5 |
| 7 | Sprzeczności RODO: „nie powiązane” + kasowanie; `kLegalVersion` 4 blokuje czat; raporty w publicznym repo | Losowy `feedback_install_id`; wersja zasad bez zmian; raport poza repo albo mailem | 5.1a, 5.2, 5.3 |
| 8 | Brak testu na telefonie do samego końca | 1.6: build z pilotem i 30 frazami, przed Etapem 2 | 1.6 |
| 9 | Brak mierników sukcesu i zawyżony zakres „każdy moduł” | Spec §2.1/§2.2; manifest pokrycia liczony z katalogów; test kontraktu pól | 4.2 |
| 10 | Rekordy bezpieczeństwa: test „po nazwach pól” za słaby (`na` też odhacza) | Biała lista pól; reszta JSON = `blank()`; bez głosowego „tak” | 4.1 |
| 11 | „Wiedza z całej aplikacji” = tylko Pomoc i słownik | 2.5: wiedza z danych modułów (wady, ISO 5817, elektrody, kolory zawiesi i tarcz, NDS) | 2.5 |
| 12 | „Steruje modułem” w modułach rejestrów = tylko otwarcie | 4.3: pytania o własne dane (uprawnienia, kalibracje, postęp, ekspozycja elektrod) | 4.3 |
| 13 | Feedback nie łapał błędów aplikacji ani zgłoszeń z modułów | Globalne handlery błędów, „Zgłoś problem z tym modułem” w `HelpButton`, karta zgody po 3× „nie rozumiem” | 5.1b |
| 14 | Dwa pola tekstowe na Start (wyszukiwarka + asystent) to więcej chaosu | Jedno pole: pisanie pokazuje trafienia, Enter albo mikrofon idzie do asystenta | 1.5 |
| 15 | Zadanie 0.2 za szerokie (część logiki już jest w domenie) | Tylko przelicznik, spadek, rolling offset | 0.2 |

## Ścieżki pracy i kolejność

```
Start równolegle:
  A1 (rdzeń logiki): 0.1 → 1.1 → 1.2 → 1.3
  B  (domena):       0.2
  C  (ISO):          3.1
  D  (backend repo): 5.2   (najpierw fixture sygnału — wspólny z 5.1a/5.3)
  E  (feedback lib): 5.1a
Po A1:
  A2 (UI rdzenia):   1.0 → 1.4 → 1.5 → 1.6 (build do właściciela)
Po A2 (+B, +C):
  2.0 (zakładki FitterTools) → równolegle 2.1 | 2.2 | 2.3 | 2.4 | 2.5 | 3.2 | 4.1 | 4.3 | 5.1b
Na koniec: 4.2 (pokrycie), 5.3 (raport właściciela), Etap 6 (odbiór, build, wdrożenie backendu)
```

Koordynator po każdym scaleniu:
- dopisuje katalog grupy do `skill_catalog.dart`;
- uruchamia globalny test routera i pełne testy;
- rozstrzyga kolizje zamiarów.

---

## Etap 0 — Fundamenty domeny

### Zadanie 0.1: Publiczne funkcje rur i tokenizer mowy (ścieżka A1)

**Files:**
- Create: `lib/domain/fitter/pipe_size_lookup.dart`
- Create: `lib/assistant/core/spoken_numbers.dart`. Przeniesione z `assistant_parser.dart`:
  - `foldSpeech` (= dawne `_fold`);
  - `spokenTokens` (= dawne `_tokens`/`_items` z zamianą liczb słownie na cyfry);
  - `parseSpokenNumber`.
- Modify: `lib/assistant/assistant_parser.dart` (importuje nowe, usuwa kopie; zachowanie bez zmian)
- Modify: `lib/data/pipe_schedules.dart` (+ `PipeRow? pipeRowForDn(int dn)`)
- Test: `test/domain/fitter/pipe_size_lookup_test.dart`, `test/assistant/spoken_numbers_test.dart`

**Interfaces — Produces:**
```dart
class OdOption { const OdOption(this.odMm, this.series); final double odMm; final OdSeries series; }
double? odForDn(int dn);                 // seria główna: asmeAndEn1 → asme → en1 → pierwsza
List<OdOption> odSeriesForDn(int dn);    // główna pierwsza; DN40 → [48.3 asmeAndEn1, 44.5 en3]
double? odForNps(double inches);
PipeRow? pipeRowForDn(int dn);
String foldSpeech(String text);
/// Tokeny po zwinięciu; ciągi liczb słownych zamienione na cyfry („czterdzieści pięć” → „45”);
/// dwie liczby słowne obok siebie zostają osobno („dwa sześćdziesiąt” → „2”, „60”).
/// „metr dwadzieścia” zostaje jako „metr”, „20” — długość składa `Utterance.lengthMm()`.
List<String> spokenTokens(String text);
double? parseSpokenNumber(String text);
```

- [ ] Testy:
  - `odForDn(40) == 48.3`;
  - `odSeriesForDn(40).map((o) => o.odMm).toList() == [48.3, 44.5]`;
  - `odForDn(999) == null`;
  - `odForNps(2) == 60.3`;
  - `pipeRowForDn(50)!.od == 60.3`.
- [ ] Testy:
  - `spokenTokens('dn czterdzieści')` → `['dn', '40']`;
  - `spokenTokens('ścianka dwa sześćdziesiąt')` → `['scianka', '2', '60']` (osobno, bez sklejania);
  - `parseSpokenNumber('półtora')` → 1.5.
- [ ] Stare korpusy parsera (`assistant_parser_test.dart`, `assistant_dirty_speech_test.dart`) zielone bez zmian.
- [ ] Commit.

### Zadanie 0.2: Czyste funkcje: przelicznik, spadek, rolling offset (ścieżka B)

**Files:**
- Create: `lib/domain/fitter/unit_conversion.dart`. Funkcje `convertLength(double v, LengthUnit from, LengthUnit to)` oraz analogicznie `Temperature`, `Pressure` i `Flow`, z enumami jednostek takimi, jakie ma dziś ekran.
- Create: `lib/domain/fitter/pipe_slope.dart`. Funkcje `riseMm({required double lengthMm, required double slopePct})`, `lengthMm({riseMm, slopePct})`, `slopePct({lengthMm, riseMm})`, `angleDeg(slopePct)` i `mmPerM(slopePct)`.
- Create: `lib/domain/fitter/rolling_offset.dart`. Funkcja `RollingOffsetResult? rollingOffset({required double riseMm, required double spreadMm, required double angleDeg})`, gdzie wynik ma pola `offsetMm`, `travelMm`, `runMm` i `rollDeg`.
- Modify: `lib/screens/quick_converter_screen.dart`, `lib/screens/pipe_slope_screen.dart`, `lib/screens/rolling_offset_screen.dart`. Strony wołają nowe funkcje, a zachowanie i formatowanie zostają bez zmian.
- Test: `test/domain/fitter/unit_conversion_test.dart`, `pipe_slope_test.dart`, `rolling_offset_test.dart`; dotychczasowe testy ekranów zielone.

- [ ] Wartości referencyjne PRZEPISZ z obecnej logiki ekranu przed refaktorem: 1″ = 25,4 mm; 100 °C = 212 °F; 10 bar → psi wg stałej ekranu; 2 % na 5000 mm = 100 mm; rolling offset rise 300 / spread 400 / 45° wg wzoru ekranu.
- [ ] Refaktor stron, ich testy zielone, commit.

## Etap 1 — Rdzeń

### Zadanie 1.1: `Utterance` (A1)

**Files:** Create `lib/assistant/core/utterance.dart`; Test `test/assistant/core/utterance_test.dart`.

**Interfaces — Produces:**
```dart
class Utterance {
  Utterance(this.raw, {required this.lang, this.byVoice = false, this.alternatives = const []});
  final String raw; final AppLanguage lang; final bool byVoice;
  final List<String> alternatives;                 // N-best z rozpoznawania (bez raw)
  late final String folded = foldSpeech(raw);
  late final List<String> tokens = spokenTokens(raw);
  bool hasAny(Iterable<String> foldedWordsOrPhrases);
  bool hasStem(Iterable<String> stems);            // 'kolan' → kolano/kolanko/kolana
  int? dn();          // dn40 | dn 40 | de en 40 | d n 40 | dn czterdzieści; „dn 4 0” → null
  double? npsInches();// 2" | 2 cale | półtora cala | trzy czwarte (cala)
  double? lengthMm({double assumeMetersBelow = 50}); // „2 m”, „1500”, „150 cm”, „metr dwadzieścia”→1200; „rura 2” → 2000 (lengthAssumedMeters = true)
  bool get lengthAssumedMeters;
  double? numberNear(Iterable<String> keys);
  double? angleDeg();
  Utterance withRaw(String alt);                   // do oceny alternatyw
}
```

- [ ] Testy z przykładami w komentarzach (każdy przypadek osobno), także EN („what is the OD of DN40”).
- [ ] Commit.

### Zadanie 1.2: Kontrakt umiejętności (A1)

**Files:** Create `lib/assistant/core/skill.dart`, `assistant_text.dart`, `module_context.dart`; Test `test/assistant/core/skill_contract_test.dart`.

**Interfaces — Produces:**
```dart
class AssistantText { const AssistantText(this.pl, this.en); final String pl, en; String of(AppLanguage l) => l == AppLanguage.en ? en : pl; }
class SkillExample { const SkillExample(this.pl, this.en); final String pl, en; }
enum AssistantTier { a, b, c, d }   // A otwórz/wyjaśnij, B licz+wypełnij, C rekord, D rysuj
/// Bez zależności od UI — implementuje ToolBridge (1.4), w testach atrapa.
abstract class ModuleContext { String? get activeToolId; bool get onHomeOrAssistant; }
abstract class AssistantSkill {
  String get id; String? get toolId; AssistantTier get tier;
  List<SkillExample> get examples;
  bool get readOnly => true;                        // false = zmienia dane → ConfirmResult
  bool get safetyCritical => false;                 // true = potwierdzenie tylko dotykiem
  SkillMatch? match(Utterance u, AssistantContext ctx);   // synchronicznie, bez I/O
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx);
}
class SkillMatch { const SkillMatch(this.skill, this.score, {this.slots = const {}, this.missing = const [], this.utterance}); final AssistantSkill skill; final double score; final Map<String, Object?> slots; final List<String> missing; final Utterance? utterance; }
class AnswerLine { const AnswerLine(this.label, this.value); final AssistantText label; final String value; }
class AssistantAnswer { const AssistantAnswer({required this.text, this.spoken, this.lines = const [], this.source}); final AssistantText text; final AssistantText? spoken; final List<AnswerLine> lines; final AssistantText? source; }
class ShowInModule { const ShowInModule(this.toolId, [this.fields = const {}]); final String toolId; final Map<String, Object?> fields; }
class FollowUp { const FollowUp(this.label, this.utterance); final AssistantText label; final String utterance; }
sealed class SkillResult { const SkillResult(); }
class AnswerResult extends SkillResult { const AnswerResult(this.answer, {this.show, this.followUps = const []}); final AssistantAnswer answer; final ShowInModule? show; final List<FollowUp> followUps; }
class AskResult extends SkillResult { const AskResult(this.slot, this.question, {required this.partial, this.choices = const []}); final String slot; final AssistantText question; final SkillMatch partial; final List<FollowUp> choices; }
typedef UndoAction = Future<void> Function();
class ConfirmResult extends SkillResult { const ConfirmResult(this.summary, this.perform, {this.show, this.touchOnly = false}); final AssistantAnswer summary; final Future<UndoAction?> Function() perform; final ShowInModule? show; final bool touchOnly; }
class NotUnderstood extends SkillResult { const NotUnderstood(this.suggestions); final List<FollowUp> suggestions; }
class FailedResult extends SkillResult { const FailedResult(this.message); final AssistantText message; }
class AssistantContext {
  AssistantContext({required this.lang, required this.modules, DateTime Function()? now}) : now = now ?? DateTime.now;
  AppLanguage lang; final ModuleContext modules; final DateTime Function() now;
  SkillMatch? lastMatch; DateTime? lastAt;          // kontynuacja i dopowiedzenie (8 s)
}
```

- [ ] Test kontraktu na atrapie umiejętności. Commit.

### Zadanie 1.3: Mózg, pilotażowe umiejętności i globalny test routera (A1)

**Files:**
- Create:
  - `lib/assistant/core/brain.dart`;
  - `lib/assistant/skills/skill_catalog.dart` (`List<AssistantSkill> buildSkillCatalog()` = suma katalogów grup);
  - `lib/assistant/skills/core/catalog.dart` (`coreSkills()`);
  - w katalogu `lib/assistant/skills/core/`: `pipe_od_skill.dart`, `pipe_wall_skill.dart`, `open_tool_skill.dart`, `explain_tool_skill.dart`, `capabilities_skill.dart` („co umiesz”, także dla bieżącego modułu), `knowledge_skill.dart` (`searchHelp` + `weldingGlossaryIndex`), `legacy_intents_skill.dart`.
- Test:
  - `test/assistant/core/brain_test.dart`;
  - `test/assistant/skills/core/*_test.dart`;
  - `test/assistant/router_corpus_test.dart` — **globalny**: każdy przykład i każde odrzucenie każdej umiejętności z `buildSkillCatalog()` przez cały mózg;
  - `test/assistant/router_perf_test.dart` (500 wypowiedzi < 1 s).

**Interfaces — Produces:**
```dart
class BrainReply { const BrainReply(this.result, {this.match, this.notUnderstood = false, this.usedAlternative}); final SkillResult result; final SkillMatch? match; final bool notUnderstood; final String? usedAlternative; }
class AssistantBrain {
  AssistantBrain({required List<AssistantSkill> skills, this.threshold = 0.55, this.ambiguityGap = 0.08, this.contextBonus = 0.1});
  /// Ocena raw + alternatyw; wybór najwyższego wyniku. Jedna tura naraz.
  Future<BrainReply> handle(Utterance u, AssistantContext ctx);
  AskResult? get pending; void cancelPending();
}
```

**Reguły mózgu:**
1. Pytanie w toku:
   - wypowiedź z wartością slotu → `pending.partial` + slot → `run`;
   - „anuluj / nie / stop / zostaw” → kasuje;
   - inna umiejętność ≥ próg → kasuje pytanie i obsługuje nową.
2. Ocena wszystkich umiejętności (z wyjątkiem fallbacków `open/explain/knowledge/capabilities`) dla `raw` i każdej z alternatyw:
   - premia `contextBonus`, gdy `skill.toolId == ctx.modules.activeToolId`;
   - remis różnych modułów (< `ambiguityGap`) → `AskResult('skill', …)` z dwoma wyborami.
3. Kontynuacja i dopowiedzenie:
   - kontynuacja: brak trafienia ≥ próg, ale `lastMatch` z ostatnich 2 min, a wypowiedź zawiera slot („a DN50?”, „a dla 2 cali”) → `lastMatch.skill` z nowymi slotami;
   - dopowiedzenie: to samo w ciągu 8 s bez słowa kontynuacji.
4. Fallbacki: `open_tool` (czasownik „otwórz/pokaż/włącz”), potem `explain`, potem `knowledge`.
5. Nic nie pasuje → `NotUnderstood` z 3 propozycjami z `searchTools`; `notUnderstood: true`.
6. `run` rzuca wyjątek → `FailedResult` (karta „Nie udało się”), sygnał błędu (Zadanie 5.1b).

**`LegacyIntentsSkill`:**
- Woła `parseAssistantCommand` (stary parser).
- Wynik liczy według dowodów:
  - `save_weld_parameter` wymaga procesu albo materiału ORAZ prądu albo ścianki;
  - samo „dodaj …” bez tych pól daje wynik 0;
  - `add_weld_journal_entry` wymaga słowa „dziennik/spoina nr”.
- Zwraca `ConfirmResult` przez `AssistantActions` (Zadanie 1.0; w 1.3 atrapa interfejsu `AssistantActionsPort`).

**`PipeOdSkill`:**
- Odpowiedź PL: „DN40 — średnica zewnętrzna 48,3 mm (EN 10220 / ISO 4200 seria 1, ASME B36.10M). W szeregu EN 3: 44,5 mm.”
- `show: ShowInModule('dn_mm', {'dn': 40})`.
- `followUps`: „a ścianka?”, „a DN50?”.
- Korpus:
  - **trafienia:** „jaka jest średnica rury dn40”, „średnica zewnętrzna DN 40”, „ile ma de en czterdzieści”, „dn40 ile mm”, „średnica 2 cale”, „what is the OD of DN40”;
  - **odrzucenia:** „ścianka dn40 sch40” → `pipe.wall`; „otwórz tabelę dn” → `tool.open`; „dodaj zawór kulowy dn50” → NIE `pipe.od` i NIE `legacy.save`;
  - „dn” bez liczby → `AskResult('dn')`.

- [ ] Testy mózgu:
  - kolejność 1–6;
  - remis;
  - „anuluj”;
  - kontynuacja „a dla DN50?”;
  - wybór alternatywy N-best („de en 40” w alt, „ten en 40” w raw);
  - stary zapis parametru → `ConfirmResult` bez zapisu.
- [ ] Globalny test routera i test wydajności.
- [ ] Commit.

### Zadanie 1.0: `AssistantActions` — zapisy wyciągnięte z `AiChatScreen` (A2)

**Files:**
- Create: `lib/assistant/assistant_actions.dart`, z metodami:
  - `Future<SavedWeldParam> saveWeldParam(WeldParamDraft d, {required bool byVoice, required AppLanguage lang})`;
  - `Future<void> undoWeldParam(...)`;
  - `prepareJournal` / `saveJournal` / `undoJournal`;
  - `historyAdd`.
  Logika 1:1 z `_save`, `_prepareJournal`, `_saveJournal`.
- Modify: `lib/screens/ai_chat_screen.dart` (woła `AssistantActions`; klucze i parametry konstruktora bez zmian)
- Test: istniejące `test/assistant/assistant_flow*_test.dart` zielone bez zmian + `test/assistant/assistant_actions_test.dart`

- [ ] Refaktor bez zmiany zachowania, testy, commit.

### Zadanie 1.4: Nawigacja globalna, `ToolBridge`, uchwyty pilotażowe (A2)

**Files:**
- Create: `lib/app_navigator.dart`, zawierający:
  - `appNavigatorKey`;
  - `AppRouteObserver` (stos tras: nazwa, czy `PopupRoute`, czy otwarta przez asystenta);
  - `Future<void> openToolById(String id, {bool byAssistant = false, bool replaceAssistantRoute = false})`, z `RouteSettings(name: 'tool:<id>')`.
- Modify:
  - `lib/app.dart`: `navigatorKey`, `navigatorObservers`;
  - `lib/widgets/tool_registry.dart`: `openTool` nadaje `RouteSettings(name: 'tool:<id>')`. To jedyna zmiana w rejestrze.
- Create: `lib/assistant/core/tool_bridge.dart`
- Modify (piloty `ToolHandleHost`):
  - `lib/screens/dn_mm_screen.dart` (`dn` → filtr i podświetlenie wiersza);
  - `lib/screens/pipe_schedule_screen.dart` (`dn`, `schedule`; `markReady` po `_loadPrefs`);
  - `lib/screens/heat_input_screen.dart` (`volts`, `amps`, `travel_mm_min`; `markReady` po przywróceniu ustawień).
- Test: `test/assistant/core/tool_bridge_test.dart`, `test/assistant/navigation_policy_test.dart`, `test/assistant/tool_handles_pilot_test.dart`

**Interfaces — Produces:**
```dart
abstract class ToolHandle {
  String get toolId; Set<String> get supportedFields;
  /// Ustawia pola i JAWNIE przelicza. Zwraca pola nieobsłużone.
  Future<Set<String>> apply(Map<String, Object?> fields);
}
class ToolBridge extends ChangeNotifier implements ModuleContext {
  static ToolBridge get instance; @visibleForTesting static void reset();
  void attach(ToolHandle h, {required Route<dynamic>? route}); void detach(ToolHandle h);
  ToolHandle? get current;                      // uchwyt trasy na wierzchu (isCurrent)
  @override String? get activeToolId; @override bool get onHomeOrAssistant;
  Future<ToolHandle?> whenReady(String toolId, {Duration timeout = const Duration(seconds: 3)});
}
mixin ToolHandleHost<T extends StatefulWidget> on State<T> implements ToolHandle { void markReady(); }
enum ShowOutcome { appliedInPlace, opened, replaced, offeredChip, blockedByPopup, timedOut }
Future<ShowOutcome> showInModule(ShowInModule s, {required bool userOnHomeOrAssistant});
```

**Polityka (spec §4.4a):**
1. `current?.toolId == s.toolId` → `apply`.
2. Wierzch to `PopupRoute` → `blockedByPopup`.
3. Wierzch otwarty przez asystenta → `pushReplacement`.
4. `userOnHomeOrAssistant` → `push`.
5. Inaczej → `offeredChip` (sesja pokaże chip „Pokaż w module”).

- [ ] Testy:
  - `whenReady` czeka na `markReady` (strona z opóźnionym `_loadPrefs` 200 ms);
  - timeout → `timedOut`, odpowiedź zostaje;
  - pięć gałęzi polityki;
  - DN40 → wiersz 48,3 widoczny;
  - `heat_input` 230 A / 24 V / 150 mm/min → wynik na ekranie zgodny z `heatInputKJPerMm`.
- [ ] Commit.

### Zadanie 1.5: Mowa współdzielona, sesja, nakładka, pole na Start (A2)

**Files:**
- Modify: `lib/assistant/speech_io.dart`:
  - `SharedSpeech.instance` (jedna instancja `SystemSpeechInput`/`SystemSpeechOutput`, dyspozytor callbacków na aktywnego konsumenta);
  - callback `SpeechHeard {text, isFinal, alternatives: List<String>, confidence}`;
  - rozpoznawanie na urządzeniu → ponowienie z siecią przy błędzie języka;
  - kategoria audio iOS i `awaitSpeakCompletion`;
  - stare API dla `AiChatScreen` zachowane przez adapter.
- Create:
  - `lib/assistant/core/assistant_session.dart`;
  - `lib/assistant/core/assistant_settings.dart` (`speakReplies` domyślnie true dla nakładki, `showMicButton` domyślnie true, pozycja przycisku jako ułamki ekranu, język rozpoznawania);
  - `lib/assistant/ui/assistant_overlay.dart`;
  - `lib/assistant/ui/assistant_answer_card.dart`.
- Modify:
  - `lib/app.dart`: `builder: WeldTimerAlarmOverlay(child: AssistantOverlay(child: child))`, czyli alarm nad nakładką;
  - `lib/screens/home_screen.dart`: `_SearchField` staje się polem asystenta (pisanie → trafienia narzędzi na żywo jak dziś; Enter/mikrofon → asystent);
  - `lib/screens/ai_chat_screen.dart`: tryb Wykonaj najpierw pyta mózg o umiejętności tylko do odczytu, a dopiero potem stary silnik i serwer; mowa ze `SharedSpeech`.
- Test:
  - `test/assistant/ui/assistant_overlay_test.dart`;
  - `test/assistant/core/assistant_session_test.dart`;
  - `test/assistant/shared_speech_test.dart`;
  - `test/assistant/no_remote_for_local_test.dart`;
  - istniejące `assistant_flow*_test.dart`, `widget_test.dart`, `welder_journey_test.dart`, `home_quick_access_test.dart`, `home_refresh_nav_test.dart` zielone.

**Interfaces — Produces:**
```dart
enum ListenState { idle, listening, thinking, speaking }
class AssistantTurn { final Utterance utterance; final BrainReply reply; final ShowOutcome? show; final DateTime at; }
class AssistantSession extends ChangeNotifier {
  AssistantSession({required AssistantBrain brain, required AssistantContext context, SpeechPort? speech, AssistantSettings? settings, FeedbackSink? feedback});
  static AssistantSession get instance; @visibleForTesting static void reset();
  List<AssistantTurn> get turns; ListenState get state; String get partial; ConfirmResult? get awaitingConfirm;
  Future<void> toggleListening();                  // w „thinking” — anuluje turę
  Future<void> submit(String text, {bool byVoice = false, List<String> alternatives = const []});
  Future<void> confirm({required bool byTouch});   // touchOnly + !byTouch → ignoruj
  Future<void> undoLast();
}
abstract class FeedbackSink { void notUnderstood(Utterance u); void complaint(Utterance u, String? toolId); void error(Object e, String? toolId); }  // implementacja w 5.1b; tu NoopFeedbackSink
```

**Nakładka (spec §4.6, §4.4a):**
- przycisk 64 dp; przeciąganie dopiero po długim przytrzymaniu; pozycja jako ułamki ekranu; domyślnie z lewej, z dala od FAB;
- panel ≤ 40% wysokości, zwijany do paska; „Wstecz” najpierw zwija panel;
- `Semantics(liveRegion)`; stan nasłuchu nie tylko kolorem; wibracja na start i stop;
- przy otwartej klawiaturze chowa się do 40 dp;
- ukryta, gdy na wierzchu jest `AiChatScreen`, `ChatScreen`, kamera skanera albo `PopupRoute`;
- w spoczynku żadnej animacji;
- na Windows i web przycisk otwiera wpisywanie.

**Potwierdzenie:**
- głosowe „tak / zapisz / potwierdzam” działa tylko przy `awaitingConfirm`, i nigdy dla `touchOnly`;
- inaczej wypowiedź idzie do mózgu.

- [ ] Testy (atrapa `SpeechPort`):
  - tap → słucham → częściowe „średnica dn” → końcowe „średnica dn40” → karta „48,3 mm”, a na Start moduł otwarty (`opened`);
  - to samo w innym module → `offeredChip`, stos tras bez zmian;
  - TTS powiedział tekst;
  - alternatywa N-best wybrana;
  - potwierdzenie zapisu parametru dotykiem i głosem + Cofnij;
  - `touchOnly` ignoruje głos;
  - dwa kolejne konsumenty mowy (nakładka i `AiChatScreen`) dostają `onDone`;
  - `MockClient`: pytanie DN40 przy zgodzie na serwer = 0 żądań HTTP;
  - `pumpAndSettle` w testach pełnej aplikacji kończy się.
- [ ] Commit.

### Zadanie 1.6: Wczesny build i test na telefonie (koordynator)

- [ ] Build `0.5.0+19-pilot` (APK arm64), wysłany przez Firebase App Distribution, z listą 30 fraz w notatkach wydania:
  - 10× DN/ścianka;
  - 5× „otwórz…”;
  - 5× wiedza;
  - 5× zapis parametru;
  - 5× ciche i z hałasem.
- [ ] Prośba do właściciela o wynik („idziemy dalej / stop”). Etap 2 rusza równolegle i nie blokuje się na odpowiedzi; uwagi z testu trafiają do bieżących zadań.

## Etap 2 — Umiejętności modułów (poziom B) i wiedza

### Zadanie 2.0: `FitterToolsScreen` sterowalny (jeden wykonawca dla wszystkich zakładek)

**Files:**
- Modify: `lib/screens/fitter_tools_screen.dart`:
  - `StatefulWidget` + `TabController`;
  - uchwyt-kontener `selectTab(toolId)`;
  - uchwyty wszystkich 8 zakładek (`slope_cut`, `elbow_cut`, `elbow_rotation`, `insert`, `reducer`, `pipe_weight`, `bevel`, `thermal_expansion`), z `supportedFields` i jawnym przeliczeniem.
- Test: `test/assistant/fitter_tools_handles_test.dart` (każda zakładka: `showInModule` → wartości i wynik na ekranie)

### Zadania 2.1–2.4: Umiejętności grup

Każda umiejętność obejmuje:
- plik `lib/assistant/skills/<grupa>/<x>_skill.dart`, rejestrowany w `lib/assistant/skills/<grupa>/catalog.dart`;
- korpus ≥ 6 trafień i ≥ 3 odrzuceń (PL + EN), w tym odrzucenia przeciw innym grupom;
- `ShowInModule` tylko z polami z `supportedFields` danego uchwytu (test kontraktu);
- `source` z domeny.

| Zadanie | Grupa / id umiejętności | Uchwyty stron |
|---|---|---|
| 2.1 | `fitter_tables`: `pipe.weight`, `steel.weight`, `units.convert`, `elbow.takeout`, `sanitary.tube` | SteelWeightPage, QuickConverterScreen, ElbowTakeoutScreen, SanitaryTubeScreen (pipe_weight z 2.0) |
| 2.2 | `fitter_routes`: `pipe.slope`, `rolling.offset`, `bevel.geometry`, `thermal.expansion`, `elbow.cut`, `insert.length`, `reducer.cut` | PipeSlopeScreen, RollingOffsetScreen (zakładki z 2.0) |
| 2.3 | `welder_calc`: `heat.input`, `preheat.ce` (w `heat_input`), `cooling.t85`, `shade.number`, `power.duty`, `power.cable`, `tungsten.pick` | CoolingTimePage, ShadePage, PowerSourcePage, TungstenScreen (HeatInput z 1.4) |
| 2.4 | `welder_misc`: `bolt.torque`, `timer.start` / `timer.stop` / `timer.cool` (narzędzie `welder_calculators`, `WeldTimerService`), `glossary.term` | BoltTorqueScreen (`markReady` po `_loadPrefs`), WelderToolsScreen (zakładka timera), GlossaryPage |

### Zadanie 2.5: Wiedza z danych modułów (grupa `knowledge_modules`)

Umiejętności tylko odpowiadają, z odsyłaczem do modułu. Wszystkie dane pochodzą z istniejących plików domeny.

| Umiejętność | Pytanie | Źródło danych |
|---|---|---|
| `defects.causes` | „przyczyny porowatości przy MAG” | `lib/data/weld_defects.dart` |
| `iso5817.limit` | „ile podtopienia na poziomie B” | `lib/domain/iso5817/*` |
| `electrodes.exposure` | „ile elektroda 7018 może leżeć poza suszarką” | `lib/domain/welding/electrode_exposure.dart` |
| `rigging.colour` | „zielony pas ile ton” | `lib/domain/rigging/rigging_colors.dart` |
| `grinding.stripe` | „czerwony pasek na tarczy” | `lib/domain/grinding/*` |
| `fume.oel` | „NDS manganu” | `lib/domain/fume/fume_hazards.dart` |
| `filler.pick` | „spoiwo do 316L” | `lib/domain/filler/filler_selector.dart` |
| `shade.quick` | (odpowiedź z `computeShade`, jeśli nie ma w 2.3) | |

- [ ] Korpusy jak wyżej. Odpowiedź zawsze z nazwą normy z domeny.

## Etap 3 — Rysowanie ISO

### Zadanie 3.1: `IsoNotebookController` (ścieżka C)

**Files:**
- Create: `lib/screens/iso_notebook_controller.dart` (`part of 'iso_notebook_screen.dart'`)
- Modify: `lib/screens/iso_notebook_screen.dart` (rejestracja kontrolera/uchwytu w `initState`/`dispose`; pole `_ghost`; kursor; dopasowanie widoku; `ready`)
- Test: `test/screens/iso_notebook_controller_test.dart` (asercje przez kodek z bazy, jak `iso_notebook_autosave_test`)

**Interfaces — Produces:**
```dart
/// Indeks kierunku siatki (_isoHeadings): 0 prawo, 1 góra (oś III = pion), 2 do tyłu, 3 lewo, 4 dół, 5 do przodu.
enum IsoDir { right, up, back, left, down, forward }
sealed class IsoStep { const IsoStep(); }
class IsoPipe extends IsoStep { const IsoPipe({this.dir, this.lengthMm}); final IsoDir? dir; final double? lengthMm; }
class IsoTurn extends IsoStep { const IsoTurn({this.toDir, this.dn}); final IsoDir? toDir; final int? dn; }   // zamiar skrętu dla następnej rury
class IsoFitting extends IsoStep { const IsoFitting(this.tool, {this.dn, this.dnOut}); final String tool; final int? dn; final int? dnOut; }  // flange, blindFlange, cap, reducer, gateValve, ballValve, checkValve, globeValve, butterflyValve, weld, support — osiowe, na kursorze
class IsoDrawReport { final List<String> assumedPl, assumedEn; final IsoDrawProblem? problem; final int segments, elbows, fittings; }
enum IsoDrawProblem { reversal, sameDirectionAfterTurn, trailingTurn, unsupported45, unsupportedTee, outOfCanvas }
class IsoNotebookController extends ChangeNotifier {
  Future<void> get ready;
  bool get hasContent; String? get sketchName; DateTime? get lastEdited;
  Future<void> startNew();                         // _flushSave() → _startBlankSketch(persist: false)
  /// Wykonuje sekwencję jako JEDEN krok Cofnij; zatrzymuje się na pierwszym problemie (bez częściowego zapisu).
  Future<IsoDrawReport> draw(List<IsoStep> steps, {Duration stepDelay = const Duration(milliseconds: 300)});
  void undo();
}
```

**Reguły:**
- Kursor:
  - pusty szkic → start przesunięty tak, żeby rysunek nie wyszedł nad górę siatki;
  - niepusty → wolny koniec ostatniej rury.
- Rura bez kierunku:
  - pierwsza: w prawo;
  - po `IsoTurn` bez kierunku — skręt domyślny: right/left → forward; forward/back → right; up/down → right;
  - zawsze dopisywany do `assumed`.
- Rura bez długości = 3 kroki siatki, bez wymiaru. Z długością: wymiar `_CutCalc('<mm>')` i liczba kroków `clamp(round(mm / 500), 2, 8)`.
- Kolano powstaje automatycznie (`_maybeInsertElbows`). DN z `IsoTurn` → `withElbowSpec` (CTE z `isoStandardElbowCteMm`).
- Problemy (zatrzymują przed problematycznym krokiem; nic nie zapisują):
  - zawrócenie;
  - ten sam kierunek po skręcie;
  - skręt na końcu;
  - 45°, trójnik;
  - wyjście poza płótno.
- Animacja: `_ghost` rośnie w 4 krokach przez `stepDelay` (w testach `Duration.zero`), potem `_mutate`. Po całości dopasowanie widoku.

- [ ] Testy:
  - `[IsoPipe(), IsoTurn(), IsoPipe()]` → 2 odcinki, 1 kolano, kierunki right → forward, `assumed` niepuste;
  - jeden `undo()` cofa całość;
  - niepusty szkic: start na końcu ostatniej rury, stary szkic w bazie bez zmian;
  - `lengthMm: 1500` → wymiar „1500”;
  - zawrócenie → `problem: reversal`, nic nie dodane;
  - skręt na końcu → `trailingTurn`;
  - rysowanie „w górę” blisko krawędzi → widok dopasowany, punkty siatki ≥ 0;
  - gest palca w trakcie animacji nie psuje `_ghost`.
- [ ] Commit.

### Zadanie 3.2: Umiejętność `iso.draw` (po 1.3, 1.4, 3.1)

**Files:**
- Create: `lib/assistant/skills/iso/iso_command_parser.dart`, `iso_draw_skill.dart`, `catalog.dart`
- Modify: `lib/screens/iso_notebook_screen.dart` (`ToolHandle` zeszytu: pola `steps` (lista), `new_sketch` (bool))
- Test: `test/assistant/skills/iso/iso_command_parser_test.dart`, `test/assistant/iso_draw_flow_test.dart`

**Gramatyka:**
- `rura|rurę|rurka|rury` [długość] [kierunek];
- `kolano|kolanko|łuk` [90] [kierunek], gdzie kierunek to zamiar skrętu;
- „kolano 45” i „trójnik” → zgłoszenie niewspieranego elementu;
- `kołnierz|zaślepka|dennica|redukcja [DN na DN]|zawór (kulowy|zasuwa|zwrotny|grzybkowy|przepustnica)` [DN];
- kierunki: w prawo / w lewo / w górę / w dół / do przodu / do tyłu (+ północ / południe / wschód / zachód przy strzałce N);
- polecenia: „nowy rysunek”, „cofnij”, „zmień ostatnie kolano w górę” (= cofnij ostatnie polecenie + odtwórz zapamiętaną listę z poprawką).

**Wynik:**
- `AnswerResult` z opisem: co narysowano, co przyjęto, problem;
- `show: ShowInModule('iso_notebook', {'steps': [...]})`;
- chipy „w górę / w dół / do przodu / do tyłu” dla ostatniego skrętu.

**Zasady:**
- Gołe „rura kolano rura” bez „narysuj/dodaj do rysunku” liczy się jako `iso.draw` tylko z premią kontekstu (zeszyt otwarty).
- Zeszyt zamknięty, a ostatni szkic niepusty i < 12 h → `AskResult('target', „Dorysować do «X» czy nowy rysunek?”)`.

- [ ] Korpus:
  - „narysuj rura kolanko rura” → [pipe, turn, pipe];
  - „rura dwa metry w prawo kolano w górę rura metr” → kierunki i długości (2000, 1000);
  - „rura 2” → 2000 i informacja „przyjąłem 2 m”;
  - „dodaj zawór kulowy dn50” → `IsoFitting('ballValve', dn: 50)`;
  - odrzucenia: „ile waży rura dn50” (`pipe.weight`), „zapisz spawam rurę dn50 141 80 amper” (`legacy.save`).
- [ ] Test przepływu: wypowiedź → zeszyt otwarty → 2 odcinki i kolano → „w górę” → kolano w górę → „cofnij” → stan sprzed.
- [ ] Commit.

## Etap 4 — Rekordy, pytania o własne dane, pokrycie

### Zadanie 4.1: Rekordy (poziom C)

Umiejętności:
- `hot_work.prepare` i `confined_space.prepare`: miejsce, opis prac, nr zezwolenia, osoby; `safetyCritical`, `touchOnly`;
- `interpass.reading`: temperatura do bieżącej spoiny; `touchOnly` nie jest wymagane, ale jest potwierdzenie;
- `hardness.convert`: przelicznik, do odczytu;
- `quote.new`: nowa wycena z materiałem, schematem i miejscem, potem otwarcie.

**Mechanizm:**
1. `X.blank(...).copyWith(<pola z białej listy>)`.
2. `ConfirmResult`.
3. `store.upsert`.
4. `openToolById` + strona edycji z `initial:`.
5. Cofnij → `store.delete`.

- [ ] Test białej listy: JSON rekordu po umiejętności == JSON `blank()` poza polami z białej listy (w tym `checked`, `na`, pomiary, gotowość nietknięte).

### Zadanie 4.3: Pytania o własne dane (do odczytu, lokalnie)

| Umiejętność | Pytanie | Źródło |
|---|---|---|
| `certs.expiry` | „kiedy wygasa moje uprawnienie 141” | `welder_certificates` (DAO) |
| `instruments.due` | „kiedy kalibracja” | `instruments` |
| `progress.today` | „ile cali-średnic dziś” | `work_progress` |
| `electrodes.status` | „ile jeszcze mogą leżeć elektrody” | dziennik ekspozycji |
| `journal.last` | „ostatnia spoina” | `weld_journal` |

- [x] Testy rzeczywistych danych: `useTestDatabase()` dla certyfikatów, przyrządów, dziennika i postępu; SharedPreferences dla faktycznie zapisywanych tam partii elektrod.

### Zadanie 4.2: Pokrycie liczone z katalogu (koordynator, na końcu)

**Files:** Create `lib/assistant/assistant_coverage.dart` (`Map<String, AssistantTier> assistantCoverage()` — z katalogu i rejestru, bez ręcznej mapy); Test `test/assistant/assistant_coverage_test.dart`.

Test sprawdza, że:
- (a) każde id z `kToolRegistry` ma co najmniej poziom A;
- (b) `open_tool` trafia z tytułu PL i EN każdego narzędzia;
- (c) `explain` daje niepusty opis;
- (d) każda umiejętność ≥ B ma ≥ 3 przykłady, które przez CAŁY mózg trafiają w nią, a `run` nie rzuca;
- (e) dla każdego `ShowInModule` z przykładów pola ⊆ `supportedFields` uchwytu (rejestr uchwytów dostarczany w teście przez otwarcie stron).

## Etap 5 — Feedback

### Zadanie 5.1a: Biblioteka feedbacku (ścieżka E, bez UI)

**Files:**
- Create:
  - `lib/feedback/feedback_signal.dart` (model + JSON = fixture `test/fixtures/feedback_signal_v1.json`, ten sam plik kopiowany do `backend/test/fixtures/`);
  - `complaint_detector.dart` (`FeedbackKind? classify(String folded, {required bool lastTurnFailed})`, rodzaje `explicit`, `complaint`, `cantFind`, `notUnderstood`, `error`);
  - `redact.dart`;
  - `feedback_store.dart` (SharedPreferences `feedback_queue_v1`, limit 300; automatyczne wypadają najstarsze z licznikiem; jawne nigdy; kopia uszkodzonego zapisu);
  - `feedback_uploader.dart` (partie ≤ 20; bez zgody 0 żądań; 404/5xx → zostaje w kolejce; nagłówek `X-Feedback-Id`);
  - `feedback_consent.dart` (`feedback_consent_v1`, domyślnie false; zapis daty polityki `kLegalUpdated` przy zgodzie; losowy `feedback_install_id`);
  - `lib/config/app_version.dart` (`kAppVersion` + test zgodności z `pubspec.yaml`).
- Test: `test/feedback/*`.

- [ ] Detektor:
  - „ta apka nie działa” → `complaint`;
  - „spawarka nie działa” bez nieudanej tury → null;
  - „gdzie jest kalkulator…” → `cantFind`;
  - „zgłoś problem: …” → `explicit`.
- [ ] Maskowanie: „+48 600 100 200”, „600100200”, „jan@x.pl”, ciąg 9+ cyfr → `***`.
- [ ] Commit.

### Zadanie 5.2: Backend (ścieżka D, repo `backend/`, worktree w tym repo)

**Files:**
- Create: `src/routes/fitterFeedback.js`:
  - `POST /api/fitter/feedback`: Zod `.strict()`, partia ≤ 20, tekst ≤ 500, limity: na `feedback_id` 50/dobę, globalnie 5000/dobę, wierszy łącznie ≤ 200 000;
  - `GET /api/fitter/feedback/admin`: `requireAdmin` z `fitterChat.js`, stronicowanie `since`, `limit` ≤ 500, filtr `kind`, `tool`.
- Modify:
  - `src/db/schema.sql`, `src/db/repos.js`;
  - migracja `SCHEMA_VERSION = '4'` + `migrate.test`;
  - `src/services/housekeeping.js` (retencja 180 dni);
  - `src/services/dataErasure.js` + `src/routes/fitterMe.js` (kasowanie po `X-Feedback-Id`);
  - `src/routes/publicPages.js` (sekcja „Zgłoszenia problemów”, ta sama treść co `legal_texts.dart`);
  - `src/app.js`;
  - `README.md`.
- Test: `test/feedback.test.js` (walidacja, partia 21 → 400, limity → 429, admin bez tokenu → 404 przy pustym `ADMIN_TOKEN` i 401 przy złym, kasowanie, retencja, fixture).

### Zadanie 5.1b: Integracja feedbacku w aplikacji (po 1.5 i 5.1a)

**Files:**
- Create: `lib/feedback/feedback_sink_impl.dart` (`FeedbackSink`: nierozpoznane ×2 w 3 min = 1 sygnał; narzekanie; błąd); `lib/feedback/report_problem_sheet.dart` (podgląd, „Wyślij”, zgoda per zgłoszenie); `lib/assistant/skills/feedback/feedback_skill.dart` + `catalog.dart` („zgłoś problem …”).
- Modify:
  - `lib/main.dart` (`FlutterError.onError`, `PlatformDispatcher.instance.onError` → sygnał `error` z typem i modułem, z zachowaniem `debugPrint`);
  - `lib/widgets/help_button.dart` („Zgłoś problem z tym modułem”);
  - `lib/assistant/ui/assistant_overlay.dart` (karta zgody po 3× „nie rozumiem”; propozycja zgłoszenia maks. 1/sesję i 1/dobę, nigdy po udanej odpowiedzi);
  - `lib/screens/profile_screen.dart` (zgoda, „Moje zgłoszenia”, „Usuń moje dane” czyści kolejkę i zgodę oraz woła kasowanie na serwerze);
  - `lib/legal/legal_texts.dart` (sekcja „Zgłoszenia problemów”, `kLegalUpdated`; `kLegalVersion` bez zmian);
  - `lib/config/backend_config.dart`.
- Test: `test/feedback/integration_test.dart`, `test/legal_*` zaktualizowane (z `publicPages.js`), `test/store/privacy_manifests_test.dart`.

### Zadanie 5.3: Raport dla właściciela

**Files:**
- Create: `tool/feedback_digest.dart`:
  - `--since 7d`, token z env `FITTER_ADMIN_TOKEN`;
  - wynik do `%USERPROFILE%\Documents\FitterFeedback\<data>.md` (POZA repo): moduł × rodzaj, liczności, top frazy nierozpoznane (kandydaci na umiejętności), błędy po typie.
- Create: `tool/feedback_digest_mail.py`: wysyłka raportu mailem przez SMTP z vaulta na adres właściciela, uruchamiana ręcznie albo z harmonogramu, jeśli właściciel zgodzi się na zadanie cykliczne.
- Test: `test/tool/feedback_digest_test.dart` (grupowanie na danych z fixture).

## Etap 6 — Odbiór

- [ ] Pełny `flutter test`, `flutter analyze`, `npm test` w backendzie.
- [ ] Przegląd kodu każdego zadania (`feature-dev:code-reviewer`), poprawki z testami.
- [ ] Audyt modułów: nowe strony w manifeście (jeśli są).
- [ ] `docs/NOWOSCI-2026-10.md` + teksty sklepów.
- [ ] Deklaracje App Privacy i Data Safety (feedback): punkt osobny, PRZED wysłaniem buildu do sklepu.
- [ ] Wdrożenie backendu nocą:
  - kopia `fitter.db`;
  - deploy z klonu z LF;
  - `/health`;
  - test `POST /feedback`;
  - potem aplikacja (przy 404 trzyma kolejkę).
- [ ] Build 0.5.0+19 → Firebase App Distribution (Android) + Codemagic (iOS) → mail do właściciela z listą testów.
- [ ] Ręczny test na telefonie wg mierników spec §2.1:
  - DN40 w ciszy i przy szlifierce;
  - „narysuj rura kolanko rura”, „w górę”, „cofnij”;
  - zapis parametru „tak, zapisz” i Cofnij;
  - „zgłoś problem”;
  - zgoda wyłączona = 0 wysyłek.


## Stan kontynuacji — 2026-10-20 (pilot, nie pełny odbiór etapów 1–6)

- Odzyskano niescalone poprawki rdzenia z worktree Claude'a ae0306298a1aca922
  i testy przeglądu. Domknięto opisy rozbieżności OD pomiędzy tabelami oraz
  odrzucenie dopasowania ogólnego FAQ do pytania z konkretnym pomiarem.
- AiChatScreen pyta lokalny mózg przed starym silnikiem; zapisy i dziennik
  nadal mają istniejące potwierdzenia. Lokalne odpowiedzi, pytania, chipy
  kontynuacji i pokazanie DN/Sch w module. Domyślna zdalna klasyfikacja
  w trybie Wykonaj wyłączona; tryb odpowiedzi zachowuje dotychczasową zgodę.
- Globalna nakładka z własnym Overlay: rozmowa pozostaje zamontowana przy
  nawigacji, panel do 40% ekranu, polecenia głosowe wykonywane po końcowym
  wyniku STT, wspólny systemowy STT/TTS, ukrycie nad dialogami i kamerą,
  Wstecz najpierw zwija panel. DN/Sch piloty przyjmują początkowe pola;
  pełny ToolBridge/ToolHandle z whenReady nadal do implementacji.
- Odzyskano parser ISO af0909ea4a926da74 i połączono go z kontrolerem:
  otwarcie zeszytu, rysowanie na żywo, dorysuj/nowy/anuluj na niepustym
  arkuszu, Cofnij, „w dół”/zmiana ostatniego kolana. Korekta ma walidację
  przed modyfikacją i odmawia po ręcznej zmianie. Nieobsługiwane 45°,
  trójniki i strony świata nie modyfikują rysunku.
- Rejestrator brakujących możliwości: maskowana lokalna kolejka feedbacku,
  deduplikacja sesji, automatyczna wysyłka tylko przy osobnej zgodzie.
  Brak wdrożenia backendu feedbacku, UI zgody i panelu konta administratora.
- Korpus porównawczy modeli: test/assistant/fixtures/model_comparison_v1.json
  (22 scenariusze PL/EN). Żadnych płatnych wywołań ani wyboru dostawcy.
- Wymagania kont na Railway, profilu zawodowego i prywatnych raportów admina
  dopisane do specyfikacji. Nie podłączono Firebase Auth.
- Kolejne: test mikrofonu na Androidzie/iOS, pełny ToolBridge, pojedynczy
  stan rozmowy także przy wejściu z kafla asystenta, ustawienia/N-best,
  kolejne umiejętności, UI zgody, konta/profil/admin Railway; test modeli.


## Kontynuacja 2026-10-20 — most do modułów i energia liniowa

- ToolBridge/ToolHandleHost: uchwyty per instancja trasy, gotowość dopiero po
  ustawieniach, timeout, odrzucanie nieobsługiwanych pól. Polecenia nie idą
  do ukrytej kopii tego samego modułu. Popup blokuje także polecenie czekające
  na ustawienia. Zmiany pól są walidowane w całości przed zastosowaniem.
- Piloty: DN ↔ mm, Grubości ścianek/Sch oraz Heat input. Bieżący moduł jest
  aktualizowany w miejscu. Przejściowe ekrany kalkulatorów otwarte przez
  asystenta są zastępowane, a ręcznie otwarty obcy moduł pozostaje bez zmian
  (przycisk „Pokaż w module”). Bez zastępowania Zeszytu ISO z rysunkiem.
- Kafel ASYSTENT na Start otwiera istniejącą rozmowę w globalnym panelu.
  Dostępny jest przełącznik czytania odpowiedzi i wynik odczytu Moich parametrów.
  Pełny ekran pozostaje zgodnym adapterem dla samodzielnego wejścia/testów.
- Umiejętność heat.input: obliczenia z domeny, wartości z jednostkami,
  dopytywanie o prąd/napięcie/prędkość/proces/EN lub ASME; sprawność z WPS
  jako 0,8 lub 80%; sprzeczne/zerowe/niepoprawne liczby blokują wykonanie.
  „Ustaw 250 A” w kalkulatorze zmienia wyłącznie prąd. Ten sam proces,
  konwencja i sprawność trafiają do ekranu, więc wynik zgadza się z kartą.
  Zmiana procesu/konwencji usuwa nieaktualny zakres WPS z widoku, bez zmian
  w zapisanej bibliotece WPS i bez wpisów do dziennika.
- Korpus porównania modeli rozszerzony do 25 scenariuszy; bez płatnych API.
- Backend: sprawdzono istniejące osobne repo i czystą gałąź feedbacku
  D:/wt/fwp-backend-feedback (5fb551c). Zwykły CLI nieautoryzowany;
  RAILWAY_API_TOKEN z vaulta odrzucony przez railway list (401).
  Nie tworzono serwera, kont ani wdrożenia. Przed deployem odświeżyć OAuth
  lub zweryfikować projektowy RAILWAY_TOKEN (także istnieje w vaulcie).
- Następne: konta/profile/admin na istniejącym Railway, UI zgody i lista
  zgłoszeń, kolejne grupy umiejętności i odbiór mikrofonu na telefonie.

Walidacja etapu: pełny przebieg 5715 PASS; najnowsze przepływy 13 PASS; heat.input 7 PASS; analyze bez uwag; build web PASS. Produkcyjny /health HTTP 200; nie wykonywano deployu.

## Stan realizacji — 2026-10-20 (po wdrożeniu kont)

Ten wpis aktualizuje historyczne notatki powyżej; nie oznacza ukończenia całej wizji.

- Railway: osobny projekt Fitter, trwały wolumen `/data`, schemat SQLite 5.
  Backend `main` `1081eb5`, PR #1 połączony. Deployment
  `cdc127e7-3d01-44dd-8fae-8b1eef627d8a` przeszedł i zachował dane po restarcie.
  Realny HTTP potwierdził konta, profile, zmianę hasła/unieważnienie sesji,
  usunięcie konta testowego i dostęp do raportów: admin 200, user 403, anon 401.
  Raport kontrolny potwierdził maskowanie na serwerze i zmianę statusu.
- Wspólny panel rozmowy i ToolBridge działają. Wszystkie osiem zakładek
  FitterToolsScreen ma uchwyty, walidację i jawne przeliczenie.
- Grupa 2.1 ma lokalne umiejętności i sterowanie ekranami: `pipe.weight`,
  `steel.weight`, `units.convert`, `elbow.takeout`, `sanitary.tube`.
  Masa stali wypełnia draft kalkulatora, bez dodania pozycji ani zmiany cen listy.
- Grupa 2.2: działają `pipe.slope`, `rolling.offset`, `bevel.geometry`,
  `thermal.expansion`, dodatkowe `slope.cut` i `reducer.cut`.
  Działa również `elbow.cut` (pomiar całych łuków, oznaczenia cięcia i reszta).
  Działa `elbow.rotation`: OD albo obwód, stopnie albo procent, korekta
  konkurencyjnych danych w rozmowie i wypełnienie rzeczywistej zakładki.
  Działa `insert.length`: dwa jednakowe kolana, rodzina tablicowa lub ręczny R,
  jawny kąt/offset/szczelina na każdą spoinę, wynik cięcia i wypełnienie zakładki.
- Z grupy 2.3 działają `heat.input`, `shade.number`, `cooling.t85`, `preheat.ce`,
  `power.duty`, `power.cable` i `tungsten.pick` (zakres tabeli DC− nierdzewnej).
  Z grupy 2.4 działa bolt.torque; pozostają timery i glossary.term.
  Grupa 2.5 wymaga implementacji i sprawdzenia rzeczywistych efektów.
- Podstawowe ISO rysuje/dorysowuje/cofa i chroni przed niejasnymi zmianami.
  Zakres etapu 3 należy zweryfikować z kodem i uzupełnić, nie uznawać za zakończony.
- Nadal potrzebne są pełny etap 4 (odczyt/zapisy oraz manifest pokrycia),
  domknięcie wszystkich ścieżek zgłoszeń i końcowy odbiór etapu 6.
- Brak tabeli w rozpoznanej umiejętności może zwrócić
  `FailedResult.reportMissingCapability`. Taki raport jest lokalnie maskowany,
  deduplikowany i wysyłany tylko zgodnie z osobną zgodą. Błędne wymiary nie
  tworzą raportu brakującej funkcji.
- Jawne oblicz/przelicz/skróć/trim przechodzi do kalkulatora także z innego
  ekranu. Negacje nie wykonują działania. Polecenie skracania redukcji nie
  trafia do rysowania kształtki w ISO.

Dowody: testy poszczególnych umiejętności w `test/assistant/`, testy rzeczywistych
formularzy i przejść w `tool_bridge_flow_test.dart` / `fitter_tools_handles_test.dart`.
Najnowsza regresja redukcji: 1119 PASS, analiza zmienionych plików czysta.
Pełny checkpoint `4f8359c`: 5911 PASS, web build i debug APK Androida przeszły.
Nowsze moduły są sprawdzane regresjami; starszy APK nie zawiera późniejszych zmian.
Test mikrofonu na urządzeniu i końcowy build całej wizji pozostają do wykonania.

Cięcie kolanka: testy umiejętności i rzeczywistego ekranu, korpus routera oraz
regresja asystent/domena/zakładki: 1134 PASS. Analiza nowych plików czysta.

Obrót kolanka: rzeczywisty ekran pokazuje 100 mm dla obwodu 400 mm i 25%;
regresja asystent/domena/zakładki 1159 PASS, analiza zmienionych plików czysta.

Wstawka: wspólne `insertBetweenElbows` przeniesione z ekranu do domeny
(reexport zachowuje istniejące importy). Tabela 45° LR używa B, segment używa
A × tan(θ/2); odpowiedź opisuje podstawę. Brak dodatniego cięcia nie wypełnia
ekranu. Brak rodziny w tabeli uruchamia ścieżkę raportu brakującej możliwości.
Regresja asystent/domena/kalkulatory/zakładki: 1198 PASS, analiza czysta;
osobno sprawdzona pełna rozmowa przełączająca kalkulator do zakładki wstawki.

Filtr przyłbicy: `shade.number` używa `computeShade` i `shadeShareText` z domeny,
bez skracania ograniczeń tabel. Procesy łukowe: prąd z jednostką; MIG wymaga
rozróżnienia metalu. Procesy gazowe: przepływ z jednostką czasu lub grubość,
bez wymyślania danych do drugiej tabeli. Jednostki l/min przeliczane na l/h,
liczby słowne obsługiwane. Cyfry prądu nie stają się kodem procesu; kody wymagają
etykiety proces/process/metoda. ShadePage ma atomowy uchwyt i czyści nieaktualne
pola poprzedniego procesu. Jawne dobierz/select/pick otwiera kalkulator;
negacja dobierz/dobieraj/select/pick nie wykonuje polecenia. Pełny czat i formularz
sprawdzone; regresja assistant+shade UI+domena: 1125 PASS, analiza czysta.

Czas stygnięcia: `cooling.t85` używa `coolingTime` i `checkT85Window`, zachowuje
przedział 2D spoin pachwinowych. Q bezpośrednie z jednostką lub obliczone z
parametrów i sprawności EN; energia łuku ASME wymaga wyjaśnienia/EN. Podanie
obu źródeł Q wymaga jawnego wyboru. Temperatura, grubość i rodzaj spoiny nie
są przyjmowane domyślnie.
Puste okno WPS czyści przykładowe 5–15 s na ekranie i daje brak oceny zgodności;
granice jednostronne, min/max i okno „od 5 do 15 sekund” obsługiwane. Błędne
lub sprzeczne okno wymaga poprawki. Słowne t osiem na pięć, kilodżul na milimetr
i stopnie Celsjusza działają w testach. Atomowy uchwyt CoolingTimePage waliduje
całość przed zmianą. Jawne polecenie przełącza stronę w pełnym czacie. t8/5
nie jest przejmowane przez heat.input nawet na ekranie energii liniowej.

Czas stygnięcia: regresja assistant + cooling UI + domena 1138 PASS, analiza
zmienionych plików czysta. Osobne testy pełnej rozmowy i umiejętności 26 PASS.

2026-10-21 — CE/podgrzewanie: własna analiza C/Mn/Cr/Mo/V/Ni/Cu albo jeden
gatunek z MaterialCatalog; dane katalogowe jawnie nazwane jako typowe. Brakujące
pierwiastki nie są zerowane bez polecenia; „pozostałe zero” zachowuje wcześniej
podane wartości. Gatunek i własna analiza razem wymagają wyboru źródła.
CE IIW, Seferian i nienormatywna reguła CE korzystają z istniejącej domeny.
Stale nierdzewne i Cr-Mo mają komunikat o nieprzeznaczeniu metod CE/Seferiana,
bez wyznaczania nimi temperatury; dla gatunku dostępne minimum B31.3 ≥ 2014
jest osobno nazwane i wskazuje potrzebę sprawdzenia wydania projektu.
Uchwyt HeatInputScreen przyjmuje pełny skład i grubość atomowo, otwiera CE,
czyści dawny wybór DN/SCH i parametry łuku. Brak podanych HD/Q nie uruchamia
metody B na domyślnych danych; HD wymaga jawnego wyboru. Polecenie heat.input
wraca do pierwszej zakładki. Pełny czat cooling→CE i formularz sprawdzone.

CE/podgrzewanie: regresja assistant + HeatInput UI + preheat domena 1220 PASS,
analiza czysta. Osobno umiejętność i pełny czat: 19 PASS.

2026-10-21 — `power.duty`: 1–3 jawne pary prąd A/cykl % z tabliczki i osobny
prąd spawania. Wspólne computeDutyCycle/powerSourceShareText/dutyAmbientNote;
zaokrąglenia ostrożne i pierwszeństwo tabliczki zachowane. Powyżej największego
prądu z tabliczki: wynik poza zakresem zamiast ekstrapolacji. Niepełne dodatkowe
wiersze i niezwiązane procenty nie są pomijane. Prąd spawania nie może stać się
punktem tabliczki tylko dlatego, że stoi przy nim procent. Korekta tabliczki
zastępuje cały zestaw. Mowa słowna A/procent działa w testach.
PowerSourcePage ma atomowy uchwyt gotowy po asynchronicznym odczycie zapisanej
tabliczki. Polecenie wypełnia draft bez zapisu tabliczki w SharedPreferences;
usuwa stare dane instalacji przewodów, których użytkownik nie podał dla tego
obliczenia. Pełny czat CE→power_source, rzeczywisty wynik i ochrona zapisu
sprawdzone. Regresja assistant+power_source UI+domena: 1204 PASS.
Analiza zmienionych plików power.duty czysta.

2026-10-21 — `power.cable`: sprawdzanie przekroju i dobór najmniejszego z
checkCable/sizeCable. Jawne A, długości obu przewodów, cykl %, temperatura C,
próg V; dla sprawdzania mm². Nie zgaduje połowy długości pętli ani progu 4 V.
Temperatura pomiędzy kolumnami używa konserwatywnie wyższego przedziału „do”
z podaniem tego w odpowiedzi. Wynik zachowuje spadek, nagrzewanie i źródła domeny.
Brak spełniającego przekroju do 95 mm² nie daje fikcyjnego zalecenia; formularz
odznacza poprzedni przekrój. AC/inny model przewodu/aluminiowe przewody trafiają
do ścieżki brakującej możliwości. Wzmianka o aluminiowym spawanym materiale nie
zmienia automatycznie materiału przewodów. Mowa z milimetrami kwadratowymi działa.
PowerSourcePage rozszerza uchwyt atomowo; nie miesza pól tabliczki z instalacją,
nie zapisuje SharedPreferences i czyści starą tabliczkę przy nowym poleceniu kabli.
PowerDuty nie przejmuje cyklu pracy przewodów. Jawne sprawdź/check/size wykonuje
obliczenie i przejście do ekranu; negacje tych czasowników zatrzymują wykonanie.
Zastrzeżenie domeny rozróżnia 40°C źródła od 25°C odniesienia tabeli przewodów.
Pełny czat i widoczny formularz sprawdzone; regresja assistant+power UI+domena:
1239 PASS, analiza czysta. Dodatkowa korekta rozróżnienia materiału spawanego
i przewodów ma osobny test umiejętności.

2026-10-21 — `tungsten.pick`: shared sizeForCurrent/tungstenExtrasFor, jawna
biegunowość DC− i stal nierdzewna. Samo DC wymaga doprecyzowania. Materiał,
prąd z jednostką i rozbieżne dane zbierane w rozmowie; liczba 304 A nie jest
automatycznie gatunkiem 304. Granice 70/80/150/250 zachowują wybór większej
średnicy wspólnej tabeli. Dodatki dysza/argon/szlif są punktami startowymi,
przepływ dotyczy palnika. ISO 6848 nazwane jako oznaczenia typów, nie źródło
pasm prądowych. Wskazany WT20 zachowuje notę o pyle z tabeli; WP/WZ8 nie
stają się doborem do nierdzewnej DC−. WC20 ma opis, ale brak osobnej tabeli
prądowej w tym modelu lantan/tor. AC/DC+/inny materiał i 15–400 A poza tabelą
uruchamiają brakującą możliwość zamiast ekstrapolacji skrajnego wiersza.
Atomowy uchwyt TungstenScreen przyjmuje tylko wspierany prąd, czeka na prefs,
nie zapisuje magazynu, historii nadpisań ani oznaczeń złącza/stempla. Pełny
czat power_source→tungsten sprawdzony. WelderCalc ma wspólny katalog grupy.
Regresja assistant+tungsten UI+dane: 1250 PASS. Kolory czubka są rozpoznawane
z tego samego źródła co kody typów; nieznany kod nie jest zastępowany WL20,
a niejednoznaczny typ można jawnie pominąć po pytaniu.
Pełny checkpoint wykrył jeden skopiowany parser przecinka w shade.number.
Zastąpiono go parseDecimal i dodano test grupowanych cyfr przepływu
„1 500,5 l/h” oraz konfliktu z drugą wartością. Testy wspólnego parsera,
filtra i wolframu po korekcie: 73 PASS.
Pełny checkpoint 2026-10-21 po wszystkich korektach: 6360 testów całej aplikacji
PASS, pełna analiza Flutter bez uwag. To checkpoint kodu, nie końcowy odbiór
fizycznego mikrofonu ani aktualny build APK; te pozostają w etapie 6.

2026-10-21 — `bolt.torque`: śruba calowa UNC/8UN albo preset DN × Class,
jawny gatunek, nazwane smarowanie i preload 30–75% SMYS. Mapy SMYS/K
przeniesione z UI do wspólnej domeny bez zmiany wartości. B8M wymaga jawnego
potwierdzenia klasy 1 (model 207 MPa). Metryczne śruby, nieznane gatunki,
nieobecne rozmiary, klasy B8M i własne K uruchamiają brakującą możliwość;
sprzeczne K/preset jest błędnym wejściem, nie raportem brakującej funkcji.
ASME B16.5/B1.1 nie staje się gatunkiem B16/B1. Wynik dotyczy jednej śruby,
liczba śrub z katalogu nie mnoży momentu. Konflikt rozmiaru z DN/Class wymaga
korekty; ręczna odpowiedź usuwa poprzedni preset.
BoltTorqueScreen ma atomowy uchwyt gotowy po _loadPrefs. Otwarcie nie zapisuje
domyślnych danych przed ich odczytem; odtworzenie i apply asystenta liczą bez
zapisu preferencji. Ręczna edycja zachowuje dotychczasowe autosave.
Pełny czat tungsten→bolt_torque i realny wynik 134 N·m / 134,07 w odpowiedzi
sprawdzone. Test możliwości pokazuje nową komendę w bolt_torque; stwierdzenie
o braku sterowania pozostaje testowane w hydrotest, gdzie nadal jest prawdziwe.
Regresja assistant+bolt UI+domena: 1298 PASS, analiza zmienionego kodu czysta.

2026-10-21 — `glossary.term`: wspólny indeks słownika PL/EN/DE/NL/NO,
wybór dokładnego hasła lub doprecyzowanie wielu wyników (np. podtopienie).
Tłumaczenie wymaga wskazanego języka; sprzeczne języki wymagają pytania.
Atomowy uchwyt otwiera dokładny rekord, rozwija definicję, usuwa stare filtry.
Zmiana języka przez asystenta jest tymczasowa; ręczna zmiana zapisuje preferencję,
a ręczne wyszukiwanie opuszcza tryb dokładnego rekordu. Ulubione zachowane.
Negacja wyszukania zatrzymuje akcję. Regresja 1338 PASS, dodatkowa kontrola
ręcznej zmiany języka i wyszukiwania 24 PASS; analiza zmienionego kodu czysta.
Etap 2.4: słownik i moment śrub wdrożone; timery pozostają do implementacji.
Następny audyt: oddzielić cytowane polecenia do tłumaczenia/wyjaśnienia od akcji
ISO, kalkulatorów i starszej ścieżki zapisu. Samo rozpoznanie słów polecenia
wewnątrz pytania nie może uruchamiać działania. Pełny odbiór wizji nadal otwarty.

2026-10-21 — spójność pytań i akcji: referencesInstruction rozpoznaje prośby
PL/EN o tłumaczenie/wyjaśnienie przed ISO, matcherami obliczeń/zapisu,
kontynuacją i starszym pending slotem. Polecenie wewnątrz pytania pozostaje
tekstem: parseAssistantCommand i AssistantEngine dają answer_question.
Silnik nie wysyła takiego tekstu do zdalnego klasyfikatora intencji; istniejąca
ścieżka odpowiedzi zachowuje zgodę i bramki AI. Lokalny słownik, wiedza i opis
narzędzia pozostają dostępne. Alternatywa transkrypcji bez ramy pytania nie może
wyprzeć głównej prośby o tłumaczenie. Normalny draw/save nadal rozpoznawany.
Pierwsza regresja wykryła blokowanie tool.explain: poprawiono listę dozwolonych
odpowiedzi. Po korekcie assistant+ISO parser:1361PASS, dodatkowe warianty językowe
z korpusem routingu:488PASS; analiza zmienionego kodu bez uwag. To testy lokalnej
klasyfikacji i regresja UI, bez płatnych wywołań AI i bez fizycznego mikrofonu.

2026-10-21 — `timer.start`, `timer.stop`, `timer.cool`: polecenia sterują tym
samym WeldTimerService co ekran i alarmy. Stoper liczy w górę, pauza zachowuje
czas, wznowienie nie zmienia ustawień; przy żądaniu zmiany wymaga „uruchom”.
Nowe odliczanie wymaga czasu z jednostką, obsługuje sumę min+sek i ułamki.
Odrzuca ujemne, zerowe, ponad limit, powtórzone jednostki i osierocone liczby.
Nowe chłodzenie czyści odziedziczony limit 150°C: WPS jest tylko jawnie podanym
limitem, nie pomiarem. Koniec odliczania nadal wymaga pomiaru temperatury / O2.
Zastąpienie lub reset timera z postępem dopytuje. Rewizja sterowania serwisu
unieważnia stare potwierdzenie po ręcznej zmianie; same takty go nie unieważniają.
Nie ma automatycznej kontynuacji timera z gołej liczby. Negacje start/stop/pause/
resume/reset/uruchom/wznów/wyzeruj są obsługiwane przed działaniem.
WelderToolsScreen ma uchwyt gotowy po zbudowaniu kontrolera, payload tab=timer.
Używa tego samego DefaultTabController co ręczne zakładki; zastosowanie odświeża
pola timera z aktualnego serwisu. Nie zmienia pozostałych kalkulatorów.
Pełny czat DN→timer, pauza, odmowa/skasowanie postępu, ponowne pola i negacja:
40 testów UI PASS (wraz z dotychczasowymi testami ekranu i handle). Odbiór
fizycznego mikrofonu i systemowych powiadomień na urządzeniu nadal w etapie6.
Etap2.4 zaimplementowany; następny zakres2.5 wiedza z domeny, później pozostałe
wymagania ISO/rejestrów/pokrycia/raportów i końcowa weryfikacja.
Pełny checkpoint po grupie welder_misc 2026-10-21:6489 testów całej aplikacji
PASS (build/welder-misc-full-app-tests.log), pełny flutter analyze bez uwag
(build/welder-misc-full-analyze.log). Po usunięciu wewnętrznej nazwy trybu z
karty odpowiedzi dodatkowe17testów timera PASS. APK pozostaje starszy; nie
utożsamiać tych testów z odbiorem fizycznego mikrofonu lub systemowego alarmu.

2026-10-21 — `defects.causes` (etap2.5): odpowiedzi z defectAdvice i
buildDefectShareText, tych samych co moduł wad spoin. Przyczyny, sprawdzenia,
naprawa, BHP, zastrzeżenie WPS/procedury i adresy źródeł pozostają z domeny.
Proces i materiał zbierane w rozmowie, bez wyboru na podstawie samego amperażu.
FCAW bez rozróżnienia 114/136 dopytuje. Rozbieżne materiały/pozycje dopytują;
para nieobecna w bazie uruchamia brakującą możliwość zamiast zmiany materiału.
Wspólne numery ISO pęknięć nie rozstrzygają typu: chip przekazuje pełną nazwę.
Liczby słownie i literowane pozycje używają wspólnego tokenizera (141 A nie jest
procesem141, ISO3041 nie jest stalą304L, H-L045 jest pozycją pipeUp).
Odpowiedź opisuje możliwe przyczyny, nie stwierdza faktycznej diagnozy. Warunki
zależne od pozycji pozostają oznaczone. Zakres ISO5817 z udostępniania to VT.
Nowe answersQuestionsOnly umożliwia umiejętnościom wiedzy odpowiedź na „wyjaśnij”
przy zachowaniu ochrony cytowanych poleceń w kalkulatorach/zapisie/ISO.
WelderToolsPage bez zmian; WeldDefectsPage ma atomowy uchwyt defect_id/process/
material/position, waliduje cały zestaw przed zmianą, czyści stary checklist tylko
w pamięci ekranu. Jawne „pokaż przyczyny…” otwiera i wypełnia moduł; zwykłe
pytanie zachowuje zasady pokazywania odpowiedzi/odnośnika w obcym module.
„Porowatość TIG60A” rozpoznawana przed starszym parserem zapisu jako pomoc przy
wadzie, nie zapis parametrów. Pełny czat DN→wady i doprecyzowanie materiału
sprawdzone. Otwieranie wszystkich narzędzi z pełnych tytułów PL/EN zachowane.
Regresja assistant+UI/domena/dane wad:1451PASS; po ochronie krótkiej wypowiedzi
odrębny router+umiejętność+pełny czat561PASS. Analiza zmienionego kodu czysta.
Checkpoint całej aplikacji nadal a105026:6489PASS, nie przypisywać go nowszym
zmianom. Dalej2.5: ISO5817, elektrody, zawiesia, tarcze, NDS dymów, spoiwo;
następnie pozostałe wymagania ISO/rejestrów/pokrycia/raportów/odbioru.

2026-10-21 — `iso5817.limit`: odpowiedzi z iso5817Limit/assessIso5817 oraz
wspólnego buildIso5817Report. Wszystkie nazwy pozycji PL/EN z istniejącej tabeli,
numery ISO6520-1 i identyfikatory pozycji; warianty wymagają wyboru, nie pierwszego
trafienia. Jawne poziom, rodzaj spoiny, t i wymiary używane przez regułę. Krótkie/
długie zbierane z definicją domeny. Nie bierze C, czołowej, krótkiej ani t z UI.
Jednostki pomiaru oddzielają mm od stopni, kąt >180 odrzucony. Liczby słownie,
przecinki i literowane be/ce/de działają; odpowiedź na pytanie o wymiar może być
samą liczbą z jednostką. Kontynuacja „a pomiar 0,4 mm” zachowuje jawnie podane
wcześniej dane w oknie rozmowy; nie uruchamia oceny cytowanych poleceń.
Numery w wymiarach nie stają się kodami wad; kod2011 nie jest automatycznie
rokiem normy. Zwykłe polecenia innych kalkulatorów nie są przejmowane przez ISO,
także na aktywnym ekranie ISO. Zakres RT/UT, fatigue/B90/B125, aluminium/beam,
częściowy przetop i systematyczne niezgodności nie dostają zmyślonego werdyktu.
Źródłowa tabela jest2014. Przed użyciem asystent wymaga2014 w pytaniu lub jawnego
potwierdzenia w rozmowie; inne wydanie trafia do brakującej możliwości. Status
wycofania2014 i zastąpienia2023 sprawdzony2026-10-21 w oficjalnym ISO:
https://www.iso.org/standard/54952.html . Nie przenosić liczb2014 na2023.
Iso5817Page ma atomowy uchwyt item_id/kind/level/t/b/b_root/a/measured/short/
limit_only, czyści stare wymiary i pomiar. Tryb limit_only nie stwierdza obecności
pęknięcia, nie pokazuje werdyktu ani eksportu protokołu. Użytkownik może jawnie
przejść do oceny pomiaru/obecności, albo podać pomiar w rozmowie.
Testy ujawniły wcześniejszą kolizję bare FCAW-G z defects.causes: qualifier G
jest rozpoznany, zapytanie jednoliterowe nie wybiera wady. Dodano szybkie bramki
nazw i cache indeksu ISO. Test wydajności używa prawdziwego WeldTimerService
z atrapą efektów (jak BrainHarness), zamiast wywoływać pluginy bez bindingu.
Nie podniesiono progu: 500 wypowiedzi860ms w regresji,920ms w kontroli dopowiedzenia.
Regresja assistant+ISO UI+domena1474PASS; po dopowiedzeniu dodatkowe29PASS
(umiejętność, pełny czat, performance). Cała grupa2.5 nadal nieukończona:
electrodes.exposure, rigging.colour, grinding.stripe, fume.oel, filler.pick.
Pełny checkpoint aplikacji nadal a105026:6489PASS. Fizyczny mikrofon, systemowe
alarmy i nowy build pozostają w etapie6. Backend w tej zmianie bez operacji.

2026-10-21 — `electrodes.exposure`: referencje czasu ekspozycji i suszenia z
ElectrodeClass/ElectrodeFamily/defaultLimitMinutes/defaultMaxRedries. Wspólny
nowy electrodeReferenceText służy asystentowi i karcie w module. Pokazuje grupę
tabeli, nie podmienia nazwy konkretnego produktu. E7018 bez R, -1, H4R/H8R,
E7018M i grupy niskostopowe mają rozdzielone dane. Bare7018 wymaga wyjaśnienia
wariantu; A1 wypowiedziane ze spacją zachowuje grupę A5.5, nie dostaje limitu R
z A5.1. Sprzeczność H4R/bezR i niejednoznaczne E7018-M wymagają wyboru.
Nieznane/nieobjęte klasy, niskostopowe R i inne wydania/ASME/D1.5 trafiają do
brakującej możliwości. Zawilgocenie nie dostaje werdyktu z samego czasu modelu.
Źródło pochodzenia (piecyk / świeże opakowanie) jest jawne. Wartość referencyjna
wymaga polecenia „model/reference/2020” albo potwierdzenia po wyjaśnieniu zakresu.
Dla EN to jawnie domyślne ustawienie/analogia, nie ogólny limit ustanowiony przez
normę EN; wiążące są karta konkretnego produktu, WPS i wymagania projektu.
Sufiks R i rozbieżność wymagań kodeksu/producenta sprawdzone w pierwotnym
Lincoln Electric MC22-140 12/22 (odczyt2026-10-21):
https://ch-delivery.lincolnelectric.com/api/public/content/c9885a12d37149b985327956ca3c9e97?v=d24abe95
Nie przenoszono danych producenta na tabelę2020 ani nie zmieniano domeny partii.
ElectrodeExposurePage ma uchwyt gotowy po odczycie dziennika i zbudowaniu tabs.
Payloadelectrode_class/origin/reference_only=true pokazuje osobną kartę i wraca
do zakładki stanowiska. Nie tworzy partii, nie zmienia istniejącego limitu,
zdarzeń QC, ekspozycji ani liczby suszeń. Test z własnym limitem17min zachował
cały JSON istniejącej partii. Nowy batch nadal wymaga osobnego przepływu zapisu
(etap4), nie jest ukrytym skutkiem pytania o czas.
Pełny czat otwiera referencję i zachowuje zapis. Oznaczenie słownie używa
wspólnego tokenizera, wszystkie12klas z podpowiedzi są wybieralne. Regresja
assistant+UI/store/domena elektrod1539PASS; osobna końcowa kontrola28PASS obejmuje
warianty, spacje, inne wydanie, wilgoć, wszystkie klasy i ochronę zapisu.
Analiza zmienionego kodu czysta. Test wydajności próbuje teraz równomiernie cały
katalog (zamiast pierwszych500pozycji) po rozgrzaniu indeksów wszystkich grup,
z zachowaniem progu500tur<1s; wynik699ms w regresji.
Dalej2.5: rigging.colour, grinding.stripe, fume.oel, filler.pick; później pozostałe
etapy ISO/rejestrów/pokrycia/raportów i odbiór mikrofonu/build. Ostatni pełny
checkpoint całej aplikacji nadal a1050266489PASS. Backend w tej zmianie nietknięty.

2026-10-21 — rigging.colour i grinding.stripe: lokalne odpowiedzi z istniejących
SlingColour/SpeedStripe i wspólne karty referencyjne otwierane przez ToolBridge.
Kolor tkaniny oznacza referencyjne WLL przy podnoszeniu prostym, kolor etykiety
materiał PES/PA/PP. Pomarańczowy oznacza 10 t i więcej. Brak etykiety = STOP.
Nie wylicza się zgody na rzeczywisty udźwig z koloru. Kolor całej tarczy nie
ustala koloru paska, dwa alternatywne kolory nie oznaczają paska dwukolorowego.
Dopytania czyszczą poprzedni kolor przy przejściu od tkaniny do etykiety.
Uchwyty przyjmują wyłącznie pola reference_*, nie zmieniają WLL, prędkości,
wybranego rzeczywistego koloru, kontroli ani zapisanych preferencji/sprzętu.
Szczególne tarcze i dobór RPM wymagają osobnej funkcji, zgłaszanej jako brak.
Źródła porównane 2026-10-21: DGUV209-021(08/2021), DGUV209-013 rozdz.10,
Klingspor Maximum operating speed; danych liczbowych domeny nie zmieniano.
Regresja początkowa1707PASS i 1FAIL wydajności1060ms przy równoległej analizie.
Przeniesiono szybkie bramki tematu przed analizę zaprzeczenia. Kontrola końcowa
37PASS, w tym pełny czat, doprecyzowania i wydajność579ms/500tur (próg nadal1s).
Analiza zmienionego kodu czysta. Pełna regresja końcowa zapisana oddzielnie.
Dalej grupa2.5: fume.oel i filler.pick. Nadal potrzebne pozostałe sterowanie
kalkulatorami/rejestrami, rozszerzenia ISO, audyt pokrycia/raportów i etap6.
Backend bez zmian; fizyczny mikrofon i finalny build nieodebrane.
Końcowa regresja assistant+rigging+grinding UI/domena:1708PASS (build/colour-reference-final-regression.log).

2026-10-21 — filler.pick: dobór pary materiałów i procesu z selectFiller,
FillerFamily/ProcessFiller/Consumable oraz nowego czystego fillerReference.
Odpowiedź zawiera dostępne oznaczenia EN ISO/AWS, gazy, formowanie, uwagi rodziny
oraz ostrzeżenia obu materiałów; wiążące WPS/projekt. Gatunek pojedynczy wymaga
pytania o B, „ten sam” jest jawnym wyborem; proces również jawny. Wszystkie14
materiałów i4procesy wybieralne. Identyczny gatunek podany dwukrotnie rozpoznany.
Kolejność A/B jest zachowana, także przy mieszanym zapisie słownym/cyfrowym.
141A nie oznacza procesu141. Sprzeczne procesy i „ten sam” przy różnych
materiałach wymagają wyjaśnienia. FCAW bez kwalifikatora nie zakłada136;
114/121/138 oraz nieobjęte gatunki (np.316Ti/904L/S355J2/tytan) nie dostają
podstawienia zbliżonego materiału, także jako odpowiedź na dopytanie.
Brak wariantu spoiwa dla procesu -> FailedResult z raportem braku. Znane
połączenie specjalne/niespawalne łukowo zachowuje werdykt domeny, nie wymyśla
spoiwa. Deskryptywne „TIG with filler…” nadal trafia do legacy.save (test kolizji).
FillerSelectorPage: uchwyt material_a/material_b/process atomowy, gotowy po
zbudowaniu. Wybiera rzeczywiste materiały/proces i zakładkę Dobór, przewija do
góry. Nie zmienia pól Schaefflera/rozcieńczenia. Test zachowuje wpis37 w drugiej
zakładce i odrzuca dodatkowe/niepełne pola. Pełny czat otwiera i wypełnia moduł.
Źródło IMOA3(2014), §12.1.9/tab.16 sprawdzone2026-10-21:
https://www.imoa.info/download_files/stainless-steel/Duplex_Stainless_Steel_3rd_Edition.pdf
Nie zmieniano reguł domeny ani klasyfikacji z katalogu.
Regresja katalog+spoiwo UI/domena+czat671PASS; cała grupa assistant+spoiwo1597PASS.
Po końcowym zachowaniu kolejności/dwukrotnym gatunku dodatkowe14PASS (nowe
przypadki, ochrona drugiej zakładki, perf691ms/500tur<1s). Analiza czysta.
Logi build/filler-assistant-full-regression.log/filler-assistant-final-check2.log/
filler-assistant-final-analyze2.log. Nadal aktywne: fume.oel, następne etapy
ISO/rejestrów/pełnego pokrycia/raportów i finalny build+mikrofon. Backend bez zmian.
Ostatni pełny checkpoint całej aplikacji nadal a1050266489PASS; APK starszy.

2026-10-21 — fume.oel kończy grupę wiedzy2.5. Lokalne odpowiedzi korzystają z
FumeAgent.nds/ndsNote i wspólnego fumeNdsText/fumeOelReference. Ten sam formatter
jest na ekranie i w rozmowie. Polska, mg/m³, frakcje, NDS/NDSCh oraz datowany
stan prawny są jawne. Brak NDSCh != zero; brak zweryfikowanego NDS -> wyjaśnienie
+ reportMissingCapability, bez wymyślonej liczby. Kadm zachowuje załącznik oraz
przepis przejściowy0,004 do11.07.2027, ołów datę9.04.2026, CrVI uwagę o2025.
Oficjalne ELI odczytane2026-10-21: Dz.U.2026/447 (załącznik),2026/1211 (§4),
Dz.U.2020/61 (§2 ust4), https://eli.gov.pl/eli/DU/2026/447/ogl . Liczby domeny
niezmienione; nie deklarowano aktualizacji całej tabeli poza jej datą18.10.2026.
Wybór składnika działa dla wszystkich pozycji. Nie zakładaCrVI dla ogólnego
chromu, ZnO dla cynku, tlenków dla żelaza ani związków niklu dla metalicznego Ni.
Obsługa polskich odmian tlenku/tlenków i słownego „chromu sześć”. „co?” nie
wybiera CO; świadomy wybór z chipu używa jednoznacznego prefiksu składnik.
Inny kraj, inne wydanie, górnictwo/tunele, nieobjęta substancja i ocena pomiaru
wymagają osobnej funkcji/źródła, raportują brak. Nie oznacza się stanowiska OK.
FumePage przyjmuje wyłącznie reference_agent i pokazuje kartę. Nie ustawia
materiału/procesu/LEV/RPE, nie dotyka pól ani listy/pomiarów. Test zachował
wpisany przepływ1357 i cały zapis; dodatkowe pole material jest odrzucone.
Pełny czat pokazuje Mn, scroll do części poza viewportem potwierdza pusty wybór
materiału; NDS glinu tworzy prywatny raport fume.oel i deduplikuje powtórzenie.
Początkowy test czatu błędnie szukał niezbudowanego elementu listy poza ekranem;
naprawiono weryfikację przewinięciem, bez zmiany działania aplikacji.
Korpus+nowe testy653PASS; końcowa kontrola umiejętności/perf27PASS (740ms/500<1s),
pełny czat39PASS przed dodatkowym sprawdzeniem raportu, raport osobno1PASS.
Pełna aplikacja6727PASS (build/knowledge-modules-full-app-tests.log), analiza całej
aplikacji czysta (build/knowledge-modules-final-analyze.log). Po końcowym guardzie
niklu i raportowaniu null wykonano dodatkowe27+1PASS. Ta kombinacja zastępuje
starszy pełny checkpointa1050266489PASS. Backend w tej zmianie bez zmian.
Cel nadal ACTIVE: audyt/rozszerzenie ISO3, rekordy i własne dane4, pokrycie,
audyt raportów5 i odbiór głosu/build6. Rozpoczęto przygotowanie świeżego APK;
nie traktować testów byVoice (transkrypcja) jako testu mikrofonu telefonu.

2026-10-21 — audyt ISO3 ujawnił czat odrzucający strony świata, mimo gotowego
IsoNotebookController.dirForCompass. Dodano czysty IsoCommand.resolveCompass:
kompletne pipe/turn oraz korekta ostatniego skrętu rozwiązują się razem,
zachowują długości/DN; brak orientacji lub błędny indeks/kształtka -> null bez
zmiany oryginału. Czat otwiera docelowy zeszyt, czeka na ready, pyta append/new
przed rozwiązaniem stron świata. Nowy arkusz nie przejmuje strzałki starego;
brak strzałki nie rysuje i nie raportuje błędu programu, prosi o orientację.
„Na zachód” w otwartym ISO poprawia ostatnie kolano według rzeczywistej strzałki.
Dodatkowo pytanie ISO o cel nie połyka mocnego nowego polecenia z katalogu:
nowy side-effect-free brain.recognizesNewCommand (bez wykonania/zapisu/kasowania
pending) działa przed legacy parse przy dopytaniu. Test NDS manganu porzuca
pytanie o arkusz, nie dorysowuje starych kroków po późniejszym „dorysuj”.
Pełny przepływ: N/E z rzeczywistej strzałki, odmowa odziedziczenia N przez nowy
arkusz, poprawka na W, Cofnij. Początkowe testy współdzieliły SQLite szkice;
fixture czyści tylko testową tabelę iso_drawings i zamyka UI w tearDown.
Docelowe testy: iso-controller-acceptance.log34PASS (cały globalny ISO, kontroler,
autosave) + iso-compass-preflight-check.log5PASS. Dodatkowy nowy-target1PASS.
Analiza pięciu zmienionych plików czysta: build/iso-compass-final-analyze2.log.
Szersza regresja build/iso-compass-regression.log NIEZAKOŃCZONA:1643 ukończonych
przypadków bez błędu, ostatni tool_bridge_flow missing-table; sesja90243 nadal
live. Processflutter_tester51372, listener zaimportował tool_bridge_flow_test.
Nie restartowano procesu na podstawie braku obserwacji. Następna tura ma
sprawdzić tę samą sesję (nie zgłaszać pełnego PASS), ew. zdiagnozować końcowy
prywatny raport. Inne testy akceptacji kończą się poprawnie.
Nadal braki ISO: valveTypeMissing dostaje ogólną odmowę zamiast dopytania;
45/tee unsupported (manualne dostępne), nowe rysowanie walidowane dopiero po
startNew może zmienić aktywny arkusz przy błędzie. Katalog nie ma iso.draw
adaptera; coverage4.2 nie zaimplementowane, rekordy4 i audyt5/6 nadal potrzebne.
Pełny checkpoint całej aplikacji6727PASS i APK pozostają e7cd1d4 (ostatni APK
nie zawiera tej poprawki kompasu). Backend bez zmian. Cel ACTIVE.

2026-10-21 — ISO dopytuje o zawór zamiast zgłaszać brak funkcji. Czyste
IsoCommand.chooseValve uzupełnia pierwszy placeholder, zachowuje wszystkie
rury, kierunki, długości i DN; usuwa tylko właściwe valveTypeMissing.
Kulowy/zasuwa/zwrotny/grzybkowy/przepustnica PL/EN, bezpośrednia odpowiedź oraz
„narysuj/dodaj zawór <typ>” w dopytaniu zachowują całą sekwencję. Jawne DN/NPS
może zmienić rozmiar tylko tego zaworu. Sprzeczne typy, negacja, nieznane DN,
wiele DN, liczby bez jednostki/etykiety i dodatkowe elementy nie są zgadywane.
„Return” bez non nie oznacza automatycznie zaworu zwrotnego. Dwa nieokreślone
zawory mają dwa kolejne pytania; przed kompletem nic nie jest rysowane.
Czat pokazuje5chipów+Anuluj, zachowuje polecenie w _pendingIsoValve. Anulowanie,
negacja, odniesienie/wyjaśnienie i nowy niezależny zamiar czyszczą je bez rysowania.
Reset akcji czyści też oba oczekiwania ISO. Pełny zapis ma żądany rodzaj iDN50,
Cofnij usuwa całą sekwencję wraz z kształtkami. Kontrola dwóch zaworów DN50/DN80
obejmuje naturalne odpowiedzi „narysuj zawór kulowy” i „dodaj zawór zwrotny”.
Naprawiono harness: seedFreshInstall/pozostałe testowe ziarna preferencji
resetują FeedbackStore._tail i FeedbackConsent._pendingId przez istniejące
resetForTest. Kolejka/Future po poprzedniej fake-async zone przeżywała podmianę
SharedPreferences i blokowała await list(), zarówno końcowy tool_bridge_flow
jak i nowe testy ISO. Po zidentyfikowaniu źródła zakończono tylko potwierdzone
własne zablokowane workery:51372 stary90243,50108 stary46342. Obie sesje terminalne
exit1, NIE PASS. Zestaw tool_bridge_flow po poprawce kończy się normalnie.
Nie restartowano na podstawie samego braku output; listener obu PID zweryfikowany.
Dwa pierwsze testy chipów początkowo klikały starą pozycję przed klatką layoutu
po ensureVisible. Dodano pumpAndSettle i hitTestable; wszystkie5 przechodzą
prawdziwym tap, bez wywoływania callbacku poza UI.
Kontrole: iso-valve-fixed-tests.log23PASS; końcowy pełny globalny dialog z2
zaworami i Cofnij build/iso-valve-final-undo-check.log11PASS. Cała aplikacja
6756PASS (build/iso-valve-full-app-tests.log), perf619ms/500<1s, cała analiza
czysta (build/iso-valve-final-analyze.log). To zamyka nieukończoną regresję
z poprzedniego checkpointu. Ostatnie doprecyzowanie jawnej odpowiedzi i resetu
zweryfikowane w końcowych11 testach rozmowy.
Nadal ACTIVE, backend bez zmian. APK pozostaje e7cd1d4 (nie zawiera e16aab5 ani
tej zmiany). Następny konkretny brak: draw(newSketch) powinien najpierw
zweryfikować nową sekwencję na pustym arkuszu; obecny startNew przed draw może
przełączyć aktywny arkusz nawet dla błędnej trasy. Następnie45/tee, katalogISO/
pokrycie, rekordy4 i własne dane, audyt5, finalny build i realny mikrofon6.

2026-10-21 — nowe ISO tworzone dopiero po pełnej walidacji pustego arkusza.
IsoNotebookController.draw(...,newSketch:true) wykonuje synchroniczny
_planOnBlank przed flush/startNew. Tymczasowo puste items/takeout/lastDN/gap są
zawsze przywracane w finally; historia, wersja, ID, nazwa i zapis nie są ruszane.
Błędna trasa (reversal/trailingTurn/tee) pozostawia aktywny stary szkic, bajty
JSON, lastEdited i undo; także ArgumentError z nieznanego narzędzia przywraca
oryginał. Poprawny nowy szkic zapisuje poprzedni i zeruje osie/pamięć DN dokładnie
jak startNew; nie dziedziczy północy ani DN80. Cofnij nie przechodzi do starego.
Wspólny prywatny _startNew zawiera dotychczasowy zapis przed przełączeniem,
publiczny startNew zachowuje kontrakt. Pusta nowa sekwencja nic nie przełącza;
„nowy arkusz” bez elementów nadal używa jawnego startNew.
Czat przekazuje newSketch do draw zamiast najpierw czyścić arkusz. StateError
przy zapisie/odmontowaniu nie zostawia busy=true: komunikat zachowuje rysunek
albo informuje o zamkniętym zeszycie. Nie ma deklaracji narysowania przy błędzie.
Realna SQLite w testach: BEFORE UPDATE trigger RAISE(FAIL) wymusza błąd zapisu.
Stare elementy zachowane, pole polecenia ponownie aktywne; po DROP TRIGGER
kolejne dorysowanie i zapis działają. Trigger dotyczy wyłącznie pamięciowej bazy
fixture, kasowany w tearDown. Log błędu jest oczekiwanym wynikiem testu.
Sprawdzenia: build/iso-new-atomic-final-tests.log42PASS; pełna regresja
assistant+controller+autosave1670PASS (build/iso-new-atomic-regression.log);
wyjątek osobno1PASS (build/iso-new-atomic-exception-check.log). Analiza całej
aplikacji czysta (build/iso-new-atomic-final-analyze.log). Starszy pełny
checkpoint całej aplikacji pozostaje36a2551:6756PASS; nie przypisywać tego
licznika późniejszej zmianie. Backend bez zmian, APK nadal e7cd1d4.
Cel ACTIVE. Następne: obsługa45/tee dostępnych ręcznie lub jawna mapa pokrycia
ISO, brakujący katalog iso.draw, rekordy4.1 i własne dane4.3, computedcoverage4.2,
audyt raportów5, finalny build i realny mikrofon6. Nie zwężać pełnej wizji.

2026-10-21 — ISO: jawne umieszczanie symbolu kolana45 i trójnika, zgodne z
manualnym narzędziem. Audyt _maybeInsertElbows potwierdził: zmiana każdej osi
ISO oznacza90° w przestrzeni, kolano45 wymaga osobnej decyzji o pochyleniu.
Nie zamieniono pełnej trasy45 na trasę90. Nowy IsoFitting.symbolOnly dopuszcza
wyłącznie samodzielne umieszczenie elbow45/tee, bez automatycznej rury/odnogi.
Polecenia „wstaw/umieść/narysuj symbol…” i EN place/add/insert/put symbol działają
bez otwartego ISO. SymbolOnly, DN/DNout i orientacja zachowują się przy opisie,
serializacji isoStepsToUtterance i ponownym parsowaniu. Zwykłe żądanie trasy
z kolanem45/trójnikiem nadal jest jawnie nieobsłużone i raportowane. Czat
podpowiada istniejące polecenie symbolu, nie twierdzi że narysował odnogę.
IsoFitting.dir oraz resolveCompass obsługują jawną orientację symbolu, także
strzałkę N. Zwykłe kształtki bez symbolOnly nadal nie przyjmują mapy kompasu.
Kolano zapisuje elbowSubtype=lr45 i CTE z DOKŁADNEGO wiersza kElbowTakeouts,
bez closestByDn/przybliżenia. Brak wiersza -> brak CTE, prośba o kartę.
Trójnik zapisuje withTeeSpec: DN przelotu/odnogi, główne CTE z TakeoutCatalog.tee,
bez fałszywego elbowSubtype ani długości korpusu. Gałąź nie jest rysowana.
Samodzielne symbole są edytowalne na ekranie i Cofnij usuwa całą operację.
DN0/ujemne/niejednoznaczne -> input warning bez raportu funkcji; nieznane DN i
odgałęzienie większe od przelotu -> invalidFittingSize bez zmiany rysunku.
Nowa walidacja occupiedSymbol chroni przed nałożeniem na istniejącą kształtkę,
przed utworzeniem undo/mutacją; przypadek sprawdzony przez bazę i Cofnij.
Pierwsze testy wykryły brak symbolOnly i DNout w serializacji mowy — naprawione.
Kontrole: rozbudowana regresja assistant+controller+autosave1682PASS
(build/iso-symbols-regression.log), końcowe parser/kompas/referencje22PASS
(build/iso-symbols-final-parser-check.log), jawne wstaw/umieść + zapis + Cofnij
2PASS (build/iso-symbols-final-placement-check.log). Testy rozmiarów/kierunku i
rozmowy24PASS wcześniej. Cała analiza czysta (build/iso-symbols-final-analyze2.log).
Cel ACTIVE, backend bez zmian; APK nadal e7cd1d4, pełny checkpoint aplikacji
36a2551:6756PASS. Ta zmiana NIE kończy pełnego prowadzenia tras45 i odgałęzień.
Nadal potrzeba katalogu iso.draw/pokrycia i pozostałych operacji ISO, rekordów4.1,
własnych danych4.3, coverage4.2, audytu raportów5, finalnego build/realnego mikrofonu6.

2026-10-21 — prowadzenie odgałęzienia od istniejącego trójnika. IsoCommand
fromLastTee/explicitLastTee i controller.draw(...fromLastTee) wskazują rzeczywisty
węzeł tee, nie wolny koniec ostatniej rury. „Od trójnika rura metr w górę”
(EN from the last tee pipe...) po zbudowaniu prostego przelotu rysuje3.leg.
Kierunek jest jawny; brak -> pytanie w czacie z zachowaną długością i dalszymi
krokami. Błędny kierunek przelotu zachowuje pytanie; krótka poprawka ponawia
odgałęzienie, nie zmienia poprzedniej trasy. Anulowanie/nowy zamiar/referencja
czyści pending. Kilka tee wymaga jawnego „od ostatniego trójnika”; wybór nie
jest zgadywany. Samotny tee, brak prostego przelotu, kierunek w osi, zajęta
odnoga albo branch+newSketch są odrzucane atomowo, bez wyczyszczenia arkusza.
Planner wyznacza przeciwległą parę faktycznie podłączonych rur, wymaga2legs,
ustawia punktstartu tee i DN z dnOut (lubrun). _PlannedBranch aktualizuje
kierunki i kropki spoin razem z rurą jako1Undo. Kopia tee zachowujeDN80/DN50,
CTE, etykietę i całą specyfikację. Kierunek i połączenia trójnika renderują się
wzdłuż rzeczywistych osi. CUT nadal rozpoznaje role run/branch z geometrii.
Naprawiono znaleziony błąd _maybeInsertElbows: count3 dodawał2.tee pomimo
istniejącej ręcznej kształtki. Guard hasExisting&&!canReplaceElbow spełnia
już istniejący komentarz; zachowuje trójnik i jego rozmiary. AutoTEE dla pustego
węzła i zastąpienie automatycznego kolana nadal działają.
Korekta kierunku prostej odnogi oraz korekta ostatniego kolana na trasie
odnogi ponownie planują odTEEniezależnie od ostatniego wolnego końca. Flagi
ostatniego polecenia i jawnego wyboru tee są zachowane. Cofnij przywraca cały
przelot i wcześniejszą orientację tee, nie dodaje drugiego trójnika.
Parent iso_notebook_screen zachował formatowanie poza małymi nowymi blokami
(uniknięto niezwiązanych1822linii formattera).
Kontrole: szczegółowe53PASS, pełna aplikacja6782PASS
(build/iso-branch-full-app-tests.log), ostatnie dialogi/parser/kompas26PASS
(build/iso-branch-final-dialogue-check.log), ponowienie złego kierunku1PASS.
Cała analiza czysta build/iso-branch-clean-analyze.log. Trigger testowej awarii
z poprzedniego zakresu nadal przechodzi, jego log SQL jest oczekiwany.
Cel ACTIVE/backend bez zmian. Do następnego zakresu: spójny inline mainrun
„rura-trójnik-rura” (obecnie sam trójnik dodawany przez symbol i dopiero
przedłużenie przelotu; nie przedstawiać tego jako gotowej1-komendowej trasy),
pełne trasy45 nadal wymagają modelu pochylenia, katalogiso.draw/pokrycie,
rekordy4.1/własne dane4.3, audyt5 i końcowe build/głos6. Rozpoczęto świeży APK;
ADB ostatnio bez telefonu, testy byVoice nie weryfikują fizycznego mikrofonu.


2026-10-21: Inline ISO main run completed. A single pipe–tee–pipe command preserves run DN and outlet DN and is undone as one operation; a following branch starts at that tee. Invalid sizes, conflicting planned fittings, and non-straight tee runs reject atomically. Explicit direction on an inline tee remains unsupported rather than silently ignored. Validation: 1698 assistant/controller/autosave tests PASS (build/iso-inline-tee-regression.log); full flutter analyze clean (build/iso-inline-tee-analyze.log). Existing APK 1e2a13b does not include this increment. Goal ACTIVE: full45 geometry, ISO catalog/coverage, records/own data, report audit, and final device acceptance remain.

2026-10-21: Computed assistantCoverage() from real tool registry + supplied session skill catalog; immutable result, baseline A for all tools, writes C only with actual actions port, no inferred ISO D while separate handler remains. Added contextual PL/EN tool explanation (do czego sluzy / what is this tool for) using foreground module only, explicit named module takes precedence; stale home context ignored. All available modules checked in PL/EN, plus title opening and global router: 655 PASS build/assistant-coverage-final-tests.log. Full analyze clean build/assistant-coverage-final-analyze.log. Coverage plan4.2 is partial: ISO catalog adapter and exhaustive ShowInModule field contract still pending; does not claim all app commands complete. Inline tee previous commit1bc8f5d pushed. Backend unchanged, goal ACTIVE.

2026-10-21: instruments.due implemented in real catalog (TierB, six PL/EN examples). Reads InstrumentDao local SQLite on each question; optional session reader for tests. Generic calibration dates plus specific name/kind/serial filters; Polish manometru inflection and natural EN when is X due for calibration. Numeric serials exact, unmatched selection does not fall back to all. Existing domain dueDate/statusOn used: manual override first, clamped month intervals, overdue/dueSoon/unknown. Deleted items excluded; query never records calibration or changes data. Answer dates absolute with local-register source; empty data is an answer, read failures sanitize details and do not claim missing capability. Added rejestr przyrzadow search alias discovered by rejection corpus. BrainHarness supplies empty isolated reader by default, SQLite tests separately verify actual production default and fresh reload. Validation1722PASS assistant/controller/autosave build/instruments-due-regression.log;5PASS final SQLite build/instruments-due-final-sqlite.log; full analyze clean build/instruments-due-final-analyze.log. No backend/paid API changes. Goal ACTIVE. Remaining own-data:certs.expiry (must preserve continuity/history + journal domain logic, not just nominal expiry), progress.today, electrodes.status, journal.last; records4.1, ISOcatalog/full45, ShowInModule contracts, report audit and final device acceptance. Latest deliveredAPK1e2a13b is older than these increments.

2026-10-21: certs.expiry added to real skill catalog (TierB,6 PL/EN examples). Questions when own qualification/certificate expires, optional exact ISO process number or family name; named natural EN supported. Production reader uses current welder identity stamp and existing certificatesForStamp policy (unstamped legacy belongs to owner, other explicit stamps excluded). Single read transaction reads DAO certificates+full confirmation history+journal; journalWeldsFromRows/journalWeldsFor/evaluateCertificate are authoritative domain calculations. No refresh(), migration, reminder scheduling, confirmation write, or new regulatory logic. Both nominal expiry and continuity shown with absolute assessment day; missing date never implies indefinite validity. Expired date takes precedence even when continuity incomplete. Late signature explicitly does not restore chain. ASME includes only owner/process-matching nondeleted journal rows up to assessment date; ISO continuity still uses confirmation history, not welding. Unknown process no arbitrary fallback,141vs142 exact; TIG family can match both. Empty data normal answer; failed read sanitized/non-gap. New real-SQLite tests verify broken ISO chain/future expiry, history, owner isolation, ASME/deleted/future/other-person/method filtering, missing dates, production fresh reads, readonly data invariants. Validation665 targeted+router PASS build/certificates-expiry-tests.log;1743 full assistant/controller/autosave PASS build/certificates-expiry-regression.log; full flutter analyze clean build/certificates-expiry-final-analyze.log. Backend unchanged,goal ACTIVE. Own-data remaining progress.today,electrodes.status,journal.last; records4.1, ISOcatalog/full45 geometry, exhaustive ShowInModule contracts, reportaudit, final build/device voice. Latest deliveredAPK1e2a13b predates current increments.

2026-10-21: journal.last implemented (TierB,6PL/EN catalog examples). Current welder identity stamp, JournalDAO live read, welder/root/cap exact membership, deleted excluded; unknown stamp never reads all people as own. Latest means maximum valid execution DATE up to today, not weld number/creation order. Domain normalizeWeldDate handles ISO/legacyPL; no date/invalid and future counts shown. Several entries on same latest day shown together, no invented time/order. Optional exact project preserves raw accents/hyphen and case-insensitive names; unreadable project suffix rejects before I/O rather than broadening selection. Retry resets invalidProject flag. Stored status labelled as recorded, not fresh inspection. Read-only: no write/history/repair mutations. Production reads reload after inserts/deletions; read errors sanitized/non-gap, empty data normal; byVoice transcript and quoted/negated no-read tests. Coverage default weld_journal nowB(read), session with actionsC(write). Validation1763 assistant/controller/autosave PASS build/journal-last-regression.log; final local/router/coverage687PASS build/journal-last-final-tests.log; last project-retry/SQLite7PASS build/journal-last-project-correction.log; full analyze clean build/journal-last-final-analyze.log. No physicalmic verification; no newAPK/backend/API change. GoalACTIVE. Remaining own-data progress.today,electrodes.status; records4.1, ISOcatalog/full45model, exhaustive ShowInModule field contract, feedbackaudit, final build and deviceacceptance.

2026-10-21: electrodes.status implemented in real catalog (TierB,6PL/ENexamples). Personal questions read actual SharedPreferences electrode_batches_v1, reuse decodeBatchesDetailed/stateAt/remainingAt/sortActive. Dedicated matcher prevents personal status queries entering theoretical electrodes.exposure; table requests still route there. Generic status lists active batches by domain urgency; explicit ID/location includes closed consumed/scrapped batches. Raw exact location preserves accents; unparseable selection does not broaden. Snapshot read does not mutate preferences or create recovery backup; lossy/wrong-type/corrupt records give sanitized failure, not empty-log or calculated allowance. Empty clean data normal answer; no automatic missing-capability report for malformed input/read errors. Future timestamps cannot yield full allowance. Actual stored limit, paused oven, exceeded-in-oven, re-dry counts/exceeded limit, and closed states shown; subminute remaining/overrun says less than1min rather than zero. Existing domain decoder now marks repaired/clamped/fractional limit or maxRedries, negative/fractional prior exposure/redry counts as lossy (UI recovery values unchanged; existing backup mechanism can preserve originals). Valid legacy defaults preserved. Test prefs production reloads/read-only, variants/loss/future, voice transcript/quoted no-read, and reference routing. Validation1852 assistant+electrode domain/page/store/export+ISO controller/autosave PASS build/electrodes-status-regression.log;69 final domain/page/store/statusPASS build/electrodes-status-final-domain-tests.log;698 final status/routerPASS build/electrodes-status-final-tests.log; full analyze clean build/electrodes-status-final-analyze.log. No backend/AIAPI/deployment change or newAPK. GoalACTIVE. Own-data remaining progress.today; records4.1, ISOcatalog/full45 geometry, exhaustive ShowInModule contract, feedbackaudit and final device/build acceptance. Physical mic still unverified; latestdeliveredAPK1e2a13b predates current increments.

2026-10-21: progress.today działa w katalogu (TierB,6 przykładów PL/EN). Czyta bieżący lokalny dziennik i stempel przez współdzielony readCurrentJournal. Używa ProgressFilter.today oraz summarizeProgress z ekranu Postęp robót; DI to diShare właściciela, ze wspólnymi spoinami dzielonymi równo, NPS z OD i oznaczeniem przybliżeń. Brak OD nie staje się pełnym DI; brak prawidłowej daty jest ujawniony. Status PENDING/NOK także liczy wykonane wpisy według istniejącej definicji modułu. Dokładny projekt zachowuje akcenty i myślniki; nierozpoznany separator nie rozszerza zakresu. Brak stempla nie zwraca wyniku brygady. Pusty zakres daje0, błąd odczytu osobny komunikat bez szczegółów technicznych. Żadnych zapisów postępu/pomiarów/pieniędzy. Nowy gotowy po wczytaniu ToolHandle work_progress przyjmuje wyłącznie project+period=today; świeży odczyt, odrzucenie nieznanego projektu/dodatkowych pól bez częściowej zmiany, otwarcie właściwego zakresu w rzeczywistym ekranie. Własne pytania4.3: wszystkie5 zaimplementowane, dalsze bramki całego celu nadal otwarte. Testy: router705PASS; dane+ekran12PASS; pełna aplikacja6899PASS build/own-data-full-app-tests.log; po drobnej korekcie angielskiego separatora dziesiętnego5PASS build/progress-today-final-tests.log; pełna analiza czysta build/progress-today-clean-analyze.log. CelACTIVE. Pozostają rekordy4.1, katalogISO/full45model, pełne kontrakty ShowInModule, audyt raportów i końcowy odbiór. ADB21.10.2026 bez urządzeń, fizyczny mikrofon niezweryfikowany. Rozpoczynany nowy Android debugAPK, wynik budowania będzie zapisany osobno; backend bez zmian.
