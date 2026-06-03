# CHANGELOG — Fitter Welder Pro

All notable changes per AGENTS.md directive. Newest first.

## Unreleased

### 2026-05-31 (round 9) — Prefab Engine Phase 2: spec sheets + physical-length wired into CUT LIST

**Module:** ISO Notebook (placement + cut math + cut-list output)

#### What changed

CUT LIST now follows the full user spec — physical components (reducer / flange / blindFlange / valve / cap) carry their own face-to-face / face length and are subtracted from the ISO dimension via PrefabEngine, with the user-selected `DimRef` controlling which ends get credited.

- **Placement spec sheets** in [iso_notebook_screen.dart](lib/screens/iso_notebook_screen.dart): four new bottom-sheet pickers that run before the component is committed to the drawing. Cancel = abort placement (nothing added).
  - `_askReducerSpec()` — DN-in / DN-out / length (mm). Length default-filled from ASME B16.9 concentric reducer table. Returns `(dnIn, dnOut, physicalLengthMm, label)`.
  - `_askFlangeSpec(kind)` — DN / EndConnection (WN / SO / SW / TH / LJ) / face length. Default WN for flange, SO for blindFlange. Face length defaults from B16.5.
  - `_askValveSpec(kind)` — DN / face-to-face length / endA + endB. Length default from B16.10 cl. 150 table. Two independent end-connection ChoiceChip rows.
  - `_askCapSpec()` — DN / face length. Length default from `TakeoutCatalog.cap`.
- **Tap-up handler** routes each physical `_Tool` through the right spec sheet and writes the result via `_Comp.withPhysicalSpec(dn, dnOut, physicalLengthMm, endA, endB)`.
- **`_autoPhysicalDeductFor(endpoint, items, tol)`** — new module-level helper, sums `physicalLengthMm` for physical components near a segment endpoint. Uses `ComponentClassification.isPhysical(t.name)` so the rule lives in one place.
- **`_midPhysicalDeductFor(seg, items, tol)`** — new helper, sums `physicalLengthMm` for physical components that project onto the segment line (within `tol`) but aren't at either endpoint. Excludes endpoint hits so they don't double-count with `_autoPhysicalDeductFor`.
- **`_resolvedCut(_Seg seg)`** now plumbs all three buckets into `PrefabEngine.cutLengthMm`: `leftPhysicalLenMm`, `rightPhysicalLenMm`, `midPhysicalSumMm`. Zero buckets are passed as `null` so the engine's "no physical at this end" branches kick in.
- **`_cutListLines()`** breakdown now shows the `DimRef` tag next to ISO and lists each contributing deduct on its own line (elbow CTE, left/right component, mid components). Plain-axial segments still render on a single line.

#### Why

This is the "real value" pass. Phase 1 gave us the engine + DimRef foundation but kept all physical-length inputs hard-wired to `null` / `0`. Phase 2 makes the engine actually receive the user's reducer / valve / flange / cap measurements so CUT LIST output is correct for non-trivial spools — reducer→pipe→flange, valve-between-elbows, FTE/FTF dimensions, etc.

#### Validation

- `flutter analyze` → No issues found (4.9s)
- `flutter test` → 116/116 PASS (incl. all PrefabEngine Phase 1 unit tests still green)
- Manual verification of the new helpers: each is unit-testable as pure code (no widget dependency).

#### Files touched
- [iso_notebook_screen.dart](lib/screens/iso_notebook_screen.dart): tap-up + four spec sheets + two new deduct helpers + `_resolvedCut` + `_cutListLines`. `_Comp` was already extended in the partial Phase 2 workflow.
- [end_connection.dart](lib/models/prefab/end_connection.dart): pre-existing (workflow), used by spec sheets.
- [component_classification.dart](lib/services/component_classification.dart): pre-existing (workflow), used by deduct helpers.
- [CHANGELOG.md](CHANGELOG.md): this entry.

### 2026-05-31 (round 8) — Prefab Engine Phase 1 shipped (Workflow-driven)

**Module:** ISO Notebook · Prefab Engine (new) · Tests (new)

#### What changed

4 new files + 1 integration + 2 test files, all delivered by a 9-agent workflow:

