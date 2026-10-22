# Asystent głosowy sterujący modułami — plan wdrożenia (v2)

Aktualizacja 2026-10-22: [parametry spawania przypisane do konta](2026-10-22-owned-weld-parameters.md).
Aktualizacja 2026-10-22: [dobrowolny kontekst zawodowy AI](2026-10-22-assistant-professional-context.md).
Aktualizacja 2026-10-22: [poprawianie wymiarów ISO w rozmowie](2026-10-22-iso-dimension-dialogue.md).
Aktualizacja 2026-10-22: [przyczyny niedostępności AI](2026-10-22-ai-availability-diagnostics.md).
Aktualizacja 2026-10-22: [nazwa ISO, zapis i Cofnij](2026-10-22-iso-sheet-name-and-undo.md).
Aktualizacja 2026-10-22: [szczelina ISO sterowana asystentem](2026-10-22-iso-root-gap-assistant.md).

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

- [x] Test białej listy: JSON rekordu po umiejętności == JSON `blank()` poza polami z białej listy (w tym `checked`, `na`, pomiary, gotowość nietknięte).

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

2026-10-21: W toku przygotowania rekordów4.1 wykryto brak integracji: _localAnswerCard pomijał AssistantAnswer.lines. Dodano etykiety i wartości wszystkich wierszy w przewijanej karcie, ze scaloną semantyką i układem pionowym dla wąskiego ekranu; przycisk Pokaż w module pozostaje przed szczegółami. AssistantAnswer.speechText domyślnie czyta tekst+wiersze; jawna krótka wersja spoken umiejętności zachowana. Dotychczasowe pytania4.3 mają teraz potwierdzenie wartości na prawdziwym ekranie i w atrapie syntezatora, nie tylko w obiekcie wyniku. Nowe testy dla5 pytań, PL/EN,320px,tekst1.3, prawdziwy SQLite+preferencje; scenariusze przewijają rzeczywistą listę. Ujawniły osobny błąd EN: namedExpiry przez backtracking przejmował my/the jako proces w ogólnym pytaniu When does my certificate expire; teraz taki przypadek idzie do ogólnego parsera. Test realnego certyfikatu EN przechodzi. Walidacja8PASS szczegółowe UI+certs build/local-answer-details-final-tests.log;1811PASS assistant+ISOcontroller/autosave build/local-answer-details-final-regression.log; analiza czysta build/local-answer-details-clean-analyze.log. UWAGA: hot_work.prepare nie zostało jeszcze dodane. Przeczytane HotWorkPermit.blank/copyWith i HotWorkStore.upsert/delete: wymagany whitelist, touchOnly, Cofnij. Potrzebne najpierw rzeczywiste wykonanie generycznego ConfirmResult w AiChatScreen (_tryLocalCommand aktualnie oddaje je starej ścieżce, a _localAnswerCard ich nie obsługuje); bez tego sama rejestracja nowego skilla C nie wykona polecenia. Nie uznawać tego za gotowe. Do rekordów trzeba też otworzyć edytor zapisanej pozycji i zabezpieczyć Cofnij przed skasowaniem późniejszych ręcznych zmian. CelACTIVE, pozostały pełny zakres4.1/ISOcatalog/full45/kontrakty/audyt/finaldevice. Backend bez zmian; nowyAPK z poprawką wierszy będzie budowany osobno.

2026-10-21: hot_work.prepare działa w głównym katalogu jako pierwszy nowy zapisC z4.1. Komenda „przygotuj protokół prac gorących” pyta o miejsce i opis; opcjonalne jawne etykiety z dwukropkiem pozwalają podać numer zezwolenia, wykonawcę, zabezpieczającego, dozór i wystawiającego. Whitelist: blank(now).copyWith tylko7 danych organizacyjnych. Kontrole/na/pomiary/progi/czasy/data/workTypes/notes spoza whitelist nie są kopiowane z slotów. Szkic nie daje gotowości ani autoryzacji pracy; data dziś, zmiana dnia przed potwierdzeniem odrzuca. Dwa różne przypisania tego samego pola lub >1000 znaków dają błąd zamiast zgadywania. Nowa rzeczywista obsługa ConfirmResult w AiChatScreen: widoczne podsumowanie z wierszami, Zapisz/Anuluj, touchOnly odrzuca tekstowe/głosowe tak; zwykły ConfirmResult może przyjąć yes po pokazaniu podsumowania. Guard lokalnego zapisu i unieważnianie starego podsumowania, brak równoległego wykonania; błędy callbacku ukrywają szczegóły, retry ręczny. Błąd otwarcia modułu po zapisie nie przedstawia zapisu jako niewykonanego. Cofnij przyciskiem lub jawną komendą „cofnij zapis”/„undo save” (nie przejmuje go ISO); błędy cofania nie udają usunięcia. HotWorkStore.insertNew używa istniejącej kolejki, odrzuca uszkodzoną historię, istniejące ID i pełną historię bez nadpisywania/przycinania. deleteIfUnchanged usuwa wyłącznie identyczny potwierdzony szkic, nie późniejsze ręczne dane/pomiary ani inne protokoły. Historia asystenta zapisuje kind hot_work.prepare, pokazuje właściwy tytuł i undone. ToolHandle HotWorkPage permit_id gotowy po odczycie otwiera rzeczywisty edytor zapisanej pozycji; oryginalna trasa edytora ukrywa panel, po powrocie rozmowa i Cofnij pozostają. Chroni to również przed cofaniem przy otwartym edytorze. Dziedziczona ścieżka starych parametrów/dziennika zachowana; jawny nowy skill ma pierwszeństwo przed parserem legacy. Testy: router720PASS; logika7 i GUI3 =10PASS; końcowe logika/GUI/ISO28PASS build/hot-work-prepare-final-undo-tests.log; regresja assistant+hotworkdomain/page/export+ISOcontroller/autosave1902PASS build/hot-work-prepare-final-regression.log (--concurrency=2). Performance500 wypowiedzi686ms w regresji (osobno693ms). Naprawiono fixture router_perf: ponowne budowanie domyślnego katalogu nie używało atrap czytników i mierzyło błędne platformoweI/O; teraz używa pełnego izolowanego katalogu BrainHarness, próg1s bez zmian. Oryginalny wcześniejszy run1899PASS/-1perf nie był zaliczony; finalna regresja zamyka błąd. Analiza czysta build/hot-work-prepare-final-clean-analyze.log. CelACTIVE, backend bez zmian. Pozostałe4.1: confined_space.prepare, interpass.reading, hardness.convert, quote.new; ISOcatalog/full45, pełne kontrakty ShowInModule, audytfeedback i końcowy odbiór/mikrofon fizyczny. Nowy APK będzie zapisany osobno.

2026-10-21: confined_space.prepare dodane do głównego katalogu (TierC,6 przykładów PL/EN, readOnly=false/safetyCritical=true/touchOnly). Polecenie „przygotuj protokół przestrzeni zamkniętej” pyta o miejsce i opis; jawne etykiety pozwalają podać numer pozwolenia, wchodzących, asekurującego, nadzór, wystawiającego i ratownictwo. Wyłącznie8 pól organizacyjnych blank(now).copyWith; porównanie pełnegoJSON dowodzi, że procesy/checked/na/pomiary/progi/maxAge/requiredGases/date/notes nie są przejmowane z slotów. Nie zmienia zakresu gazów ani oceny, brak stanu readyToEnter. Powtórzone sprzeczne pola i >1000znaków odrzucone, zmiana dnia przed potwierdzeniem wymaga nowego szkicu. Nowe insertNew/deleteIfUnchanged w ConfinedSpaceStore korzystają z istniejącej kolejki: bez nadpisania ID, uszkodzonej lub pełnej historii; Cofnij nie usuwa późniejszych zmian/pomiarów ani innych rekordów. Historia asystenta kind confined_space.prepare ma właściwy tytuł oraz undone. ToolHandle ConfinedSpacePage(record_id) gotowy po odczycie otwiera zapisany rekord w rzeczywistym ConfinedSpaceEditPage. Wspólna ścieżka ConfirmResult z hot_work zachowana. Testy: router736PASS;9PASS modele+nativeGUI build/confined-space-final-dialogue-tests.log, w tym surowe etykiety8 ról PL/EN, własne pomiary przy Cofnij, pełna/uszkodzona historia, data i kolizjaID;2011PASS cała grupa assistant+oba domain/features bezpieczeństwa+ISOcontroller/autosave build/confined-space-prepare-regression.log (--concurrency=2), performance500wypowiedzi758ms; pełna analiza czysta build/confined-space-prepare-clean-analyze.log. Backend/AIAPI bez zmian, celACTIVE. Nadal interpass.reading, hardness.convert, quote.new; ISOcatalog/full45model, pełne kontraktyShowInModule, audytfeedback i finalne urządzenie/mikrofon. Nowy APK zostanie zapisany osobno.

2026-10-21: Dodano hardness.convert (Tier B) do katalogu welder_calc. Dialog PL/EN zbiera wartość+skalę źródłową, skalę docelową i jawny materiał; bez domyślnego materiału, bez ekstrapolacji ani orzekania zgodności. Oblicza istniejącym convertHardness (ISO18265:2013 tab.A.1); nierdzewna/austenityczna odrzucona przy zmianie skali, ujemne/niejednoznaczne wartości i wiele skal docelowych wymagają korekty. ShowInModule hardness przekazuje value/scale/material do rzeczywistej HardnessPage. ToolHandle odrzuca cały nieprawidłowy zestaw, chroni wpisane ręcznie pomiary przed zmianą materiału; nie zmienia limitu ani serii. Testy805PASS router+asystenttwardości+domain/features, potem10PASS końcowy dialog+GUI z ochroną ręcznych danych. Pełna analiza czysta build/hardness-clean-analyze.log. Trwa szeroka regresja assistant (build/hardness-assistant-regression.log). CelACTIVE: nadal interpass.reading,quote.new,ISOcatalog/full45,pełne kontraktyShowInModule,audytfeedback,finalne urządzenie/mikrofon. Backend bez zmian.

2026-10-21: Końcowa regresja hardness.convert:1847PASS cały test/assistant (--concurrency=2), build/hardness-assistant-regression.log; router500wypowiedzi698ms. Końcowy10PASS dialog+ToolHandle obejmuje ochronę własnych wpisanych pomiarów przy próbie zmiany materiału.805PASS wcześniej domain/features/router; analiza czysta. Backend bez zmian, najnowszy APK pozostaje e32a40c (nowa konwersja dotąd w kodzie, nie w tamtym APK). Następne interpass.reading: jawna spoina/ścieg/temperatura/jednostka/metoda, zachowanie WPS, podsumowanie/potwierdzenie/Cofnij i ochrona przed równoległą zmianą. CelACTIVE.

2026-10-21: interpass.reading wdrożone (Tier C, readOnly=false, zwykłe ConfirmResult — potwierdzenie przyciskiem ALBO „tak/yes”, zgodnie z4.1; nie safetyCritical). Jawne temperatura+jednostka C/F, ścieg, metoda kontakt/pirometr/kredka, czas teraz lub RRRR-MM-DD GG:MM; kredka wymaga stopiła/nie stopiła, nie udaje odczytu dokładnego. Liczby słowne przez wspólny tokenizer; ujemna temperatura dopuszczona zgodnie z domeną, ułamkowy/ujemny ścieg i niejednoznaczne liczby odrzucone. Opcjonalna uwaga:/note: (do1000znaków) zachowana bez interpretowania liczb i poleceń z jej treści. Identyfikacja aktualnej otwartej karty przez nowe RecordModuleContext/RecordToolHandle; wybór bieżącej karty utrwalany na początku dialogu. Po numerze spoiny odczyt dokładny, kilka kart → wybór, brak karty nie tworzy fikcyjnej spoiny. InterpassStore.replaceIfUnchanged serializowane, odmawia uszkodzonych danych/kolizjiID/późniejszej zmiany; zapis dopisuje wyłącznie rzeczywisty przekazany pomiar + updatedAt, bez zmiany WPS/limitów/starszych pomiarów. Cofnij przywraca oryginalny rekord tylko jeśli po zapisie nie było żadnej edycji; nie usuwa całej spoiny. Historia z własnym tytułem, byVoice i undone. InterpassPage(weld_id) otwiera właściwy InterpassWeldPage, nazwany tool:interpass i dostępny globalnej rozmowie; obserwacja udanych zapisów odświeża listę i pomiary w edytorze bez nadpisania równoległej lokalnej edycji. Testy22PASS finalne dialog+realnyGUI (przycisk, tak, otwarta karta bez powtarzania numeru, Undo, kredka, Fahrenheit, wpis wsteczny, konflikt edycji, równoległe potwierdzenia, uszkodzenie, notatka, wybór numerów i słowne liczby), build/interpass-assistant-voice-confirmation-final.log. Finalna regresja1940PASS test/assistant+features/interpass+domain/welding/interpass_log_test.dart, build/interpass-assistant-final-regression.log (--concurrency=2), router500wypowiedzi628ms. Pełna analiza czysta build/interpass-assistant-final-clean-analyze.log. Wcześniejszy run1938PASS/-2 miał kod/testy odczytywane podczas zmiany touchOnly i NIE jest uznany za zaliczenie; końcowy pełny run zamyka te różnice. Backend/płatneAPI bez zmian. Brak urządzeń ADB i brak AVD2026-10-21 — fizyczny mikrofon nadal niezweryfikowany. CelACTIVE: quote.new (money-path-review), ISOcatalog/full45, pełne kontraktyShowInModule, audytfeedback i końcowy odbiór. Nowy APK zawierający również hardness.convert2550779 będzie zapisany osobno.

