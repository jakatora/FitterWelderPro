# Raw audit findings — 2026-06-08 (round 2)

One block per iteration. Synthesis phase will dedupe + consolidate with c:\Users\Startklaar\Documents\FitterWelderPro\BACKLOG_2026-06-07.md.

P0 items shipped today (commit d025247):
- P0-01 weld journal mounted/try-catch guards
- P0-02 _ensureTable selective catch
- P0-03 iso scanner cut total guard + AI clamp + warning chip
- P0-04 premium service 2-minute downgrade grace
- P0-05 rolling offset stale-result clear

Round-2 audit MUST verify these don't have edge cases or regressions.

---

## Iter #1 · lib/screens/iso_notebook_screen.dart · regression-check-p0-fixes

- **severity**: high
- **location**: lib/screens/iso_notebook_screen.dart:4738-4747 (PDF watermark painter `total`) and 2942-2950 (`_totalMm` getter feeding clipboard summary + PDF cut-list + stick-nesting hint at 3048-3052)
- **issue**: P0-03 was applied only to `iso_scanner_screen.dart`. The exact same bug class lives untreated in `iso_notebook_screen.dart`: both `total += v` (painter) and `sum += v` (`_totalMm`) gate on `v.isFinite` ONLY — negative cuts (components longer than ISO, the case the dialog flags in red at 1595-1612) silently subtract from the total. A single mistyped ISO like `300-500` (operator subtracted a deduct twice) poisons the headline CUT, the clipboard summary, the printed PDF cut-list ("Suma CUT") AND the stick-nesting hint (sticks count under-reports stock to buy).
- **why it matters**: Fitter copies the PDF cut-list to the saw and is short pipe stock for the day — the very scenario P0-03 was supposed to eliminate, now leaking through the sister screen.
- **suggested fix**: Replicate the P0-03 pattern verbatim — `if (v.isFinite && v >= 0) total += v; else if (v.isFinite && v < 0) invalid++;` plus surface `_invalidSegmentCount` in `_SummaryBar` and on the PDF watermark ("N do sprawdzenia" red chip).
- **effort**: M
- **round1Ref**: P0-03 (extension to sister screen — same class, new file)

--- end block ---

## Iter #1 · lib/screens/iso_notebook_screen.dart · regression-check-p0-fixes

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:75-95 (`_CutCalc.cutMm`), 1351 (`parseIsoExpression(isoCtrl.text)`), 2898 (`isoMm = parseIsoExpression(c.iso)`), 2924
- **issue**: P0-03 clamped AI dimensionMm to (0, 100000) to defang vision-model hallucinations. Manual ISO entry in the notebook has NO upper bound — a fitter typing `15000000` (15 km, easy thumb-fumble of `15000`) or `15000+1500-80` (mixed orders of magnitude from chained route segments) sails through `parseIsoExpression` and lands in the CUT-list total without a single warning. Combined with the negative-cut bug above, total integrity is a function of operator typing accuracy.
- **why it matters**: Workshop quoting and saw-list rely on these numbers — out-of-bound values quietly corrupt material orders without ever firing the "Komponenty dłuższe niż ISO" red warning (which only catches the negative case).
- **suggested fix**: Add a sanity guard in `_CutCalc.cutMm` (and the live dialog at 1349-1361) that clamps the parsed `isoMm` to the same `(0, 100000)` window used in P0-03 and surfaces a "Sprawdź wymiar" hint above ~100 m.
- **effort**: S
- **round1Ref**: P0-03 (parallel of the AI-clamp half — manual-entry path)

--- end block ---

## Iter #29 · lib/services/chat_service.dart · pdf-print-quality

- **severity**: low
- **location**: lib/services/chat_service.dart:1-220 (entire module)
- **issue**: `chat_service.dart` is a pure networking + SharedPreferences service for the community chat (rooms, messages, nickname, report). It contains no PDF generation, no `pw.*` widgets, no `Printing.layoutPdf` call, no font/glyph loading, no page-size logic. The pdf-print-quality lens has no direct surface here — chat messages are never rendered into the PDF cut-list, weld-journal export, ISO summary or any other printable artifact in the app today.
- **why it matters**: Workshop staff print cut-lists and weld logs on shop-floor printers (mono A4); they do not print chat threads. No fitter is affected by the print quality of this module.
- **suggested fix**: No action under this lens. (Adjacent observation only — not a finding: if a future feature exports a chat thread to PDF, the post path at :186-204 has no client-side length/control-char normalization, which would matter for `pw.Text` rendering then. Out of scope today.)
- **effort**: S
- **round1Ref**: new (lens N/A — module is networking only, no print surface)

--- end block ---

## Iter #1 · lib/screens/iso_notebook_screen.dart · regression-check-p0-fixes

- **severity**: high
- **location**: c:\Users\Startklaar\Documents\FitterWelderPro\test (whole directory) — no `iso_notebook_test.dart`, no `iso_scanner_test.dart`, no `weld_journal_test.dart`, no `rolling_offset_test.dart`, no `premium_service_test.dart`. Only `prefab_engine_test` + `unit_parser_test` under `test/services/`.
- **issue**: ZERO widget/unit tests cover the five P0 fixes shipped in commit d025247. The commit message "120 tests pass" is true but vacuous — the new behaviours (mounted guards, selective `_ensureTable` catch, `_totalCutMm` negative-skip, `_invalidSegmentCount` exposure, `_pendingDowngradeAt` 2-min grace, rolling-offset stale wipe) have no regression net. Any future refactor silently re-introduces the original ship-blockers.
- **why it matters**: P0 fixes are one bad merge away from regressing without anyone noticing until users hit the same wedged spinner or wrong saw cuts that prompted today's audit.
- **suggested fix**: Add widget test for `WeldJournalScreen` (`_load` rethrow surfaces SnackBar, `_saving` cleared on error); `PremiumService` unit test for the downgrade-grace state machine (3 reads across 2 min); unit test on `_totalCutMm` covering negative + non-finite; widget test on `RollingOffsetScreen._calculate` confirming controllers clear before early-return.
- **effort**: L
- **round1Ref**: new (process-level regression net for P0-01..P0-05)

--- end block ---

## Iter #1 · lib/screens/iso_notebook_screen.dart · regression-check-p0-fixes

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:640-670 (`_setHintHidden`, `_setShowAxisCompass`, `_setShowStatusBox`, `_setPaperMode`, `_setAxisLock`)
- **issue**: All five toggle persisters call `setState(...)` BEFORE awaiting `SharedPreferences.setBool(...)`. No try/catch, no `mounted` check after await. This is the exact failure-mode class P0-01 surfaced for `weld_journal._load`/`_save`: on locked/full storage (MDM phones, low-storage Android, hostile OEMs that block SharedPreferences after force-stop) the in-memory toggle flips but never persists — user thinks paper-mode is on, restarts the app on next route, paper-mode is off, ISO sketch made for client is in dark-theme. Worse: if widget is unmounted (back-swipe during the await) there is no `mounted` guard and no error path.
- **why it matters**: Paper-mode + axis-lock are workshop-critical settings — silent regression means the welder re-discovers their config is gone mid-job. The pattern P0-01 ratified for weld_journal should be applied here too.
- **suggested fix**: Wrap each `prefs.setBool` in `try/catch`; on failure revert the `setState` and surface a brief "Nie zapisano ustawienia" SnackBar with Retry, mirroring P0-01.
- **effort**: S
- **round1Ref**: P0-01 (same antipattern, sister screen)

--- end block ---

## Iter #1 · lib/screens/iso_notebook_screen.dart · regression-check-p0-fixes

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:199-203, 224-228, 1353, 1359, 2899, 2925, 3643, 6613-6618 (12+ silent `catch (_) {}` blocks)
- **issue**: P0-02 declared the project policy "only swallow what we expect, rethrow real failures". This file has 12+ silent `catch (_) {}` across hot paths: `ComponentClassification.isPhysical(it.t.name)` (called per item per frame), `parseIsoExpression` failures during live dialog evaluation, sheet rebuild failures. Some are legitimately recoverable (e.g. the parser ones), but `ComponentClassification.isPhysical` throwing is a data-integrity issue — silently skipping a physical component means it never deducts from CUT. P0-02 fixed exactly this class of bug in `_ensureTable`; the notebook file is the next-largest reservoir of the same antipattern.
- **why it matters**: Workshop math integrity. A component-name typo (or future enum reshuffle) silently drops half the deducts from every cut.
- **suggested fix**: Narrow each `catch (_)` to the actually-expected exception type, log others via `debugPrint` with a tag so they surface in CI/Sentry; promote the `ComponentClassification` ones to rethrow or assert.
- **effort**: M
- **round1Ref**: P0-02 (policy extension to sister file)

--- end block ---

## Iter #1 · lib/screens/iso_notebook_screen.dart · regression-check-p0-fixes

- **severity**: med
- **location**: lib/services/premium_service.dart (per d025247 diff — P0-04). Flagged from this iteration because iso_notebook is a premium-gated screen (PDF export, cut-list copy) and a misfire of the new grace logic would land on this user.
- **issue**: P0-04 introduced `_pendingDowngradeAt`. Two edge cases the diff plausibly missed: (a) if the backend is STRUCTURALLY returning `is_active=false` (e.g. Stripe webhook never reaches Railway because commit 3d9e2a7 INTERNET perm is missing on older sideloaded APKs that didn't get rebuilt), the SECOND read after 2 min commits the downgrade — meaning a permanently-misconfigured backend will eventually rip PRO off paying users 2 minutes after first launch, with no recovery. (b) On a re-purchase before the second confirming read, is `_pendingDowngradeAt` cleared on an "active" backend read? Yes per commit message — but is it ALSO cleared when the local Stripe success-redirect lands? If not, a successful re-buy followed by a flaky read 2 min later still downgrades.
- **why it matters**: Fitter on PRO exports PDF iso to a client at 16:55, backend hiccup at 16:57, PRO ripped at 16:59 — PDF export modal locks them out mid-export.
- **suggested fix**: Call `_clearPendingDowngrade()` on every local "purchase succeeded" event (not just on subsequent "active" backend read); cap the grace state-machine to require 3 confirming reads, not 2, when device is online but backend `lastSuccessAt > 5 min ago` (signal: backend itself flaky, not user actually downgraded).
- **effort**: M
- **round1Ref**: P0-04 (edge-case hardening of the new grace logic)

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · regression-check-p0-fixes

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:594-602 (`_invalidSegmentCount` getter) + line 596 (`if (s.iso.text.trim().isEmpty) continue;`)
- **issue**: The new `_invalidSegmentCount` getter silently skips any segment whose `iso` text is empty — but a row with empty ISO and **populated deducts** still flows through `cutMm` (lines 69-83), which returns NaN because `parseIsoExpression('')` throws. The row's `cutMm` is correctly excluded from `_totalCutMm`, but the user is never warned because the counter ignores it. Round-1 P0-03 was meant to surface every silent exclusion; this case slips through.
- **why it matters**: The fitter taps "Dodaj komponent" and types take-outs intending to come back and fill in the ISO measurement, gets distracted, walks to the saw with the cut-list that quietly omits an entire row. The "do sprawdzenia" chip reads 0 / clean.
- **suggested fix**: Drop the early `continue` on empty ISO, or change it to also check deducts: `if (s.iso.text.trim().isEmpty && s.deducts.every((d) => d.value.text.trim().isEmpty)) continue;`
- **effort**: S
- **round1Ref**: P0-03 (gap in the chip's coverage)

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · regression-check-p0-fixes

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:262-267 (P0-03 AI-clamp fallback branch)
- **issue**: The clamp rejects `dim <= 0 || dim >= 100000 || !isFinite` AI dimensions and falls back to `aiSeg.rawDimension!` as a free-text string. But the raw dimension is exactly what the AI saw on the drawing — for a hallucination case ("AI read '1500 mm' as 150000") the raw is overwhelmingly likely to be the same garbage `"150000"`, which then sails through `parseIsoExpression` and lands in `_totalCutMm` without re-validation. The clamp is bypassed via a string detour and the negative-cut guard never fires because the value is positive-but-absurd.
- **why it matters**: P0-03 was sold as "no more AI-poisoned totals". This regression preserves the exact poisoning channel for the most common AI failure mode (order-of-magnitude misreads), just routed through `rawDimension`.
- **suggested fix**: When clamp rejects `dim`, do NOT auto-fill `seg.iso.text` from raw. Either leave it blank with a "Sprawdź wymiar" hint chip on that row, or try-parse the raw and apply the same (0, 100000) bounds before assigning.
- **effort**: S
- **round1Ref**: P0-03 (string-laundered bypass of the clamp)

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · regression-check-p0-fixes

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:619-638 (`_copySummary` per-segment write loop) + 623-625 (cutStr formatting)
- **issue**: P0-03 protects `_totalCutMm`, but `_copySummary` still emits each individual segment's `cut.toStringAsFixed(1)` even when `cut < 0`. The summary line reads `"  3. 1500-1700 = -200.0 mm"` with the headline "Suma CUT" excluding it — a fitter pasting to WhatsApp/Teams sees a per-row CUT number (negative sign easy to miss on a glanced glove-read), assumes it is a fixed length, sends to the saw. No "(do sprawdzenia)" marker on the negative-cut line.
- **why it matters**: The audit-trail document (clipboard summary) becomes inconsistent with the UI warning chip and with the printed total — exactly the contradiction P0-03 was meant to eliminate.
- **suggested fix**: Mirror the segment-card `cut < 0` logic in the summary: if `cut < 0` write `'(do sprawdzenia: ${cut.toStringAsFixed(1)} mm)'` / `'(check: ...)'` instead of a bare value, so foreman / fitter sees the anomaly in the text stream too.
- **effort**: S
- **round1Ref**: P0-03 (summary/PDF text path not patched)

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · regression-check-p0-fixes

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:75-82 (`_Segment.cutMm` deduct try/catch) — interaction with the new `_invalidSegmentCount`
- **issue**: `cutMm` silently swallows `parseIsoExpression(d.value.text)` failures with `catch (_) {}` (line 79-80). A typed deduct of "abc" or "76 1/2" (Unicode fraction, per P1-03) is silently dropped and the segment's `cutMm` is computed as if the deduct were never entered. Result: total looks plausible, `_invalidSegmentCount` stays at 0, the user never learns a fitting allowance was ignored. P0-03 explicitly set out to surface every excluded value; deduct-parse failures are a sister case that was missed.
- **why it matters**: This is the exact "silent under-deduct" scenario in the BACKLOG P0-03 motivation, but on the deduct side — fitter cuts pipe stock by metres LONGER than needed (waste), or the negative-cut chip never fires because the bad deduct didn't subtract at all.
- **suggested fix**: Track per-deduct parse failures on `_Segment` (a `bool _hasDeductParseError` flag set during `cutMm`), and either bump `_invalidSegmentCount` when set or surface a per-row red dot in `_SegmentCard`. Alternatively, set an `errorText` on the offending deduct's `TextField` (already done for out-of-range, missing for parse failure).
- **effort**: M
- **round1Ref**: P0-03 (deduct-side parallel of the ISO-side guard)

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · regression-check-p0-fixes

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:244-282 (`_applyAiResult`) + 505-517 (`_isDirty`) + 660-667 (PopScope canPop)
- **issue**: P0-03 touched `_applyAiResult` for the clamp but the function still wipes ANY user-typed segments (lines 246-249 `for (final s in _segments) { s.dispose(); } _segments.clear();`) with zero confirmation, then re-builds from AI output. Combine with the `_isDirty` rule that treats `_lastScan != null` as dirty: a fitter who manually entered 5 segments, then tapped "Analyse AI" out of curiosity, loses all 5 typed rows. After the AI run the PopScope `canPop` is false (because `_lastScan != null`), so the back gesture prompts "Porzucić skan?" — they tap "Discard" and ALSO lose the AI result. Net: they had useful data, ran AI, ended with nothing, and no undo path.
- **why it matters**: A 30-90s Vision API round-trip costs the user real cents and minutes. Shop-floor workflows mix manual + AI scan ("type the obvious ones while AI thinks"). The silent wipe was an existing bug; P0-03's expanded `_applyAiResult` plus the new dirty-state interaction make recovery worse.
- **suggested fix**: Before `_segments.clear()` in `_applyAiResult`, if any existing segment has user input, show a confirm dialog ("Zastąpić wpisane odcinki wynikiem AI?"). Independently, snapshot the pre-AI segments and offer an `_undoAiResult` action / SnackBar.
- **effort**: M
- **round1Ref**: P0-03 + new (interaction surfaced by the clamp-fix's expansion of `_applyAiResult`)

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · regression-check-p0-fixes

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:813-833 (warning chip rendering) + 826-829 (text style)
- **issue**: The new chip's foreground is solid `_kRed` text on an 18%-opacity `_kRed` background within a `_kCard` (#1A1D26) container. Under direct workshop sunlight + tinted visor (per P1-08, P2-07), pure-red-on-near-black with a low-alpha tint blends to a muted purple smudge. The chip is also only 10 pt — below the 11-pt minimum for shop-floor screens (P1-08, P3-08). The fitter literally cannot see the warning that P0-03 introduced.
- **why it matters**: The chip is the entire UX surface for the P0-03 fix. If unreadable outdoors, the user reverts to trusting "Suma CUT" and the silent exclusion lands them at the saw with too little stock anyway.
- **suggested fix**: Use white text on a saturated `_kRed` background (or `_kRed` on `Colors.white`), 12 pt min, with an inline `Icons.warning_amber_rounded`. Mirror the negative-CUT pill treatment at lines 1502-1516.
- **effort**: S
- **round1Ref**: P0-03 + P1-08 (legibility regression introduced by the fix)

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · regression-check-p0-fixes

- **severity**: high
- **location**: c:\Users\Startklaar\Documents\FitterWelderPro\test (no `iso_scanner_test.dart` or `iso_scanner_screen_test.dart` exists)
- **issue**: P0-03 ships zero widget/unit tests for `_totalCutMm` (negative-cut skip), `_invalidSegmentCount` (counter behaviour), or `_applyAiResult` (clamp + fallback path). The commit message "120 tests pass" is true but does not exercise any of the new branches. Any later refactor (especially the dirty-state work flagged above) can silently re-introduce the original bug class.
- **why it matters**: P0-03 is exactly the math-integrity fix that MUST be locked behind tests — failure mode is silent and on the wrong-quantity-of-pipe side.
- **suggested fix**: Add unit test on the segment math: build `_Segment` instances directly (or extract `cutMm`/totals to a pure helper) and assert behaviour for (a) negative cut excluded from total, (b) NaN cut excluded, (c) `_invalidSegmentCount` increments per bad row, (d) AI dim of 150000 falls back safely. Widget test that the red chip renders when `_invalidSegmentCount > 0`.
- **effort**: M
- **round1Ref**: new (process-level regression net specific to P0-03)

--- end block ---

## Iter #3 · lib/screens/weld_journal_screen.dart · recent-commit-quality

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:148-153 (P0-02 `_ensureTable` selective catch — commit d025247)
- **issue**: The "duplicate column" detection is string-matching against `e.toString().toLowerCase()` for the substrings `"duplicate column"` and `"already exists"`. sqflite on Android emits `"duplicate column name: weld_type (code 1 SQLITE_ERROR)"`; sqflite_common_ffi on desktop/test emits `"duplicate column name"`; some sqlite builds in non-EN locales (Asian Android OEMs with localized error tables) emit `"列名重复"` or similar. A locale-translated error becomes a non-duplicate rethrow → P0-01 SnackBar fires every cold start on those phones, blocking the journal entirely.
- **why it matters**: Fitter on a Huawei/Xiaomi shop tablet opens the journal and gets a permanent "Nie udało się wczytać dziennika" Ponów loop because the migration is rethrowing on benign "column already exists" errors with localized messages — exact opposite of the P0-02 goal.
- **suggested fix**: Match on SQLite error code (DatabaseException.isDuplicateColumnError() in sqflite ≥ 2.3, or substring `"code 1"` + `"column"`) rather than locale-prone English substrings; or pre-check `PRAGMA table_info(weld_journal)` and only run ALTER for missing columns (idempotent, no exception channel at all).
- **effort**: S
- **round1Ref**: P0-02 (hardening the new error-shape recognition)

--- end block ---

## Iter #3 · lib/screens/weld_journal_screen.dart · recent-commit-quality

- **severity**: high
- **location**: lib/screens/weld_journal_screen.dart:384-402 (`_cycleStatus`, P0-01 guards added in d025247)
- **issue**: P0-01 wrapped the DAO call in try/catch but kept the local mutation `e.status = next;` (line 386) BEFORE the await. When `_dao.update(e)` throws, the SnackBar fires "Failed to update weld status" — yet `e.status` is already mutated to `next` and `_entries` holds the same reference. Until the user manually triggers another `_load()`, the tile keeps showing the new (un-persisted) status. A NOK weld can read as OK on screen while DB still says PENDING. Worse: the user taps the tile again, status cycles further (OK→NOK), DAO call fires again — if it succeeds this time, the NOK persists, skipping the OK state the welder thought they recorded.
- **why it matters**: A weld that the welder thinks is "OK" but is actually unsynced becomes a phantom record — the next morning the foreman reads NOK on the same tile after `_load`, and there is no audit trail for the disagreement. Traceability fail.
- **suggested fix**: Stash `final prev = e.status;` before mutating, mutate after a successful await (or rollback `e.status = prev` in the catch and `setState`).
- **effort**: S
- **round1Ref**: P0-01 (gap in the optimistic-update rollback path)

--- end block ---

## Iter #3 · lib/screens/weld_journal_screen.dart · recent-commit-quality

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:19-27, 510-511 (`_localizedNum` helper added in 69310f8)
- **issue**: `_localizedNum` reads `AppLanguageController.isEnglish` directly (a static getter), but `_WeldTile` is a `StatelessWidget` and never listens for language changes. Switching language via the settings screen while the journal is open leaves every tile rendering the old separator until the user navigates away and back. The helper also mutates display only — the stored `entry.od` keeps the original separator the user typed, so an EN user who typed "60,3" sees "60.3" in the list and "60,3" in the editor — silent inconsistency.
- **why it matters**: Workshop tablets are often left in PL for the welder and switched to EN by the foreman exporting reports — they see different OD strings on the same record and lose trust in the journal. Foreman pastes a value they read on screen into an email, but the editor truth is the original separator.
- **suggested fix**: Either (a) parse OD/t once on save into a canonical `double` and format on display (best — also unblocks future unit tests), or (b) subscribe `_WeldTile` to `AppLanguageController` via `AnimatedBuilder` / `ValueListenableBuilder` so language flips rebuild tiles.
- **effort**: M
- **round1Ref**: new (introduced by 69310f8 locale-aware display)

--- end block ---

## Iter #3 · lib/screens/weld_journal_screen.dart · recent-commit-quality

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:530-538 (48dp delete hit target, 69310f8)
- **issue**: The commit replaced `Padding(EdgeInsets.only(left: 8))` around the delete icon with a `SizedBox(width: 48, height: 48, child: Icon(size: 20))`. A `SizedBox` with a smaller child does NOT center it — the 20pt trash icon renders top-left of the 48×48 box, visually shifted up and toward the tile body, with empty space to its right. On a 360dp-wide phone the trash glyph sits ~14dp away from the right edge instead of centered, looks misaligned with the OK/NOK badge on the left.
- **why it matters**: Welder reads the misaligned trash icon as a layout bug ("is this app broken?") — undermines confidence in the journal that handles their traceability. Also the comment says "48dp square hit target so gloved fingertips don't miss" but the icon's visual centroid is now not centered in its hit area, so the gloved-finger argument only half-lands.
- **suggested fix**: Wrap the `Icon` in `Center` (or use `Container(width:48, height:48, alignment: Alignment.center, child: Icon(...))`), or switch to `IconButton(iconSize: 20, padding: EdgeInsets.zero, constraints: BoxConstraints.tightFor(width: 48, height: 48))` which centers + bakes in the ripple effect.
- **effort**: S
- **round1Ref**: new (visual regression introduced by 69310f8)

--- end block ---

## Iter #3 · lib/screens/weld_journal_screen.dart · recent-commit-quality

- **severity**: low
- **location**: lib/screens/weld_journal_screen.dart:702 (`hintText: 'W-001 lub SP-001-W005'`)
- **issue**: Hardcoded Polish-only hint string `'W-001 lub SP-001-W005'` — bypasses the `_tr(pl, en)` wrapper used everywhere else in the editor. An EN user opening the editor reads the Polish conjunction "lub" inside an otherwise-English form. The 69310f8 commit explicitly localized OD/t display values but left this hint untranslated.
- **why it matters**: Bilingual polish — EN-mode foreman sees a stray PL word in the editor placeholder. Minor but visible inconsistency in the screen the audit just hardened.
- **suggested fix**: `hintText: _tr('W-001 lub SP-001-W005', 'W-001 or SP-001-W005')`.
- **effort**: S
- **round1Ref**: new (untranslated string in editor sheet)

--- end block ---

## Iter #3 · lib/screens/weld_journal_screen.dart · recent-commit-quality

- **severity**: low
- **location**: lib/screens/weld_journal_screen.dart:795-796 (date picker `firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 1)`)
- **issue**: Hardcoded `5` years back / `1` year forward window in the date picker (untouched by the recent commits but inside their blast radius — the editor sheet is a P0-01 / 69310f8 hot spot). A welder back-dating a fabrication that started 6+ years ago for a project re-certification, or pre-dating a planned shutdown 14+ months out, cannot pick the date and must type YYYY-MM-DD by hand — which then bypasses the format-validation the picker was supposed to enforce.
- **why it matters**: Pipework projects routinely span multi-year shutdowns; re-certification campaigns reach into old archives. Hardcoded ±5/+1 window forces manual typing for legitimate use cases, undermining the picker's reason to exist.
- **suggested fix**: Either widen to a generous `now.year - 30` / `now.year + 5` (cost: zero), or pull both from a centralised `WorkshopDateConfig` constant alongside the other hardcoded windows in jobs/pre-weld screens for one-place tuning.
- **effort**: S
- **round1Ref**: new (hardcoded config the audit lens explicitly hunts for)

--- end block ---

## Iter #4 · lib/screens/jobs_screen.dart · recent-commit-quality

Only one commit since 2026-06-04 touched this file: `69310f8` ("backend: switch to standalone fitter Railway service…"). The diff has two hunks: (a) try/catch wrap around the Edit-route `Navigator.push` at 481-507, (b) `_copy` delegated to shared `copyToClipboard` helper at 713-717.

- **severity**: med
- **location**: lib/screens/jobs_screen.dart:500-505 (new catch-branch SnackBar)
- **issue**: Raw exception `$e` is interpolated directly into the user-facing PL/EN SnackBar message ("Nie udało się otworzyć edycji: $e"). Real exceptions look like `PlatformException(sqlite_error, no such table: job_listings, null, null)` or `DatabaseException(disk I/O error (code 1802 SQLITE_IOERR_DELETE)) sql 'INSERT…' args [...]`. A fitter on jobsite reads workshop-hostile English stack-y text inside the Polish UI, has no actionable next step, and the technical fragment may even be longer than the SnackBar can render — gets truncated, useless.
- **why it matters**: The whole point of the try/catch (per the new comment) was to "surface as a SnackBar instead" of a red screen. Surfacing it as raw exception text is barely better — fitter still doesn't know whether to retry, restart, or call support.
- **suggested fix**: Replace `$e` interpolation with a stable user message ("Nie udało się otworzyć edycji — spróbuj ponownie" / "Could not open editor — please try again"), and `debugPrint('JobAddScreen open failed: $e')` for developer triage. Include an action button "Ponów" calling the same onPressed.
- **effort**: S
- **round1Ref**: new (recent-commit regression — new code path adds bad UX)

- **severity**: med
- **location**: lib/screens/jobs_screen.dart:484-488 (comment) and 489-506 (try/catch scope)
- **issue**: The added comment claims this catches `JobAddScreen.initState` throwing after low-memory kill. Flutter doesn't propagate widget-tree build/initState errors through the `Navigator.push` future — those errors are reported via `FlutterError.onError` and rendered as `ErrorWidget` (red screen) inside the pushed route, not raised on the awaiting future. The try/catch as written only catches (i) errors thrown by `Navigator.push` itself (very rare — bad route arguments), or (ii) errors thrown by the `await` resolution. So the documented threat model and the actual catchable surface don't match — the code is dead-defensive against the wrong failure mode while leaving the real one (red screen mid-edit) untouched.
- **why it matters**: Tight coupling between a misleading comment and code creates false confidence — next reviewer assumes the red-screen-during-edit case is handled and stops thinking about it. The actual case (initState throw → red screen → fitter loses half-typed posting) still happens; needs `FlutterError.onError` override or a `RouteObserver` + custom error widget builder for the route.
- **suggested fix**: Either delete the misleading comment and document what is actually caught (rare push-time errors), OR add a real error-widget builder on the MaterialPageRoute via `MaterialApp.builder` / page route error handling so initState/build errors surface as SnackBar + auto-pop. Decouple comment from code reality.
- **effort**: M
- **round1Ref**: new (recent-commit quality — false-confidence pattern)

- **severity**: low
- **location**: lib/screens/jobs_screen.dart:500-505 (catch-branch SnackBar — no duration, no action, no haptic)
- **issue**: This new SnackBar uses Flutter's default `Duration(seconds: 4)` (no explicit duration), no `SnackBarAction` for retry, and no failure haptic. Round-1 P1-08 specifically called for "SnackBar duration 4s → 6-8s with floating + colored background" and the codebase already has `Haptic` (imported on line 9) and `copyToClipboard` patterns that pair haptics with SnackBars. The new error path ignores all of this.
- **why it matters**: Failure SnackBars are exactly when the welder needs longer read time (4 s with gloves + sunlight + safety visor = unreadable), a one-tap Retry, and a tactile "something went wrong" cue. Tight coupling to default Material behaviour in the catch-branch undermines the workshop-friendly UX the rest of the screen tries to provide.
- **suggested fix**: `Haptic.error()` (add helper if missing); SnackBar with `duration: Duration(seconds: 7), behavior: SnackBarBehavior.floating, backgroundColor: _kAccent, action: SnackBarAction(label: 'Ponów', onPressed: () => …)`.
- **effort**: S
- **round1Ref**: P1-08 (font/SnackBar bump), P1-05 (haptic on destructive)

- **severity**: low
- **location**: lib/screens/jobs_screen.dart:713-717 (`_copy` after refactor)
- **issue**: The refactor calls `copyToClipboard(context, value)` with no `label`. The shared helper supports a `label` argument that renders as `"$label: $value"` instead of the bare `"Skopiowano: $value"`. The two call sites in this screen pass `listing.contactEmail!` (line 657) and `listing.contactPhone!` (line 663) — both lose their "Email" / "Telefon" semantic when copied. After the refactor, a phone number and an email produce visually identical SnackBars apart from the value, costing context for the fitter who copies in a hurry.
- **why it matters**: Loss of contextual labels in a multi-row list = worse UX than before the refactor; a refactor "to match calculator-screen behaviour" actually regressed semantics — calculator screen always knows what it's copying (Travel, Run, Rise…), contact rows don't.
- **suggested fix**: Plumb a label through `_ContactRow` → `_copy(context, value, label)`. Two-line change: `_copy(BuildContext c, String v, String label) => copyToClipboard(c, v, label: c.tr(pl: label, en: …));` + pass `'Email'` / `'Telefon'` from each call site.
- **effort**: S
- **round1Ref**: new (recent-commit refactor regression)

- **severity**: low
- **location**: lib/screens/jobs_screen.dart:483-507 (entire edit-button onPressed) + 510-518 (delete button) inconsistency
- **issue**: The delete button (line 515) calls `Haptic.tap();` before opening the confirm dialog — "gloved tap on a destructive icon — confirm registration before the dialog covers the button." The edit button — modified in this commit — does NOT call `Haptic.tap()` before opening the edit route. Now that the edit-button onPressed was rewritten, a consistency check is overdue: every destructive/navigational AppBar IconButton should haptic-confirm. Edit isn't strictly destructive but tap registration on gloves still matters, and the lack of haptic now sits jarringly next to the delete button that does it 4 lines below.
- **why it matters**: Inconsistent haptic feedback across adjacent AppBar buttons is a "did my tap land?" usability bug specifically called out by round-1 P1-09. The recent rewrite was the perfect time to fix it; instead the inconsistency was preserved.
- **suggested fix**: Add `Haptic.tap();` as the first line inside the new try block.
- **effort**: S
- **round1Ref**: P1-09 (haptic on every tappable row/chip)

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · test-coverage-gaps

- **severity**: high
- **location**: c:\Users\Startklaar\Documents\FitterWelderPro\test (whole directory) — no `job_add_screen_test.dart`, no `jobs_service_test.dart`. Test dir contains only calculator + parser tests (cut_calculator, iso_parser, bar_nesting, elbow_takeouts, cut_packing_service, orbital_tig, tungsten, sanitary_tube, pipe_schedules, heat_tint, support_spacing, widget_test, services/{unit_parser, prefab_engine}).
- **issue**: A 49 PLN monetised flow (Stripe Checkout creation → external browser launch → webhook flip) has ZERO automated coverage. The only regression net against `_save()` (lines 170-222) regressing — duplicate Checkout sessions on double-tap, missing `setState(_saving = false)` on the launchUrl-failure path, missing `mounted` guards before SnackBar, SnackBar Retry calling `_save` while already saving — is a manual smoke test by a fitter who actually pays 49 PLN.
- **why it matters**: Workshop fitter taps "Opłać 49 PLN i opublikuj", network glitches, the SnackBar Retry button fires but `_saving` is still true (or false but the previous call is mid-flight) — duplicate Stripe Checkout sessions, possible double-charge, money-disappeared support ticket. The exact P1-11 scenario (49 PLN double-charge risk) without any test gate to prevent the regression in CI.
- **suggested fix**: Add `test/screens/job_add_screen_test.dart` with a fake `JobsService` (inject via constructor or service-locator override) covering: (a) double-tap on Save dispatches exactly ONE `createCheckout`, (b) launchUrl=false resets `_saving` AND surfaces the PL+EN SnackBar, (c) the Retry SnackBarAction does NOT re-enter when already in-flight, (d) Navigator.pop(true) only after a successful URL launch, (e) widget unmount during `await createCheckout` does NOT crash on the post-await `setState`.
- **effort**: L
- **round1Ref**: new (process-level test-net for the paid posting flow; cross-refs P1-11 webhook-polling + P1-30 numeric-input guards)

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · test-coverage-gaps

- **severity**: high
- **location**: lib/screens/job_add_screen.dart:170-222 (`_save`), specifically the missing test for "already-saving guard" — `onPressed: _saving ? null : _save` (line 394) protects the FilledButton but the SnackBarAction Retry at line 217-219 (`onPressed: _save`) has no `_saving` guard
- **issue**: The Retry SnackBarAction calls `_save` directly with no check on `_saving`. If the user taps Retry twice rapidly (gloved double-tap), or taps Retry while the first `_save` is mid-flight on its `await JobsService.instance.createCheckout`, a second Stripe Checkout Session is created and a second DRAFT row is inserted backend-side. Stripe charges per successful checkout, but the user can complete BOTH — paying 98 PLN for one listing. No test asserts a single `createCheckout` call per user intent.
- **why it matters**: Direct revenue-disputes vector. The retry SnackBar appears EXACTLY in the failure window where the user is most likely to mash the button (cellular flake, 4G in a basement workshop). A unit test would have caught it; manual QA missed it because nobody taps Retry twice on purpose.
- **suggested fix**: Add `onPressed: _saving ? null : _save` to the SnackBarAction; write a widget test that pumps a stalling `createCheckout` future, taps Retry twice, asserts `createCheckoutCallCount == 1`.
- **effort**: S
- **round1Ref**: new (untested duplicate-charge path; adjacent to P1-11)

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · test-coverage-gaps

- **severity**: high
- **location**: lib/screens/job_add_screen.dart:34-91 (singleton `JobsService.instance` usage) and 175 (`JobsService.instance.createCheckout`)
- **issue**: `_save` calls a hard-coded singleton (`JobsService.instance.createCheckout(...)`) with no constructor injection or testing seam. Even if a developer wanted to write a coverage test, there is no way to substitute a fake service without monkey-patching the singleton or refactoring. Result: every test for this screen ends up doing real-or-mock HTTP at the service layer, which means in practice nobody writes any test. This is the architectural reason the test gap exists at all.
- **why it matters**: Tightly coupled singletons in a paid-flow screen are a self-perpetuating coverage hole — the cost of adding the first test is the cost of refactoring service access first, so the test never gets written. Each new payment-related change accumulates regression risk.
- **suggested fix**: Expose an optional `JobsService? service` constructor parameter (`final JobsService _svc = service ?? JobsService.instance;`); two-line refactor unlocks all the tests listed in the previous bullet.
- **effort**: S
- **round1Ref**: new (DI seam pre-req for any of the test bullets above)

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · test-coverage-gaps

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:462-467 (`_req` validator) — only required-field check; no other validators
- **issue**: Five fields are marked required (Title, Company, Location, Description) but several never-validated fields ride on the same `_save` path into Stripe and the backend DRAFT row: `_emailCtrl` (line 333-337, `keyboardType: TextInputType.emailAddress`) has NO validator — a malformed email like "spawacz@" or "jan kowalski" goes straight to backend; `_phoneCtrl` (339-343) accepts arbitrary text including newlines; `_titleCtrl` has no max length, allowing a 5000-char title that breaks the Jobs list rendering and the Stripe Checkout description (Stripe caps `line_items.description` at 500). NO tests assert that invalid emails are rejected, that title length is enforced, that newlines are stripped from phone, or that the required `_req` validator returns the localised string in both PL and EN.
- **why it matters**: Welder pays 49 PLN, listing publishes with garbage contact email — phone calls go unanswered, recruiter / client never reaches them, posting is effectively dead until expiry 30 days later. No refund flow exists. A simple validator test would catch the regression before ship.
- **suggested fix**: Add `_email` validator (regex anchored `^[^@\s]+@[^@\s]+\.[^@\s]+$` with PL/EN error); add `maxLength: 120` on title with `LengthLimitingTextInputFormatter`; add `FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))` on phone; write a parameterised widget test covering each invalid input → submit blocked.
- **effort**: M
- **round1Ref**: P1-13 (sanitise+length-cap free-text), P1-30 (per-field error+sanity bounds)

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · test-coverage-gaps

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:157-168 (`_addRequirement`) + 56-74 (`_commonReqs`) + 438-460 (`_buildReqChips`)
- **issue**: The 14-chip requirement adder is shop-floor critical (TIG 141 / 6G / NACE MR0175 etc.) and has subtle invariants that no test guards: (a) dedupe by EXACT case+trim match — `_addRequirement('TIG 141')` after a user typed `'tig 141'` will produce duplicates; (b) the comma-split on line 163 (`.split(',').map((s) => s.trim())`) does not handle trailing comma, Unicode commas, or semicolons (likely on PL keyboards swiping); (c) the chip cache (`_chipCache`/`_chipCacheLang`) invalidates on locale switch but no test asserts the cache is actually rebuilt when `context.language` changes mid-session; (d) tapping a chip while the field has focus does not update the caret position — re-tap can land cursor in the middle of a tag.
- **why it matters**: Welder spends 20 seconds wrestling with a "TIG 141" tag that has a hidden trailing space and stops appearing in cross-listing filters; subtle bug hides recruiter-side full-text-search hits, listing gets fewer applicants for the 49 PLN paid.
- **suggested fix**: Add unit tests over an extracted pure helper `addRequirementCsv(existing, tag) -> String` covering: empty, dup exact, dup case-insensitive, trailing comma, Unicode comma, semicolon. Add a widget test asserting `_chipCache` is invalidated when `context.language` flips.
- **effort**: M
- **round1Ref**: P1-13 (free-text sanitation), new (chip dedupe semantics)

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · test-coverage-gaps

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:104-110 (`_isDirty`) + 227-234 (PopScope) + 112-142 (`_confirmDiscard`)
- **issue**: The unsaved-changes guard is the single most-likely-to-regress piece of UX in this screen (a 5-line job description retyped on a phone in gloves is misery — comment line 47). It is also entirely untested. Specific gaps no test covers: (a) edit mode (`widget.existing != null`) snapshots the EXISTING values, so editing a listing and reverting it to original yields `_isDirty == false` — correct, but no test asserts the snapshot is taken in the SAME order as `_currentSnapshot()`; (b) `_saving == true` flips `canPop` to true (line 228) — meaning if a fitter starts a save, the network stalls, they back-swipe, the screen pops mid-await and the post-await `setState(_saving=false)` (line 209) runs on a disposed State (no `mounted` check), throwing a debug-mode error and silently losing the SnackBar; (c) when PopScope onPopInvokedWithResult fires with `didPop=false`, `Navigator.of(context)` is captured BEFORE the awaited dialog (line 231) but `mounted` is checked AFTER — `BuildContext` use across awaits is a known Flutter analyzer warning and is exactly the pattern P0-01 ratified `mounted`-checks for.
- **why it matters**: Edge case (b) corrupts the paid-flow on cellular flake — same root cause as P0-01. The discard dialog is the seatbelt against a 5-min typed listing — if it regresses, fitters retype on the saw floor. Untested = invisible regression.
- **suggested fix**: Widget tests covering: (i) entering text → back-swipe shows discard dialog; (ii) editing existing → reverting → back-swipe pops without dialog; (iii) `_saving` mid-flight + back-swipe leaves no crash + cleans up `_saving`. Also wrap line 209's `setState` in `if (!mounted) return;`.
- **effort**: M
- **round1Ref**: P0-01 (`mounted`-guard pattern extension), new (discard-flow regression tests)

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · test-coverage-gaps

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:226-244 (build, edit vs create title) + 79-89 (initState seed from widget.existing)
- **issue**: The "edit" mode branch is silently never exercised because the workflow is "pay 49 PLN to publish, then there is no editing UI today" — but `widget.existing` IS plumbed and the AppBar title flips on it. No test asserts that when `existing` is non-null all 8 controllers are pre-filled correctly, that null `rate`/`contactEmail`/`contactPhone` translate to empty strings (line 84, 87, 88 — currently `?? ''`), and that `_initialSnapshot` reflects the loaded state (so a no-op back-swipe does NOT prompt the discard dialog). If the future "edit listing" feature lands without a test, a regression in initState could pre-fill the wrong controller (e.g. swap `rate` and `company`) and the welder edits, re-pays, and the wrong field updates.
- **why it matters**: Forward-compatibility for the edit-listing flow already half-wired in this screen; the absence of a test means the first PR that turns the feature on will be reviewed without coverage.
- **suggested fix**: Add a widget test passing a fully-populated `JobListing` via `JobAddScreen(existing: ...)` and assert each controller text + that `_isDirty` is false on first frame.
- **effort**: S
- **round1Ref**: new (forward-compat coverage for the existing edit-mode plumbing)

--- end block ---

## Iter #6 · lib/screens/saddle_template_screen.dart · backend-integration-edge-cases

- **severity**: high
- **location**: lib/screens/saddle_template_screen.dart:199-224 (`_exportPdf`) calling lib/services/saddle_template.dart:124-143 (`exportPdf` → `getTemporaryDirectory` + `File.writeAsBytes` + `Share.shareXFiles`)
- **issue**: The screen wraps `tpl.exportPdf(...)` in a single try/catch that surfaces the raw `$e` to the user, then races a `setState(_exporting = false)` against an unmounted widget. The service can throw at four distinct points — `getTemporaryDirectory()` (path_provider MissingPluginException on first cold-launch race), `doc.save()` (PDF encoder OOM for a 30+ page strip on a 6"x3" branch — see _buildStripPages loop), `f.writeAsBytes` (ENOSPC / EACCES on full or MDM-locked storage), and `Share.shareXFiles` (PlatformException when user has no share targets / iOS scene not foregrounded). The user sees an indistinguishable `"Błąd eksportu PDF: PlatformException(error_no_activity, ...)"` for all four, with no Retry, no "delete from temp", and no telemetry. On the share-failure path the PDF is silently left in temp dir to leak space.
- **why it matters**: Welder pays for PRO, hits export, gets gibberish English exception text in Polish UI, no Retry button, and on storage-full devices the next 2-3 attempts all fail silently because previous templates accumulated in temp. PRO refund risk + cluttered tmp dir on field phones that almost never clear cache.
- **suggested fix**: Branch the catch on exception type — `MissingPluginException` → "Restart aplikacji wymagany", `FileSystemException` → "Brak miejsca / dostępu do pamięci, zwolnij miejsce", `PlatformException` from share → "Plik PDF zapisany, otwórz Pliki/Files aby udostępnić" + open the dir; always delete `f` on Share cancellation or write failure; add `Retry` action on SnackBar. Wrap the `setState` after await in `if (mounted)` (already present) but also clear `_exporting` even when the throw escaped before `setState` could run — use try/finally semantics with explicit mounted guard.
- **effort**: M
- **round1Ref**: P0-01 (sister antipattern — mounted-safe + retry on async backend op)

--- end block ---

## Iter #6 · lib/screens/saddle_template_screen.dart · backend-integration-edge-cases

- **severity**: high
- **location**: lib/screens/saddle_template_screen.dart:60-92 (`_recompute`) + lib/services/saddle_template.dart:82-89 (`ArgumentError` throws)
- **issue**: `_recompute` runs from `initState` (line 46) BEFORE `AppLanguageController` is guaranteed to be initialised (it is a static singleton but the comment at 95-97 admits "InheritedWidget lookups are not allowed" — implying current locale may be stale at first frame). If the singleton has not been hydrated from SharedPreferences yet, the bilingual `_errorMessage` and `_localizeError` fall back to default (English) regardless of device locale. Worse: the service's two ArgumentError messages have changed text shape between versions (the matcher uses `raw.contains('Branch OD') && raw.contains('header OD')` — a single rephrase in `saddle_template.dart:84` to e.g. `'branch outer diameter ...'` silently breaks localisation across the whole edge-case path, falling back to raw English exception text inside `_ErrorBox`. There is no test that asserts the matcher still matches the live thrown string.
- **why it matters**: Polish fitter on a Samsung A14 sees English exception text intermittently (first-launch race) AND any minor refactor of the service's error wording silently regresses Polish UX without any test catching it. Backend contract (`ArgumentError.message`) is being string-parsed by the UI — a brittle integration boundary.
- **suggested fix**: Define a `SaddleTemplateException` enum (`branchTooLarge`, `angleOutOfRange`) thrown by the service with structured fields (`branchOd`, `headerOd`, `angle`); switch on the enum in `_localizeError`. Add a unit test asserting the enum cases are thrown for known bad inputs. For the initState race, defer the first `_recompute` to a post-frame callback so the locale singleton is hydrated.
- **effort**: M
- **round1Ref**: new (typed-error contract between service and screen; brittle string-parsing fix)

--- end block ---

## Iter #6 · lib/screens/saddle_template_screen.dart · backend-integration-edge-cases

- **severity**: med
- **location**: lib/screens/saddle_template_screen.dart:199-224 (`_exportPdf` no debounce) + lib/services/saddle_template.dart:407-422 (`_buildStripPages` loop)
- **issue**: Tapping the export button rapidly (e.g. impatient first-time user who thinks the first tap missed) spawns a second `tpl.exportPdf(...)` Future BEFORE the first one's `setState(_exporting = false)` lands, because the button only disables AFTER the `setState(_exporting = true)` rebuild flushes. While the disabled state IS gated on `_exporting`, the gap is real on slower devices. Two concurrent PDF generations on a 6"x3" tie-in compute 73 trig samples × N strip pages × 2 — and both call `Share.shareXFiles` at the end, racing the iOS share sheet (only one can show). On iOS this is known to throw `_activity_view_controller_busy`. Beyond that, the temp file path uses `DateTime.now().millisecondsSinceEpoch` — two rapid taps within the same millisecond collide on the same path (rare but observed under emulator clock-stall).
- **why it matters**: Workshop welder taps twice on glove; second tap silently fails or hangs the share sheet; he assumes export is broken and gives up on PRO feature.
- **suggested fix**: Wrap the `_exporting` flag in a guard at the top of `_exportPdf`: `if (_exporting) return;` so even pre-rebuild double-fires no-op. Switch the temp file name to include a UUID v4 or `Random().nextInt(1<<32)` suffix to make collisions impossible.
- **effort**: S
- **round1Ref**: new (rapid-tap re-entrancy + temp-file name collision on backend handoff)

--- end block ---

## Iter #6 · lib/screens/saddle_template_screen.dart · backend-integration-edge-cases

- **severity**: med
- **location**: lib/screens/saddle_template_screen.dart:60-92 (`_recompute`) + saddle_template.dart:91-121 (constructor loop running synchronously inside `setState`)
- **issue**: Every keystroke in `_headerCtrl`/`_branchCtrl` reconstructs a brand-new `SaddleTemplate` synchronously inside `setState`. The constructor runs 73 iterations of `sqrt`+`sin`+`cos` and allocates a new `List<SaddleCutPoint>`. There is no debounce (round 1 flagged this as P1-19) — but the BACKEND-INTEGRATION angle round-1 missed is that on a budget Android (Snapdragon 4xx) the synchronous compute can exceed 16ms while the user is mid-input, leading to lost keystrokes when the IME's hidden event queue overflows. Worse, when the user pastes a multi-digit string (`"114.3"` pasted from clipboard during measurement), the `onChanged` fires once per character on some IMEs but as a single event on others — creating non-deterministic behaviour across phones, which is impossible to debug from a SnackBar log.
- **why it matters**: Welder on a 200 PLN burner phone reports "the app eats my keystrokes when I type pipe sizes" — un-debuggable without a debounce + frame-budget guard. PRO churn on cheap fleet phones in the workshop.
- **suggested fix**: Move `SaddleTemplate(...)` construction off the build thread via `compute()` for `pointsCount >= 73`, OR memoise on `(h, b, angleDeg)` tuple so unchanged values skip reconstruction. Combine with the P1-19 debounce.
- **effort**: M
- **round1Ref**: P1-19 (round-1 said "debounce" — this is the underlying frame-budget + IME-eats-keystrokes integration consequence that justifies it)

--- end block ---

## Iter #6 · lib/screens/saddle_template_screen.dart · backend-integration-edge-cases

- **severity**: med
- **location**: lib/screens/saddle_template_screen.dart:204-208 (`projectName: _projectCtrl.text.trim()`) → lib/services/saddle_template.dart:124-143 (`exportPdf(projectName)` → file name uses `${branchOdMm.toInt()}x${headerOdMm.toInt()}`)
- **issue**: The `_projectCtrl` free-text passes straight through to the PDF (rendered as `pw.Text(projectName)`) AND the share sheet subject — with NO sanitisation. A welder pastes a tag like `"Line 12-WP-3045 / TIE-IN B"` containing emoji, RTL marks, control chars or 500+ chars; the PDF renderer chokes on unsupported glyphs (`pw` font lacks Polish diacritics by default — round 1 flagged this as P2-09 but missed it lives here too), and the share-sheet subject crashes on iOS for strings with NUL bytes. Also, the FILE NAME uses `branchOdMm.toInt()` — for any header OD that ends in `.3` (every NPS-standard pipe: 60.3, 114.3, 168.3) this truncates silently, so 60.3 mm and 60.0 mm produce the SAME file name "saddle_60x114_<stamp>.pdf" — surprisingly fine because of the timestamp, but means the user has zero way of distinguishing files in temp listing when they share multiple.
- **why it matters**: PDF for archive shows boxes instead of "Linia 12 / Króciec B"; share-sheet crashes on iOS for long descriptions; temp dir littered with same-name PDFs makes "share previous" useless. P1-13 in round 1 covered free-text sanitisation broadly but did not name this screen.
- **suggested fix**: Apply the P1-13 cap+sanitise utility to `_projectCtrl` before passing into `exportPdf`. Include the original-typed OD strings (not the int-truncated) in the PDF file name to make multi-export distinguishable: `saddle_${branchOdMm.toStringAsFixed(1)}x${headerOdMm.toStringAsFixed(1)}_$stamp.pdf`. Ship Polish-diacritic font with the PDF doc.
- **effort**: S
- **round1Ref**: P1-13 + P2-09 (free-text sanitise + Polish font — explicit coverage on saddle export path)

--- end block ---

## Iter #6 · lib/screens/saddle_template_screen.dart · backend-integration-edge-cases

- **severity**: low
- **location**: lib/screens/saddle_template_screen.dart:67-76 (guard against `h <= 0 || b <= 0`)
- **issue**: The OD guard catches only zero/blank, not other backend-rejection conditions. The service constructor at saddle_template.dart:82-89 throws when `branchOdMm > headerOdMm` (caught by `_localizeError` string match) — but the screen also lets through `NaN`/`Infinity` because `double.tryParse('Infinity')` returns `Infinity` and the guard `h <= 0` is false for inf. Constructor then computes `under = rh*rh - rb*rb*sinPhi*sinPhi` with infinite operands → NaN propagates into every point, `stripLengthMm = Infinity`, `maxDepthMm = NaN`. Painter at line 808-810 then computes `sx = dw / Infinity = 0`, `sy = (dh*0.85)/NaN = NaN`, canvas draws nothing or crashes on the PDF text "Max głębokość NaN mm". PDF export then writes the literal string "NaN" into the offset table — confusing for the welder who saved a "valid" looking template.
- **why it matters**: Edge case (user types `"inf"` or `"1e308"`), but the silent NaN propagation through PDF generation is a real footgun that round 1's input-validation P1-30 did not target this screen.
- **suggested fix**: Strengthen guard to `if (!h.isFinite || !b.isFinite || h <= 0 || b <= 0 || h > 10000 || b > 10000)`. 10 m OD upper bound is far past any real pipe.
- **effort**: S
- **round1Ref**: P1-30 (per-field sanity bounds — explicit coverage with NaN/Inf semantics)

--- end block ---

## Iter #7 · lib/screens/rolling_offset_screen.dart · state-consistency-after-error

- **severity**: high
- **location**: lib/screens/rolling_offset_screen.dart:46-94 (`_calculate()` early-return paths at lines 74 and 80)
- **issue**: At lines 46-49 the four result controllers are cleared BEFORE the validation guards. When validation fails (Rise/Spread ≤ 0 at line 57, or angle out of range at line 76) the function returns at line 74 / 80 WITHOUT calling `setState(() {})` — the closing `setState(() {})` only runs on the success path at line 94. The result `TextField`s do show as cleared because `TextEditingController.clear()` fires its own listener, but the `_result()` builder at lines 305-311 captures `ctrl.text.trim().isEmpty` only at build time and decides whether the copy IconButton's `onPressed` is `null` (disabled) or a real callback. After (1) successful calc → (2) typo → CALCULATE → validation fails → controllers wiped → no rebuild → the copy buttons remain "enabled" from the previous build. Tapping copy now invokes `copyToClipboard(context, ctrl.text, ...)` with the just-emptied controller — an empty-string copy is pasted into the cut-list, silently overwriting whatever was on the clipboard.
- **why it matters**: Fitter computed Travel=707.1 for pipe A, copied it. Switches to pipe B, mis-types Rise, hits CALCULATE — snackbar warning fires but visually the result field is blank, fitter taps copy "to refresh", overwrites the 707.1 already on the clipboard with empty string, then pastes "nothing" into the saw operator's WhatsApp. Or worse: fitter assumes copy button greyed = no value, taps anyway, gets empty paste into BOM cell silently. Round 1's P0-05 covered the wipe-stale-result aspect but did NOT identify that the wipe leaves the copy IconButton's enable-state out of sync with the now-empty controller.
- **suggested fix**: Move `setState(() {})` BEFORE each early-return (or wrap the four `.clear()` calls inside a `setState`) so the rebuild reflects the empty controller state and the copy buttons properly disable.
- **effort**: S
- **round1Ref**: P0-05 (extends — wipe is correct, but the IconButton's `onPressed: ctrl.text.trim().isEmpty ? null : ...` capture means a rebuild is required for the disable to take effect)

- **severity**: high
- **location**: lib/screens/rolling_offset_screen.dart:245-269 (`_angleBtn` onTap) + 41-95 (`_calculate`)
- **issue**: Tapping a different angle preset (45 → 60 → 30 → custom) only mutates `_selectedAngle` via `setState(() => _selectedAngle = value)` (line 249). It does NOT clear the four result controllers, NOR clear `_customAngleController`. After computing for 45°, the screen shows `True Offset = 500, Travel = 707.1, Run = 500, Multiplier = 1.4142`. User taps "60°" — chip highlight moves to 60° but the result fields still display the 45° numbers. Equally: after computing in 'custom' with say 32.5°, user taps "45" — `_customAngleController` retains "32.5" off-screen; if user later taps "Inny" again it loads the stale 32.5 and they may CALCULATE without noticing they re-loaded a previous job's angle.
- **why it matters**: Visually the chip selector and the result panel are decoupled. Fitter reads "60°" highlighted + "Travel 707.1" and copies it to the saw — but 707.1 is the 45° travel, the 60° travel would be 577.4. Wrong cut, wrong elbow length, potentially scrapped pipe (Schedule 80 stainless = ~150 PLN/m). Round1 P3-12 mentions auto-clearing `_customAngleController` on selection change and tightening `_isDirty`, but does NOT mention clearing the four RESULT controllers on angle-chip change — which is the cut-list-corruption path.
- **suggested fix**: In `_angleBtn` onTap, additionally clear `_trueOffsetController`, `_multiplierController`, `_travelController`, `_runController`, and if the new value is not 'custom' clear `_customAngleController`, all inside the existing `setState`.
- **effort**: S
- **round1Ref**: P3-12 (extends — P3-12 covers `_customAngleController` reset and `_isDirty` semantics, but does NOT explicitly cover wiping the four result fields on angle re-selection, which is the harder-to-spot wrong-cut path)

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:99-102 (`_isDirty` getter) + 142-149 (`PopScope`)
- **issue**: `_isDirty` returns true based on input fields only — it does NOT consider that a successful calculation has populated result fields. After CALCULATE succeeds and the fitter swipes back to copy a value from another screen, `_isDirty` is true (inputs still filled) → discard dialog fires → fitter taps "Porzuć" reflexively → returns to home screen — but the results that took 4 keystrokes to compute are gone, and on returning the screen rebuilds with empty controllers because `_RollingOffsetScreenState` was disposed. Also: `canPop: !_isDirty` is evaluated only at build time (line 143). After a calc-then-swipe-back without re-entering the screen, the build runs once with `_isDirty == true`; if the fitter then quickly clears one field and pops, `canPop` is still stale `false` until next rebuild. Round1 P3-12 mentions including `_trueOffsetController.text.isNotEmpty` in `_isDirty` — that fix would actually MAKE this worse (more dialog fires), unless paired with a "results are safe, only inputs warrant warning" decision.
- **why it matters**: Reflex-tap discard culture: when every back-button shows a dialog, users learn to dismiss them, defeating the safety net entirely. Workshop ergonomics: fitter in gloves can't reliably hit "Wróć do edycji" vs "Porzuć" — they're adjacent TextButtons (lines 113-122) with no destructive-color distinction.
- **suggested fix**: Tighten `_isDirty` to fire only when inputs differ from the last successfully-calculated values (track a `_lastCalcSnapshot`), or only show dialog when results are NOT yet computed (pre-CALCULATE state). Visually mark "Porzuć" as destructive (`TextButton(style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error), ...)`).
- **effort**: M
- **round1Ref**: P3-12 (overlaps on `_isDirty` semantics but P3-12 proposed ADDING result-non-empty to dirty check — this finding argues the opposite; the two should be reconciled before either is implemented)

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:53-55, 76-81 (`angleDeg` resolution + 'custom' validation)
- **issue**: When `_selectedAngle == 'custom'` and `_customAngleController.text` is empty (or unparseable), `_parse(...)` returns 0 (line 28). The guard at line 76 (`angleDeg <= 0 || angleDeg >= 90`) catches this and shows the snackbar "Kąt musi być między 1° a 89°" — but the user has ALSO just had the result fields wiped (lines 46-49). State after: inputs present (Rise/Spread filled), chip shows "Inny" highlighted, custom-angle field blank, all four results blank, snackbar floating. The user re-types the angle and hits CALCULATE — works. BUT if the user instead taps a preset chip (45°) at this point, `_selectedAngle` flips but the still-blank `_customAngleController` is left blank — fine. However, the inverse case: user has a successful calc with preset 45°, then taps "Inny" by mistake — `_selectedAngle = 'custom'`, custom field appears empty (line 171-175 conditional render mounts an empty TextField), but the result controllers STILL hold the 45° values (as flagged in finding #2 above). Now the fitter sees Travel=707.1 + an empty custom-angle field + "Inny" highlighted — they don't know which angle produced 707.1.
- **why it matters**: Compound failure — combination of (a) angle-chip change not wiping results and (b) 'custom' mount/unmount semantics make the result panel's provenance ambiguous. Welder cannot answer "for which angle is this Travel valid?" by looking at the screen.
- **suggested fix**: Either (a) require both angle AND results to come from the same calculation invocation by clearing results on ANY angle change (preset OR toggling custom mode), OR (b) annotate the WYNIKI section header with the angle used for the last calc — e.g. `_sectionLabel('WYNIKI (kąt 45°)')` updated after successful `_calculate`.
- **effort**: S
- **round1Ref**: new (compound of P3-12 and finding #2 above — not separately covered)

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:104-126 (`_confirmDiscard` dialog)
- **issue**: `showDialog<bool>` uses `context: context` (line 106) from the State — which is the same context PopScope is observing. If the framework is mid-pop transition the dialog can fail to attach (`Looking up a deactivated widget's ancestor is unsafe`). No try/catch around the `await`. If `showDialog` throws, the future resolves with the error and `_confirmDiscard` propagates it; `onPopInvokedWithResult` doesn't await with error handling (line 147) — uncaught exception in async callback → red error overlay in debug, silent swallow in release but the back-button is now in a broken state.
- **why it matters**: Edge case (rapid double-tap of back button or system back + gesture), low frequency, but the failure mode (stuck unable to back out) is workshop-frustrating.
- **suggested fix**: Wrap `await showDialog` in try/catch returning false on error; or guard with `if (!mounted) return false;` before the await.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:144-149 (`onPopInvokedWithResult`)
- **issue**: `Navigator.of(context)` captured at line 146 before the await (good pattern). But the `mounted` check at line 148 guards only `nav.pop()`. If the dialog returns `discard = false` (user kept editing) the function returns silently — fine. But there's no handling for the case where `_confirmDiscard` returns true AND the widget was unmounted during the dialog wait (e.g. parent route was disposed by deeplink navigation). `nav.pop()` would not run (guarded by `mounted`) — but the user's discard intent is silently dropped. They will tap back again and re-see the dialog.
- **why it matters**: Very rare; deeplink / push-notification mid-dialog. Minor UX glitch.
- **suggested fix**: Acceptable as-is; optionally log the dropped intent in debug builds.
- **effort**: S
- **round1Ref**: new

--- end block ---


## Iter #8 · lib/screens/hydrotest_screen.dart · concurrency-races

- **severity**: low
- **location**: lib/screens/hydrotest_screen.dart:340-342 (`_copyReport` end)
- **issue**: `if (!mounted) return;` sits BEFORE the only await in `_copyReport` (line 341 `await copyToClipboard(...)`). The function entered from an IconButton.onPressed and does zero awaits between entry and line 340 — the guard can never fire. The real cross-async-gap protection lives inside `copyToClipboard` (clipboard_helper.dart:16 already checks `context.mounted` after `Clipboard.setData`), so the path is sound, but the misplaced guard is dead code that gives a false sense of safety.
- **why it matters**: A future refactor adding an `await` between line 306 and 340 (e.g., awaiting a settings lookup for unit preference, or a Fakturownia trace token) will not be protected — author assumes "we already check mounted" and ships a use-context-after-unmount bug. Wedged report screens mid-shift while welder back-presses.
- **suggested fix**: Either delete line 340 (it's redundant — `copyToClipboard` self-protects), or move it AFTER the `await copyToClipboard` and re-show snackbar there if needed. Add a code comment explaining where the actual mounted check lives.
- **effort**: S
- **round1Ref**: new (concurrency hygiene — not in BACKLOG_2026-06-07)

--- end block ---

## Iter #8 · lib/screens/hydrotest_screen.dart · concurrency-races

- **severity**: low
- **location**: lib/screens/hydrotest_screen.dart:91-98 (Copy report IconButton onPressed) and 404-408 (_FactorChip GestureDetector)
- **issue**: No debounce / in-flight flag on the "Copy report" IconButton or the three factor chips. A fast double-tap on the AppBar copy icon fires two parallel `_copyReport` calls — both write the same clipboard payload (benign) but both call `Haptic.copied()` (double pulse) and both call `ScaffoldMessenger ..hideCurrentSnackBar() ..showSnackBar(...)` — the second hide cancels the first show, producing a visible flicker. On factor chips, a frantic chip-mashing welder can interleave `setState(() => _factor = 1.5)` with `setState(() => _factor = 1.3)` — outcomes are deterministic (last tap wins), but each tap triggers a full rebuild of the result card during typing, with no debounce on `_designCtrl.onChanged` either — perceptible jank on low-end Android tablets common on site.
- **why it matters**: A welder with gloves and water on the screen does not get a single clean tap; the calculator visibly stutters and the haptic feedback misfires, which the welder reads as "the app didn't catch my input" and they retap, compounding the problem. The hydrotest screen is used precisely when nerves are highest (live pressure test in progress).
- **suggested fix**: Track `bool _copying = false;` and gate `_copyReport` entry; gray the icon while copy is in flight (~150 ms). For factor chips, the existing `if (!selected) Haptic.tap();` already short-circuits redundant haptic — fine. For design-pressure typing rebuilds, debounce `setState` via 80 ms `Timer` if profiling shows jank.
- **effort**: S
- **round1Ref**: new (concurrency-races — fast-tap race on copy + rebuild storm during typing)

--- end block ---

## Iter #8 · lib/screens/hydrotest_screen.dart · concurrency-races

- **severity**: low
- **location**: lib/screens/hydrotest_screen.dart:51-79 + 91-98 (computed result snapshot vs IconButton onPressed closure)
- **issue**: The "Copy report" `onPressed` closure captures `od, wall, id, lengthM, design, _factor, testPressure, volL, flowLpm, fillMin` from the CURRENT `build()` scope (lines 56-82). Between the tap event being scheduled by the OS and the gesture arena resolving it, another rebuild can occur (e.g., keyboard dismiss triggering MediaQuery rebuild via `MediaQuery.viewPaddingOf(context)` at line 103). The CALLBACK retains the older closure (Dart closes over the lexical scope at function literal creation time), so a welder who edits a field after tapping but before the callback fires gets the PRE-edit snapshot in the clipboard. This is correct Flutter semantics (snapshot at tap time), but the calculator does not surface which values were copied — there's no toast confirming "Pressure 15 bar, volume 24.3 L copied" — the welder cannot tell that the just-changed field was NOT included.
- **why it matters**: The fitter changes design pressure from 10 to 16 bar after seeing the result, taps copy, pastes into WhatsApp to the QC engineer — but the clipboard contains the 10-bar report. QC procedure is wrong; pressure test runs at 50% of intended factor. Real workshop scenario the moment the welder spots a missing zero last-second.
- **suggested fix**: Either (a) recompute the snapshot INSIDE `_copyReport` by reading controllers fresh — guarantees latest user input, or (b) keep the snapshot pattern but show a confirmation snackbar listing the captured test pressure + volume so a wrong-snapshot copy is immediately visible.
- **effort**: S
- **round1Ref**: partial overlap with P1-22 (Share/Copy AppBar wiring) — concurrency angle is new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: high
- **location**: lib/screens/pipe_route_calculator_screen.dart:170-240
- **issue**: Results section lives BELOW the CALCULATE button in a `SingleChildScrollView`, so after tapping CALCULATE on a phone held in a gloved hand, the keyboard collapses and the computed Segment 1/2/3 and TOTAL render off-screen — fitter must scroll down blindly to see what just came out. No `Scrollable.ensureVisible` / `scrollController.animateTo` is called after `_calculate()`.
- **why it matters**: Welder taps OBLICZ to verify a cut before grinding; if the answer is hidden below the fold he assumes the app froze, taps again, gets the same SnackBar/no scroll, and walks away. On a gloved sausage-finger workflow this is the #1 abandonment risk.
- **suggested fix**: Wrap the results block in a `GlobalKey`, after `setState(() {})` in `_calculate()` call `Scrollable.ensureVisible(_resultsKey.currentContext!, alignment: 0.0, duration: 200ms, curve: Curves.easeOut)` so TOTAL snaps into view.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: high
- **location**: lib/screens/pipe_route_calculator_screen.dart:128-156
- **issue**: Input layout pairs H1+H2 in one row and X+Y in another with `Expanded` + 12 dp gap — on a 360 dp phone that gives ~168 dp per field. The `labelText` "H1 – wys. startu" / "X – bieg poziomy 1" is long enough to ellipsize or wrap when the field is focused (label floats above) AND the value is 4-5 digits ("12345 mm"). Floating label clashes with suffix "mm" because both compete for the same right-edge real estate at narrow widths.
- **why it matters**: A fitter measuring 12 487 mm horizontal cannot quickly verify the value he just typed because the label collapses to "H1 – wy…" and the unit "mm" cramps against the digits — easy to mistake mm for cm and double-cut a 400 PLN spool.
- **suggested fix**: Stack H1/H2 and X/Y vertically on screens < 380 dp via `LayoutBuilder`, or shorten labels to plain "H1 (mm)", "X (mm)" and drop redundant `suffixText`.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:223-230
- **issue**: The Formula info button is rendered as a 20 dp icon inside a 32 x 32 dp constraint, INSIDE the TOTAL primaryContainer card. Tap target is below the 48 dp Material guideline and sits next to the bold TOTAL text — a gloved finger pressing the "SUMA (bez kolanek)" label often triggers the info dialog accidentally, hiding the result.
- **why it matters**: On the shop floor with cotton gloves the welder taps the TOTAL row to focus / copy it, instead gets a 14-line formula dialog popping over the answer. Cognitive cost: he loses orientation, has to dismiss + re-scroll.
- **suggested fix**: Move the formula info button out of the Row — make it a trailing `IconButton` aligned right with 48 x 48 hit area, or replace with a subtle question-mark chip below the suma value. Keep min 48 dp tap target.
- **effort**: S
- **round1Ref**: P1-07 (related, tap target >= 48 dp)

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:173-195
- **issue**: Empty-state placeholder ("Wpisz H1, H2, X, Y…") sits where the 3 result fields + TOTAL card will appear, but the placeholder height (~120 dp icon + text) is much shorter than the filled state (~340 dp: 3 fields + 16 sb + container). Layout jumps ~220 dp upward when results appear, causing the SUM card to overshoot the visible viewport.
- **why it matters**: The vertical jump means after OBLICZ the welder sees the screen "jump" and his eye loses the TOTAL — compounds the off-screen problem from finding #1. Visual continuity matters on a sun-glare site display.
- **suggested fix**: Wrap empty state in a `SizedBox(height: ~340)` or render skeleton result fields in disabled state so the layout has stable height before/after CALCULATE.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:197-204, 327-346
- **issue**: Segment result fields use the same `OutlineInputBorder` + `mm` suffix as the input fields above, with only `filled: true` and readOnly distinguishing them. Visually the welder cannot tell at a glance which row is INPUT and which is OUTPUT — both are rounded rectangles with "mm" suffix. The `_sectionLabel` headers in CAPS are the only separator and they scroll out of view as the user reads.
- **why it matters**: At a glance during a quick check, the fitter may try to edit the result field thinking it is an input, or copy from the input thinking it is the output. Misreads cost stock.
- **suggested fix**: Render results as `Card` + bold display-large monospaced number on a contrasting tinted surface (e.g. `theme.colorScheme.surfaceContainerHigh`), drop the TextField/border treatment for output. Inputs = textfields, outputs = read-only display tiles.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:243-260
- **issue**: Two trailing `bodySmall` paragraphs (Wzór + Spoiny) hang below the SUMA card with no visual grouping — they look like footnotes/legalese and are easy to dismiss. The FW/SW weld-marking advice is genuinely important for the welder mapping the iso but blends into theme default outline grey.
- **why it matters**: The FW/SW guidance is the bridge from "I have 3 numbers" to "now I weld them in field order" — burying it as small grey text breaks the workflow handoff. Workshop reading distance + brightness will dim it further.
- **suggested fix**: Wrap each note in an `ExpansionTile` titled "Wzor" / "Oznaczenie spoin (FW/SW)" with a `lightbulb_outline` leading icon — collapsible, scannable, and surfaces the FW/SW callout with intent.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:115-119
- **issue**: AppBar shows only title + HelpButton. There is no inline visualisation of the pipe route (3 segments, 3 elbows, X/Y/H1/H2 labels) — the user must mentally map "X = bieg poziomy 1" to physical geometry. The formula dialog at line 267 is the only place where geometry is described, and only in text.
- **why it matters**: Without a sketch the welder can swap X and Y if he reads the iso from the other side; "bieg poziomy 1" vs "bieg poziomy 2" is ambiguous on a real 3D run. A static SVG/CustomPaint of the L-with-2-bends route with labelled arrows is the canonical fitter-friendly cue.
- **suggested fix**: Add a small `CustomPaint` (or asset SVG) above DANE WEJSCIOWE showing the 3-elbow route with H1/H2/X/Y/R labels; <= 120 dp tall. Reuse the existing route sketch painter if one exists on the rolling_offset / saddle screens.
- **effort**: L
- **round1Ref**: new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:159-167
- **issue**: The CALCULATE button is full-width `FilledButton.icon` with `padding: EdgeInsets.symmetric(vertical: 16)` — fine on phone, but on a 600 dp+ tablet (some site shops use 7" foreman tablets) it spans the entire screen width with the icon and label drifting apart, making the button look like a banner rather than a button. No `ConstrainedBox(maxWidth: 360)`.
- **why it matters**: Tablet users (foremen reviewing iso) see a confusing "is this a button or a header?" element. Visually centred buttons read as action; banner-wide buttons read as content.
- **suggested fix**: Wrap the `SizedBox(width: double.infinity)` in `Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 480), …))`.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · ux-layout-deeper

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:336-343
- **issue**: Copy IconButton on each result field sits inside the `suffixIcon` slot, which on a focused/filled outlined TextField visually overlaps the "mm" suffixText. The 24 dp icon + 48 dp hit area pushes the value text leftwards, so 5-digit results ("12345.7 mm") need horizontal scroll on narrow phones.
- **why it matters**: A 5-digit segment for a 12 m header pipe truncates or scrolls, masking the most important digit (units place). Welder may read 1234 instead of 12 345.
- **suggested fix**: Move copy IconButton OUT of the suffixIcon slot — put it as a trailing `IconButton` in a `Row` next to the field, or use a dedicated `ListTile` with `trailing` copy action. Or shrink suffix to "mm" inline-bold inside the value Text and reserve the suffix slot for copy.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · input-validation-deeper

- **severity**: high
- **location**: lib/screens/orbital_tig_screen.dart:56, 75 (and lib/services/orbital_tig.dart:41-70)
- **issue**: Arc voltage input is silently coerced. `_p(_volts.text) ?? 10` accepts any positive number (including `0`, `0.001`, `999`, `12345`) without bound check. The value flows directly into `estimateOrbital(arcVolts: v)` and multiplies into the heat-input formula `0.6 * arcVolts * base / vMmS / 1000`. A welder fumble-typing `100` instead of `10` displays a 10x heat input (e.g. 0.4 -> 4.0 kJ/mm) with no warning. The copied paste-string then transmits the wrong WPS qualification basis to the foreman.
- **why it matters**: Orbital TIG on thin-wall 316L is a heat-input-limited procedure (food / pharma piping). A bogus voltage produces a bogus kJ/mm that gets copied verbatim into the WPS form. Either the welder distrusts the app and stops using it, or worse, runs the coupon against falsified energy and the weld passes a procedure it shouldn't.
- **suggested fix**: Bound arcVolts to a realistic TIG window (e.g. 6-20 V). If `v < 6 || v > 20`, set `_error` with bilingual "Napiecie poza zakresem 6-20 V / Voltage outside 6-20 V" instead of silently using it.
- **effort**: S
- **round1Ref**: P1-30 (per-field sanity bounds; round-1 bullet did not enumerate the voltage field specifically)

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · input-validation-deeper

- **severity**: high
- **location**: lib/screens/orbital_tig_screen.dart:57-68, 75
- **issue**: OD and wall validation rejects only `<= 0`. No upper bound. A common thumb-fumble - typing `254` instead of `25.4` (PL keyboard, comma key adjacent to numbers) or `1650` for `1.65` - sails through into `estimateOrbital`. The resulting "current" jumps to ~12000 A and travel speed clamps to 70 mm/min, but the screen displays them as valid orange figures. The welder may notice 12000 A is absurd, but the `heatInputKJmm` figure of 80+ kJ/mm is at the edge of what looks plausible to a hurried operator scanning the row.
- **why it matters**: The screen says "STARTING values for coupon". If the displayed start is two orders off, the coupon set-up wastes 20 minutes of head time and an argon bottle before the operator realises. On a foreman's clipboard via the copy button, the bad numbers ship to whoever asked for parameters.
- **suggested fix**: Clamp OD to (0, 1000) mm (DN ~1000 is the orbital head limit) and wall to (0, 25) mm, with "Sprawdz wymiar / Check dimension" hint if exceeded. Service should also `clamp` internally as defence-in-depth.
- **effort**: S
- **round1Ref**: P1-30 (per-field sanity bounds on every numeric input)

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · input-validation-deeper

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:47-48, 314
- **issue**: `_p` does `double.tryParse(s.replaceAll(',', '.'))` and the input filter `RegExp(r'[0-9.,]')` allows ANY count of dots and commas. Typing `1.2.5` or `1,2,5` produces a null double, which triggers the "Podaj srednice... / Enter tube OD..." error. This is misleading because the user DID enter something. They re-type the same number, see the same error, and assume the app is broken. There is no specific "Niepoprawny format / Invalid number" message.
- **why it matters**: Confusing error messages cost a fitter 30 seconds of squinting under a welding hood; repeated they breed app distrust and the screen gets uninstalled in favour of paper.
- **suggested fix**: Tighten the formatter to allow at most one separator (custom `TextInputFormatter` matching `^\d*[.,]?\d*$`). When `_p` returns null on non-empty input, surface a distinct "Niepoprawny format liczby / Invalid number format" error rather than reusing the empty-field message.
- **effort**: M
- **round1Ref**: new (parse-error message disambiguation; round-1 covered bounds, not format-vs-empty)

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · input-validation-deeper

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:33, 153-165, 239-242, 250
- **issue**: The traceability field has neither `maxLength` nor a newline/control-char filter. A welder paste from a WPS PDF (common workflow) lands the full multi-line WPS header into `_trace`. `.trim()` (line 239) only strips leading/trailing whitespace; embedded `\n`, `\t`, and stray Unicode separators stay. The "Copy all parameters" output (line 250) becomes mangled: lines `$header\n$lvl\n$geo$traceLine` split on the embedded `\n` so the foreman's chat shows half the parameters under a random WPS title. Also no upper bound - pasting a 5 KB blob is possible.
- **why it matters**: The whole point of the trace field is a clean one-line stamp the foreman can scan. A garbled paste defeats traceability and a multi-kB paste can wedge low-end Android keyboards.
- **suggested fix**: Add `maxLength: 40`, `inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\r\n\t]'))]`. In the copy handler also do `_trace.text.replaceAll(RegExp(r'\s+'), ' ').trim()` to collapse internal whitespace before stitching the paste string.
- **effort**: S
- **round1Ref**: P1-12 (round-1 names this field with 40-char cap; this finding adds the newline-strip and the copy-time collapse that P1-12 omits)

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · input-validation-deeper

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:28, 56, 229
- **issue**: The voltage field defaults to `'10'` text, and `_p(_volts.text) ?? 10` silently substitutes 10 when the field is cleared OR when parse fails. Combined with the missing format error (finding above) this means if the welder deletes "10" to type "12" but accidentally types `.` first, the field is `.` -> parse null -> silent fallback to 10. The result card shows numbers computed at 10 V but the displayed input field shows `.` - the welder reasonably believes the numbers were computed at the displayed (broken) input. Also the copy handler at line 229 silently re-uses the same fallback `?? 10`, so the foreman sees `U=10 V` in the paste even though the welder thought they were entering 12.
- **why it matters**: A welder cannot trust the screen's "what you see is what you computed" contract; an invisible substitution is functioning like a bug.
- **suggested fix**: Drop the `?? 10` default. If `_p(_volts.text)` is null AND text is non-empty, treat as a parse error and refuse to compute (clear `_est`). If empty, leave the previous result but show a "Napiecie wymagane / Voltage required" hint instead of computing.
- **effort**: S
- **round1Ref**: new (silent-default vs displayed-input mismatch; round-1 did not cover this WYSIWYG break)

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · input-validation-deeper

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:50-77, 322
- **issue**: `onChanged: (_) => _calc()` recomputes on every keystroke. While typing `25.4` the user sees the field pass through `2`, `25`, `25.` - each triggers `_calc()`. If they typed wall first (e.g. `2`) and then start OD (`2`), the rule `wall > od / 2` flashes red mid-typing (`2 > 2/2 = 1` -> error). The error then disappears once OD reaches `4`. Welder pauses, rereads, tries again - 5-10 s lost per parameter entry. P1-19 already names a 150 ms debounce; this finding sharpens the requirement to also suppress the cross-field "wall > OD/2" check while either field is empty or in transition (not just debounce timing).
- **why it matters**: Spurious mid-typing errors under a hood look like the app rejecting valid input. Workshop trust in the calculator depends on it being calm during normal typing.
- **suggested fix**: Inside `_calc`, only run the `wall > od/2` rule when BOTH fields have been "settled" (debounce flag set) AND both > 0 with non-empty text; otherwise hide the error rather than display the cross-check.
- **effort**: S
- **round1Ref**: P1-19 (debounce names the timing; this adds the cross-field settle-gating which P1-19 leaves implicit)

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · input-validation-deeper

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:54-75 (and lib/services/orbital_tig.dart:46-78)
- **issue**: The service is designed for "thin-wall austenitic stainless tube" per its own header comment, but the screen accepts arbitrary wall thickness with the only domain rule being `wall <= od/2`. A welder running a thick-wall flange (e.g., OD 100, wall 10) gets a result card with "Passes: 2" and a base current of `48 * 10 + 0.12 * 100 = 492 A` - an orbital head physically cannot run 492 A; the figure is outside the model's design envelope. No "out-of-envelope / outside model scope" banner is shown.
- **why it matters**: The disclaimer at the top says "STARTING values" but does not say "thin-wall only". A welder using the tool on a thick-wall fitting silently gets a number outside the formula's intended domain, and the copied paste-string carries that bogus 492 A to the foreman.
- **suggested fix**: Add a soft warning (orange chip, not blocking error) when `wallMm > 3.0` or `odMm > 168.3` (orbital head practical envelope) with text "Poza zakresem cienkosciennym - wynik orientacyjny / Outside thin-wall envelope - indicative only". Keep the calculation, just flag it.
- **effort**: S
- **round1Ref**: new (envelope warning; distinct from the bounds finding above. This is soft model-validity advice, not a hard rejection)

--- end block ---

## Iter #11 · lib/screens/pre_weld_checklist_screen.dart · async-crash-safety

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:152-162 (`_toggle`) + 158, 161 (Haptic calls)
- **issue**: `Haptic.tap()` and `Haptic.saved()` are invoked as fire-and-forget Futures from inside the `setState` callback (158) and immediately after (161). `Haptic._safe` does catch internally, so today's call is safe — BUT the call inside `setState(() {...})` runs as part of the synchronous closure, and if `Haptic.tap()` were ever refactored to throw BEFORE reaching `_safe` (e.g. someone adds a non-null assertion or a static analytics hook above `_safe`), the throw lands inside `setState` and corrupts the rebuild — the tick mutation `_done.add(i)` happens, but the `setState` exception escapes, the rebuild is skipped, and the welder sees no checkmark on the item they just tapped. They tap again, `_done.contains(i)` is now true so the branch flips to remove — the user's first tap silently became a no-op. Async-crash-safety relies on synchronous side effects inside `setState` being throw-free.
- **why it matters**: Welder under hood taps the "PWHT slot booked" item, sees no green tick, taps again — checklist now reads UNticked when in their head it is ticked. Pre-weld-safety integrity erodes over an invisible code path.
- **suggested fix**: Move `Haptic.tap()` OUTSIDE the `setState` closure (call it after `setState(...)` returns), mirroring the `Haptic.saved()` placement at line 161. Defensive against future refactors of Haptic that introduce a throw above `_safe`.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #11 · lib/screens/pre_weld_checklist_screen.dart · async-crash-safety

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:161 (`if (_done.length == _all.length) Haptic.saved();`)
- **issue**: `Haptic.saved()` (medium-impact buzz, semantically "saved/persisted") fires every time `_done.length == _all.length` evaluates true — meaning if the welder unticks the last item then re-ticks it, the "saved" buzz fires AGAIN. There is no edge-trigger guard (e.g. `_wasAllDone` flag). The screen header even reframes the buzz as "Gotowe — możesz zajarzać łuk" — celebratory feedback. Spamming the celebratory buzz mid-checklist edit (welder discovers item 7 was wrong, unticks, re-ticks, hears the "saved" thud again) trains the welder to ignore the cue. Beyond UX: this also calls `Haptic.saved()` on the SAME frame as the toggle's `Haptic.tap()` from line 158 — two haptics back-to-back inside one gesture. On low-end Androids the second can be swallowed by the haptic motor cooldown (~30 ms recovery), so the welder feels only the light tap and misses the "all done" signal — the very cue they need most.
- **why it matters**: Pre-weld checklist's strongest workflow cue (you're cleared to strike the arc) gets degraded by motor cooldown collision on the same gesture; same cue fires falsely on tick-flip-flip patterns. Erodes trust in tactile completion feedback under glove + hood.
- **suggested fix**: Add `bool _wasAllDone = false;` field; only `Haptic.saved()` when `was=false && now=true` (rising edge). Optionally schedule the saved-buzz via `Future.delayed(Duration(milliseconds: 80))` so it doesn't collide with the prior `tap()`. Even cheaper: skip `Haptic.tap()` on the toggle that crosses the "all done" threshold, fire only `Haptic.saved()`.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #11 · lib/screens/pre_weld_checklist_screen.dart · async-crash-safety

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:117-127 (`_preheatFahrenheit`) called from line 258 (`Tooltip.message:` during build)
- **issue**: `_preheatFahrenheit` runs `int.parse(m.group(1)!)` against every numeric run in `preheatNote`. Source notes today are hardcoded by the dev so values are safe — but the function offers ZERO guards: a future MaterialCatalog entry with a temperature like `15000000` (typo by future contributor) overflows `int.parse` only on 32-bit Dart (web), and on mobile produces gibberish Fahrenheit. More critically: the function is invoked SYNCHRONOUSLY inside the build method for every material chip (line 253 loop), every frame, every rebuild. A regex compile + allMatches + double-map + reduce runs per chip per build. The screen rebuilds on every checkbox tick (line 153 setState) — meaning O(materials) regex passes per tap. Not a crash, but a frame-budget tax on the screen welders interact with under hood. Combined with the rebuild-on-every-tick, on a Snapdragon 4xx phone (mentioned in iter #6 finding above as workshop fleet reality) a glove-tap that takes >16 ms to register feels mushy and can lose to a second tap, mis-toggling adjacent items.
- **why it matters**: Pre-weld checklist must be rock-solid responsive — a missed tap means the welder thinks they ticked "purge gas connected" but didn't, and strikes arc on contaminated SS. Frame-budget hits compound the haptic-cooldown issue above.
- **suggested fix**: Compile the regex once as a top-level `final _kPreheatNumRe = RegExp(r'(\d+)\s*°?\s*C');` (avoid per-call recompile). Memoise `_preheatFahrenheit` result per MaterialSpec.key in a `final Map<String, String> _fahrenheitCache = {};` field on the State so the per-chip Tooltip lookup is O(1) after first build. Wrap `int.parse` in `int.tryParse` and skip non-parsing matches (forward-compat for any future weird unicode digit).
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #11 · lib/screens/pre_weld_checklist_screen.dart · async-crash-safety

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:136-138 (state fields `_done` + `_material`) — entire screen
- **issue**: ALL checklist state is in-memory only. The class doc-comment at line 22-23 calls this out intentionally ("live check, not a record"). But the async-crash-safety angle the comment misses: a phone backgrounded mid-checklist (welder pauses to fetch the WPS sheet from the office), Android Doze + low-memory killer reaps the process within 90 s, welder unlocks the phone, the route is restored by Flutter's RestorationManager — but `_done` is a `Set<int>` and `_material` is `MaterialSpec?` and NEITHER is restorable (no `RestorationMixin`, no `RestorableProperty`, no key). The screen returns to its initial state with zero ticks and "generic" material — the welder may NOT notice (the AppBar title doesn't change) and proceeds to strike arc believing the checklist was completed minutes ago. Crash-safety in the broader sense: the welder's safety state is silently lost without any user-visible cue.
- **why it matters**: The checklist exists precisely to prevent striking an arc on an un-purged or wrong-filler joint. Silent state loss after backgrounding turns "I ticked all 15 items" into "the app shows no ticks" — and gloves+hood means the welder doesn't double-check the screen, they trust the buzz they felt 90 s ago.
- **suggested fix**: Option A (minimum): on `AppLifecycleState.paused`, write a "last checklist state" snapshot (set of ticked indices + material key) to SharedPreferences; on resume, if snapshot exists AND was created <10 min ago, show a SnackBar "Przywrocic checkliste z ostatniej sesji?" with restore action. Option B (proper): apply `RestorationMixin`, register `RestorableSet<int>` (custom) + `RestorableString` for material key. Either way: surface state-loss to the welder, never silently reset to zero.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #11 · lib/screens/pre_weld_checklist_screen.dart · async-crash-safety

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:184-187 (Reset TextButton in AppBar)
- **issue**: The Reset button passes `setState(_done.clear)` — `Set.clear` returns void and matches `VoidCallback` so it works as a setState argument. BUT: no haptic fires on reset (inconsistent with `_toggle` which haptics on tick). More importantly: no confirmation dialog. A welder mid-list (10 of 15 ticked) brushes the AppBar reset with a thumb during scroll, and 60-90 s of careful inspection vanishes silently. Crash-safety adjacent: the wipe is destructive and irreversible, runs synchronously, and Flutter's gesture system has no undo. Round-1 P1-09 / P1-05 (haptic on destructive ops + confirm before destroy) ratified the pattern; this destructive AppBar action skips both.
- **why it matters**: Welder loses pre-weld verification progress to a phantom thumb tap during a hood-up moment — no haptic confirmation, no undo, no "Reset?" dialog. Reverts safety state to zero with the same finger gesture as scrolling the list.
- **suggested fix**: Wrap in an AlertDialog confirm ("Wyzerowac checkliste? — N pozycji zaznaczonych" / "Reset checklist? — N items ticked"), call `Haptic.error()` after the wipe, snapshot the previous `_done` set into a local for a SnackBar `Cofnij` / `Undo` action (5-6 s window).
- **effort**: S
- **round1Ref**: P1-05 (haptic on destructive), P1-09 (haptic-on-tap consistency)

--- end block ---

## Iter #12 · lib/screens/elbow_takeout_screen.dart · loading-error-empty-states

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:88-94 (ListView.builder with no `_rows.isEmpty` branch)
- **issue**: Round-1 P1-10 already specified the centred "Brak wynikow — wyczysc filtr" empty state, but the code on disk still has zero branching: if `_rows` is empty the `ListView.builder` just paints 0 items and the body collapses to the search bar + legend chips floating over a void. Round-2 confirms the bug is still LIVE (commit d025247 did not ship P1-10), and the void is worse than round-1 estimated: the `Expanded` underneath the legend swallows the keyboard's safe area, so on Android the on-screen keyboard partially covers the search field while the welder stares at blank dark grey wondering whether to long-press where rows should be. No "Brak wynikow", no "Wyczysc filtr" CTA — the welder cannot tell the filter is wrong vs. the table is broken.
- **why it matters**: Welder in dust + gloves types "D N 5 0" (autocorrect inserts a space — `_q` becomes "dn 50", contains-check fails) and the screen goes silent. He swipes back, opens it again — same blank. He assumes "the new app version broke the elbow table" and goes back to paper catalogue, eroding the very trust the offline-first promise was built on.
- **suggested fix**: Land the P1-10 fix verbatim: `if (_rows.isEmpty && _q.isNotEmpty) return _NoResults(query: _q, onClear: () { _filter.clear(); setState(() => _q = ''); });` inside the `Expanded` slot. Two-line message: bold `Brak wynikow dla "$q"` + `OutlinedButton('Wyczysc filtr')`.
- **effort**: S
- **round1Ref**: P1-10 (still unshipped — round-2 confirms regression risk)

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:64-86 (TextField has no `suffixIcon` clear button)
- **issue**: The only way to escape a failed search is to backspace each character — gloves on, that is 4-6 mis-presses to clear "dn 50". The TextField has `prefixIcon` but no `suffixIcon` clear (X) button, no `clearButtonMode` equivalent (Material 3 doesn't auto-show one), no `IconButton(onPressed:_filter.clear)` adornment. When the filter returns zero rows (the very moment the user is most stuck), the recovery affordance is absent. This is the loading-error-empty-states sister bug to the missing empty state: even if you SHOW "Brak wynikow", the user has no one-tap way back to the full table.
- **why it matters**: Welder on a ladder, one hand on the rail, the other on the phone — backspace 6x to clear is impossible. Real users will just close the app and reopen it. Each occurrence trains "the search is broken, scroll instead". The 25-row table doesn't need search at all if search is unusable, so the feature degrades to dead weight.
- **suggested fix**: `suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _filter.clear(); setState(() => _q = ''); }, tooltip: context.tr(pl: 'Wyczysc', en: 'Clear'))`. Add `Haptic.tap()` for glove-friendly confirmation. Pair with P1-10 empty-state CTA — both should clear via the same code path.
- **effort**: S
- **round1Ref**: new (P1-10 mentions [Wyczysc filtr] inside empty state but NOT a TextField suffix clear — distinct affordance)

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:87 (_LegendBar) + 88-94 (Expanded ListView)
- **issue**: When `_rows.isEmpty` the `_LegendBar` ("DN / NPS · LR 90° · SR 90° · LR 45°") still renders at full opacity above the empty list. A welder seeing four column headers with NO rows below interprets the screen as "the columns exist but data is loading / failed to load" — not "your filter matches nothing". Loading-vs-error-vs-empty ambiguity: three distinct states (still loading / errored / filter mismatch) all present the same visual to the user. Combined with iter #37 round-1's "no error boundary" finding, the screen has no state-discrimination affordance at all — every failure mode looks like "stale columns over a void".
- **why it matters**: Workshop user with no debugging vocabulary sees "headers without data" and concludes the app is mid-load (sets phone down, waits, nothing happens), or that the data refresh failed (force-quits, reopens, blank again). Neither matches reality (filter mismatch). Time lost ~1 min per occurrence x dozens of fitters x daily searches.
- **suggested fix**: Dim `_LegendBar` to 30% opacity when `_rows.isEmpty && _q.isNotEmpty`, or hide it outright and replace with the empty-state widget. If `kElbowTakeouts.isEmpty` (future remote-config failure) show distinct "Tabela kolan chwilowo niedostepna — sprawdz polaczenie" with retry — different copy than "Brak wynikow dla \"$q\"".
- **effort**: S
- **round1Ref**: P1-10 (overlaps the empty-list-from-filter angle but adds the three-state discrimination requirement)

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:89-94 (ListView.builder with persistent scroll offset on filter change)
- **issue**: No `ScrollController` reset / `jumpTo(0)` when `_q` changes. Scenario: user scrolls down to DN300 in the unfiltered list, types "dn50", filter cuts list to 1 row (DN50) — but the ListView's internal scroll offset of ~450px is still applied, so the single matching row renders below the viewport. From the user's perspective: typed a filter, list went BLANK (the empty-state lens sees this as a false-negative empty state — there IS data, but it looks empty). User cannot distinguish "scrolled off-screen" from "no results" — the response to both is to backspace and retry.
- **why it matters**: Confuses the welder into thinking the filter found nothing when it actually found exactly what was wanted. Trust erosion compounds: "even when I type right, app shows nothing".
- **suggested fix**: Hold a `_scroll = ScrollController()`; on `onChanged` when query goes from empty to non-empty (or row count drops), `_scroll.jumpTo(0)` inside `setState`. Wire `controller: _scroll` on the ListView.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:28 + 42 (kElbowTakeouts referenced as the source of truth)
- **issue**: No defensive handling for `kElbowTakeouts.isEmpty` at startup (today impossible — it's a `const` list of 25 rows, but the loading-error-empty-states lens demands the data-empty branch exists). If a future PR ever moves the table to a generated file, a JSON asset, or remote-config (likely given user's Firebase stack), an empty list at boot renders a screen with only the search box + dimmed legend + void — IDENTICAL to the filter-no-results state, and indistinguishable from a backend outage. Currently `_rows` returns `kElbowTakeouts` when `_q` is empty, so an empty source = empty rows = same silent void. No "data not available" message, no retry path.
- **why it matters**: Forward-looking: the moment the data source becomes async (Remote Config rollout, A/B testing of alternative standards like JIS B2311), this screen has zero failure ceremony — the welder sees an empty table during the rollout, files no bug (because the screen looks "loaded" — just empty), and the team learns months later from churn metrics.
- **suggested fix**: Branch on `kElbowTakeouts.isEmpty` (or future data-source result) BEFORE filter logic: render a distinct "Tabela kolan nie zaladowala sie — [Odswiez]" with retry. Keep separate from the filter-empty state. Even today, `assert(kElbowTakeouts.isNotEmpty)` paired with a release-mode fallback would document intent.
- **effort**: S
- **round1Ref**: iter #37 "no error boundary" (related — but iter #37 is about exceptions; this is about empty-data-success state)

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:80-84 (onChanged setState without `mounted` guard, no debounce)
- **issue**: The filter callback calls `setState(() => _q = t)` directly — no `mounted` check, no debounce. Today it's safe because TextField only fires while widget is alive, but if a user types fast then navigates away (pops the route during a 60 Hz keystroke), the trailing `setState` after dispose throws "setState called after dispose" red-screen during the navigation animation. The loading-error-empty-states lens cares because that red screen IS the error state the user sees — and there is no error handler. Also: every keystroke rebuilds the entire list — on a low-end Android (Samsung A14) the rapid setState during typing can drop a frame and render a brief "blank Expanded" between rebuilds, mistaken for an empty state.
- **why it matters**: Edge case (route pop mid-keystroke), but the resulting red screen is the worst possible UX for a workshop tool. Combined with no error boundary (iter #37 round-1), there is no graceful fallback.
- **suggested fix**: Guard `if (!mounted) return;` before `setState`; add a 150-200 ms `Timer` debounce on `onChanged` so filter recomputes only after the welder stops typing (also halves CPU during typing on low-end devices).
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: high
- **location**: lib/screens/cut_list_summary_screen.dart:106 (`const Text('CUT LIST')`)
- **issue**: AppBar title is a hardcoded English `Text('CUT LIST')` with no `context.tr` wrapper. Every other widget in this file (`_PipeGroup` header line 500-503, `_GlobalSummary` line 380-383, `_BarCard` line 622) flips to PL/EN — this single literal stays English even when the user switched the whole app to Polish.
- **why it matters**: Polish-only fitter opens "Lista cięć" from the home grid expecting consistent PL chrome; sees an English ALL-CAPS title that reads like leftover Lorem-Ipsum and erodes trust on a screen they're about to print/share to a foreman.
- **suggested fix**: `Text(context.tr(pl: 'LISTA CIĘĆ', en: 'CUT LIST'))` (uppercased to match the visual hierarchy of adjacent `_SectionLabel` widgets).
- **effort**: S
- **round1Ref**: new (slipped past P3-04 i18n style sweep)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: high
- **location**: lib/screens/cut_list_summary_screen.dart:201-220 (`_buildTextSummary`) — invoked by the Share/Copy IconButton at line 124-126
- **issue**: The clipboard text payload is fully hardcoded English ("CUT LIST — ...", "Material:", "Stock:", "Kerf:", "Bar N:", "(rem: ... mm)") regardless of `AppLanguage.current`. The PL SnackBar "Skopiowano do schowka" (line 262) confirms a successful copy, but what landed in the clipboard is English-only — opposite of the AppBar's bilingual tooltip "Kopiuj tekst" / "Copy text".
- **why it matters**: PL fitter taps "Kopiuj tekst" to paste a cut list into a WhatsApp message to the warehouse / brygadzista; what arrives is English text the recipient may not parse. Worse: the Polish UI just lied about what got copied. PDF export (via `PdfExportService`) likely has the same issue but is out of scope for this lens.
- **suggested fix**: Pass `BuildContext` into `_buildTextSummary` and use `context.tr` for every literal — PL labels "LISTA CIĘĆ", "Materiał:", "Sztanga:", "Kerf:", "Sztanga N:", "(zostaje: ... mm)" should match the on-screen card copy.
- **effort**: M
- **round1Ref**: extension of P1-26 / P1-28 (clipboard payload localisation, not just snackbar)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:85-89 (`SnackBar(content: Text('PDF błąd: $e'), ...)`)
- **issue**: PDF export-error SnackBar is Polish-only ("PDF błąd: $e") AND embeds the raw exception string verbatim. EN user gets a half-Polish error, PL user gets a half-developer error (`MissingPluginException`, `PathAccessException(..., OS Error: Permission denied, errno = 13)` is not workshop-readable in either locale).
- **why it matters**: Foreman trying to PDF the cut list at the saw bench sees gibberish like `PDF błąd: PathAccessException` mid-shift — can't tell whether to retry, free up storage, or call IT. EN user thinks the app is broken in two languages at once.
- **suggested fix**: `context.tr(pl: 'Nie udało się wygenerować PDF — sprawdź miejsce na dysku', en: 'Could not generate PDF — check storage')` plus a separate debug-only log of the raw exception. Mirror P1-28's `PathAccessException` errno-13 special-case.
- **effort**: S
- **round1Ref**: P1-28 (cut-list export error messaging — same anchor lines)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:320 (`project.name?.isNotEmpty == true ? project.name! : 'CUT LIST'`)
- **issue**: Fallback title in `_ProjectHeader` for unnamed projects hardcodes English `'CUT LIST'` ALL-CAPS. Same anti-pattern as the AppBar finding — appears in a card the user reads right under the AppBar, so the PL user gets the English fallback twice on one screen.
- **why it matters**: An "Untitled" cut-list shared to a print queue carries an English heading into Polish workshop paperwork — looks like a default placeholder leaked from a wireframe.
- **suggested fix**: `: context.tr(pl: 'LISTA CIĘĆ', en: 'CUT LIST')` (unify with the AppBar-title fix via a shared const).
- **effort**: S
- **round1Ref**: new (same string as AppBar finding above)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:526-529 (`'${plans.length} ${context.tr(pl: 'szt.', en: plans.length == 1 ? 'bar' : 'bars')}'`)
- **issue**: PL branch always uses the abbreviation `'szt.'`, EN branch does ad-hoc singular/plural based on count. Polish has its own three-way plural rule (1 / 2-4 / 5+ → 1 sztanga / 2 sztangi / 5 sztang). Using "szt." sidesteps it on the PL side, but ALL adjacent labels on the same screen say "Sztangi" (line 389) or "Sztanga ${i+1}" (line 622). Mixing "szt." with full-word "Sztangi" reads as a typo on a paid app.
- **why it matters**: Workshop print of "5 szt." reads as "5 pieces" of anything — weakens the visual link to the stock-bar count shown below. A brygadzista may count 5 generic pieces, not 5 stock bars, and order wrong material.
- **suggested fix**: Centralise a `pluralBars(int n, BuildContext)` helper returning `1 sztanga / 2-4 sztangi / 5+ sztang` (PL) and `1 bar / N bars` (EN); reuse across `_PipeGroup` header + `_GlobalSummary` "Sztangi" label.
- **effort**: S
- **round1Ref**: new (Polish pluralization gap — sibling of P3-04 i18n style sweep)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:325-328, 501-503, 546, 564-567, 622, 647-650, 663
- **issue**: Seven `context.tr(pl: '...$x...$y...', en: '...$x...$y...')` call-sites bake string-interpolated values *inside* the translation literal. Both branches end up structurally identical (only "Sztanga" vs "Stock", "Netto" vs "Net" differ). This kills any future move to `intl`/ARB extraction (each unique number explodes into a new key), and any locale that needs a different value-format (Polish thin-space `'1 500 mm'` vs EN `'1,500 mm'`) is locked out.
- **why it matters**: BACKLOG already plans `flutter_localizations` + ARB rollout for DE/AT/UK (P2-11 mixed-units, P3-04 i18n style). Every interpolated `tr` here is rework debt — and worse, freezes German users at PL-style number formatting because the placeholder lives inside the literal not the message-format. DE fitter could read `'1,500 mm'` as 1.5 mm (DE convention) → silent off-by-1000 on the saw.
- **suggested fix**: Switch to a template pattern: `context.tr(pl: 'Rura  Ø{d} × {w} mm', en: 'Pipe  Ø{d} × {w} mm')` + small `.format({'d': ...})` extension, OR pre-format numbers via `NumberFormat(..., languageCode)` then interpolate once outside the `tr` call.
- **effort**: M
- **round1Ref**: P3-04 (i18n style guide — codify this pattern as the rule)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:226 (CSV header `'project;material;stock_mm;kerf_mm;diameter_mm;wall_mm;bar_no;piece_no;cut_mm;bar_remaining_mm'`)
- **issue**: CSV header row is permanently English snake_case. The accompanying SnackBar (line 275) markets it as "wklej do Excela" — Polish Excel default treatment will not auto-translate these headers, so the warehouse pivot-table aliases stay English.
- **why it matters**: Defensible *if* the CSV is meant as an interchange format (English-only is normal for column keys), but inconsistent with the bilingual mission everywhere else and undocumented. A PL foreman pasting into a Polish PowerQuery template hits case/encoding pain.
- **suggested fix**: Either (a) leave English snake_case but add a leading `# generated by FitterWelderPro v…` comment line explaining the convention, OR (b) `context.tr(pl: 'projekt;material;sztanga_mm;...', en: ...)` to fully localise. Document the chosen rule in an i18n style note (P3-04).
- **effort**: S
- **round1Ref**: P3-04 (i18n style guide — explicit rule for machine-data exports)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:475-476 (`_lineTag` returns `'${OD}-$materialGroup-${wall}'`)
- **issue**: `project.materialGroup` (whatever the DAO stores — possibly `CS` / `SS304` today, possibly an enum-key or PL token later) is splatted raw into the line-tag chip with no localisation indirection. If `materialGroup` ever becomes a localised string (`StalWeglowa` in a future PL-first migration), the chip becomes `'168-StalWeglowa-7.1'` which breaks the ASME line-list convention the code-comment celebrates.
- **why it matters**: Mixed-material cross-locale (PL/EN offshore + onshore) sharing needs a *stable, locale-independent* material code. Today it relies on whatever string the project DAO happens to hold — fragile against any future i18n migration of material catalog labels.
- **suggested fix**: Pipe `materialGroup` through a `materialCodeFor(group)` helper that always returns the ASME short tag (`CS / SS / DSS / IN`) independent of UI locale; add a code-comment locking the contract.
- **effort**: S
- **round1Ref**: new (i18n stability of cross-locale spec identifiers)

--- end block ---

## Iter #13 · lib/screens/cut_list_summary_screen.dart · i18n-coverage

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:14-20 (color constants), 156-168, 321, 504, 559, 622, 641, 663-664 (`const TextStyle(..., color: Color(0xFFE8ECF0))` with no `fontFamily`)
- **issue**: Dozens of `const TextStyle(..., color: Color(0xFFE8ECF0))` with no `fontFamily`. When a Polish-diacritic font is rolled out (P2-09 already mandates Roboto-Mono for cut-list lines + a Polish-diacritic font for PDF), every diacritic-containing tr-string ("Sztanga", "Odpad", "Cięcia", "nadaje się na spady") will fall back to the platform default and break the visual unity. i18n-adjacent: typography fallbacks for PL glyphs.
- **why it matters**: Generic system fonts render ć/ą/ę in noticeably different weight/style on Xiaomi/MIUI ROMs popular among Polish welders — the cut-list screen would look half-built on the exact phone demographic the app targets.
- **suggested fix**: Define a `TextTheme` in `MaterialApp` with a Polish-glyph-tested font (Inter / Roboto with extended-Latin subset) and replace hardcoded `Color(0xFFE8ECF0)` literals with `Theme.of(context).textTheme.bodyMedium`-derived styles.
- **effort**: L
- **round1Ref**: P2-09 (Polish-diacritic font — extend from PDF export into UI screens)

--- end block ---

## Iter #14 · lib/screens/material_list_screen.dart · perf-rebuilds

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:134-154 (`ListView.separated.itemBuilder`)
- **issue**: `itemBuilder` recreates a fresh `ListTile` with two `Text` widgets, a non-cached `qty/enUnit/catLabel` closure, and two `context.tr(pl:..., en:...)` calls PER ROW PER BUILD. There is no extracted `const`/stateless row widget and no `RepaintBoundary`, so any parent rebuild (locale change, scroll-triggered re-layout, future SnackBar) re-evaluates the localization branch and rebuilds every visible tile. On a 200-row BOM (large piping skid) this is 400+ Text widget rebuilds and 200+ ternary `it.category == 'PIPE'` branches every frame the screen is touched.
- **why it matters**: Fitter scrolling a long BOM in gloves on a mid-range Android workshop tablet (cheap A-series, common shop-floor handout) sees the list stutter and skip frames — looks like the app froze mid-cut planning, leading to force-quit + lost place in list.
- **suggested fix**: Extract a `class _BomRow extends StatelessWidget { final MaterialItem item; const _BomRow(this.item); ... }` wrapped in `RepaintBoundary`; precompute `catLabel`/`enUnit` once in build; pass already-localised strings down. Avoid `context.tr` deep inside hot itemBuilders.
- **effort**: S
- **round1Ref**: new (orthogonal to P1-09 InkWell wrap — perf, not haptics)

--- end block ---

## Iter #14 · lib/screens/material_list_screen.dart · perf-rebuilds

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:75-133 (Scaffold body empty-state branch + AppBar `actions: [HelpButton(...)]`)
- **issue**: The empty-state `Center > Padding > Column > Container(decoration: BoxDecoration(... withValues(alpha: 0.10), Border.all(... withValues(alpha: 0.35)), borderRadius: ...))` tree is constructed inline inside `build()` with `Colors.amber.withValues(alpha: ...)` — neither the `Container`, its decoration, nor the inner `Row`/`Text` can be `const` because `withValues` returns a non-const Color at runtime. Every locale toggle, every rotation, every keyboard-show triggers a full reallocation of the decoration object plus all child Text widgets. Same for `HelpButton(help: kHelpMaterialList)` in `actions: [...]` which is not const-constructed and is re-instantiated each frame.
- **why it matters**: An empty BOM is the FIRST screen a brand-new welder sees after install (P1-10 even highlights this) — repeated wasted rebuilds delay the coaching card's first paint by 1-2 frames on an A12 tablet, and on locale switch the amber chip visibly flickers.
- **suggested fix**: Hoist the coaching card to a `static const _BomEmptyState` widget; precompute the amber tints as `static const Color _kAmberFill = Color(0x1AFFC107); static const Color _kAmberStroke = Color(0x59FFC107);` so the whole subtree becomes const; make `HelpButton` const-constructable and lift the actions list to a `static const`.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #14 · lib/screens/material_list_screen.dart · perf-rebuilds

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:38-62 (`_load`)
- **issue**: `_load` fires `setState(() => _loading = true)` UNCONDITIONALLY at entry, even when the screen is mounted with stale data already showing — this forces a full rebuild that wipes the existing list to a `CircularProgressIndicator` even if the new fetch would have completed in 30 ms. Additionally `SharedPreferences.getInstance()` is awaited TWICE in the same method (lines 45 and 54) when a single fetch would suffice; both awaits suspend the frame and re-trigger the loading-spinner rebuild path without need. Lastly, a `setState` is also called after `await` without batching the `_items = items; _loading = false` change with any error-path reset (P0-01 / P1-01 land), meaning the rebuild count is 2 (start + end) where 1 (end-only with optimistic refresh) would suffice.
- **why it matters**: Every time the welder pops back to the BOM from ISO/Notebook (a routine 5-10 times per shift workflow), the entire list flashes white→spinner→list — the spinner is the #1 "is the app frozen?" complaint per the existing P1-01 rationale; here it's gratuitously self-inflicted.
- **suggested fix**: Skip the leading `setState(_loading = true)` on first build if `_items.isEmpty`; cache the SharedPreferences instance in a `late final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();` and await it once; on refresh keep the previous `_items` rendered and overlay a small top-progress chip instead of swapping to a full-screen spinner.
- **effort**: S
- **round1Ref**: P1-01 (mounted-safety overlap, perf angle is new)

--- end block ---

## Iter #14 · lib/screens/material_list_screen.dart · perf-rebuilds

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:64-70 (`_fmtLen`) used at 150 in itemBuilder
- **issue**: `_fmtLen` does `mm / 1000.0` + `toStringAsFixed(3)` + string interpolation every itemBuilder call, every rebuild. The result depends only on `it.totalLengthMm` (immutable post-load), so the same string is recomputed N times per scroll frame for PIPE rows. No memoization on `MaterialItem`, no per-row cache.
- **why it matters**: Negligible on a 20-row BOM, but at 500+ rows (large refinery skid quoting) the string formatting dominates list scroll perf on low-end Android — fitter scrolling fast through a quote feels jank in low-light glove conditions.
- **suggested fix**: Either add a computed `String get formattedLength` on `MaterialItem` (computed once at build time) or memoize per-row in the extracted `_BomRow` widget via a `late final String _len = _fmt(item.totalLengthMm);` field in a small wrapper class.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #15 · lib/screens/quick_converter_screen.dart · edge-case-zero-one
- **severity**: med
- **location**: lib/screens/quick_converter_screen.dart:235
- **issue**: Absolute-zero guard is Kelvin-only; user typing -300 in °C or -500 in °F produces a negative Kelvin in the result card (k = -26.85, k = -23.15) with no warning. Asymmetric physics check.
- **why it matters**: A fitter doing preheat-conversion can typo a minus or extra digit ("- 300" pasted from PWPS) and read a sub-absolute-zero Kelvin as legitimate, then quote it to the foreman. Undermines trust in the converter the moment it's questioned.
- **suggested fix**: Extend the guard: `final belowAbsZero = v != null && ((_src == 'K' && v < 0) || (_src == '°C' && v < -273.15) || (_src == '°F' && v < -459.67));` and use the same errorText branch.
- **effort**: S
- **round1Ref**: new (extends P3-01 scope)

- **severity**: med
- **location**: lib/screens/quick_converter_screen.dart:58-62 (_fmt)
- **issue**: Edge-case-one of formatting: for tiny non-zero values (e.g. converting 1 mm to m gives 0.001, but 0.5 mm to m gives 0.0005 → rendered as "0.001" via toStringAsFixed(3); 0.1 mm to m → "0.000") the value collapses to zero in display. User sees "0.000 m" for a real 0.1 mm input and may think the converter is broken or the value is truly zero.
- **why it matters**: Fitters convert wall-thickness deductions and weld-cap offsets in fractions of a mm; "0.000 m" for a real 0.1 mm input destroys the whole point of the conversion row. Also affects pressure converting bar→MPa for low test pressures.
- **suggested fix**: When `v.abs() < 0.001 && v != 0` switch to `v.toStringAsExponential(2)` or bump precision to 5; render exact 0 as "0".
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/quick_converter_screen.dart:163, 342, 425
- **issue**: No upper bound / maxLength on numeric input. Typing/pasting 1e15 or 999999999999999 produces values approaching Infinity after multiplication; _fmt renders "Infinity" or a meaningless number with zero useful precision. Edge-case at the "one too many digit" boundary.
- **why it matters**: WhatsApp/clipboard paste from a phone-keyboard tap-spam can drop 14-digit values into the field; welder sees gibberish results and assumes a bug rather than a paste error.
- **suggested fix**: Add `LengthLimitingTextInputFormatter(12)` to all four TextFields; clamp the parsed double to a sane domain (e.g. length ≤ 1e6 mm, pressure ≤ 1e6 bar, flow ≤ 1e6 l/min) with an errorText "Wartość zbyt duża / Value out of range" when exceeded.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/quick_converter_screen.dart:176, 264, 355, 438
- **issue**: Input formatter regex allows multiple separators ("12.3.4", "5,,0", "1.2,3"), and on the temp tab allows misplaced minus ("5-3", "--7"). `_parse` then returns null and the result card silently disappears mid-typing — the boundary between "valid" and "invalid input" provides no feedback.
- **why it matters**: Welder typing in gloves bumps the decimal twice; the result card vanishes with no errorText; user thinks the converter crashed and force-quits. Classic zero-feedback failure at the one-character boundary.
- **suggested fix**: Tighten regex to `RegExp(r'^-?\d*[.,]?\d*$')` via a single TextInputFormatter with `formatEditUpdate` rejecting illegal transitions, OR show `errorText: 'Niepoprawny format / Invalid number'` when controller text is non-empty but `_parse` returns null.
- **effort**: S
- **round1Ref**: extends P3-01

- **severity**: low
- **location**: lib/screens/quick_converter_screen.dart:457-461 (Flow tab card)
- **issue**: cfh and scfh render the identical computed value (both divisors are 0.4719474). At every input including zero, one, and any other, the two rows show byte-identical text. Edge case where the converter renders a duplicated row by design but the duplication looks like a copy-paste bug.
- **why it matters**: A fitter seeing two identical "211.888" rows assumes the app has a display bug and stops trusting the column; or worse, assumes scfh is mis-labeled and quotes the wrong unit upstream.
- **suggested fix**: Either drop one row and add a SmallHint explaining "scfh = cfh przy warunkach normalnych — rotametry argonu kalibrowane są tak samo", or remove scfh from source picker entirely (l/min, slpm, cfh suffice on a workshop floor).
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/quick_converter_screen.dart:198, 292, 373, 456
- **issue**: Zero-state UX: when the controller is empty (the natural opening state) the result card is hidden — no example numbers, no "Wprowadź wartość, np. 12,5" hint, no placeholder card. First-launch user sees only an input field and a dropdown with no visual confirmation that anything will happen on type.
- **why it matters**: First-time welder on a basement 3G phone opens the converter, sees only the input row, and concludes the converter doesn't work or is loading. Especially confusing because the Temp tab DOES show the Kelvin error in this state, but Length/Pressure/Flow show absolutely nothing.
- **suggested fix**: Render a faint placeholder card with the example values for "1" of the source unit (e.g. for Length src='mm': 1 mm = 0.001 m = 0.0394 in) wrapped in `Opacity(0.4)` and labelled "Przykład / Example" until `v != null`.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/quick_converter_screen.dart:425 (Flow tab)
- **issue**: Zero-flow input has no semantic warning. Typing "0" or leaving 0 selected as a converted value shows "0.000 l/min" without flagging that 0 l/min is below the workshop minimum (~6 l/min TIG, ~12 l/min GMAW) hinted in `_SmallHint` below.
- **why it matters**: Edge-case of "one value the welder definitely shouldn't accept" — zero flow means the argon bottle is closed, not just a number; reinforcing that visually (orange border or "↑ Otwórz zawór gazu") is a cheap safety nudge consistent with the existing SmallHint.
- **suggested fix**: When `lpm == 0` and `_ctrl.text.isNotEmpty` render the SmallHint in orange with prefix "⚠ Sprawdź czy zawór otwarty"; otherwise leave as-is.
- **effort**: S
- **round1Ref**: extends P1-15 spirit (safety nudge banner)

--- end block ---

## Iter #16 Â· lib/screens/heat_input_screen.dart Â· discoverability

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:163-200 (TabBar) + 258-281 (WPS range section on Heat Input tab) + 429-506 (material picker on Preheat tab)
- **issue**: The WPS range fields (Min/Max kJ/mm) live on the **Heat Input** tab, but the material chip picker that auto-fills them lives on the **Preheat / CE** tab. A first-time welder lands on Heat Input, sees empty WPS range with no hint, has to manually type values from a paper WPS â€” without ever discovering that switching tabs and tapping a P22/P91 chip would have populated those numbers automatically. The auto-fill behavior is described in copy ONLY on the second tab ("chemia + zakres WPS uzupelnia sie same"), where the welder no longer needs to know it.
- **why it matters**: Workshop welder gives up on the "in range" green checkmark feature because they can't be bothered to re-type WPS numbers; they paste the calculated HI to a Teams chat and the foreman has no validation. The biggest differentiator of this PRO screen (auto-validation against material-class WPS window) is hidden behind a tab switch.
- **suggested fix**: Add a one-line hint under the WPS range card on Tab 1 - `context.tr(pl: 'Wskazowka: wybierz gatunek na zakladce Preheat aby uzupelnic zakres', en: 'Tip: pick a grade on the Preheat tab to auto-fill')` with a tappable "Wybierz materiaÅ‚" chip that switches to tab 2.
- **effort**: S
- **round1Ref**: new (round-1 P1-24 unifies the picker widget but doesn't address cross-tab discoverability)

--- end block ---

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:171-189 (PRO badge in AppBar title)
- **issue**: The gold "PRO" pill next to the screen title is purely decorative - Container inside Row, no GestureDetector/InkWell. Welders who land on this screen (free or PRO) cannot tap the badge to learn what PRO unlocks, how much it costs, or whether they already have it. It looks like a button but does nothing - a classic dead affordance. A free user who reached this screen via deep-link or marketing wonders why the calculator works but doesn't see an upgrade path.
- **why it matters**: PRO badge is a discovery touchpoint for conversion; making it inert wastes the impression and undermines trust ("why is there a badge if nothing happens?"). Existing PRO users get no confirmation of their subscription state.
- **suggested fix**: Wrap the badge in GestureDetector(onTap: () => Navigator.pushNamed(context, '/premium')) - for active PRO users add a check icon and tooltip "Aktywne PRO"; for free users show the upgrade screen on tap.
- **effort**: S
- **round1Ref**: new (round-1 missed the dead-affordance angle on the badge)

--- end block ---

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:323-335 (heat-input formula info icon) vs 590-612 (CE tooltip)
- **issue**: Two different discoverability patterns for "explain this result" on the same screen: the Heat Input card uses a 14 px Icons.info_outline in an InkResponse opening a full AlertDialog with formula breakdown; the CE card uses the same-looking 14 px icon but inside a Tooltip(triggerMode: TooltipTriggerMode.tap) showing a 4-line text bubble. Both look identical visually but behave differently - one opens a dialog, the other shows a transient tooltip. A welder who learns "tap the (i) icon to see the formula" on the HI tab will tap it on the CE tab and see only a brief popup, missing the deeper context.
- **why it matters**: Inconsistent affordance for the same visual element breaks the user's mental model; the welder gives up trying to learn the math behind the result and just trusts (or distrusts) the number. The dialog version is also far more useful for the CE - there's actually MORE math to explain on CE (formula, factor weights, P-No mapping) than on HI.
- **suggested fix**: Unify both to the dialog pattern - extract _showFormulaDialog(title, formulaText, variableTable, sourceCitation) and use it from both tabs; bump icon to 18 px in a 44 px hit area for gloved tap.
- **effort**: S
- **round1Ref**: new

--- end block ---

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:888-934 (_ProcessSelector chips)
- **issue**: The five process chips (SMAW / GMAW / FCAW / GTAW / SAW) are bare acronyms with no tooltip, no expandable name, no efficiency hint until selected. A junior welder or apprentice who knows "MIG" but not "GMAW" can't discover the mapping; an experienced TIG welder who knows GTAW=0.60 won't see this until after selecting it and reading the small "Efektywnosc luku" caption way down at 381-387. The chips also lack Tooltip widgets entirely (only a Semantics.label for screen readers).
- **why it matters**: Picking the wrong process is the #1 cause of bad HI calculations - the welder doesn't know FCAW splits into FCAW-G (0.80) and FCAW-S (0.75), and silently picks the default for a wire that should be FCAW-S. Discoverability of the efficiency factor (the whole point of the process picker) is bound to the result card, not to the input.
- **suggested fix**: Wrap each chip in Tooltip(message: '$opt - ${_efficiency[opt]! * 100}% efficiency Â· ${_fullName(opt)}') with long-press; add a chevron-down on each chip opening a help sheet describing each process and its eta value.
- **effort**: S
- **round1Ref**: new (round-1 P1-16 addresses eta values but not chip discoverability)

--- end block ---

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:442-455 (material ChoiceChip wrap, m.key only)
- **issue**: Each chip renders only m.key (e.g. "P91", "S355", "316L") - a fitter unfamiliar with the catalog can't tell that "P91" is Cr-Mo creep-resistant steel for high temp or that "S355" is generic structural. The full m.name only surfaces in the orange info box AFTER selection (lines 469-475). There's no tooltip, no description, no preheat preview before selection. Long-press does nothing.
- **why it matters**: Welder browsing for the right grade taps each chip in sequence to read the name in the box below - slow on gloves, error-prone (mis-tap loses the previous chemistry edit if any was made manually). They give up and type chemistry by hand from a paper PMI report.
- **suggested fix**: Wrap each ChoiceChip in Tooltip(message: '${m.name} Â· P-No ${m.pNumber} Â· CE approx ${ceQuick.toStringAsFixed(2)}') triggered by long-press; consider a small "i" sub-icon on each chip opening the full chemistry preview.
- **effort**: S
- **round1Ref**: P1-24 (overlaps - unifies picker; this adds per-chip tooltip)

--- end block ---

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:389-405 (Copy result button on Heat Input tab) vs 562-670 (CE/Preheat result card with NO copy button)
- **issue**: The Heat Input tab has a prominent "Kopiuj wynik" OutlinedButton.icon under the HI result. The Preheat/CE tab - which produces TWO important numbers (CE value and recommended preheat C) - has zero export affordance. The welder cannot copy the CE or preheat recommendation to a job log, WhatsApp the foreman the suggested preheat, or paste it into the weld journal. Asymmetric discoverability across tabs of the same screen.
- **why it matters**: QC inspector asks "what preheat did you use and why?" - welder has the number on screen but no way to paste it; ends up retyping it (transcription error risk) or screenshotting. The combined CE + preheat + material is the most audit-friendly bundle in the whole calculator and nobody can extract it.
- **suggested fix**: Mirror the "Kopiuj wynik" button under the CE/Preheat card with payload 'CE ${ce.toStringAsFixed(2)} - Preheat ${rec.tempC.toStringAsFixed(0)}C - ${_material?.key ?? manual} - ${rec.note}'; add an AppBar "Share both" icon that concatenates HI + CE + Preheat as a one-line trace.
- **effort**: S
- **round1Ref**: P1-26 (overlaps - universal copy/share lever, this is the concrete instance)

--- end block ---

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:163-209 (Scaffold w/o AppBar trailing actions)
- **issue**: AppBar has zero trailing IconButtons - no help, no reset/clear, no share. On a screen with 13 controllers (volts, amps, travel, C, Mn, Cr, Mo, V, Ni, Cu, thickness, WPS min/max), a welder doing 3-4 back-to-back jobs has no way to clear all fields for a new pipe. They have to manually re-edit each chemistry cell - especially painful after auto-fill from a material, where you now need to clear chemistry AND clear the material chip selection (no visible "unselect" affordance for ChoiceChip either).
- **why it matters**: Mid-shift fitter switches from a 304L weld to a P22 weld; thinks "I'll just pick P22" - but the WPS Min/Max range from 304L lingers because _applyMaterial overwrites them silently while the welder may want to preserve a custom range. There's no discoverable way to reset the screen.
- **suggested fix**: Add three AppBar IconButtons: Icons.refresh (reset all controllers + selected material), Icons.help_outline (open HelpEntry formula+process+CE bundle), Icons.share_outlined (export HI+CE+preheat trace). Tooltips PL/EN.
- **effort**: S
- **round1Ref**: P1-04 + P1-14 + P1-26 (concrete instance - add the three icons together to discoverability win)

--- end block ---

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:74-87 (_applyMaterial silently overwrites WPS Min/Max + chemistry)
- **issue**: When a welder picks a chip, EVERY chemistry field plus WPS Min and Max get overwritten without any "this will replace your custom values" prompt or undo affordance. A welder who manually typed C=0.18 and Mn=1.40 from a PMI report, then taps "S355" out of curiosity to compare, loses their values forever - no Snackbar, no undo, no tooltip warning that selecting will replace manual input. The chips ALSO act as a one-way toggle: tapping the selected chip again does NOT deselect it (ChoiceChip default behavior with onSelected: (_) => _applyMaterial(m) ignores the boolean), so there's no way to revert to "manual chemistry" mode.
- **why it matters**: Real chemistry from PMI != catalog midpoint. Welder wants to use the calculator with their actual heat-cert numbers but the picker takes over. They give up on the auto-fill and type all 8 chemistry cells by hand - wasting the whole material catalog feature.
- **suggested fix**: When fields differ from current _material, show a Snackbar "Chemia z PMI zostala nadpisana wartosciami katalogu - [Cofnij]"; toggle behavior: tap selected chip -> clear _material + don't touch chemistry (returns to "manual" mode). Show a small "i Wpisz wlasne" text-button next to the chips to make the manual-mode path discoverable.
- **effort**: M
- **round1Ref**: new (round-1 #41 P1 noted WPS overwrite as a fidelity issue; discoverability angle = undo + manual-mode signaling)

--- end block ---

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:559-670 (CE/Preheat result card) vs 674-684 (CE reference table)
- **issue**: The reference table (CE <0.35 / 0.35-0.45 / 0.45-0.55 / >0.55 with color chips) shows ranges but the current ce value is NOT marked on the table - no highlighted row, no arrow, no chip showing "you are here". The welder has to mentally compare the 42-pt ce value above with the reference rows below to learn which preheat bucket they fell into. The connection between the dynamic result and the static reference is hidden in spatial proximity only.
- **why it matters**: Junior welder or apprentice reading "CE 0.48" doesn't immediately know which row maps to that value - they hunt for the right bucket; under outdoor sun + 11 pt text, this is slow and error-prone. The reference table's discoverability as a guide is degraded by not connecting it to the live calculation.
- **suggested fix**: In _CeRow, accept a bool isCurrent flag computed from the parent's ce; render the matching row with a left border accent + bold label + small "TY TUTAJ / YOU ARE HERE" chip in the row.
- **effort**: S
- **round1Ref**: new

--- end block ---

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:367-372 (in/out of range message) + 380-386 (efficiency caption)
- **issue**: When HI is out of WPS range, the message says "POZA zakresem WPS - koryguj parametry" but does not suggest WHICH parameter to change. A welder seeing "HI = 3.1 kJ/mm, range 1.0-2.5" doesn't know whether to lower amps, raise travel speed, or lower voltage to reduce HI. The screen has all the inputs needed to give a directional hint ("travel speed too low - try 250 mm/min") but only emits a generic warning.
- **why it matters**: Welder under field pressure tweaks the wrong variable (e.g. drops voltage when raising travel would be cleaner) - wastes attempts to get back into the WPS window.
- **suggested fix**: When out of range, add a one-line directional hint computed from current values: if (hi > wpsMax) "Sprobuj zwiekszyc predkosc spawania do ~${(travel * hi / wpsMax).toStringAsFixed(0)} mm/min" and analogous for under-range (lower travel or raise VÂ·I).
- **effort**: M
- **round1Ref**: new

--- end block ---

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:163-209 (DefaultTabController, no preview of CE/Preheat from Tab 1)
- **issue**: A welder spending time on the Heat Input tab has no idea that picking a material on the Preheat tab will auto-fill the WPS range here, and has no preview of the CE / preheat result from Tab 1 - the two tabs feel like two unrelated calculators that happen to share a screen. No persistent header strip showing "Material: P22 - CE 0.48 - Preheat 175C" visible across both tabs.
- **why it matters**: The screen markets itself as combined HI + Preheat (the title literally says "Heat input + Preheat") but the tabbed layout fragments the result. Welder building a weld traveler that needs BOTH numbers has to flip back and forth, copying each separately. The pin-on-wall printable summary cannot be assembled in-app.
- **suggested fix**: Above the TabBarView add a thin pinned summary chip strip showing the current material chip + live CE + live HI; long-press copies the full trace; tap on each chip switches to the relevant tab.
- **effort**: M
- **round1Ref**: new

--- end block ---


## Iter #17 · lib/screens/tungsten_screen.dart · settings-persistence
- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:24,58
- **issue**: `_amps` TextEditingController has zero persistence — no SharedPreferences read in initState, no write on onChanged/dispose, no AppLifecycleState observer. Every time the welder closes the app, switches to camera/PDF viewer, or the OS kills it for memory, the entered current is wiped.
- **why it matters**: Welder enters 95 A for a stainless root pass, gets pulled to grab the next tube, comes back 10 minutes later — input is gone, has to retype and re-look-up the diameter pick. Worse on shared workshop tablets where the user is the only one paying attention to which value belonged to which joint.
- **suggested fix**: Add `WidgetsBindingObserver`; persist `_amps.text` under `prefs_tungsten_amps` in `onChanged` (debounced) + `didChangeAppLifecycleState(paused)`; restore in `initState()` via `SharedPreferences.getInstance()`.
- **effort**: S
- **round1Ref**: P2-01 (auto-draft form state to SharedPreferences across screens including tungsten)

- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:23-247 (entire class)
- **issue**: No persistence of the resulting pick (selected diameter, electrode type, grind angle, cup size). Once the screen is popped the pick is gone — nothing is saved to the weld journal or a local "last used" cache.
- **why it matters**: Stainless/pharma QA asks "what tungsten was on weld JT-014?". The welder either guesses or re-enters amps to re-derive — and that re-derivation can drift if the underlying `kTungstenSizes` table is later tuned. Without persisted pick + electrode type + timestamp, the audit trail is unreliable.
- **suggested fix**: Add a "Save to journal" FAB or AppBar action that persists `{amps, diaMm, electrodeCode, joint?, ts}` either to journal table or `prefs_tungsten_history` (JSON list capped at 20); pre-fill restored state on next open.
- **effort**: M
- **round1Ref**: P1-21 (add unit/joint-ID/batch/gas/polarity + save-to-log on tungsten)

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:35
- **issue**: Decimal separator handling (`replaceAll(',', '.')`) is hardcoded — there's no persisted user preference for comma vs dot. PL-locale workshops type "9,5", US/UK tablets type "9.5" — both work for input but the displayed value `s.diaMm.toStringAsFixed(1)` always uses dot, ignoring locale.
- **why it matters**: Polish welder writes "1,6" on a paper QR ticket — app shows "1.6" — when the inspector compares, the mismatch (even cosmetic) is friction. Persisting `prefs_decimal_separator` (auto/dot/comma) would let the workshop standardise across all calc screens.
- **suggested fix**: Add a centralised `prefs_decimal_separator` setting (Settings screen) read via a helper; use `NumberFormat` instead of `toStringAsFixed` for `s.diaMm` display.
- **effort**: M
- **round1Ref**: P1-22 (decimal-separator preference centralised across calculators)

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:33-37
- **issue**: `isPl` / `context.language` is the only language signal — no per-screen persistence of "show DC- only" vs "show AC mode" (which doesn't exist yet but is in P2-14 scope), and no persistence of expanded/collapsed state for the long electrode-type list. Every open re-renders the full 4+ row card stack.
- **why it matters**: Field welders typically use one tungsten type (e.g. WC20 for SS) consistently — surfacing all four types every time wastes scroll time on a 6" phone in the rain. A persisted "favourite type" pin would speed selection.
- **suggested fix**: Long-press a type card → persist `prefs_tungsten_favourite_code` → reorder to top + add a pin icon on next open.
- **effort**: S
- **round1Ref**: P2-14 (per-row override + cup/gas/grind-angle for tungsten log — overlap)

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:58
- **issue**: `onChanged: (_) => setState(() {})` rebuilds the whole ListView (10+ children with `withValues(alpha:)` allocations and Container decorations) on every keystroke. There's no debounce and no `addListener` pattern that would also let us persist the value.
- **why it matters**: On low-end Android tablets used in workshops (Lenovo M8, Galaxy Tab A7), keystroke lag is real — and if we later add prefs writing on each keystroke without debounce, we hit disk I/O on every char.
- **suggested fix**: Replace direct setState with `_amps.addListener(_onAmpsChanged)` where `_onAmpsChanged` calls setState + debounced (300ms) `prefs.setString('prefs_tungsten_amps', _amps.text)`.
- **effort**: S
- **round1Ref**: new (perf-adjacent enabler for P2-01)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: high
- **location**: lib/screens/premium_screen.dart:223-241 (AppBar) + 632-674 (_Hero) + entire ListView ordering (252-457)
- **issue**: First-time visitor lands on the Premium screen with ZERO above-the-fold price information. The AppBar shows "PREMIUM" (gradient), the _Hero shows "Fitter Welder Pro+" + a vague tagline ("Pełen arsenał monterski + AI asystent w jednej apce"), then a Try-AI demo tile (~52pt tall), then SECTION_LABEL "Co dostajesz", then SIX feature tiles, BEFORE the user ever sees "19 PLN / 149 PLN". On a 360×780 phone the price cards (line 422-447) sit at ~scroll-position 900-1100 px. A first-time user who opened this from a feature gate ("Try AI Assistant") explicitly to evaluate cost has to scroll past 6 feature blocks they did not ask to read.
- **why it matters**: Workshop fitter taps "Premium" link mid-shift on a phone with one hand in glove; expectation is "how much?" — reality is "scroll, scroll, scroll past marketing". Conversion drops; user back-swipes thinking the screen is broken / paywalled before purchase signal even shown. P2-06 mentioned the feature comparison table but did NOT flag the price-below-the-fold ordering.
- **suggested fix**: Move the _PlanCard row directly under _Hero (or render a compact "19 PLN/mc · 149 PLN/rok (-35%)" pill inside _Hero), demote feature list to BELOW pricing. Mirrors standard SaaS pricing-page pattern.
- **effort**: S
- **round1Ref**: new (extends P2-06 / P3-05 — layout ordering issue, not content)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: high
- **location**: lib/screens/premium_screen.dart:258-351 (Try-AI demo tile) + 255-257 (comment about PremiumGate)
- **issue**: The "DEMO" badge (line 301-316) and sample-prompt copy ("Spróbuj tego: \"Preheat dla P91 grubość 25 mm?\"" line 332-343) promise first-time users a free try of the killer feature. But tapping the tile pushes AiChatScreen unconditionally. The comment at line 255-257 admits "When the gate is enforced the PremiumGate around AiChatScreen will route non-PRO users back here automatically" — meaning today the gate may or may not be enforced. A first-time non-PRO user who taps the demo tile expecting a free demo gets EITHER (a) a working AI chat (no gate enforced → they never convert) OR (b) bounced back to PremiumScreen with no SnackBar explaining "this was a teaser, upgrade to use it" — they assume the tap failed.
- **why it matters**: The screen's strongest conversion lever ("try before you buy") is broken at both ends: either gives the product away or fails silently. A first-time fitter trying the sample prompt at 10am gets either confused (no response, no explanation) or hooked-and-not-charged. Money-on-the-table either way.
- **suggested fix**: Wire a true preview mode: tapping the demo tile opens AiChatScreen with the sample prompt pre-loaded as the first message, allow ONE response, then show an inline upgrade banner ("Spodobało się? Odblokuj nielimitowane pytania → 19 PLN/mc"). Add a debug-mode assert that PremiumGate is enforced before shipping.
- **effort**: M
- **round1Ref**: new (UX contract between marketing copy and gate enforcement)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: high
- **location**: lib/screens/premium_screen.dart:449-456 (legal footnote) — refund/trial/GDPR copy missing
- **issue**: First-time user evaluating 149 PLN/yr commitment sees ONE footnote line ("Płatność: Stripe ... Anuluj w każdej chwili") in 11pt _kTextMut — the lightest color in the palette, the smallest text on screen, sandwiched between the price row and the bottom of the ListView. NO refund policy, NO free trial (P1-27 already flagged), NO "no questions asked" reassurance, NO GDPR/data-handling note, NO link to T&C. A fitter parting with a YEAR of subscription (149 PLN ≈ half-day's wage in some regions) gets less reassurance than a Black Friday t-shirt page. Also: the BLIK mention is PL-only (line 451-452 EN copy omits BLIK), so a PL user reading EN translation thinks BLIK is not supported and bounces.
- **why it matters**: First-time conversion friction. Polish JDG fitter mentally calculates "what if it sucks? 19 PLN is cheap to try, 149 PLN is not" — without trial or refund copy they default to monthly and many never upgrade. Lifetime-value impact direct.
- **suggested fix**: Add three lines above the legal footnote: "7 dni za darmo na planie rocznym" (Stripe trial_period_days=7), "Zwrot 100% w ciągu 14 dni — bez pytań", "Faktura VAT na żądanie". Bump font to 12pt _kTextSec. Include BLIK in the EN copy.
- **effort**: S
- **round1Ref**: P1-27 (extends — adds refund + GDPR concerns first-time users care about)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: med
- **location**: lib/screens/premium_screen.dart:769-849 (_PlanCard) — outer GestureDetector AND inner FilledButton with same onTap
- **issue**: Each plan card is wrapped in GestureDetector(onTap: onTap) (line 769-770) AND contains a FilledButton(onPressed: onTap) (line 833-844) with the SAME callback. The card has no visual feedback (no InkWell, no ripple) when tapped outside the FilledButton — only the button gets a ripple. First-time user taps the price text (22pt w900 — the most tap-attracting element, line 798-803), expects feedback, sees nothing for 100-300ms while _creatingCheckout fires, taps AGAIN on the FilledButton "to make sure" — second checkout session enqueued. The `_creatingCheckout` overlay (line 460-530) only appears AFTER setState flushes; the race window is real.
- **why it matters**: First-time user accidentally double-fires checkout, hitting the same duplicate-Stripe-session class as P1-11 / jobs_screen. The dual tap target pattern itself is unusual — users hesitate ("is the whole card a button, or just the button?") and trust drops.
- **suggested fix**: Either (a) remove the FilledButton and make the whole card a single InkWell with the button-styled bottom region as a visual cue, OR (b) remove the outer GestureDetector and make ONLY the FilledButton clickable. Plus add an in-function guard at the top of _startCheckout: `if (_creatingCheckout) return;`
- **effort**: S
- **round1Ref**: new (duplicate-tap-target + double-fire risk)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: med
- **location**: lib/screens/premium_screen.dart:537-547 (_startCheckout when stripeBackendLive=false)
- **issue**: If BackendConfig.stripeBackendLive is false, the first-time user taps "Wybierz" and gets a SnackBar "Płatności w przygotowaniu — wkrótce uruchomimy Premium." with default duration (4s), no action, no haptic, NO fallback. They scrolled the whole screen, evaluated features, tapped a price, and learn the WHOLE screen is decorative. Nothing visually indicates the screen is currently inactive BEFORE the tap — the "Wybierz" button looks identical to a working CTA. No badge, no countdown, no email-signup capture, no notification opt-in.
- **why it matters**: During launch/migration windows (Codemagic build pre-Stripe-cert, regional rollout, A/B test) a first-time user who would have paid is shown a dead end with zero capture mechanism. By the time the backend goes live the user has uninstalled.
- **suggested fix**: When !stripeBackendLive: render a top-of-screen banner "Premium uruchamia się wkrótce — zostaw email aby wiedzieć pierwszy" with an inline email TextField + "Daj mi znać" button hitting /api/fitter/waitlist. At minimum, change the SnackBar duration to 7s with an action "Powiadom mnie" that toggles a SharedPreferences flag + schedules a local notification once live.
- **effort**: M
- **round1Ref**: new (kill-switch state UX — no launch-window capture)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: med
- **location**: lib/screens/premium_screen.dart:69-80 (initState refreshFromBackend) + 222-534 (build — identity-blind UI)
- **issue**: First-time user (no _awaitingReturn, no pending checkout, no _verifying) lands on the screen and sees NO indication that the screen knows their current premium status. An ACTIVE PRO user landing here (e.g. via the AppBar deep-link from settings) sees the SAME plan picker + the same "Wybierz" CTAs — the screen is identity-blind. PremiumService.instance.refreshFromBackend() is called in initState (line 75) but its result is never reflected in the UI. P3-05 mentioned the active-user case; the first-time-ux mirror is a CONFUSED user (one who already paid on another device but the backend hasn't synced) sees no "Sprawdzam Twój plan…" indicator, no "Mam już Premium — przywróć zakup" action. The classic Apple "Restore purchases" entry point is entirely missing.
- **why it matters**: Cross-device fitter who paid on tablet last week, now opens app on phone for the first time: refreshFromBackend resolves silently, screen still renders as if they have no plan, they tap "Wybierz" thinking they need to repay — second charge. OR: deviceId hashing changed (P0-04 territory), they don't get matched server-side, pay twice. No "I already have premium" escape hatch.
- **suggested fix**: Add a top banner state-machine: (a) loading → "Sprawdzam Twój plan…", (b) active → green "Masz Premium do {date}" + "Zarządzaj" → Stripe portal, (c) free + first-time → show prices, (d) free + recently-canceled → show prices + "Reaktywuj poprzedni plan". Add an explicit "Mam już Premium — przywróć" TextButton at the bottom that re-runs refreshFromBackend with a visible spinner.
- **effort**: M
- **round1Ref**: P3-05 (extends — first-time-ux mirror of the active-user case)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: med
- **location**: lib/screens/premium_screen.dart:355-418 (six _FeatureTile blocks) — jargon density
- **issue**: First-time first-week fitter reads the feature tiles and meets a wall of acronyms with no glossary: WPS, NACE, ASME B31, P91, B7/B7M/B16/B8M, IIW + Pcm, CE, kJ/mm, DN/kąt, "fish-mouth" (line 369-370 — PL copy leaves "fish-mouth" in EN!). Each tile compresses 2-3 standards references into ~25 words. A seasoned welder reads "WPS preheat ASME B31" and nods; a first-time apprentice or jobsite-foreman evaluator (the buyer persona for a 149 PLN/yr decision) reads it as gibberish. There's no "What is WPS?" expandable, no Polish gloss for "fish-mouth" (rybi pyszczek — P2-06 noted), no "powered by 30+ standards" plain-language line.
- **why it matters**: First-time conversion. A foreman who buys for the whole shop reads the tiles to evaluate "is this for my guys?", sees acronym soup, decides the app is for someone else. Lost B2B sales. Apprentices feel the app is "above their level" and abandon.
- **suggested fix**: Wrap each acronym in a tappable Tooltip / popover ("WPS = Welding Procedure Specification — karta procesowa spawania"). Add a one-line plain-language opener to each tile body BEFORE the jargon. Replace "fish-mouth" with "rybi pyszczek (fish-mouth)". Add a small "30+ norm: ASME, EN, AWS — po polsku" badge under the first AI tile.
- **effort**: S
- **round1Ref**: P2-06 (mentions PL/EN mix in feature copy — this broadens to apprentice persona)

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · first-time-ux

- **severity**: low
- **location**: lib/screens/premium_screen.dart:583-587 (launchUrl externalApplication) + 460-530 (overlay covered immediately)
- **issue**: When the user taps "Wybierz" and the checkout URL is created, the app silently launches the external browser via launchUrl(externalApplication). A first-time user mid-screen sees their browser pop up without warning. The overlay underneath says "Otwieram bezpieczną stronę Stripe…" (line 502-504) but it's covered IMMEDIATELY by the browser before the user can read it. The first-time user lands in Stripe's PL page without context about what to do AFTER paying (return to app? click a link? wait for email?).
- **why it matters**: First-time payer trust. Workshop user on a 4G connection with adblockers / VPN / corporate MDM may see the launchUrl land on a blank tab, blocked page, or Stripe-error page; they assume the app crashed and back out. No "what to do next" instruction means more "I paid, where's my Premium?" support tickets.
- **suggested fix**: Before calling launchUrl, show a 2-3s onboarding dialog: "Otworzymy Stripe w przeglądarce. Po płatności wróć do aplikacji — automatycznie aktywujemy Premium. Jeżeli przeglądarka się nie otworzy, spróbuj ponownie." with a "Rozumiem" button. Mirror the mobile-banking handoff convention.
- **effort**: S
- **round1Ref**: new (handoff-to-external UX gap)

--- end block ---

## Iter #19 · lib/screens/ai_chat_screen.dart · cross-screen-consistency

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:15-21 (palette constants)
- **issue**: Yet another file-private palette declaration. Six screens declare the SAME `_kBg = 0xFF0F1117`, `_kCard = 0xFF1A1D26`, `_kBorder = 0xFF2C3354`, but each picks a different `_kAccent` (gold here `0xFFE8C14B`, red on heat_input `0xFFEF5350`, teal on saddle `0xFF26A69A`, blue on elbow `0xFF4A9EFF`, purple on chat `0xFFAB47BC`, etc.). Even worse, this file invents `_kAccentBlue = 0xFF4A9EFF` which is *exactly* the elbow `_kAccent` value — same hex, different name in different files. There is zero single source of truth.
- **why it matters**: A fitter pivots from "ISO notebook" (gold-accented Premium feature) into "AI Asystent" (also gold-accented Premium feature) — same gold, good. But Bolt Torque uses purple `0xFFAB47BC` while public Chat ALSO uses purple `0xFFAB47BC` — two unrelated screens reading "same category". Worse, the user-message bubble on this screen renders blue (`_kAccentBlue 0xFF4A9EFF`) which the welder has just trained their eye to read as "elbow take-out" on the previous screen. Under a tinted welding visor these accents are the only at-a-glance identity each screen has; reusing/conflicting palette codes erodes the trust signal.
- **suggested fix**: Move palette to `lib/theme/app_colors.dart` (per P1-23) and assign roles, not raw hex, e.g. `AppColors.bgPrimary`, `AppColors.accentPremium`, `AppColors.accentUserBubble`. Drop `_kAccentBlue` here in favor of a semantic name.
- **effort**: L
- **round1Ref**: P1-23 (palette extraction sweep — this file is one of the 26)

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:174-189 (AppBar refresh/clear-chat IconButton)
- **issue**: `Icons.refresh` is used as the destructive "clear conversation" action with tooltip "Wyczyść rozmowę". Other screens use `Icons.refresh` for non-destructive *reload* (P2-08 pull-to-refresh, jobs_screen, BOM). The same icon thus has TWO opposite meanings across the app: refresh-from-server vs wipe-local-state. There is also no confirmation dialog despite this destroying a multi-message thread (P1-05 noted this).
- **why it matters**: Welder sees the refresh icon top-right and reaches for it expecting "re-fetch / sync" (the familiar Jobs/BOM gesture). Instead it nukes a 5-minute Q&A thread including the citations they may have been about to screenshot for the foreman. Inconsistent icon semantics + no confirm = irrecoverable data loss in gloves.
- **suggested fix**: Swap to `Icons.delete_sweep_outlined` or `Icons.clear_all` and gate behind `showDialog` confirmation when `_messages.length > 1`.
- **effort**: S
- **round1Ref**: P1-05 (already filed; cross-screen icon-semantics angle is new)

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:108-122 (SnackBar after AI failure) vs lib/screens/chat_screen.dart (no SnackBar duration override)
- **issue**: `Duration(seconds: 4)` SnackBar with "Ponów" action — but P1-08 backlog already mandates 6-8 s floating-coloured SnackBars across the app for outdoor readability, and P1-29 mandates "Spróbuj ponownie" instead of curt "Ponów". This file ships with both the old short duration AND the wrong button label, while sibling chat_screen and jobs_screen have their own variants. Three different SnackBar conventions for the same "retry network call" situation.
- **why it matters**: A welder with sweat-spattered phone under sunlight needs >4 s to even notice the bar, let alone read PL text + reach the "Ponów" button with gloved finger. The retry SnackBar pattern is the single most-used error UI in the app — it MUST be identical wherever it appears or workers learn screen-by-screen.
- **suggested fix**: Extract `showRetrySnackBar(context, message, onRetry)` helper in `lib/widgets/snackbars.dart` with 7 s + floating + `_kCard` background + "Spróbuj ponownie" label; replace all three call sites.
- **effort**: M
- **round1Ref**: P1-08, P1-29

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:54-61, 180-186 (welcome message)
- **issue**: The initial welcome message at line 54-61 is hard-coded PL only (`'Cześć! 👋 Jestem AI asystentem od piping + welding (Claude Haiku 4.5)...'`) — no `context.tr(pl:..., en:...)` wrapper. Yet the clear-chat reset path at 182-186 DOES use `context.tr`. The seeded welcome therefore stays Polish even when the user has the app in English, while every other screen (chat_screen, jobs, premium) localizes initial copy correctly.
- **why it matters**: An EN-locale fitter (UK/offshore) opening AI Asystent for the first time hits a wall of Polish text — feels like the feature is "not for them" and bounces. P0 of the premium upsell journey crippled. Inconsistent with the bilingual-by-default invariant the codebase otherwise honors.
- **suggested fix**: Move welcome string into `context.tr(pl:..., en:...)` and seed inside `build()` (or in a post-frame callback reading `context.language`), matching the reset-path behavior.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:145 (AppBar `backgroundColor: _kCard`)
- **issue**: AppBar background is `_kCard` (lighter card surface) while every other Premium-gated tool screen (heat_input, hydrotest, orbital_tig, saddle_template, iso_notebook) uses the DEFAULT theme AppBar (transparent or `_kBg`). The result is a visible brightness step at the top edge ONLY on this screen when navigating in from the menu — reads as "different app".
- **why it matters**: A fitter rapid-toggling between AI Asystent and Heat Input (very common workflow: ask the bot, then run the calc) sees the AppBar brightness flicker each navigation. Trained eyes treat the inconsistency as a UI glitch and lose trust in the surface.
- **suggested fix**: Drop the explicit `backgroundColor: _kCard` and inherit the global AppBar theme (or, if intentional to "lift" the chat header, propagate the same lift to chat_screen for consistency).
- **effort**: S
- **round1Ref**: P1-23 (palette / theme sweep)

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:209-214 (`_Composer`) vs lib/screens/chat_screen.dart `_Composer`
- **issue**: There are TWO `_Composer` widgets — one here (AI chat), one in `chat_screen.dart` (public chat) — implementing essentially the same affordance (text field + circular send button + maxLines:4 + textInputAction.send) but with different padding, hint styling, border radius (22 here vs whatever chat uses), button colors (gold accent vs purple accent), and enabled-state visuals. Two implementations to keep in sync.
- **why it matters**: When P1-07 bumps the send button to 56×56 dp for glove targets, it must be applied twice with manual reconciliation. Inevitably one drifts. Fitter learns "send" in one screen and the gesture-shape differs in the other (textInputAction behaves differently, send-button position offset).
- **suggested fix**: Extract `lib/widgets/chat_composer.dart` parameterised by `accentColor`, `hint`, `onSend`; use in both screens.
- **effort**: M
- **round1Ref**: P1-07 (consistency cost is new; will be much harder to fix P1-07 across two implementations)

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:153-170 (DEMO badge)
- **issue**: The "DEMO" badge appears only on this screen when `!kAiBackendAvailable`. No equivalent "DEMO" / "OFFLINE" badge appears on other screens that depend on the same backend (e.g. iso_scanner AI suggestions, premium status verification). User has no idea which features are live-AI-backed vs stub when the backend env flag is off.
- **why it matters**: A QA tester or a brigadier evaluating the app on an env where `BackendConfig.aiBackendLive == false` will see "AI Asystent — DEMO" and assume only that screen is stubbed; ISO Scanner's AI auto-fill will then surprise them with hallucinated values without any DEMO indicator. Inconsistent transparency about backend liveness.
- **suggested fix**: Add a shared `kAiBackendAvailable` indicator (small chip in the AppBar) on every screen that calls into the AI route, OR move the DEMO indicator into a global banner shown app-wide while the flag is false.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #20 · lib/screens/chat_screen.dart · permission-ux
- **severity**: high
- **location**: lib/screens/chat_screen.dart:104-109, 378-438
- **issue**: No community-guidelines / code-of-conduct acceptance gate before a user can post or even enter a room. The user taps a room tile and lands straight in `_RoomView` with a live `_Composer`. No "By posting you accept …" / "Czat publiczny — szanuj zasady" affordance, no checkbox, no first-time onboarding sheet enumerating banned-link / banned-word policy that `_send`'s 400 branch alludes to.
- **why it matters**: A fitter joining the public chat may post a phone number, a competitor's price quote, or vent about a brigadier — content that will then get rejected, hidden, or reported, but the user had no prior notice of what the rules are. Reports → hidden message after 3 = silent moderation; without prior consent to the rule set this feels arbitrary. Also a legal/GDPR exposure: a public chat in a paid PL app without published terms is hard to defend.
- **suggested fix**: On first room-enter ever (gated by SharedPreferences key `chat_terms_v1_accepted`), show a modal sheet listing 4-5 rules (no links, no PII, no insults, respect coworkers, reports lead to hiding) with "Akceptuję / Anuluj"; only set the flag and proceed after Akceptuję; expose the same sheet via an "i" icon in the room AppBar.
- **effort**: M
- **round1Ref**: new

- **severity**: high
- **location**: lib/screens/chat_screen.dart:440-479
- **issue**: Report dialog asks only Yes/No — no reason category (spam, link, insult, off-topic, PII, impersonation). Backend `report(messageId)` is fire-and-forget with no reason payload. User who reports has no agency about WHY; moderation team gets zero signal to prioritize. There is also no de-dup feedback: tapping report a second time on the same message shows "Zgłoszono." again with no hint that it was already counted (or whether re-reporting from the same device counts toward the 3).
- **why it matters**: A fitter sees an abusive post, reports it, then later sees it still there because two more distinct devices haven't reported. They tap report again, get the same toast, and assume the system is broken or rigged. Moderators then can't tell whether 30 reports are 30 separate angry users or 1 user spamming. Permission flow without categorization or feedback erodes trust in moderation.
- **suggested fix**: Replace AlertDialog with a `showModalBottomSheet` listing 4-5 reason chips (Spam, Link/reklama, Wulgaryzm, PII / dane osobowe, Inne) + optional text field; pass `reason` to `ChatService.report`; if backend returns "already-reported-by-this-device", show "Juz zgloszono — czekamy na innych" instead of generic "Zgloszono."
- **effort**: M
- **round1Ref**: new

- **severity**: high
- **location**: lib/screens/chat_screen.dart:546-547 (`onLongPress: isMine ? null : onLongPress`)
- **issue**: Long-press on user's own message is explicitly disabled — there is NO affordance to delete, edit, or copy a message the user posted. The fitter has zero permission over their own content after `_send` succeeds.
- **why it matters**: A fitter typo-posts a wrong joint number, a wrong DN, a coworker's name, or a phone number into a public room and has no way to take it back. Backend likely supports `DELETE /api/.../message/{id}` keyed to deviceId (mirrored from how `isMine` is derived); the UI just doesn't expose it. Permission-UX failure: user owns the content but cannot exercise that ownership. Also a GDPR right-to-erasure gap.
- **suggested fix**: When `isMine == true`, long-press should open a sheet with "Skopiuj tekst" + "Usun wiadomosc" (the latter requiring a confirm), wired to a new `ChatService.deleteMessage(id, deviceId)`; if backend doesn't yet support delete, at minimum surface "Skopiuj tekst" so the long-press isn't dead.
- **effort**: M (UI) + L (if backend delete missing)
- **round1Ref**: new

- **severity**: high
- **location**: lib/screens/chat_screen.dart:111-148, lib/services/chat_service.dart:121 (`getNickname`)
- **issue**: A user can enter a room and post without ever having seen the nickname dialog. `getNickname()` returns either a stored value OR a default derived from `deviceId`. The first message posts that auto-generated identity into a public room without consent. The "person_outline" tooltip "Ksywka" / "Nickname" is the only path to change it, and it's an unobtrusive AppBar icon on the room-list screen — easy to miss before tapping into a room.
- **why it matters**: A fitter joins, types a question, and the message appears under an identity he never chose. Permission-UX failure: identity broadcast without explicit user opt-in. Worse: nicknames "Admin" or "Moderator" pass the 32-char filter — impersonation without warning.
- **suggested fix**: On first chat entry (gated by `chat_nickname_set`), force the nickname dialog before allowing room entry; reject (with toast) values matching `^(admin|moderator|mod|fitterwelder|support)$/i`; show the current nickname in the room AppBar subtitle ("Piszesz jako: Krzysiek 304L") so the user sees their broadcast identity at all times; tap subtitle = edit.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:405-415 (banned-link / banned-word rejection)
- **issue**: When the backend returns 400 for a banned link/word, the user is told "Wiadomosc odrzucona (link lub niedozwolone slowo). Sprobuj inaczej." but is not told WHICH token tripped the filter, and the input text is preserved unmodified — the user has to manually hunt for the offending fragment.
- **why it matters**: A fitter writing a message with a brand URL gets a generic rejection, tries again, gets rejected again, gives up. He doesn't know if the trigger was the brand name or the ".com" or some banned phrase. User has no path to consent/comply with the rule because the rule is opaque. After 2-3 rejections the user assumes chat is broken and stops engaging.
- **suggested fix**: Backend should return the matched token in the error body (`{"error":"banned_token","token":"..."}`); UI highlights it in red inline above the composer and offers "Usun to slowo" button that removes only that fragment. If backend won't change, at least split the message into "link wykryto" vs "slowo zabronione" and document the link policy in the rules sheet from finding #1.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:400-404 (429 rate-limit message)
- **issue**: Rate-limit error says "Zwolnij — max 8 wiadomosci na minute." but doesn't tell the user WHEN they can post again (no countdown, no "sprobuj za 23 sek."). The 429 branch also strips the Retry SnackBarAction (correctly, per the comment), so the user has zero permission-restoration feedback — input field stays editable, send button re-enables, but next tap may 429 again.
- **why it matters**: A fitter under pressure on the shop floor mashes send, gets throttled, doesn't know if they need to wait 2 seconds or 60 seconds, and the unhelpful "zwolnij" feels condescending. Permission to participate is revoked with no time signal.
- **suggested fix**: Backend already knows the window — return `Retry-After` header (seconds remaining); UI displays "Sprobuj za 23 sek." in the SnackBar and disables the send button with a countdown ring for that duration. Even without backend change, hardcode "Sprobuj za 60 sek." as a worst-case ceiling.
- **effort**: S (UI countdown) + S (backend Retry-After)
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:104-109 (room enter), 482-528 (room UI)
- **issue**: No "block / mute / hide user" affordance. A fitter who finds another user (identified by `message.nickname` + `deviceId`) consistently abusive can only report individual messages — each one triggers a separate dialog, and the abusive user's NEXT message will still appear in their feed in real time. There is also no local mute (client-side filter by deviceId or nickname) to give the user immediate relief without waiting for moderation.
- **why it matters**: Workshop chat with an antagonistic coworker becomes unusable; report-then-wait-for-3-strangers-to-also-report is the only escape valve. Permission-UX failure: user has no individual-level control to curate their own feed. Compare WhatsApp/Discord: "block user" is a basic permission expectation in 2026.
- **suggested fix**: Add "Wycisz tego uzytkownika" to the message long-press sheet (next to Report); store muted deviceIds in SharedPreferences; filter `_messages` and `_pollDelta` results client-side; add a "Wyciszeni (3)" entry in the room AppBar overflow with unmute.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:65-67, 151-189 (`_ChatComingSoon`)
- **issue**: When `BackendConfig.chatBackendLive == false`, user sees "Czat wkrotce / Backend nie jest jeszcze wlaczony." — but no information about (a) whether their nickname / any other state is being collected, (b) whether opt-in to chat happens later automatically when the flag flips, (c) whether premium status is required for chat. User implicitly grants consent to "chat" as a feature without knowing the data model.
- **why it matters**: A premium subscriber pays expecting community access and sees "coming soon" with no ETA or scope. After flag flips they'll be auto-enrolled with their existing deviceId (no opt-in moment). Permission to participate is granted retroactively, which is the wrong default for a public broadcast feature.
- **suggested fix**: Coming-soon screen should explicitly say "Po wlaczeniu zostaniesz zapytany czy chcesz dolaczyc — nic sie nie wysyla automatycznie." + "Powiadom mnie" button that toggles a SharedPreferences flag and triggers a real opt-in prompt on first live load.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/chat_screen.dart:111-148 (nickname dialog)
- **issue**: Nickname field has no impersonation guard. User can set ksywka to "Admin", "Moderator", "Wsparcie FitterWelder", "0x000000", emoji-only, or a single space (after trim — empty is rejected, but " A " becomes "A" which is allowed). Also no preview of how the name will look in a bubble before saving.
- **why it matters**: An impersonator posing as moderator can socially engineer fitters into clicking dodgy links or revealing pricing data. Single-character / unicode-tricky names hurt readability and reportability. Permission to choose identity should be bounded.
- **suggested fix**: Reject case-insensitive matches of `{admin, moderator, mod, support, wsparcie, fitterwelder, fitter welder pro}`; require >=3 visible characters; strip zero-width chars; show a live preview bubble in the dialog so user sees their identity before committing.
- **effort**: S
- **round1Ref**: P3-13 (related polish thread)

- **severity**: low
- **location**: lib/screens/chat_screen.dart:46-61, 327-349 (no GDPR data-control entry point)
- **issue**: User has no "Usun moje konto czatu / Pobierz moje dane" entry point. The deviceId-keyed message history is a personal-data persistence that under GDPR Art. 17 (right to erasure) and Art. 20 (portability) the user must be able to control. Currently the only chat-related control is the nickname icon in the room-list AppBar.
- **why it matters**: PL/EU paid app exposes legal risk; also fitters who change jobs or sell their phone may want to wipe their chat trail. Permission-UX failure on the data-control axis.
- **suggested fix**: In Settings (not chat_screen itself, but linked from the room-list AppBar overflow): "Usun moja historie czatu" and "Pobierz moje wiadomosci (JSON)"; both call dedicated backend endpoints keyed to deviceId.
- **effort**: M (UI) + L (backend endpoints)
- **round1Ref**: new

--- end block ---

## Iter #21 · lib/screens/home_screen.dart · snackbar-quality

- **severity**: high
- **location**: lib/screens/home_screen.dart:51-68 (`_load`) and 130-132 (`RefreshIndicator(onRefresh: _load)`)
- **issue**: `_load()` awaits `projectDao.listAll()` and then `Future.wait(segmentDao.listForProject)`. Neither call is wrapped in try/catch — any DB failure (locked sqlite, migration mismatch, corrupted file on Android low-storage, SD-card eject) throws into the framework and the `RefreshIndicator` spins forever, no SnackBar fires, and `_loading` is never cleared. The user sees a frozen pull-to-refresh spinner with stale numbers, and on cold start the giant CircularProgressIndicator in the "Recent projects" section is wedged for the rest of the session. This is the same antipattern P0-01 fixed in `weld_journal_screen._load`.
- **why it matters**: Home screen is the first thing a fitter sees every shift. A wedged spinner with no SnackBar telling them what happened means they assume the app is bricked, force-stop it, and lose unsynced state in adjacent screens. Even worse: no Retry CTA.
- **suggested fix**: Wrap `_load` in try/catch; on error set `_loading = false`, keep last-known stats, and surface `ScaffoldMessenger.of(context).showSnackBar` with message `Nie udalo sie wczytac projektow / Could not load projects` and a Retry action that re-invokes `_load`. Mirror P0-01 verbatim.
- **effort**: S
- **round1Ref**: P0-01 (same antipattern — extension to home_screen)

- **severity**: high
- **location**: lib/screens/home_screen.dart:166-235 (all 7 `_MenuCard` `Navigator.push` calls) and 259-264 (FITTER coaching callout `Navigator.push`)
- **issue**: Eight `Navigator.push(...MaterialPageRoute(...))` calls and zero error feedback. If a target screen's `initState` throws (e.g. JobsScreen failing to read backend listings, ChatScreen failing to init device id, IsoScannerScreen failing camera permission grant) the user sees an unrelated red-banner crash screen or — worse — a navigation pop straight back to home with no SnackBar explaining what happened. The user just sees their tap "didn't work" and taps again, sometimes 5-6 times, before giving up.
- **why it matters**: Workshop user on a Pixel 4a with 2 GB free hits SKANER ISO, camera-permission denial pops them back to home silently. They assume the app is broken; they uninstall. The cure (a single SnackBar "Aparat niedostepny — sprawdz uprawnienia") is one line.
- **suggested fix**: Wrap each `Navigator.push(...).then` chain with `.catchError((e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(pl:'Nie udalo sie otworzyc ekranu', en:'Could not open screen')), action: SnackBarAction(label:'Retry', onPressed: ...))); })`. Alternatively, factor a `_safeNavigate(BuildContext, WidgetBuilder)` helper used by all 8 sites.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/home_screen.dart:93-100 (`PopupMenuButton<AppLanguage>.onSelected: context.setLanguage`)
- **issue**: Language change has no SnackBar confirmation. Tap PL→EN and the AppBar pill flips silently — but every label across the rebuild may take a frame, AppBar title doesn't change ("FITTER WELDER PRO" is constant), and there is no `Jezyk: EN aktywny` / `Language: EN active` feedback. If the persist fails (SharedPreferences locked — exact failure mode flagged in Iter #1 P0-01 sister-screen finding) the user sees the UI flip but on next restart it's back to PL with no explanation.
- **why it matters**: A fitter who hands the phone to a Ukrainian/English-speaking colleague to make an entry, switches language, and the colleague restarts the app (or the app is auto-killed in background) and language reverts. No SnackBar = no clue that persistence failed.
- **suggested fix**: After `setLanguage`, fire SnackBar `Jezyk zmieniony / Language changed`; in `setLanguage` itself, on persist failure throw → caller catches → SnackBar `Nie zapisano jezyka / Language not saved` with Retry.
- **effort**: S
- **round1Ref**: new (UX feedback gap)

- **severity**: med
- **location**: lib/screens/home_screen.dart:130-132 (RefreshIndicator) and 244-340 (recent-projects section)
- **issue**: After pull-to-refresh `_load` completes successfully, there is no SnackBar/toast confirming what changed. If the user pulled-to-refresh because they expected a new project to appear (e.g. they just imported via FITTER), and the new project isn't in `_recent.take(3)` because three more-recent projects exist, the user has no signal that the refresh DID succeed but the new project is off-screen. They repeatedly pull-to-refresh.
- **why it matters**: Pull-to-refresh is the workshop user's primary "did the app actually do anything" gesture. Silent success looks like silent failure.
- **suggested fix**: After successful `_load`, if `_recent.length < _totalProjects`, fire short SnackBar `Lacznie X projektow — pokazano 3 najnowsze / Total X projects — showing 3 most recent` with action `Zobacz wszystkie` opening a project list.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/home_screen.dart:259-322 (FITTER coaching callout for first-time users)
- **issue**: The callout is only shown when `_recent.isEmpty`. After the user taps it, navigates to FITTER, comes back, the callout disappears even if they didn't create a project (because nothing changed in `_recent`). But if the navigation to FitterMenuScreen threw (per finding above), there is no SnackBar — the user just sees the callout still sitting there with no signal that their tap didn't take them anywhere. Similarly, when the user DOES create their first project, there is no celebratory SnackBar (`Pierwszy projekt dodany!` / `First project added!`) reinforcing the behaviour — a known retention pattern for trade-app first-run UX.
- **why it matters**: First-run delight loop is broken — the coaching callout is one-way: it tells the user what to do but never acknowledges they did it. Trade apps live or die by the first 60 s.
- **suggested fix**: In the `.then((_) => _load())` callback after returning from FitterMenuScreen, compare `_totalProjects` before vs after; if it incremented, fire SnackBar `Pierwszy projekt dodany — gotowy do CUT LIST / First project added — ready for CUT LIST` with a green checkmark icon.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/home_screen.dart (whole file — no use of `ScaffoldMessenger` at all; verified via `Grep -p 'SnackBar|ScaffoldMessenger' = 0 matches`)
- **issue**: Zero SnackBar usage across the entire HomeScreen. Every error path is silent. This is a structural omission consistent with the snackbar-quality lens: the home screen is the navigational hub but never speaks back to the user about anything (load failures, language persistence, navigation failures, refresh outcome, first-project celebration). Across the codebase 36 SnackBar occurrences exist in 10 sister files — the pattern is clearly known, just absent here.
- **why it matters**: Hub screens with zero feedback create the perception "the app does nothing when I tap" — fatal for retention with workshop users who are skeptical of trade software to begin with.
- **suggested fix**: Adopt a small helper `_snack(BuildContext, {required String pl, required String en, SnackBarAction? action, Color? bg})` colocated in the file (or a shared `lib/utils/snack.dart`) and use it at every failure / confirmation point flagged above. Single PR knocks out findings 1-5.
- **effort**: M
- **round1Ref**: new (structural rollup)

--- end block ---

## Iter #22 · lib/screens/help_screen.dart · help-tooltips

- **severity**: med
- **location**: lib/screens/help_screen.dart:122-130 (search bar suffix close icon)
- **issue**: The `IconButton(Icons.close)` that clears the search query has no `tooltip:` — every other AppBar icon in the file (line 99 info_outline) does. Welder with gloves who long-presses to confirm "is this the clear button or back?" sees nothing.
- **why it matters**: Workshop user reading on a dusty 6" phone often long-presses unfamiliar icons; missing tooltip = uncertain tap = either lost query (irrecoverable since it was not persisted) or no action.
- **suggested fix**: Add `tooltip: context.tr(pl: 'Wyczyść wyszukiwanie', en: 'Clear search')` to the suffix IconButton.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/help_screen.dart:498-505 (`AnimatedRotation` chevron icon in `_EntryRow`)
- **issue**: The expand/collapse chevron `Icons.keyboard_arrow_down` is not wrapped in `Tooltip` and the parent `InkWell` (line 470) has no `Semantics(button: true, label: ...)`. The whole row is tappable but the affordance is purely visual (color shift to accent when expanded). No tooltip, no hint, no a11y label.
- **why it matters**: A welder with mid-grade reading glasses scanning 8-15 entries inside a category card can mis-tap because the chevron is the only signal that the row is interactive — and TalkBack just reads the question text with no "expand/collapse" hint.
- **suggested fix**: Wrap the `AnimatedRotation` in `Tooltip(message: expanded ? 'Zwiń / Collapse' : 'Rozwiń / Expand', child: ...)` and add `Semantics(button: true, expanded: expanded, label: entry.question(lang), child: InkWell(...))` on the row.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/help_screen.dart:286-334 (`_FilterChip` build method)
- **issue**: Filter chips show a count badge next to label ("TIG  14") but no `Tooltip` wrap. Workshop user has no way to know what the number means — is it 14 results, 14 matched terms, 14 sub-categories? Long-press does nothing.
- **why it matters**: Welder skimming the chip strip on a noisy site needs an instant "ah, this category has 14 entries — worth tapping" cue. Without it the badge is decorative.
- **suggested fix**: Wrap the chip Container in `Tooltip(message: context.tr(pl: '$count tematow w "$label"', en: '$count topics in "$label"'), child: ...)`. Pass `BuildContext` through `_FilterChip` (or precompute message in the parent).
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/help_screen.dart:522-543 (tag chips `#purge`, `#tig` etc.)
- **issue**: Inside expanded entries the `Wrap` renders tags as styled containers (`#tig`, `#purge`, `#nace`) that LOOK tappable (colored, rounded, accent text) but have no `GestureDetector`, no `Tooltip`, and no callback. They are pure decoration despite looking like ChoiceChips.
- **why it matters**: Welder reads "API 5L X65" expanded entry, sees `#nace` and `#sour` tags, taps them expecting filtered re-search ("show me everything sour-service related"). Nothing happens — silent dead affordance. Either commit to interactivity (better) or add tooltip "Tag — informacyjny" so the user stops trying.
- **suggested fix**: Either (a) wrap each tag in `InkWell(onTap: () { _searchCtrl.text = tag; _onSearchChanged(tag); })` — turning tags into one-tap re-searches — or (b) add `Tooltip(message: context.tr(pl: 'Slowo kluczowe — uzyj w wyszukiwarce', en: 'Keyword — use in search'))`. Option (a) is the welder-friendly answer.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/help_screen.dart:467-551 (`_EntryRow` expanded body — answer text)
- **issue**: When an entry is expanded the answer body (line 510-519) is plain selectable-less text. There is no long-press copy, no share button, no tooltip indicating the user could copy it. Other screens in the app (BOM, pre-weld) use `ClipboardHelper.copyWithToast` for trace strings — that pattern is absent here.
- **why it matters**: Welder finds the right NACE / PWHT answer, wants to paste it into a WhatsApp message to brygadzista or into a WPS note. Currently must screenshot. Project memory says copy/share helpers are a first-class pattern (`lib/utils/clipboard_helper.dart`).
- **suggested fix**: Add an `IconButton(Icons.copy_all_outlined, tooltip: 'Kopiuj odpowiedz / Copy answer')` in the expanded section's bottom-right (or a small `TextButton.icon`) calling `ClipboardHelper.copyWithToast(context, entry.answer(lang))`. Also wrap the answer in `SelectableText` so on-press copy works natively.
- **effort**: S
- **round1Ref**: overlaps P1-25 (share/copy pattern across calc screens)

- **severity**: med
- **location**: lib/screens/help_screen.dart:585-617 (`_SearchResultCard` category badge)
- **issue**: The colored category badge atop each search-result card ("[ICON] TIG") has no `Tooltip` and no tap target. It looks like a chip but is purely visual. Welder might tap it expecting to filter to that category — nothing happens.
- **why it matters**: When a query returns 25 results spanning 6 categories, a one-tap "narrow to TIG only" gesture on the badge would be a power feature. Currently the badge is decorative; user must scroll back up to the chip strip.
- **suggested fix**: Wrap badge in `InkWell(onTap: () { _toggleCategory(result.category.id); }, child: Tooltip(message: 'Filtruj do "{title}" / Filter to "{title}"'))`.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/help_screen.dart:97-102 (AppBar `Icons.info_outline`)
- **issue**: Tooltip is present but no `Semantics(label: 'About knowledge base', button: true)`. Same a11y gap as the AppBar semantics rollup in BACKLOG (P2-13).
- **why it matters**: Workshop a11y users with TalkBack hear "info outline button" not "About knowledge base button" — tooltip text doesn't always map to screen-reader label automatically on older Android.
- **suggested fix**: Either rely on Material `Tooltip`+`IconButton` auto-mapping (verify on Android 10 with TalkBack) or wrap in explicit `Semantics(button: true, label: ...)`.
- **effort**: S
- **round1Ref**: P2-13 / overlap with a11y semantics rollup

- **severity**: low
- **location**: lib/screens/help_screen.dart:107-148 (search `TextField` decoration)
- **issue**: No `helperText` under the search field explaining "obsluguje synonimy / supports synonyms" — the `_showAbout` dialog reveals this feature but it is buried behind an info icon. New welder doesn't know typing "argon" finds "back-purge" without first tapping About.
- **why it matters**: Discoverability of the synonym engine — the single biggest UX advantage of this Help v2 — is locked behind a dialog. A 1-line `helperText` exposes it inline.
- **suggested fix**: Add `helperText: context.tr(pl: 'Synonimy: argon = purge', en: 'Synonyms: argon = purge')` and `helperStyle: TextStyle(color: _kTextMut, fontSize: 11)` to the InputDecoration. Drops after first query character via `helperText: _query.isEmpty ? '...' : null`.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/help_screen.dart:151-173 (filter chip horizontal scroll)
- **issue**: There is no scroll affordance on the horizontal chip list — no fade edge, no chevron tooltip, no scroll indicator. On a 360-dp phone in PL only the first 4-5 chips fit; user might not know more exist to the right. No `Tooltip` and no visual hint.
- **why it matters**: Welder doesn't scroll horizontally because nothing suggests scrolling is possible — they miss NDT/Safety categories entirely.
- **suggested fix**: Add a 12-dp gradient fade at the right edge via `ShaderMask` OR wrap the `ListView` in a horizontal `Scrollbar(thumbVisibility: true)`. Cheaper: append a trailing `Tooltip(message: 'Przewin poziomo / Scroll horizontally', child: Icon(Icons.chevron_right))` cue.
- **effort**: M
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/help_screen.dart:188-200 (`_EmptyState` for "no search matches")
- **issue**: The "Brak wynikow" empty state has no actionable tooltip / button. It tells the user to try different keywords but doesn't tooltip-explain the synonym engine, doesn't offer a "Wyczysc / Clear" button, and doesn't surface category browsing as a fallback ("nic nie znaleziono dla 'XYZ' — przejrzyj kategorie ponizej").
- **why it matters**: Dead-end state. Welder typed "spawanie aluminium" and the synonym engine didn't catch it — now they are stuck staring at an icon.
- **suggested fix**: Add `TextButton.icon(Icons.tune, label: 'Przegladaj kategorie / Browse categories', tooltip: ..., onPressed: () { _searchCtrl.clear(); setState(() => _query=''); })` under the subtitle. Surface a tooltip on the search bar hint that synonyms exist.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/help_screen.dart:38-77 (`_HelpScreenState` — no recent searches / no favourites / no tooltip explaining persistence)
- **issue**: No "recent searches" tooltip / chip strip. Welder who searched "preheat 4130" yesterday must retype today. No pin-favourite icon on entries either; `_expandedEntries` lives only in `State` and is lost on pop. No tooltip explaining what stays / what doesn't.
- **why it matters**: For workshop use the same 5-6 entries (PWHT for P22, NACE H2S limits, hydrotest holding time) get re-opened daily. A persisted "Ulubione / Favourites" with star icon + tooltip = retention.
- **suggested fix**: Phase 1: add `IconButton(Icons.star_border, tooltip: 'Dodaj do ulubionych / Pin')` in `_EntryRow` expanded section persisting to `SharedPreferences('help_favs')`. Phase 2: pin a "Ulubione" chip at the head of the filter strip pre-filtering to pinned entries.
- **effort**: M
- **round1Ref**: P2-10 (persisted help-dismissed flag — same SharedPreferences pattern)

--- end block ---

## Iter #23 · lib/screens/tutor_screen.dart · asme-iso-fidelity

- **severity**: high
- **location**: lib/screens/tutor_screen.dart:45-50 (`isInScope` substring keyword gate)
- **issue**: The scope filter accepts ANY message containing the substring "spaw"/"weld"/"mont"/"fit"/"assemble" and rejects everything else. A fitter asking standards-critical questions like "WPS dla rury P235GH wg PN-EN 15614", "kąt fazowania 60 stopni dla ISO 9692", "tolerancja B1 wg ISO 13920", "PWHT dla stali 13CrMo4-5", "NDT klasy B wg EN ISO 5817", "kwalifikacja 6G AWS D1.1", "WPQR PED 2014/68/UE" gets BLOCKED with `tutor_out_of_scope` because none contain the magic substrings. Conversely, asking about a "fit-bit smart watch" or "Welding Beach Resort" passes. The whitelist has zero standards/code vocabulary (no WPS, WPQR, PQR, NDT, RT, UT, MT, PT, VT, HAZ, PWHT, GTAW, GMAW, SMAW, FCAW, TIG, MIG, MAG, ISO, ASME, AWS, EN, PN, DIN, B31, D1.1, 5817, 9606, 15614, 9692, 13920, PED, CE).
- **why it matters**: This is the AI tutor for an app whose entire BACKLOG is built around ISO sketch accuracy, AWS/ASME WPS compliance and welder code-stamp competency. The current gate sandbox-rejects the exact ASME/ISO/EN code questions the user needs the tutor for. Fitter pays for PRO, asks "klasa B wg 5817?", gets "tutor only answers welding questions" — uninstalls.
- **suggested fix**: Replace the substring filter with a curated lower-cased token set covering WPS/WPQR/PQR/NDT/HAZ/PWHT/GTAW/GMAW/SMAW/FCAW/TIG/MIG/MAG plus standard codes (`iso`, `asme`, `aws`, `en`, `pn-en`, `din`, `b31`, `d1.1`, `5817`, `9606`, `15614`, `9692`, `13920`, `4063`, `2553`, `ped`), and check word-boundary matches not raw `contains`. Better: drop the local filter entirely and let the backend Claude prompt enforce scope.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #23 · lib/screens/tutor_screen.dart · asme-iso-fidelity

- **severity**: high
- **location**: lib/screens/tutor_screen.dart:69 (`BackendService.getOrSearchAnswer`) + lib/services/backend_service.dart:40-58 (`searchAnswer` returns hard-coded `null`)
- **issue**: The "Tutor" feature is wired to a backend service whose external-search path is a stub returning `null`. Every cache miss (which is every question on a fresh install) lands in the `tutor_no_answer` branch (line 79). The user-facing menu / pricing promises an AI tutor on welding standards, but the only answers ever returned come from a local cache that nothing else in the codebase populates (no `BackendService.addAnswer` call sites outside the cache plumbing itself). For ASME/ISO fidelity this is not a "low-quality answer" issue — it is a "no answer at all" issue.
- **why it matters**: A welder typing "WPQR dla 6G P235GH wg ISO 15614-1?" needs a code-grounded answer; getting `tutor_no_answer` repeatedly on EVERY question makes the tutor functionally dead. PRO subscribers paying 29 zł/mc for AI features will charge-back. Worse: there is no telemetry that records the unanswered questions for backlog mining.
- **suggested fix**: Wire `BackendService.searchAnswer` to the PrzetargAI Railway route (e.g. `/api/fitterwelderpro/tutor`) with a Claude haiku prompt grounded in ASME/ISO/EN/AWS standards excerpts; until then mark the Tutor entry as `Beta / coming soon` in the menu and gate it behind a feature flag so PRO users do not see an empty product. Log every `tutor_no_answer` event with the question to a backend table for prompt-tuning.
- **effort**: L
- **round1Ref**: new

--- end block ---

## Iter #23 · lib/screens/tutor_screen.dart · asme-iso-fidelity

- **severity**: med
- **location**: lib/screens/tutor_screen.dart:69-83 (answer rendered as plain `Text(answer)` at line 180-185)
- **issue**: Even if the backend tutor is hooked up, every tutor reply is rendered with a single `Text(message.text)` widget. ASME/ISO/EN answers MUST cite the clause ("ISO 5817:2014, Table 1, row 1.7 — undercut, quality level B: h <= 0.5 mm but <= 0.05 t") and often include tables (preheat vs CE, NDT extent vs quality level), tolerance ranges, formulae (CE = C + Mn/6 + (Cr+Mo+V)/5 + (Ni+Cu)/15), and sketches. A plain text bubble cannot render a table, cannot mark sources, cannot link to the relevant section of EN ISO 5817 / ASME B31.3 / AWS D1.1, cannot show formula superscripts. Worse, there is no "source: standard X, clause Y" footer — a fitter relying on the answer to stamp a weld has zero audit trail for a third-party inspector.
- **why it matters**: Workshop and inspection-room realities — an unsourced answer is unusable for a code-job, and a fitter who blindly trusts it risks failed RT, scrapped joint, contractual penalty. EN ISO 17637 inspectors will not accept "the app said so".
- **suggested fix**: Render assistant messages as Markdown via `flutter_markdown` (already a small dep, and prefab_engine already uses md elsewhere — check pubspec), require the backend prompt to return JSON `{answer, citations: [{standard, clause}], formulas: []}` and render citations as a chip row below each answer with a "Skopiuj cytat" action so fitter can paste the standard reference into a WPS or PQR document.
- **effort**: L
- **round1Ref**: new

--- end block ---

## Iter #23 · lib/screens/tutor_screen.dart · asme-iso-fidelity

- **severity**: med
- **location**: lib/screens/tutor_screen.dart:45 (`final lower = text.toLowerCase()`) + Polish-locale fitter typing diacritics
- **issue**: The scope filter `lower.contains('spaw')` works for "spawanie" but the same `toLowerCase` does NOT normalise Polish diacritics: a user typing "Spawanie łukiem krytym" lower-cases to "spawanie łukiem krytym" — fine — but inquiries phrased without the root, e.g. "Łuk pod topnikiem dla SAW", "Złącze BW dla PED", "Złącze doczołowe wg ISO 9692-1", get bounced because none contain `spaw|weld|mont|fit|assemble`. The same problem hits English: "WPS for stainless butt joint" (no "weld"/"fit") is rejected. Diacritic-insensitive normalisation is also missing — typing "Łączenie spawów" or stripped "laczenie spawow" both should pass; with the current filter the stripped form (auto-correct keyboard, SwiftKey ASCII fallback) does because of "spaw", but "ŁĄCZENIE SPAWÓW" upper-case Unicode could trigger Dart Unicode lower-case edge cases on older Android WebViews.
- **why it matters**: Polish welders type in mixed-case with diacritics or stripped ASCII depending on keyboard skin. The gate accepts/rejects inconsistently based on whether the keyword root happens to appear, not based on intent.
- **suggested fix**: Normalise input via `text.toLowerCase().replaceAll(RegExp(r"[ąćęłńóśźż]"), "_")` (or use `package:diacritic` `removeDiacritics`) before keyword match; expand keyword list per finding #1 of this iter; ultimately move scope-classification server-side where a small Claude haiku call can judge intent properly.
- **effort**: S
- **round1Ref**: new (related to iter #23 finding #1)

--- end block ---

## Iter #23 · lib/screens/tutor_screen.dart · asme-iso-fidelity

- **severity**: med
- **location**: lib/screens/tutor_screen.dart:69-112 (`getOrSearchAnswer` future + SnackBar retry) — no abort/timeout
- **issue**: The future has no timeout. On a workshop 3G cell or hostile site Wi-Fi the request can hang for 30-120s; meanwhile the "searching..." bubble stays parked at `searchIndex` and the fitter assumes the tutor is thinking deeply about their ASME B31.3 question. There is no per-message id either: a user firing question A, getting bored, then sending question B will, when A late response arrives, see A answer rendered as the response to B — they may apply ISO 5817 quality-class-B undercut limits (answer A) to their question about preheat (question B), with potentially safety-relevant consequences for the joint.
- **why it matters**: Out-of-order tutor responses about code/standard limits are not a UX nit — a fitter who reads the wrong answer for the wrong question may apply the wrong preheat / wrong undercut tolerance and the joint fails inspection or, worse, fails in service.
- **suggested fix**: Wrap `getOrSearchAnswer(text)` with `.timeout(Duration(seconds: 20))` and replace the "searching" bubble with a "Timeout — Ponów" affordance; tag each pending bubble with a monotonically-increasing `_requestSeq` and discard responses whose seq != the latest, so late arrivals never land on the wrong question.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #24 · lib/screens/register_screen.dart · weld-traceability

- **severity**: high
- **location**: lib/screens/register_screen.dart:30-64 (+ auth_service.dart:13-42)
- **issue**: Registration captures only email + password — no welder stamp / WPQR no. / certificate ID / personnel ID. Every downstream weld journal entry (`weld_journal_screen.dart`) is then signed only by an anonymous email and cannot be linked to a qualified welder per ISO 3834 / EN ISO 9606 / ASME IX QW-301.
- **why it matters**: Weld-traceability requires a unique welder identifier on every joint. Without capturing the welder stamp + WPQR + expiry at onboarding, NDT/QC audit cannot answer "who welded JT-014, and was their qualification valid on that date?" — full traceability chain breaks at the identity root.
- **suggested fix**: Add required `welderStamp` (TextField, uppercase, regex `[A-Z0-9-]{2,12}`) + optional `wpqrNo`, `wpqrExpiry` (date), `certBody` (TÜV/UDT/LRS) fields; persist on user record; surface stamp in weld journal author column.
- **effort**: M
- **round1Ref**: new

- **severity**: high
- **location**: lib/services/auth_service.dart:13-16
- **issue**: User store is an in-memory `Map<String,String>` — all registered welders + their hashed credentials vanish on app restart. The weld journal author binding has zero persistence, so historical weld logs reference identities that no longer exist in the auth store.
- **why it matters**: A welder signs 40 fit-up + root pass entries on Monday; phone reboots Monday night; Tuesday morning the account is gone but the weld_journal rows still claim authorship — orphaned trace records, useless for QC audit and falsifiable.
- **suggested fix**: Persist users via SharedPreferences/sqflite (`users` table: email, hash, stamp, wpqrNo, wpqrExpiry, certBody, createdAt) and FK the weld_journal.author column on stamp instead of email.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/register_screen.dart:47-63
- **issue**: `AuthService.register(...).then(...)` has no `.catchError` / try-catch; future rejection silently leaves `_errorMessage = null` and no SnackBar fires. The welder sees no feedback yet no navigation pop — they may assume registration succeeded and sign joints under an account that does not actually exist.
- **why it matters**: Silent registration failure produces "ghost welder" entries: the local UI binds a session to a stamp the backend never recorded. Audit later cannot reconcile the joint signer to any registered welder.
- **suggested fix**: Wrap in try/catch (or `.catchError`), set `_errorMessage` to a localized "Rejestracja nie powiodła się — spróbuj ponownie", and disable the button + show a spinner while in-flight.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/register_screen.dart:35-40
- **issue**: Empty-field branch reuses the `register_password_mismatch` translation key — message reads "Hasła nie pasują" while the actual error is "field empty". Welder cannot tell what to fix and may type random characters to satisfy a non-existent rule.
- **why it matters**: Onboarding friction blocks legitimate welders from creating the traceable identity needed for weld logs; wrong message is a known cause of weak/abandoned credentials, which then break traceability when a substitute "shared" login is used on shop tablets.
- **suggested fix**: Add `register_field_empty` key and branch on the specific failure (empty vs mismatch); ideally per-field `errorText` on the offending TextField.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/register_screen.dart:85-92
- **issue**: No email format validation, no max length, no `inputFormatters` stripping CR/LF — a welder typing "jankowalski" (no @) registers successfully, and that string becomes the immutable author on every future weld log. No way to reach the welder via the stamped email, and no de-dup vs the real email later.
- **why it matters**: Email is the only post-hoc audit handle to the welder ("contact JT-014 about porosity"); accepting non-email garbage breaks the traceability outreach chain and lets one physical welder accidentally maintain multiple author identities for the same joints.
- **suggested fix**: Add regex validator `^[\w.+-]+@[\w-]+\.[\w.-]+$`, `maxLength: 80`, `FilteringTextInputFormatter.deny(RegExp(r'[\s\r\n]'))`, `keyboardType: emailAddress` (already set), inline `errorText`.
- **effort**: S
- **round1Ref**: new (overlaps P1-13 sanitise pattern)

- **severity**: med
- **location**: lib/screens/register_screen.dart:94-101 (+ auth_service.dart:19-21)
- **issue**: No minimum password complexity. SHA-256 over a 3-char password is brute-forceable in milliseconds; impersonating a welder's stamped account becomes trivial. Also no current-rotation policy or 2FA hook reserved.
- **why it matters**: Audit value of "welder JT-014 signed weld 7" collapses if any colleague can guess JT-014's password and submit forged joints; the traceability chain is only as strong as the credential gating it.
- **suggested fix**: Enforce ≥10 chars + at least 1 digit + 1 letter; replace SHA-256 with bcrypt/scrypt/argon2id (e.g. `package:bcrypt`); show live strength meter; document policy in onboarding copy.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/register_screen.dart:73-130
- **issue**: No regulatory / qualification consent capture — missing GDPR/RODO checkbox, no acknowledgement that "ja, niżej podpisany welder declare my WPQR is valid and accept that my stamp will sign weld journal entries used in QC/NDT records". ISO 3834-2 §13 personnel records and PED 2014/68/EU Annex I 3.1.2 require a documented qualified-personnel link.
- **why it matters**: Without a documented welder consent + qualification declaration at account creation, the audit chain has no legal "first signature" tying the digital identity to the physical welder; the weld journal exports become contestable.
- **suggested fix**: Add two `CheckboxListTile`s — RODO consent (link to policy URL) + qualification declaration with WPQR number text-input that gates the Register button; persist with consent timestamp.
- **effort**: M
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/register_screen.dart:32 (`email.trim()` only)
- **issue**: Email is trimmed but not `.toLowerCase()`-normalized before passing to `AuthService.register`. AuthService internally lowercases, but the *displayed* author in any future welder-card UI keeps the original casing — "Jan.Kowalski@x.pl" vs "jan.kowalski@x.pl" rendered as two different welders in journal exports.
- **why it matters**: Mixed casing in trace exports makes column sorts and de-dup queries unreliable; a foreman filtering "jan.kowalski" misses joints authored by "Jan.Kowalski".
- **suggested fix**: Lowercase + trim at the UI boundary; also normalize Unicode NFC and strip zero-width chars.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/register_screen.dart:112-115
- **issue**: No loading state on the Register button — fast double-tap on slow phones could call `_register()` twice, hitting the AuthService twice. With future backend persistence the second call may create a duplicate or race-condition the stamp uniqueness check.
- **why it matters**: Duplicate-welder rows mean the same physical fitter signs joints under two emails for the same stamp — destroys the 1-to-1 identity link needed for trace.
- **suggested fix**: Track `_busy` bool; disable button + show `CircularProgressIndicator.adaptive` while register future is in-flight.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #25 · lib/services/prefab_engine.dart · cut-list-clarity

- **severity**: high
- **location**: lib/services/prefab_engine.dart:59-60 (DimRef.centreToFace branch)
- **issue**: `centreToFace` subtracts `cteBoth = leftCte + rightCte` instead of just the centre side's CTE. The docstring rule (lines 30-33) says "face → 0 (no body subtracted)" but the code subtracts whatever CTE the face-side caller happens to pass. Caller in iso_notebook_screen.dart:2930-2938 always passes both `leftCteMm` and `rightCteMm` computed from elbows at BOTH endpoints regardless of `ref`, so an elbow sitting at the face-side endpoint silently shaves its CTE off the CUT. Tests pass only because they manually zero the face-side CTE.
- **why it matters**: A fitter dimensioning oś-czoło on an elbow-to-flange spool gets a CUT that is ~55-76 mm too short — pipe arrives undersized at fit-up, has to be scrapped or extended with a butt weld the WPS doesn't allow. The bug is silent (no warning, no asymmetry hint) and the docstring on lines 28-37 lulls the reviewer into thinking it's correct.
- **suggested fix**: For `centreToFace`, decide which side is the centre via the existing per-side physical-or-not flag (or take only one CTE param), then `return isoValueMm - centreSideCte - midPhysicalSumMm;` — and add a test like `centreToFace + leftCte=55 + rightCte=55 → 445` (not 390) to lock in the spec.
- **effort**: M
- **round1Ref**: new (round-1 P0-03 / P1-30 cover numeric input sanity but not the per-DimRef contribution math; iter #48 offline-resilience lens explicitly skipped semantic correctness)

- **severity**: high
- **location**: lib/services/prefab_engine.dart:56-67 (whole switch)
- **issue**: No guard against a negative or absurdly small CUT result. If `isoValueMm < cteBoth + phyBoth + midPhysicalSumMm` the function returns a negative number; the only downstream filter (iso_notebook_screen.dart:2947) is `v.isFinite`, which a negative double passes. A negative segment silently *reduces* the grand total.
- **why it matters**: A welder mis-typing 100 instead of 1000 on a 76-mm elbow-elbow segment gets `CUT = -10 mm` quietly folded into the total — the spool total looks plausible but cumulative pipe stock is short. BACKLOG P0-03 calls for an "X segments excluded" chip at the screen level; the engine should also signal the condition (return `double.nan` or a sentinel + flag) so the caller can render the warning.
- **suggested fix**: After the switch, `final cut = ...; return cut <= 0 ? double.nan : cut;` (or expose a `(cut, warning)` record); add a unit test `cutLengthMm(iso=100, ref:CTC, leftCte=55, rightCte=55) → isNaN`.
- **effort**: S
- **round1Ref**: P0-03 (P0-03 patches the screen aggregator; this finding pushes the same guard one layer down so other future callers can't bypass it)

- **severity**: med
- **location**: lib/services/prefab_engine.dart:75-80 (`needsDimRefPicker`)
- **issue**: Picker only fires when at least one side is physical. But two purely-axial endpoints can still legitimately be dimensioned face-to-face on real ISOs (e.g. flange-to-flange face dim is industry-standard, NOT centre-to-centre). The function locks axial-axial to CTC silently per the 2026-05-31 directive — but the directive itself says "designers always dimension centre-to-centre" which is true for ELBOWS, not for flanges/valves which also fall under "axial". `leftIsPhysical` is the caller's call, and at the call site there's no distinction between "elbow centre" vs "valve face" — so a flange-to-flange dim gets silently treated as CTC, subtracting two phantom valve-CTE values.
- **why it matters**: A fitter on a flanged spool sees the CUT auto-computed with no picker — and no explanation of WHY no picker — and trusts a number that may be 50-150 mm off per valve. There is no audit trail saying "we assumed CTC". Workshop impact: cut pipe is too short between two flanges, gasket gap wrong, leak path.
- **suggested fix**: Either (a) widen the signature to `leftIsAxialAlwaysCtc: bool` (true only for elbows/tees/reducers) and force picker for axial-but-not-always-CTC endpoints like flanges/valves, OR (b) at minimum surface a one-time "assumed centre-to-centre" hint chip on the segment.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/services/prefab_engine.dart:45, 62 (`midPhysicalSumMm` parameter)
- **issue**: No validation that `midPhysicalSumMm >= 0`. A negative value (caller bug, or a future deduct-row that pasted a Unicode minus surviving P1-03 normalisation) would INFLATE the CUT instead of shrinking it. Engine is direction-agnostic by design but blind to sign.
- **why it matters**: A typo or stray `-` on a mid-component takeout silently lengthens the pipe — fitter cuts long, has to re-saw, scraps the offcut. Hard to spot in a 30-row cut list because totals still "look reasonable".
- **suggested fix**: `assert(midPhysicalSumMm >= 0, 'midPhysicalSumMm must be non-negative');` and at runtime `final mid = midPhysicalSumMm < 0 ? 0 : midPhysicalSumMm;` with a `debugPrint` so QA notices.
- **effort**: S
- **round1Ref**: P1-03 (normalisation), P0-03 (range guard at screen level)

- **severity**: low
- **location**: lib/services/prefab_engine.dart:47 (NaN propagation)
- **issue**: `if (isoValueMm.isNaN) return double.nan;` is the only sentinel — `double.infinity` (which `parseIsoExpression` could produce on a `1e9999`-style overflow) is NOT guarded, and would propagate through the switch as ±infinity into the cut-list total, which is then filtered by `v.isFinite` upstream — silently dropping a segment without telling the welder.
- **why it matters**: A drawing pasted "1.5e3" (legitimate scientific notation some CAD exporters use) parses fine, but a malformed "1e500" produces infinity, gets silently dropped, and the welder is missing a segment from the spool. Fewer pipes than the drawing requires = fit-up stops.
- **suggested fix**: `if (!isoValueMm.isFinite) return double.nan;` (covers both NaN and infinity in one line).
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/services/prefab_engine.dart:38-68 (no rounding/precision contract)
- **issue**: Engine returns a raw `double` with no documentation about how the result should be rounded for the welder. Mixed int (CTE, physical) + double (iso, deducts via `parseIsoExpression`) arithmetic can produce results like `444.99999999999994` for a nominal 445 mm CUT. iso_notebook_screen formats this elsewhere but the engine docstring is silent — a future caller may pipe the raw double straight to a PDF cut list.
- **why it matters**: A fitter reading `444.9999 mm` on a cut list can't tell whether it's a rounding artefact or a real sub-mm spec; either he wastes time chasing 0.0001 mm or he ignores it and misses a real 1-mm deviation later. Clarity demands the engine state its precision contract.
- **suggested fix**: Add doc line "Caller should round to nearest mm (or 0.1 mm for sanitary/hygienic spools) before display." and optionally expose `cutLengthMmRounded({...})` returning `int` for the common case.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #26 · lib/services/iso_pdf_export.dart · glove-48dp

- **severity**: med
- **location**: lib/services/iso_pdf_export.dart:97-105 (CUT LIST body rows) + 126 (BOM `cellStyle: TextStyle(fontSize: 10)`)
- **issue**: Cut list lines render at `fontSize: 9` (line 102) and BOM table cells at `fontSize: 10`. The PDF's whole purpose is the welder/fitter prints it, pins it next to the saw and reads the numbers through safety glasses + gloved fingertip running along the line. The `pdf` package renders at 72 dpi nominal — 9 pt prints at ~3.2 mm cap-height, below the 4 mm minimum legibility for workshop documents (DIN 6774 informational annex / ISO 7200 readability guidance). A welder with reading glasses pushed up under a visor cannot reliably scan "1500.0" vs "1300.0" on a glance. The header at 16 pt and section bands at 11 pt are fine; the actual DATA rows people use are the smallest type on the page — exactly backwards for shop-floor reading.
- **why it matters**: The PDF's only job (carry to saw, read while cutting) is degraded by undersized body type. Mis-reads cause wrong cuts and wasted stock — the document fails its core glove-on use case.
- **suggested fix**: Bump cut-list rows to `fontSize: 11` (Courier), BOM cells to `fontSize: 12`, and `cellHeight: 16` → `cellHeight: 20` so the larger font has room without clipping descenders.
- **effort**: S
- **round1Ref**: P1-08 (font/legibility on shop floor — extended to printed-doc readability)

- **severity**: med
- **location**: lib/services/iso_pdf_export.dart:153-158 (size/exists check raises StateError with raw `dir.path` interpolated)
- **issue**: When `file.length() < 100` the service throws `'PDF zapisany niepoprawnie — sprawdz miejsce na dysku (${dir.path}).'` — Polish-only message, `sprawdz` unaccented (should be `sprawdź`), and a raw temp directory path interpolated. On Android `dir.path` is something like `/data/user/0/com.fitterwelderpro/cache` — meaningless to a fitter and >40 chars long, so the SnackBar truncates to `"PDF zapisany niepoprawnie — sprawd…"` on a 360 dp phone. The user has no actionable next step (delete what? from where?) and the truncation hides whatever hint the path was meant to give.
- **why it matters**: Glove-48dp lens cares about error legibility under field pressure. Fitter is mid-export to brygadzista, error fires, the path-padded string truncates — they don't know whether storage is full, permission was denied, or the app crashed. They retry blindly or give up on PDF feature.
- **suggested fix**: Drop the path interpolation. Use a stable PL+EN message "PDF zapisany niepoprawnie — sprawdź miejsce na dysku urządzenia." Throw a typed `IsoPdfExportException` with an enum cause (`emptyFile`, `noSpace`, `noPermission`) so the caller localises and can offer an "Otwórz Pliki" action (mirrors Iter #6 saddle fix).
- **effort**: S
- **round1Ref**: P0-01 (typed-error contract), Iter #6 (sister antipattern in saddle export)

- **severity**: med
- **location**: lib/services/iso_pdf_export.dart:241-246 (`_safeFileName`)
- **issue**: Two bugs: (a) `.substring(0, s.length.clamp(0, 40))` clamps against the ORIGINAL string's length, not the post-replace chain's length. For ASCII this works by coincidence; for CJK / RTL paste (subcontractor names) the post-replace string can differ in code-unit length and `substring` throws `RangeError`. (b) The chain runs `replaceAll(r'_+','_')` BEFORE substring, so substring may cut mid-underscore-run and re-introduce a trailing `_`. Also strips all Polish diacritics: `"Wymiana króćców P-12 Płock"` becomes `"Wymiana_kr_c_w_P-12_P_ock"` — barely identifiable in the share-sheet's "recent files" list.
- **why it matters**: Fitter types the project name with gloves on (autocorrect mis-fires, paste from email with Polish quotes, etc.). The generated filename is what they see in the share sheet's recent-files picker when forwarding to the brygadzista on WhatsApp. Ugly stripped names mean scrolling through 5 lookalike "ISO________" PDFs to identify the right job — wasted seconds with a glove pulling down the phone notification shade by accident.
- **suggested fix**: After the regex chain, compute `out.substring(0, out.length.clamp(0, 40))`. Trim leading/trailing `_`. Better: keep diacritics with Unicode classes `[^\p{L}\p{N}_-]` (Dart RegExp supports `unicode: true`) so "Płock" stays "Płock".
- **effort**: S
- **round1Ref**: new (filename clarity — share-sheet UX with gloved scrolling)

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:88-108 (CUT LIST body — flat `pw.Column` of `pw.Text`s with no row affordance)
- **issue**: The cut-list block renders each pre-formatted string as its own `pw.Text` in a single Container. No row-level zebra striping, no separator rule, no leading row-number badge. For a 20-segment cut list (multi-tee fab) the print is a wall of monospace text with no visual anchor — a welder scanning down for "row 12" must count from row 1. With gloves, holding the printout against a windy yard, that is precisely when alternating background bands or numbered chips matter most. Comment at 100 mentions `Font.courier()` for column alignment, but alignment alone doesn't help row-find under stress.
- **why it matters**: PDF is meant to be read off-screen, on paper, under poor light, with gloves. DIN/ISO workshop drawings zebra-stripe tables for exactly this reason.
- **suggested fix**: Wrap each line in a `pw.Container(decoration: pw.BoxDecoration(color: i.isOdd ? PdfColor.fromHex('#E9ECF3') : null))` with a leading 24 pt row-number box. Use `cutListLines.asMap().entries.map(...)` to get the index.
- **effort**: S
- **round1Ref**: P1-08 (legibility on shop floor — extended to printed-doc table treatment)

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:43-50 (font fallback — all four weights point to the same Regular file)
- **issue**: `pw.ThemeData.withFont(base, bold, italic, boldItalic)` is fed `Roboto-Regular.ttf` for ALL FOUR weights. This means every `pw.FontWeight.bold` in the layout (the orange CUT LIST / BOM band at line 230, the ISOMETRIC title at 184, the table headers at 121, the page-number `str. $page / $pages`) actually renders at REGULAR weight. The visual hierarchy the code carefully describes collapses on the printed page — the band shows orange background + dark text but the text weight matches the 9 pt body under it. Glove-reading on a printout depends on weight contrast to find sections.
- **why it matters**: Brygadzista glancing at the printout to find the BOM section flips pages or hunts column-by-column instead of letting bold weight pop. Minor on small lists; real annoyance on 3-page prints in a binder.
- **suggested fix**: Bundle `Roboto-Bold.ttf` (one extra TTF, ~170 KB; declare in `pubspec.yaml` assets) and wire `bold: pw.Font.ttf(boldBytes)`. Italic / boldItalic can stay on Regular (italic is unused in the layout).
- **effort**: S
- **round1Ref**: new (asset bundling so the printed deliverable's typographic hierarchy actually renders)

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:62 (`margin: const pw.EdgeInsets.all(28)` — 28 pt ≈ 9.9 mm all-round)
- **issue**: Page margin is 28 pt all-round. Welders routinely three-hole-punch the printout into a project binder, and standard DIN A4 binders bite 8-10 mm in from the left edge. With only ~10 mm left margin, the leftmost characters of the cut list (Courier, 9 pt) get punched THROUGH — losing the segment number prefix or the first deduct value. Comment at line 16 explicitly calls out "the document monter prints / shares with brygadzista" — the binder use case is the intended workflow.
- **why it matters**: Binder-punched cut lists with missing first character = mis-read jobs. DIN 6771 specifies 20 mm left, 10 mm other margins precisely for hole-punch tolerance — and the workshop expects it.
- **suggested fix**: Use `pw.EdgeInsets.only(left: 57, top: 28, right: 28, bottom: 28)` (57 pt ≈ 20 mm). No header/footer geometry needs to change. Optionally expose `_binderMarginLeft = 57.0` as a const.
- **effort**: S
- **round1Ref**: new (physical binder/punch tolerance — workshop workflow detail)

--- end block ---

## Iter #27 · lib/services/premium_service.dart · outdoor-visibility
- **severity**: low
- **location**: lib/services/premium_service.dart:67-78 (`PremiumStatus.label`)
- **issue**: Plan labels mix case styles — `FREE` (all caps) vs `PRO · monthly` (mixed case lowercase tail). The lowercase `monthly`/`yearly`/`lifetime` are 6-8 chars at small badge sizes, with the U+00B7 middle-dot separator that ends up nearly invisible at <14pt on a sweaty/visor-tinted screen.
- **why it matters**: Welder glancing at a Premium badge through a tinted PAPR visor sees "PRO" + an unreadable smear; can't tell whether their subscription is monthly (cancellable now) or yearly (committed). The middle dot also vanishes outdoors so "PRO monthly" reads as one blob.
- **suggested fix**: Switch tail to ALL-CAPS ("PRO · MONTHLY", "PRO · YEARLY", "PRO · LIFETIME"); replace U+00B7 with " — " or "/" for outdoor legibility; ensure consumers render with min 13pt + bold.
- **effort**: S
- **round1Ref**: new (P1-08 covers body font sizing globally but does not address mixed-case PRO labels)

- **severity**: low
- **location**: lib/services/premium_service.dart:225-289 (`refreshFromBackend`)
- **issue**: On network error (catch block at L283-288) the method silently returns `_current` — no status change broadcast, no signal to UI. The `lastVerifiedAt` field exists specifically so the UI can show a "stale data" hint outdoors, but on failure it is NOT updated and no error indicator surfaces.
- **why it matters**: Fitter on a 4G dead-spot opens Premium screen, sees PRO badge, no visual cue that the verification just failed. In direct sunlight a missing "refresh failed" toast is invisible-by-default; field workers need a positive signal (yellow stale-data chip) that this status hasn't been confirmed in N minutes.
- **suggested fix**: On catch, broadcast `_current.copyWith(/* keep lastVerifiedAt */)` together with a new `lastRefreshError` field (DateTime + reason) so widgets can render an amber "ostatnia weryfikacja: 3 min temu" pill — high-contrast outdoor cue.
- **why it matters extension**: surfaces silent-failure state for the outdoor-mode toggle proposed in P2-07.
- **effort**: M
- **round1Ref**: new (relates to P0-04 grace logic but on the visibility/UX side, not the protection side)

- **severity**: low
- **location**: lib/services/premium_service.dart:222 (`_kDowngradeGrace = 2 minutes`)
- **issue**: The 2-minute downgrade grace is invisible to the UI. There is no exposed getter (`pendingDowngradeStartedAt`, `gracePeriodRemaining`) so the Premium screen cannot render a "weryfikujemy subskrypcję..." amber banner during the suspenseful interval.
- **why it matters**: Welder mid-job glances at Premium screen during the 2-minute window — UI shows full PRO badge, no high-visibility "verifying" indicator. If grace elapses and PRO drops, the change appears instantaneous and confusing; an outdoor-readable yellow/amber "weryfikacja w toku" banner during the grace window would prepare the user for a potential downgrade and prompt them to check connectivity.
- **suggested fix**: Expose `bool get isPendingDowngrade => _pendingDowngradeAt != null;` and `Duration? get downgradeGraceRemaining`. UI in Premium screen can render an amber high-contrast strip.
- **effort**: S
- **round1Ref**: P0-04 (downgrade grace was added but no outdoor-visible UI hook)

- **severity**: low
- **location**: lib/services/premium_service.dart:39-91 (`PremiumStatus`)
- **issue**: No high-contrast / color-blind-safe colour or icon hint exposed on `PremiumStatus`. Consumers must derive a colour from `plan` enum which leads to inconsistent (often low-contrast purple/gold) badges across screens.
- **why it matters**: Fitter+welder population skews male 40+ with elevated red-green colour-blindness rates; outdoor lighting washes out gold/purple gradients used for PRO badges. A canonical high-contrast accent (`Color get outdoorAccent`) + icon hint (`IconData get glyph`) on PremiumStatus would let every consumer render a uniformly readable badge.
- **suggested fix**: Add `Color get badgeBg` returning solid `#FFB300` for active / `#3A3F55` for free + `IconData get glyph` returning `Icons.workspace_premium`/`Icons.lock_outline_rounded`. Reuse across PremiumGate + headers.
- **effort**: S
- **round1Ref**: new (P3-05 polishes Premium screen but not the model-level accessor)

- **severity**: low
- **location**: lib/services/premium_service.dart:160-162 (`debugClear`) and 153-158 (`debugUnlockPro`)
- **issue**: Debug overrides do not mark the resulting status with any "debug" flag. UI cannot render a distinct outdoor-visible "DEBUG · PRO" tag when a tester unlocks PRO during a field trial.
- **why it matters**: Test pilot welders on jobsite cannot tell if their PRO state is real or debug-injected — a high-contrast "DEBUG" overlay would prevent them from making purchasing decisions based on a debug grant.
- **suggested fix**: Add `final bool isDebugOverride` field on PremiumStatus, defaulted false; set true in `debugUnlockPro`. PremiumGate renders red "DEBUG" badge when true.
- **effort**: S
- **round1Ref**: new
--- end block ---

## Iter #28 · lib/services/ai_chat_service.dart · mixed-units

- **severity**: high
- **location**: lib/services/ai_chat_service.dart:149 (`_demoReply` P91 preheat branch)
- **issue**: "PWHT 730-760°C × 1h per inch wall" — metric temperature followed by imperial wall-thickness rule with no metric equivalent. The rest of the app is metric-default (DN/mm, ASME B31.3 cards in mm) yet the canonical PWHT soak-time rule is given only "per inch", forcing the welder to convert mm→in at the furnace.
- **why it matters**: P91 PWHT is safety-critical (creep, Type-IV cracking). A welder reading "1h per inch" with a 25 mm wall measures 25 mm with the tape, mentally rounds to "1 inch ≈ 25 mm so 1 h" — fine — but at 32 mm wall (common Sch 80, 6" pipe) the right answer is 1.26 h, not 1 h. Under-soak = brittle HAZ, field failure.
- **suggested fix**: Render dual: "PWHT 730-760°C × 2.4 min/mm wall (≈1 h per 25 mm / per inch)". Apply same dual-unit treatment to all demo branches.
- **effort**: S
- **round1Ref**: new (P2-13 dual-unit length formatter exists for cut-list — extend pattern to AI canned answers)

- **severity**: high
- **location**: lib/services/ai_chat_service.dart:184-188 (`_demoReply` heat-input branch)
- **issue**: Heat-input formula `HI = (V × I × 60) / (travel × 1000) × η` is published WITHOUT specifying the unit of `travel` or the resulting `HI`. The constant `60` and divisor `1000` only work when travel is in mm/min → HI in kJ/mm. A US-trained welder feeding travel as in/min gets a number that is 25.4× too high. The P91 ceiling "1.0-2.5 kJ/mm" is also unit-blind — US WPS sheets quote J/in or kJ/in.
- **why it matters**: This is the single most consulted welding formula on the shop floor. A unit-naked formula in an "AI expert" answer breaks trust the first time it disagrees with the inverter's live kJ display (which itself can be J/in on a US-bought Lincoln). Welder either ignores the app or burns a coupon with wrong HI and fails the procedure-qualification record.
- **suggested fix**: State explicitly: "Travel in mm/min → HI in kJ/mm. For in/min × 25.4 first, or use kJ/in × 0.0394 → kJ/mm." Cross-link the "Heat Input + CE" tool which already handles units. Show both 1.0-2.5 kJ/mm and 25-64 kJ/in for the P91 ceiling.
- **effort**: S
- **round1Ref**: P2-13 (length-unit dual; here generalised to derived units kJ/mm vs kJ/in)

- **severity**: high
- **location**: lib/services/ai_chat_service.dart:163-167 (`_demoReply` torque branch)
- **issue**: Bolt-torque equation `T = K × F × d` is shown without units for ANY variable. ASME PCC-1 publishes K dimensionless, F in lbf, d in inches → T in lbf·in; Euro practice has F in N, d in mm → T in N·m. The preload spec "50-75% SMYS" is also unit-naked (SMYS is a stress, ksi or MPa, not the preload force).
- **why it matters**: Misreading this on a class-300 flange leads to either gross over-torque (snapped stud, blowout during hydrotest) or under-torque (leak in sour-gas service triggering the NACE branch's own warnings). Workshop torque wrenches are split market: Polish suppliers ship N·m, offshore/US rigs ship lbf·ft.
- **suggested fix**: Replace with dual-unit form: "T [N·m] = K × F [kN] × d [mm] / 1000, or T [lbf·ft] = K × F [lbf] × d [in] / 12. Preload F = (0.50-0.75) × A_s × SMYS, where A_s in mm² and SMYS in MPa → F in N (or A_s in in², SMYS in ksi → F in lbf)."
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/services/ai_chat_service.dart:173-176 (`_demoReply` saddle/coping branch)
- **issue**: Formula `d(φ) = R_h − √(R_h² − R_b²·sin²(φ))` and "Owijka = π × D_branch" omit units. Result `d` is in whatever unit `R_h, R_b, D_branch` were entered in. The fitter's tape may be inches (UK/US fab shops) or mm (PL/DE). No guidance.
- **why it matters**: Saddle cut error of 1 mm vs 1 in on the offset curve = root gap unbuildable, joint scrap. Mixed-unit pipe shops (oil/gas pipeline contractors) routinely have inch nominal but mm wall (5L X65) — fitter must know which to feed.
- **suggested fix**: Add explicit "All R, D in same unit; output d in that unit. For DN/SCH input use OD from app's pipe dim table." Reference the FITTER tool that already handles unit-coherent input.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/services/ai_chat_service.dart:178-181 (`_demoReply` purge branch)
- **issue**: "flow 8-15 L/min" recommended — but the existing app already distinguishes slpm (standard L/min, normalised to 0°C/1 atm) from actual L/min in `quick_converter_screen` per P2-17. The AI demo branch only quotes "L/min" — ambiguous when welder is consulting a flowmeter at 5°C outdoor temp where actual ≠ standard by ~5%.
- **why it matters**: O₂ targets `<50 ppm Ti, <20 ppm Zr` are unachievable if the operator interprets "8 L/min" loosely. Backend retrieval over the 270 KB knowledge base will likely inherit the same ambiguity if the prompt template doesn't enforce it.
- **suggested fix**: Standardise the demo + system-prompt template to always quote "slpm (standard L/min)" with one-line gloss "≈ actual L/min at workshop temperature". Add bracketed scfh equivalent for US gauges: "8-15 slpm (17-32 scfh)".
- **effort**: S
- **round1Ref**: P2-17 (slpm clarification in quick_converter — extend to AI answers)

- **severity**: med
- **location**: lib/services/ai_chat_service.dart:156-160 (`_demoReply` NACE branch)
- **issue**: Hardness shown as "≤22 HRC (~250 HV10)" — equivalence is approximate (HV10 ≈ 248 at 22 HRC per ASTM E140 Table 1). The "~" hides that NACE MR0175 actually specifies HRC AND has separate HV10 limits for welds (≤250 HV10 max for CS welds per A.2.1.3). Treating them as interchangeable lets a welder reading HV10 on a portable tester accept 255 HV10 as "close enough to 250 ≈ 22 HRC" when the spec line is 250 HV10 absolute.
- **why it matters**: Sour service. Off-spec hardness in HAZ → sulphide-stress-cracking → catastrophic failure. The hardness-scale conversion is the single most contested data point in pipeline inspection.
- **suggested fix**: Split: "Base metal ≤22 HRC per NACE MR0175 §6.2.1; welds + HAZ ≤250 HV10 per §A.2.1.3 (NOT a conversion — both limits apply)."
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/services/ai_chat_service.dart:80-95 (`http.post` body construction in live mode)
- **issue**: Outgoing payload sends `lang: 'pl'` hardcoded but NO `units` field. Backend retrieval + Claude response will default to whatever the knowledge base happens to phrase each entry in (likely mostly metric, but inherited US texts will quote inches). The client cannot signal user preference — there is no `Settings.unitSystem` plumbed through to the AI request.
- **why it matters**: When live mode ships in Phase 5b, a UK/US fitter who has set imperial as preferred unit in the rest of the app will still get random mm/in mix in AI answers. Erodes the unit-consistency that the rest of the app (cut-list, hydrotest) works hard to maintain.
- **suggested fix**: Add `'units': BackendConfig.preferredUnitSystem` (or pull from `SettingsService`) to the POST body. Document in the backend system-prompt template that the model MUST quote dual units if input ambiguous, and respect `units: 'imperial' | 'metric' | 'both'`.
- **effort**: M
- **round1Ref**: P2-13 (unit-preference plumbing — extend to AI service)

- **severity**: med
- **location**: lib/services/ai_chat_service.dart:191-197 (demo-mode fallback hint examples)
- **issue**: Sample queries shown to user mix conventions inside a single list: "Moment śrub dla flange 4 cale class 300" (PL+inches), "Czas back purge dla SS DN100" (PL+metric DN), "preheat dla P91" (no units). The onboarding example list itself is mixed-units — sets the tone that the AI does not care which unit system you use.
- **why it matters**: First impression on Premium upsell. The fitter who sees "4 cale" assumes app speaks inches and types in inches everywhere else (silently breaking metric calcs); the fitter who sees "DN100" assumes metric-only and gets confused when AI quotes "per inch wall" in the P91 answer.
- **suggested fix**: Pick one convention per locale: PL → DN/mm in all 5 examples; EN → DN/SCH with inch nominal in parentheses. Or explicitly show dual-unit example: "Moment śrub dla DN100 (4") class 300".
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/services/ai_chat_service.dart:182 (`_demoReply` purge citations)
- **issue**: Citation strings mix English-only headings ("Iteration 91 — Ti/Zr welding") regardless of `lang: 'pl'` sent in live mode. When backend returns citations they will also be raw KB headings without unit-localisation — a PL fitter sees "P91 wall thickness 1 inch threshold" verbatim in citation snippet.
- **why it matters**: Lower trust — citations look like translation artifacts rather than authoritative sources matched to the welder's unit world.
- **suggested fix**: Have backend post-process citation snippets through a unit-localiser before returning (1 in → 25 mm in PL mode, mm → in in EN mode). Client-side: render citations through a `formatUnits(text, system)` helper.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #30 · lib/config/backend_config.dart · offline-resilience

- **severity**: high
- **location**: lib/config/backend_config.dart:20-21 (`baseUrl` const) + lib/services/api_client.dart:40 (only consumer)
- **issue**: `baseUrl` is a hardcoded `const` Railway URL with NO override mechanism (no `String.fromEnvironment`, no SharedPreferences override, no fallback URL list). When Railway has an outage, every backend-gated screen (Premium, AI chat, Jobs, Chat rooms, ISO AI scan) hangs on its own per-service timeout with no central kill-switch the user can flip. Contrast: `iso_scanner_ai.dart:24` reads `kIsoAiBase` from `String.fromEnvironment` with `defaultValue: BackendConfig.baseUrl` — an inconsistent partial override that suggests the dev knew the need but only wired one path.
- **why it matters**: Fitter on a basement worksite with flaky cellular cannot tell the app "stop trying, work offline" — every screen tries the same dead URL for its own 30 s timeout, draining battery and blocking UI. A workshop-floor outage today means each module fails independently, slowly.
- **suggested fix**: Add `static String get baseUrl => const String.fromEnvironment('FITTER_BACKEND_URL', defaultValue: '<railway url>');` plus an optional SharedPreferences offline-mode toggle so support can tell the user "tap Settings → Offline Mode" and every gate evaluates to `false` immediately.
- **effort**: M
- **round1Ref**: new (offline-mode central kill-switch missing)

- **severity**: high
- **location**: lib/config/backend_config.dart:34-36 (`jobsBackendLive = false`) vs lib/services/jobs_service.dart:20,35 (gate reads `stripeBackendLive`)
- **issue**: The flag `jobsBackendLive` is defined here with a comment claiming "Until then jobs_screen.dart uses local SQLite only", but the actual consumer (`jobs_service.dart` :20 and :35) gates on `BackendConfig.stripeBackendLive` — a completely different flag. The `jobsBackendLive=false` setting is therefore DEAD CONFIG: flipping it has no effect, and the Jobs feature is silently live (because `stripeBackendLive=true`). There is no local-SQLite fallback path in `jobs_service.dart` either — both `listPublic` and `listMine` return `const []` when the wrong flag is false. So when Railway is down the Jobs screen shows empty list with no "offline" indicator, looking identical to "no jobs posted yet".
- **why it matters**: An entire offline-resilience promise documented in this file is a lie. Fitter on cellular flake sees empty Jobs list, assumes there are no welding jobs in their area, closes app. The 49 PLN paid posting flow stays accessible but cannot complete.
- **suggested fix**: Either (a) align `jobs_service.dart` gates on `jobsBackendLive` and provide the SQLite fallback the comment promises, or (b) delete the `jobsBackendLive` flag and its misleading comment, and replace with an actual offline-detection that surfaces a "Brak polaczenia z serwerem" banner instead of returning `const []`.
- **effort**: M
- **round1Ref**: new (config-vs-implementation contract break with offline implications)

- **severity**: high
- **location**: lib/config/backend_config.dart:23-41 (all four feature flags are `const bool ... = true`)
- **issue**: All four "feature live" flags are compile-time `const`. There is NO runtime path to disable a backend call when the network is down or Railway is degraded. The file header even says "Until then the relevant screens fall back to demo mode / local storage" — but with every flag baked to `true`, demo mode is unreachable at runtime even when the fitter is on a plane / underground / in a steel-cladded shop with zero RF signal. Contrast with `premium_service.dart`'s new 2-min downgrade grace (P0-04): that elegant runtime-state machine cannot route around an offline Stripe call because the gate is const.
- **why it matters**: Offline-resilience requires runtime knobs, not compile-time toggles. Today the only way to "turn off Stripe" is a release rebuild + reupload to App Store/Play — useless in an outage. A connectivity-aware wrapper (`connectivity_plus` + cached "last known good" state) would let Jobs/Chat/AI degrade gracefully to "Tryb offline" without a release.
- **suggested fix**: Replace the four `const bool` flags with `static bool get xxxBackendLive => _ConfigGate.xxx;` where `_ConfigGate` consults `Connectivity().checkConnectivity()` + a circuit-breaker (e.g. 3 consecutive 5xx within 60s flips to false for 5 min). Default to the current `true` values when connectivity unknown. Keep the const versions as `_FORCED_xxxBackendLive` for the actual rollout gate.
- **effort**: L
- **round1Ref**: new (compile-time flags inadequate for offline-resilience lens)

- **severity**: med
- **location**: lib/config/backend_config.dart (entire file) — no timeout, no retry, no cache-TTL constants
- **issue**: The "single source of truth" advertised at line 3 does NOT define any of the offline-relevant constants every consumer needs: HTTP timeout, retry count, exponential-backoff base, cache TTL, max-stale-while-revalidate window, batch-flush interval for queued writes. Result: `api_client.dart` picks one timeout, `chat_service.dart` polls every 8s with no backoff under failure (per file-header line 41), `ai_chat_service.dart` likely has its own, `iso_scanner_ai.dart` uses dart-define override. Each module re-invents offline behavior. When Railway flakes, chat polls drain battery at 8s intervals indefinitely; AI chat times out at 30s; Jobs at whatever `api_client` defaults to. No coordination = uneven UX.
- **why it matters**: Fitter on metered cellular wonders why the battery vaporized after 40 min on a flaky-network site; reason is chat poll-storming because there is no central backoff knob. Workshop tablets on power-saver mode die during a 90-min shift.
- **suggested fix**: Add to this file: `static const Duration requestTimeout = Duration(seconds: 12);`, `static const Duration chatPollInterval = Duration(seconds: 8);`, `static const Duration chatPollBackoffMax = Duration(minutes: 2);`, `static const int retryMax = 2;`, `static const Duration jobsCacheTtl = Duration(minutes: 10);`. Then have every consumer reference these — and exponential-backoff chat polling under failure.
- **effort**: M
- **round1Ref**: new (no central offline-tuning surface in the "single source of truth" module)

- **severity**: med
- **location**: lib/config/backend_config.dart:20-21 (single `baseUrl`, no fallback list) + 60-67 (Stripe plan IDs as constants)
- **issue**: There is exactly ONE `baseUrl`. The header comment mentions reuse of the PrzetargAI Railway backend was DROPPED in favor of `jubilant-charm`; but if `jubilant-charm` goes down, the PrzetargAI backend at `backend-production-a43e3.up.railway.app` still runs the `/api/fitter/*` routes per the user's memory note (multi-route reuse pattern). The config has no `fallbackBaseUrls` list, so during a single-project Railway outage there is no client-side failover even though a perfectly functional sister deployment exists. Same shape for `planMonthly`/`planYearly` — the absence of any version field means a future "plan_v2" rollout requires an app rebuild.
- **why it matters**: Resilience by design — the app could hot-failover to the secondary Railway backend during outages. Today it cannot. Lost revenue + frustrated users during single-project outages.
- **suggested fix**: `static const List<String> baseUrlFallbacks = ['<jubilant-charm>', 'https://backend-production-a43e3.up.railway.app'];` + `api_client.dart` rotates on connection-refused / 502/503 after `retryMax` attempts on primary.
- **effort**: M
- **round1Ref**: new (no failover URL list — single point of failure)

- **severity**: med
- **location**: lib/config/backend_config.dart:1-11 (header doc) + 26-41 (flag comments promising fallbacks)
- **issue**: Doc-comment debt with offline-resilience consequences. Header line 5 says "the relevant screens fall back to demo mode / local storage"; line 30 says "Until then, AiChatService returns canned demo answers"; line 34 says "jobs_screen.dart uses local SQLite only". All three are false in the current commit (`aiBackendLive=true` so demo answers unreachable; `jobsBackendLive` is dead config per the high-sev finding above; `chatBackendLive=true` so `_fallbackRooms` at `chat_service.dart:150` is unreachable). The comments will mislead the next reviewer hunting for the offline path during an outage RCA, costing 30-60 min of triage at the worst possible moment.
- **why it matters**: Misleading inline docs become weaponized at 3am during a Railway outage when on-call (the solo dev) is half-asleep and trusts comments to point at the offline graceful-degradation path that does not exist.
- **suggested fix**: Update each flag's comment to reflect the live reality, OR (better) make the comments accurate by wiring the actual fallback paths (`_fallbackRooms`, demo AI canned answers, SQLite jobs cache). Both are equally valid; one of them must hold true.
- **effort**: S
- **round1Ref**: new (doc-vs-code drift, offline-critical)

- **severity**: low
- **location**: lib/config/backend_config.dart:20 (https:// hardcoded, no dev override)
- **issue**: HTTPS-only with no localhost / dev-server override path. During development against a local emulator (`http://10.0.2.2:8000/api/fitter/*` on Android, `http://localhost:8000` on iOS sim), the dev has to hand-edit this file and risk committing a `localhost` URL to main. There is no `kDebugMode ? 'http://localhost:8000' : ...` ternary, no `String.fromEnvironment` override. Marginal offline-resilience angle: on aircraft / fully-offline test rigs there is no way to point the app at a local mock backend without source edits.
- **why it matters**: Mostly a dev-velocity concern, but at the offline lens: prevents wiring a "local mock server" for offline integration testing on planes / EMC chambers.
- **suggested fix**: `static String get baseUrl { if (kDebugMode) { final dev = String.fromEnvironment('FITTER_DEV_URL'); if (dev.isNotEmpty) return dev; } return 'https://fitter-welder-pro-backend-production.up.railway.app'; }`
- **effort**: S
- **round1Ref**: new (dev/offline-mock seam missing)

--- end block ---

## Iter #31 · lib/screens/iso_notebook_screen.dart · a11y-semantics

- **severity**: high
- **location**: lib/screens/iso_notebook_screen.dart:4068-4144 (9 AppBar IconButtons + Tune popup), 4067 (HelpButton)
- **issue**: Every AppBar IconButton (Note prefixes, Enter dimensions, Copy summary, Undo, Axis lock, Export PDF, Show hint, Clear all, View) has a `tooltip:` but NO explicit `Semantics(label: ..., button: true)`. Material IconButton auto-maps tooltip → semanticLabel on modern Android/iOS, but the dynamic axis-lock tooltip (`_axisLock ? 'Wyłącz blokadę osi (slope)' : 'Włącz blokadę osi'`) is the announced state — there is no `Semantics(toggled: _axisLock)` so TalkBack/VoiceOver users hear the lock as a plain button and cannot tell whether it is currently engaged without toggling it and listening to the SnackBar.
- **why it matters**: Workshop a11y users (and PL WCAG 2.1 for state apps under EAA 2025) cannot determine the current lock state — toggling the axis-lock blindly mid-drawing pushes any in-progress pipe to a different snap mode, silently distorting the iso geometry the welder is about to cut from.
- **suggested fix**: Wrap the axis-lock IconButton in `Semantics(toggled: _axisLock, label: _tr('Blokada osi izometrycznej', 'Isometric axis lock'), child: ...)` and prefix the SnackBar text with `SemanticsService.announce(...)` so the new state is also announced when toggled by touch.
- **effort**: S
- **round1Ref**: P2-16 (extends — P2-16 covers `Semantics(label, button: true)` on every AppBar IconButton for orbital_tig/tungsten/cut_list_summary but explicitly omits iso_notebook; the toggled-state angle on axis-lock is new)

- **severity**: high
- **location**: lib/screens/iso_notebook_screen.dart:4233-4272 (canvas GestureDetector + inner Semantics)
- **issue**: The Semantics wrapper labels the canvas "Płótno szkicu izometrycznego — przeciągnij aby rysować, dotknij aby wybrać" but is placed INSIDE the GestureDetector child tree under `RepaintBoundary > Semantics > CustomPaint`. The outer GestureDetector (line 4233) intercepts pan/tap/long-press but exposes no semantics of its own, so screen-reader focus lands on the inner Semantics node which has `container: true` but no `button`/`textField`/`onTap`/`onLongPress` properties. As a result the screen reader announces the label as static text and never offers the "double-tap to activate / hold for long-press" affordance that gesture actions require — the canvas is functionally invisible to TalkBack.
- **why it matters**: A monter using TalkBack (regulated by PL Act of Apr 4 2019 on digital accessibility extended to private apps under EAA from June 2025) literally cannot draw a pipe — the canvas reads as a paragraph of text, not an interactive surface, so the whole tool becomes inaccessible.
- **suggested fix**: Add `onTap`, `onLongPress` semantic actions to the Semantics node and either move it OUTSIDE the GestureDetector or merge them: Semantics with onTap/onLongPress wrapping GestureDetector. Drop `container: true` in favour of `explicitChildNodes: true` if child Semantics need to surface.
- **effort**: M
- **round1Ref**: new (round-1 backlog mentions canvas-area issues at P2-04 fullscreen mode but not a11y wiring)

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:4416-4446 (chip builder in _Toolbar)
- **issue**: The 24 toolbar chips (Rura/Linia/Ukryta + 18 fittings + 3 annotations) are built from GestureDetector wrapping an AnimatedContainer with Icon + Text. No `Semantics(selected: sel, button: true, ...)`, no Tooltip, no Material+InkWell. The visual selected state is colour-only (border + fontWeight). Screen readers therefore announce all 24 chips identically — "Rura" reads the same whether selected or not — and there is no group label ("LINES/FITTINGS/ANNOTATIONS" are visual `groupLabel` Text widgets, not Semantics headers).
- **why it matters**: TalkBack users cannot tell which tool is the currently-active one and so cannot determine what a subsequent canvas tap will produce. For a sighted welder the colour border is a glance — but in glove-degraded haptic conditions even sighted users miss the small colour delta and the missing `selected` semantic hides the same info from the haptic-aware feedback loop on Android 12+.
- **suggested fix**: `Semantics(selected: sel, button: true, label: e.$3, child: GestureDetector(...))` per chip; wrap each `groupLabel(...)` in `Semantics(header: true, child: ...)`. Bonus: add `Tooltip(message: e.$3)` so long-press also speaks the name.
- **effort**: S
- **round1Ref**: P1-07 (extends — P1-07 covers tap-target sizing on these same chips at 4416-4446 but does NOT cover Semantics state/selected); related to P2-16 a11y rollup

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:1406-1416 (isoCtrl TextField), 1452-1474 (component name + value TextFields in deduct rows), 1645-1653 (slope), 1798-1809 (text/instrument), 2163-2178 (reducer length), 2342-2358 / 2645-2660 (flange face length), 7368-7385 / 7435-7452 (bulk dimension entry TextFields)
- **issue**: All ~10 TextFields in the dimension-entry flows use only `hintText` / `suffixText` / `helperText` — none have `labelText`. Flutter a11y: when no `labelText` is supplied the screen reader reads only the (often very short) hintText until focus arrives, and never announces a stable name when the field has content. The lone exception at lib/screens/iso_notebook_screen.dart:1972 ("CTE — oś do czoła") establishes inconsistency. Numeric input fields tagged only with '76' or '24' are essentially unlabelled to TalkBack.
- **why it matters**: A monter with TalkBack focusing on the second component row hears "komponent, edit box, 76, edit box" instead of "Nazwa komponentu, edit box; Długość mm, edit box". The same TextField pattern in the bulk dimensions sheet (7368-7452) repeats N times for N segments — confusing in dense 50-pipe routes where field 1 and field 25 are indistinguishable to the reader.
- **suggested fix**: Replace `hintText: 'np. 76'` with `labelText: _tr('Długość (mm)', 'Length (mm)'), hintText: '76'` so labels are stable; add `labelText` to slope, ISO segment, and bulk-dim TextFields. Wrap bulk-sheet rows in `Semantics(label: 'Segment ${i+1} z ${total}', textField: true, child: ...)`.
- **effort**: M
- **round1Ref**: P2-16 (related — a11y rollup; field-label gap is iso-notebook-specific and not yet filed)

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:4047-4064 (AppBar title GestureDetector + edit icon)
- **issue**: The AppBar title is a GestureDetector that opens the rename dialog. Wrapped in a Tooltip(message: 'Dotknij, aby zmienić nazwę projektu', child: GestureDetector(onTap: _editName, child: Row(...))) — but with no `Semantics(button: true, label: ...)`. The pencil icon is decorative-only (no excludeSemantics) and the title text is the only semantic. TalkBack reads "Zeszyt ISO" as plain heading text and gives no "double-tap to rename" affordance.
- **why it matters**: Renaming the drawing is needed for every job (line number 6"-CWS-1234) — discoverability of the rename target is invisible to a11y users; they have no path to set the project name short of the implicit tooltip (long-press only fires Tooltip on phones, never enough for screen-reader path).
- **suggested fix**: Wrap the GestureDetector with `Semantics(button: true, label: _tr('Zmień nazwę rysunku — aktualnie: $_projectName', 'Rename drawing — current: $_projectName'), child: ...)`; mark the `Icon(Icons.edit_outlined)` as ExcludeSemantics since the parent Semantics owns the affordance.
- **effort**: S
- **round1Ref**: new (round-1 BACKLOG P2-07 mentions iso_notebook line 4039-4042 for outdoor-mode, not a11y on title)

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:4290-4358 (empty-state hint card with close InkWell)
- **issue**: The dismiss button is InkWell(onTap: () => _setHintHidden(true), child: Padding(child: Icon(Icons.close, ...))) with no tooltip, no `Semantics(button: true, label: ...)`, and no MergeSemantics around the hint card. The `Icon(Icons.touch_app_outlined)` at line 4309 also lacks a semanticLabel. Screen readers will announce: "icon, How to draw a route, …, icon" with no indication that the trailing icon is a dismiss control.
- **why it matters**: First-time onboarding for an a11y user becomes a trap — the close affordance is unreachable by labelled focus, so the hint stays permanently overlayed on the empty canvas; the user cannot get past the onboarding hint to start drawing.
- **suggested fix**: Wrap the close InkWell in `Semantics(button: true, label: _tr('Schowaj instrukcję', 'Dismiss hint'))` (or use IconButton which auto-provides this), and wrap the card in `MergeSemantics(child: Column(...))` so the hint reads as a coherent block.
- **effort**: S
- **round1Ref**: P2-16 (cross-screen a11y rollup; this hint card not explicitly listed)

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:4108-4119, 3522-3541, 3593-3599 (SnackBar emission sites for axis-lock toggle, copy-summary, clear-drawing)
- **issue**: These SnackBars carry important state-change info ("Blokada osi: WÅ.", "Skopiowano zestawienie (N linii)", "Wyczyszczono rysunek (N el.)") but rely on the default SnackBar a11y, which on TalkBack often announces only the message ONCE at appearance â€” and any concurrent gesture (a follow-up tap) will dismiss/race the announcement. There is no `SemanticsService.announce(...)` call so the state change can be missed entirely.
- **why it matters**: A11y user toggling axis-lock has no confirmation route; copy-summary feedback is delivered through transient SnackBar only. Combined with the missing `toggled:` Semantics on the lock button (finding #1) this leaves a11y users unable to confirm whether the lock toggle actually fired.
- **suggested fix**: After each SnackBar emission call `SemanticsService.announce(message, Directionality.of(context))` for state-changing actions. Wrap the SnackBar content Text in `Semantics(liveRegion: true, child: Text(...))` per P2-16 pattern.
- **effort**: S
- **round1Ref**: P2-16 (extends — live-region pattern from P2-16 explicitly mentions orbital_tig validation; same pattern needs applying to iso_notebook state changes)

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:4061 (edit pencil), 4309 (Icons.touch_app_outlined in hint), 7541-7553 (axis legend label + decorative chip rows)
- **issue**: Decorative/standalone Icons inside Row/Column without surrounding actionable semantics lack ExcludeSemantics wrappers (the file does this correctly at 3527 for the snackbar checkmark and at 7561 for the compass painter — but inconsistently elsewhere). On TalkBack each freestanding Icon announces a generic "icon" between meaningful text, producing noisy reads like "icon, How to draw a route, icon".
- **why it matters**: Noise pollution in the reading order makes the hint card and the AppBar title unnecessarily long to listen through; cumulative across the screen it materially slows a11y task completion.
- **suggested fix**: Wrap decorative icons in `ExcludeSemantics(child: Icon(...))` (or use the `excludeSemantics: true` flag on Semantics); apply consistently to: 4061 (edit pencil — parent should own label), 4309 (touch_app icon), 4198/4182/4191 (popup menu icons — PopupMenuItem already labels the row text).
- **effort**: S
- **round1Ref**: new (cosmetic a11y polish — not in round-1 BACKLOG)

--- end block ---


## Iter #37 · lib/screens/rolling_offset_screen.dart · regression-check-p0-fixes

- **severity**: high
- **location**: lib/screens/rolling_offset_screen.dart:46-49 (wipe) + 305-311 (`_result` copy IconButton enable-state) + 57-81 (early-return paths with no `setState`)
- **issue**: The P0-05 fix (commit d025247) wipes the four result controllers BEFORE the validation early-returns at lines 74 and 80, but does NOT trigger a rebuild on those early-return paths. The closing `setState(() {})` (line 94) only runs on the success path. The copy IconButton at lines 305-311 captures `ctrl.text.trim().isEmpty ? null : () => copyToClipboard(...)` at build time — after a validation failure the controllers ARE empty but the IconButton remains in its previously-built "enabled" state. Tap the copy button → `copyToClipboard(context, '', label: ...)` runs (clipboard_helper.dart:14 does not guard empty strings) → the clipboard's previously-copied 707.1 from pipe A is silently overwritten with empty string. The previously-shown numerals also visually disappear from the result TextFields (because TextEditingController listeners DO rebuild the bound TextField subtree), so the fitter sees blank fields + an enabled copy button — a confusing UI contradiction. Round-1 Iter #7 (in the same audit log) already flagged this; the P0-05 fix shipped without addressing it.
- **why it matters**: Workshop scenario the P0 was meant to prevent: fitter computes pipe A (707.1 copied to clipboard, on its way to the saw operator). Switches to pipe B, mistypes Rise (e.g. leading dot), hits CALCULATE → snackbar "Wpisz Rise i Spread > 0" → result fields blank → fitter reflex-taps copy "to refresh" → clipboard now empty → fitter pastes empty into WhatsApp to saw operator OR pastes empty into BOM cell silently. The P0-05 fix INTRODUCED this regression: pre-fix, the stale 707.1 remained displayed AND on the clipboard (wrong number copied to saw — what P0-05 set out to fix). Post-fix, the field is blank but the copy button still works and silently overwrites the clipboard with empty string. Net outcome: a different wrong-cut path, equally damaging.
- **suggested fix**: Move/duplicate `setState(() {});` immediately after the four `.clear()` calls at lines 46-49 (before any validation), or wrap the four clears inside a `setState(() { ... })`. Optional belt-and-braces: in `copyToClipboard` (lib/utils/clipboard_helper.dart:14) early-return + warn snackbar when `value.trim().isEmpty`.
- **effort**: S
- **round1Ref**: P0-05 + Iter #7 finding #1 (round-1 already flagged this; the P0 fix did not address it — true regression of the P0)

- **severity**: high
- **location**: lib/screens/rolling_offset_screen.dart:46-49 (wipe) + 245-269 (`_angleBtn` onTap)
- **issue**: The P0-05 wipe runs only inside `_calculate()`. Tapping a preset angle chip (45°/60°/30°/'Inny') at lines 248-249 only mutates `_selectedAngle` and does NOT clear the result controllers. Post-fix scenario the BACKLOG explicitly invokes ("computed pipe A, switched config, copied stale 707.1") still applies the moment the user switches angle without re-typing inputs. The P0 covered the case where the user re-presses CALCULATE; it does NOT cover the case where the user changes the angle chip and copies the stale result without re-calculating. P3-12 in round-1 mentioned auto-clearing `_customAngleController` on selection change but not the four result controllers.
- **why it matters**: Workshop: fitter computes 45° rolling offset, then realises the elbow is 60° (label was unclear in dim shop lighting), taps the "60°" chip — chip highlight jumps to 60° but Travel still reads 707.1 (the 45° travel). The 60° travel would be ≈577.4 — fitter cuts pipe 130 mm too long. P0-05's stated goal — "stop stale results from being copied" — is only half-met.
- **suggested fix**: In `_angleBtn.onTap` (or wrap in helper), additionally clear the four result controllers and (if value != 'custom') the `_customAngleController` inside the existing `setState`. Same wipe must also run on toggle of `_selectedAngle == 'custom'` mount/unmount.
- **effort**: S
- **round1Ref**: P0-05 + P3-12 + Iter #7 finding #2 (P0-05 chose the narrow re-CALCULATE path and missed the angle-switch path that exhibits the same wrong-cut symptom)

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart (whole file) + test/ directory (no rolling_offset_test.dart)
- **issue**: P0-05 ships zero regression test for the wipe behaviour. No widget test asserts that after a successful calc + validation-failing recalc the result controllers are empty AND the copy IconButton is disabled. No widget test asserts that switching angle chip post-calc clears results. The `test/` directory contains math-only unit tests (cut_calculator, iso_parser, orbital_tig, etc.) but no screen-level widget tests for any of the calculator screens. The commit message claims "120 tests pass" but none of them exercise this regression-prone surface — any future refactor of `_calculate()` (or accidental removal of the four `.clear()` lines) re-introduces the original stale-707.1 cut bug with no CI signal.
- **why it matters**: P0-05 is exactly the kind of subtle, easy-to-undo correctness fix that needs a regression test pinned to it — otherwise the next contributor moving the validation block above the clears (a reasonable "early-return first" refactor) reverts the safety guarantee silently. The BACKLOG / decision-record convention for FitterWelderPro typically pairs P0 with a test; this one didn't.
- **suggested fix**: Add `test/widgets/rolling_offset_screen_test.dart` with a `testWidgets` that pumps the screen, enters Rise/Spread + 45°, taps CALCULATE, asserts Travel field non-empty, then enters invalid Rise (empty), taps CALCULATE, asserts all four result `TextField`s contain empty text AND the copy `IconButton.onPressed` is null (i.e. `tester.widget<IconButton>(...).onPressed == null`). Second test: tap a different angle chip after a successful calc, assert results are wiped.
- **effort**: M
- **round1Ref**: new (no round-1 BACKLOG item explicitly demanded a widget test for the rolling-offset P0; the gap is real)

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:99-102 (`_isDirty`) — interaction with P0-05 wipe
- **issue**: After P0-05's pre-validation wipe runs and the early-return fires, the controllers' `_*Controller.text` are empty BUT the input controllers (`_riseController`, `_spreadController`, `_customAngleController`) are still populated, so `_isDirty` returns `true` and the back-button still triggers the discard dialog. That is correct behaviour. However, if a future round-1 implementer adds result-non-empty to `_isDirty` (as P3-12 suggested), the P0-05 wipe would briefly toggle `_isDirty` from `true → true` (input dirty already) → no visible change. BUT if the user CLEARS the input fields manually after a validation failure, `_isDirty` becomes `false`, the back-button silently pops, AND the stale-but-cleared result controllers contribute nothing to the dirty signal. That's fine for back-pop but the screen state ends up in a confusing "no inputs, no results, but the user remembers having computed something" state. No actual bug, but a stale assumption: P0-05 assumed `setState` would be called by the success path; P3-12 assumed `_isDirty` could rely on result-controller state. The two reasonable-looking fixes interact awkwardly.
- **why it matters**: Coordination risk for future code touching this file. Not directly workshop-impacting.
- **suggested fix**: When implementing P3-12 (`_isDirty` includes results), explicitly reason about the post-P0-05 empty-controller window and add the `setState` before early-returns first.
- **effort**: S
- **round1Ref**: P3-12 + P0-05 interaction (annotation for whoever picks up P3-12 next)

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:46-49 — interaction with PremiumService P0-04 grace window (lib/services/premium_service.dart)
- **issue**: Not a defect IN this module, but a stale assumption worth flagging: the rolling-offset screen does NOT gate behind premium. If a future change makes any of the four results (e.g. Multiplier, or PDF export of the cut) premium-only, the P0-05 unconditional wipe at lines 46-49 + the P0-04 2-minute downgrade grace would interact: a fitter with a stuck `_pendingDowngradeAt` whose grace expires during a calc session would see the result fields wiped on next CALCULATE due to a premium check, attribute it to P0-05's wipe, and never realise their PRO was silently downgraded. Currently moot (screen is free); flagged for whoever adds premium gating to calculator screens.
- **why it matters**: Pre-emptive — prevents a debugging loop where a fitter swears "the calc isn't working" and the symptom is actually a premium-downgrade race.
- **suggested fix**: When/if premium gating is added to calculator screens, expose `PremiumService.isInDowngradeGrace` to the UI so a banner can warn the user that their entitlement state is being confirmed.
- **effort**: S
- **round1Ref**: P0-04 (cross-module stale assumption)

--- end block ---

## Iter #38 · lib/screens/hydrotest_screen.dart · recent-commit-quality
- No findings: no commits touch this file in the window `--since=2026-06-04`. Most recent commit on this path is `3883cc0` (2026-06-03, ISO notebook mojibake sweep) — outside lens scope. Round-1 hydrotest-specific concerns (factor 1.5 hardcoded vs ASME B31.3, no min-hold-time enforcement, no PED/EU pressure-unit toggle) are tracked separately and not surfaced by a recent-commit lens. Round-1 P1 items covering this module remain authoritative.

--- end block ---

## Iter #39 · lib/screens/pipe_route_calculator_screen.dart · recent-commit-quality
- **severity**: high
- **location**: lib/screens/pipe_route_calculator_screen.dart:92 (commit 69310f8 hunk @@-87,10 +90,13)
- **issue**: The locale-aware decimal-separator switch reads `AppLanguageController.isEnglish` — a STATIC getter backed by `static AppLanguage current` in `lib/i18n/app_language.dart:14-16`, NOT the per-widget-tree `InheritedNotifier`. The widget is rebuilt by `context.tr(...)` via `dependOnInheritedWidgetOfExactType<AppLanguageScope>` (line 39 of app_language.dart), but `_calculate()` is invoked from a button tap, NOT from `build()`. As a result: (a) if the language toggle in another tab fires after this widget has been mounted but `_calculate()` has not yet been called, `current` gets updated correctly only because both `setLanguage` and the constructor write to it (line 11, 21) — fine. BUT (b) the comment "Safe because _parse() accepts both" hides a real round-trip bug: after Calculate produces `1234,5` (PL) and the welder toggles to EN to share the screen with a foreign colleague, the result controllers KEEP the PL comma (no rebuild rewrites the controller text). Then if they hit Calculate again with empty inputs the validation re-fires; if they instead just COPY the value via the copy icon they get `1234,5` pasted into an EN-locale spreadsheet which parses it as `12345` (US Excel) — off by an order of magnitude. Tight coupling: the screen reads a global static from a controller that has no listen-mechanism here.
- **why it matters**: Workshop: fitter computes a 1234,5 mm cut, switches the app to EN to take a screenshot for the German project manager, copies the value into WhatsApp → Excel imports it as 12345 mm on the PM side. Off-by-10 cut order for spool fabrication is a four-figure scrap cost.
- **suggested fix**: Either (a) use `context.language == AppLanguage.en` to localise the separator (subscribes the widget to rebuilds and the choice is captured at calc-time per the active locale of THIS tree), AND in `build()`, when locale has changed since last calc, re-format the existing result controllers via a stored `double` cache; or (b) store results as canonical `double` and format on display only (`Text('${_totalValue.toStringAsFixed(1).replaceAll(...)}')`) so the controller is render-time, not storage. Option (b) also fixes the broken copy-to-clipboard path for free.
- **effort**: M
- **round1Ref**: new (round-1 P1-22 mentions persisting decimal-separator preference but doesn't surface this round-trip data-corruption path; the commit 69310f8 introduced the bug by adding the static read)

- **severity**: high
- **location**: lib/screens/pipe_route_calculator_screen.dart:93-96 (commit 69310f8) + 333-342 (copy IconButton)
- **issue**: The result controllers now contain locale-formatted strings (with comma in PL). The copy IconButton at line 342 calls `copyToClipboard(context, ctrl.text, ...)` — it copies the raw display string including the comma. Round-1 P1-22 lists clipboard / persistence concerns but this commit silently introduced a clipboard payload format inconsistency: a PL user copies `1234,5`, an EN user copies `1234.5`, and no metadata says which is which. Any downstream tool (Notion, Excel, calculator app) that re-imports the value will interpret it per its OWN locale, not the source's.
- **why it matters**: A welder pastes `1234,5` into the iOS Calculator (EN locale on a borrowed phone) — it shows `12345`. Same hazard as finding #1 but specifically on the copy path, which is the most-used downstream of this calculator.
- **suggested fix**: Pass an unambiguous form to clipboard: either always copy with `.` separator (machine-canonical), or copy `1234,5 mm (PL)` / `1234.5 mm` with explicit suffix. Trivially: in the `onPressed` lambda at line 342, do `ctrl.text.replaceAll(',', '.')` for clipboard while leaving the visible field locale-formatted.
- **effort**: S
- **round1Ref**: P1-22 partial (round-1 BACKLOG flagged decimal-separator preference but did not call out the clipboard interop hazard)

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:173-240 (commit 69310f8 hunk @@-167,6 +170,30)
- **issue**: The empty-state guard `if (_totalController.text.isEmpty)` uses the result-controller text as the proxy for "has computed". Two missing-path scenarios introduced by this commit: (1) once the welder has computed once, then changes any input field and the result is NOT recomputed — the stale result block still renders (no `onChanged` invalidation on the input fields). The blue TOTAL container will display a result that does not match the inputs currently visible above it. (2) The `else ...[ ... ]` branch contains no recovery path if `_seg1Controller.text` ends up empty (e.g. user manually cleared one via a copy gesture race). The branch unconditionally renders the three _result fields. Tight coupling: UI structure assumes "all four controllers filled OR all four empty" — never enforced.
- **why it matters**: Fitter tweaks H1 from 1200 to 1250 to test a new spool position, doesn't tap Calculate, glances at TOTAL — sees the OLD 1200-based total and orders pipe to that length. The empty-state guard was added precisely to prevent confusion, but it created a NEW confusion: false-confidence stale result.
- **suggested fix**: Add `onChanged: (_) => _invalidateResults()` to each `_field(...)` call (lines 129, 132, 138, 141, 146) — clear the four result controllers and `setState`. Bonus: change `if (_totalController.text.isEmpty)` to a `bool _hasResult` state flag set true in `_calculate()` success, false in `_invalidateResults()` — single source of truth.
- **effort**: S
- **round1Ref**: new (round-1 P2-01 mentions "auto-draft form state on every onChanged" for pipe_route, but does not require invalidating results on input change — that's a different concern)

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:267-302 (`_showTotalFormulaDialog`) — entire method added by commit 69310f8
- **issue**: The 35-line formula dialog string is HARDCODED inline in PL and EN. The constants `1,5708`, `1,5·DN`, the C-F vs C-C nomenclature, the LR-elbow assumption — all baked into a 16-line PL string literal and a parallel 16-line EN string literal. (a) No knowledge-base / source citation (ASME B16.9 for LR elbow CLR=1.5·DN; ISO 15590-1 for SR). (b) The factor `1.5708` is the ROUNDED form of π/2; if a future contributor edits the PL string and forgets the EN one, locale-divergence between PL and EN formulas (subtle units bug). (c) Hardcoded values that should be config: the `1.5·DN` ratio applies to LR (long-radius) 90° elbows; SR (short-radius) is `1.0·DN`; the dialog ASSERTS the LR convention without exposing the choice. A welder reading the dialog for SR work computes a takeout 33% too large. (d) Round-1 BACKLOG item P3-12 explicitly lists this method at line 267-302 as needing a `prefs_pipe_route_formula_seen` flag; this commit didn't add that.
- **why it matters**: Reference dialogs are exactly the surface where "info_outline" creates trust. If the welder follows the dialog formula assuming SR elbow (more common in tight shop work), takeout error compounds across three elbows → 30+ mm error per route — a misalign-the-flange disaster.
- **suggested fix**: Extract the dialog text to `lib/help/pipe_route_formula.dart` returning `(String pl, String en)` from a single source. Add an explicit LR/SR/3D selector at the top of the dialog showing the takeout factor (1.0·DN / 1.5·DN / 3.0·DN). Cite ASME B16.9 inline. Wire P3-12 prefs_pipe_route_formula_seen while at it.
- **effort**: M
- **round1Ref**: P3-12 (round-1 flagged the dim-after-seen behaviour and listed this exact line range; the commit added new content without addressing P3-12)

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:336-342 (commit 69310f8 hunk @@-259,8 +334,9) — copy IconButton tap-target enlargement
- **issue**: The commit enlarges the copy icon from `size: 18` to `size: 24` and adds `constraints: BoxConstraints(minWidth: 48, minHeight: 48)`. Good intent (accessibility), but this is applied ONLY to pipe_route, NOT to the other ~20 IconButton call-sites across calculator screens that share the same `_result` widget pattern (rolling_offset, hydrotest, heat_input, orbital_tig, tungsten, quick_converter, weld_journal). Tight coupling to one screen of a shared visual pattern means a fitter switching between calcs encounters DIFFERENT-SIZED copy targets — UI-consistency regression. Round-1 P1-23 and P1-24 are explicit about cross-screen consistency; this commit drifted from it.
- **why it matters**: Workshop ergonomics: welder muscle-memory expects the same tap target on every calc. Inconsistent target size causes mis-taps when switching screens in a hurry between solving offsets.
- **suggested fix**: Extract `_CopyableResultField` (or `lib/widgets/copyable_result.dart`) used by ALL calc screens, with the 48×48 tap target as default. Replace `_result()` here and the 6+ inline copies in sibling screens. Effort upgrade reflects the rollout, not the localised change.
- **effort**: M
- **round1Ref**: P1-23 + P1-24 + P3-12 (round-1 already wanted shared widget extraction; this commit moved one screen forward without unifying)

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:218-231 (commit 69310f8) — the new info-button `Row`
- **issue**: The added `Row` wrapping `Text + IconButton` has NO `mainAxisSize: MainAxisSize.min` and NO `Flexible` around the Text. In the parent layout the Row is inside an `Expanded > Column > Row`, which means it expands to fill horizontally and the IconButton ends up flush-right OR if the PL string `"SUMA (bez kolanek)"` is rendered at large text scale (settings → accessibility → text size 200%), the Text overflows and the IconButton is pushed off-screen with a yellow-black `RenderFlex overflowed` stripe.
- **why it matters**: Welders frequently use large text on phones (sun glare, safety glasses, presbyopia). A "broken pixels" RenderFlex stripe reads as "app is buggy, don't trust it".
- **suggested fix**: `Row(children: [Flexible(child: Text(...)), IconButton(...)])` or wrap Row with `mainAxisAlignment: MainAxisAlignment.spaceBetween` and `Flexible` on the Text.
- **effort**: S
- **round1Ref**: new (not in round-1 BACKLOG)

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:269 + 271 + 297 (commit 69310f8) — `ctx.tr(...)` inside `showDialog<void>(builder: (d) => ...)` then `Navigator.of(d).pop()`
- **issue**: The dialog builder receives a fresh `BuildContext d` but the method body uses `ctx.tr(...)` (the outer context) for title/content text. Mixing two contexts in one builder is non-fatal but: (a) if the outer widget unmounts while the dialog is open (rare — only via deep-link navigation), `ctx` becomes invalid and the next rebuild of the dialog crashes; (b) Flutter analyzer in stricter modes flags this as `use_build_context_synchronously`. Untranslated edge: `OK` is the same PL and EN — fine — but the pattern duplicates `ctx.tr(pl: 'OK', en: 'OK')` which is dead overhead and arguably a translator-facing inconsistency ("don't translate OK" is locale-dependent — German prefers `In Ordnung` for formal UI).
- **why it matters**: Future DE/AT rollout (BACKLOG P3-* mentions DE locale): the `OK` literal will fail review by a German translator who expects to localise it.
- **suggested fix**: Use `d.tr(...)` consistently inside the builder, or hoist tr() calls to before `showDialog()`. Replace `ctx.tr(pl: 'OK', en: 'OK')` with `MaterialLocalizations.of(d).okButtonLabel`.
- **effort**: S
- **round1Ref**: P3-12 (round-1 flagged the formula-dialog area generally; the use_build_context_synchronously micro-smell is new)

--- end block ---

## Iter #40 · lib/screens/orbital_tig_screen.dart · test-coverage-gaps

- **severity**: high
- **location**: test/orbital_tig_test.dart (entire file) vs lib/screens/orbital_tig_screen.dart:25-325
- **issue**: Zero widget tests exist for `OrbitalTigScreen`. The `test/orbital_tig_test.dart` file covers only the pure-math `estimateOrbital` service. None of the screen's branching logic — `_calc()` error paths (OD missing / wall missing / wall > OD/2), the `if (_error != null)` red banner, the `if (e != null)` result tree, the comma-vs-dot decimal parsing in `_p()`, or the `_volts` 10 V fallback (line 56, 229) — has a single widget test. A regression that flips the wall<OD/2 inequality, drops the error banner widget, or silently coerces an empty OD field would ship undetected.
- **why it matters**: Orbital TIG is used on stainless food/pharma piping where a bad starting current ruins a 6-meter coil — the welder relies on the L1-L4 amp readouts and the "STARTING values" banner being correct. A silent UI regression (e.g. result card rendered with stale `_est` after an error) would have the welder dialling in numbers from a previous tube size without realising.
- **suggested fix**: Add `test/orbital_tig_screen_test.dart` with `WidgetTester` cases: (a) entering "25.4" and "1.65" renders 4 `_LevelRow` widgets with descending amps; (b) wall > OD/2 renders red error container and NO `_ResultCard`; (c) entering "1,65" with comma parses identically to "1.65"; (d) leaving volts empty applies the 10 V fallback in copy header; (e) clearing OD after a valid calc clears the result card on next keystroke.
- **effort**: M
- **round1Ref**: new (round-1 P1-30 was per-field validation, not widget-test coverage)

--- end block ---

## Iter #40 · lib/screens/orbital_tig_screen.dart · test-coverage-gaps

- **severity**: high
- **location**: lib/screens/orbital_tig_screen.dart:226-263 (Copy-all-parameters OutlinedButton onPressed)
- **issue**: The "Kopiuj wszystkie parametry" handler — the single most important workflow output (the string a foreman pastes into a WPS form or chat) — has no test. The `try/catch` around `copyToClipboard` (lines 247-263), the fallback `ScaffoldMessenger.showSnackBar`, the `context.mounted` guard (line 254), the `_trace` empty-vs-non-empty `traceLine` branch (lines 239-242), and the exact format of the header/lvl/geo lines are all untested. A locale change, a stamp with newline injection, or a clipboard exception path could silently ship a corrupted parameter string with no test catching it.
- **why it matters**: The copied string IS the deliverable to the foreman/QA — if the L1-L4 amps line gets mangled (e.g. translation drift swaps the middle-dot for a slash, or an empty volts field produces "U=NaN V") the welder pastes garbage into the WPS log and an auditor rejects the joint downstream. Worse, if `copyToClipboard` silently fails on a locked-profile device and the snackbar fallback regresses, the welder sees nothing and assumes the copy worked.
- **suggested fix**: Add widget test that pumps the screen, fills OD/wall/volts/trace, taps the OutlinedButton, captures `Clipboard.setData` via a `MethodChannel` mock, and asserts the exact multi-line string (header + lvl + geo + traceLine). Add a second test where the mock throws, asserting the SnackBar surfaces with the localised clipboard-failure text and that `context.mounted` short-circuits when the widget is unmounted mid-await.
- **effort**: M
- **round1Ref**: new (overlaps thematically with P1-13 sanitise free-text, but P1-13 is a fix, not a test)

--- end block ---

## Iter #40 · lib/screens/orbital_tig_screen.dart · test-coverage-gaps

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:310-324 (`_field` helper) + 47-48 (`_p` parser) + 314 (`FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))`)
- **issue**: No test guards the input-formatter regex against pathological strings — e.g. multiple dots ("25..4"), leading comma (",165"), trailing comma ("1.65,"), bare dot ("."), or duplicate commas ("1,6,5"). All pass the `[0-9.,]` allow-list but break `double.tryParse` after `replaceAll(',', '.')` (line 48), returning `null` and silently rejecting input — the UI shows the OD-missing error as if the welder typed nothing, which is confusing when they see digits on screen.
- **why it matters**: On a glove-fat-finger device, accidental double-decimal is common and the current UX makes it look like the calc is broken rather than the input being malformed. A test pinning this behaviour (or driving the fix toward a single-separator regex / explicit "invalid number format" error) protects users.
- **suggested fix**: Add a `group('input parsing edge cases')` in a new `orbital_tig_screen_test.dart` enumerating pathological inputs and asserting either a clear error message OR successful normalisation (whichever the team decides). Pin the contract.
- **effort**: S
- **round1Ref**: P1-30 (per-field error + sanity bounds — this test would lock in the fix once P1-30 lands)

--- end block ---

## Iter #40 · lib/screens/orbital_tig_screen.dart · test-coverage-gaps

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:357-398 (`_LevelRow`) and 400-429 (`_DataRow`)
- **issue**: The private `_LevelRow` and `_DataRow` widgets — each wrapping a `CopyOnLongPress` — have no golden / widget tests. There is no assertion that long-press on the L1-L4 amp readout actually invokes the clipboard with `amps.toStringAsFixed(0)` and label `L$level`, nor that `_DataRow` long-press copies the value with the label propagated. A regression where `CopyOnLongPress` is replaced with a non-interactive `Text` (e.g. during refactor) would slip through.
- **why it matters**: The long-press-to-copy gesture is the secondary copy path the welder uses when they only need one number (e.g. just the L3 vertical-up amps). Losing it forces them to copy the entire block and edit it on a phone with gloves — slow and error-prone.
- **suggested fix**: Add widget tests that pump `_ResultCard` with seeded `OrbitalEstimate` data, perform `longPress` on each level row + each data row, and assert `Clipboard.getData('text/plain')` returns the expected `toStringAsFixed(0)` amp value / formatted unit string.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #40 · lib/screens/orbital_tig_screen.dart · test-coverage-gaps

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:50-77 (`_calc` invoked from `onChanged` at line 322)
- **issue**: No test guards the recompute-on-every-keystroke behaviour. There is no assertion that typing "2", "5", ".", "4" in OD triggers four `_calc()` runs and that intermediate invalid states (e.g. "2" with empty wall) correctly suppress the result card and surface the wall-missing error rather than an OD-missing error. The error-message ordering is part of the implicit contract — a regression that re-orders the early returns would change which message the welder sees mid-typing.
- **why it matters**: Workshop UX hinges on predictable mid-typing feedback — the welder watches the result update live to ballpark amps before committing. Silent ordering changes ("wall missing" appearing when OD is empty) confuse the user into thinking the wrong field is at fault.
- **suggested fix**: Add a sequenced `tester.enterText` test that walks through OD-only -> OD+invalid wall -> wall>OD/2 -> valid, asserting the error message at each step and that `_ResultCard` appears only at the final step. Also covers the round-1 P1-19 debounce work (test would need to be rewritten if/when debounce lands — that is fine, lock in current behaviour first).
- **effort**: S
- **round1Ref**: P1-19 (debounce text-field recompute — test would baseline current behaviour ahead of that work)

--- end block ---

## Iter #40 · lib/screens/orbital_tig_screen.dart · test-coverage-gaps

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:84-86, 109, 230-238, 251, 258-260 (`context.tr(pl:..., en:...)` calls)
- **issue**: No bilingual locale test exists for `OrbitalTigScreen`. The screen has ~15 PL/EN translation pairs (AppBar title, warning banner, all input labels, error messages, result card titles, level names, geometry labels, copy button label, snackbar, tip card). Per CLAUDE.md the app is PL default with EN fallback via `context.tr`; if a developer adds a new field but forgets the `en:` arm, a locale test would catch the missing translation. Currently nothing locks the locale contract.
- **why it matters**: Round-2 audits keep flagging translation drift across calc screens. A snapshot/golden test per locale prevents regressions where a UK welder on the same site as a PL crew suddenly sees Polish strings, or vice-versa.
- **suggested fix**: Add two widget tests pumping the screen wrapped in an `AppLanguage` override (one for `pl`, one for `en`) and assert the AppBar title, copy button label, and at least one error message are localised. Optionally `matchesGoldenFile` for both locales.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #41 · lib/screens/pre_weld_checklist_screen.dart · backend-integration-edge-cases

- **severity**: high
- **location**: lib/screens/pre_weld_checklist_screen.dart:136-138, 152-162 (`_done` + `_material` are pure in-memory state; no persistence layer wired)
- **issue**: Zero persistence + zero audit trail. The checklist gates safety-critical actions (P91 PWHT booking, Duplex ferrite check, low-H electrode oven status), but the moment the OS kills the app for memory, the welder backgrounds it to read a WPS PDF, or the screen is rebuilt via Hot Reload, every tick is gone. There is no write-through to local storage (Hive/SharedPreferences/SQLite) and no upload to the PrzetargAI Railway backend (`/api/fitterwelder/*` route) that the rest of the app already reuses.
- **why it matters**: A QA inspector turning up the next morning has no record that the welder ticked "PWHT slot booked" or "ferrite check after cooldown" before joint X. If a weld fails post-PWHT and the question is "did you preheat?", the screen cannot answer. This is the exact use-case that justifies a checklist tool in the workshop and the current implementation cannot survive a phone reboot, let alone an audit. Also blocks the "weld log" integration that the rest of the app (job_add, weld map) implies exists.
- **suggested fix**: Persist `_done` + `_material.key` to Hive box keyed by current job/weld number (pull from job context if available, else timestamp); on the backend side, POST a snapshot `{weldId, materialKey, checkedItems[], completedAt, welderId}` to `/api/fitterwelder/checklists` when `all == true`; degrade to local-only when offline and replay on reconnect (use the same retry/queue pattern PrzetargAI uses for sync).
- **effort**: L
- **round1Ref**: new

--- end block ---

## Iter #41 · lib/screens/pre_weld_checklist_screen.dart · backend-integration-edge-cases (cont.)

- **severity**: high
- **location**: lib/screens/pre_weld_checklist_screen.dart:27-86 (`_pNumberExtras` map) vs lib/services/material_catalog.dart pNumbers {1, 3, 4, 5, 6, 8, 10, 42, 43}
- **issue**: Silent gap in P-Number coverage. The map only has entries for P-No {1, 4, 5, 8, 10, 43}. The catalog ships materials with P-No 3 (line 75), P-No 6 (line 115), and P-No 42 (line 190, likely Monel/Ni-Cu) that produce **zero** material-specific extras when picked. The screen renders a "Specific to <key>" divider only inside `if (_material != null && showDivider)`, but since `extras` is null/empty the divider is never shown either; the welder sees the picker chip "selected" with no visible change to the list and no warning that the grade-specific safety items are missing for the very steel in front of them.
- **why it matters**: P-No 3 needs preheat + filler match guarding similar to P-No 4. P-No 42 (Ni-Cu, e.g. Monel 400) has its own gas-purity and crevice-corrosion concerns that don't appear in the generic 11-point list. A welder who picks "A335 P3" trusting the chip turns "on" actually receives the same checklist as picking nothing; the chip becomes a confidence trap instead of a safety gate. This is integration drift between the data catalog and the checklist catalog (two sources of truth that aren't reconciled).
- **suggested fix**: Either (a) add `_pNumberExtras` entries for {3, 6, 42} from existing welding code references, OR (b) when `extras == null && _material != null`, show an amber banner "Grade-specific checks not available for P-No X — follow your WPS" so the welder knows the absence is real, not silently empty; add a unit test that asserts every `MaterialCatalog.all` `pNumber` exists in `_pNumberExtras` (or is on an explicit allowlist) so the next catalog addition cannot silently regress safety.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #41 · lib/screens/pre_weld_checklist_screen.dart · backend-integration-edge-cases (cont.)

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:164-171 (`_setMaterial` + `_done.removeWhere((i) => i >= _all.length)`)
- **issue**: Switching material does NOT clear ticks that overlap by index but mean different things. If the welder picks P-No 1 (extras start at index 11: "E7018 low-H oven", "Bevel 30° clean"), ticks indices 11-12, then changes mind to P-No 10 Duplex, indices 11-12 are now "Interpass MAX 150°C" + "Backing gas Ar + 2% N2". The two indices stay in `_done` because they are `< _all.length`, so the welder sees Duplex-critical items **pre-ticked** without ever having confirmed them.
- **why it matters**: This is the worst kind of checklist bug: it falsely affirms a safety check the welder never made. Misreading "interpass MAX 150°C" as already verified on a Duplex 2205 joint is exactly the kind of error that causes sigma-phase formation and field failure. The chip change is a soft event for the user (just trying a different material) but a hard event for the data integrity of the check state.
- **suggested fix**: On material change, also `_done.removeWhere((i) => i >= _checks.length)` (clear ALL extras, not just out-of-range), or store ticks as a `Set<String>` keyed by check text/hash instead of index so they survive list reshuffles correctly. Add a debug assertion that ticked extras' check texts match the new material's extras list when transitioning.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #41 · lib/screens/pre_weld_checklist_screen.dart · backend-integration-edge-cases (cont.)

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:117-127 (`_preheatFahrenheit`) + line 258-259 (Tooltip.message built every frame)
- **issue**: Tooltip message is recomputed via regex on **every build** for **every material chip** in the horizontal list (16+ materials x every setState). There is no memoization (`Map<String, String> _fCache`), no precompute at catalog build time, and crucially no fallback when the regex matches a number that is NOT a Celsius temperature (e.g. a preheat note that ever included a pressure value like "100 bar" — `_preheatFahrenheit` would happily convert 100->212 °F). The function trusts that every integer near "°C" actually IS a Celsius value.
- **why it matters**: Hot path lag on a glove-tap-and-hold gesture is annoying but recoverable; a Fahrenheit conversion that silently misreads a non-temperature integer prints WRONG safety guidance to a welder cross-reading EU vs ASME specs. The current `MaterialCatalog` notes happen to be clean, but the integration contract between catalog text and tooltip math is "trust the string" with no schema. The fix-effort gap will widen as more grades land.
- **suggested fix**: Move preheat to structured fields on `MaterialSpec` (`preheatMinC`, `preheatMaxC`, `interpassMaxC` as `int?`), derive both °C and °F at compile-time, and keep `preheatNote` only as a display fallback; meanwhile cache `_preheatFahrenheit` results in a `static final Map<String,String>` keyed by the input note.
- **effort**: M
- **round1Ref**: new (related to BACKLOG line 209 about heat-input/Fahrenheit tooling but specifically about the integration contract, not the UI sweep)

--- end block ---

## Iter #41 · lib/screens/pre_weld_checklist_screen.dart · backend-integration-edge-cases (cont.)

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:175 (`final isPl = context.language == ...`) -> drives 354 (`isPl ? c.pl : c.en`) for every row
- **issue**: Language is resolved at build time and applied to live text, fine for the visible list, BUT when the screen eventually syncs to the backend (see first finding) or is shared as a screenshot to a foreman, there is no captured language metadata. A Polish welder ticks "Drut/elektroda zgodna z B-grade", the German foreman views the synced record in English: there is no guarantee the text he sees ("Filler matches B-grade...") is **the same translation that was on screen when ticked** if the `_Check` catalog ever evolves. No versioning of the checklist itself.
- **why it matters**: Multi-language workshops (PL welder + DE foreman + EN auditor, common in EU offshore/petrochem) need provable equivalence: "what did the welder see when he ticked this?" Without check IDs + a versioned catalog the answer is "the current code on whatever app version they had". An update that rewords "Bevel 30° clean" to "Bevel 37.5° verified" silently rewrites historical records.
- **suggested fix**: Give each `_Check` a stable `id` (string slug or int), include a `version` constant for the checklist catalog, and persist `{checkId, version, languageAtTickTime}` so the backend can re-render the exact text shown at tick time; show the language in the AppBar (PL/EN badge) so welder + auditor are on the same page.
- **effort**: M
- **round1Ref**: new

--- end block ---

## Iter #41 · lib/screens/pre_weld_checklist_screen.dart · backend-integration-edge-cases (cont.)

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:143-150 (`get _all` builds a fresh List on every read) — called from build (line 176), `_toggle` (line 161), `_setMaterial` (line 169), and itemBuilder count (line 276)
- **issue**: `_all` rebuilds the combined list on every getter access — at minimum 4 times per `_toggle`, plus once per item in `itemBuilder` if iter counts are recomputed. Not a correctness bug yet, but as `_pNumberExtras` grows (currently 6 P-Nos, will grow to cover all 9 in catalog) and the universal `_checks` list grows past 11, this is hot-path work on the UI thread under glove input. Also: there is no defensive null check on `_material!.pNumber` lookup beyond the `extras != null` guard, if a future catalog change adds `pNumber: -1` (placeholder/unknown), the map silently returns null and the welder gets an incomplete list with no warning.
- **why it matters**: This is the integration boundary between catalog data and runtime UI. Tightening it costs almost nothing now; finding it after a perf regression on a glove-tap is harder. Workshop phones are mid-range Androids, not iPhones, list rebuilds on every setState() matter.
- **suggested fix**: Cache `_all` as `List<_Check>? _allCache` invalidated only in `_setMaterial`; assert in debug mode that `_material!.pNumber > 0`.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #42 · lib/screens/elbow_takeout_screen.dart · state-consistency-after-error

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:37-50 (`_rows` getter cache update order)
- **issue**: `_cachedQ = _q;` is assigned on line 39 BEFORE `_cachedRows` is rebuilt on lines 42 or 44-47. If `kElbowTakeouts.where(...).toList()` ever throws (today impossible because `kElbowTakeouts` is a const list of plain data; tomorrow possible if the data source migrates to a generated/lazy list, JSON-backed asset, or includes a row with a null/non-string `nps`), the cache lands in a torn state: `_cachedQ` advertises "computed for current `_q`" while `_cachedRows` still holds the previous query's result. The next rebuild short-circuits at line 38 (`_cachedQ == _q`) and silently shows stale rows forever (until `_q` changes again to something else).
- **why it matters**: Fitter searches `DN200`, screen briefly errors during the filter walk, then they type `DN150` and the list shows results that no longer match — they might cut to the wrong takeout dimension because the displayed row IS labelled `DN150` but came from a stale filtered set. Very unlikely today but a latent trap for the cheapest possible refactor.
- **suggested fix**: Compute `final next = q.isEmpty ? kElbowTakeouts : kElbowTakeouts.where(...).toList();` first, THEN assign both `_cachedRows = next; _cachedQ = _q;` atomically at the end of the getter.
- **effort**: S
- **round1Ref**: new (latent — no symptom today, hardens against future data-source swap)

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:88-94 (ListView when `_rows` is empty)
- **issue**: When the filter excludes every row (e.g. fitter mistypes `DN5O` with letter O, or searches `100"` and no NPS matches), `ListView.builder` renders an empty Expanded — no placeholder, no "Brak wyników / No results" hint. From a state-consistency-after-error standpoint, the legend bar stays visible suggesting data IS there, while the body is blank. The user cannot distinguish "I mistyped" from "this dataset has no DN5000" from "the app crashed silently".
- **why it matters**: On a noisy/cold workshop site the fitter assumes the app is broken, force-closes it, loses any clipboard value queued for the foreman SMS. Small daily-friction symptom, not a data-integrity bug.
- **suggested fix**: If `_rows.isEmpty && _q.isNotEmpty`, render a centered muted `Text(context.tr(pl: 'Brak dopasowań dla "$_q"', en: 'No matches for "$_q"'))` instead of the empty list.
- **effort**: S
- **round1Ref**: new (UX-level state cue, not P0/P1)

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:210-228 (`_Cell` uses `CopyOnLongPress` → lib/utils/clipboard_helper.dart:14 `Clipboard.setData` unguarded)
- **issue**: Long-press on a takeout cell awaits `Clipboard.setData` without a try/catch (helper file, but this screen is the consumer). On a device where the clipboard channel throws (rare: Android work-profile clipboard restrictions, iOS Universal Clipboard hand-off failure, ChromeOS sandbox), the future rejects: `Haptic.copied()` never fires, the snackbar never appears, and the fitter assumes the value WAS copied. They paste an old/empty value into the foreman SMS — wrong centre-to-face goes to the saw. The elbow screen itself has no local error state to keep consistent, but the user-perceived state ("did the copy succeed?") is silently desynced.
- **why it matters**: Centre-to-face values are the headline product of this screen — a silently-failed copy is the only realistic data-integrity failure mode for a read-only reference table.
- **suggested fix**: Wrap `Clipboard.setData` in try/catch in `clipboard_helper.dart`; on catch show an error snackbar ("Nie udało się skopiować — sprawdź uprawnienia") and skip haptic. Out of scope for this file, but record the consumer linkage.
- **effort**: S
- **round1Ref**: new (cross-file — clipboard helper, this screen is one of ~6 consumers)

--- end block ---

## Iter #43 · lib/screens/cut_list_summary_screen.dart · concurrency-races

- **severity**: high
- **location**: lib/screens/cut_list_summary_screen.dart:43-76 (`_load()` final `setState` at lines 69-75)
- **issue**: `_load()` is invoked from `initState` (line 98) and awaits TWO DAO calls (`getById`, `listForProject`) plus a synchronous nesting pass, then calls `setState(...)` at line 69 with NO `mounted` check. If the user opens the Cut List, sees it spin, and pops back to the project screen before SQLite returns (cold DB on a cheap Android can be 200-800 ms), the State has been disposed; `setState` after dispose throws `setState() called after dispose()` and the error is silently swallowed in release but crashes a debug/Codemagic build verification run. Worse: there is no guard against `_load()` being re-entered, so any future call (e.g. a `RefreshIndicator` added later, a `didChangeDependencies` retrigger) would let two concurrent loads race - the slower one would clobber the newer state (`_project`, `_segments`, `_groupPlans` all reassigned out of order). The first `setState(() => _loading = true)` at line 44 is fine (we are mounted), but the second one is not.
- **why it matters**: A fitter on a 4-year-old Moto E with stale SQLite cache opens the Cut List for a 200-segment ISO and immediately taps back - the app crashes mid-session, losing whatever was unsaved on the previous screen (job notes, weld-journal row not yet flushed). On WPS-audit day this looks like "the app eats my data" to the QC inspector standing next to him.
- **suggested fix**: Wrap the final `setState` in `if (!mounted) return;` AND set a `bool _loadInFlight = false;` guard at the top of `_load` (`if (_loadInFlight) return; _loadInFlight = true; try { ... } finally { _loadInFlight = false; }`); also bump a `_loadGeneration` int and bail if the generation that finished is not the latest.
- **effort**: S
- **round1Ref**: new (P1-26/P1-28 cover UX of export buttons, not the load lifecycle)

- **severity**: high
- **location**: lib/screens/cut_list_summary_screen.dart:78-93 (`_exportPdf`) - IconButton at line 117-121
- **issue**: `_exportPdf` is gated only by the visual swap between `IconButton` and `CircularProgressIndicator` based on `_exporting`. Between tap-1 and the next frame pump (~16 ms on 60 Hz, longer if the UI is jank-y from the nesting algorithm running in `_GlobalSummary.build` - see separate finding), a double-tap on the AppBar PDF button fires `_exportPdf` TWICE before the first `setState(() => _exporting = true)` repaints. Two concurrent `PdfExportService.exportCutList` futures run, both touch the same temp `.pdf` file under the OS cache dir, both call `Share.shareXFiles` (or whatever the service does internally). The slower one overwrites the file the faster one already handed to the share-sheet, so user gets corrupted PDF, or share-sheet opens twice, or one Future throws a `FileSystemException` whose error is mapped into the `catch` block (line 84) and shows a misleading "PDF blad" snackbar even though the OTHER PDF succeeded.
- **why it matters**: Welder rage-taps the PDF icon (workshop gloves, capacitive screen lag) - gets a corrupted PDF emailed to the QC inspector or two share-sheets stacked. On iOS this is reproducible because UIDocumentInteractionController will fail the second presentation. The "did my PDF actually export?" anxiety is exactly the trust-failure mode P1-28 was about, but the underlying race is separate.
- **suggested fix**: At the top of `_exportPdf`, add `if (_exporting) return;` BEFORE any await; keep the `_exporting` flag as the single source of truth and let the UI follow. Optional: synchronously call `Haptic.tap()` on entry so the user gets feedback even before the first frame.
- **effort**: S
- **round1Ref**: P1-28 (touches the same buttons but for disabled-when-empty semantics, not re-entrancy)

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:78-93 (`_exportPdf` `catch`/`finally` blocks at lines 84-92)
- **issue**: `_exportPdf` reads `_project` and `_segments` from `this` state, holds them across an await (`PdfExportService.exportCutList`). If a future code path triggers `_load()` (a pull-to-refresh, a deep-link callback re-mounting the screen, a `setState` from a subscribed stream), `_segments` field gets reassigned to a NEW list while the OLD list is still being iterated inside `PdfExportService` on another microtask. Dart hands references at call-time so the export sees a stable list reference, BUT if the export ever calls back into widget state (e.g. progress callbacks via a `ValueNotifier`), the snapshot drift creates a subtle "the PDF shows segments that are not in the table anymore". Same applies to `_share` / `_copyCsv` which read `_groups` across the `await Clipboard.setData` and `await Haptic.copied()` awaits at lines 257-258 and 270-271 - though those builders are synchronous, the awaits run AFTER the string is built, so on its own this one is benign today. The export path is the live risk.
- **why it matters**: Pre-empts a class of "stale data in exported artefact" bug the moment any background refresh is wired up. Foreman receives a PDF dated to a project state that does not match what is on screen - a QA-audit smell.
- **suggested fix**: Snapshot `_project` and `_segments` into local `final` vars (`final p = _project; final segs = List<Segment>.unmodifiable(_segments);`) at the start of `_exportPdf`, and pass `segs` to the export service. Same defensive copy pattern for `_buildTextSummary` / `_buildCsv` if they ever go async.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:78-93 (`_exportPdf` `catch` at line 84, `finally` at line 90)
- **issue**: The `catch` and `finally` both gate on `if (mounted)`. If the export future is still running when the screen is popped, the `finally` correctly skips `setState`. BUT - `_exporting` field stays `true` forever on the disposed State (object survives until GC). If the user re-navigates to the same Cut List (a new `_CutListSummaryScreenState` instance is constructed, so this is not a leak for THAT state), no problem. However, the orphaned Future running `PdfExportService.exportCutList` keeps writing temp files / touching the share channel; on iOS, this can leak a UIDocumentInteractionController and on Android can collide with the next export's temp filename if the service uses a deterministic name (e.g. `cut_list_${projectId}.pdf`).
- **why it matters**: Re-opening the Cut List of the same project, hitting export again before the orphan finishes: two writers on the same path, the share-sheet shows half-written content. Reproducible if the export service serialises by `project.id`.
- **suggested fix**: Pair the export future with a `CancelableOperation` (from `package:async`) and cancel it in `dispose()`. Minimum: cancel the share-sheet presentation on dispose. Long-term: move PDF generation to an `Isolate` and kill it in dispose.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:95-99 (`initState` -> `_load`) and the absence of any `didChangeDependencies` / lifecycle hook
- **issue**: `_load()` fires once in `initState` and never again. If the upstream `projectId` changes via a parent `setState` that swaps widget identity (it does not today because the constructor takes `projectId` as `final` and routes always push a new screen), no problem. BUT - there is no `didUpdateWidget` override; if a future refactor changes the parent to reuse the same `_CutListSummaryScreenState` with a new `widget.projectId` (Flutter does this if the `Key` matches), the screen would silently show the OLD project's cut list with the NEW project's id in `widget.projectId`. Worse, if a parent does call `setState` with a new projectId AND the screen reloads from a tab swap, the old `_load` Future may still finish AFTER the new one (race), overwriting the new data with stale data for the old project. There is no per-load generation counter.
- **why it matters**: Defensive - today no caller does this, but the moment Cut List becomes a tab in a `BottomNavigationBar` for a multi-project dashboard, the data-mixing bug is silent and dangerous. Wrong cut list to the saw operator = wrong material to the welder.
- **suggested fix**: Add `int _loadGen = 0;` field. In `_load`, capture `final gen = ++_loadGen;` before the awaits; after the awaits check `if (gen != _loadGen || !mounted) return;` before `setState`. Also override `didUpdateWidget` to re-trigger `_load` when `widget.projectId` changes.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:255-266 (`_share`) and 268-279 (`_copyCsv`)
- **issue**: `_share` calls `await Clipboard.setData(...)` then `await Haptic.copied()` then `ScaffoldMessenger.of(context).showSnackBar`. There is a `if (!context.mounted) return;` check between the awaits and the snackbar, which is correct. BUT - the IconButton has no debouncer; if the user double-taps "Kopiuj tekst" while the first `Clipboard.setData` is in-flight (rare but possible on cold MethodChannel start), two snackbars stack and two clipboard writes race. Last-write-wins on the clipboard, so functionally OK, but the second snackbar appears AFTER the first dismisses, causing the welder to see "Skopiowano" twice and wonder which copy is in the clipboard. Same applies to `_copyCsv` - and worse, if the welder taps Share THEN CSV within 100 ms (intending to share, mis-tapped CSV), the CSV may land in the clipboard last while the snackbar still says "Skopiowano do schowka" (text), making them paste CSV into an SMS thinking it is the human-readable summary.
- **why it matters**: A fitter pastes raw `;`-delimited CSV into a WhatsApp message to the foreman who cannot read it. Trust hit, even if cosmetic.
- **suggested fix**: Add a single `bool _copyInFlight = false;` guard reused by both `_share` and `_copyCsv`; on entry `if (_copyInFlight) return;`, in `finally` reset. Tag the snackbar with `ScaffoldMessenger.of(context).hideCurrentSnackBar()` before showing the new one so messages do not pile.
- **effort**: S
- **round1Ref**: new (P1-26 covers ShareResult feedback, not the inter-button race)

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:341-413 (`_GlobalSummary.build`) - also lib/screens/cut_list_summary_screen.dart:206-219, 228-251 (`_buildTextSummary`, `_buildCsv`)
- **issue**: Three independent code paths recompute `nestCutsToBars` on every build (`_GlobalSummary.build` at line 354) and on every export tap (`_buildTextSummary` line 212, `_buildCsv` line 233) - none of them read the already-memoised `_groupPlans` field that `_load()` populates at line 54-66. If `_load()` finishes, repaints with `_groupPlans` filled, but then the user rapidly orientation-changes the device (or a soft-keyboard appears for the snackbar input), `_GlobalSummary` re-runs `nestCutsToBars` on the UI thread for every group EVERY FRAME. Concurrency angle: if a user taps "Eksport PDF" while the device is mid-rotation, the PDF generation Future, the share Future, and the synchronous `_GlobalSummary.build` recomputation all run on the same root isolate event loop; the build chews the frame budget, the PDF future starves, the `_exporting` snackbar takes 600+ ms to appear - looks like a freeze, user double-taps (see re-entrancy finding above), and the race chain compounds.
- **why it matters**: Multi-megabyte SQLite + 500-segment ISO + rotation = visible freeze, fitter blames the app, calls support, opens the saw-operator's cut list manually (defeats the whole point).
- **suggested fix**: `_GlobalSummary` should accept the pre-computed `_groupPlans` map (or a derived `totalBars/totalCutMm/totalWasteMm` triple) from the parent; `_buildTextSummary` and `_buildCsv` should iterate `_groupPlans.entries` instead of re-calling `nestCutsToBars`. This kills the race vector by making the synchronous work O(segments) instead of O(segments x bar_packing).
- **effort**: M
- **round1Ref**: new (touches perf + concurrency; intersects with the cached `_GroupPlan` introduced earlier but never propagated to consumers)

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:30-41 (no `dispose` override on State)
- **issue**: `_CutListSummaryScreenState` has no `dispose()` override. The DAOs (`_projectDao`, `_segmentDao`) are bare singletons (likely) so no streams to cancel - but if a future refactor adds a `Stream<List<Segment>>` subscription (common pattern when segments become live-updated from another tab), there is no place to cancel it. Currently benign, but the absence of `dispose` means the `mounted` checks are the only defence against post-dispose `setState` - and as noted, `_load`'s final `setState` does not check `mounted`. The class is one stream-subscription away from a leak.
- **why it matters**: Defensive - a regression-bait. Reactive-data refactor (D-014 style) would silently leak listeners.
- **suggested fix**: Add `@override void dispose() { /* cancel any future subscriptions */ super.dispose(); }` now as a stub. Document the contract.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: high
- **location**: lib/screens/material_list_screen.dart:147-153
- **issue**: Single-column `ListTile.title` concatenates `"$catLabel  -  ${it.description}"` into one TextSpan that grows arbitrarily long (full pipe descriptions like "RURA DN150 SCH40 304L PN16 ASTM A312 TP304L cold-drawn 6m") and visually competes for width with the `trailing` length/qty. With Material's default `ListTile` text scaling honoring system font (welders with reading glasses bump to 1.3-1.5x), the title ellipsis chops the very spec (DN/Sch/grade) the warehouse needs, while the trailing length is preserved. Worse, there is NO visual hierarchy: category code ("RURA"/"ELB90"/"TEE") shares font weight and color with description, so eye-skim down the column to find pipes vs fittings is slow.
- **why it matters**: Fitter standing at the rack reading the BOM on a sweaty phone needs the category as a glanceable "column" - currently it's just the first word of a wall of identical-weight text. Truncated descriptions make the welder phone the office for the spec.
- **suggested fix**: Replace `title` with a two-line layout: `title: Row` with a fixed-width 56-72px `Container` rendering `catLabel` chip-style (mono, bold, bordered, color-coded PIPE=blue / ELB90=orange / TEE=green / valve=red), and `subtitle: Text(it.description, maxLines: 2, overflow: TextOverflow.ellipsis)`. Move trailing into a 92-px right column with `textAlign: TextAlign.end` and `fontFeatures: [FontFeature.tabularFigures()]` so "12.345 m" and "8 szt." line up vertically.
- **effort**: M
- **round1Ref**: extends P3-10 (BOM rows) and P1-09 (InkWell+haptic) - adds layout/hierarchy dimension not covered by either

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: high
- **location**: lib/screens/material_list_screen.dart:79-154 (whole body)
- **issue**: There is NO summary / aggregate row at the top or bottom of the BOM. The list shows N rows but the fitter has no glanceable "Suma rur: 12 poz, 84.500 m - Suma kolan: 23 szt - Suma trojnikow: 5 szt" - they have to scroll the entire list and add in their head to brief the warehouse over the phone ("how many 90 degree elbows do I need?"). The empty state shows a hint chip but the populated state shows none of: total pipe length, total fittings count, item count, project name, or generation timestamp ("BOM zbudowane na podstawie 47 segmentow, 2026-06-08 14:32").
- **why it matters**: Warehouse phone call is the #1 friction moment ("ile metrow rury DN50 schedule 40?" - fitter has to scroll, count, hold phone with shoulder, count again). The same screen that should serve the call shows zero aggregate.
- **suggested fix**: Add a sticky `Container` header below AppBar (or pin via `SliverPersistentHeader`) showing 3 KPI tiles: total pipe meters (sum of `totalLengthMm` for PIPE rows), total fittings (sum of `quantity` for non-PIPE), and item count. Below, in subtitle row, the project name + "wygenerowano: HH:mm". Format meters with tabular figures and PL/EN unit.
- **effort**: M
- **round1Ref**: new - neither P1-10 nor P3-10 cover aggregate KPI surface

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: high
- **location**: lib/screens/material_list_screen.dart:134-154 (ListView without grouping/sorting/filtering)
- **issue**: `ListView.separated` renders items in the raw order returned by `_builder.buildForProject(pid)` with no grouping by category, no sort, no search/filter, and no section headers. On a realistic spool BOM (40-80 rows) the fitter sees PIPE rows interleaved with ELB45, ELB90, TEE, FLG, VLV - finding "all DN80 schedule 40 pipes" requires linear eyeballing. There's no sticky category divider, no per-category collapse, no `TextField` to filter by description, and no way to jump to "PIPE" from the bottom of a long list.
- **why it matters**: Welder cuts pipes in one batch then fits elbows - they want PIPE group first, then ELB grouped, then TEE/FLG. Today they thumb-scroll back and forth, lose place, mis-order materials.
- **suggested fix**: Group `_items` by `category` post-load (memoized), render `ListView` with section headers (`Material` + `Padding` + `Text(catLabel + ' (n)')` + small Suma length/qty for the section). Add `SliverAppBar.large` with a `bottom: PreferredSize` hosting a search `TextField` filtering on description + category; add `Chip` row at the top with category toggles ("Wszystko / Rury / Kolana / Trojniki / Kolnierze"). For long lists, `Scrollbar(thumbVisibility: true)`.
- **effort**: L
- **round1Ref**: new - adjacent to P1-10 (empty state nuance) but covers structuring populated state, which round 1 did not flag

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:64-70, 147-152 (units presentation)
- **issue**: PIPE rows render only meters (`_fmtLen` -> "12.345 m") to 3 decimals; non-PIPE rows render only count ("8 szt."). Two issues for the shop floor: (1) `12.345 m` to 1/1000 m precision is meaningless when the saw graduation is 1 mm - and the welder cannot eyeball whether "12.345" means twelve metres or twelve-point-three-four-five. PL convention uses comma as decimal, not dot - `toStringAsFixed` always emits `.` regardless of locale, so the welder sees a "thousands separator" that isn't one. (2) Pipe rows hide the more useful representation: number-of-sticks-needed-at-6 m + offcut. (3) For non-PIPE rows there's no "DN/size + count" - the description does the work but a fitter who wants "5x DN80 ELB90 SR" sees only the count.
- **why it matters**: PL fitter under workshop lights reads `1.234 m` as "thousand two hundred thirty four metres" for a half-second; ambiguous decimal-separator causes a real ordering mistake (request 12 m of pipe, receive 12345 mm = 12.3 m, OK; request 1.5 m, receive 1500 m, disaster).
- **suggested fix**: Use `NumberFormat.decimalPattern(localePl ? 'pl_PL' : 'en_US')` from `intl`; render meters with 2 decimals + raw mm in parentheses for <= 10 m parts ("1,500 m  (1500 mm)"). For PIPE rows append "~ N szt. po 6 m + 0,4 m" hint (cuts-per-stick estimate). For fittings, show "qty unit" with the DN extracted from description as the prominent token.
- **effort**: M
- **round1Ref**: new - round 1 P1-10 only nudged at empty state; numeric-format pitfalls not flagged

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:79-154 (no actions on populated state)
- **issue**: There is ZERO action affordance on the populated BOM: no Export PDF, no Copy whole list, no Share, no Refresh, no Print, no Filter/sort toggle, no Edit-segment shortcut, no "Generuj zapotrzebowanie do magazynu". `AppBar.actions` carries only `HelpButton`. The welder ends every BOM session by switching to ISO scanner / weld journal / OS share-sheet to recover the data - every escape hatch is outside this screen. P1-32 (round 1) calls for AppBar share IconButton but doesn't enumerate the full action set: there's no FAB or bottom bar.
- **why it matters**: BOM is the natural hand-off artifact (welder -> warehouse -> buyer). With no in-screen "export/share" the welder screenshots the list (loses copy/paste) or types it manually into WhatsApp.
- **suggested fix**: Add (a) `AppBar.actions`: `IconButton(refresh)`, `IconButton(share)`, `IconButton(filter_list)` (toggles search bar); (b) `FloatingActionButton.extended` "Wyslij" using `share_plus` with a generated PDF (reuse the existing PDF service patterns from iso_notebook/cut_list_summary); (c) bottom `SafeArea` with `Row` of secondary actions "Kopiuj liste / Eksport PDF / Drukuj". Wire `ClipboardHelper.copyWithToast` for the whole list.
- **effort**: L
- **round1Ref**: extends P1-32 (AppBar share) and P3-10 (per-row copy) - but flags the missing FAB + filter bar + PDF/print, which round 1 did not consolidate

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:99-129 (empty state coaching card)
- **issue**: The amber "Try this" coaching card is hard-coded inside the empty branch and (a) shows every single time the BOM is empty - repeat sessions of an experienced welder who just deleted segments will keep seeing the toddler-tutorial; (b) has no CTA button (just text) - the user must mentally navigate "go to ISO/Notatnik" with no `OutlinedButton(onPressed: Navigator.pop)` shortcut; (c) the title row uses `letterSpacing: 0.5` on 11-pt bold which under workshop lighting / safety glasses borders on illegible (very tight, very small); (d) the entire empty body lives inside `Padding(all: 24)` + `Column` - at landscape on a 5" phone the Container can overflow vertically (no `SingleChildScrollView`).
- **why it matters**: Coaching that annoys experienced welders + lacks a CTA wastes the most useful prompt moment in the flow ("no BOM -> take me to where I add segments").
- **suggested fix**: (a) Wrap empty body in `SingleChildScrollView`; (b) gate the coaching card behind `prefs_seen_bom_coaching_v1` flag, dismissed on a small "x" / "Rozumiem"; (c) add a primary `FilledButton.icon(Icons.edit_note, 'Otworz ISO/Notatnik')` that pops back to the project menu or pushes the notebook with this projectId; (d) bump title from 11->13 pt and drop `letterSpacing` to 0.2.
- **effort**: S
- **round1Ref**: extends P1-10 (empty-state nuance) - round 1 only noted the missing-pid vs empty-segments split; persistent-tutorial + no-CTA + landscape-overflow are new dimensions

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:79-80 (loading indicator), 134-154 (no skeleton), 38-62 (no try/catch in `_load`)
- **issue**: Loading state is a bare `CircularProgressIndicator` centered on a blank screen. For a BOM that depends on `SegmentDao + ComponentLibraryDao + builder` on cold start with 100+ segments, the spinner can sit for >1 s with no context - under workshop lighting + safety visor a small theme-coloured spinner against dark scaffold is barely visible. There's no skeleton (ghost rows) hinting at the imminent list structure, no "Buduje liste... (n segmentow)" subtitle, and no timeout/error path: if `_builder.buildForProject(pid)` throws, the screen will exception out (no try/catch in `_load`) and the welder sees a Flutter red error screen on the shop floor.
- **why it matters**: A welder who taps "Lista materialowa" and sees a blank screen for 2 seconds, then suddenly a list, has no signal of progress; if the build crashes silently they re-tap and re-tap.
- **suggested fix**: (a) Wrap `_load` body in `try { ... } catch (e) { if (mounted) setState(...) }` and render a friendly retry state; (b) replace spinner with 6 shimmer/ghost `ListTile`s (or `LinearProgressIndicator` at top + `Skeletonizer`); (c) add subtle "Buduje BOM..." caption under the indicator with `Theme.of(context).textTheme.bodyMedium`.
- **effort**: M
- **round1Ref**: new - round 1 did not flag missing error handling or skeleton loading on BOM

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:147-153 (Divider height: 0, no row affordance)
- **issue**: `Divider(height: 0)` collapses rows visually too tightly for gloved thumb targeting (44pt Apple HIG / 48dp Material minimum is borderline). The `ListTile` has no `onTap`, no `onLongPress` - so a curious tap does nothing (no indication the row is read-only). There is also no Theme'd dense option, no zebra striping for outdoor readability, and no `selected` state for row that was last copied. No `Semantics` label for screen reader / TalkBack ("RURA DN80 SCH40, 12 metrow 345 milimetrow") - accessibility is dead on this screen.
- **why it matters**: Welder thumb-taps a row trying to copy, nothing happens - they tap harder, longer, eventually swipe - every wasted gesture is friction on a phone they hold in nitrile gloves.
- **suggested fix**: Replace bare `ListTile` with `Material(child: InkWell(onTap, onLongPress, child: ListTile(dense: false, minVerticalPadding: 12)))`; add `Divider(height: 1, color: ... withAlpha(0.08))`; alternate row tint `Colors.white.withAlpha(0.02)` on even rows for stripe; add `Semantics(label: 'Kategoria $catLabel, opis: ...')`.
- **effort**: S
- **round1Ref**: extends P1-09 (InkWell+haptic) - but accessibility, stripe, and selection-state dimensions are new

--- end block ---

## Iter #44 · lib/screens/material_list_screen.dart · ux-layout-deeper

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:75-78 (AppBar title/actions)
- **issue**: AppBar title is `"Lista materialowa (BOM)"` - the parenthetical "(BOM)" is engineer-jargon and on a small phone the title may itself ellipsize the PL word. There is no `subtitle` / project context - when a welder has 3 active projects the BOM AppBar gives no hint which project's BOM they're viewing. `HelpButton` is the only action; no `backgroundColor`, no project-color stripe, no count badge ("47 pozycji"). On large-system-font users (1.3x), the AppBar title may collide with the help icon.
- **why it matters**: Confused-project errors are real: welder pulls BOM, calls warehouse "DN50 elbows", warehouse ships them, only to discover the BOM was for a different project still open from yesterday.
- **suggested fix**: Render `AppBar(title: Column(children: [Text('Lista materialowa', maxLines: 1, overflow: ellipsis), Text(projectName ?? 'Projekt: $pid', style: Theme.of(context).textTheme.labelSmall)]))` after fetching project name in `_load`; drop "(BOM)" from title (move to subtitle as "n pozycji - BOM"); fetch project name from a `ProjectDao` or accept via constructor.
- **effort**: M
- **round1Ref**: new - round 1 did not surface project context on AppBar

--- end block ---

## Iter #45 · lib/screens/quick_converter_screen.dart · input-validation-deeper

- **severity**: high
- **location**: lib/screens/quick_converter_screen.dart:53-56 (`_parse`), 176, 264, 355, 438 (FilteringTextInputFormatter regex on all 4 tabs)
- **issue**: The `[0-9.,]` whitelist (and `[\-0-9.,]` on temp) permits multiple decimal separators (`12,5,5`, `1.2.3`), trailing separator (`12,`), leading minus mid-string (`5-3` on temp), and multiple minuses (`--5`). All silently fail `double.tryParse` → `_parse` returns null → the `_Card` with results just disappears. The fitter sees an empty screen and cannot tell whether they are mid-typing, the regulator number is invalid, or the app is broken. Worst case: on a noisy job site they assume the tool is "stuck" and walk away with a wrong manual conversion (psi→bar gas-bottle pressure off by ~14x).
- **why it matters**: Real input on PL keyboards under gloves: comma vs dot mistakes are constant; PDF copy-paste of `12,5,0 mm` (some specs use comma as thousands sep too) silently kills the screen. No error feedback = silent wrong work.
- **suggested fix**: In `_parse`, after replace, check `RegExp(r'^-?\d*([.]\d*)?$').hasMatch(...)`; expose `_ParseState { value, error }`; when invalid show inline `errorText: 'Sprawdź format (np. 12,5)'` instead of vanishing the card.
- **effort**: M
- **round1Ref**: P3-01 (round-1 only added helperText/hintText cosmetic; root validation gap unaddressed) + parallels P0-12 ISO parser char-normalization

- **severity**: high
- **location**: lib/screens/quick_converter_screen.dart:162-163 (length), 341-342 (pressure), 424-425 (flow)
- **issue**: No upper-bound clamp on parsed input. Fitter typing `9999999` mm (thumb-fumble of `999`) yields `9999.999 m` and `393700 in` — astronomical numbers rendered as plain text with no sanity hint. Same on pressure: `9999 psi` reads `689.5 bar` (rupture pressure of most pipework) without a red flag. This is the exact bug class P0-03 patched in iso_scanner (AI clamp 0-100000) and that Iter #1 round-2 flagged as still open in iso_notebook. Quick-converter has the same shape.
- **why it matters**: A misread saw measurement copied into the converter that quietly returns 9.99 km of pipe stock invalidates a quote or, on hydrotest pressure entry, primes a downstream calculator with a destructive number. No "Sprawdź wartość" warning anywhere.
- **suggested fix**: Per-tab sanity ceiling (length 100 m, pressure 2000 bar, temp 5000 °C, flow 1000 l/min) — above threshold render an orange `_SmallHint` "Sprawdź wartość — typowy zakres do X" but still show the conversion.
- **effort**: S
- **round1Ref**: P0-03 (parallel — quick_converter is the third screen with the same uncapped-input pattern)

- **severity**: med
- **location**: lib/screens/quick_converter_screen.dart:232-249 (`_TempTabState.build`)
- **issue**: Kelvin-below-zero is correctly flagged, but the physically equivalent inputs are NOT: `°C` < -273.15 and `°F` < -459.67 also map to sub-absolute-zero Kelvin yet the card happily computes and renders `k = -300 + 273.15 = -26.85 K` as a result row. A welder doing preheat math who fat-fingers `-2730` °C sees a card with three numbers and no warning — the K row alone is physically nonsense.
- **why it matters**: Preheat / interpass temperatures are safety-relevant per WPS. Silent display of impossible Kelvin values undermines the user's check ("if K is weird, my input was weird"). Inconsistency with the K-negative rule is also a usability surprise.
- **suggested fix**: Extend the guard: `final cBelowAbs = v != null && _src == '°C' && v < -273.15; final fBelowAbs = v != null && _src == '°F' && v < -459.67;` — combine into one `belowAbsoluteZero` flag driving the same errorText branch.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/quick_converter_screen.dart:341-342 (`_PressureTabState`), 424-425 (`_FlowTabState`)
- **issue**: Negative values are physically impossible for absolute gas pressure and mass flow, but only the temp tab whitelist excludes `-`. Pressure/flow regex `[0-9.,]` already blocks the literal minus, BUT paste bypasses inputFormatters for some IME paths on iOS and Android API <30 (known Flutter quirk on `TextInputType.numberWithOptions(decimal: true)` — pasted clipboard content is processed before the formatter on certain IMEs). A clipboard value of `-1.5` from another app slips through, `_toBar[_src]!` happily multiplies, and `_Row` renders negative bar/psi as if normal.
- **why it matters**: A negative hydrotest pressure card is a credibility hit and, downstream of "Copy → paste into hydrotest screen", primes that calculator with garbage.
- **suggested fix**: After parse, `if (v != null && v < 0) → show errorText 'Wartość nie może być ujemna'` and skip rendering the result card (mirror the Kelvin pattern at 268-272).
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/quick_converter_screen.dart:53-56 (`_parse`) — whitespace + thousands separator handling
- **issue**: Pasted values from PDFs/Excel commonly contain U+00A0 (non-breaking space), U+202F (narrow NBSP) as thousands separators (`12 500,0` rendered with NBSP between 12 and 500). FilteringTextInputFormatter strips those chars on type but NOT on paste in older Flutter (3.16-3.19 — pin in pubspec.yaml needed). Result: `_parse('12 500,0')` → `replaceAll(',', '.')` → `'12 500.0'` → `tryParse` → null → empty card. Same with trailing `mm`, `in`, `°` units pasted alongside the number.
- **why it matters**: Direct paste from a job sheet or WhatsApp text (`Ø168,3 mm`) is the most common workflow on site; silent failure looks like an app bug. The BACKLOG P0-12 entry already addresses this for ISO parser — same fix family applies here.
- **suggested fix**: In `_parse`, strip `[  ​‎‏\s]`, drop trailing non-numeric tokens (`mm`, `in`, `°C`, `°F`, `K`, `bar`, `psi`), normalise U+2212 → `-`, then validate against canonical numeric regex before `tryParse`.
- **effort**: S
- **round1Ref**: P0-12 (extension of the ISO parser character-normalisation work to the converter)

- **severity**: low
- **location**: lib/screens/quick_converter_screen.dart:162, 233, 341, 424 (`onChanged: (_) => setState(() {})`) — empty-vs-invalid signalling
- **issue**: `_parse` collapses two semantically distinct states ("user has not typed yet" → return null) and ("user typed garbage" → also return null). Build only checks `if (v != null)`; the card vanishes identically in both cases. There is no way for the welder to learn which characters are accepted — the input field offers no validation feedback unless they happen to be on the temp tab and happen to type a negative Kelvin.
- **why it matters**: Discoverability — a fitter pasting `12.5"` (literal quote-inch suffix) sees the field accept the digits/dot and silently reject the whole input. They blame the app, fall back to a paper conversion table, and miss the tool's value.
- **suggested fix**: Distinguish `_parse` returning `ParseOutcome.empty` vs `ParseOutcome.invalid(reason)`; only the latter sets `errorText` and clears the card — empty leaves a neutral "Wpisz wartość, np. 12,5" hint.
- **effort**: M
- **round1Ref**: P3-01 (cosmetic helperText was the round-1 scope; semantic state model is the gap)

--- end block ---

## Iter #46 · lib/screens/heat_input_screen.dart · async-crash-safety

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:389-396 (`OutlinedButton.icon` → `copyToClipboard`)
- **issue**: Fire-and-forget call to `copyToClipboard(context, ...)` (returns `Future<void>` but is not awaited and no `unawaited(...)` marker). The helper itself guards `context.mounted` (clipboard_helper.dart:16) so the SnackBar path is safe, BUT errors from `Clipboard.setData` (rare PlatformException on locked-screen Android, denied user-perms on iOS share-extension contexts) are silently swallowed by the unhandled future. The welder taps "Kopiuj wynik", expects the green confirmation, sees nothing, and has no signal that the copy actually failed. They paste a stale clipboard value into a foreman SMS thinking it's the new HI number.
- **why it matters**: The whole point of the copy button on a calculator card is to move a verified number from the app into the WPS log / SMS / Notes without re-typing. A silent failure that LOOKS like a no-op is worse than a crash — the fitter doesn't know to re-tap, and the next paste is wrong data.
- **suggested fix**: Wrap in `try { await copyToClipboard(...); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kopiowanie nieudane'))); }`; OR have `copyToClipboard` itself return a bool and surface a red SnackBar on the false path. Apply the same pattern to every copy button in the calculator family.
- **effort**: S
- **round1Ref**: new (round-1 P0-01 was about journal save/load disposed-state crashes — different surface; this is the calculator-card copy path that no audit iteration has flagged yet)

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:701-769 (`_showHeatInputFormulaDialog`)
- **issue**: `showDialog<void>` is invoked with the outer screen's `context` and its returned Future is neither awaited nor `.then`-handled. Inside the builder the dialog correctly uses its own `ctx` for `Navigator.of(ctx).pop()` (good), but if the welder backgrounds the app while the dialog is open and Android's low-memory killer disposes the route, the future completes with a stale state and any future `_HeatInputScreenState` work scheduled off this would target a disposed state. Today there is no such follow-up work, so the crash surface is theoretical — but the pattern is fragile if a teammate later adds `.then((_) => setState(...))` to refresh on close.
- **why it matters**: Defensive coding for a screen that runs on a welder's phone with the app constantly backgrounded for camera/SMS/measurement — the next iteration that adds "remember last-shown formula" or analytics tracking on dialog dismissal will inherit the unawaited-future trap.
- **suggested fix**: Either `await showDialog<void>(...)` and gate any post-dialog work with `if (!mounted) return;`, or document at the call-site that the future is intentionally fire-and-forget (`unawaited(showDialog(...))`). Prefer the former so future maintainers can't accidentally land async work in an unsafe path.
- **effort**: S
- **round1Ref**: new (no round-1 entry covers dialog-future lifecycle on this screen)

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:74-87 (`_applyMaterial`)
- **issue**: `setState` mutates seven `TextEditingController.text` properties in a single batch. While this is synchronous and safe today, each `.text` setter fires the controller's listeners synchronously, which in turn re-run `onChanged: () => setState(() {})` on the `_NumField`s. Inside the build cycle this means a chain of setState-during-setState that Flutter tolerates but treats as already-dirty (no extra rebuild scheduled) — fine. HOWEVER if a future change wraps `_applyMaterial` to also fire after an async `await materialCatalog.loadCustom()`, the same chain will trigger after the widget might have been disposed (user tapped back during the picker animation). No `mounted` guard here.
- **why it matters**: Preheat chemistry is the safety-critical step — if `_applyMaterial` ever becomes async (e.g. fetching custom alloy chemistry from backend), the lack of a mounted guard will surface as "setState called after dispose" the first time a welder taps back fast on a slow connection.
- **suggested fix**: Add a marker comment `// SAFE: synchronous-only — if you add an await above, gate setState with `if (!mounted) return;`` and pre-emptively wrap the body. Cheap insurance for a screen that is one PR away from async chemistry fetch.
- **effort**: S
- **round1Ref**: new (parallels the BACKLOG P0-01 disposed-state pattern but applied preventively to a synchronous handler)

--- end block ---

## Iter #47 · lib/screens/tungsten_screen.dart · loading-error-empty-states

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:35-36, 73-109
- **issue**: No empty-input state — when `_amps.text` is empty or unparseable, `pick = null` and the diameter table renders with NO highlight, NO hint, NO call-to-action. A first-time user sees four rows of generic data and may not realise they have to type amps into the field above to get a recommendation.
- **why it matters**: Fitter opens the screen on a basement gantry, glances at the table, misreads "1.0 mm 15-80 A" as "use 1.0 mm" without entering current — picks wrong electrode (too small / too thin) and burns through on the first arc strike. Empty state should explicitly say "Wpisz prąd spawania powyżej, aby zobaczyć rekomendowaną średnicę".
- **suggested fix**: When `pick == null && _amps.text.isEmpty`, render a thin orange info banner above the table: `"↑ Wpisz prąd (A) aby zobaczyć rekomendację"` / `"↑ Enter current (A) to see recommendation"`.
- **effort**: S
- **round1Ref**: P2-15 (empty-state coaching + skeleton loaders + auto-scroll-to-results — backlog lists hydrotest/orbital/heat_input; tungsten missing from list, new addition)

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:35, 47-59 (and lib/data/tungsten.dart:90-97)
- **issue**: No invalid-input error state — `double.tryParse` returns null for malformed input like `"1.2.3"`, `"."`, `","`, `"-5"`, and the UI silently shows no pick, no error text under the TextField. The `InputDecoration` has no `errorText` wired in.
- **why it matters**: Welder with wet/cold fingers in winter on a 6" phone mistypes `"1..6"` or `"90,,5"` — sees no highlight, assumes "calculator is broken" and goes back to guessing tungsten from memory. Silent failures kill trust in the tool.
- **suggested fix**: Track parse error explicitly: `final raw = _amps.text.trim(); final parsed = double.tryParse(raw.replaceAll(',', '.')); final showErr = raw.isNotEmpty && (parsed == null || parsed <= 0);` then set `decoration.errorText: showErr ? context.tr(pl:'Niepoprawny prąd', en:'Invalid current') : null`.
- **effort**: S
- **round1Ref**: new (P1-30 covers per-field error/sanity bounds for heat_input/orbital/hydrotest but explicitly omits tungsten — this extends P1-30 to tungsten)

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:35-36 + lib/data/tungsten.dart:90-97 (`sizeForCurrent`)
- **issue**: Out-of-range input silently clamps to first/last band without telling the user. Type `500 A` (above the 400 A max for 3.2 mm) — UI happily highlights the 3.2 mm row as if it's recommended. Type `5 A` (below 15 A min for 1.0 mm) — UI highlights 1.0 mm. There is no "out of validated DC- range" warning state.
- **why it matters**: 500 A on a 3.2 mm tungsten is well outside the safe band — electrode will melt back and contaminate the weld pool. For stainless food/pharma piping this is a reject. The app's silent clamp gives false confidence that the pick is valid for that current.
- **suggested fix**: After computing `pick`, also compute `outOfRange = pick != null && (a! < pick.minA || a > pick.maxA)`; when true render an amber warning card above the table: `"⚠ Prąd poza zakresem DC- (15-400 A). Zweryfikuj dane spawalnicze."` and de-highlight the row (use lighter shade).
- **effort**: M
- **round1Ref**: new (related to P1-30 sanity bounds; specific to tungsten clamping behaviour in `sizeForCurrent` data layer)

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:171-242 (kTungstenTypes loop) + lib/data/tungsten.dart:50-86
- **issue**: No defensive empty-data fallback. Code does `kTungstenSizes.last` in `sizeForCurrent` (data file line 94-95) and unconditionally spreads `kTungstenTypes.map(...)` into the ListView. If either const list is ever emptied in a future refactor (or hot-reload race in dev), `.last` throws `StateError` and the spread silently shows nothing under the "TYP ELEKTRODY" header — no empty state widget.
- **why it matters**: Low risk in production (const lists), but during a data-file edit (e.g. someone adding new electrode types and accidentally commenting out the existing ones) the screen would crash on `sizeForCurrent` or show a bare header with no list and no message, leaving the welder confused whether the app is broken or there are genuinely no electrode types.
- **suggested fix**: Guard `sizeForCurrent` with `if (kTungstenSizes.isEmpty) return null;`; in the screen, after the header at line 170, wrap the spread in `if (kTungstenTypes.isEmpty) Text(context.tr(pl:'Brak danych — zaktualizuj aplikację', en:'No data — update the app'), style: TextStyle(color: _kMuted))`.
- **effort**: S
- **round1Ref**: new (no backlog item covers defensive const-list emptiness; P2-15 covers shimmer/empty-state but not data-corruption fallback)

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:43-46 (ListView + EdgeInsets)
- **issue**: No auto-scroll-to-result after entering amps. On a 5.5" phone in landscape, after the user taps the TextField, the soft keyboard covers the diameter table and the highlight is below the fold. There is no `Scrollable.ensureVisible` call on the matching row when `pick` changes.
- **why it matters**: Welder enters `90 A`, expects to see the recommended diameter pop up — but the keyboard hides rows 2-4, and only the 1.0 mm row (15-80 A) is visible above the keyboard. They don't realise the 1.6 mm row was actually selected and they're staring at the wrong band.
- **suggested fix**: Add a `GlobalKey` per row when `hit == true`, and after `setState` schedule `WidgetsBinding.instance.addPostFrameCallback((_) => Scrollable.ensureVisible(key.currentContext!, alignment: 0.2, duration: 250ms))` only when `pick` changes (track prev pick in state).
- **effort**: M
- **round1Ref**: P2-15 (auto-scroll-to-results — backlog explicitly lists hydrotest/orbital/heat_input; tungsten not listed, new addition to that backlog item's scope)

--- end block ---

## Iter #48 · lib/screens/premium_screen.dart · i18n-coverage

- **severity**: med
- **location**: lib/screens/premium_screen.dart:427 (`price: '19 PLN'`), :437 (`price: '149 PLN'`), :399 (`oszczędność ~19 PLN` / `~19 PLN saved`)
- **issue**: Price strings are hardcoded as `'19 PLN'` / `'149 PLN'` outside of `context.tr(...)`. The EN branch of the body copy at :399 literally reads "~19 PLN saved" — an English speaker (Irish/UK/DE fitter who flipped the language toggle and is the exact ICP for the AI Assistant pitch) sees Polish złoty in an English UI with no currency conversion or even formatting (no thousands separator, no `zł` vs `PLN` consistency check across screens).
- **why it matters**: A Polish fitter on a UK site sharing the app with English-speaking coworkers gets asked "what's 149 PLN?" mid-pitch — the conversion friction kills the upgrade conversation right at the Plans CTA. Workshop crews are mixed-nationality on big projects; the screen with money on it is the one that MUST read natively in both languages.
- **suggested fix**: Wrap prices in `context.tr(pl: '19 zł', en: '€4.50')` (or whatever the conversion target is) — or at minimum `context.tr(pl: '19 PLN', en: '19 PLN (~€4.50)')` so the EN user has a frame of reference. Apply same to :399 savings line.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/premium_screen.dart:451-452 (`'Płatność: Stripe (karta, BLIK, Apple Pay, Google Pay)'` vs `'Payment: Stripe (card, Apple Pay, Google Pay)'`)
- **issue**: Asymmetric payment-method list — the PL string mentions BLIK, the EN string silently drops it. Defensible (BLIK is PL-only), BUT a Polish fitter who toggled language to EN to show a coworker the app suddenly loses BLIK from the trust signals on the very screen where trust matters most. Also inverse: an EN-speaking user in PL who flips to PL discovers a payment method they didn't know was available — but only by accident.
- **why it matters**: BLIK is the dominant fitter-friendly payment in PL (no card, instant from banking app on the same phone). Hiding it from the EN view is the single biggest conversion lever on this screen for bilingual PL users — they're often the decision-makers and read EN by preference but pay via BLIK.
- **suggested fix**: EN copy should read `'Payment: Stripe (card, BLIK, Apple Pay, Google Pay). Cancel anytime.'` — BLIK is a brand name, doesn't need translating, and signals "local-friendly" to anyone reading EN in PL.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/premium_screen.dart:233 (`Text('PREMIUM', ...)`) — AppBar title
- **issue**: Title bar text `'PREMIUM'` is a bare string literal, not `context.tr(...)`. Today it reads identically in both locales so the bug is latent — but it dodges the i18n discipline that every other on-screen string in the file follows, so the next translator/PM who decides EN should read "PRO" or PL should read "PREMIUM ✨" has to first refactor the literal.
- **why it matters**: Low impact today; mostly a consistency / maintainability finding. A fitter never sees a wrong word here under current setup.
- **suggested fix**: `Text(context.tr(pl: 'PREMIUM', en: 'PREMIUM'), ...)` so the pattern is consistent and the next change is a one-liner edit, not a refactor.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/premium_screen.dart:367 (`title: context.tr(pl: 'Coping & saddle templates (PDF)', en: 'Coping & saddle templates (PDF)')`)
- **issue**: PL branch is identical to EN — "Coping & saddle templates (PDF)" is left untranslated for Polish fitters. The body translates fine ("szablony do owinięcia na rurze"), but the FEATURE TITLE — the scannable line a user reads when deciding to upgrade — stays in English. Inconsistent with sibling tiles (`'Kalkulator momentu śrub'`, `'Bez reklam'`) which DO translate the title.
- **why it matters**: Polish pipefitters absolutely know what fish-mouth is, but "coping & saddle templates" is a US/UK term-of-art. The 50-something fitter scanning the feature list in PL may skim past this tile not recognising the English jargon as something they need. That's a missed conversion on what's arguably the most uniquely useful Pro feature.
- **suggested fix**: `pl: 'Szablony cięcia siodłowego (PDF)'` (or `'Szablony fish-mouth (PDF)'` keeping the loanword most fitters actually use on shop floor) — mirror tone of the body line below.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/premium_screen.dart:428 (`per: context.tr(pl: '/mc', en: '/mo')`), :438 (`per: context.tr(pl: '/rok', en: '/yr')`)
- **issue**: Period abbreviations are translated correctly, but PL uses `/mc` where industry-standard Polish billing UIs use `/mies.` or `/m-c` — `/mc` reads ambiguous (megaCalorie? mileage?) to a first-time user not steeped in this app's conventions. Minor wording.
- **why it matters**: A fitter scanning the price card spends ~1 second on it; an ambiguous unit forces a re-read and a half-second of doubt right where the CTA needs zero friction.
- **suggested fix**: `pl: '/mies.'` (or `/m-c` matching Stripe's PL invoices). EN `/mo` is already idiomatic — leave it.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/premium_screen.dart:440-441 (`pl: 'OSZCZĘDZASZ 35% · POPULARNE'`, `en: 'SAVE 35% · MOST POPULAR'`)
- **issue**: PL badge reads as two stacked claims separated by `·` — "OSZCZĘDZASZ 35% · POPULARNE". Grammatically `POPULARNE` (neuter plural adj.) without a noun is jarring; native PL marketing copy would say `NAJPOPULARNIEJSZY` (matching EN "MOST POPULAR") or `BESTSELLER`. Currently it reads like a half-finished translation.
- **why it matters**: Trust signal on the highlight CTA; awkward Polish makes the offer feel auto-translated and erodes the premium-product framing the orange/gold gradient is working hard to build.
- **suggested fix**: `pl: 'OSZCZĘDZASZ 35% · NAJCZĘŚCIEJ WYBIERANY'` or simpler `'OSZCZĘDŹ 35% · BESTSELLER'`.
- **effort**: S
- **round1Ref**: new

--- end block ---

## Iter #49 · lib/screens/ai_chat_screen.dart · perf-rebuilds

- **severity**: high
- **location**: lib/screens/ai_chat_screen.dart:433-458
- **issue**: AnimatedBuilder rebuilds the full Row + 3 Padding + 3 Container + 3 Transform.scale every animation tick (~60 fps for a 900 ms repeat). BoxDecoration with `_kAccent.withValues(alpha: 0.7)` is re-allocated per frame for each of the 3 dots, so ~180 Color/BoxDecoration allocations per second while the AI is "typing".
- **why it matters**: Typing indicator runs for the full duration of every AI response (often 5-10 s). On a Snapdragon 4xx workshop phone this raises baseline jank during the wait and battery drain becomes visible across a 50-message shift. The fitter perceives the app as heavy exactly while waiting for the answer they paid Premium for.
- **suggested fix**: Build the 3 dots once outside AnimatedBuilder; inside the builder only return the `Transform.scale` driven by a per-dot Animation. Promote the alpha-modulated dot color to a top-level `const Color(0xB3E8C14B)` (0.7 alpha pre-baked) and reuse one `const Container` decoration.
- **effort**: S
- **round1Ref**: new (round-1 P1-XX did not cover the typing-indicator paint path)

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:196-206
- **issue**: ListView.builder has no explicit `RepaintBoundary` around `_MessageBubble`/`_TypingIndicator` and items have no stable keys. When the typing indicator animates inside the list, the whole viewport can re-paint because the typing item shares the list's RepaintBoundary with sibling bubbles containing SelectableText.
- **why it matters**: SelectableText is expensive to repaint (paragraph layout + selection handles). Every typing-dot frame can ripple a re-paint across all visible message bubbles. After a 10-message chat, scrolling stutters and selection handles flicker — a welder trying to long-press-copy a citation mid-response sees the cursor jump.
- **suggested fix**: Wrap `_MessageBubble` and `_TypingIndicator` returns in `RepaintBoundary`; add a `ValueKey` on each message (uuid on ChatMessage or `ObjectKey(message)`) so insert-at-end keeps existing element identities.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:289-298, 304-313, 339-345, 365-374, 415-423, 449-451
- **issue**: Repeated `_kAccent.withValues(alpha: 0.15)`, `_kAccentBlue.withValues(alpha: 0.18/0.3)`, `_kAccent.withValues(alpha: 0.1/0.25)`, `_kAccent.withValues(alpha: 0.7)` allocate fresh Color objects on every bubble build. With 30 messages on screen and 5 alpha-blended decorations per bubble, every setState (send / receive / typing toggle) allocates ~150 throwaway Color instances plus matching BoxDecoration/Border objects.
- **why it matters**: Garbage pressure on budget Android shows up as 16 ms frame-budget misses during scroll — exactly when the fitter is scrolling back to re-read a preheat answer from 5 messages ago. GC pauses while wearing gloves feel like "phone froze, did my message go?".
- **suggested fix**: Promote all alpha-modulated colors to top-level const literals (e.g. `const _kAccent15 = Color(0x26E8C14B);`). Replace every `withValues` call site. Same for `Border.all`/`BoxDecoration` — they become const-able once colors are const.
- **effort**: S
- **round1Ref**: new (overlaps P1-23 palette extraction, adds pre-baked alpha variants)

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:1, 275-379, 384-464, 469-517, 522-596
- **issue**: Inner widgets (`_MessageBubble`, `_TypingIndicator`, `_SuggestionStrip`, `_Composer`) cannot be `const`-constructed because of the file-wide `// ignore_for_file: prefer_const_constructors` at line 1 and non-const color literals. Every Composer/SuggestionStrip rebuild on parent setState (send/receive) allocates fresh widget trees even though their inputs (controller, focusNode, onSend, onPick) are stable references.
- **why it matters**: Each `_send()` triggers two setState calls (user msg + reply), each rebuilding Composer + SuggestionStrip + every bubble. Cumulative widget allocations dwarf the actual visual delta. On low-end phones every send adds a perceptible ~50 ms hitch before the keyboard re-anchors.
- **suggested fix**: Remove the file-wide ignore. Mark inner widget constructors `const` (already feasible — only refs are stable callbacks/controllers). Hoist `_typing` into a `ValueNotifier<bool>` and convert Composer to a `ValueListenableBuilder` so a `_typing` flip does NOT rebuild Scaffold/AppBar/ListView/SuggestionStrip.
- **effort**: M
- **round1Ref**: new (companion to P1-20 saddle_template pattern, applied to chat)

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:72-123
- **issue**: `_send` calls `setState(...)` twice per message round-trip (once before await, once after). Each setState rebuilds the entire Scaffold tree including AppBar (re-running `context.tr` + DEMO badge logic), the SuggestionStrip mount/unmount check on line 208, full ListView.builder, and Composer.
- **why it matters**: The send button feels sluggish — the user-typed bubble appears with a frame of stutter because the whole Scaffold re-layouts. SuggestionStrip mount/unmount triggers a layout shift that visibly bumps the composer up/down right after the first message, distracting in a glove-tap context.
- **suggested fix**: Hoist `_typing` into a ValueNotifier<bool> and `_messages` into a ChangeNotifier so only the ListView (wrapped in AnimatedBuilder/ListenableBuilder) rebuilds on append. Keep AppBar/Scaffold as const-equivalent shells. Wrap the suggestion strip in AnimatedSwitcher so its appearance is animated rather than a hard layout flip.
- **effort**: M
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:475-481
- **issue**: `_SuggestionStrip.build` re-allocates the 5-entry `suggestions` list every rebuild and re-runs 5 `context.tr` lookups, even though the strip only appears when `_messages.length <= 1` (i.e. once at session start).
- **why it matters**: Tiny but every parent setState while the strip is visible reflows the horizontal ListView.builder, re-measures all 5 chips, and re-creates the closures passed to GestureDetector.onTap. Wasted work on the welcome screen.
- **suggested fix**: Cache `suggestions` in a converted StatefulWidget initState (or memoise via `didChangeDependencies` keyed on language). Even simpler: pull strings to `app_strings.dart` and make the list `static const`.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:546-578
- **issue**: TextField in Composer constructs 3 fresh `OutlineInputBorder` objects (`border`, `enabledBorder`, `focusedBorder`) and an `InputDecoration` on every build. None are const because `BorderSide(color: _kBorder)` is not const-callable with the current Color literal.
- **why it matters**: Composer rebuilds on every `_send` round-trip → 6 Border allocations + InputDecoration per send. ~50 messages/shift = ~300 throwaway InputDecoration objects, contributing to GC pressure on the most-touched widget on the screen.
- **suggested fix**: Hoist the three OutlineInputBorder instances + InputDecoration to file-level `final` (or `static final` inside `_Composer`) so they are built once. Once the color palette is const-ified, promote to `const`.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:328-357
- **issue**: Citation chips are built via `.map(...).toList()` inside the bubble `build`. Every parent rebuild re-walks the citations list, re-allocating 1 InkWell + 1 Container + 1 Text + 2 Color per citation per bubble. With 5 bubbles × ~2 citations average = ~10 chips rebuilt per send.
- **why it matters**: Adds proportional cost to every setState ripple. A single AI response with 3 citations on top of 4 prior bubbles produces ~35 wasted InkWell rebuilds per send tick.
- **suggested fix**: Once `_MessageBubble` is constified and isolated under RepaintBoundary (above), this becomes near-free. As an interim, extract a `const _CitationChip({required String text})` widget so identical citations reuse Element identity.
- **effort**: S
- **round1Ref**: new

--- end block ---


## Iter #50 · lib/screens/chat_screen.dart · edge-case-zero-one

- **severity**: high
- **location**: lib/screens/chat_screen.dart:351-353
- **issue**: `_pollDelta` early-returns when `_messages.isEmpty`, which means if a welder opens an empty room (zero messages) and someone else posts the first message, the poller NEVER picks it up - only a manual pull-to-refresh recovers. The room is stuck on "empty" forever during a session.
- **why it matters**: A new shift starts, the welder opens "Hydrotest tips" room (0 messages), waits for the foreman's first message. Backend has a message arriving 30 s later - the welder never sees it because polling is gated on `_messages.isNotEmpty`. They assume the chat is broken.
- **suggested fix**: When `_messages.isEmpty`, call `_refresh()` (no sinceIso) instead of returning. Or initialise `sinceIso` to room creation timestamp / `widget.room.createdAt` and always poll.
- **effort**: S
- **round1Ref**: new

- **severity**: high
- **location**: lib/screens/chat_screen.dart:87-99
- **issue**: When `_rooms` returns an empty list (zero rooms - backend live but no rooms seeded yet, or all hidden by moderation), the body renders an empty `ListView.builder` with `itemCount: 0` - completely blank scrollable. No empty-state message, no call-to-action, no hint that pull-to-refresh exists.
- **why it matters**: First-time user opens the Czat tab, backend is up but zero rooms configured -> user sees a bare dark screen with just an AppBar. They conclude the feature is broken or premium-only and never come back. Lost engagement on a community feature.
- **suggested fix**: When `(_rooms?.isEmpty ?? true)` after load completes, render a centred empty state: "Brak kanalow. Pociagnij w dol, aby odswiezyc." with `Icons.forum_outlined` and the room count = 0.
- **effort**: S
- **round1Ref**: new

- **severity**: high
- **location**: lib/screens/chat_screen.dart:111-148
- **issue**: Nickname dialog accepts any non-empty trimmed string but does NOT reject the single-character case (e.g. "a"), pure-digit nicknames ("1"), or whitespace-only-with-one-character. There is no minimum length and no character-class validation. After `res.isNotEmpty` check, ANY string of length 1-32 is sent to `setNickname()`.
- **why it matters**: A gloved fitter mis-types "a" instead of "Andrzej" and the chat now shows them as "a" - every message in the room is attributed to a meaningless single letter. Foreman cannot identify who said what during a safety review of the chat history.
- **suggested fix**: Require `res.length >= 2` (or 3) and reject pure-whitespace-after-trim / pure-numeric. Show inline `errorText` "Min. 2 znaki" / "Min. 2 characters" without dismissing the dialog.
- **effort**: S
- **round1Ref**: new

- **severity**: high
- **location**: lib/screens/chat_screen.dart:351-367
- **issue**: `_pollDelta` uses `_messages.last.createdAt.toUtc().toIso8601String()` as the `sinceIso` cursor. If two messages share the same `createdAt` (sub-second clock resolution on the backend, or burst posts within the same second), the second one may be missed because the backend likely returns `created_at > since` strictly, not `>=`. With exactly one message at time T and a second arriving at the same T, the second is silently lost.
- **why it matters**: Two welders hit "send" at the same instant about a fit-up issue; one of the messages disappears from the polling cursor and only shows up after a manual refresh. Critical clarification ("DON'T weld yet - pressure not relieved") is lost mid-shift.
- **suggested fix**: Track `_lastSeenId` alongside `lastCreatedAt`; when burst-receiving messages with identical timestamps, send the higher of `(lastCreatedAt - 1ms)` to ensure overlap, then dedup by id (which already happens at line 359-360). Or use a monotonically increasing server-assigned cursor.
- **effort**: M
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:378-380
- **issue**: `_send` rejects empty text but does NOT reject single-character messages or pure-whitespace-after-trim. A "." or "?" or "k" alone passes through and is posted. Also no minimum-length check matching backend expectations.
- **why it matters**: Gloved bumps on the send button after typing one stray character spam the room with noise like ".", "k", "x" - pollutes the searchable log and burns the 8-msg/min rate limit, blocking real messages for the next minute.
- **suggested fix**: Require `text.length >= 2` (or accept emoji-only as a special case). Cheap, prevents accidental noise. Match the backend's actual minimum.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:608-618
- **issue**: `_formatTime` uses `DateTime.now()` (local) to compare with the message's local time for the "today" decision, but `t` is already converted via `.toLocal()`. Edge case: a message posted at 23:59:59 local time, opened by the user the next day at 00:00:01 - it shows "$h:$m" (e.g. "23:59") with NO date, looking like it was just sent. Conversely, a message from today's 00:00:00 viewed at 23:59:00 shows the date prefix unnecessarily.
- **why it matters**: A welder reviewing the chat at midnight sees yesterday's "20:15 - watch the purge" appear as if it's today's instruction. Misattributed timing on safety-relevant comments.
- **suggested fix**: When the date differs from `now`, always show date prefix. Additionally, if `t` is more than 23 h ago, force date display even if year/month/day happens to match (same-day-next-week edge). Even simpler: render relative time ("2h ago" / "wczoraj 23:59") for the recent window.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:142-144
- **issue**: After dialog closes with `res != null && res.isNotEmpty`, the call to `setNickname(res)` is awaited but `mounted` is NOT re-checked AFTER the await. If the user pops the screen while the setNickname HTTP call is in flight, the result is ignored but any subsequent setState would crash. There is also NO feedback (success snackbar) confirming the nickname was saved - silent success indistinguishable from silent failure.
- **why it matters**: Welder types "Krzysiek 304L", taps OK, then backs out to a job site (off-screen) - no confirmation the nickname stuck. Next message posts as "anon-XYZ" because the call failed silently and there is no retry.
- **suggested fix**: Wrap `setNickname` in try/catch; on success show `SnackBar('Zapisano')`; on failure show retry SnackBar. Also re-check `mounted` after the await even though no setState follows - defensive against future edits.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:316-317
- **issue**: The 8s polling Timer keeps running even when the screen is in the background (app paused / phone locked / user navigates to another screen via deep link). `dispose()` cancels it only on widget tear-down, but if the user backgrounds the app for 30 minutes, the Timer wakes every 8 s burning network and battery for messages that will be re-fetched on resume anyway.
- **why it matters**: Workshop phones live in pockets on 4G with limited battery; idle polling drains battery and the welder finds the phone dead at the end of the shift, missing the foreman's emergency message.
- **suggested fix**: Implement `WidgetsBindingObserver` and pause the Timer on `AppLifecycleState.paused`; on resume, do one immediate `_pollDelta()` then restart the periodic timer. Save battery + bandwidth.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:512-516
- **issue**: `_MessageBubble.isMine` is decided by `_messages[i].deviceId == _myDeviceId`. Edge case: `_myDeviceId` is set in `_bootstrap()` via `PremiumService.instance.deviceId` - if `init()` resolves AFTER `_refresh()` runs (race in the await chain) OR if PremiumService.deviceId is the empty string `''` momentarily, every message with empty deviceId would be flagged "mine" and reportable via long-press would be suppressed (line 547: `onLongPress: isMine ? null : onLongPress`).
- **why it matters**: Edge condition: server hands back a message with `deviceId == ''` (legacy / migration row) - every welder sees it as "their own" message, cannot report it. Spam or banned content stays visible.
- **suggested fix**: Guard `isMine` as `_myDeviceId.isNotEmpty && message.deviceId == _myDeviceId`. Also ensure `_myDeviceId` is set before `_refresh` runs so the first paint never falsely flags messages.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:327-349, 502-518
- **issue**: When `_messages` returns exactly one message from `listMessages`, `_pollDelta` will use that one's `createdAt` as the since cursor. But there is no UI difference between "1 message" and "0 messages" for the empty-state perspective - the ListView simply has one row. Also the auto-scroll-to-bottom on initial load (line 339-340) is invoked even when there is exactly one message (degenerate scroll case: maxScrollExtent ~ 0).
- **why it matters**: Welder opens a room expecting threaded conversation, sees a single solo message and a "Napisz wiadomosc..." composer with no contextual hint that this is the start. Minor but the empty/one boundary creates a confused first impression for community-feature adoption.
- **suggested fix**: When `_messages.length <= 1`, prepend a soft "Poczatek rozmowy - badz pierwszy" hint card. Skip the animateTo call when `maxScrollExtent < 1` to avoid jitter on degenerate scroll.
- **effort**: S
- **round1Ref**: new

- **severity**: med
- **location**: lib/screens/chat_screen.dart:120-127
- **issue**: Nickname TextField has `maxLength: 32` with `counterText: ''` (hidden counter). Edge case at the upper boundary: a user pastes a 40-char string - Flutter silently truncates to 32, with NO visible feedback because the counter is suppressed. They tap OK on what looks like "Krzysiek-spawacz-z-warszawy" but server stores "Krzysiek-spawacz-z-warsza".
- **why it matters**: Welder pastes a Steam-style handle, the truncated suffix removes a meaningful disambiguator ("304L" vs "316L"), and now two welders share the same prefix. Misattribution in chat.
- **suggested fix**: Either show the counter (`counterText` not empty) or show a `helperText` reminder "max 32 znaki". Or display the live char count "12/32" so the truncation is visible at the boundary.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/chat_screen.dart:88
- **issue**: `itemCount: _rooms?.length ?? 0` handles the null/empty case at zero, but combined with `RefreshIndicator` wrapping a 0-item `ListView.builder`, the pull-to-refresh GESTURE may not trigger because the ListView has no scroll extent when itemCount==0. (Known Flutter quirk: `ListView` needs `physics: AlwaysScrollableScrollPhysics()` for RefreshIndicator to fire on empty content.)
- **why it matters**: Backend was offline at load, user pulls down to retry, nothing happens. The Retry path is only available if `_error != null`; if the list silently returned `[]` (no exception, no rooms), the user is trapped in an un-refreshable empty screen.
- **suggested fix**: Add `physics: const AlwaysScrollableScrollPhysics()` to the ListView.builder so RefreshIndicator works at zero items.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/chat_screen.dart:553-556
- **issue**: `ConstrainedBox` uses `maxWidth: MediaQuery.of(context).size.width * 0.78`. Edge case: when the device width is very narrow (small phone in split-screen / foldable), 78% can drop below the minimum width required for a single-emoji message + padding, causing the bubble to wrap awkwardly. The other boundary is wide tablets where 78% = 800+ dp making bubbles span almost the whole screen and lose the chat-asymmetry visual.
- **why it matters**: On foldable workshop phones (Z Flip in the gloved hand) and split-screen Android setups, the chat becomes unreadable; on shop iPads the visual hierarchy breaks.
- **suggested fix**: Clamp to `min(0.78 * width, 480)` and `max(160)`. Also constrain by `LayoutBuilder` so the bubble respects the actual parent constraints rather than the raw device width.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/chat_screen.dart:585-592
- **issue**: `Text(message.text, ...)` has no `maxLines` or `softWrap` boundary handling. Edge case: a message containing exactly one extremely long URL or one continuous-character string (e.g. `aaaaa...` x 400 from the 400-char composer limit) becomes a single unwrapped overflowing word that breaks the bubble layout. Flutter wraps on whitespace by default but degenerates with no-whitespace content.
- **why it matters**: A spam-trolling welder sends `kkkkkkk...` x 400, the bubble overflows past the maxWidth constraint visually (and may push neighbouring bubbles), and the long-press report gesture target gets misaligned. Reports become harder to send.
- **suggested fix**: Wrap `Text` with `softWrap: true` and set `overflow: TextOverflow.visible`; better, force `WordWrapper` by injecting zero-width-space every N chars for tokens >40 chars without whitespace. Or `TextWidthBasis.longestLine` with `wordSpacing: 0`.
- **effort**: S
- **round1Ref**: new

- **severity**: low
- **location**: lib/screens/chat_screen.dart:573-584
- **issue**: `_MessageBubble` displays `message.nickname` for non-mine messages without checking if it is empty. If the backend returns a message with `nickname == ''` (legacy row, user never set one), the bubble shows a 0-height Text widget with the 3 dp bottom padding - looking like an unlabelled message floating in the room.
- **why it matters**: Anonymous-looking messages from "" reduce trust ("who sent this?"); reporting an unattributed message gives the moderator no context.
- **suggested fix**: Fallback to `'Anonim'` / `'anon'` localised when `nickname.isEmpty`. Suppress the empty Text widget so the bubble doesn't reserve the unused padding.
- **effort**: S
- **round1Ref**: new

--- end block ---