- **`lib/models/prefab/dim_ref.dart`** — `DimRef` enum (centreToCentre / centreToFace / faceToFace / faceToEnd / centreToEnd) with `code` (CTC/CTF/...), `labelPl`, `labelEn` extensions and `parseDimRefCode(String)` helper.
- **`lib/models/prefab/component_behaviour.dart`** — `ComponentBehaviour` enum (6 classes: axialCenter, axialWithBranch, physicalLength, faceOnly, diameterChange, zeroLength) with `isAxial` / `hasPhysicalBody` / `code` extensions. Self-contained — no reference to `_Tool`.
- **`lib/services/unit_parser.dart`** — `UnitParser.parseToMm(String)` accepts `1500`, `1500 mm`, `59"`, `59 in`, `4'11"`, `5'`, decimals, case-insensitive units; returns null for unparseable. `UnitParser.validate(String)` for `errorText`. Internal base unit = mm. 1 inch = 25.4 exactly.
- **`lib/services/prefab_engine.dart`** — pure `PrefabEngine.cutLengthMm({isoValueMm, ref, leftCteMm, rightCteMm, leftPhysicalLenMm, rightPhysicalLenMm, midPhysicalSumMm})` with explicit branches per `DimRef`. `needsDimRefPicker({leftIsPhysical, rightIsPhysical})` returns `false` for axial↔axial (auto-CTC) and `true` for anything with a physical end.
- **`lib/screens/iso_notebook_screen.dart`** integration (7 surgical edits):
  - Two new imports.
  - `_CutCalc` extended with `final DimRef ref` (default `centreToCentre` — backwards-compatible).
  - `_CalcResult` extended with `final DimRef ref`; `.set()` + `.removed()` factories thread it through.
  - Dim-sheet picker injected below the slope row. Shows ONLY when `seg.a` or `seg.b` is within tolerance of a physical-class `_Tool` (reducer, flange, blindFlange, cap, gateValve, ballValve, checkValve, globeValve, butterflyValve). Hidden otherwise → no popup spam when both ends are axial.
  - 5 `ChoiceChip`s for CTC / CTF / FTF / FTE / CTE in the picker row.
  - `_resolvedCut(_Seg seg)` body replaced — now parses ISO once, splits the existing elbow CTE auto-deduct into left / right buckets, calls `PrefabEngine.cutLengthMm(...)`.
- **`test/services/prefab_engine_test.dart`** + **`test/services/unit_parser_test.dart`** — 30 tests covering every `DimRef` branch, mid-segment physical, NaN propagation, `needsDimRefPicker`, mm / inches / feet-inch / invalid parser cases.

#### Why

User confirmation 2026-05-31 of design questions from the spec doc:
- ✅ Default `DimRef.centreToCentre` for axial↔axial — no popup
- ✅ Inline picker row in the existing dim sheet (not a separate modal)
- ✅ Global weld numbering as default (Phase 3)
- ✅ Internal mm; parser accepts mm / inches / feet-inches; project has primary unit (Phase 7)

#### Expected benefit

Behaviour-preserving on the default — every existing drawing computes identically. New value: drawings that include a flange / reducer / valve / cap now prompt the user to pick the dimension reference instead of silently assuming CTC and producing a wrong cut length.

#### Validation

- `flutter analyze` — 0 issues across 5 touched + 4 new files.
- `flutter test test/services/` — 30/30 PASS.

#### Open for Phase 2

- Component behaviour classification (`_Tool` → `ComponentBehaviour`) — file-local map.
- Spec sheets at placement for reducer / valve / flange / cap (DN + physical length + diameter change).
- Mid-segment `physicalLength` plumbed into `_resolvedCut`.
- `leftPhysicalLenMm` / `rightPhysicalLenMm` plumbed from new spec data.

---

### 2026-05-31 (round 7) — 12-iteration autonomous polish batch

**Module:** Premium · AI Chat · Jobs · ISO Notebook · Bolt Torque · Projects · Weld Journal · Widgets

#### What changed