2026-10-21: quote.new zaimplementowane w głównym katalogu (Tier C, ConfirmResult z potwierdzeniem przyciskiem lub tak/yes). Wymaga jawnego materiału, schematu (kolejno grań/wypełnienie) i miejsca; brak domyślnych wyborów tych3danych. Opcjonalne etykietytytuł/klient/notatka do1000znaków; nie interpretuje pieniędzy/procesów z metadanych. Schemat rozpoznaje aliasy proces+numerISO bez podwójnego procesu, odrzuca alternatywy TIG lub MMA i nieznany składniknp.TIG+138. Kopiuje ratesFor(material),validityDays,purgeByDefault z modelu/native szablonu, status zawszeDRAFT, bez spoin/dodatków/kwoty oferty/samodzielnej wysyłki. Summary pokazuje materiał,schemat,miejsce,source szablonu (zapisany lub domyślny, brakujące ceny modułu), rzeczywiste stawki spawacz/monter,VAT,purge. Nowe QuoteSettingsStore.loadForAssistant odrzuca uszkodzony/złotypowy/ujemny/stratny szablon zamiast cichego podstawienia innych cen; poprawne starsze częściowe szablony zachowują wartości i jawnie dopuszczają brakujące domyślne pola. WeldQuoteDao.insertNewDraft: atomowa alokacja nextQuoteNumber i INSERT ABORT w transakcji, skanuje także kosz, numer nie zmienia się wstecz; IDkolizja nigdy nie REPLACE. createdAt/updatedAt z zegaraDAO w chwili zapisu. Cofnij=softDeleteIfUnchanged: porównuje cały SUROWY wiersz (w tym data_json/sumy/status/metadane), sprawdza boolwyniku; ręczna zmiana ceny/tytułu,statusSENT lub uszkodzenie JSON blokują cofnięcie, numer zachowany w koszu. Localhistory quote.new ma własny tytuł/byVoice/undone. ToolHandle QuoteListPage(quote_id) otwiera istniejący QuoteEditPage zakładkaDane, store notifier odświeża listę. Przywrócono spójność rozmowy: ukryty AssistantOverlay nie zamyka panelu przy zablokowanym PopScope edytora; po powrocie jest ta sama rozmowa i Cofnij. Computedcoverage doc poprawione: domyślny katalog ma lokalne zapisy, tylko legacy wymaga osobnego portu.
Testy:2046PASS assistant+features/quotes+domain/quotes build/quote-assistant-regression.log (--concurrency=2), router500wypowiedzi619ms; następnie805PASS końcowy skill+nativeGUI+globalrouter build/quote-assistant-final-money-check.log, obejmuje pełnySQLJSONwhitelist, stawki snapshot po zmianie szablonu, równoległe numery/ID, numer po Cofnij, uszkodzony JSON, note niewykonywana, powrót do rozmowy i ręczną edycję. Końcowa pełna analiza czysta build/quote-assistant-final-money-analyze.log. Ścieżka pieniędzyA: idempotencja zapisu/konflikty, sprawdzany wynik Undo, snapshot stawek, brak faktycznych płatności/APIbudżetów. DowódB ograniczony do rzeczywistegoSQLite i produkcyjnych widgetów w testach; NIE wykonano jeszcze na uruchomionym buildzie/telefonie. Nie ogłaszać finansowego odbioru produkcyjnego na podstawie samych testów.
Ostatnie805PASS dodają guard jawnej prośby o stawkę/cenę/VAT/rabat lub kwotęPLN/zł: quote.new NIE ignoruje tej części i nie zapisuje innej kwoty z szablonu; FailedResult(reportMissingCapability:true), brak zapisu. Edycja tych pól przez asystenta jest jeszcze nieobsługiwana, nativeedytor ją ma — uwzględnić to w audycie pełnego zakresu/pokrycia4.2 i raportach5. Nie udawać pełnej kontroli całego modułu tylko z faktu TierC. Krok4.1 whitelist test [x]; cała wizja nadalACTIVE. Pozostaje ISOcatalog/full45, pełne kontrakty/zakres poleceń4.2, audytfeedback5, odbiór żywego buildu/mikrofon/iOS6. Backend/Stripe/płatneAI bez zmian; nowy APK zostanie zapisany osobno.

2026-10-21: Dodano iso.draw do wspólnego katalogu przez nowe skills/iso/iso_draw_skill.dart i catalog.dart. Produkcyjny AiChatScreen przekazuje CallbackIsoDrawingPort (isForeground/hasPendingQuestion/execute); to AssistantBrain wybiera i wykonuje ISO, usunięto niezależne wywołanie _tryIsoCommand PRZED mózgiem. Istniejący, sprawdzony workflow kontrolera/nawigacji pozostaje wykonawcą portu. _collectIsoReply przechwytuje rzeczywisty wynik kontrolera/dialogu, dzięki czemu UI/TTS odpowiada raz przez wspólną ścieżkę. Match jest czysty, nie otwiera zeszytu, run wywołuje port dokładnie raz z wybraną wypowiedzią (w tym N-best). Brak portu → brak umiejętności D w domyślnym/headless katalogu; po podłączeniu portu runtime ma rzeczywiste iso.draw TierD. Testcoverage potwierdza A→D i powrót po odłączeniu, dokumentacja coverage aktualna. FakeIsoDrawingPort jest wyłącznie testową atrapą ROUTINGU, nie udaje obliczonych rur/rysunku; rzeczywiste efekty dowodzą GUI/SQLite/controller tests.
Pytania ISO (wybór zaworu, kierunek odgałęzienia, docelowy arkusz) nadal należą do portu/trasy. Adapter daje słaby fallback.56, który ustępuje rozpoznanym nowym poleceniom, pytaniom, tool.open i capabilities. Prawidłowe odpowiedzi zaworowe są mocne, aby nie wpadały w legacy.save. Jawne odpowiedzi dorysuj/append/nowy/new/anuluj/cancel/stop/nie/no są rozpoznawane w pytaniu; zachowany realny dialog, nie latentne wykonanie po przełączeniu zadania. Po obsłużeniu innego skillu usuwany jest stan pytania ISO. Nowy exceptSkillId w recognizesNewCommand pozwala workflow nie rozpoznać SAMEGO SIEBIE jako obcego polecenia i nie zgubić sekwencji przy niepełnej odpowiedzi. Negacje/cytowane instrukcje nie uruchamiają portu. Parser obsługuje jawne dodaj/add jednoznacznego rodzaju zaworu także z domu (planowy przykład); ENappend jest czasownikiem i trybem dorysowania, znane słowo w słowniku. Nie zmienia geometrii, nie dodaje pozornej obsługi trasy45.
Testy:814PASS pierwszy pełny globalrouter+nativeISOflow po parser/adapter;1985PASS całe test/assistant+screens/iso_notebook_controller_test.dart+iso_notebook_autosave_test.dart build/iso-catalog-regression.log (--concurrency=2), router500wypowiedzi634ms. Po dodatkowym guard odpowiedzi dorysuj i nowym ENappend flow:828PASS końcowy globalrouter+unitport+coverage+globalnativeflow build/iso-catalog-final-dialogue.log. Obejmuje jedną rozmowę, dawny szkic vsnowy, strzałkęN, zaworykolejno/DN, odgałęzienie/tee, cofnięcia, błędny zapis i realneSQLite, N-best, brak wykonania wmatch, przerwanie pytania przezotwarcie/Capabilities/NDS, wyjście z legacy.save, niepełną odpowiedź i zachowanie sekwencji, bare dorysuj i Englishappend bez zmianyID. Pełna analiza czysta build/iso-catalog-last-clean-analyze.log. Nie formatowano ogromnego iso_notebook_screen.dart.
To jest rzeczywista integracja katalogu/portu, NIE pełne zakończenie3.2 ani całej wizji: dialog nadal route-owned (nie AskResult centralnego mózgu), nie ma jeszcze pełnego kontraktu ShowInModule.steps/typedAsk, trasa45 pozostaje nieobsługiwana (sam symbol jest). Następne: dokończyć ISOworkflow/kontrakty i geometrię45, audytpełnego zakresu4.2 (np. edycje stawek nadal raportowane jako brak asystenta), feedback5 i żywybuild/mikrofon/iOS6. Backend/Stripe/płatneAI bez zmian. CelACTIVE; najnowszy APK będzie zapisany osobno.

2026-10-21: Rozpoczęta rzeczywista geometria tras45: nowy czysty moduł lib/domain/iso_notebook/spatial_route.dart. IsoSpatialVector opisuje ortogonalne osie I/II/III, gridHeading0..5 mapuje dodatnieI/ujemneIII/ujemneII/ujemneI/dodatnieIII/dodatnieII, projekcja odpowiada istniejącym _isoHeadings. angleTo/turnTowards liczą kąt3D (iloczyn skalarny i obrót w płaszczyźnie incoming+target), nie kąt na papierze. Odrzuca nieokreśloną płaszczyznę (współ-/przeciwrównoległy target przy niezerowym skręcie), przestrzelenie kierunku, niefinity i zero kierunku. Normalizacja, norma i projekcja skalowane, odporne na pośredni overflow dla skończonych dużych liczb; codecVector zachowuje pełną precyzję i odrzuca zniszczone/niefinity dane. planIsoSpatialRoute daje niezmienne segmenty i łuki w współrzędnych fizycznych mmC-C, atomiczny czysty plan; zachowuje kierunek odcinka skośnego, dwa45 kończą na osi docelowej, przesunięcie początku nie zmienia geometrii. Wymaga rur po obu stronach skrętu, bez kolejnych pustych skrętów, dodatnich długości i kątów0<θ<180. Nie odejmuje kształtek — to pozostaje w istniejącym CUT.
Model nie jest martwym prototypem: obecny controller używa isoSpatialGridTurnDegrees do sprawdzenia nawrotu180 i pozornego kolana0; wszystkie24 prostopadłe pary osi mają fizyczne90, choć na kartce bywają60/120. Dotychczasowa geometria i dane szkiców zachowane; iso_notebook_screen.dart zmieniony tylko o1import (NIE sformatowany). Test pokazuje też ważny przypadek: skośna ruraI−II i oś−III mogą mieć równoległe rzuty2D, mimo kąta3D90 — dlatego nie wolno odzyskiwać przestrzennego kierunku z samej kreski.
Walidacja:114PASS test/domain/iso_notebook+screens/iso_notebook_controller_test.dart+iso_notebook_autosave_test.dart+assistant/global_iso_flow_test.dart build/iso-spatial-regression.log; następnie11PASS finalnych testów modelu build/iso-spatial-final-unit.log (w tym overflow projekcji i współliniowy target przy mikrokącie); pełna analiza czysta build/iso-spatial-final-clean-analyze.log. Oczekiwane logi SQLiteTRIGGER w teście awarii zapisu nie są porażką, finalrunexit0.
WAŻNE: to podstawa przestrzenna i integracja walidacji osi, NIE jeszcze wykonanie polecenia45 w UI. _Seg nadal nie przechowuje kierunku3D/pozycji fizycznych; _Comp ma dir/dir2 jako6kierunków. Następny wymagany krok: rozszerzyć metadane segmentów i kolan oraz codec JSON (zachowanie po autosave/reopen/Undo i po metodach with*/kopii), renderer używający rzeczywistych rzutów wektorów ramion, planer/controller i parser IsoTurn45. Kontynuacja skośnego odcinka musi używać zachowanego kierunku3D zamiast _closestIsoHeading; ręczna zmiana musi unieważniać/prawidłowo aktualizować takie metadane. Zachować kompatybilność starych szkiców i jeden Undo, brak częściowych zapisów. Po tym dopiero można usunąć unsupported45 z workflow; aktualnie parser nadal odmawia pełnej trasy45. Nadal typedAsk/kontraktyISO i pełny audyt4.2/feedback5/żywybuild/mikrofon/iOS6. Backend/Stripe/płatneAI bez zmian. CelACTIVE. Nie zbudowano osobnego APK dla tej wewnętrznej podstawy; ostatni524aecd nadal jest najnowszym dostarczonym APK i nie ma pełnych tras45.