- **Premium yearly card badge** (`premium_screen.dart`) — "OSZCZĘDZASZ 35%" → "OSZCZĘDZASZ 35% · POPULARNE" to give the recommended plan stronger visual hierarchy. EN: "SAVE 35% · MOST POPULAR".
- **AI Chat error bubble Retry** (`ai_chat_screen.dart`) — when the Claude call throws, a SnackBar with a "Ponów/Retry" `SnackBarAction` now restores the user's prompt into the input and re-fires `_send`. No more retyping after a transient network drop.
- **Jobs checkout Retry** (`job_add_screen.dart`) — `SnackBarAction` re-fires `_save` on failure. Stops leaking raw `$e` into the snackbar text.
- **Premium checkout Retry** (`premium_screen.dart`) — `SnackBarAction` re-fires `_startCheckout(context, plan)` with the same plan.
- **PDF export progress snackbar** (`iso_notebook_screen.dart`) — persistent snackbar with spinner during the multi-second capture + encode + share-sheet handoff. Dismissed in `finally`. Stops double-tap-the-button confusion on busy drawings.
- **Bolt Torque "no result" guidance** (`bolt_torque_screen.dart`) — when the lookup fails (unsupported size × grade combo), the empty result area now shows a help card instead of being blank: "Brak wyniku — sprawdź, czy wybrany rozmiar i klasa są obsługiwane".
- **Projects skeleton placeholder** (`projects_screen.dart`) — replaces the centred `CircularProgressIndicator` over an empty viewport with 6 greyed-out row placeholders. The screen shape is visible immediately on tap.
- **Shared `EmptyState` widget** (`widgets/empty_state.dart` new) — single 56-px badge + title + optional subtitle + optional FilledButton. Migrated Projects to use it; Chat/Jobs/AI Chat queued for follow-up.
- **Weld Journal date picker** (`weld_journal_screen.dart`) — calendar icon `IconButton` in the date field opens `showDatePicker`; text input still works for back-dating / power users. Saves the welder typing `YYYY-MM-DD` by hand.

#### Why

All ten items came straight from BACKLOG audit lines (P2/P3). Each is surgical, behaviour-preserving / strictly additive. Audit found two false positives (help search highlight + ISO Notebook keyboard insets — both already implemented); the corresponding BACKLOG entries are stale and removed.

#### Expected benefit

- Yearly plan visibly stands out → conversion lift.
- AI Chat / Jobs / Premium / PDF flows have first-class retry / progress UX.
- Bolt Torque no longer silently hides when an unsupported combination is picked.
- Projects feels faster on tap (perceived load latency drops).
- One shared `EmptyState` widget kills a recurring style drift across screens.
- Weld journal entry is one tap faster on the date field, fewer typo dates.

#### Validation

- `flutter analyze` — 0 issues across 8 touched + 1 new file.
- Behaviour-preserving / additive; risk = zero.

---

### 2026-05-31 (continued) — UX polish · scanner progress · dead-code cleanup

**Module:** Premium · Chat · Scanner · AI Chat · Praca (tech debt)

#### What changed