2026-10-21: ISO spatial metadata checkpoint: format 4 persists unit flow directions on pipes and incoming/outgoing elbow rays; strict decoding rejects mismatched angles, hidden/reversed projections and downgrade declarations. Legacy sketches retain formats 1/2/3. Native painter projects a genuine circular elbow centreline, independent of CUT/take-out, and labels compound spatial rays 3D instead of guessing a paper axis. Pipe property edits preserve geometry; manual symbol rotation invalidates its spatial linkage. Real SQLite/widget test opens spatial sketch, edits canvas, flushes on exit, reopens and checks unchanged original items. 170PASS domain+codec+controller+autosave+takeouts+stops+global ISO flow (build/iso-spatial-metadata-regression.log); targeted analysis clean. This is groundwork: assistant 45-degree route execution and spatial cursor planning remain pending; unsupported45 stays in place. Goal ACTIVE.


2026-10-21: Real spatial 45-degree route commands are now connected through the common assistant. IsoTurn.degrees defaults to90; parser distinguishes an actual45 turn from standalone symbol, preserves angle through compass resolution, descriptions, utterance roundtrip and encoded steps. Missing45 target plane asks before opening/modifying a sheet; direction replies retain sequence/DN/lengths, cancel and unrelated commands discard the pending intent. Native controller plans fractional schematic coordinates with actual unit flow rays and explicit45/90 bend metadata, never quantizes a spatial cursor on reopen/append. Full sequence preflight, new-sheet preview, animation queue and one-command Undo stay in use. atan2(cross,dot) fixes the false tiny bend caused by acos round-off after normalization. Actual realSQLite/native tests prove two45 bends, saved lr45 DN100 CTE64, reopening/continuation, rejected invalid plane without mutation, and CUT3244 from3500 minus four64 take-outs once. 2105PASS broad assistant+ISO domain/controller/codec/autosave/takeouts/stops (build/iso-spatial-route-assistant-regression.log); router500utterances643ms. After final diagnostic wording/missing-downstream-pipe refinement,85PASS spatial domain+native+parser+global conversation (build/iso-spatial-route-final-dialogue.log), analysis9files clean (build/iso-spatial-route-last-analyze.log). No backend/API cost change.
Scope still ACTIVE: oblique axial fitting orientation, weld-marker placement and tee branches from spatial rays need a proper component direction contract (not guessed grid directions); current spatialFitting refusal emits consent-gated private missing-capability feedback. Full typed Ask/ShowInModule.steps integration and broader4.2/5/6 audit remain. Existing native manual auto-elbow path also needs spatial-ray awareness before claiming all manual/assistant combinations complete. Physical microphone/device acceptance not proven.


2026-10-21: Spatial axial fittings and weld markers now execute through the actual ISO controller and common assistant. Added component spatialDirection, preserved by DN/physical-spec property copies; painter rotates symbols by atan2 of the actual projected ray. Format5 is emitted only for these component fields; formats1–4 remain stable, downgraded declarations are refused, malformed/hidden/nonunit directions and unsupported annotation tools are unreadable rather than silently repaired. Oblique ball/gate/check/globe/butterfly valves, flange/blind flange/cap, reducer, shop/field weld and support use existing native dimensional tables/end connections. Elbows and physical fittings receive correctly directed, numbered and idempotent auto-weld markers; one command Undo includes all symbols. Real tests cover12 component types, save/reopen/append/Undo, strict codec and actual global-chat valve placement with4welds. Standalone tee symbols retain exact cursor location without inventing spatial branches.
Manual ISO pipe joining an existing spatial ray now derives its45/90 bend from actual unit vectors, never projected hex headings; an actual gesture test proves a physical45 bend whose paper projection looks like a grid-axis90. This exposed the native ScaleStart focal-point slop bug: a Listener retains initial pointer-down positions so a drawn pipe starts at the touched endpoint; pinch and animation interruption regressions pass. Ambiguous spatial three-way junctions still require explicit spatial tee support, not guessed branches.
Validation:198PASS ISO domain/controller/codec/autosave/stops/takeouts/narrow-screen/global-chat regression (build/iso-spatial-fitting-regression.log); after final standalone-symbol path,77PASS controller+global conversation (build/iso-spatial-fitting-final-flow.log); final6file analysis clean (build/iso-spatial-fitting-final-clean-analyze.log). A production painter capture was inspected from a scratch widget test; geometry aligned, but widget-test Ahem fonts/desktop viewport do not prove phone typography or physical microphone acceptance. Backend and paid API unchanged. Goal ACTIVE: true spatial tee/branch contract, full typedAsk/ShowInModule.steps, module action/field coverage4.2 and feedback/acceptance5/6 remain.


2026-10-21: Spatial tee runs and branches execute through native controller and common assistant. IsoSpatialTee stores visible unit run and optional perpendicular branch; unknown roll remains null and painter marks ? instead of fabricating a branch. Format6 emitted only for spatialTee; formats1–5 remain stable, older declared formats with new metadata are refused and malformed metadata is unreadable/protected. Inline oblique tee preserves run DN / branch DN, native take-out C and run rays; branch command validates both actual opposite run legs, explicit-last selection with multiple tees, perpendicular physical target, empty branch, and the complete remainder before mutation. New spatial branch op updates tee plus correctly directed/idempotent numbered welds in the same Undo snapshot. Branch correction replays the latest step safely, reopen preserves all metadata. A standalone symbol can acquire a spatial run only after two real opposite pipes exist; one pipe does not invent the other.
Manual branch gestures now snap to existing fractional spatial endpoints, update real run/branch metadata and preserve reducing sizes. Three-pipe physical geometry is validated rather than inferred from paper headings. Weld deduplication compares spatial directions as well as paper positions: physically different legs with overlapping projections retain separate records.
CUT/DN/project export now read optional SketchSpatialPipe/SketchSpatialTee metadata. This fixes a demonstrated case where a physical run and perpendicular branch share the same paper ray: run DN100 keeps explicit C123 => CUT877, branch DN80 uses existing M98 => CUT902, and exported cuts agree. Native table-default overlapping-ray case:4000 - two elbow CTE64 - two run C105 - branch M98 =3564;5 physical weld records preserved. Existing axis-only graph behavior stays unchanged.
Validation:206PASS ISO domain/controller/codec/autosave/stops/takeouts/narrow/global conversation (build/iso-spatial-tee-regression.log); after final standalone-symbol run inference,83PASS controller+spatial CUT+global conversation (build/iso-spatial-tee-final-flow.log);10fileanalysis clean (build/iso-spatial-tee-clean-analyze.log). Backend/paidAPI unchanged. Goal ACTIVE: typed Ask/ShowInModule.steps contracts, full module action/field audit4.2 and feedback/acceptance5/6 remain. A targeted audit of distinct physical nodes sharing a projected coordinate is still needed: legacy connectivity uses paper points; current tests prove ray-role/CUT disambiguation, not arbitrary coincident-node topology. Phone typography/microphone acceptance remains unverified.


2026-10-21: Structured ISO step contract is now executable through the real route-owned ToolHandle. Native ISO state uses ToolHandleHost, becomes ready only after preferences/sketch/layout, accepts steps plus explicit append/new_sketch/from_last_tee/explicit_last_tee booleans, validates and freezes the complete input before awaiting, rejects hidden routes and requires an explicit append/new choice on a nonempty sheet. Controller preflight protects the current sheet when a requested new sketch has invalid geometry; successful actions retain existing animation, autosave and one-command Undo. This adds the missing ShowInModule.steps transport; current conversational drawing still uses its controller port for detailed reports/questions.
Step encoding now preserves fitting symbol_only and dir (previously silently lost),45-degree angles and sizes. Decoding validates maps and typed primitives alike, refuses unknown keys/types/tools, fractional/unsupported DN, invalid positive-length values, fitting-only directions without symbol mode, irrelevant outlet sizes and impossible tee sizes. Native editor and decoder share one constant DN choice list. Common chat validates normalized steps against this same contract before drawing, so a requested unsupported DN400 cannot silently become a remembered DN50. Unresolved compass/valve/question intent must still be resolved before producing executable steps; full typedAsk migration remains pending.
Found and fixed stored-input rounding: controller previously reused a one-decimal DISPLAY formatter for dimensions. New pure isoLengthExpression preserves the supplied finite positive double, expands exponent notation into literals accepted by ISO parser, keeps integer strings stable, and does not change display formatting. Actual ShowInModule -> native screen -> SQLite test preserves1000.125 exactly; exponent/subnormal/max-finite roundtrip tests pass. No backend/paidAPI change.
Validation:2142PASS whole assistant+ISO domain/controller/autosave/codec regression before precision/chat guard refinement (build/iso-step-handle-regression.log),500utterances700ms. Final precision/native-wire/controller/global run130PASS (build/iso-step-handle-final-flow.log); after adding common-chat DN guard,74PASS full global dialogue+step contract+precision (build/iso-step-handle-last-dialogue.log). Final8fileanalysis clean (build/iso-step-handle-last-clean-analyze.log). Goal ACTIVE: typed ISO AskResult workflow and4.2 all-module action/field coverage, feedback/acceptance5/6, physical microphone/device tests, and projected-node topology audit remain; do not treat maximum tier per module as proof every action is controlled.


2026-10-21: ISO parameter fidelity and native module field audit. Standalone axial symbols retain explicit grid/cardinal direction through valve-type questions, wire transport, controller, SQLite and Undo (12 component types); terminal flange/cap no longer reverses an explicitly oriented symbol. Ambiguous directions, extra/invalid sizes and direction attached to an in-route axial fitting ask for clarification without mutation or false gap reports, including with feedback consent granted. Genuine unsupported30-degree request retains the sketch and queues iso.unsupported with accurate45/90 guidance.
Native catalog audit opens35 real module pages and validates emitted field names;32 read-only targets also accept actual emitted values. Confirmed writes remain schema-only; quote completion reaches confirmation without performing it and real quote table stays empty.41 explicit fixture skips are NOT coverage proof; full4.2 remains pending. Actual value application exposed elbow-cut horizontal overflow, fixed using Expanded on two labels.32 responsive cases cover360/432/600 widths, landscape, text1/1.3, PL/EN, light/dark.
Validation:2201PASS broad assistant+ISO regression (500 utterances709ms); final109PASS/~41 fixture skips across native global ISO conversation/module fields/32 responsive cases;59 parser/valve/symbol regressions;8-file analysis clean. Logs build/iso-axial-parameter-regression.log, build/iso-axial-module-contract-final.log, build/iso-axial-direction-final-parser.log, build/iso-axial-final-analyze.log. Backend, paid APIs and pricing unchanged. Goal ACTIVE: typed ISO AskResult migration, full action coverage4.2, feedback/physical phone/microphone acceptance5/6 and coincident projected-node topology audit remain.


2026-10-21: Added real B-tier mitre.bend control rather than navigation-only coverage. Six bilingual catalog examples use the native computeMitreBend domain function. Typed questions collect actual OD/tabulated DN, total angle, integer weld count1–12, centreline radius (irrelevant for one weld) and explicit end tangent including zero. Invalid/conflicting values remain unresolved per parameter; a correction to weld count cannot resolve an ambiguous angle. Unit conversion, natural count labels, one-weld minimum tangent, finite/overflow refusal, continuation and interruption are tested. Explicit DN is retained for cross-module questions (e.g. wall schedule), while manual OD clears inherited DN and its table attribution. Numeric DN→OD answers cite the actual ASME table.
MitreBendPage now owns a ready ToolHandle; complete validated fields apply atomically, recompute through the native build path, clear stale DN/radius-factor selections and retain prior values on malformed/partial updates. Native weld chips now expose all1–12 choices already supported by the domain; overflow displays an actual error instead of an empty notice. The common global assistant asks all missing inputs, opens the real page, updates4/12-weld selections, refuses too-small radius unchanged and accepts correction without false feedback (consent enabled).
Coherence fix: a request to draw a mitred/segmented bend in ISO cannot silently create a normal elbow. Both PL post-noun and EN prefix variants produce an explicit unsupported warning, preserve the whole drawing/Undo and queue iso.unsupported only with feedback consent; an ordinary pipe segment does not trigger that warning. Native ISO has no dedicated mitred-bend component contract; the assistant points to the available calculator rather than inventing one.
Validation:2146PASS/~40 explicit fixture skips in broad assistant+mitre domain/native-page regression before final extra argument guards (build/mitre-assistant-final-regression.log). Final945PASS/~40 across new skill/global conversation, ISO parser/global drawing, full routing corpus, native field contracts and mitre domain/page after those guards (build/mitre-assistant-final-verified.log);10-file analysis clean (build/mitre-assistant-final-verified-analyze.log); latest500-utterance performance783ms (build/mitre-assistant-verified-perf.log). Field audit now36 targets,33 actual read-only value application targets;40 skips mean missing field-bearing catalog fixtures, NOT complete action coverage. No quote confirmation performed by the field audit. Backend, payments/prices and paid AI calls unchanged. ADB devices list empty on2026-10-21; no physical microphone acceptance claimed.
Goal ACTIVE: typed ISO AskResult migration, remaining all-module action/field coverage4.2, feedback/app acceptance5/6, physical phone/microphone/iOS and coincident projected-node topology audit remain. Next concrete gap inspected: tube_bending has three native modes (single/offset/multi), canonical millimetres and async persisted settings; its future handle must wait for _loaded and preserve the store/load and unit contracts.


2026-10-21: Added real tube.bending B-tier control for all three native calculation modes: single, flat/spatial offset and multi-bend (up to12 bends). Shared pure TubeBendingCommand strictly validates complete mode-specific fields, units, finite values, array lengths, first rotation0, domain bounds and feasible geometry; copies/freezes lists and refuses irrelevant fields. Skills use existing computeTubeRun/computeTubeOffset, actual native cut-up/mark-nearest rounding and bender warnings. Questions collect missing CLR, angles and dimensions; mm/cm/m/inch input, individually unit-labelled or one final shared list unit, explicit rotations and bender corrections are supported. Fresh calculations explicitly set unspecified corrections0 and disclose their meaning; unknown saved bender settings cannot silently alter the answer.
Native page owns a ready handle only after asynchronous preferences load, applies complete calculations atomically, keeps inactive-mode geometry, safely replaces multi-bend controllers and saves the actual canonical state. A unit-only action deliberately uses the native selector semantics even with incomplete/invalid geometry: no invented cut result or changed dimension. Existing v1 persistence format stays compatible. Editable angle/rotation/springback restoration is now lossless instead of rounded by numText: real boundary regression at45.0049° proves a300mm cut stays300 after apply/reopen (old rounding would add0.5mm). Canonical length precision and mm/inch switching remain stable.
New optional FieldModuleContext/InputToolHandle snapshot port reads only the visible ready opt-in calculator, never hidden routes/popups or credential forms. Tube explicit edits and active-module follow-ups merge the NEWEST actual native inputs, not stale conversation data; pending partials retain unresolved changes. Real global chat test manually changes legA to400, then changes the angle by assistant without restoring old200; changes units while native angle0 is invalid, repairs the angle, then correctly continues another dimension. Immutable snapshots, not-ready/hidden/popup guards, actual prefs/reopen, all3 modes and12-bend replacement are covered. This readback is currently adopted only by tube_bending; remaining calculators still require their own adoption/audit.
Cross-module routing: tube-bender rolling offsets go to the bender domain, while ordinary pipe rolling offset retains its existing calculator. Active tube edits cannot steal slope/bevel requests; narrow ukosowanie alias added to existing bevel.geometry with its own bilingual corpus example. Supported calculations and invalid input emit no false gap report even with feedback consent granted. No backend, pricing/payment or paid-AI-call changes.
Validation:2294PASS/~39 explicit missing-fixture skips in full assistant + tube command/domain + native tube page/store regression (build/tube-assistant-full-regression.log); all12 modified/new Dart files analyze clean (build/tube-assistant-final-clean-analyze.log);500 utterances688ms. Native field audit37 targets,34 real read-only value-application targets;39 skips are NOT action-completeness proof. Goal ACTIVE: full all-module action/field coverage4.2 (including native readback for other calculators and non-calculation actions), typed ISO AskResult migration, feedback/app acceptance5/6, actual phone/microphone/iOS and projected-node topology audit remain.


2026-10-21: pipe.route B-tier now controls the real two-90-degree-elbow route calculator. Pure PipeRouteInput validates complete finite dimensions, distinct signed datum heights, nonnegative gap/takeout, explicit end-weld reference and physically fitting segments. Assistant asks typed questions, converts units, distinguishes LR/SR/3D table takeouts and missing rows, preserves the requested radius type through clarification and never silently substitutes LR. SR/3D travel as custom R because the native DN picker is LR-only; explicit R clears stale DN/source. R=0 is explicitly labelled C-C rather than ready-to-cut stock. Unsupported angles/elbow counts/mitred bends preserve inputs and report only real missing capability; invalid inputs ask without false reports.
Native PipeRouteCalculatorScreen opts into current-input readback only when visible/ready, waits asynchronous preference loading, applies validated complete fields atomically and serializes immutable saved snapshots per instance. User edits during loading survive; explicit zero-R survives reopening while legacy unmarked zero remains rejected. Current native edits/recalculation use actual manually changed fields, not stale dialogue data. Clear action works through the actual page and saves cleared state. Fixed result-heading overflow; PL/EN at320/360/432 widths and text1.3 tested. Nine bilingual catalog examples; common global chat, real screen, preferences and failed-input recovery covered.
Validation:2294PASS/~38 explicit missing-example fixture skips, whole assistant plus pipe-route domain and both existing page suites (build/pipe-route-assistant-final-regression.log);8-file analysis clean (build/pipe-route-assistant-radius-clean-analyze.log);500utterances708ms. Native field audit38 targets/35 actual read-only applications;38 skips are NOT complete action coverage. No backend, payments or paid-AI-call changes. ADB empty2026-10-21, physical microphone unverified. Goal ACTIVE: other calculators' current-input adoption, remaining non-calculation actions4.2, typed ISO AskResult migration, feedback/acceptance5/6, phone/microphone/iOS and projected-node topology audit remain. Inspected next concrete gap: pipe_slope already accepts all three calculation modes but lacks current-input readback and contextual edits/recalculation/clear.


2026-10-21: pipe.slope now reads current native independent inputs through the ready visible InputToolHandle. Snapshot is immutable and contains mode plus only its two actual inputs, never a rounded computed result. Explicit edits and contextual follow-ups merge current manually changed values, recalculate the selected mode and choose the correct inverse pair when editing its former computed quantity. Missing fields ask in the selected mode; labelled alternatives can complete a different pair. Invalid dimensions/percent units remain questions without mutating the page or generating false reports. Clear acts on actual controllers and guide-result state, preserves mode, rejects mixed/unknown action payloads atomically. Native apply additionally refuses contradictory supplied derived values rather than ignoring them.
Confirmed and fixed a continuation bug in the new implementation: empty quantity parse initially produced metadata-only slots and replayed the prior slope result for unrelated PL/EN text. Three new tests first failed (build/slope-current-unrelated-red.log), then passed after _intent returns empty when no parameter was parsed. Actual common-chat test covers manual12000mm,2percent=>240mm, rise120=>1percent inverse mode, invalid negative length with correction, angle-unit refusal for percentage, clear and completion with an alternative pair; consent enabled and feedback queue remains empty. Native tests cover all3 modes, readonly input snapshots, current recalculation, inverse changes, clear, missing-field recovery, mixed/contradictory/infinite field atomic refusal, hidden/non-opt-in read failure and cross-tool routing.
Validation:872PASS final local/native/global/full-router run (build/slope-current-final-routing.log);2283PASS/~38 explicit missing-fixture skips whole assistant+pipe-slope domain regression after final continuation guard (build/slope-current-final-regression.log);4-file analysis clean (build/slope-current-final-analyze.log);500utterances750ms. Field audit unchanged38 targets/35 actual read-only applications;38 skips are NOT complete action coverage. No backend, pricing/payment or paid AI changes. ADB list empty2026-10-21; physical microphone unverified. Goal ACTIVE: remaining module current-input/field/actions4.2, typed ISO AskResult migration, feedback/acceptance5/6, phone/microphone/iOS and coincident projected-node topology audit. Pipe-slope copy-result, formula/help, presets and explicit mode-only control still need action contracts; next concrete broader gap rolling_offset only accepts rise/spread/angle and resets native optional DN+gap, while rollingOffsetCut already computes actual tabulated cut lengths. Future current edits must preserve actual DN/gap and distinguish fresh geometry from edits; never present Travel as cut length.


2026-10-21: Native calculator actions added through opt-in ModuleActionContext/ModuleActionHandle, returning actual completed/failed bilingual results. ToolBridge executes only a matching visible ready opt-in route, blocks popups/hidden/wrong-target/unloaded modules and sanitizes exceptions; no widget scraping, generic text-copy or credential exposure. First adoption pipe_slope: copy the actual displayed main result for all3 modes, slope angle or mm/metre via existing copyToClipboard, and open the existing formula dialog. Clipboard completion is awaited before success; empty/stale results and requested input-only fields refuse without copying or false missing-capability reports. Values/units in confirmations match actual native text, not dialogue memory or recomputed values. Qualified formula requests from another page use ShowInModule(action=formula) and open the real module/dialog.
PL/EN copy targets, explicit one-value ambiguity questions, plural/all-results clarification and actual result-to-clipboard wording covered. Copy/formula parsers require relevant known target words; unrelated profile requests do not copy calculator data. Pending copy questions cannot swallow a new explicit edit/calculation. Action metadata is cleared by later genuine parameter continuations; gibberish cannot replay a clipboard write. Post-calculation localized chips Copy result/Copy angle/Show formulas make actions discoverable at the point where they apply. Cold catalog examples include formula opening; current-result copy is verified by actual mounted-module tests rather than advertising it as a fresh stateless calculation.
Actual common-chat test taps the localized copy chip, verifies platform clipboard payload60.0, edits/manual/inverse calculations without replaying copy, refuses copy after clear, keeps consent-enabled feedback queue empty, and opens native formula dialog. Native tests prove all3 result modes, angle/mm-per-metre, ambiguity/follow-up, explicit-edit interruption, frozen input state, platform errors without leaked exception details, hidden/wrong/not-ready/popup guards and actual cold navigation. Module field-contract audit now verifies explicit formula popup and restoration of the SAME underlying handle after close; ordinary field updates retain the strict no-route-change invariant.
Validation:912PASS/~38 explicit missing-fixture skips targeted native/global/router/module-field contracts (build/slope-actions-contract-final.log);2293PASS/~38 whole assistant+pipe-slope domain final regression (build/slope-actions-final-regression.log);7-file analysis clean (build/slope-actions-verified-clean-analyze.log);500utterances716ms. Field audit unchanged38 targets/35 actual read-only value-application targets;38 skips are NOT complete action coverage. No backend, pricing/payment or paid AI changes. ADB empty2026-10-21, physical microphone unverified. Goal ACTIVE: pipe-slope explicit mode-only and native preset controls remain, other modules need actions/current-input adoption4.2, typed ISO AskResult migration, feedback/acceptance5/6, phone/microphone/iOS and coincident projected-node topology audit. Next concrete native slope controls: modes length_to_rise/rise_to_length/slope_from_lr and presets0.5(1:200),0.67(1:150),1(1:100),2(1:50); preserve native selector clearing and exact0.67 approximation instead of silently using2/3. Broader rolling_offset optional DN/gap/cut still pending as noted previously.