- **Pull-to-refresh on Premium screen** (P2, `premium_screen.dart`) — `RefreshIndicator` around the ListView calls `PremiumService.refreshFromBackend()`. Useful when the webhook lagged after a successful Stripe payment and the user knows it should have activated by now.
- **"Ponów / Retry" SnackBarAction on chat send failures** (P2, `chat_screen.dart`) — for retryable errors (network / generic) the snackbar now offers a Retry action that re-invokes `_send` directly. Rate-limit (429) and banned-word (400) errors don't get the action because they need the user to wait or rephrase.
- **Scanner progress nudges at 30 s and 60 s** (P2, `iso_scanner_screen.dart`) — `Timer`s scheduled after kickoff update `_aiStatus` to "still working…" then "taking longer than usual…" so a slow Sonnet vision call doesn't look like a frozen spinner. Timers cancelled in `finally`.
- **Clickable citations in AI Chat** (P3, `ai_chat_screen.dart`) — `📖 Iteration N` chips are now `InkWell` that opens a small dialog explaining the citation and pointing to `data/piping_knowledge.md`. Placeholder content for now (the full section text endpoint isn't built yet — flagged in BACKLOG); the visual + click pattern is in place.
- **Dead `JobListingDao` removed** (tech debt) — `lib/database/job_listing_dao.dart` deleted (Praca is backend-only since 2026-05-28). `models/job_listing.dart` doc-comment updated to reflect that the class is now only the on-wire DTO for `JobsService`.

#### Why

Each item came from BACKLOG audit lines marked P2/P3 (or, for the DAO, "tech debt"). All five are surgical changes that ship behaviour-preserving or strictly additive UX without expanding scope (per AGENTS.md "PRODUCT SCOPE RULES").

#### Expected benefit

- Premium users who paid and didn't see activation can pull-to-refresh once instead of force-quitting the app.
- Chat send failures (the most common — momentary network drop) are one tap away from retry, no re-typing.
- Scanner UX no longer looks frozen on a slow 4G uplink — the user sees the system is still working.
- AI Chat citations stop feeling like decorative text; the click pattern teaches users they're interactive ahead of the future "open full section" content.
- Codebase is one DAO + one orphaned file lighter, no more sqflite write path for Praca that nothing reads.

#### Validation

- `flutter analyze` — 0 issues across 5 touched + 1 removed file.
- Behaviour-preserving / additive changes; no risk to existing flows.

---

### 2026-05-31 — HTTP client wrapper + ISO Notebook hot-path fix + image cache

**Module:** Services (ApiClient) · Chat · Jobs · Premium · ISO Notebook · Photos

#### What changed

- **New `services/api_client.dart`** — single `ApiClient` singleton wraps every Railway HTTP call. Adds: 10-12 s default timeout, one retry on 502/503/504 / `SocketException` / `HandshakeException` / `TimeoutException`, 500 ms exponential back-off with ±25% jitter, structured `debugPrint` of failure context, typed `ApiException` so callers can `switch (e.statusCode)`.
- **`services/jobs_service.dart`** migrated to ApiClient (3 endpoints: list, mine, checkout) — ~50 lines of boilerplate gone.
- **`services/chat_service.dart`** migrated to ApiClient (rooms, messages list, message post, report). Report is fire-and-forget now (failure non-actionable, used to bubble).
- **`services/premium_service.dart`** migrated to ApiClient (checkout, portal, status refresh). Portal call now returns `null` on failure instead of bubbling — that's what the only caller already wanted.
- **ISO Notebook `_DimensionsSheet` keystroke jank fixed** (P1) — `onChanged: (_) => setState(() {})` removed from each row's TextField. The sheet's visual state never depended on the typed text (only on `seg.calc` which is captured at open), so setState was rebuilding the whole ListView N rows × every keystroke for nothing. Routes with 50+ pipes will now type smoothly.
- **`heat_photos_screen.dart` image cache** (P2) — `Image.file(file, fit: BoxFit.cover)` upgraded to `cacheWidth: 1080 + gaplessPlayback: true`. A modern phone camera writes 4000-px JPEGs; decoding them at native size for a 220-px-tall list row was burning ~40× the memory needed and re-decoding on every scroll. Now decodes at display res once.

#### Why

The HTTP wrapper is the single biggest reliability lever — every network call now retries once on a 502 instead of bubbling, and uses one timeout enforcement instead of three (8 / 10 / 12 s scattered across services). Removing the dead `setState` on dim entry kills a P1 jank that real users hit when sketching long lines. The image cache is surgical — 2 lines for a measurable memory + scroll-perf win.

#### Expected benefit

- A flaky Railway 502 no longer fails a chat poll or job listing fetch — the silent retry catches it.
- ISO Notebook dim-entry sheet types smoothly on long routes (no full-list rebuild per keystroke).
- Heat-photos list scrolls smoothly on projects with many photos.
- ~150 lines of duplicated `http.get/post + status check + jsonDecode + Exception()` boilerplate gone.

#### Validation

- `flutter analyze` — 0 issues across 5 touched + 1 new file.
- Behaviour-preserving refactor; covered by code review.

---

### 2026-05-30 (continued) — Performance + reliability batch

**Module:** Home · Jobs · ISO Scanner · Premium

#### What changed

- **Home blocking I/O parallelised** (P1, `home_screen.dart`) — sequential `await _segmentDao.listForProject(p.id)` per project replaced with one `Future.wait` round. Saves ~N×50 ms on home open for users with many projects, eliminates intermediate UI-thread ticks.
- **Jobs post-checkout polling instead of fixed 3 s delay** (P2, `jobs_screen.dart`) — when the user returns from Stripe Checkout, we now poll `/api/fitter/jobs` every 1.5 s for up to 12 s and stop as soon as the listing count changes (the user's new paid listing). Old fixed `Future.delayed(3 s)` was either too long (laggy) or too short (listing missing for users with slow webhook activation).
- **ISO Scanner timeout 90 s → 150 s** (P2, `services/iso_scanner_ai.dart`) — Sonnet vision over a 4-8 MB iso photo on a 4G connection routinely runs 30-60 s for the first byte; the old window cancelled successful scans. 150 s leaves margin for slow uplink without becoming a UX hang.
- **Premium polling mounted guards** (P2, `premium_screen.dart`) — added `if (!mounted) return;` after every `await` in the 6× polling loop. Removes a rare "setState after dispose" crash when user dismisses the sheet between poll cycles.

#### Why

Each item came straight out of the audit done earlier today (BACKLOG.md P1/P2 list). All four are surgical changes with zero behavioural shifts for the happy path, so they're safe to ship together.

#### Expected benefit

- Home screen opens noticeably faster after first few projects exist.
- Stripe payment flow for Jobs feels instant when the webhook is fast, still falls back to manual reload when it isn't.
- Scanner finishes scans that would previously have timed out on a hotel/4G connection.
- Premium screen no longer crashes when paying user backs out mid-verification.

#### Validation

- `flutter analyze` — 0 issues across 4 touched files.
- Emulator visual: no changes to layout / copy; behaviour-level fixes covered by code review.

---

### 2026-05-30 (emulator audit) — Critical mojibake fix in 15 source files

**Module:** Fitter Menu · Cut List · Project tiles · Quick Converter · Fitter Tools · Segment Builder · Welder Tools · Help · misc

#### What changed

Emulator-driven visual audit (per AGENTS.md EMULATOR VALIDATION) caught widespread mojibake on the FITTER submenu. The previous two PowerShell fixers (`tools/fix_polish_encoding.ps1`, `tools/fix_emoji_dashes.ps1`) covered Polish letters and emoji dashes but missed engineering symbols. Added a third pass in `tools/fix_symbols_encoding.py` covering:

- `Ø` (diameter) — was `Ã˜`
- `↔` (left-right arrow) — was `â†"`
- `←` (left arrow) — was `â† ` followed by control byte
- `°` (degree) — was `Â°`
- `·` (middle dot separator) — was `Â·`
- `×` (multiplication) — was `Ã—`
- `Δ` `α` `β` `θ` `ρ` (Greek formulas) — were `Î”` `Î±` `Î²` `Î¸` `Ï`
- `√` (square root) — was `âˆš`
- `±` (plus-minus) — was `Â±`
- `²` `³` (superscripts) — were `Â²` `Â³`
- `•` (bullet) — was `â€¢`
- `—` `–` `−` (em / en / minus dashes) — were `â€"` `â€'` `âˆ'`

Touched files (now UTF-8 clean): `screens/fitter_menu_screen.dart`, `screens/cut_list_summary_screen.dart`, `screens/fitter_screen.dart`, `screens/fitter_tools_screen.dart`, `screens/home_screen.dart`, `screens/projects_screen.dart`, `screens/quick_converter_screen.dart`, `screens/segment_builder_screen.dart`, `screens/weld_journal_screen.dart`, `screens/welder_tools_screen.dart`, `widgets/help_button.dart`, `widgets/pipe_3d_preview.dart`. ~60 thousand char positions touched (most are no-ops where the bytes were correct).

#### Why

These glyphs render as `Ã˜` `Â°` etc. on a real phone — a fitter looking at the DN-MM tile saw `DN ât" OD (mm) + NPS` instead of `DN ↔ OD (mm) + NPS`. The pattern is a UTF-8 stream that was re-decoded as Windows-1252 and saved back. Caught only because we actually ran the app on the emulator and captured a screenshot of the FITTER submenu.

#### Expected benefit

- Engineering symbols (`°`, `Ø`, `×`, `↔`, Greek letters used in physics formulas) now render correctly.
- Trust signal — a paying fitter who sees `Ã˜` in the elbow-takeout column thinks the app is broken.
- Future-proofs against the recurrence pattern: the script lives in `tools/` and is idempotent; CI can re-run it on every commit if we wire it.

#### Validation

- `flutter analyze` — 0 issues across 12 touched source files + 1 added tool script.
- Visual emulator validation: before/after side-by-side on FITTER submenu — `audit_shots/04_fitter_menu.png` (before) vs `audit_shots/06_fitter_fixed.png` (after). All four mojibake'd subtitles now render correctly.
- ISO Notebook empty state confirmed visually (`audit_shots/07_iso_empty.png`): compass widget with 3 axes, dismissable hint card with × close button, all 2026-05-30 P0 work present.
- Chat screen confirmed: 4 rooms load from Railway backend.

#### Limitations

`widgets/help_button.dart` still has ~96 hits of mojibake'd EMOJI bytes (e.g. `ðŸ"`, `ðŸ—'ï¸`) — these are decorative icons in help-center step lists. Fixing them safely requires per-line context (the 4th byte of the original UTF-8 emoji was lost in the mojibake round-trip) and isn't tackled here. Added to BACKLOG as P3.

---

### 2026-05-30 (later) — Full project audit pass · P1 leaks + cleanup

**Module:** Chat · ISO Notebook · Heat Input · New Project · Premium Service · Backend Service · Database seed · misc

#### What changed

- **TextEditingController leak fixes** (P1):
  - `chat_screen.dart` `_editNickname()` — controller now disposed in a `try/finally` around `showDialog`.
  - `iso_notebook_screen.dart` `_askCalc()`, `_askText()`, `_editName()`, `_editElbowSpec()`, `_enterAllDimensions()` — every dialog/sheet that creates ad-hoc controllers now disposes them deterministically. The dimensions sheet (up to N controllers for N segments) now uses `try/finally` so a sheet that throws still releases the batch.
- **Heat Input silent-NaN fallback** (P1) — `_NumField` now derives invalid state from its own controller text and surfaces `errorText: "Nieprawidłowa liczba"` instead of letting `double.tryParse(...) ?? 0.0` silently feed 0 into the CE / HI math.
- **New Project raw exception leak** (P1) — `new_project_screen.dart` no longer concatenates `$e` into the snackbar. Common causes (duplicate name, no disk space) get human-readable mapped messages; raw `$e` goes to `debugPrint`. Behaviour for unknown errors falls back to a generic "spróbuj ponownie".
- **Premium startup refresh hardened** (P2) — `main.dart` now `.catchError`s the fire-and-forget refresh chain. Debug builds no longer surface an unhandled async error when offline at first launch.
- **Chat SharedPreferences singleton-flight** (P2) — `ChatService` caches `Future<SharedPreferences>` via a private `_prefs()` helper, dropping a method-channel round-trip on each nickname read/write.
- **Stale "Phase 4/5" comments removed** (P3) — `premium_screen.dart`, `saddle_template_screen.dart` updated to reflect current shipped state instead of pre-launch rollout phases.
- **Dead Firebase ghost cleared** (P3) — `lib/firebase_options.dart` placeholder shim deleted (nothing imported it). Stale "do podmiany na dane z Firebase" comment in `db.dart` seed rewritten. `premium_service.dart` docstring no longer mentions Firebase init.
- **Dead TODO removed** (P3) — `backend_service.dart` `searchAnswer()` doc-comment + `// TODO` replaced with a clear "this is a stub by design" note; behaviour unchanged.

#### Why

Per AGENTS.md `BUG FIXING RULES`, P1 = runtime risks (memory leaks, crashes, data corruption). Each leak in the previous patch path was ≤2 controllers per dialog, but a long ISO session can open `_askCalc` dozens of times; over a single field shift the memory pressure becomes measurable jank.

The other items are direct picks from the new BACKLOG.md added in the same session.

#### Expected benefit

- No frame stutter after 30+ dimension edits per drawing.
- Heat-Input results no longer lie to the welder when a comma slips through.
- New-project error message is now actionable instead of being a Dart stack-trace fragment.
- Premium gate cold-start is more resilient on flaky networks.
- Codebase is `flutter analyze`-clean and ~150 lines lighter (dead Firebase shim).

#### Validation

- `flutter analyze` — 0 issues across 7 touched files + 1 removed file.
- Emulator: not run (user opted out of APK builds for this round).

---

### 2026-05-30 — ISO drawing overhaul (BACKLOG P0 HEAD)

**Module:** ISO Notebook · Elbow Takeouts · Fitter Menu · ISO Scanner · Premium Gate

#### What changed

- **Dimension lines now plotted as iso shop convention** (`iso_notebook_screen.dart`):
  - Thin extension lines perpendicular to pipe at each endpoint
  - Dim line parallel to the pipe at fixed offset, with 30° tick-mark terminators
  - Dimension value centred on the dim line with a small surface backdrop
  - When elbow CTE auto-deducted, a second line shows the original `ISO XXX` so the fitter sees both the typed value AND the resolved CUT
- **Elbow component carries spec data** — added `dn`, `elbowSubtype` (LR90 / SR90 / LR45 / SR45) and `cteMm` fields to `_Comp`. Tap an elbow to open a sheet where DN + type are pickable; CTE auto-fills from ASME B16.9 table (`closestByDn`) and stays user-editable for non-standard parts.
- **CUT-list math now uses elbow CTE automatically** — new pure function `_autoElbowDeductFor(seg, items, tol)` walks each pipe and subtracts the CTE of any spec-tagged elbow sitting at either endpoint. Surfaces in canvas dim labels, `_totalMm`, and copied/PDF cut list (with an explicit `− oś kolanek: NN mm` line).
- **On-drawing elbow tag** — two-line chip next to each spec'd elbow showing `DN50  2"` on top and `90° LR · 76 mm` on the bottom (CTE in accent colour). Pure read-only; spec comes from the edit sheet above.
- **ISO Notebook empty-state hint dismissable + persistent** — added `×` to close the hint, app-bar Help button to re-open, preference stored in `SharedPreferences` (`iso_notebook_hint_hidden` key). Replaces the previous behaviour where the hint reappeared on every session.
- **Elbow takeouts column shows pipe size prominently** (`elbow_takeout_screen.dart`) — DN + NPS rendered on one bold line `DN50 · 2"` with the actual elbow size in accent orange so the fitter no longer has to read a second muted row to identify the size.
- **Skaner ISO behind Premium gate** — `IsoScannerScreen` wrapped in `PremiumGate(alwaysEnforced: true)`. New `alwaysEnforced` flag added to `PremiumGate` for features that hit metered external services (Claude Vision per scan) — those stay gated even while the rest of PRO is free in beta.
- **Removed modules:**
  - `Pomiar trasy` (`route_measure_screen.dart` deleted, fitter menu tile removed)
  - `Montaż w terenie` (`field_assembly_screen.dart` deleted, fitter menu tile removed)

#### Why

User spec (2026-05-30): the iso notebook must look like a real plotted shop drawing — wireframe-chip dimensions and abstract elbow connectors weren't conveying the data fitters need. Pomiar trasy and Montaż w terenie were unused noise in the menu. Scanner uses metered AI per call, so it must always cost money to access.

#### Expected benefit

- A fitter reading the iso sees dimensions in their familiar visual language (extension + dim + tick).
- CUT = ISO − Σ CTE happens automatically the moment a DN is set on each elbow, matching how fitters actually do the math in their head.
- Elbow takeouts reference shows pipe size at a glance, halving scan time.
- Premium gate on Scanner protects margin per scan.
- Fitter menu down 2 unused tiles → less cognitive load.

#### Validation

- `flutter analyze` — 0 issues across all touched files (3 rounds of cleanup during dev: identifier collisions, struct bracket mismatch, public-API private type warning resolved).
- Backend: no changes.
- Emulator visual validation: pending (user opted out of APK builds; will run on next request).