2026-10-21: Explicit pipe-slope mode-only control implemented for length_to_rise/rise_to_length/slope_from_lr. Native mode selection is shared with the actual radio rows: preserve applicable independent inputs, clear the old and new computed quantities on a real switch, retain valid current result when selecting the SAME mode, and never silently calculate or invent missing dimensions. ModuleActionHandle accepts whitelisted mode:<id>; ShowInModule accepts exactly action=mode+valid mode, refuses unknown/mixed/typed-invalid payloads atomically. Mode actions work on incomplete forms. Qualified PL/EN catalog commands open the correct native mode from another page; contextual explicit commands operate on the visible module. Three new bilingual examples are actual cold navigations, not merely labels.
Pending numeric/copy questions can accept an explicit mode request without treating it as a number or clipboard target; former parameter/action metadata is cleared. Actual common-chat flow begins on home, asks missing slope inputs, then mode request opens the real rise_to_length page before a new valid calculation; subsequent calculation/copy/clear/formula flow and consent-enabled empty feedback queue stay intact. Native nine-transition comparison to actual taps PLUS pinned six inverse-switch input maps and computed angle/copy-invalid invariants prevent a shared-helper bug from passing solely by agreement; same-mode angle stays0.573, changed mode clears angle and cannot copy a stale result. Invalid wire fields do not partially alter state.
Validation:873PASS targeted native mode/actions/common-chat/full-router before final three qualified examples (build/slope-mode-final-targeted.log);2309PASS/~38 explicit missing-example fixture skips full assistant+pipe-slope domain after those examples (build/slope-mode-full-regression.log); final10PASS strengthened pinned native transitions (build/slope-mode-pinned-native.log);4-file analysis clean (build/slope-mode-final-clean-analyze.log);500utterances678ms. Field audit remains38 targets/35 actual readonly applications;38 skips are NOT action completeness. No backend, paidAI or financial changes. ADB empty2026-10-21, physical microphone still unverified. Goal ACTIVE: native percent presets0.5/0.67/1/2 and ratio intent distinction remain; preserve native0.67 preset approximation for1:150 rather than silently choosing2/3, while an explicit mathematical ratio request needs its own exact conversion contract. Other modules' actions/current-input adoption4.2, rolling_offset optional DN/gap/cut, typed ISO AskResult migration, feedback/acceptance5/6, phone/microphone/iOS and projected-node topology audit remain.


2026-10-21: Completed pipe-slope native preset control and exact slope-ratio calculations. Immutable domain pipeSlopePresets is shared with existing buttons; action selection uses exact native0.5/0.67/1/2 values and recalculation semantics.0.67 is explicitly labelled rounded1:150 in native label(approx sign) and assistant confirmation. Incomplete-form selection honestly says input is needed; unavailable slope_from_lr shortcuts refuse without mutating mode/values. Unknown shortcut requests ask for one actual available choice instead of silently becoming a generic ratio calculation. Preset actions work through the ready visible module action port; strict action/preset wire validates combinations/types and refuses a stray numeric preset field in ordinary calculation payloads. Valid explicit wire applies real40.2mm result. Preset choices and point-of-use chip are localized; chip only offered for modes with the native shortcut row.
New pure slopePercentFromRatio validates finite positive rise/run and resulting percent;1:150 produces40mm over6000mm, versus native rounded preset40.2mm. Parser accepts decimal numeric ratios and scoped PL/EN spoken ratios, removes denominator tokens before reading lengths, protects the Polish one/ten pronoun policy by using actual utterance language, and refuses signed/zero/overflow, unit-attached, chained, multiple conflicting and percent-conflicting ratios. Relative1e-12 consistency comparison avoids declaring two different tiny percentages equal. Percent answers show up to6 decimals with an explicit approximation marker, preserve nonzero tiny values and do not trim exponent zeros; actual module input fields retain full native double precision. Native/main-chat tests distinguish exact ratio from shortcut and return to1percent without stale action replay; feedback consent enabled with queue empty.
Global negation guard extended to PL choosing/copying/clearing verbs and EN copy/choose/clear. Negative primary speech cancels pending work and blocks positive N-best alternatives before module actions or remote AI. Actual chat verifies a negative shortcut cannot change60mm and negative copy cannot write clipboard. Broad regression first exposed500-utterance1012ms budget failure; PipeSlopeSkill now skips quantity parsing for unrelated requests instead of relaxing the budget. Final routing/performance packet912PASS with775ms.
Validation:2347PASS/~38 explicit missing-fixture skips full assistant+pipe-slope domain regression before final stray-preset guard (build/slope-ratio-preset-final-regression.log),500utterances726ms;949PASS/~38 final native/actual-global/negation/full-router/module-field contracts after that strict guard (build/slope-ratio-preset-verified-contract.log); final8-file analysis clean (build/slope-ratio-preset-final-verified-analyze.log). Field audit unchanged38 targets/35 actual readonly applications;38 skips are NOT action completeness. No backend, prices/payments or paid AI changes. ADB empty2026-10-21, physical microphone unverified. Goal ACTIVE: other-module actions/current-input adoption4.2, rolling_offset optional DN/gap/cut, typed ISO AskResult migration, feedback/acceptance5/6, phone/microphone/iOS and projected-node topology audit.
Next concrete correctness issue independently reproduced in a gitignored diagnostic: shared assistantNumber(1e30,EN) returns1e+3 because its trailing-zero regex trims the exponent (lib/assistant/assistant_validator.dart). build/assistant-number-large-probe.log invokes the ACTUAL helper; probe intentionally records existing wrong output and is NOT a correctness-pass claim. Current slope percent display guards exponent text separately, but shared formatter still needs a scoped fix, truthful regression expectations and review of callers/financial paths before broader completion. Do not forget this verified remaining bug or call the vision complete.


2026-10-21: Resolved the verified shared assistantNumber exponent bug:1e+30 can no longer become1e+3, fractional mantissas/signs/exponents are preserved, and small nonzero values cannot silently render as0. Ordinary two-decimal compact PL/EN output stays compatible; negative zero displays0. Actual-function red tests first exposed24 failures; final strict numeric round-trips cover exponent endings0/100/300, large/small signed values, subnormal and max-finite bounds, plus independent ordinary-display fixtures. Hot formatting now trims only known fixed-precision suffixes without constructing regexes. Broad initial run had only router budget failure1170ms; after hot-path change100 targeted tests passed with773ms and final whole run659ms. No threshold relaxation or skipped performance test.
Real answer->ShowInModule->QuickConverterScreen tests also exposed a separate wire bug: incoming finite1e30 was accepted by the handle but its toString exponent was rejected by the native decimal-only parser, leaving an error instead of results. Added shared pure decimalInputText: expands finite signed exponent notation losslessly, preserves ordinary5.0/-40.0 input spelling, rejects nonfinite values. Native conversion input now uses it; strict user input/keyboard syntax and conversion domain are unchanged. ISO isoLengthExpression delegates to the same primitive while retaining its finite-positive validation and integer spelling policy; no schema/data migration or rounded stored dimensions. Existing ISO length precision, controller, autosave and spatial/cut tests pass. Native small/large conversion examples independently compare actual response numeric magnitude and visible native result, not just a rewritten formatter.
Call-site audit covered shared fmt, local parameter descriptions and actual chat save-summary fields. No price/rate/payment/budget calculation or paid-API invocation was changed; no live financial proof or backend deployment is claimed. Diagnostics which expected the old wrong exponent output are obsolete after this fix; historical log build/assistant-number-large-probe.log remains evidence of the previous bug, not current correctness.
Validation:100PASS target formatting/actual native conversion/validator/ISO literal/performance packet (build/assistant-number-fast-tests.log);2520PASS/~38 explicit missing-example fixture skips full assistant+ISO domain+controller/autosave final regression (build/assistant-number-final-regression.log),500utterances659ms;5-file analysis clean (build/assistant-number-final-analyze.log). Field audit unchanged38 targets/35 actual readonly applications;38 skips are NOT action completeness. ADB empty2026-10-21; physical microphone still unverified. Goal ACTIVE: remaining module actions/current-input adoption4.2, rolling_offset optional DN/gap/cut, typed ISO AskResult migration, feedback/acceptance5/6, phone/microphone/iOS and coincident projected-node topology audit. Next concrete module scope remains rolling_offset: current geometry edits must preserve actual native optional DN/gap while fresh calculations clear stale selections, and tabulated cut lengths must use existing rollingOffsetCut rather than mislabelling Travel as cut stock.


2026-10-21: Rolling offset now reads actual visible inputs for edits/recalculation, preserves manual rise/spread/angle/DN/gap, and clears stale cut selections on a fresh geometry-only calculation. Added strict atomic RollingOffsetInput validation and actual ASME LR takeout cut calculation (300/400/45, DN100, gap3: Travel707.106781mm, B64mm, cut573.106781mm). Missing gap/DN or contradictory LR90/45 asks before changing UI; SR/3D/custom-radius cut requests report a genuine missing capability instead of silently substituting standard LR. Native malformed nonblank gap is rejected; blank retains native zero semantics. Clear resets actual page. AnswerResult.contextSlots opt-in stores frozen resolved inputs in returned match and conversation context; manual DN50 stays DN50 in later pipe-wall questions. Default skills unchanged. Main-chat/native/domain/core/router coverage901PASS; final assistant+rolling-domain+ISO domain/controller/autosave2549PASS/~38 explicit missing-example fixture skips,500utterances647ms (build/rolling-current-final-regression.log). Skips are not action completeness. No physical microphone proof or backend deployment for this scope.
User steering2026-10-21: assistant feels rigid; priority is cheap real AI for free-form conversational interpretation and actual app execution. Existing chat service and legacy save/open/unknown classifier are insufficient for all native actions; investigate unified AI action interpretation with current module/conversation context and strict validated execution. Candidate low-cost Anthropic Haiku, verify account availability/current pricing before configuring. Retain per-request budget reservation, project isolation, actual-execution proof. Full goal ACTIVE; do not treat deterministic module coverage as completion of user vision.


2026-10-21: Added real contextual AI interpretation foundation, beyond the legacy save/open/unknown classifier. Backend POST/api/fitter/ai/assistant accepts a bounded public capability catalog, opt-in visible inputs, pending-question field and six conversational turns; returns strict execute plans (known skill IDs plus canonical commands, up to8steps), answer routing, clarification or unsupported. Uses cheap Haiku5.5 loweffort, reserves monthly budget before paidcalls and shares existing intent daily device/IP counters. Strict identity and request/output sanitization; no arbitrary native controller fields or server execution.197backendPASS0skips, including shared old/new daily allowance, hardbudget block, refusal/truncation/malformed/unknown action rejection.
Real provider HTTP first returned400: Anthropic structured output rejects array maxItems. Removed unsupported provider-schema constraint; server/client still strictly enforce8steps. This was a real integration failure invisible to the initial fake tests; regression asserts the supported schema and local count enforcement. Actual FWP-account Haiku then accepted full53-skill app catalog and actual native rolling inputs600/400/45 DN50 gap3. User requested colloquially to keep native rise/spread and change only weld gaps to2mm. Exact model proposal: rolling.offset / Rolling offset wznios600mm odsunięcie400mm kąt45stopni DN50 szczelina2mm; actual recorded cost$0.0010463. Evidence backend build-assistant-live-proof.log and app build/ai-live-request.json,build/ai-live-proposal.json.
Flutter AssistantAiClient builds consent-independent transport requests only from the public skill catalog and explicitly opted-in visible input port, filters nonfinite values, validates strict AI plans/allowedIDs, retains typed unavailable errors, bounded30s timeout and install identity. AssistantBrain.executeProposal serializes through the existing execution queue, checks source/command negation and quoted instructions, demands the exact named local skill really matches, then uses existing domain functions/Ask/Confirm/Undo paths. No model-supplied fields are injected. Captured REAL provider response committed as test/fixtures/assistant_ai_actual_haiku_offset.json and replayed through actual skill/native RollingOffsetScreen: preserves manual600/400, DN50, changes gap3→2, actual cut945.8mm. Important table correction for future arithmetic: DN50 B45 is35mm in existing catalog, NOT32; independent expected cut=sqrt(600²+400²)/sin45−2×35−2×2. Initial test fixture used wrong32 expectation; production table/domain unchanged.
Validation:21PASS targeted client/core/native/captured-real-response/performance packet,500utterances722ms (build/ai-interpreter-real-replay.log); final2558PASS/~38 explicit missing-example fixture skips full assistant+rolling-domain+ISO domain/controller/autosave (build/ai-interpreter-final-regression.log),500utterances696ms. Skips still do not prove all actions.
Backend1072dd9 pushed feat/assistant-interpreter; PR3 merged squash e119e88ffc87dfbce7cd497731be9ab1173c6d71, attached https://github.com/jakatora/fitter-welder-pro-backend/pull/3. Retried scoped railway up for new backend; same terminal rejection Deploys have been paused temporarily, no new deploymentID. Production remains old deployment, not newAI. Local work continues; no goalblocked claim.
CRITICAL remaining UI step: new AssistantAiClient is NOT YET connected to AiChatScreen._submitCommand. Current APK13b933b is still offset-only improvement, not unified AI chat. Integrate AI before generic local fallback for free-form requests, retain consent/offline behavior and original utterance. Feed actual execution results into bounded history. Handle ordered multi-step plans, pausing/resuming on native AskResult/ConfirmResult, cancelling on user superseding/negation; never silently discard remaining steps or replay old writes. `_brain` buildSkillCatalog default has53skills (+ISO port in screen), but legacy save/journal/query are outside it; concrete AssistantActionsPort production implementation is missing (only interface in core, no assistant_actions.dart). Either extract existing native persistence flow into the intended port or provide strictly validated dispatch through existing legacy summaries/confirmations; don't invent missing actions or bypass writes. Consent/privacy copy must accurately cover visible inputs/history before enabling cloud use. Current small examples3percapability describe basic syntax, not necessarily every action; improve action metadata/context as actual UI integration grows. Then verify full main-chat+voice-transcript+ISO+records flows, phone mic/iOS, all native actions4.2 and final5/6 acceptance. Full user goal ACTIVE.


2026-10-21: Connected contextual Haiku interpretation to the actual AiChatScreen main embedded conversation. Unknown free-form requests reach AssistantAiClient before generic fallback; recognizesLocalRequest keeps real exact/active-module requests and supported core fallbacks offline (generic knowledge fallback cannot swallow AI input). AiExecutionQueue executes validated known local skill proposals in order, pauses on native AskResult/ConfirmResult, resumes only after actual matching resolution/save and discards remaining steps after superseding commands/failure/cancel. Legacy native save/journal/query workflows still retain ownership and confirmations; they are not yet exposed to the AI catalog.
AI context uses the real visible input port, bounded recent conversation and explicit pending model clarification. A cancelled request epoch, changed module/handle/inputs, changed/revoked consent or disposed screen prevents late execution. CancelAI is available during cloud interpretation. Cloud failure/limit is visibly distinguished from local operation; a transient AI outage cannot generate a false missing-feature report. Native answers have explicit nativeAction provenance in question history, and actual save results enter conversation after persistence. General questions can refer back to verified local calculations without treating them as model answers.
User-facing privacy/consent version5 dated2026-10-21 now covers capability list, shared visible calculator inputs and recent native conversation. Previously local commands may enter later AI context after consent, so the obsolete never-leaves-device promise is removed. Existing version4 acceptance does not permit the new flow. Feedback permission remains separate; regression verifies feedback grant does not grant AI/server consent.
Real main-chat widget integration tests replay the EXACT captured real Haiku command against actual native rolling inputs600/400/45 DN50 gap3→2, resulting945.8mm. Final microphone transcripts traverse the same main AI path (SpeechInput fake; not physical phone audio). AI ordered plan opens actual ISO and draws two parts; native Undo removes the last part without a cloud call. SQLite quote test creates no row before confirmation, uses actual stored177.5/122 rates, opens actual QuoteEditPage and soft-deletes on Undo. Additional tests cover native questions, model clarification/history, touch-only saves, superseding queued work, cancellation, consent revocation and manual-edit stale-response rejection.
Independent red probes exposed two actual defects after the first broad green2809 run: outage incorrectly queued FeedbackKind.notUnderstood; a delayed summary speech allowed early Save before queue pause. Both now fixed: outage guard and busy/perform guards during plan presentation. The2 red failures are preserved in build/ai-chat-outage-speech-red.log; full main chat/quote15PASS green build/ai-chat-outage-speech-green.log. Final verification after fixes:2810PASS/~38 explicit missing-example fixture skips,500utterances685ms (build/ai-chat-final-regression.log),11-file analyze --fatal-infos clean (build/ai-chat-final-analyze.log).38 skips still do NOT prove all native actions; field contract38targets/35readonly applications unchanged. No Dart source edits after final verification.
Backend companion:PR4 merged4925a8575638bdec3aec46ce3cb1e0fff982088d (Dwt local03a3a6986dd11386dcb17ada7b4f0fb4238e256b), https://github.com/jakatora/fitter-welder-pro-backend/pull/4 attached.199backendPASS0skips. New interpreter uses25s provider deadline below30s client timeout and maxRetries0; every call reserves project budget first, shares intent daily limits and records actual usage. Ambiguous connection/5xx loss retains a conservative estimate under fitter_assistant_uncertain rather than silently releasing monthly allowance. Real local backend HTTP to actual FWP-account Haiku after these SDK options returned200, same command as captured fixture, cost$0.0010053 (build-assistant-live-proof.log). Primary nested backend clean main fast-forwarded fromac54edd to4925a857 after verifying/reverting only our four temporary privacy hunks; both local backend source trees now current. No PrzetargAI or other project changes.
Latest scoped Railway deploy for03a3a69 again rejected before deploymentID: Deploys have been paused temporarily. Do not claim new backend/model is production-live. ADB empty2026-10-21; physical microphone and iOS remain unverified. Full goal ACTIVE: AI-assisted legacy save/journal/query (extract actual AssistantActionsPort or strict dispatch), broader unparsed pending native/ISO replies, clearing ephemeral AI conversation on account/data deletion/session change, all remaining native actions/input adoption4.2, typed ISO AskResult migration, projected-node topology audit, final5/6 acceptance and physical phone/iOS. Avoid returning to endless deterministic parser expansion; use explicit native capability/action metadata for wider AI execution while retaining domain validation.


2026-10-21 native persistence milestone (supersedes missing-production-actions note): AssistantActions now shares actual WeldParamDao/WeldJournalDao persistence between existing native dialogs and AI legacy.save/legacy.journal. params.saved reads actual saved values. Native prepare is readonly; commit uses stable snapshots, atomic duplicate weld-number recheck including tombstones, same-ID retry after lost completion, and guarded Undo refusing manual edits/status-history changes. Actual stamp/time/project and voice provenance are native. Voice-started Ask followed by typed wall retains source. Main catalog now includes these capabilities; AI plan execution still requires native confirmation. Undo success enters conversation. Existing native dialogs/toasts preserved.
Verification:32 initial persistence/native UI tests passed. Broader regression exposed ISO/interpass interception by generic legacy parser; fixed by excluding only the three legacy/own-param skills from independent-command preflight. Targeted76PASS includes actual ISO/interpass and old/native record flows. Broad final run2576PASS/~38explicit fixture skips/1catalog-metadata failure; sole failure required6examples/3rejections for new params.saved. Added those; final catalog+perf+realSQLite run893PASS,500utterances779ms. Broader run performance652ms. No threshold relaxed, no skipped tests added. This is not full all-app acceptance.
Remaining: main-chat REAL provider legacy multi-action save+thenquery replay and voice/journal confirmation widget proofs; natural compound requests can still be intercepted by single-intent preflight, so fix entry before claiming multi-action records complete. Saved parameter read DI available, BrainHarness uses in-memory empty reader. Preserve real rolling provider fixture before reusing build/ai-live-request.json. Need actual provider output for records fixture, no arbitrary AI fields. Also pending native/ISO replies, session/data deletion chat reset, broader module actions/typedISO/topology/physical microphone/iOS. Railway new interpreter deployment remains paused/unavailable; previous productionPOST endpoint404 andprivacy2026-10-20. No new backend deploy attempted in this milestone; no claim of production availability. Cheap model already claude-haiku-5-5 from prior real HTTP proof. Full goal ACTIVE.


2026-10-21 compound record execution milestone: main AiChatScreen detects explicit sequence connector plus next action (nastepnie/potem/pozniej/then/after that) before exact single-command preflight. This fixes natural save+thenread requests previously stolen by query parser. Does not use bare conjunction i/and. Existing negation/quoted instruction/native pending ownership preserved. Without AI consent offers enable/replay while retaining original text; unavailable or malformed model plan cannot fall into partial single-intent execution and reports no action. Existing native single commands remain offline.
Real paid model proof: captured actual production-screen57-capability request, isolated LOCAL backend HTTP/api/fitter/ai/assistant to real claude-haiku-5-5 returned200, ordered legacy.save canonical Zapisz TIG nierdzewka ścianka2mm60Abezdrutu thenparams.saved. Actual recorded costUSD0.0010647, hard-budget0.03 for isolated proof DB, no automatic provider retry, shared reservation before call. Fixture test/fixtures/assistant_ai_actual_haiku_records.json replays EXACT real response in main embedded chat +realSQLite: no row before touch-confirm, native60Arow then actual read. Existing rolling request/proposal preserved build/*-rolling-13f710e.json; records archives build/*-records.json. Generic live-request/proposal now records case, beware prior helper assumptions. Backend build-assistant-live-proof.log current recordsproof.
Voice final-transcript widget test (fakeSpeech, NOT physical microphone) drives compound plan, native wall Ask, typed2mm, confirm, voice-source note and subsequent actual query with just1AIcall. Real journal main-chat test runs3confirmed writes, duplicate7asks8preservesWPS, missingprojectreply ten sam uses actual lastprojectBlokA. Native welderJanTestowy123/time2026-10-21/statuspending asserted. This exposed parser project swallowing hyphenated WPS marker into project; fixed stop boundary for WPS-/WPS/, preserving existing WPSidentifier semantics.78parser+newflow testsPASS. Final selected mainAI/chat/quote/native/oldsave/catalog/perf936PASS0skips;500utterances776ms (build/ai-compound-final-tests.log);4-file analyze --fatal-infos clean(build/ai-record-compound-analyze.log). Initial3compoundred probes, thenjournalredprojectswallow fixed; logs build/ai-record-*.
Railway scoped up retried same isolated project/env/service from Dwt backend03a3a69. TERMINAL rejected: Deploys have been paused temporarily; no deploymentID (logs/deploy-records-interpreter-attempt.log). This remains LOCAL API proof, NOT productionAI availability. No otherprojectchanges. Full goalACTIVE; remaining multi-action natural statements lacking explicit connector, unparsed native/ISO follow-up replies, clearing ephemeral AI context/queue on account/data deletion/session changes, full native action/input adoption/typedISOAsk/projected topology, physical microphone/iOS and finalacceptance. Do not mark4.2/5/6done from these cases.


2026-10-21 transient conversation/session isolation milestone: AccountService exposes integer sessionRevision, advanced on secure token restoration, successful login (even same account/token), logout/forget and401revocation. Profile saves only notify without revision.401/forget invalidate in-memory session and notify before awaiting OS-storage deletion, so late UI work cannot slip through that await. Existing server logout-before-forget preserved; no backend auth/API contract change.
AiChatScreen listens to captured AccountService instance revision and UserProfileService.clear(null) stream, unsubscribes on dispose. Boundary clears visible messages, hidden bounded AI history, clarification, native pending/undo, ISO questions, queued plans, input/project context, mic/listening and old snackbars; closes client and recreates Brain/AssistantContext/native action port so stale in-flight native result cannot repopulate new pending/recent slots. Conversation epoch guards late AI plan execution, generic question replies/errors/retry callbacks, mic initialization/final transcripts/submission microtasks, speech-delayed result presentation, native summary writes and native read/Undo completion. Old summary routes tracked and removed without confirmation on boundary. Actual already-started/authorized SQLite commit may finish; no rollback or cancellation claim for in-flight durable commits. UI/remainder cannot leak into the new conversation. Persisted local module records/history are still device-local, NOT partitioned by account by this change; do NOT claim full native multi-account data isolation.
Manual Clear chat now calls same reset, fixing old behavior that removed visible messages but retained hidden AI history. Existing standalone native summaries preserve normal flow.7new real main/standalone widget cases: same-account relog clears context while profileedit preserves; oldaccountlateAI cannot offer record confirmation; localprofileerasure clears context; late generic answer ignored; late microphone final transcript ignored; Clear chat clears history/pendingquestion; logout removes old native record summary and actual SQLite remains empty. Auth service tests assert revision1afterlogin2afterlogout plus existing secure-store/logout/expired transport/registrationcontract cases. Initial3red probes captured build/ai-session-isolation-red.log; final selected946PASS0skips,500utterances735ms(build/ai-session-final-tests.log).4file analyze --fatal-infos clean(build/ai-session-analyze.log). No paidAI calls added/executed in this milestone; existing actualHaiku records fixture replayed. No new Railway retry this milestone; immediately preceding scoped attempt remains terminalpaused, newbackendnotlive.
Full goalACTIVE. Remaining: full native action/input adoption4.2, broader AI-assisted unparsed pending native/ISO replies, compound natural requests without explicit sequence connector, typedISOAsk/projected topology, account ownership policy for device-local module data if shared-phone accounts require separation, physical microphone/iOS and final5/6acceptance. Auth legalVersion4 is existing registrationcontract test, distinct from AIconsentversion5; not casually migrated. Backend deployment still required when Railway permits.


2026-10-21 heat-input visible-context milestone: HeatInputScreen opts into InputToolHandle only selectedHeatinput tab0; exports current process/standard,volts,amps,travel and explicitWPS efficiency override. Empty/invalid numeric remainsnull (neverdefault0); absenteta meansprocessdefault. Preheat/CEtab exposes empty map, not hiddenheatfields/chemistry. HeatInputSkill native_edit merges CURRENT ready route values plus newparsed edits, rather than staleconversation. Native Przelicz to/recalculate works only with visibleheatinputs. Calculate validation handles null/nonnum/nonfinite/range before domainmath; pendingAsk freezes validated/question snapshot like existingrolling pattern. Processchange drops oldWPSeta unless newlyexpliciteta; sameprocesspreservesactualoverride. AnswercontextSlots freezes canonicaldomaininputs, no inventedcomputed values. Existing partial set mode keepsnativebehavior.
Real LOCAL backend HTTP actualHaiku5.5 proof returned200 with57capabilities, recordedcostUSD0.0010230000000000005 under isolatedproofhardbudget0.03/maxRetries0. Userrequest restvaluesfromform/twohundredamps/result; actualvisibleGTAW,en1011,24V,110A,150mm/min,eta0.7. Modelcanonical Oblicz energię liniową TIG EN24V200A150mm/min OMITTED expliciteta, but actualnative merge preservesWPS0.7 and domainresult1.344kJ/mm. Exactrealproposal fixture test/fixtures/assistant_ai_actual_haiku_heat_input.json replayed inactual mainchat/nativepage withmanualV24/speed150. Actualdata not inferredfrommodel. Genericbuild/ai-live-request/proposal nowHEATcase; archived *-heat-input.json; priorrecords preserved *-records-03a588c.json. Backend build-assistant-live-proof.log currentheatproof. No productionAIavailabilityclaim.
Regressions: initial2realformred tests exposedmissingreadport. Broader router exposed10cooling.t85failures because it reusedHeatInputSkill.slotsFrom mutable/contextbehavior; split pure heatInputQuantities parser forcooling so native heat continuationmetadata cannot enter cooling. FinalmainAI/session/records/heat/catalog/perf920PASS0skips,500utterances711ms(build/heat-current-final-tests.log). Added actualvisibleheat→coolingroute case: explicitQ1 remains1 ratherthanexistingU/I/v/eta, actualCoolingTimePage5.98s. Finalheat/preheat/coolingdomain+UI+skills212PASS0skips(build/heat-current-domain-final-tests.log).5file --fatal-infos analyze clean(build/heat-current-analyze.log). No Dartsourcechanges afterthesechecks. Tests alsovalidate emptyampsasks/nooverwrite,CEtabhidesheatvalues,manualchangesbeatoldhistory,processswitchreseteta, nativeexactcommandsnoAIcall.
FullgoalACTIVE; currentvisibleinputadoption now5nativepages(rolling,pipeSlope,pipeRoute,tubeBending,heatInput), NOT allmodule4.2completion. Next: broadenmore realmoduleinput/actionports andAI-assistedpendingnative/ISOreplies, compoundrequestswithoutconnector, typedISOAsk/projectedtopology, localdataaccountownershippolicy, physicalmic/iOS/finalacceptance. NewbackendstillrequiresRailwaydeploymentwhenallowed; noretrythismilestone. Preserve03a588csessionisolation.


2026-10-21 AI-assisted native pending reply milestone: optional version1 context.pending_reply={skill_id,slot,choices<=6bounded128chars} plus native pending_question. Descriptor does NOT export partial native payload; existing consented visible conversation/history may contain prior user data as before. Screen restricts pending catalog toONE owner capability (57fornormal requests), reducing paid input. New proposal kind reply exactlyone canonical answer/sameid/emptymessage; execute forbidden whilepending descriptor. BackendstrictZod rejects wrong/unknown target,extra partial/credentialkeys,missingquestion,oversizedchoices beforepaidcall. Normal oldrequest contract compatible; replywithoutpending rejected. Native Brain.answerProposal serializes with_tail, verifies IDENTICAL still-owned AskResult/skill, source/canonical negation/quotedguard, parses with nativefillSlot andmerges onlyaskedscalarfield(+voiceorigin); compositeinputs strip module_action/native_action/native_edit/action/copy_field. Neverrebuild originalrecordorconfirmwrite. Ordinary choices/values/nativeactions/literalform prose stayoffline; relation/correction only goesAI. Nativequeue remainswaiting acrossAsk/Confirm and continues originalremaining steps onlyafteractual completion/save. NoConsent/outage/malformed/switchedtarget keepsoldquestion+data andneverfallsback towrongfirstnumber.
Realprovider evidence: actualLOCALbackendHTTP/api/fitter/ai/assistant→claude-haiku-5-5 returned200 kindreply legacy.save command2mm for Połowa czterech milimetrów. Firstfull57capcatalogcost0.0009753; onecapoptimizedrequestcost0.0002288 (actualusage ledger, not invoice guarantee). Testisolatedhardbudget0.03/sharedreservationbeforecall, maxRetries0,25s timeout unchanged. Exactoptimizedreply fixture test/fixtures/assistant_ai_actual_haiku_pending_reply.json replayed againstactual mainchat+SQLite: originalTIGSS60A/no-filler+missingwall, modelreplyfills2mm,NOrowbeforeconfirm, actualrow2mm60A thenqueuedparams.saved readsactualrow. Wrongtarget/outage/revokedconsent keepdraft; direct2mm repairs withoutanotherAIcall. Coreunit provesothermodelparsedfield200A cannotreplace original60A, stalequestionblocked, typedreplyenvelope1step, no nativeclearaction in composite, literal safety descriptions and pendingnativemode remainoffline.
Broadred regression initially2474PASS/38explicitmissingfixtureSKIP/5fail: nativehotwork/confinedprosewentAI, same-skillroute/slopecommandswentAI, plus previousheatPrzelicz matcher stole unitconversion. Fixed explicitAssistantSkill.literalReplySlots metadata forlocation/description; knownnonnatural nativecommands can supersedepending; nativevalidfieldanswers preservepriorbehavior; relational helper onlygates interpretation; heatgenericrecalc nowEXACTcanonicalphrase,notany Przelicz request. Native slopeMode andwznios60mm restored. SubsequentFULLassistant2482PASS/38preexistingfixtureSKIP0fail,500utterances736ms(build/ai-pending-reply-final-tests.log). ThenlocalizedlegacyinvalidfieldvalidationnowAskResult (ratherthanlosingdraft/reportinginvalidinputasmissingfeature), preservesdataforcorrection; finaltargeted927PASS0skip,500utterances666ms(build/ai-pending-validation-final-tests.log). Final11-file dart analyze --fatal-infos CLEAN(build/ai-pending-reply-analyze.log). No thresholdrelaxed/newskips. Skip38stillNOTallmodulecoverage.
Backend PR5 https://github.com/jakatora/fitter-welder-pro-backend/pull/5 attached/merged squash42e2fb297957ca6f4f8a454d81e817c872e6348d; canonicalDwtbranch feat/assistant-pending-replies head5dd183f35498f41c69b5dba9e20325e499b7f575 samecontent.202backendtestsPASS0skip(logs/assistant-pending-full-tests.log), HTTP/strictschema/budget/no-retry coverage. GitHubPRhead/files3/mergeablecleanverified; check-runsAPI403 tokenpermission unavailable,NOTclaimed CIpass. Primarynestedbackend cleanmainFFto42e2fb afterdirtyguard. ScopedRailwayupfor5dd183f terminalREJECTED Deploys have been paused temporarily, no deploymentID(logs/deploy-pending-reply-attempt.log). NewbackendNOTproductionlive; do not mistake actualLOCALHaikuHTTP forproductiondeployment.
FullgoalACTIVE. Nextpriority typedISOAskResult adapter so nativeiso pending states can use same replypipeline withoutreplayingdrawing, plusbroaderrealmoduleinput/actionports4.2, compoundwithoutconnector, localdataaccountownershippolicy, physicalmic/iOS/final5/6acceptance andRailwaywhenavailable. ISOrouteownedquestionsstilloutsideBrainandearlyguarded; NOTcoveredbythisgenericreplymilestone. Ordinaryconfirmationsstillnative; safetywritesstilltouchonly. Preservee044588heatinputs+03a588csessionisolation. Genericbuild/ai-live-request/proposal nowoptimizedPENDINGcase; archived*-pending-reply.json, firstfullcatalog*-pending-full-catalog.json; priorheat preserved*-heat-e044588.json. Backend build-assistant-live-proof.log currentoptimizedpendingproof.


2026-10-21: Typed ISO pending replies integrated with the existing native AskResult/AI reply pipeline. IsoDrawSkill reads an optional IsoQuestionPort (valve type, 45-degree plane, tee branch direction, append/new choice), so ordered AI plans pause before unresolved native drawing and resume only after actual successful execution. Direct native choices remain offline. fillProposalSlot preserves the richer native grammar while checking model-added valve DN/direction/compass against the original user reply; an AI-only DN80 cannot replace the stored DN50, but an explicit DN80 from the user is accepted. AnswerResult.actionCompleted=false distinguishes a native refusal from completion so an unsupported first ISO action cannot run the queued tail. Natural cancellation drops pending drawing and tail; a new explicit drawing supersedes the old plan. Per-screen ISO execution serialization and conversation-epoch guards prevent old-session replies from populating a newer conversation. Local IsoNotebookController.revision rejects delayed AI after manual undo/edit; it is not exported to the provider.
Verification: 11 new real-main-chat/native/SQLite integration tests cover valve choice/ordered sequence, direct and natural cancellation, superseding command, unsupported angle, delayed answer after native undo, invented vs explicit DN, append/new choice, natural 45-degree and tee-branch replies. The interpreter is controlled in these tests; no new real-provider ISO proof is claimed. Initial DN tests failed only because queued drawing animation remained unfinished at teardown; they now await actual controller completion and assert stored values. Actual ISO pending HTTP request captured in build/ai-live-request-iso-pending.json, but fetching isolated FWP credentials from Railway failed before any Anthropic call. Existing generic live-request/proposal restored as the matching prior wall-reply proof; no cross-project key was used.
Final regression: 2625PASS, 38 pre-existing missing-example fixture skips, 0fail across test/assistant + test/domain/iso_notebook + native ISO controller/autosave (build/ai-iso-question-final-regression.log). Router 500 utterances727ms; no budget relaxation. Targeted ISO packet54PASS0skip (build/ai-iso-question-targeted.log). Final static analysis and APK tracked separately below. No Dart source edits after this regression.
Cheap model continuity: backend runtime already defaults chat/intent to claude-haiku-5-5 with low effort where supported, no automatic provider retries and the shared pre-call budget/daily reservation. Fixed stale .env.example chat/intent values to match those defaults; docs-only PR6 https://github.com/jakatora/fitter-welder-pro-backend/pull/6 attached and merged to main3db3277a3aae136aa193f1f895cd6032ab995f82, head d9cde5a46178c39eaf806060c03222a668e3cf03. Verified exact head, one example file, mergeable clean and direct comparison to actual runtime defaults; no new runtime/budget/price changes, no CI-pass claim. Primary nested backend clean main fast-forwarded to3db3277. Canonical Dwt branch now docs/cheap-assistant-model-example d9cde5a, clean; its source content matches main3db3277. Prior runtime PR5 merge42e2fb remains included.
Railway: official https://status.railway.com reports Dashboard/API unavailable and builds paused (2026-10-21 incident, latest observed update19:55UTC); no blind redeploy retry or new infrastructure/billing change. Additional scoped project read now returns Unauthorized. Started normal browser railway login (session46658) and asked user to finish OAuth per Railway skill; confirmation pending, no refreshed-auth claim. Official outage and CLI auth are separate conditions. New /api/fitter/ai/assistant still not proven production-live; previous production probe404. Do not confuse local historical Haiku proof with deployment.
Goal ACTIVE. Remaining: all-module current-input/action adoption4.2 (5 pages currently), other ISO/native question cases, standalone-to-common ordered-plan handoff, compound requests without explicit connector, local record ownership across accounts, projected-node topology audit, physical microphone/iOS and final5/6 acceptance; real ISO provider proof and scoped Railway deployment after auth/platform recovery. Next concrete module candidate identified: lib/assistant/skills/fitter_tables/pipe_weight_skill.dart currently parses only utterance slots and has no current native input merge; inventory the corresponding actual screen contract before changing it. Preserve unrelated macOS registrant/pubspec.lock/.atlas.

2026-10-21 final ISO question analysis: all7changed Dart files dart analyze --fatal-infos CLEAN (build/ai-iso-question-final-analyze.log). Regression2625PASS/38pre-existing skips, router727ms. APK and source commit next.


2026-10-21: Pipe-weight visible-input AI context. FitterToolsScreen now implements InputToolHandle through an explicit private per-tab opt-in interface. Only the selected pipe_weight tab currently publishes its actual text-controller OD/wall/length/quantity and selected material; sibling tabs return an empty map, and ToolBridge still rejects hidden/wrong-target/dialog/unready routes. Blank or malformed values remain null, never invented 1m/1piece/zero defaults. This is the sixth native module with current-input export (rolling, pipeSlope, pipeRoute, tubeBending, heatInput, pipeWeight), not all 8 fitter tabs and not all-module completion. Existing PipeWeightSkill canonical execution/domain/native validation remains unchanged; flexible AI can now receive current form values and propose a complete native command for a requested edit. No deterministic native edit merge is claimed for pipeWeight, and no new real-provider proof is available.
Four real embedded-chat/native-screen tests prove manual length6000/quantity3 enter the actual AI request, a controlled canonical model proposal changes only quantity to5 and produces the independently checked native total mass from OD60.3/wall3.91/316L8000density, selected-tab isolation, empty/malformed input export, and rejection of a delayed proposal after manual wall change to2mm. Initial red actual getter returnednull; after opt-in, input tests pass. The malformed-value fixture originally used a forbidden minus sign, which the native positive numeric formatter correctly refused; corrected to an accepted incomplete decimal '.' and asserted actual controller text before expectingnull. No native input rules weakened.
Final appropriate regression934PASS0skip covering new native AI flow, pipe weight skill/domain, all fitter tab handles, mainAI execution/session isolation and full router corpus/performance (build/ai-pipe-weight-inputs-final-tests.log),500utterances656ms. Two-file dart analyze --fatal-infos CLEAN (build/ai-pipe-weight-inputs-analyze.log); no Dart changes after these checks. No new backend/paid API/budget/pricing changes or provider calls. Prior full ISO milestone2625PASS/38existingfixture skips remains a historical broader check, not a new full-suite claim for this increment.
Railway login session46658 is now TERMINAL exit1: Authentication timed out — no callback received after5minutes. No renewed-auth claim. Do not poll/restart that terminal handle or repeatedly launch expiring login windows without the user being ready; earlier asynchronous login question remains unanswered. Last actual production assistant POST probe404 (build/assistant-5d6ad02-production-probe.json). Backend main3db3277 still awaits scoped deployment with authorized account after authentication/platform recovery; no new infra or billing changes.
Goal ACTIVE. Latest installable stays APK5d6ad02 (ISO milestone); this pipe-weight source increment is not in that APK. Next coherent scope: explicit visible-input getters and real-tab tests for remaining7 fitter calculators (slope_cut,elbow_cut,elbow_rotation,insert,reducer,bevel,thermal_expansion), then remaining module actions/current inputs, real provider/production deployment, standalone ordered-ISO handoff, compound requests without connector, account-local record ownership, projected topology audit, physical microphone/iOS/final acceptance. Preserve unrelated macOS registrant/pubspec.lock/.atlas. Previous goal turn classified PROGRESS (committed ISO replies, docsPR6, verified APK and production404); current turn also concrete progress via new native read port and tests.


2026-10-21: Completed explicit current-input read ports for all8FitterToolsScreen calculators: slope_cut,elbow_cut,elbow_rotation,insert,reducer,pipe_weight,bevel,thermal_expansion. Supersedes prior note that sibling fitter tabs exportempty. Every tab opts into _FitterTabReadable and exports only its own actual controllers and selected enums through the parent InputToolHandle; hidden/wrong-target/unready/popup guards stay in ToolBridge. Insert exposes only active tableOD vs manualradius, never a stale hidden counterpart; emptygap maps0 exactly like nativecalc while malformedgap remainsnull. Thermal exports signed raw temperature_start_c/end_c plus the exact effective delta used by nativecalc (bothvalidtemps→absdifference, otherwise existingdeltafield), avoiding loss from the native rounded0.1display. No formula, validation, ShowInModule write contract, paid API invocation, price or budget change.
Verification:10new real selected-tab tests check all8actualform→AIrequest maps, manual edits/restoration, tab isolation, popup guard, manual/table radius switching with hiddenfieldretention excluded, nativegap semantics and signed temperatures -20.04→-20 yielding0.04 despite visible delta0.0. Priorpipeweight integrationtest now expects selected slope_cut's actual emptyfields instead of noopt-in. New scopeinitialred proved missing slope_cut inputs.14targeted testsPASS0skip(build/fitter-visible-inputs-modes.log). Final appropriate regression1205PASS/38pre-existing missing-example fixture skips across allfitterdomains/nativehandles/current-inputs, mainAI client/execution/session guards, modulecontracts andfullrouter(build/fitter-visible-inputs-final-tests.log),500utterances693ms. Three-file dart analyze --fatal-infos CLEAN(build/fitter-visible-inputs-final-analyze.log); no Dart edits after those checks. The38skips are not action completeness. New tests use the actual assistantAiRequest and nativeUI but no new realprovider call or production deployment is claimed.
Native input adoption now13moduleIDs: previous5(rolling,pipeSlope,pipeRoute,tubeBending,heatInput)+8fitter calculators. This is current-input context, not a universal deterministic edit merge: AI must still propose validated native commands. For example thermal nativeapply currently clears start/end temperature controllers when applying canonicaldelta; do not claim preservation of every raw UI representation for later partial edits. Allmodule4.2/physicalmic/iOS/final5/6 remain incomplete.
Infrastructure unchanged: earlier normalRailwaylogin46658TERMINALtimeout with no callback, no auth restored and no repeated loginlaunch. Last productionassistantPOST404 at5d6ad02proof; backendmain3db3277awaits scoped deployment after authorized account/platform recovery. Last actualHaikoproof remains prior wall/heat/records LOCAL HTTP fixtures, not the newgetter scope. Isolatedproject IDs unchanged. GoalACTIVE; preserve unrelated macOSregistrant/pubspec.lock/.atlas.
Next task candidate from actualsourceinventory: WelderToolsScreen gas,purge,pressure tabs remain outside the general module-input/apply bridge (parent onlywelder_calculators supportedFields={tab}, onlytimer applies). TimerSkill is integrated; pressure conversion exists inUnitsConvertSkill viaQuickConverter, andgas/purge questions routeKnowledgeSkill, but actualgas/purge calculators do not yet have equivalent nativeassistant execution. Inspect their existing domain functions and input semantics before implementing new nativeports/capabilities rather than only expanding readonly exports. Otherremaining scope: allothermoduleactions/inputs, realprovider+productiondeployment, standalone orderedISO handoff, compoundrequestswithoutconnector, localrecordownershipacrossaccounts, projectedtopologyaudit andphysicalacceptance. LastgoalturnclassifiedPROGRESS via0c896ffgetter; thisturn alsoPROGRESS via7moreexplicit nativeports andcurrentstateevidence.

2026-10-21: Gas/purge native assistant milestone: see [implementation and verification](2026-10-21-gas-purge-assistant.md). 2582PASS/38existing fixture skips, router671ms, five-file analysis clean; goal ACTIVE; deployment pending authentication.

2026-10-22: Further implementation evidence: [natural gas commands](2026-10-21-gas-natural-interpretation.md), [purge result to native countdown](2026-10-21-purge-timer-context.md), [account/profile/private-report session isolation](2026-10-22-account-session-isolation.md), and [native pressure conversion and current-input AI edits](2026-10-22-pressure-native-assistant.md). These milestones do not complete the overall module coverage or production/physical acceptance gates. Goal remains ACTIVE.

2026-10-22: [Natural timer configuration/control and exact current-state context](2026-10-22-natural-timer-control.md): timer.set configures without starting; native proposal checks preserve explicit action kinds/modes, pending replacement snapshots reject manual edits, and ordered configuration/start uses actual ready forms. Full regression 2693PASS/38existing fixture skips; final scoped 1004PASS; nine-file analysis clean. Production/runtime acceptance and the full goal remain ACTIVE.

2026-10-22: [Current-form context and natural edits in eight more modules](2026-10-22-current-form-assistant.md): actual controllers, selected modes and scalar context; native preservation for power/cable and t8/5 parameter edits. Controlled interpreter and native widget verification are recorded in the milestone; production deployment and full action coverage remain incomplete. Goal ACTIVE.

2026-10-22: [Native fitter calculator actions](2026-10-22-fitter-native-actions.md): shared toolbar/assistant copy and clear across all eight fitter tabs, retained tab state, actual native results, explicit target checks, ordered execution and cancellation after manual edits/navigation/consent change. Full assistant plus fitter domain/screens regression: 2959PASS/38existing fixture skips; six-file analysis clean. Individual fields/results, other module actions and full production/physical acceptance remain incomplete. Goal ACTIVE.

2026-10-22: [Jedna rozmowa przy wejściu z Premium](2026-10-22-single-assistant-presentation.md): wspólna instancja panelu, duża prezentacja i powrót z kalkulatora bez pustej strony. Rzeczywiste logowanie właściciela, rola admin, odczyt raportów i unieważnienie sesji potwierdzone na Railway; nowy endpoint sterowania AI nadal 404. Pełny cel ACTIVE.

2026-10-22: [Własne konto w nagłówku asystenta](2026-10-22-assistant-own-profile.md): nazwa i zawód z konta Railway, odtwarzanie istniejącej sesji, aktualizacja po edycji profilu i prywatna nawigacja do konta. Konwersacja nadal jest czyszczona przy zmianie sesji. Pełny cel ACTIVE.

2026-10-22: [Jawny zakres działań dla modelu](2026-10-22-assistant-action-scope.md): typowany opis kopiowania całych wyników i czyszczenia całych pól w ośmiu kalkulatorach; zgodny opcjonalny kontrakt backendu połączony w PR7. Aplikacja 1032PASS0skip, backend204PASS0skip. Produkcyjna trasa sterowania AI nadal404; pełny cel ACTIVE.

2026-10-22: [Podgląd bieżącej rozmowy](2026-10-22-assistant-conversation-view.md): dostęp do wcześniejszych wiadomości, źródła odpowiedzi, lokalne pytania/statusy bez przekazywania ich jako faktów AI, zachowany moduł/szkic/oczekujący plan, zamykanie prywatnych widoków przy zmianie sesji. Regresja100PASS0skip, końcowy zestaw27PASS0skip; pełny cel ACTIVE.
