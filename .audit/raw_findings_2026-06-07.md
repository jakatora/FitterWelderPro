# Raw audit findings — 2026-06-07

One block per iteration. Synthesis agent will dedupe at end.

---

## Iter #1 · lib/screens/iso_notebook_screen.dart · ux-layout

- **severity**: high
- **location**: lib/screens/iso_notebook_screen.dart:4066-4223
- **issue**: AppBar carries 9 IconButtons + a PopupMenuButton (Help, NotePrefix, Wymiary, Copy, Undo, AxisLock, PDF, Hint, ClearAll, ViewMenu). On a 360 dp phone in portrait this overflows — Flutter silently truncates the trailing actions or pushes the title to ellipsis. No MenuAnchor/auto-overflow handling — fitter can lose access to Undo or Export when title is non-empty.
- **why it matters**: Welder holds the phone in a chest bracket, one hand free, gloved. If "Cofnij" or "Eksportuj PDF" gets cut off behind the kebab on jobsite-typical 5.5" devices, they have to scroll/rotate or lose work.
- **suggested fix**: Move Undo + PDF + Wymiary into a primary "Akcje" group; collapse the rest under the existing PopupMenuButton(Icons.tune) so AppBar has <=4 visible icons regardless of width.
- **effort**: M

- **severity**: high
- **location**: lib/screens/iso_notebook_screen.dart:4457-4482 (_Toolbar.build)
- **issue**: Toolbar uses two SingleChildScrollView(scrollDirection: Axis.horizontal) rows with 19 fitting chips on row 1 — no visual affordance that the row scrolls (no fade-edge gradient, no scroll-indicator), and no hint that spawanie/support/instrument/spool-break live off-screen to the right. Empty-state hint mentions it at line 4341 ("pasek KSZTAŁTKI przewija się w bok") but disappears once user draws first segment.
- **why it matters**: A fitter who never sees the hint (because they drew something first) will believe the app has only the first ~6 fittings. Discovery failure for half the tool palette.
- **suggested fix**: Add a ShaderMask fade gradient on right edge of toolbar row when content overflows, OR add a small ">" chevron at right when scrollable. Persist a "scroll for more" badge until the user has actually scrolled at least once.
- **effort**: M

- **severity**: high
- **location**: lib/screens/iso_notebook_screen.dart:4416-4446 (chip builder)
- **issue**: Chip tap targets are EdgeInsets.symmetric(horizontal: 9, vertical: 5) with fontSize: 11 and iconSize: 15 — total height ~26 dp. Material/HIG guidelines require 44-48 dp minimum tap target. The chips also sit shoulder-to-shoulder (margin 3 dp), making mis-taps with gloved fingers extremely likely.
- **why it matters**: Workshop-floor users wear nitrile/leather gloves; a 26 dp chip with 3 dp gap is a coin-toss between "Kolano 90°" and "Kolano 45°" — wrong tool placed corrupts layout, requires undo+retry. Cumulative annoyance over 100-element drawing.
- **suggested fix**: Increase chip vertical padding to 12 dp (height >=44 dp), horizontal margin to 6 dp, bump icon to 20 dp. Horizontal scroll absorbs the size cost.
- **effort**: S

- **severity**: high
- **location**: lib/screens/iso_notebook_screen.dart:4659-4723 (_drawColorLegend) + 4274-4284 (_AxisCompass)
- **issue**: Bottom-right canvas overlay (_drawColorLegend — 60x72 box) collides with the area where a fitter dimensions the rightmost segment. Combined with the top-right _AxisCompass (~110 dp wide), the bottom-left title block (168 dp wide), and the empty-state hint (full-width), the canvas has overlays in all four corners. No way to dismiss/move the color legend (the axis-compass toggle in "Widok" menu does NOT affect it).
- **why it matters**: On a real drawing the user can't dimension what's hidden behind the legend. Mobile screen real-estate is precious; uncloseable overlays = wasted canvas.
- **suggested fix**: Add showColorLegend toggle (persisted) to the "Widok" PopupMenuButton alongside showAxisCompass/showStatusBox. Auto-hide once user has drawn >=10 segments (they have learned the color code by then).
- **effort**: S

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:4226-4361 (Scaffold.body Column)
- **issue**: Layout vertical stack: AppBar (~56 dp) + _Toolbar (~76 dp, two rows) + Canvas (Expanded) + _SummaryBar (~46 dp). On a 5.5" phone in landscape this leaves <300 dp of vertical canvas. No fullscreen drawing mode that hides toolbar + summary.
- **why it matters**: Fitter often needs to see the WHOLE iso to verify connectivity before dimensioning. ~300 dp in landscape barely shows 6-8 grid steps tall.
- **suggested fix**: Add Icons.fullscreen toggle to AppBar that collapses _Toolbar + _SummaryBar into a single 40-dp strip (current tool + expand button). Re-tap restores. Persist last state.
- **effort**: M

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:1318-1782 (_askCalc dialog)
- **issue**: The "Wymiar / cięcie odcinka" AlertDialog uses ConstrainedBox(maxWidth: 420) + inner SingleChildScrollView. On 360 dp with keyboard open, the dialog squeezes ISO input, deducts list, slope, DimRef chips, "Insulated" checkbox and the live-result card into <240 dp visible area. The most critical UI element — the big "CUT — rura do ucięcia" number at line 1587 — is below the fold; user must scroll past every input to confirm.
- **why it matters**: Fitter types ISO and immediately wants to read CUT. Scrolling to confirm with a wet/gloved finger after every dimension entry is friction x 100 segments.
- **suggested fix**: Pin the live-result card (lines 1525-1615) to the TOP of the dialog (above ISO input) so the cut value is always visible at thumb position. Move rarely-touched slope/DimRef/insulated controls under an ExpansionTile("Opcje zaawansowane").
- **effort**: M

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:1730-1769 (dialog actions)
- **issue**: Action row has three buttons: "Usuń" (destructive, left), "Anuluj" (middle), "OK" (right). On a right-handed phone the thumb arc reaches bottom-right (OK) but also sweeps over "Usuń" on the left. With gloves on, hand position drifts — destructive action sits where the off-thumb naturally rests when reaching across. No confirmation step before deletion.
- **why it matters**: One slip = lost dimension on a segment already measured in the field. No tooltip warning, no second-tap confirm.
- **suggested fix**: Move "Usuń" to a small icon-only button in the dialog header (top-right, separate from action row) and require a second tap to confirm ("Tap again to remove"). Same fix applies to _askText (line 1825) and elbow spec sheet.
- **effort**: S

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:4290-4358 (empty-state hint)
- **issue**: Empty-state hint is Positioned(bottom: 16, left: 16, right: 16) — full-width pinned to canvas bottom. Overlaps with the title block (bottom-left, line 4729+) when canvas is non-empty, and on first run blocks the bottom third of the grid so the user can't see their drag preview while reading the instructions.
- **why it matters**: Onboarding screen literally blocks the onboarding action — "przeciągnij palcem po siatce" but the hint covers the bottom third of the grid.
- **suggested fix**: Position the hint at top-left under the AppBar instead of bottom, OR shrink to a single-line collapsed strip until tapped to expand. Auto-fade on first finger-down.
- **effort**: S

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:4106-4121 (axis-lock toggle)
- **issue**: Lock icon uses Icons.lock (locked = axis ON) vs Icons.lock_open (unlocked = axis OFF). The "lock" metaphor is ambiguous — locked could mean "feature ON" OR "feature FROZEN/CANNOT-USE". The SnackBar feedback helps but appears only AFTER the tap, by which point the user may have toggled the wrong way and drawn a wrong segment.
- **why it matters**: Fitters expect axis-lock by default. A misread mid-drawing causes free-angle pipes where they should be axis-locked.
- **suggested fix**: Replace with explicit text-label segmented button "OŚ: ON/OFF" or use Icons.straighten (on = lined) / Icons.gesture (off = free). Add a small permanent indicator on the canvas (top-left corner of toolbar) showing current axis-lock state.
- **effort**: S

- **severity**: med
- **location**: lib/screens/iso_notebook_screen.dart:1849-2049 (_editElbowSpec sheet)
- **issue**: Elbow spec bottom-sheet has DN dropdown + Type dropdown side-by-side at lines 1907-1970 with Expanded halves. DropdownButton arrow targets are tiny (~24 dp), and the items list ("DN15, DN20...DN600 · 1/2"...24"") shows both metric and imperial — long string in a narrow column means truncation. Also no DN search field, so DN300 means scrolling 18 items.
- **why it matters**: Welders work on jobs with mixed DN sizes; scrolling a long dropdown with a gloved finger is slow and error-prone.
- **suggested fix**: Replace dropdowns with Wrap(ChoiceChip) rows or a horizontal scrollable chip strip for common DN values. For Type use a SegmentedButton (only 4 options).
- **effort**: M

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:4385-4414 (toolbar item lists)
- **issue**: 19 fitting items + 3 line items + 3 annotation items = 25 chips total. No category sub-headers within FITTINGS (elbows/valves/flanges/welds all in one undifferentiated row). The lone separator at line 4467 only divides LINES from FITTINGS, not the FITTINGS sub-groups.
- **why it matters**: When hunting for "Zwrotny" (check valve), the user reads every chip label. Sub-headers would let them skim by category.
- **suggested fix**: Insert mini vertical separator chips between groups: Elbows | Branches | Reducers | End-pieces | Valves | Welds | Misc — even subtle 1 px colored ticks would help.
- **effort**: S

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:4530-4584 (_SummaryBar)
- **issue**: Summary bar shows dimensioned/pipeCount and "Suma CUT" only when pipeCount > 0. When user has many components but zero pipes (mid-drawing), the bar is hint-only — no signal of "you have N elbows / N valves / nothing measured yet". Lacks at-a-glance progress.
- **why it matters**: Mid-job status is invisible until pipes exist. A foreman glancing at the screen can't tell how complete the drawing is.
- **suggested fix**: Show component count chips ("3 kolanka · 2 zawory · 0 wymiarów") alongside the existing CUT total. Color-code: gray (nothing), amber (partial), green (complete).
- **effort**: S

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:586, 4039-4042 (_paperMode default)
- **issue**: Paper mode (light canvas) defaults to false (dark canvas). On bright workshop floors with direct sun, dark canvas is unreadable. The toggle is buried in "Widok" popup, three levels deep.
- **why it matters**: First impression for outdoor users is "I can't see anything"; many won't dig into the menu to find paper mode.
- **suggested fix**: On first launch prompt "Pracujesz na zewnątrz?" Y/N -> if Y set paperMode=true. Or auto-detect screen brightness >=80% and suggest light mode via SnackBar with quick-toggle action.
- **effort**: M

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:4262 (axisLock + tool gate)
- **issue**: Ghost extension visualization (axis-snap preview) ONLY shows for _tool == _Tool.pipe. For thin and dashed line tools, snap is off and there's no visual feedback indicating that. User draws a line, it doesn't snap, they wonder whether the system failed.
- **why it matters**: Inconsistent behavior between line types creates a "is it broken?" moment.
- **suggested fix**: Add a small label near the drag-start point reading "WOLNA RĘKA" when drawing a non-snap line tool.
- **effort**: S

- **severity**: low
- **location**: lib/screens/iso_notebook_screen.dart:1270-1298 (_longPress) + 1303-1315 (_toastDeleted)
- **issue**: Long-press is a single-action deletion trigger for every element type — _longPress deletes immediately and shows snackbar with Undo. No visual preview (e.g. red flash on the element about to be removed). On a busy drawing with 50+ elements, a long-press near a junction can delete either the elbow OR the segment (depends on which is closer at _s*0.6 vs _s*0.5 thresholds).
- **why it matters**: Ambiguous hit-test radius + immediate deletion = "I deleted the wrong thing." Undo snackbar duration 4 s is short for a confused user.
- **suggested fix**: Increase Undo snackbar duration to 8 s for long-press deletions. Add a brief 200 ms red-highlight animation on the element being removed before it disappears.
- **effort**: M

--- end block ---

## Iter #2 · lib/screens/iso_scanner_screen.dart · input-validation

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:108-142 (_pickImage)
- **issue**: No validation of the picked file beyond `path != null`. The file picker can return a path to a non-image (HEIC/PDF/MOV via OEM "Files" pickers that ignore `type: FileType.image`), an empty 0-byte placeholder (cloud-stub from Google Photos / iCloud not yet downloaded), or a path that no longer exists by the time `Image.file` opens it. Result: blank black canvas + AI call against a non-image that wastes a Vision API token and surfaces a generic "not an isometric" toast — fitter doesn't know it's a picker problem.
- **why it matters**: Welder on jobsite WiFi often picks a cloud-stub photo that hasn't synced. They see a black tile, hit "Analizuj AI", wait 60 s of nudge spinners, then get "to nie wygląda na rysunek izometryczny" — confusing and costs an API call each time.
- **suggested fix**: After picking, validate `File(path).existsSync()`, `lengthSync() > 1024`, and lowercased extension in {jpg,jpeg,png,webp,heic}; otherwise show a specific PL/EN toast ("Plik pusty / nie pobrany z chmury") and skip the AI button.
- **effort**: S

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:145-176 (_runAiAnalysis)
- **issue**: `_runAiAnalysis()` is invokable as soon as `_imagePath != null`, but there is no upper bound on file size. A 12-megapixel HDR photo from a flagship phone is 8-15 MB; Sonnet Vision charges per image but also the request body has to traverse Railway over 4G — easy to hit the proxy 25 MB limit or the model's 5 MB practical cap. No client-side resize/compress before upload (this screen doesn't, and even if `scanIsoImage` does it internally, no UI feedback when a file is obviously too large).
- **why it matters**: Workshop floors usually mean spotty signal; failing 8 MB uploads after 30 s of "Wysyłam zdjęcie do AI…" then crashing with a generic catch-all toast at line 228 leads users to retry repeatedly, racking up API spend and frustration.
- **suggested fix**: Add a `File(path).lengthSync()` guard: if > 8 MB, refuse and toast with size + suggestion to compress; ideally pre-shrink to <=2048 px long edge with the `image` package before passing to `scanIsoImage`.
- **effort**: M

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:69-83 (_Segment.cutMm) + 572-579 (_totalCutMm)
- **issue**: `cutMm` sums deducts but accepts ANY parse-able expression including negative values (`-50`) and pathological large numbers. A typo of "-100" in a deduct (user types literal minus thinking the UI prefix will be added) actually ADDS 100 mm to the cut. Likewise the ISO field accepts negative results (e.g. user types `300-3000`) and the screen happily shows negative CUT in red (line 1314) but `_totalCutMm` still SUMS that into the grand total, silently corrupting the cut list. No min/max sanity bounds on the ISO field (the 0-5000 mm guard at line 1410 is only on the deduct).
- **why it matters**: A -2700 mm segment in a 30-segment cut list pulls 2.7 m off the project total. Welder reads grand total, cuts 2.7 m too little stock. Real-world cost in scrap pipe.
- **suggested fix**: In `_totalCutMm` skip non-finite OR negative `cutMm`; surface a top-of-list warning chip "X segments with invalid CUT — excluded from total". Add the same `outOfRange` check on the ISO TextField errorText at line 1346 (e.g. cut < 0 or > 100000 mm).
- **effort**: S

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:1417-1418 (_SegmentCard deduct field)
- **issue**: Deduct field declares `keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true)` but the iso_parser accepts full expressions (`5*200+150`, parentheses, `x` / `×`). The signed numeric keyboard on Android hides `*`, `(`, `)`, `+` switches, so a fitter who types an expression in the ISO row but pastes one into a deduct can't easily do the same — they must long-press into the multi-line text editor. Worse, the keyboard's minus glyph differs across IMEs (some send Unicode U+2212) which `parseIsoExpression` rejects as "bad chars" (line 35 of iso_parser).
- **why it matters**: Fitter types "-76" copied from a flange spec PDF, sees red "Sprawdz skladnie" — assumes their value is wrong, types it again. Hidden Unicode minus is one of the top causes of "but I typed it right!" bug reports for measurement apps.
- **suggested fix**: Normalize input pre-parse in `parseIsoExpression` to convert U+2212, U+2010..U+2015 to ASCII `-`; allow the Unicode minus in the regex on line 35. Also document accepted glyphs in the field hint.
- **effort**: S

- **severity**: high
- **location**: lib/screens/iso_scanner_screen.dart:244-276 (_applyAiResult)
- **issue**: `aiSeg.dimensionMm` is trusted blindly: `seg.iso.text = aiSeg.dimensionMm!.toStringAsFixed(0)`. No clamp on the value — a Vision hallucination of `-150` or `999999999.0` would fill the segment with garbage that then propagates to `_totalCutMm`. Similarly, `aiSeg.rawDimension` is dropped verbatim into a TextField that the parser will choke on if AI returns something with units (`"525 mm"`), arrows, or non-breaking spaces.
- **why it matters**: AI vision occasionally hallucinates on poor photos; a single wrong segment in a 20-segment auto-filled list is invisible to the user (they trust the AI, move on). Total cut on the clipboard is wrong, stock is cut wrong.
- **suggested fix**: After `parseIsoExpression(aiSeg.rawDimension)` succeeds, also validate `0 < value < 100000`; if not, leave the segment blank and add the AI-suggested raw value to `result.uncertainty` so the user reviews it explicitly.
- **effort**: M

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:269-272 (titleBlock lineNumber as project name)
- **issue**: `tbLine` from the AI title-block is poured directly into `_projectName.text` with no length cap and no character sanitisation. AI returns junk like `"LINE: 6\"-CWS-1234\\nSCHEDULE 40"` and that newline survives into clipboard output (lines 586-589) where it breaks the format of the cut list header. No `.replaceAll(RegExp(r'\\s+'), ' ').trim()` and no maxLength on the `_projectName` TextField (line 756).
- **why it matters**: When a welder copies the summary to Teams/WhatsApp the line break inside the project header makes the message look corrupted; foreman thinks the app glitched.
- **suggested fix**: Sanitise tbLine via trim + collapse-whitespace + clamp to ~60 chars before assigning. Add `maxLength: 80` + `inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\\r\\n]'))]` to the project-name TextField.
- **effort**: S

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:1344-1361 (segment ISO TextField)
- **issue**: No `maxLength` on the ISO expression; no input formatter to strip pasted Unicode. A user pasting a value from a spec sheet PDF may bring in zero-width space (U+200B), narrow no-break space (U+202F) or directional marks (U+200E/F) — `parseIsoExpression` will reject as "bad chars" with a generic error and the fitter has no clue why. Also no `textInputAction` set — no `onSubmitted` to advance focus to the deduct row.
- **why it matters**: Lots of fitters paste from PDFs or scanned PFDs. Invisible chars from clipboard are a common silent failure mode.
- **suggested fix**: Add `inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\\-*Xx.,()\\s]'))]` to the ISO field; sanitise zero-width chars before parsing.
- **effort**: S

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:1402-1410 (deduct out-of-range check)
- **issue**: Out-of-range guard only triggers for parsed values in (0, 5000). The guard treats `parsed < 0` AND `parsed > 5000` as out of range — but `parsed == 0` is fine (legit "no take-out"). However the guard doesn't trigger for `parsed.isNaN` or `parsed.isInfinite`. More importantly, no validation that the deduct (when positive) is LARGER than the parent ISO — a 6000 mm deduct on a 3000 mm ISO yields negative CUT and the only feedback is a red total at line 1314.
- **why it matters**: A fitter mis-typing a deduct (e.g. swaps gasket 3 mm for valve+gasket 300 mm) silently makes the cut list go negative on that segment without an inline error indicator on the deduct row itself.
- **suggested fix**: Extend `outOfRange` to also flag when the deduct would push CUT below 0 (compare against parent `parseIsoExpression(segment.iso.text)`). Surface a per-deduct warning icon, not just the red total.
- **effort**: M

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:1383-1391 (deduct name TextField)
- **issue**: Deduct name accepts arbitrary text including newlines and 1000+ characters. That string flows into the clipboard summary at line 611 (`'       - $tag: ${d.value.text.trim()}'`). A multiline tag corrupts the cut-list format; an overly long tag pushes the value off the right edge in messaging apps.
- **why it matters**: Cut list shared to WhatsApp/Teams becomes hard to read and the foreman might misread component identity.
- **suggested fix**: `maxLength: 24`, `inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\\r\\n]'))]`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:584-623 (_copySummary)
- **issue**: Copy is allowed when `_dimensionedCount > 0`, but produces output even when EVERY segment has `parseError`. The summary shows "(nieczytelne)" lines but ALSO a "Suma CUT" that is the sum of only the parseable subset. There is no "X of Y segments unreadable — review before sharing" warning. Worse, `_imagePath` is included in the summary as the file basename (line 591) — leaking potentially private path / project filename from the user's gallery to whoever receives the message.
- **why it matters**: A foreman receiving "Suma CUT: 12 345 mm" with three "(nieczytelne)" lines might not notice the unreadable rows and order short. Privacy: file names like "IMG_2026_BIDDER_PROJECT_X.jpg" leaking into Teams.
- **suggested fix**: Block copy (or show a confirm dialog) when any dimensioned segment has `parseError`. Make the source-file inclusion opt-in (off by default) via a checkbox; show only the file basename without dotted prefixes.
- **effort**: M

- **severity**: med
- **location**: lib/screens/iso_scanner_screen.dart:1206-1209 (_MissingInputRow apply)
- **issue**: `_pickSegmentAndApply` calls `onApply(pick, label, suggestedMm.toString())` — passing AI's `componentId` directly as the deduct name. If AI returned `componentId: "FL-100\\n(field)"` with embedded newlines or non-ASCII, that string ends up in the cut-list clipboard summary verbatim. Also `suggestedMm.toString()` of an int cannot represent fractional take-outs (B16.9 LR DN50 = 76.2 mm rounds to 76 today, but if the upstream returns a double in the future, `.toString()` may yield "76.19999999999"). No formatting safeguard here.
- **why it matters**: Field welds and orbital sanitary marks often include glyphs that don't render the same way across messaging apps. Future-proofing for B16.9 inch sizes (which ARE fractional in mm) needs explicit handling now or it will silently regress.
- **suggested fix**: Sanitise label `(need.componentId ?? need.type).trim().replaceAll(RegExp(r'[\\r\\n\\t]+'), ' ')` and clamp length to ~24 chars; format value with `.toStringAsFixed(1)` once and trim trailing `.0`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/iso_scanner_screen.dart:756-766 (project name TextField)
- **issue**: No `maxLength`, no `inputFormatters`, no `textCapitalization`. Project names are usually `6"-CWS-1234` style codes (caps, no spaces) — the soft keyboard defaults to lowercase + autocorrect ON, which causes "cws" -> "cwd" type corrections silently. Also no clear button to wipe a long pasted string.
- **why it matters**: Misspelled line names in shared cut lists; foreman can't match against the official iso index.
- **suggested fix**: `textCapitalization: TextCapitalization.characters`, `autocorrect: false`, `maxLength: 80`, suffix clear icon.
- **effort**: S

- **severity**: low
- **location**: lib/screens/iso_scanner_screen.dart:75-83 (cutMm silently swallows deduct parse errors)
- **issue**: When ONE of several deducts has a syntax error, the catch-all `catch (_) {}` at line 80 silently skips it and the segment's CUT is computed against the remaining deducts — no per-deduct indicator that the value was excluded. The deduct field itself does not render `errorText` for parse errors (only for out-of-range, line 1423).
- **why it matters**: Fitter typing "abc" in a deduct sees CUT compute as if that deduct were 0. Silent skip = wrong number, no feedback.
- **suggested fix**: Promote the per-deduct `errorText` builder to also flag parse failure: "Niepoprawny zapis — pomijam w sumie".
- **effort**: S

- **severity**: low
- **location**: lib/screens/iso_scanner_screen.dart:899-905 (_ImageViewer Image.file)
- **issue**: `Image.file(File(path))` with no `errorBuilder`. If the picked file disappears between selection and render (cloud-sync evict, OS deletes temp), the widget throws and a partial gray tile renders with no recovery affordance.
- **why it matters**: Fitters on storage-low phones get this regularly (OS purges photo cache).
- **suggested fix**: Provide `errorBuilder` that shows "Plik niedostepny — wybierz ponownie" with a tap-to-rePick CTA.
- **effort**: S

--- end block ---

## Iter #3 · lib/screens/weld_journal_screen.dart · async-crash-safety

- **severity**: high
- **location**: lib/screens/weld_journal_screen.dart:195-199 (_load)
- **issue**: `_load()` calls `setState(() => _loading = true)` synchronously, then `await _dao.listAll()`, then a second `setState` with the result — neither setState is guarded by `mounted`. If the user backs out of the journal while the SQLite query is in flight (cold-start can take 100-500 ms on budget Android with a big weld_journal table plus the seven ALTER TABLE migrations in `_ensureTable`), the second `setState` fires on a disposed State and throws `setState() called after dispose()`. The exception bubbles into the navigator stack.
- **why it matters**: Fitter taps "Dziennik spoin" by mistake, immediately taps back. App crashes mid-shift. They reopen, lose context of what they were doing. On Android the crash sometimes triggers ANR if the rebuild kicks off in the same frame.
- **suggested fix**: Wrap both setStates in `if (!mounted) return;`. Also wrap `_dao.listAll()` in try/catch so a DB exception clears `_loading=false` and surfaces a SnackBar instead of leaving the spinner up forever.
- **effort**: S

- **severity**: high
- **location**: lib/screens/weld_journal_screen.dart:352-357 (_cycleStatus)
- **issue**: `_cycleStatus` mutates `e.status = next` BEFORE awaiting `_dao.update(e)`, then awaits `_load()`. No try/catch. If SQLite throws (locked DB, concurrent write from a pending `_save`, mid-migration), the in-memory entry is already mutated to the new status but never persisted — visible UI disagrees with DB until the next `_load`. Also `_load` then setStates with no `mounted` check.
- **why it matters**: Welder taps the OK badge to cycle to NOK on a defective weld. If the write fails silently, the badge shows NOK but the database still says OK — when they reopen the journal the bad weld appears OK again. Audit/traceability gets corrupted; QC may not catch a NOK weld that the welder flagged.
- **suggested fix**: Wrap in try/catch; on failure revert `e.status` to its prior value, show a SnackBar "Nie zapisano — sprobuj ponownie", add `if (!mounted) return;` before `_load`.
- **effort**: S

- **severity**: high
- **location**: lib/screens/weld_journal_screen.dart:359-376 (_delete)
- **issue**: After `await showDialog<bool>(...)` line 375 does `await _dao.delete(e.id); await _load();` with no `mounted` check between awaits and the setState inside `_load`. No try/catch around `_dao.delete` either — if it throws (table missing, FK constraint, locked DB), the dialog already closed showing "deleted" outcome, the entry stays in the list, the user thinks the row was removed.
- **why it matters**: Fitter deletes a wrongly-numbered weld during shift. If it silently fails, the wrong weld stays in the journal, gets exported to the PDF report submitted to QC. Worst case: a weld marked for deletion because of wrong heat number lingers and confuses the auditor.
- **suggested fix**: Wrap delete+load in try/catch; on failure show SnackBar. Add `if (!mounted) return;` after the dialog await and before `_load`.
- **effort**: S

- **severity**: high
- **location**: lib/screens/weld_journal_screen.dart:573-604 (_WeldEditorState._save)
- **issue**: `_save` sets `setState(() => _saving = true)` then awaits `_dao.insert` / `_dao.update` with NO try/catch and NO setState-back to `false` on error. If the DAO throws (disk full, schema mismatch from a half-applied migration, SQLite locked from concurrent `_cycleStatus`), `_saving` stays true forever, the button stays disabled, and the modal sheet stays open with "Zapisywanie..." frozen. The only escape is to swipe the sheet down — which loses every field the welder typed (notes, heat numbers, WPS ref, exam result, fitter name). No autosave / draft.
- **why it matters**: Welder spent 30 s typing two heat numbers + WPS ref + exam result for an ASME BPE traceable joint. Save fails (rare but real on cheap Android with low storage). They lose everything and have to retype. On the workshop floor with gloves this is a 90 s tax per failure — they will stop logging welds.
- **suggested fix**: try { await save } catch (e) { if (mounted) setState(() => _saving = false); show SnackBar with retry; }. Ideally serialise the controllers to SharedPreferences on every onChanged so a crash/swipe doesn't lose work.
- **effort**: M

- **severity**: high
- **location**: lib/screens/weld_journal_screen.dart:602-603 (_save success path)
- **issue**: `if (!mounted) return;` then `Navigator.pop(context, true)`. The mounted check guards the pop, but `_saving` was set true at line 575 and is never reset on the error path — even mounted-correct, this strands the sheet. Together with the missing try/catch above, any DAO exception wedges the editor.
- **why it matters**: Same as above — stuck "Zapisywanie..." with welder unable to retry without losing the form.
- **suggested fix**: Always reset `_saving` to false in a finally block (gated on `mounted`).
- **effort**: S

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:378-391 (_openEditor)
- **issue**: After `await showModalBottomSheet<bool>(...)` line 390 does `if (result == true) await _load();` with no mounted check. If the parent screen is popped immediately after the sheet returns true (e.g. user backs out of the journal as soon as save completes), `_load` will setState on a disposed widget.
- **why it matters**: Edge-case crash on fast taps. Rare but reproducible on slow devices where the navigator transition outpaces the load.
- **suggested fix**: Add `if (!mounted) return;` at the start of `_load` (one fix covers all callers).
- **effort**: S

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:707-726 (date picker onPressed)
- **issue**: `onPressed: () async { ... final picked = await showDatePicker(context: context, ...); if (picked != null) { _dateCtrl.text = ...; } }` — no `mounted` check after the await. `showDatePicker` uses the editor's `context` which lives inside a modal bottom sheet; if the user swipes the sheet down while the picker is still open, the State disposes and the date picker's then-callback mutates `_dateCtrl` on a disposed controller (the controllers are disposed in the loop at line 562).
- **why it matters**: Welder opens the date picker, gets distracted by the shop, swipes the sheet away to take a call, comes back — app crashes with "TextEditingController used after disposal".
- **suggested fix**: After the await: `if (!mounted) return;` then mutate `_dateCtrl.text`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:112-148 (_ensureTable migration loop)
- **issue**: Seven sequential `ALTER TABLE ... ADD COLUMN` are each wrapped in a bare `catch (_) {}`. The intent is to absorb "column already exists" but the catch also swallows "database is locked", "disk I/O error", "no such table" — any of which mean the migration is broken but the next `db.query` returns wrong-shaped rows. Combined with `_load` having no error handling, a partial migration silently corrupts the journal.
- **why it matters**: After a major app update (new BPE columns being added), if the migration partly fails the journal shows old entries fine but every NEW save will fail because the column doesn't exist. The save failure cascades into the wedged "Zapisywanie..." state from finding #4.
- **suggested fix**: Inspect the exception message; only swallow when it contains "duplicate column" / "already exists". Re-throw everything else and let the outer `_load` / `_save` show an error.
- **effort**: M

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:150-155 (WeldJournalDao.listAll) + _load error path
- **issue**: `listAll` returns `await db.query(...)`. No error path. If the DB is locked (concurrent transaction), corrupted, or the migration left the table in an inconsistent state, the throw propagates up to `_load` which has no try/catch — the second setState (line 198) never runs, `_loading` stays `true`, and the journal screen shows the orange spinner indefinitely with no recovery except killing the app.
- **why it matters**: "App is hung on the spinner" is the #1 complaint pattern for SQLite-backed Flutter apps. Welder force-quits, loses state in other screens.
- **suggested fix**: try/catch around `_dao.listAll()` in `_load`; on error setState `_loading = false`, `_entries = []`, surface an error placeholder with a retry button.
- **effort**: S

- **severity**: med
- **location**: lib/screens/weld_journal_screen.dart:625-631 (auto-number suffixIcon onPressed)
- **issue**: The auto-number IconButton calls `widget.suggester(_projCtrl.text)` inside setState. `widget.suggester` is `suggestNextWeldNo` from the parent state and reads `_entries` from the parent. If the parent was disposed while the sheet is still open (split-screen reconfiguration, external display attach), this accesses fields of a disposed State. Synchronous so no await — but the parent's `_entries` may have been GC-eligible.
- **why it matters**: Edge-case crash on split-screen / external display attach. Fitters increasingly use phones plugged into shop monitors; reconfiguration is real.
- **suggested fix**: Have the editor cache the parent's entries (or just the max numbers) at constructor time and compute suggestions locally — eliminates the cross-State call.
- **effort**: M

- **severity**: low
- **location**: lib/screens/weld_journal_screen.dart:193 (initState calling _load)
- **issue**: `initState() { super.initState(); _load(); }` fires an unawaited future from initState. Standard Flutter pattern, but combined with the missing mounted checks in `_load` this is the root entry point for the crash chain in finding #1.
- **why it matters**: Already covered above — flagged here as the call site.
- **suggested fix**: Same — make `_load` mounted-safe end-to-end.
- **effort**: S

- **severity**: low
- **location**: lib/screens/weld_journal_screen.dart:360-374 (delete dialog uses outer context for Navigator.pop)
- **issue**: `_delete` builder is `(_) => AlertDialog(...)` but the buttons call `Navigator.pop(context, ...)` where `context` is the *outer* parent State's BuildContext (captured by closure), not the dialog's local context. Works today because the dialog route is mounted on the parent navigator, but it's an unsafe pattern that bypasses proper nested-navigator dismissal — and Navigator.pop's context lookup may yield a different navigator if anything is mounted between them.
- **why it matters**: Doesn't crash today. Flagged so a future refactor that adds a nested navigator doesn't silently regress.
- **suggested fix**: Use the builder's own context: `builder: (ctx) => AlertDialog(... onPressed: () => Navigator.pop(ctx, true) ...)`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/weld_journal_screen.dart:557-566 (dispose loop)
- **issue**: Dispose iterates 15 controllers and calls `c.dispose()` on each. If any one throws (double-dispose race during hot-reload, or a controller never initialised because a future refactor adds an early-return in initState), the remaining controllers leak.
- **why it matters**: Memory leak after hot-reload during dev; on shipped builds also possible if future refactor introduces early-return in initState.
- **suggested fix**: Wrap each dispose in try/catch, or accept the minor risk.
- **effort**: S

- **severity**: low
- **location**: lib/screens/weld_journal_screen.dart:603 (Navigator.pop after save chained into parent _load)
- **issue**: After save completes, parent's `_openEditor` continuation does `if (result == true) await _load();`. That `_load` has no mounted check. Narrow timing window: the editor pops, the parent rebuilds with `result==true`, parent's `_load` setStates — meanwhile if a system back gesture also unmounts the journal screen, the second setState throws.
- **why it matters**: Chained issue; covered by findings #1 and #6.
- **suggested fix**: Same as finding #1 — make `_load` mounted-safe end-to-end.
- **effort**: S

--- end block ---

## Iter #4 · lib/screens/jobs_screen.dart · loading-error-empty-states

- **severity**: high
- **location**: lib/screens/jobs_screen.dart:181-209
- **issue**: Error UI only shown when `_error != null && _listings.isEmpty`; if a refresh fails after listings already loaded, the error is silently swallowed — user sees stale list with no toast/banner/snackbar indication that refresh failed.
- **why it matters**: A welder pulls-to-refresh hoping to see a new posting; network drops, list stays the same, they assume there are no new jobs. They miss work.
- **suggested fix**: When `_error != null && _listings.isNotEmpty`, show a one-shot SnackBar in `_load()` catch block ("Nie udało się odświeżyć — pokazuję zapisane dane").
- **effort**: S

- **severity**: high
- **location**: lib/screens/jobs_screen.dart:75-111 (`_addNew`)
- **issue**: After Stripe checkout returns `true`, the screen polls silently for up to 12 s with no visible loader, no progress hint, no "czekamy na potwierdzenie płatności" banner. User just sees the same list and may tap Add again, double-paying.
- **why it matters**: Fitter just spent 49 zł on a featured listing; UI gives zero feedback that the system is waiting for the webhook. Trust crisis + duplicate-charge risk.
- **suggested fix**: Set a `_waitingForWebhook = true` flag during the polling loop and render a top banner / inline spinner with text "Czekamy na potwierdzenie płatności…"; disable the Add FAB + AppBar action while it's true.
- **effort**: M

- **severity**: high
- **location**: lib/screens/jobs_screen.dart:104-106 (`catch (_) {}` inside `_addNew` poll)
- **issue**: Transient errors inside the 12 s polling loop are silently swallowed; if ALL 8 attempts fail (no network), the fallback `_load()` may also fail and the user lands on an empty list with no explanation of why their paid listing is missing.
- **why it matters**: User just paid via Stripe but offline-mode hits at the wrong moment; UX silently degrades to "your money disappeared".
- **suggested fix**: Track last error from poll loop; if all attempts fail, show SnackBar with action "Sprawdź połączenie i odśwież — Twoje ogłoszenie pojawi się po opłaceniu (webhook)".
- **effort**: S

- **severity**: med
- **location**: lib/screens/jobs_screen.dart:210-211 (`_listings.isEmpty` branch)
- **issue**: Empty state does not differentiate between "no listings exist at all" and "filter returned zero results". User who typed "Płock" into the filter sees the generic "Be the first — publish a listing" message, suggesting nothing exists anywhere.
- **why it matters**: Welder filters by their city, sees the generic empty state, concludes the whole module is dead — never tries clearing the filter to see jobs elsewhere.
- **suggested fix**: If `_filterCtrl.text.trim().isNotEmpty`, render a distinct empty state: "Brak ogłoszeń dla \"{filter}\". [Wyczyść filtr]".
- **effort**: S

- **severity**: med
- **location**: lib/screens/jobs_screen.dart:69 (`_error = e.toString()`)
- **issue**: Raw exception `toString()` is stored but the UI on lines 191-198 doesn't actually display it — only a generic "Brak połączenia z modułem Praca / Jobs module unreachable" message. For 401/403/500 backend errors this is misleading (the network may be fine).
- **why it matters**: A 401 from an expired session looks identical to "no internet"; user retries forever instead of re-logging or contacting support.
- **suggested fix**: Distinguish error types (Socket/Http/Timeout vs auth vs unknown) and render an appropriate icon + message; optionally show `_error` in a small monospace block under the headline for debugging.
- **effort**: M

- **severity**: med
- **location**: lib/screens/jobs_screen.dart:177-180 (loading state)
- **issue**: Centered `CircularProgressIndicator` only — no skeleton list, no "Ładuję ogłoszenia…" caption. On a slow 3G connection in a workshop basement the spinner can run 5-8 s with no context, indistinguishable from a hang.
- **why it matters**: Workshops often have weak signal; fitter assumes app froze, force-quits, loses cached filter text.
- **suggested fix**: Replace with 3-4 shimmer skeleton job cards or add a "Ładuję ogłoszenia…" label below the spinner with a 6 s timeout that prompts "Wolne połączenie — kontynuuj czekanie / Spróbuj ponownie".
- **effort**: M

- **severity**: med
- **location**: lib/screens/jobs_screen.dart:173 (`onChanged: (_) => setState(() {})`)
- **issue**: Filter `TextField` rebuilds on every keystroke (for the clear-button suffix) but does NOT trigger a fresh `_load()` until `onSubmitted`. No loading indicator while user is mid-typing — they can't tell whether the list is stale or current.
- **why it matters**: Welder types "Płock", sees the same listings as before — no spinner, no indication "results not updated until you press Enter". Confusing on a 6" phone with a virtual keyboard.
- **suggested fix**: Either debounce + auto-reload on `onChanged`, or render a subtle "Naciśnij Enter aby filtrować" hint above the list when the filter text differs from the active query.
- **effort**: M

- **severity**: low
- **location**: lib/screens/jobs_screen.dart:468-718 (`_JobDetailScreen`)
- **issue**: Detail screen has no loading or error state at all — it renders directly from the `JobListing` passed via constructor. If the underlying record becomes stale (deleted server-side, edited by webhook between list and detail open), the user sees outdated info with no refresh affordance.
- **why it matters**: Edge case — relevant once Firestore sync lands; for MVP local-first DB this is mostly fine. Flag as low.
- **suggested fix**: Add a pull-to-refresh on the detail ListView that re-fetches by id; show "Ogłoszenie zostało usunięte / Listing no longer available" if the fetch returns null.
- **effort**: M

- **severity**: low
- **location**: lib/screens/jobs_screen.dart:700-710 (delete confirmation flow)
- **issue**: After the user confirms deletion in the dialog, the SnackBar explains the 30-day auto-expiry — but the delete button still shows in the AppBar permanently, inviting repeated taps that all dead-end at the same SnackBar.
- **why it matters**: Minor friction; user expecting actual delete will tap, read message, dismiss, and likely try again later thinking it was a bug.
- **suggested fix**: Either remove the delete IconButton in MVP (since there is no delete API), or replace with an info-icon that opens the same "auto-expire" explanation as a dialog.
- **effort**: S

- **severity**: low
- **location**: lib/screens/jobs_screen.dart:50-73 (`_load` doesn't surface partial success)
- **issue**: `JobsService.instance.listPublic` may return cached results even when a background sync fails — there's no indicator that the displayed listings are stale (e.g. "ostatnia synchronizacja: 2 h temu").
- **why it matters**: Once Firestore sync lands this matters more; for current local-first MVP, the local DB IS the source of truth, so low priority now.
- **suggested fix**: Add a "Ostatnia aktualizacja" timestamp footer once remote sync is wired; defer until Phase 6b.
- **effort**: M

--- end block ---

## Iter #5 · lib/screens/job_add_screen.dart · i18n-coverage

- **severity**: high
- **location**: lib/screens/job_add_screen.dart:334
- **issue**: Hardcoded English field label `_Field(label: 'Email', ...)` — bypasses `context.tr` entirely. The surrounding labels ("Telefon", "Płatność") all go through `tr`, this one alone is a raw literal. Even though the word "Email" exists identically in both locales, future PL copywriting changes (e.g. "Adres e-mail", "E-mail kontaktowy") are locked out and a translation audit script will flag this as a missed key.
- **why it matters**: Inconsistency breaks i18n parity across the very same form. Polish style guides often prefer "E-mail" with hyphen; the screen can't follow company-house style. Also blocks accessibility/screen-reader label adjustments per locale.
- **suggested fix**: Replace with `label: context.tr(pl: 'E-mail', en: 'Email')` for symmetry with the "Telefon"/"Phone" pair below it.
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:285
- **issue**: Label `pl: 'Kwalifikacje (csv)', en: 'Qualifications (csv)'` exposes the technical token "csv" verbatim in both locales. Workshop-floor users typically read "csv" as a file format reference (Excel), not as "comma-separated values".
- **why it matters**: A welder posting a job in gloves, in poor light, must not be asked to parse dev jargon — comprehension hit on a mandatory field label.
- **suggested fix**: `pl: 'Kwalifikacje (po przecinku)', en: 'Qualifications (comma-separated)'`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:365-367, 377-378, 408-410
- **issue**: Price string "49 PLN" is hard-coded inside three separate `tr` calls (banner title, banner subtitle, CTA button). EN reads "Pay 49 PLN and publish" — anglophone currency convention is prefix ("PLN 49"). Also, three duplicate price tokens means changing the price requires editing three translation pairs.
- **why it matters**: Non-PL recruiter sees an unfamiliar postfix-currency layout; copy maintenance is brittle.
- **suggested fix**: Extract `JobsService.postPriceLabel` constant (e.g. "PLN 49") and interpolate; EN copy: "Pay PLN 49 and publish".
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:377-378
- **issue**: EN translation lists "Stripe (card, BLIK, Apple/Google Pay)" — "BLIK" is a Polish-only mobile-payment scheme. Non-PL viewer has no context and may assume it's a required action ("what is BLIK?").
- **why it matters**: Payment-screen friction; advertiser may abandon the 49 PLN flow.
- **suggested fix**: EN: "Stripe (card, BLIK [PL], Apple/Google Pay)" or "Stripe (card, Apple/Google Pay, local methods incl. BLIK)".
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:421-427
- **issue**: Footer disclaimer leaks the term "MVP" to end-users ("Ogłoszenie jest zapisywane lokalnie (MVP)"). A tradesperson reading "MVP" on a paid (49 PLN) screen interprets it as "unfinished/beta" and may abandon the purchase.
- **why it matters**: Trust signal on a monetized screen; product-roadmap jargon does not belong here.
- **suggested fix**: `pl: '* Pola wymagane. Aktualnie ogłoszenia są zapisywane na tym urządzeniu — synchronizacja w przygotowaniu.', en: '* Required fields. Listings are currently stored on this device — cross-device sync coming soon.'`
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:278
- **issue**: Rate hint "np. 150 PLN/h netto" / "e.g. 150 PLN/h net" — "netto"/"net" is PL accounting jargon. EN-locale poster unfamiliar with VAT-net conventions may post wrong rate (gross vs net of VAT).
- **why it matters**: Pricing transparency for cross-border posters; recruiters from DE/UK may mis-state pay.
- **suggested fix**: EN: "e.g. 150 PLN/h (net of VAT)"; PL: "np. 150 PLN/h netto (bez VAT)".
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:299-303
- **issue**: Instruction "Stuknij chip aby dodać do wymagań" / "Tap a chip to add it to requirements" uses Material-design term "chip". PL user reads "chip" as SIM-card chip, not as a UI tag-button. Comprehension miss.
- **why it matters**: First-time discoverability of the requirement-preset feature — a fitter who doesn't grasp "chip" ignores the helper and types every qualification manually.
- **suggested fix**: `pl: 'Stuknij etykietę aby dodać (bez duplikatów):', en: 'Tap a tag to add it (no duplicates):'`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:212-214
- **issue**: Catch-all error SnackBar copy assumes network failure ("Sprawdź połączenie." / "Check your connection.") but the try/catch (line 206) swallows every exception — including 400 (validation), 401 (auth), JSON-parse, etc. Misleads diagnostics for both locales.
- **why it matters**: Welder on solid wifi receiving a server 400 toggles airplane-mode trying to "fix" the connection — wasted time on a real workshop floor.
- **suggested fix**: Branch on `e is SocketException` to keep the network copy; otherwise surface `e.toString()` truncated, or use a generic `pl: 'Nie udało się utworzyć płatności. Spróbuj ponownie.', en: 'Could not create payment. Please try again.'`.
- **effort**: M

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:406
- **issue**: Loading-state button label `pl: 'Tworzę sesję…'` uses first-person Polish ("I am creating"). Modern PL UIs prefer impersonal noun forms ("Tworzenie sesji…") consistent with Material PL guidelines and the rest of the codebase.
- **why it matters**: Tone consistency across the app; first-person feels off when the *system* is doing the action.
- **suggested fix**: `pl: 'Tworzenie sesji płatności…', en: 'Creating payment session…'`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:131, 136
- **issue**: Discard dialog EN buttons are "Keep editing" / "Discard" — the destructive label "Discard" alone is ambiguous (discard what?). PL counterpart "Porzuć" has the same brevity issue.
- **why it matters**: Standard UX heuristic: destructive actions should carry the noun ("Discard changes").
- **suggested fix**: `pl: 'Porzuć zmiany', en: 'Discard changes'` — matches the dialog title "Discard changes?".
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:438-460 (`_buildReqChips` + Tooltip interpolation at 444-447)
- **issue**: Tooltip translation interpolates the requirement tag into PL/EN templates (`pl: 'Dodaj $tag do wymagań'`). `_chipCache` is keyed on `AppLanguage` only — if `_commonReqs` is ever changed to a dynamic / backend-driven list, stale tooltips will leak. Currently safe because list is `static const`, but the invariant is undocumented.
- **why it matters**: Latent foot-gun the day someone makes the preset list user-customizable (a foreseeable feature request).
- **suggested fix**: Add a code-comment: `// _chipCache assumes _commonReqs is immutable; if it becomes dynamic, invalidate cache on list mutation in addition to lang change.`
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:324
- **issue**: Description hint ends with U+2026 ellipsis "…" — TalkBack (PL TTS) pronounces it awkwardly as "wielokropek" or "trzy kropki". Cosmetic but reduces accessibility for vision-impaired users.
- **why it matters**: Screen-reader users get a noisy ending on the hint narration.
- **suggested fix**: Drop the ellipsis: `'Zakres prac, obiekt, czas trwania zlecenia, zakwaterowanie'` (no trailing punctuation).
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:256, 278, 288
- **issue**: Multiple hints use em-dash "—" (U+2014) instead of hyphen "-" — visually cramped at `fontSize: 12` on Android Material text-field hints, and harder to type if user wants to mimic the format.
- **why it matters**: Minor legibility hit in workshop lighting / small phones.
- **suggested fix**: Replace " — " with " - " (ASCII hyphen-minus) in all three hint strings.
- **effort**: S

--- end block ---

## Iter #6 · lib/screens/saddle_template_screen.dart · perf-rebuilds

- **severity**: med
- **location**: saddle_template_screen.dart:60-92 (_recompute) + 286, 293 (text-field onChanged)
- **issue**: every keystroke in header/branch TextFields calls `_recompute()` which constructs a fresh `SaddleTemplate` (72-point sampling with math.sin/cos per point) inside `setState`, rebuilding the entire ListView + CustomPaint + metrics row + marker-step hint.
- **why it matters**: a fitter tapping "114.3" on a phone glove-keyboard triggers 5 full template recomputes + 5 rebuilds of the whole screen during the typing burst, causing visible lag and frame drops on entry-level Android devices common on a workshop floor.
- **suggested fix**: debounce `_recompute` ~150ms via a `Timer` started inside `onChanged` (cancel previous on each keystroke); slider and preset chips can still call it immediately.
- **effort**: S

- **severity**: med
- **location**: saddle_template_screen.dart:314-325 (Slider onChanged)
- **issue**: dragging the angle slider fires `setState(() => _angleDeg = v)` + `_recompute()` on every continuous tick — easily ~60 events/sec while the welder drags, each rebuilding ListView/CustomPaint and re-sampling 72 trig points.
- **why it matters**: dragging the angle from 90° down to 30° on a budget device gives stuttery preview and burns battery; the workshop user perceives the tool as sluggish for what should be a smooth scrub.
- **suggested fix**: throttle slider-driven recomputes (only recompute on `onChangeEnd` or on integer-degree boundaries, while keeping the `_angleDeg` label updated cheaply via a separate ValueListenable).
- **effort**: S

- **severity**: med
- **location**: saddle_template_screen.dart:263-481 (single ListView holds all sections)
- **issue**: the whole screen is one ListView whose children rebuild together when ANY setState runs (input change, slider tick, angle preset, exporting flag). Preview card, metrics row, error box, info footer all rebuild even when only `_exporting` flips.
- **why it matters**: tapping "Export PDF" toggles `_exporting` true→false, rebuilding the CustomPaint preview and re-running `_mmAsFeetInches`/string format on metrics for no reason — extra jank precisely when the welder is staring at the spinner.
- **suggested fix**: isolate `_exporting`-dependent button into its own `StatefulWidget` (or `ValueListenableBuilder<bool>`) so only it rebuilds; same pattern for the `_angleDeg` readout.
- **effort**: M

- **severity**: med
- **location**: saddle_template_screen.dart:781-887 (_CutProfilePainter.shouldRepaint + construction at 762)
- **issue**: `shouldRepaint` correctly compares 3 numeric fields of `template`, BUT `_PreviewCard` builds a NEW `_CutProfilePainter(template)` instance on every parent rebuild — including ones unrelated to template change (exporting flag toggle, focus change). RenderCustomPaint always re-evaluates with a new painter object.
- **why it matters**: extra raster work for ~72 points + fill + stroke + 5 text labels + grid lines every time the screen rebuilds. On low-end Android the preview redraw cost shows up as a frame budget hit during typing.
- **suggested fix**: cache `_CutProfilePainter` keyed by template identity, or memoize the fill/stroke `Path` objects; wrap CustomPaint in a `RepaintBoundary`.
- **effort**: M

- **severity**: med
- **location**: saddle_template_screen.dart:757-766 (CustomPaint without RepaintBoundary)
- **issue**: CustomPaint for the cut profile lives inside a scrollable ListView with no `RepaintBoundary` wrapper — every ListView paint pass (scroll, sibling rebuilds) can dirty the layer containing the preview.
- **why it matters**: scrolling the page (info card, export button below) repaints the heavy preview pixel-pushing path each frame on weak GPUs.
- **suggested fix**: wrap the `AspectRatio(child: ClipRRect(child: CustomPaint(...)))` in a `RepaintBoundary`.
- **effort**: S

- **severity**: med
- **location**: saddle_template_screen.dart:389-423 (marker-step hint inside Builder)
- **issue**: the `Builder` recomputes `stepMm = stripLengthMm / (points.length - 1)` and `stepDeg = 360 / (points.length - 1)` on every rebuild, allocates a fresh `Row` + `Icon` + `Text` tree each time, and runs `context.tr(...)` string interpolation.
- **why it matters**: minor per-frame overhead during slider drags; combined with other rebuild paths it adds up.
- **suggested fix**: memoize step values when template changes (compute once in `_recompute` and store on state), extract widget as `StatelessWidget` so const Icon/Row literals can be reused.
- **effort**: S

- **severity**: low
- **location**: saddle_template_screen.dart:638-687 (_MetricsRow rebuilds + format work)
- **issue**: `_mmAsInches` / `_mmAsFeetInches` run on every parent rebuild even when `template` is unchanged (e.g. `_exporting` flip). Same for `template.points.length` access.
- **why it matters**: trivially cheap individually, but compounds inside the same ListView rebuild fan-out.
- **suggested fix**: wrap `_MetricsRow` in a `RepaintBoundary`, or hoist computation into a memoized state field updated only on `_recompute`.
- **effort**: S

- **severity**: low
- **location**: saddle_template_screen.dart:1 (`// ignore_for_file: prefer_const_constructors`)
- **issue**: file-wide lint disable hides missing `const` on many widgets (lines 129, 402, 464, 624, 912 `Icon(...)`, plus dozens of `BorderSide(color: _kBorder)` and `TextStyle(...)`). Lack of const means new Widget instances on every rebuild, defeating element/widget diffing.
- **why it matters**: hot path during slider drag / typing builds many throwaway Widget objects per second — extra GC pressure that low-end Androids feel as jitter.
- **suggested fix**: remove the file-wide ignore, then prefix `const` on all literal Icon/TextStyle/BorderSide constructors (most `_k*` colors are already `const Color(0xFF...)`).
- **effort**: M

- **severity**: low
- **location**: saddle_template_screen.dart:67-92 (_recompute setState wrapping SaddleTemplate constructor)
- **issue**: the heavy `SaddleTemplate(...)` constructor (72 trig samples) is called INSIDE the `setState` callback. setState's contract is to be cheap — work done inside still runs synchronously before the rebuild but obscures profiling.
- **why it matters**: hides actual recompute cost from DevTools timeline (shows up under build phase instead of pre-build); any exception inside surfaces as a build-time error.
- **suggested fix**: compute `final tpl = SaddleTemplate(...)` BEFORE `setState`, then assign in the setState body.
- **effort**: S

- **severity**: low
- **location**: saddle_template_screen.dart:329-337 (preset row uses `for (final preset in [30.0, ...])` inline literal)
- **issue**: the literal `[30.0, 45.0, 60.0, 75.0, 90.0]` list and 5 resulting `_AngleChip` widgets are rebuilt on every parent rebuild (every keystroke / slider tick).
- **why it matters**: 5 chip widgets × N rebuilds during a typing burst — additive churn.
- **suggested fix**: pull the list to a top-level `const _kAnglePresets = [30.0, 45.0, 60.0, 75.0, 90.0];` and isolate the preset row into a small `StatefulWidget` reacting only to `_angleDeg`.
- **effort**: S

- **severity**: low
- **location**: saddle_template_screen.dart:68, 99-100, 121, 899 (`AppLanguageController.isEnglish` read inline)
- **issue**: language flag is read via static getter inside build/recompute multiple times per rebuild (separate reads for header callout, error message, formula dialog, build body via `context.tr`).
- **why it matters**: many tiny string conditionals are re-evaluated every rebuild; if `AppLanguageController` is also a ChangeNotifier, missing subscription means stale UI on language switch (correctness side-effect).
- **suggested fix**: cache `final isEn = AppLanguageController.isEnglish` once per build at the top, pass down to subwidgets via constructor, and ensure the screen subscribes if it should rebuild on language change.
- **effort**: S

--- end block ---

## Iter #7 · lib/screens/rolling_offset_screen.dart · edge-case-zero-one

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:67
- **issue**: Angle upper bound `>= 90` allows values like 89.9999° which produce a near-zero Run (tan(89.99°) ≈ 5729, so Run ≈ trueOffset/5729) displayed as "0.0".
- **why it matters**: A fitter who fat-fingers "89.9" into custom angle gets a calculated Run of "0.0 mm" alongside a valid Travel — could be interpreted as "no run needed" when in reality the geometry is degenerate. Workshop misread.
- **suggested fix**: Tighten upper bound to `>= 89` or refuse angles where `tan(angleRad) > 50` with a sensible message ("Kąt zbyt bliski 90° — Run nieobliczalny").
- **effort**: S

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:67
- **issue**: Lower angle bound `<= 0` allows tiny values like 0.01° which produce a Run of millions of mm (Run = trueOffset/tan(0.01°) ≈ 5.7M for trueOffset=1000). No upper sanity check on output.
- **why it matters**: Fitter mistyping a custom angle (e.g. "1" missing zeros, or entering "5" thinking degrees but accidentally getting "0.5") receives nonsense output rendered as plausible-looking numbers in mm. No crash but completely wrong physical result.
- **suggested fix**: Tighten lower bound to `< 5°` (no practical pipe elbow under 5°) — show message "Kąt poniżej 5° — niewykonalny rolling offset".
- **effort**: S

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:48
- **issue**: Validation allows Rise/Spread values like 0.0001 mm which pass `> 0` check but produce True Offset that displays as "0.0" via `toStringAsFixed(1)`.
- **why it matters**: A fitter who typed ".0001" by accident before a real value (and pressed CALCULATE prematurely) sees "0.0" results — may interpret as "calculation failed" or, worse, as a valid zero-length pipe. No minimum dimensional sanity check.
- **suggested fix**: Add `if (rise < 1 || spread < 1)` warning ("Wartości poniżej 1 mm — sprawdź jednostki") OR widen result precision based on magnitude.
- **effort**: S

- **severity**: high
- **location**: lib/screens/rolling_offset_screen.dart:80-83 vs 48-66
- **issue**: When validation blocks a re-calculation (e.g., user clears Rise and taps CALCULATE), the previously computed results remain visible in the result fields. There is no clearing of stale `_trueOffsetController`/`_travelController`/`_runController` on validation failure.
- **why it matters**: Workshop floor scenario — fitter computes for pipe A (Rise=300, Spread=400), gets Travel=707.1. Switches to pipe B, clears Rise, types new value but accidentally taps CALCULATE before Spread is entered. Warning shows "Enter Rise and Spread > 0", BUT old "707.1" still sits in the Travel field. Fitter glances down, taps Copy on the stale value, welds wrong length. This is the classic edge-case-zero-one trap (one input cleared, others stale).
- **suggested fix**: On validation failure, clear all four result controllers and call `setState`. Or disable Copy buttons until inputs match the displayed results (track an `_isResultStale` flag).
- **effort**: M

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:90-93
- **issue**: `_isDirty` returns true if `_customAngleController` has text even when `_selectedAngle != 'custom'` (custom field is hidden). User who typed in custom, switched to '45', then tries to leave gets a confusing discard dialog mentioning "angle" data they cannot see.
- **why it matters**: A glove-handed fitter on the shop floor toggling angles to compare results sees an unexpected confirm dialog with no visible angle field — wastes time figuring out what's "dirty".
- **suggested fix**: Gate the custom-angle check: `(_selectedAngle == 'custom' && _customAngleController.text.trim().isNotEmpty)`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:88-93
- **issue**: `_isDirty` comment says "but not yet copied results" yet there is no copy-state tracking; field remains dirty after CALCULATE + view, so back-swipe always prompts even when fitter has already memorized/copied the number.
- **why it matters**: Annoying repeated confirm dialog after every successful calculation; trains workers to mash "Discard" reflexively, defeating the safety net.
- **suggested fix**: Track `_hasUnviewedInputChange` — set true on text change, false on successful `_calculate`. Or skip dialog if results are populated.
- **effort**: M

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:164-166
- **issue**: Custom angle field has no `textInputAction: TextInputAction.done` + `onSubmitted: (_) => _calculate()` like the Spread field. Keyboard "next" arrow on custom angle moves focus rather than triggering compute.
- **why it matters**: Inconsistent UX. A fitter using only the custom angle path (already typed Rise/Spread, came back to tweak angle) cannot submit-to-calculate; must reach for the OBLICZ button.
- **suggested fix**: Wire the same submit handler on `_customAngleController` field.
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:265
- **issue**: Regex `^\d*[.,]?\d*` accepts standalone "." or "," which `_parse` returns 0 for — but this also means a fitter who types ".5" intending 0.5 is fine, while typing just "." silently produces 0 and triggers the "Enter Rise > 0" toast with no hint that "." isn't a number.
- **why it matters**: Minor input confusion under work gloves where the user can't see what they typed. Low impact since the toast still appears.
- **suggested fix**: Either accept `^(\d+([.,]\d*)?|[.,]\d+)?$` to disallow lone separators, or improve the toast: "Wpisz pełne liczby Rise i Spread".
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:90-93
- **issue**: `_isDirty` does NOT detect change from default `_selectedAngle = '45'` to e.g. '60' — angle radio change alone is not considered dirty.
- **why it matters**: User who picked '60' (intentionally) and entered nothing, then swipes back, loses the selection silently. Low impact because angle is fast to reselect, but inconsistent with the protective intent of the PopScope.
- **suggested fix**: Include `_selectedAngle != '45'` in dirty heuristic, or persist last-used angle.
- **effort**: S

--- end block ---

## Iter #8 · lib/screens/hydrotest_screen.dart · discoverability
- **severity**: high
- **location**: lib/screens/hydrotest_screen.dart:84-100
- **issue**: No info / help icon in AppBar — the screen references ASME B31.3 § 345.4.2, PED gas, B31.1 steam, but a fitter has no in-app way to discover what these codes mean or when to pick which factor. Help entry `hydrotest-pressure` exists in `lib/data/help_entries.dart:1008` but is not linked from this screen.
- **why it matters**: On a workshop floor, a fitter selecting between 1.5x, 1.3x and 1.43x has no contextual guidance — they cannot easily leave the app to Google a standard, and a wrong factor can mean over- or under-pressurising a line. Discoverable inline help = fewer wrong tests, fewer calls to QC.
- **suggested fix**: Add IconButton(Icons.help_outline) in AppBar actions that opens the matching `hydrotest-pressure` help entry (push HelpDetailScreen).
- **effort**: S

- **severity**: high
- **location**: lib/screens/hydrotest_screen.dart:139-165
- **issue**: Three factor chips (1.5x, 1.3x, 1.43x) labelled only with code names ("ASME B31.3", "PED gaz", "B31.1 para") — no discoverable explanation of WHEN to use each. No long-press / info popup, no media-type icon (liquid vs gas vs steam).
- **why it matters**: Wrong factor = wrong test pressure. PED gas (1.3x) is for gas/pneumatic test, B31.1 (1.43x) for steam piping, B31.3 (1.5x) for process. Misapplication is a safety hazard; the only discriminator today is jargon.
- **suggested fix**: Add small media-type icon per chip (water-drop / gas / steam) + long-press tooltip with one-line "use for..." guidance, or a "Which factor?" bottom sheet.
- **effort**: M

- **severity**: high
- **location**: lib/screens/hydrotest_screen.dart:88-99
- **issue**: Copy-report button uses Icons.copy_all_outlined in AppBar without a text label; when both `volL` and `testPressure` are null it appears disabled silently — no visible hint that the user must fill OD/wall/length/design to enable it. No "Reset" / "Clear all" action either.
- **why it matters**: Fitter wonders "why can't I tap copy?" — wastes time. After one test he often needs a fresh measurement; today he must wipe each of the five fields by hand.
- **suggested fix**: Add Tooltip explaining required fields when disabled; add IconButton(Icons.refresh) reset action that clears all controllers and resets `_factor` to 1.5.
- **effort**: S

- **severity**: med
- **location**: lib/screens/hydrotest_screen.dart:101-178
- **issue**: No discoverable presets for common pipe sizes (DN50/SCH40, DN80/SCH40, DN100/SCH40 etc.) — every test requires typing OD and wall by hand. App already has pipe-geometry data elsewhere (ISO scanner, quick converter); none of it is surfaced here.
- **why it matters**: On the floor, fitters work mostly with standard schedule pipes. Manual entry of OD 60.3 / wall 3.91 for DN50 SCH40 is repetitive and error-prone (the hint "60.3" only helps if they already know which size that is).
- **suggested fix**: Add a "DN / SCH" chooser row above OD/wall (or a "Pick standard pipe" link) that auto-fills OD and wall from a lookup table.
- **effort**: M

- **severity**: med
- **location**: lib/screens/hydrotest_screen.dart:131-137
- **issue**: Design pressure label is only in bar; no toggle and no hint that the user can enter MPa or psi. Result panel shows MPa+psi for test pressure (line 208-209), but discoverability of INPUT units is missing. Quick converter even notes hydrotest is often given in MPa.
- **why it matters**: A drawing may give design pressure in MPa (EU) or psi (US clients). A fitter typing "1.6" thinking MPa instead of bar will set test pressure ~10x too low and miss the leak.
- **suggested fix**: Add bar / MPa / psi unit toggle chips above the design pressure field (default bar), or show a tiny "= X MPa" preview under the input.
- **effort**: M

- **severity**: med
- **location**: lib/screens/hydrotest_screen.dart:170-177
- **issue**: Pump flow field defaults to "40 L/min" with no UI hint that this is editable or what realistic ranges are. No presets for common pump sizes (e.g. 20 / 40 / 80 / 150 L/min electric, larger for diesel).
- **why it matters**: A new user may believe 40 L/min is a fixed assumption; an experienced user wastes time typing it. Either way, discoverability of "this is your variable" is weak.
- **suggested fix**: Tag the default with a "typowa pompa elektryczna" / "typical electric pump" hint and add 3 quick-pick chips below the field.
- **effort**: S

- **severity**: med
- **location**: lib/screens/hydrotest_screen.dart:242-251
- **issue**: "Minimum hold time: 10 min" is hard-coded into the result panel but only appears AFTER calculation. Before the user fills anything, the requirement is hidden. No discoverable "what happens during hold" guidance either (drop tolerance, gauge reading frequency, failure signs).
- **why it matters**: Hold time is the most safety-critical part of a hydrotest; if it is invisible until results render, a fitter checking the app first to plan the test gets no orientation.
- **suggested fix**: Show the 10-min minimum + one-line procedure summary as a permanent info banner near the pressure section header.
- **effort**: S

- **severity**: med
- **location**: lib/screens/hydrotest_screen.dart:101-104
- **issue**: ListView body has no empty-state instructions when the screen opens with all fields blank. A first-time user sees four input groups and three chips with zero orientation about workflow order (geometry, pressure, factor, pump, results).
- **why it matters**: Discoverability of the workflow is poor; the screen is a form, not a guided calculator. Workshop users open the tool mid-job and need to immediately know "what do I enter first?"
- **suggested fix**: Add a 1-line orientation header at top ("Wprowadz geometrie i cisnienie projektowe, aplikacja policzy test, objetosc wody i czas napelniania") or numbered steps next to section headers.
- **effort**: S

- **severity**: med
- **location**: lib/screens/hydrotest_screen.dart:294-343
- **issue**: Copy-report exists but there is no discoverable Share action (WhatsApp/email to QC) and no PDF / formatted output. Bare text in clipboard means the fitter has to paste somewhere then forward.
- **why it matters**: On site, the test result is often sent immediately to the QC engineer or supervisor over WhatsApp; an explicit share button shortens the loop.
- **suggested fix**: Add IconButton(Icons.share) in AppBar alongside the copy button that calls share_plus with the same buffer text.
- **effort**: S

- **severity**: low
- **location**: lib/screens/hydrotest_screen.dart:213-241
- **issue**: Result rows use `CopyOnLongPress` for individual values, but there is no discoverable hint (e.g. "long-press to copy") — the gesture is hidden. Many users will never find it.
- **why it matters**: Hidden affordance; users default to retyping or screen-grabbing values when they could just long-press.
- **suggested fix**: Add a one-line subtle hint under the result card, or a small icon next to the value indicating long-press copy; alternatively a Tooltip "Przytrzymaj aby skopiowac".
- **effort**: S

- **severity**: low
- **location**: lib/screens/hydrotest_screen.dart:9-16
- **issue**: Module defines its own const colour palette (`_kCard`, `_kBorder`, `_kOrange`...) duplicating tokens that exist in other screens — discoverability of "the app's design system" is hurt for future maintainers, and in-app theme drift is likely.
- **why it matters**: Indirect — workshop users notice only if a future theme update doesn't reach this screen, making it look outdated next to other tools and weakening trust.
- **suggested fix**: Pull colours from shared theme tokens (Theme.of(context).colorScheme + a shared constants file) instead of inlining.
- **effort**: S

- **severity**: low
- **location**: lib/screens/hydrotest_screen.dart:62-79
- **issue**: When wall >= 1/2 OD the error message says "Scianka >= 1/2 OD - sprawdz wymiary." with no remediation hint (did the user swap OD and wall? mix mm with inches?). The most common cause — entering inches by accident — is invisible.
- **why it matters**: A welder reading inches off a drawing types "2.375" for OD and "0.154" for wall (DN50 SCH40 inches) — the screen could detect plausibly-inch input and prompt a unit toggle.
- **suggested fix**: Extend error text with a hint "OD i scianka musza byc w mm - wpisales w calach?" and offer a one-tap unit toggle below the fields.
- **effort**: M

- **severity**: low
- **location**: lib/screens/hydrotest_screen.dart:256-287
- **issue**: Safety panel only appears AFTER results are computed (inside the `if (testPressure != null || volL != null)` block at line 193). A user exploring the screen before entering data sees no safety reminders.
- **why it matters**: Safety guidance is most useful BEFORE the test is set up; surfacing it only post-calculation reduces its discoverability and impact.
- **suggested fix**: Pin a collapsible "BHP / Safety" banner at top of screen that is always visible (or move the panel above the results).
- **effort**: S

--- end block ---

## Iter #9 · lib/screens/pipe_route_calculator_screen.dart · settings-persistence

- **severity**: high
- **location**: lib/screens/pipe_route_calculator_screen.dart:15-25
- **issue**: Zero persistence of `R` (elbow takeout) — the only value that is a *setting*, not a per-job input. Every screen entry resets `R` to "0", so the welder must re-type the CLR radius for the elbow they always use (e.g. 1.5 × DN for stocked 2"/3"/4" LR) on every single route calculation. Other workshop screens in this app (bolt_torque, pipe_schedule, material_list, iso_notebook) already use `SharedPreferences`; this screen is the odd one out.
- **why it matters**: On a real fab floor the welder typically works one pipe schedule + one elbow size per shift. Re-typing R (e.g. "57.2" for 1.5×DN 38) for every route in a 20-route iso is finger-pain + transcription errors → wrong segment lengths → scrapped pipe.
- **suggested fix**: Persist `_rController.text` to `SharedPreferences` under key `pipe_route_last_R` on every successful `_calculate()`, restore in `initState()`. Same pattern as `bolt_torque_screen.dart`.
- **effort**: S

- **severity**: high
- **location**: lib/screens/pipe_route_calculator_screen.dart:35-99
- **issue**: No persistence of last inputs (H1, H2, X, Y) or last result. App backgrounded (phone call on site, gloves off, scroll PDF iso) → state lost on memory pressure / hot restart. Even on warm resume, navigating away from the screen and returning rebuilds State and zeros everything.
- **why it matters**: Welder enters 5 numbers from the iso drawing, app gets backgrounded for SMS / camera / WhatsApp foreman photo, returns — has to retype. Workshop tablets/phones are often low-RAM Androids that aggressively kill background activities.
- **suggested fix**: Persist all five input controllers + four results to `SharedPreferences` after `_calculate()`; restore in `initState()`. Optional: save-as-named-route feature for typical recurring spools.
- **effort**: M

- **severity**: high
- **location**: lib/screens/pipe_route_calculator_screen.dart:92
- **issue**: Decimal separator is decided **per calculation** by reading `AppLanguageController.isEnglish` at runtime — but there is no persisted user preference for "I'm Polish but the iso is in English / I want a dot". The locale flip also reformats already-displayed results immediately on language toggle without the user touching the screen, which is confusing on the floor (saved "1,5" suddenly becomes nothing because `_parse` is rerun? — actually result fields are not reparsed, but visually the next CALC will swap separator and confuse the comparison with the previous physically-marked pipe).
- **why it matters**: Welders working with international drawings often need a consistent unit / separator regardless of UI language. Currently the separator is coupled to UI locale with no override and no persistence of an explicit "decimal style" preference.
- **suggested fix**: Add a persisted "Decimal separator" setting (auto / dot / comma) in the global Settings screen, default to auto-from-locale, and read it here instead of `isEnglish` directly. Store under `prefs_decimal_separator`.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:88,96
- **issue**: `toStringAsFixed(1)` is hard-coded — 1 decimal place. No persisted "precision" preference. For SCH 160 or thin-wall fabrication the welder may want 2 decimals; for rough chalk-on-pipe layouts, 0 decimals are friendlier.
- **why it matters**: Fitter precision is process-driven (chalk vs. punch vs. CNC). A user who sets "0 decimals" once should not have to mentally round on every result.
- **suggested fix**: Read `prefs_route_decimals` (0/1/2) from `SharedPreferences`, default 1, surface in a global Settings screen.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:69,76
- **issue**: "Reset R" SnackBar action overwrites `_rController.text = '0'` directly without flushing to persistence; the inverse "Undo" sets `prevR` back, again no persistence call. If persistence is added (per finding above) these two paths must also save — easy to miss.
- **why it matters**: Inconsistent persistence state — welder hits Reset R, app gets killed, returns with `R = 0` saved (or not saved) — non-deterministic.
- **suggested fix**: Centralise `_saveSettings()` helper and call it from `_calculate()`, the Reset-R `onPressed`, and the Undo `onPressed`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:118
- **issue**: `HelpButton(help: kHelpPipeRoute)` — no "remember help dismissed" persistence. Other screens may already store `help_seen_<id>` flags; this screen's help dialog likely re-pops fresh content unless `HelpButton` itself persists. Confirm `HelpButton` actually persists per-screen "seen" state and that the key `kHelpPipeRoute` matches the persistence convention.
- **why it matters**: If help dialog auto-pops every cold start (some HelpButton implementations do), seasoned welders get re-trained every morning.
- **suggested fix**: Verify in `widgets/help_button.dart` that `kHelpPipeRoute` has a persisted `seenAt` flag in `SharedPreferences`. If not, add it.
- **effort**: S

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:20
- **issue**: `_rController` default literal `'0'` is hard-coded in the field initializer. If a persistence layer is added later, this literal masks the restored value because it runs before `initState()`'s async `prefs.getString(...)`.
- **why it matters**: Subtle bug when wiring persistence — first frame shows "0", then jumps to restored value — visual flicker on the workshop floor where the user may already be typing.
- **suggested fix**: Initialise empty, set "0" in `initState()` *after* attempting prefs restore, so restore wins cleanly.
- **effort**: S

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:35-99
- **issue**: No "calculation history" persistence (last N routes). A welder doing a 12-spool iso would benefit from a "recent routes" drawer so they can re-open a previous calculation to double-check before cutting.
- **why it matters**: Production fabrication is iterative — measure, calculate, mark, then verify against drawing. History reduces re-keying when foreman challenges a number.
- **suggested fix**: Append `{h1, h2, x, y, r, total, ts}` to a JSON list in `SharedPreferences` under `pipe_route_history`, cap at 20, add a small "History" icon to the AppBar actions.
- **effort**: L

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:312-325
- **issue**: Input field `keyboardType` is hard-coded `numberWithOptions(decimal: true)` — does not respect a persisted "unit system" preference. App is mm-only today, but a "inch fractional" mode (e.g. 12-1/2") would need a different input mode, and any persisted unit-system flag would naturally drive both this and the result formatter.
- **why it matters**: US/UK contractors on PetroChem jobs still spec NPS imperial. Currently impossible to store an "always mm" vs "always inch" preference for this screen.
- **suggested fix**: Out of scope for now, but document as future work tied to a global `prefs_unit_system` once introduced.
- **effort**: XL

--- end block ---

## Iter #10 · lib/screens/orbital_tig_screen.dart · first-time-ux
- **severity**: high
- **location**: lib/screens/orbital_tig_screen.dart:80-90 (initial render, no inputs filled)
- **issue**: First open shows only the disclaimer + 4 empty fields with no example/preset button and no explanation of WHAT the calculator does or for WHICH joint type it is valid (thin-wall austenitic tube). A welder unfamiliar with orbital TIG sees no result, no hint of expected output.
- **why it matters**: Workshop floor, gloves, mid-shift — if the first screen isn't self-explanatory in 3 seconds the welder closes it and uses gut feel. The autogenous/316L note exists but is muted 11pt below the voltage field — easily missed.
- **suggested fix**: Add a one-tap "Wczytaj przykład 25.4 × 1.65" (Load example) chip just under the disclaimer that pre-fills OD/wall/V and instantly shows results; promote the autogenous-316L note to the disclaimer card.
- **effort**: S

- **severity**: high
- **location**: lib/screens/orbital_tig_screen.dart:322 (_field onChanged: (_) => _calc())
- **issue**: `_calc()` fires on every keystroke. While typing "25.4" the user briefly has empty wall → red "Podaj grubość ścianki" error flashes; then typing wall they get "Ścianka nie może być większa niż połowa OD" mid-entry. First-timer reads these as the app being broken.
- **why it matters**: Error-on-every-keystroke is the #1 cause of "the app doesn't work" complaints from first-time industrial users. They don't yet trust the tool.
- **suggested fix**: Debounce `_calc()` by 350-500ms, OR suppress error UI while either field is empty AND only show errors after the field has been blurred once / a explicit "Oblicz" tap.
- **effort**: S

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:147-151 (Arc voltage field pre-filled "10")
- **issue**: The voltage field is pre-filled with "10" and labeled "Napięcie łuku (V)" with hint "8-12". A first-time user has no idea (a) that this is editable, (b) why orbital TIG voltage matters, or (c) what to put if their head shows a different reading. There is no info icon, no helper text.
- **why it matters**: An incorrect arc voltage produces a wrong heat-input number — that's the figure the welder will write into a WPS log. Misreading "10" as a fixed constant could put a wrong Q on a traceability sticker.
- **suggested fix**: Add a small (i) info tap that opens a one-screen explainer: "Read U from the head display during the test arc; 9-11V is typical for autogenous 316L." Mark the "10" as a default with subdued style and "(default)" suffix.
- **effort**: S

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:153-165 (stempel/WPS field above the disclaimer of its purpose)
- **issue**: The "Stempel spawacza / WPS (opc.)" field appears as input #4 in the form, before any result is calculated. First-timer doesn't know this is a traceability tag for the copy/paste flow — they might think it's required for the calculation and bail.
- **why it matters**: Asking for a stamp+WPS reference up front feels like a registration wall to a welder who just wants a number for a coupon. They abandon the screen.
- **suggested fix**: Move the stamp/WPS field into a collapsed "Dodaj stempel do kopiowania" expandable below the result, or grey-disable it until results exist and label it "Stempel (dodawany do skopiowanych parametrów)".
- **effort**: M

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:188-196 (level 1-4 labels with no diagram)
- **issue**: First-timer sees L1 "Płasko (dół)", L2 "Pionowo w dół" etc., but there is no orbital clock graphic showing the 12/3/6/9 sectors. Newer welders trained on TIG-by-hand may not know that L1 is the 6-o'clock weld-down start.
- **why it matters**: If the welder loads the wrong sector currents into the head they will burn through overhead. Misinterpretation is a real workshop risk for first-time orbital users.
- **suggested fix**: Add a tiny clock-face SVG/icon (4 sectors coloured by current value) above the level list, OR a one-line caption "L1 = 6 o'clock down · L4 = 12 o'clock top".
- **effort**: M

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:277-303 (post-result purge / O₂ checklist tip card)
- **issue**: The critical "backing gas purge, O₂ < 50 ppm, fit-up ≈ 0" pre-flight checklist appears AFTER results, hidden below the copy button. First-timer copies the parameters then walks to the head — and only later (if they scroll) sees they should have purged first.
- **why it matters**: Skipping backing-gas purge on stainless tube ruins the root immediately (sugar/oxide). One missed purge = scrapped coupon.
- **suggested fix**: Move the purge/O₂ tip card directly under the disclaimer (above inputs) so it is read BEFORE the welder sets parameters, not after.
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:175-185 (red error block)
- **issue**: Error text "Ścianka nie może być większa niż połowa OD" is technically correct but first-timer doesn't know WHY (it would mean a solid bar, not a tube). No micro-hint.
- **why it matters**: Cryptic validator messages erode trust on first use.
- **suggested fix**: Append "(sprawdź czy nie pomyliłeś OD z ID)" / "(check OD vs ID)".
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:82-86 (AppBar title only)
- **issue**: AppBar says "Orbital TIG — parametry" with no subtitle. First-timer reaching this screen via deep link doesn't know the calculator is restricted to thin-wall stainless tube and autogenous welding.
- **why it matters**: A welder using it for a 6 mm carbon-steel pipe would get heat-input numbers that are dangerously low — same risk as misusing any specialist tool.
- **suggested fix**: Two-line AppBar: title + subtitle "cienka rura 316L · bez drutu".
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:25-77 (no Clear/Reset action)
- **issue**: There is no "Wyczyść / Reset" button. After running one example the first-timer struggles to start over — voltage retains "10" while OD/wall keep stale values.
- **why it matters**: On a multi-job shift the welder calculates 3-4 tube specs back to back; manual field clearing in gloves is painful.
- **suggested fix**: Add a small "Wyczyść" icon button in the AppBar actions that resets controllers and `_est`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:223-275 (Copy button only appears post-calculation)
- **issue**: First-timer never sees the copy/share affordance until they enter valid numbers. They may not realize the app supports paste-to-foreman flow at all.
- **why it matters**: The copy feature is the main value for traceability — discoverability is critical.
- **suggested fix**: Show a disabled-state Copy button from screen open with tooltip "Wprowadź OD i ściankę, aby aktywować".
- **effort**: S

--- end block ---

## Iter #11 · lib/screens/pre_weld_checklist_screen.dart · cross-screen-consistency

- **severity**: high
- **location**: lib/screens/pre_weld_checklist_screen.dart:7-12 (private color constants)
- **issue**: Screen redeclares its own private palette (`_kCard 0xFF1A1D26`, `_kBorder 0xFF2C3354`, `_kOrange 0xFFF5A623`, `_kGreen 0xFF2ECC71`, `_kSec 0xFF9BA3C7`, `_kMuted 0xFF55607A`) — 26 sibling screens do the exact same thing with subtly different hex values (heat_input uses `_kTextMut/_kTextSec` naming, weld_journal/tungsten/passivation pick their own greens, sanitary_tube has another _kCard). No `AppColors`/`AppTheme` import in the file. Drift is already visible in prior audit blocks.
- **why it matters**: A welder flips between Pre-weld checklist → Heat input → Coupon log inside a single 5-min job prep. Inconsistent green for "OK / done" vs orange for "warning" across screens breaks the at-a-glance trust signal — they cannot tell at-a-glance whether they are in a "safe" or "warning" state without reading text. Workshop lighting is bad and visors are tinted.
- **suggested fix**: Extract `_kCard/_kBorder/_kOrange/_kGreen/_kSec/_kMuted` into a single `lib/theme/app_colors.dart` and `import` everywhere; replace literal hex with `AppColors.card/border/accent/success/textSec/textMut`. Roll out file-by-file in a single sweep PR.
- **effort**: L

- **severity**: high
- **location**: lib/screens/pre_weld_checklist_screen.dart:184-188 (AppBar Reset action)
- **issue**: Reset action is rendered as a `TextButton` with plain text label "Reset" — every other screen uses an `IconButton` with `tooltip:` (jobs_screen `Wyczyść filtr`, dn_mm `Wyczyść` with `Icons.clear_all`, ai_chat_screen `Wyczyść rozmowę`, iso_notebook `Wyczyść`, welder_tanks `Wyczyść`). Also the label is the English word "Reset" in BOTH PL and EN — `context.tr(pl: 'Reset', en: 'Reset')` is a no-op.
- **why it matters**: Polish welder expects PL UI per project default; sees "Reset" instead of "Wyczyść" → inconsistent with every other screen they use. Plus TextButton AppBar action has no tooltip, fails accessibility/long-press hint convention seen elsewhere.
- **suggested fix**: Replace with `IconButton(tooltip: context.tr(pl: 'Wyczyść', en: 'Clear all'), icon: const Icon(Icons.clear_all), onPressed: ...)` matching dn_mm_screen.dart:62 pattern.
- **effort**: S

- **severity**: high
- **location**: lib/screens/pre_weld_checklist_screen.dart:137 (`_done` in-memory only)
- **issue**: Checklist state is `final _done = <int>{}` in `State` — never persisted to `SharedPreferences`. Heat-input, premium, iso_notebook, pipe_schedule, bolt_torque all use SharedPreferences for their session state. Material picker selection also resets. Phone-call interruption, screen lock, or accidental back-swipe wipes the partially-ticked checklist.
- **why it matters**: A welder ticks 8/15 items, gets called away to fetch argon bottle, comes back 2 min later, taps the app — empty list. They either re-tick from memory (skip = risk of weld defect, mis-aligned tube, contamination) or restart from #1 (frustration, more time loss). Doc comment "live check, not a record, resets for next weld" acknowledges this but the trigger should be EXPLICIT (button press), not implicit (app backgrounded).
- **suggested fix**: Persist `_done`+`_material.key` in SharedPreferences keyed by date (`preweld_done_YYYYMMDD`); auto-clear at midnight or on explicit Reset; restore in `initState`. Pattern from pipe_schedule_screen.dart.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:311-372 (item tap target — GestureDetector)
- **issue**: Item rows use `GestureDetector(onTap: _toggle)` instead of `InkWell` — no ripple feedback, inconsistent with iso_notebook/jobs/projects/component_library which use InkWell for tappable list rows. Also missing long-press handler for showing P-No reference / detail expanding the abbreviated check (e.g. "Bevel 30° czysty…" — what bevel angle for what material?).
- **why it matters**: With gloves on, a welder needs visual confirmation that the tap registered (ripple > haptic alone — haptic gets dampened through nitrile gloves). Lack of ripple = "did I tap it?" → double-tap → toggle off → confusion.
- **suggested fix**: Wrap row in `Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(10), onTap: ..., child: ...))`. Optionally add `onLongPress` to show a SnackBar with the full guidance text (matches Tooltip pattern used for chips at line 257).
- **effort**: S

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:14-18 (`_Check` private model)
- **issue**: `_Check(pl, en)` private model is bespoke to this screen, with hard-coded inline PL/EN strings. Other screens with same bilingual pattern use `context.tr(pl:, en:)` directly (welder_menu, heat_input). The check items are also a hard-coded `const List` in the screen file — should live in `lib/data/` next to `help_entries.dart`/`support_spacing.dart` for consistency with how other screen data is organized.
- **why it matters**: Adding a 12th universal check or fixing a P91 PWHT temperature requires editing UI code — drift risk between checklist content and the AI-tutor (chat_screen, tutor_screen) which would reference the same metallurgy. Foreman/QA cannot review a single data file.
- **suggested fix**: Extract `_Check` and the two const Lists to `lib/data/preweld_checks.dart` exporting `kPreweldChecks` + `kPreweldExtras`; mirror help_entries pattern.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:174 (no Share/Copy action)
- **issue**: Once `all == true`, the screen offers no way to record/export the completed checklist as evidence for the weld log. Sister screens (cut_list_summary, orbital_tig, heat_input, bolt_torque, hydrotest) all wire `Clipboard`+`Share.share` so foreman gets a paste-able receipt. weld_journal_screen exists and would naturally consume a "checked at HH:MM, material X, all 14 items" string.
- **why it matters**: Inspector at jobsite asks "did you run pre-weld check on this joint?" — currently no artifact. Welder must re-tick or re-state verbally. Pasting one line into WhatsApp foreman group is the existing app-wide convention.
- **suggested fix**: Add an AppBar `IconButton(Icons.share)` (or bottom CTA visible once `all == true`) that builds a multi-line summary "PRE-WELD OK 2026-06-07 14:32 · 304L (P8) · 11/11 universal + 4/4 specific" and shares via existing ShareHelper utility.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:236-272 (material picker height + style)
- **issue**: Material picker is a `SizedBox(height: 48)` with `ListView(scrollDirection: horizontal)` — heat_input_screen.dart:442-455 uses `Wrap(spacing:6, runSpacing:6)` for the SAME `MaterialCatalog.all` selector. The two screens look and behave differently for the same catalog: here it scrolls, there it wraps; here chips have `materialTapTargetSize:padded` but no `labelPadding`, there both. Welder switching between screens has to re-learn the affordance.
- **why it matters**: Same data → same widget. The horizontal scroll has no fade-edge indicator (consistent with iter #1 toolbar gripe) — fitter sees only ~5 chips and assumes there are only 5 materials. Hides P22/P91 from discovery on narrow phones.
- **suggested fix**: Replace `ListView` with `Wrap(spacing:6, runSpacing:6)`; copy `labelPadding: EdgeInsets.symmetric(horizontal:8, vertical:6)` from sanitary_tube/heat_input for visual parity. Single material-picker widget could be extracted to `lib/widgets/material_picker.dart`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:178-189 (AppBar — no help/tutor link)
- **issue**: AppBar has no `Icons.help_outline` link to the Help screen entry for this calculator, unlike heat_input/coupon_log which surface contextual help. The screen also does not link to weld_journal (where the checklist artifact should end up) or AI tutor for "what does PWHT 750-770°C mean" follow-up. Screen is a dead-end navigation island.
- **why it matters**: Cross-screen flow `Checklist → done → Weld Journal entry` is the natural workshop loop. Missing it forces back-button + menu hunt.
- **suggested fix**: Add `IconButton(Icons.help_outline, tooltip:'Pomoc')` deeplinking to Help section "preweld", and once `all==true` show a bottom-sheet "Zapisz w Dzienniku" → push WeldJournalScreen with pre-filled material.
- **effort**: M

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:317-324 (item card border style)
- **issue**: Each row uses `BoxDecoration(color:_kCard, border:Border.all(color: done ? _kGreen.withValues(alpha:0.5) : _kBorder), borderRadius: 10)` — inconsistent radius with heat_input/tungsten/passivation which use radius 8 or 12; inconsistent "done" highlight (here is border only, weld_journal uses left-edge stripe, hydrotest uses background fill).
- **why it matters**: Visual rhythm inconsistency across the welder menu. Low impact because each screen is internally consistent.
- **suggested fix**: Settle on 10dp radius across screens and standardize "done/selected" treatment in a single AppRowStyle helper. Mark low — covered by the AppColors sweep above.
- **effort**: M

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:117-127 (`_preheatFahrenheit` utility)
- **issue**: Bespoke °C→°F converter lives inside this screen file. quick_converter_screen exists and presumably hosts the same conversion. Sanitary_tube/heat_input both display temperature ranges and would benefit from the same utility.
- **why it matters**: Code duplication risk; if rounding rule changes (e.g. switch to nearest-5°F) both implementations drift.
- **suggested fix**: Move `_preheatFahrenheit` to `lib/utils/temperature.dart` as `String formatPreheatRangeFahrenheit(String note)`; import from quick_converter/heat_input as needed.
- **effort**: S

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:280-309 (group divider for "Specific to X")
- **issue**: Divider header uses fontSize:10 + letterSpacing:0.6 + FontWeight.w900 — the divider style is invented here. Welder_pipes and weld_journal also have section headers but use fontSize:12 + w800. Material-specific item row prefix `${m.key} · P${m.pNumber}` at line 344 has its own micro-typography (fontSize 9, w900). Small-text legibility on a workshop screen is risky.
- **why it matters**: 9-10dp text is below mobile readability minimum especially on a smudged screen with a welding helmet flipped up.
- **suggested fix**: Bump divider to fontSize 12 w800 (match welder_pipes), and the inline P-No prefix to fontSize 11 w700 — extract `AppTextStyles.sectionLabel` for consistency. Mark low — overlaps with AppColors sweep.
- **effort**: S

--- end block ---

## Iter #12 · lib/screens/elbow_takeout_screen.dart · backend-robustness

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:28-50
- **issue**: `_cachedRows` is initialised to the const `kElbowTakeouts` list and `_cachedRows = kElbowTakeouts;` is reassigned on empty query. The cache holds a reference to the underlying const list; if any caller in the future mutates the result of `_rows` (e.g. `.sort()` in-place), it will crash with `Unsupported operation` at runtime. No defensive copy.
- **why it matters**: A future feature (sort by DN, reverse list) added by another dev would crash the screen mid-shift; the fitter sees "Aplikacja niespodziewanie zamknięta" while trying to look up DN300.
- **suggested fix**: Return `List.unmodifiable(...)` from `_rows` or document the contract that the returned list is read-only.
- **effort**: S

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:40-48
- **issue**: Filter uses `'${e.dn}'.contains(q)` — substring match on the DN number. Typing "5" matches DN15, DN25, DN50, DN65, DN125, DN150, DN250, DN350, DN450, DN500 — basically half the table. There's no "starts-with" or word-boundary filter, and no fallback to closest-by-DN.
- **why it matters**: A fitter searching for DN50 by typing "5" gets a wall of false positives and has to scroll; under stress on a job site this defeats the point of the search field. The standard ASME table has 20 rows so an exact-DN-first ordering would be more useful.
- **suggested fix**: Match `startsWith` on `dn`/`dn${e.dn}` first, fall back to `contains`; or rank exact-DN match to the top of the results.
- **effort**: M

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:44-47
- **issue**: NPS search is case-insensitive on the query (`q.toLowerCase()`) but NPS strings contain spaces and fractions like `'1 1/4'`, `'3 1/2'`. A user who types `11/4`, `1-1/4`, `1.25`, or `1¼` gets zero matches. No normalisation of fractions, dashes, or unicode vulgar fractions.
- **why it matters**: Fitters in PL often type `1 1/4"` or `5/4"` (the common Polish form) — the search returns "no results" and the screen looks broken, forcing manual scroll through 20 rows.
- **suggested fix**: Normalise both sides: strip spaces, map `¼→1/4`, `½→1/2`, accept `1-1/4` and `5/4` as `1 1/4`.
- **effort**: M

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:88-94
- **issue**: When `_rows` is empty (e.g. search "DN999" or "abc"), `ListView.builder` simply renders nothing — no "Brak wyników" / "No matches" placeholder, no hint to clear the filter.
- **why it matters**: Workshop user looks at a blank list and assumes the app froze or the database is broken; they may close-and-reopen losing other state. An empty-state message anchors the UI and offers a recovery path.
- **suggested fix**: Render an inline empty-state with "Brak wyników — wyczyść filtr" and a clear-button when `_rows.isEmpty`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:37-50
- **issue**: `_rows` getter mutates state (`_cachedQ`, `_cachedRows`) from inside a getter called during `build()`. While correct here (no setState), this is a code-smell that fights Flutter's mental model — a future maintainer adding any listener-notify or assert in the cache path can trigger "setState during build" errors.
- **why it matters**: Maintenance hazard; subtle bugs surface only when the table grows or a derived state is added. Workshop impact is indirect (crash during update rollout) but real.
- **suggested fix**: Compute `_cachedRows` inside `onChanged` (alongside `setState`) instead of lazily during build; getter becomes pure.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:80-84
- **issue**: `onChanged` trims input but never debounces. For a 20-row list this is fine, but if `kElbowTakeouts` is later extended (e.g. to DN1200+, schedule-aware variants, ~200 entries), every keystroke rebuilds the whole list synchronously on the UI thread.
- **why it matters**: On low-end Android devices in the workshop (BLE-budget phones common among site workers), typing in the filter could cause perceptible jank once the dataset grows.
- **suggested fix**: Add a 120 ms debounce via a `Timer?` field; pre-lowercase the dataset's searchable fields at construction.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:68
- **issue**: `maxLength: 16` silently caps input but doesn't strip non-printable characters or RTL marks that paste from messaging apps (WhatsApp foreman messages often carry U+200E/U+200F). The substring filter never matches if a stray bidi mark slips in.
- **why it matters**: Fitter pastes "DN50" from a chat, sees zero results, retypes manually — friction in the exact paste-driven workflow this app is built for.
- **suggested fix**: Sanitise input with a regex stripping non-ASCII non-printable characters before storing in `_q`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:64-85 (no use of inputFormatters)
- **issue**: No `inputFormatters` to constrain input to alphanumerics, slash, space and double-quote — the screen accepts any character but only those types can match. Wasted keystrokes silently.
- **why it matters**: On a phone the wrong keyboard might appear; restricting input gives the fitter immediate feedback that emojis / weird chars are ignored.
- **suggested fix**: Add `FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z/ ".dn]'))` (case-insensitive set covering DN/NPS).
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:193-195
- **issue**: `_Cell` uses `'${e.lr90}'` etc. directly — copies the raw number "152" without unit. The label argument passed to `CopyOnLongPress` is the English `'centre–face'` only, so the snackbar shows "centre–face: 152" but the clipboard payload is just `152`.
- **why it matters**: Fitter long-presses LR 90° of DN100, pastes into chat to foreman: foreman sees a bare "152" with no context — is it mm, inches, DN? A bilingual app should copy with unit ("152 mm") for unambiguous paste.
- **suggested fix**: Pass `value: '${e.lr90} mm'` (or have `_Cell` build the clipboard string explicitly with unit).
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:212
- **issue**: `CopyOnLongPress(label: 'centre–face', ...)` is hardcoded English, but the rest of the screen uses `context.tr(pl:..., en:...)`. The snackbar after copy is therefore always English on a PL device.
- **why it matters**: Inconsistent locale; PL user sees a confusing mixed-language toast which undermines trust in the app's polish under stress.
- **suggested fix**: Wrap label with `context.tr(pl: 'środek–czoło', en: 'centre–face')`.
- **effort**: S

- **severity**: low
- **location**: lib/data/elbow_takeouts.dart:51-62 (helper `closestByDn`)
- **issue**: `closestByDn` is defined but unused in the screen. Dead helper means it's also untested in real flows — if a feature ("press DN50 button to jump") is added later, the closest-tie behaviour (returns first match on ties) is silent and may surprise.
- **why it matters**: Workshop impact is currently nil but the helper is part of the screen's contract surface; an audit lens should flag latent untested paths.
- **suggested fix**: Either wire `closestByDn` to the search (jump-to behaviour on exact DN), or move it behind a unit test until used.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:115-118
- **issue**: Legend labels (`'DN / NPS'`, `'LR 90°'`, `'SR 90°'`, `'LR 45°'`) are hardcoded and not localised through `context.tr`. While these are technical abbreviations universal in piping, the bilingual contract is broken silently.
- **why it matters**: Minor — abbreviations are universal. But the inconsistency means future column additions can drift from the bilingual contract without anyone noticing.
- **suggested fix**: Add an explicit comment that abbreviations are intentional universals; or route via `context.tr` for consistency.
- **effort**: S

--- end block ---


## Iter #13 · lib/screens/cut_list_summary_screen.dart · permission-ux
- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:78-93 (_exportPdf)
- **issue**: PDF export calls `PdfExportService.exportCutList()` which writes to `getTemporaryDirectory()` and hands off to the iOS/Android share sheet. The OS share sheet itself may request transient permissions (e.g. on first-time email/messaging app selection) but the user is given zero pre-share rationale — they tap the PDF icon and a system sheet pops without a hint that "the file is generated and will be passed to the app you pick". On a workshop floor a fitter with greasy gloves who taps the wrong icon may be confused that "PDF błąd" never appears yet nothing seems to happen if they dismiss the system sheet.
- **why it matters**: Worker confidence on first export. A foreman printing CUT LIST for the saw operator must trust that "PDF" = "I get a file out" — silent share-sheet dismissal looks like a broken button.
- **suggested fix**: After `Share.shareXFiles(...)` returns, inspect `ShareResult.status` (share_plus exposes it) and show a snackbar: "PDF zapisano i wysłano przez <app>" on success or "Eksport anulowany" on dismiss, so the user gets a closed feedback loop without OS-level permission noise.
- **effort**: S

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:117-121 (PDF IconButton)
- **issue**: PDF export icon has only a `tooltip` (long-press on Android, hover on web). On iOS there is NO tooltip system at all — the picture_as_pdf icon is unlabeled. A welder who has never used the screen has no idea what tapping it does (might fear it triggers a print/email/external upload requiring a permission grant) and may avoid it. There is no pre-action rationale dialog explaining "this generates a PDF and opens the share sheet — you pick where to send it".
- **why it matters**: Permission-adjacent UX trust. The share sheet on iOS first-time triggers system prompts (e.g. AirDrop, Save to Files which needs Files access). The user needs to understand what they are authorizing before tapping.
- **suggested fix**: Replace bare icons with `Tooltip` + a small text label below on tablets, OR on first export of a session show a one-shot bottom sheet: "Wygenerujemy PDF i otworzymy systemowy wybór aplikacji — nie wysyłamy nic do chmury".
- **effort**: M

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:255-279 (_share + _copyCsv)
- **issue**: Both copy actions write directly to system clipboard via `Clipboard.setData` without any privacy rationale. On Android 12+ and iOS 14+ the OS shows a system banner "App pasted from clipboard" / "Fitter Welder Pro skopiowano …" when another app reads it back. There is no in-app explanation of why this is happening — workshop user pastes into WhatsApp on phone, sees the system "clipboard accessed" banner, and may panic that data was exfiltrated.
- **why it matters**: Trust on shared-device shop phones. Fitters often share a phone between shifts; an unexplained OS-level clipboard notification can trigger calls to the foreman or distrust of the app.
- **suggested fix**: Add a tiny one-time info chip on first copy-action in a session: "Dane lądują w schowku Twojego telefonu — system Android/iOS może pokazać o tym powiadomienie. To normalne.", dismissible with "Nie pokazuj więcej".
- **effort**: S

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:82-89 (PDF error path)
- **issue**: When PDF export fails, the snackbar reads `PDF błąd: $e` and surfaces the raw exception (could be `FileSystemException: ... permission denied (errno = 13)` on Android 10 scoped-storage edge cases or `MissingPluginException` on a stale build). For a workshop user this is gibberish and gives zero guidance on whether they need to grant a permission, free up storage, or retry.
- **why it matters**: When a permission/storage exception actually does fire (rare but possible on locked-down enterprise MDM Androids) the user is left without recovery steps and will assume the app is broken.
- **suggested fix**: Wrap exception in a translator: detect `FileSystemException`, `PathAccessException`, `MissingPluginException` and show actionable PL/EN messages ("Brak miejsca na pliki tymczasowe — zwolnij ~5 MB" / "Aplikacja wymaga aktualizacji — zrestartuj telefon"); log raw `e` to console for support.
- **effort**: S

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:107-132 (AppBar actions row)
- **issue**: Three side-by-side IconButtons (PDF, Share/Copy Text, CSV) plus HelpButton + back nav give five tap targets in an AppBar that is ~56dp tall. On Android these icons are roughly 48x48dp each. A fitter wearing gloves can easily mis-tap and trigger an export they did not intend, which in turn could fire a share sheet asking for first-time permissions. No "confirmation" or visual differentiation among the three "export-ish" buttons that all have similar grey outline icons.
- **why it matters**: Accidental taps causing OS permission prompts. A glove-wearing welder who meant to tap "?" (help) but hit "share" gets dropped into a share sheet — which may request contacts/files access on first use and confuse them about whether the cut-list app needs those permissions.
- **suggested fix**: Move CSV + Text copy into an overflow menu (`PopupMenuButton`), keep only PDF + Help in the AppBar. Reduces accidental hits and visually clarifies "primary action = PDF".
- **effort**: M

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:135-198 (no project / no segments empty states)
- **issue**: When a foreman hits "CUT LIST" with an empty project they see "Brak segmentów" but no contextual hint that the PDF/share buttons are still visible up top and ARE disabled-looking-but-clickable (they early-return at line 80 silently). Tapping an export button does nothing and gives no feedback — looks like the app froze, which on gloved hands invites repeated tapping. Worse, in `_share`/`_copyCsv` the empty-segments guard is not even present — clicking those copies a header-only string/CSV header line to clipboard, again triggering an OS clipboard banner for what is effectively no content.
- **why it matters**: User trust + OS-level "app accessed clipboard" notification fires for zero-value data. Combined with permission-adjacent UX confusion, the user loses confidence.
- **suggested fix**: Disable (grey-out) PDF/Share/CSV IconButtons when `_groups.isEmpty || _segments.isEmpty`, and show a snackbar "Najpierw dodaj odcinki w izometrii" if somehow tapped while disabled.
- **effort**: S

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:78-93 (export concurrency)
- **issue**: `_exporting` boolean prevents the PDF icon being shown, but `_share` and `_copyCsv` have no such guard — a user can tap "copy text" while a PDF export is mid-flight. If the share-sheet for PDF is up and the user dismisses it then hits copy, the OS may flag two near-simultaneous clipboard/file operations and (on stricter privacy ROMs like One UI 6 or HyperOS) actually show two permission banners stacked.
- **why it matters**: Stacked OS permission/privacy notifications across two actions look like the app is leaking data even when it is not.
- **suggested fix**: Disable Share + CSV IconButtons while `_exporting == true`; symmetric guard.
- **effort**: S

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart (whole file — no `permission_handler` use)
- **issue**: File never references `permission_handler` or storage permissions, which is CORRECT for current behavior (temp dir + share sheet need no perms on iOS or Android 10+). However there is NO comment documenting this design choice — a future contributor adding "save to Downloads" feature would silently add `WRITE_EXTERNAL_STORAGE` to the manifest and break the current zero-permission UX. The file is the canonical export entry-point and deserves a header comment locking in the no-runtime-permission posture.
- **why it matters**: Codebase guardrail. Permission creep silently triggers OS dialogs that confuse workshop users and break trust.
- **suggested fix**: Add a top-of-file comment: `// EXPORT POLICY: temp-dir + share_plus only. Do NOT add permission_handler or WRITE_EXTERNAL_STORAGE — workshop users must not see OS permission dialogs on cut-list export.`
- **effort**: S

--- end block ---

## Iter #14 · lib/screens/material_list_screen.dart · snackbar-quality
- **severity**: high
- **location**: lib/screens/material_list_screen.dart:38-62 (_load)
- **issue**: `_builder.buildForProject(pid)` and SharedPreferences calls are unguarded — any DB/IO exception is uncaught, _loading stays true forever or screen ends up empty with no error SnackBar
- **why it matters**: welder taps "Lista materiałowa" with gloves on a noisy shop floor — if DB read throws (corrupt segment row, locked sqlite during sync), they see a frozen spinner or empty list and can't tell whether to retry, restart the app, or call support
- **suggested fix**: wrap _load in try/catch; on error, set _loading=false and show SnackBar `context.tr(pl: 'Nie udało się zbudować listy materiałowej. Spróbuj ponownie.', en: 'Could not build the material list. Try again.')` with a "Ponów / Retry" action that re-calls _load()
- **effort**: S

- **severity**: high
- **location**: lib/screens/material_list_screen.dart:44-47 (empty pid fallback)
- **issue**: When projectId is empty AND no last_project_id pref exists, screen silently shows the "no data" coaching card as if user just hasn't added segments — but the actual cause is lost project context
- **why it matters**: misleads welder into adding segments to a phantom project; on shop floor they can't distinguish "I need to add pipes" from "the app lost which job we're on"
- **suggested fix**: detect this branch and show a distinct SnackBar `context.tr(pl: 'Nie wiem, dla którego projektu pokazać listę. Wróć i wybierz projekt.', en: 'No project selected. Go back and pick a project.')` plus an explicit empty-state CTA rather than the generic coaching card
- **effort**: S

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:44-47 (recovered-from-prefs branch)
- **issue**: When pid was empty but recovered from SharedPreferences, user is silently shown a BOM that may be for the WRONG (last) project — no SnackBar indicating "showing last-opened project: X"
- **why it matters**: welder on shop floor switches between two jobs daily; a silent recovery to "yesterday's BOM" could cause cutting wrong pipe lengths against wrong ISO — costly material waste
- **suggested fix**: when recovery branch fires, after load show SnackBar `context.tr(pl: 'Pokazuję ostatnio otwartą listę materiałową.', en: 'Showing last opened material list.')` with action "Zmień / Switch" that pops back to project picker
- **effort**: S

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:79-154 (whole body)
- **issue**: No pull-to-refresh and no manual refresh affordance, and no SnackBar when BOM is rebuilt — after editing segments in another screen, welder returns and sees stale data with no signal it can/should be refreshed
- **why it matters**: on a workshop floor welders frequently bounce ISO -> BOM -> ISO; without refresh + feedback they may cut by stale numbers, especially after correcting a length
- **suggested fix**: wrap ListView in RefreshIndicator that calls _load(); after successful rebuild show brief SnackBar `context.tr(pl: 'Zaktualizowano listę materiałową.', en: 'Material list updated.')` with duration 2s
- **effort**: S

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:67 (`return '— m'` for non-finite)
- **issue**: When totalLengthMm is NaN/Inf, row silently shows "— m" with no SnackBar or banner explaining a row has corrupt data — welder has no signal that BOM is partially invalid
- **why it matters**: a silent "— m" against PIPE row could be read as "0 m" through dirty safety glasses and lead to skipping a pipe in the cutting plan
- **suggested fix**: on first non-finite encountered during build, show one-shot SnackBar `context.tr(pl: 'Niektóre długości są nieczytelne — sprawdź segmenty.', en: 'Some lengths are invalid — check your segments.')` with action "Otwórz segmenty / Open segments"
- **effort**: M

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:147-153 (ListTile)
- **issue**: Tapping a BOM row does nothing — no feedback at all (not even a SnackBar) when welder tries to copy a quantity or description for an order; common need on shop floor is "long-press = copy to clipboard"
- **why it matters**: welder on a phone with gloves wants to dictate the row to a foreman or paste into WhatsApp; no affordance and no feedback makes the screen feel read-only and dead
- **suggested fix**: add onLongPress that copies "$catLabel  •  ${it.description}  •  ${trailing text}" via clipboard_helper and shows SnackBar `context.tr(pl: 'Skopiowano pozycję.', en: 'Row copied.')` with haptic.light()
- **effort**: S

- **severity**: low
- **location**: lib/screens/material_list_screen.dart (no AppBar action for share/export)
- **issue**: No "share BOM" action and therefore no SnackBar for "copied / exported / shared" — typical workshop need is sending the BOM as text to procurement
- **why it matters**: without share, welder photographs the screen which loses text searchability; with share, SnackBar confirmation prevents double-sending
- **suggested fix**: add IconButton(Icons.share) in AppBar.actions that builds plaintext BOM and uses Share.share(); on copy fallback show SnackBar `context.tr(pl: 'Skopiowano listę materiałową.', en: 'Material list copied.')`
- **effort**: M

--- end block ---

## Iter #15 · lib/screens/quick_converter_screen.dart · help-tooltips

- **severity**: high
- **location**: quick_converter_screen.dart:26-38 (AppBar / TabBar)
- **issue**: AppBar has no help/info action (IconButton with `?` or `info_outline`). A first-time user opening the converter sees only four tab names — there is no entry point explaining "long-press a value to copy", the supported unit list, or the quirks (l/min approx slpm at site, hydrotest in MPa, etc.). The `_SmallHint` at the bottom of each card is only visible AFTER the user types something, so the discoverability gap is real.
- **why it matters**: A fitter trying to convert degF preheat from a US PWPS on a noisy workshop floor needs to know up-front what units the tool covers and how to grab the result into the WhatsApp chat with the foreman. Currently they tap each tab to find out.
- **suggested fix**: Add `actions: [IconButton(icon: Icon(Icons.help_outline), tooltip: tr('Pomoc','Help'), onPressed: () => showModalBottomSheet(...))]` to AppBar; sheet lists supported units per tab + the long-press-to-copy gesture.
- **effort**: M

- **severity**: high
- **location**: quick_converter_screen.dart:29-37 (TabBar)
- **issue**: Tab labels have no `Tooltip` wrapper and no `Semantics` hint. On a scrollable tab bar, off-screen tabs (Pressure / Gas flow) are invisible without horizontal swipe — a fitter who only sees the first two tabs may not realise pressure & gas flow exist.
- **why it matters**: Gas-flow conversion (cfh -> l/min) is the killer feature for a welder reading a US-spec WPS — if they do not discover the tab, they will Google it instead and the app loses trust.
- **suggested fix**: Wrap each Tab in `Tooltip(message: tr('Konwersja mm/in/ft ...','Convert mm/in/ft ...'))`; also add a faint right-edge fade or arrow icon hinting at scrollable content.
- **effort**: S

- **severity**: high
- **location**: quick_converter_screen.dart:198-208, 292-300, 373-383, 456-465 (every `_SmallHint`)
- **issue**: The contextual hints (`_SmallHint`) only render INSIDE the `if (v != null)` block, i.e. after the user has typed something. A fresh tab shows zero guidance — no example unit, no "type a value", no copy hint. Empty-state coaching is the textbook use of help tooltips.
- **why it matters**: On a building site with gloves on, a fitter who taps the tab and sees a bare input + dropdown will assume the tab is broken and back out.
- **suggested fix**: Move `_SmallHint` outside the `if (v != null)` (or render a second always-visible `_SmallHint` above the input with text like "Wpisz wartosc, wybierz jednostke — przelicznik pokaze wszystkie warianty"). Alternatively, prefill the field with a sensible example (e.g. `25.4`).
- **effort**: S

- **severity**: med
- **location**: quick_converter_screen.dart:170-194, 256-289, 346-369, 429-453 (TextField + DropdownButtonFormField)
- **issue**: No `helperText` or `tooltip` on the input fields or unit dropdowns. The label is just "Wartosc/Value" — the user does not know if decimal separator must be `.` or `,`, or that negative values are accepted in Temperature only.
- **why it matters**: PL keyboards default to `,` and a fitter typing `25,4` on the Length tab will succeed silently — but the same on iOS in EN locale might confuse. Tooltip on the dropdown would also surface "mm, cm, m, in (cale), ft (stopy)" — useful when "in" vs "ft" is ambiguous to non-English speakers.
- **suggested fix**: `decoration: InputDecoration(labelText: ..., helperText: tr('Kropka lub przecinek','Dot or comma'))`; wrap dropdowns in `Tooltip(message: tr('Jednostka zrodlowa','Source unit'))`.
- **effort**: S

- **severity**: med
- **location**: quick_converter_screen.dart:200-204, 294-296, 375-379, 458-461 (`_Row` rendering)
- **issue**: Each result row shows a unit label and a value but no tooltip on long-press to explain what the unit means. `slpm` vs `l/min` is non-obvious — the code comment at line 400-401 reveals "rotameters on shielding-gas regulators are calibrated for atmospheric flow, so l/min == slpm" but the user never sees this rationale. They see two rows with identical numbers and may suspect a bug.
- **why it matters**: A welder calibrating a TIG flow meter will distrust a tool that shows two identical numbers without explaining why; trust = retention.
- **suggested fix**: Wrap each `_Row` label in `Tooltip(message: ...)` with a one-line explanation (e.g. "slpm = standard liters per minute (warunki referencyjne); na manometrach swiata l/min approx slpm"); or add a small `info_outline` icon next to the unit label.
- **effort**: M

- **severity**: med
- **location**: quick_converter_screen.dart:205-207, 297-299, 380-382, 462-464 (`_SmallHint` body text)
- **issue**: The hint text is informative but appears only in italic muted grey 11pt — easy to miss in workshop light. Also the wording mixes operational guidance ("Typowy GMAW 12-18 l/min") with usage instruction ("Przytrzymaj wartosc -> kopia"). They serve different purposes and should be visually distinct.
- **why it matters**: Operational hints (preheat ranges, hydrotest convention) are reference knowledge a fitter would WANT to long-press to expand or pin. Usage tip ("long-press to copy") is a one-time UX coach mark.
- **suggested fix**: Split into two widgets — a persistent `_OperationalNote` (with `Icons.lightbulb_outline`) for the domain hint, and a one-shot dismissible `_GestureHint` (or `Tooltip` on first result) for "long-press to copy".
- **effort**: M

- **severity**: med
- **location**: quick_converter_screen.dart:81-90 (`CopyOnLongPress` wrapping result text)
- **issue**: There is no visible affordance that the value is long-pressable. Standard help-tooltip pattern would attach a long-press `Tooltip` to each value showing "Przytrzymaj — kopiuj do schowka" the first few times, or display a small content_copy icon next to the value.
- **why it matters**: Hidden gestures are a known accessibility/discoverability anti-pattern. A welder will not randomly long-press a number to discover the feature, especially with gloves on a capacitive screen where long-press is finicky.
- **suggested fix**: Wrap the inner `Text` in `Tooltip(message: tr('Przytrzymaj — kopiuj','Long-press to copy'))`; or add a small `Icons.content_copy` icon next to each value (more discoverable than a tooltip).
- **effort**: S

- **severity**: med
- **location**: quick_converter_screen.dart:268-272 (Kelvin error text)
- **issue**: When `K < 0`, the field shows only `"K nie moze byc ujemna (zero absolutne)."` — but there is no tooltip/help explaining WHY (no mention that absolute zero = -273.15 degC) and no inline correction hint (e.g. "Did you mean degC?"). The error is technically correct but pedagogically opaque to a non-engineer.
- **why it matters**: A fitter not familiar with absolute zero will think the app is broken or that K is unsupported, and will switch tools.
- **suggested fix**: Extend error to `'K musi byc >= 0 (zero absolutne = -273.15 degC). Moze chodzilo o degC?'` and on tap of an inline `info_outline` icon show a bottom sheet explaining the scale.
- **effort**: S

- **severity**: low
- **location**: quick_converter_screen.dart:32-35 (Tab labels — no Semantics)
- **issue**: Tabs lack `Semantics(label: ...)` for TalkBack/VoiceOver. While not strictly a tooltip issue, screen readers serve the same "what is this control" role tooltips serve for sighted users.
- **why it matters**: Workshop accessibility — some pipefitters have hearing/vision impairments and use TalkBack with Bluetooth headphones under PPE.
- **suggested fix**: Wrap each `Tab` text in `Semantics(label: tr('Konwersja dlugosci','Length conversion'), child: Tab(text: ...))`.
- **effort**: S

- **severity**: low
- **location**: quick_converter_screen.dart:15-17 (file-level doc comment)
- **issue**: The dartdoc comment "Long-press any result to copy it" is great FOR developers but invisible to end users. The same string never appears in the rendered UI as a persistent tooltip — only as a one-line `_SmallHint` below results.
- **why it matters**: Knowledge that exists in code but never reaches the user is wasted. A consistent in-app help system would surface this on the AppBar help sheet.
- **suggested fix**: Reference this string from the new AppBar help bottom-sheet (see first finding) — single source of truth.
- **effort**: S

- **severity**: low
- **location**: quick_converter_screen.dart:286, 367, 450 (dropdown `onChanged` — no Haptic)
- **issue**: Length tab calls `Haptic.tap()` on dropdown change (line 190); Temperature, Pressure, Flow tabs do not. Inconsistent feedback weakens the "I changed the unit" affordance — tooltip-equivalent in tactile modality.
- **why it matters**: Cross-screen consistency lens (Iter #11) already flagged similar; for help-tooltips lens, haptic = tactile tooltip = "yes, that gesture registered".
- **suggested fix**: Add `Haptic.tap();` before `setState` in the three other dropdown onChanged callbacks.
- **effort**: S

--- end block ---

## Iter #16 · lib/screens/heat_input_screen.dart · asme-iso-fidelity

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:13-18 + 89-95 (efficiency map and dialog text 745-748)
- **issue**: Hard-coded arc efficiency η values diverge from EN ISO/IEC 1011-1 Table 1, the standard cited in the ASME IX / EN ISO 15614 dialog blurb. Per ISO/TR 17671-1 / ISO 1011-1: SMAW η=0.80 (OK), SAW η=1.00 (code uses 0.90), GTAW η=0.60 (OK), GMAW/FCAW η=0.80 (OK). The SAW value of 0.90 silently undercounts true heat input by ~10%, pushing welders to add filler/current when they are already at the upper WPS bound.
- **why it matters**: A welder running SAW on P22 trusts the kJ/mm reading; if the app reports 2.0 but real heat input is 2.2, they may run hotter (more current/voltage), the resulting HI exceeds the WPS upper bound, microstructure damage, possible PWHT non-compliance, NDT rejection of root + cap.
- **suggested fix**: Set `'SAW': 1.00` per ISO/IEC 1011-1; add a doc comment citing the exact standard (ISO/TR 17671-1 Table 1 or ASME IX QW-409.1 commentary), and surface η source in the info dialog.
- **effort**: S

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:140-150 (`_preheatRecommendation`)
- **issue**: Preheat recommendation ignores material thickness for CE >0.35 branches. ASME B31.3 Table 330.1.1 and AWS D1.1 Annex H both make minimum preheat a function of CE and thickness — CE 0.40 at 6 mm wall demands 10-50 °C; CE 0.40 at 38 mm demands 100-150 °C. The current code returns a single midpoint (125 / 175 / 250 °C) regardless of whether the pipe is sched 10 or sched XXS.
- **why it matters**: Workshop welder running A106 B (CE ~0.43) on 6 mm DN50 tube gets told to preheat to 125 °C — overkill, wastes propane and time, risks burn-through. Same welder running A516-70 at 60 mm gets the same 125 °C — way under spec, hydrogen-induced cracking 24-48 h after weld completion.
- **suggested fix**: Implement Yurioka or BS EN 1011-2 Method B lookup (CE × thickness × HI × hydrogen scale) or a two-axis table CE × thickness; expose hydrogen scale H1/H2/H3 as a chip selector.
- **effort**: L

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:120-127 (heat input formula)
- **issue**: Formula uses voltage-current-travel only; ASME IX QW-409.1 and ISO 15614-1 also recognise the energy method HI = (E_arc × η) / s where E_arc = ∫(v·i)dt / weld_length, which is what modern inverter sets actually report. App does not let the welder enter the inverter's displayed kJ value directly. Also, the formula does not document that voltage must be measured at the arc, not at the machine terminal — a 2-4 V cable drop yields ~10-20% HI error on long leads.
- **why it matters**: Modern Migatronic / Lincoln Power Wave / Fronius units display kJ/mm live. A welder copying the inverter number versus the calculator number sees a 5-15% discrepancy and loses trust in the app. Inspectors with audit demand the energy-method number.
- **suggested fix**: Add a toggle: "Energy method (kJ direct)" → HI = E_arc × η / weld_length. Add a help note that V must be measured at the arc; flag long-cable scenarios.
- **effort**: M

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:21 + 129-138 (CE formula)
- **issue**: Only IIW carbon equivalent is offered. ISO 15608 groups, AWS D1.1 Annex I, and CE for stainless / Ni alloys require different CE formulas — Pcm (Ito-Bessyo) for low-alloy high-strength steel (X65 line pipe), CEN (Yurioka) for modern HSLA, PRE_N for duplex. Applying IIW to 2205 Duplex (Cr 22, Ni 5.5, Mo 3.0) gives CE ~0.66 which mis-classifies it as "critical preheat + PWHT" when the actual rule is no preheat, interpass <150 °C, no PWHT. The material preset masks this but the moment the welder edits chemistry, the result is wrong.
- **why it matters**: Duplex tube fabrication is high-value oilfield work; a "PWHT mandatory" warning on duplex is a category error that will be ridiculed by a senior welder and tank app credibility for everything else.
- **suggested fix**: When `_material != null && _material.pNumber >= 8`, hide the IIW CE result and show a material-class banner ("CE not applicable — austenitic SS"). Optionally add Pcm and PRE_N selectors.
- **effort**: M

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:23-27 (doc) + reference table 678-682
- **issue**: Reference table shows CE thresholds without citing the source standard. ASME B31.3 Table 330.1.1 uses different breakpoints (0.30 / 0.45 / 0.65), AWS D1.1 Annex H uses 0.35 / 0.45 / 0.55, EN 1011-2 uses different ones again. No indication which standard the welder should reference if a third-party inspector challenges the number.
- **why it matters**: When an EN 9606-1 certified welder is audited and asked "why 175 °C?", they need to cite a clause. The app gives them a number with no provenance.
- **suggested fix**: Add a footnote under the reference table: "AWS D1.1:2020 Annex H; for ASME B31.3 service consult Table 330.1.1." Add a clause reference next to each row.
- **effort**: S

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:140-150 + 678 ("Cienka ścianka brak / >25 mm")
- **issue**: 25 mm threshold for "thin" vs "thick" is hard-coded; ASME B31.3 / AWS D1.1 actually use ≥25 mm (1 in) for P-No 1, but ≥13 mm (½ in) for P-No 4/5A and ≥10 mm (3/8 in) for P-No 5B (P91). No P-number context. So a P91 weld at 12 mm registers "thin" in the calculator and yields the wrong preheat.
- **why it matters**: P91 work is the most expensive welding in power plants; missing the 10 mm threshold and skipping preheat creates martensite + hydrogen cracks in the HAZ.
- **suggested fix**: Pass `_material?.pNumber` into `_preheatRecommendation`; switch thickness threshold based on P-number per ASME IX QW-422 / B31.3 Table 330.1.1.
- **effort**: M

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:50-52 + 63 (default values)
- **issue**: Default V=22 / I=110 / travel=200 / thickness=15 are SMAW-shop defaults; when welder switches process to GTAW the defaults remain (22 V is too high for TIG, which runs 10-15 V). The HI display shows an irrelevant number until the welder corrects everything. There's no per-process default profile.
- **why it matters**: Trust hit on first open with GTAW selected: numbers look wrong.
- **suggested fix**: Add `_defaultParamsFor(process)` returning (V, I, travel) tuples per process; trigger on `_process` change.
- **effort**: S

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:391-395 (Copy result)
- **issue**: Copy-to-clipboard exports only the HI value; ASME IX QW-409.1 / ISO 15614-1 traceability needs V, I, travel speed, process, η and timestamp. Welder copying the result for inclusion in a WPQR record loses the underlying parameters.
- **why it matters**: WPQR / NDT inspector demands the full row. Welder has to retype it.
- **suggested fix**: Format clipboard payload as `HI=X kJ/mm | V=Y | I=Z A | s=W mm/min | η=0.80 SMAW | 2026-06-07 14:32` (tab-separated for paste into Excel).
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:23-27, 678-682 + dialog 745
- **issue**: Pre-heat thresholds in the doc comment use °C only; AWS D1.1 / ASME B31.3 give °F as primary unit. App has no F/C toggle.
- **why it matters**: US-based welders or expats on EPC sites read WPS in °F; mental conversion is friction.
- **suggested fix**: Add °C ↔ °F toggle in settings, propagate into preheat / interpass display.
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:148 "+ low-H elektrody"
- **issue**: "low-H" advice triggers at CE 0.45 only, but ASME B31.3 and AWS D1.5 require low-hydrogen consumables for any P-No 4/5/9 work regardless of CE. Advice line ignores P-number.
- **why it matters**: Welder on P11 / P22 sees no warning if chemistry inputs are low.
- **suggested fix**: When material P-No ≥3, always show "Use low-H electrodes (E7018-1 H4R or equivalent)".
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:721-723 (dialog says "ASME IX / EN ISO 15614")
- **issue**: Citation is informal — neither standard contains this exact formula expression; ASME IX QW-409.1 defines HI as J/mm (not kJ/mm) and uses the same V·I·60/s structure but does not explicitly include η (η is added by ISO/IEC 1011-1). Citing both blurs the source.
- **why it matters**: Inspector reading the dialog may challenge "where in ASME IX is this with η?". Loss of credibility.
- **suggested fix**: Reword to "ISO/TR 17671-1 (efficiency η) + ASME IX QW-409.1 (heat input definition)".
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:141-149 (preheat recommendation)
- **issue**: Returns single midpoint preheat (125, 175, 250 °C) instead of a min-max range. Standards give ranges; pinning to midpoint loses the welder's degree of freedom and the option to cross-check inspector spec.
- **why it matters**: Welder asked "why 125 and not 100?" cannot answer; range 100-150 °C is the actual code-allowed window.
- **suggested fix**: Return `tempMin / tempMax` and display "100-150 °C" instead of "125 °C".
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:367-372 (WPS range UI)
- **issue**: WPS range comparison treats the boundary as strict inclusive (`>= wpsMin && hi <= wpsMax`); ISO 15614-1 §8.4.6 and ASME IX QW-409.1 allow ±10% on the qualified essential variable. Hitting exactly the boundary may legally still be in range but with margin; running slightly over is a non-conformance, not "within range".
- **why it matters**: A welder at 2.51 kJ/mm against WPS max 2.5 is told "OUT of range" even though tolerance allows 2.75; conversely 2.49 is shown as OK even though it sits at the cliff.
- **suggested fix**: Apply ±10% qualification tolerance with a yellow "marginal" band, green inside, red exceeded.
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:678 ("CE <0.35 → 0 / 50 °C")
- **issue**: Reference table conflates two cases (no preheat for thin, 50 °C for >25 mm) in one row, while the result card uses separate `_PreheatRec`. Wording is hard to scan for a welder under time pressure.
- **why it matters**: Misread under shop fluorescent lights → wrong preheat selection.
- **suggested fix**: Split the row into two: "CE <0.35, t ≤25 mm" and "CE <0.35, t >25 mm".
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:50-67 + 97-98
- **issue**: No range validation on inputs (V can be entered as 500, current as 9999, travel as 0.01). Out-of-band physical values produce nonsense HI without warning.
- **why it matters**: Welder making a typo (1100 A instead of 110) gets a wildly wrong number; if used without sanity check, leads to incorrect WPS conformance call.
- **suggested fix**: Add per-field sanity bounds (V 8-50, I 5-1500, travel 30-2000 mm/min) and surface a yellow warning when out of plausible welding range.
- **effort**: S

--- end block ---

## Iter #17 · lib/screens/tungsten_screen.dart · weld-traceability
- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:23-247 (whole screen)
- **issue**: No traceability persistence — welder enters current, sees suggested electrode (Ø + type), but nothing is logged. No record of which electrode was used on which joint, no timestamp, no welder/WPS reference linking the pick to a real weld.
- **why it matters**: In stainless/food/pharma jobs an inspector asks "what tungsten did you run on weld #JT-014?" — without a saved entry the fitter has to guess from memory hours/days later. Tungsten type (e.g. WL20 vs WT20) is part of pWPS records under ISO 3834/EN ISO 15614.
- **suggested fix**: Add "Save to job log" button that writes {timestamp, jobId/jointId, amps, picked diaMm, picked typeCode, polarity DC-, gas note} to the existing job-log service used elsewhere in the app.
- **effort**: L

- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:34-58 (input row)
- **issue**: No field to capture **joint ID / WPS number / welder ID** alongside the amps entry. The pick is anonymous — cannot be tied to a specific weld for a traceability dossier.
- **why it matters**: A traceability record without joint ID is useless to QA. Welder on the floor needs one-tap "tag this calculation to joint WX-23 / WPS-114-3 / welder PE-77".
- **suggested fix**: Add optional TextFields (joint ID, WPS ref, welder stamp) above the amps input, persisted in shared prefs for the session.
- **effort**: M

- **severity**: high
- **location**: lib/data/tungsten.dart:29-86 (TungstenType model)
- **issue**: Model has no field for **electrode batch / lot number / manufacturer / heat number**. ISO 6848 marking (colour stripe) identifies the *type* but not the *physical batch* that ended up in this weld.
- **why it matters**: For pressure-vessel or pharma tubing, the consumable batch must be traceable per EN ISO 3834-2 §14 (consumable identification). Right now the app can never produce that record.
- **suggested fix**: Add `batchNo`/`lotNo` optional TextField in the screen, store with each saved calculation entry. Don't change the static catalogue — capture batch at the moment of saving.
- **effort**: M

- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:36 (sizeForCurrent call)
- **issue**: No **export / share** of the pick. Cannot email the suggested electrode + current to a foreman, cannot paste into a weld map, cannot generate a PDF tag for the joint folder.
- **why it matters**: Traceability is dead-on-arrival if the calculation never leaves the device. Welders routinely text/email pick decisions to QC before striking an arc on a critical joint.
- **suggested fix**: Add Share/Copy button under the suggested electrode (reuse `clipboard_helper.dart` per project memory) that emits a one-line text trace: "DC- 95A → Ø 1.6 mm WL20 (blue) @ 2026-06-07 14:22 — joint WX-23".
- **effort**: S

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:35 (parsing amps)
- **issue**: Out-of-range / out-of-band currents (e.g. user enters 12 A or 500 A) silently snap to the nearest band via `sizeForCurrent` clamping, but the UI does **not** warn the welder that the value is **outside the qualified DC- envelope**. No trace flag is recorded.
- **why it matters**: A traceability log later shows "500A on Ø3.2 WL20" without any caveat — auditor cannot tell if it was a typo or a deliberate override of WPS limits.
- **suggested fix**: Detect `amps < minFirst || amps > maxLast` and show an orange warning chip "Out of WPS band — verify before welding" plus mark the log entry with `outOfBand:true`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:34-247 (whole screen)
- **issue**: No capture of **gas + polarity + base material** alongside the pick. Current bands are valid only for DC-, inert gas, stainless — but the user can be calculating for steel/AC and the screen happily logs an "incorrect" pick with no context.
- **why it matters**: A traceability entry that omits shielding gas and polarity is incomplete by EN ISO 15614-1 standards.
- **suggested fix**: Add fixed metadata pill at the top: "DC- · Ar 100% · stainless" + a small "Change" toggle that surfaces when user is on a different process and warns the screen is single-process.
- **effort**: M

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:73-109 (electrode size list rendering)
- **issue**: Once a row is highlighted as the "pick", there is no way to **manually override** the pick (e.g. fitter knows the joint needs Ø 2.4 due to thermal mass, not Ø 1.6). The override action is unrecorded — and override decisions are exactly what auditors care about.
- **why it matters**: Welders override calculator picks every day. Without a tap-to-override-with-reason flow, the audit trail will silently disagree with reality.
- **suggested fix**: Make each row tappable; on tap, prompt "override pick? reason:" (cone too cold, thicker root, etc.) and store {suggested, used, reason} in the log entry.
- **effort**: M

- **severity**: med
- **location**: lib/data/tungsten.dart:50-86 (kTungstenTypes)
- **issue**: No **AWS/ANSI equivalent codes** (EWLa-2 ↔ WL20, EWTh-2 ↔ WT20) and no **ISO 6848** reference printed on each row.
- **why it matters**: International workshops mix AWS and ISO paperwork. A welder receiving a US-flagged WPS sees "EWLa-2" and won't immediately map it to WL20 in this app — the calculation gets logged under the wrong type.
- **suggested fix**: Add `awsCode` + `isoRef` strings to `TungstenType`, show them as a small secondary line under the code.
- **effort**: S

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:111-140 (grind angle hint)
- **issue**: Grind angle text is generic copy. It is not bundled into the saved record, so the actual grind angle used on this electrode is never tied to the joint.
- **why it matters**: Tip geometry directly affects penetration profile on stainless tube — QC sometimes asks for it on root passes.
- **suggested fix**: Add a small grind-angle chooser (20°/30°/45°/60°) that's stored with the trace entry. Lowest priority of the bunch.
- **effort**: S

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:170-242 (electrode type list)
- **issue**: No way to **mark a type as "in stock / preferred"** for this shop — every workshop has 1-2 boxes on the wall, not the full catalogue. The screen always shows WT20 as a peer option when the shop may not even own thoriated electrodes.
- **why it matters**: Improves picks logged into the trace (prevents picking an electrode that the welder doesn't actually have, and then over-writing the trace later).
- **suggested fix**: Long-press a type row to set "available in shop", filter or grey-out the rest. Persist in shared prefs.
- **effort**: M

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:24 (TextEditingController _amps)
- **issue**: Amps input is volatile — leaving the screen and coming back loses the value, so the welder has to re-enter and the "last pick" is not part of a recoverable session log.
- **why it matters**: Mid-shift interruptions are common; losing the last value also means the latest unsaved trace candidate vanishes.
- **suggested fix**: Persist last entered amps in shared prefs; restore in `initState`.
- **effort**: S

--- end block ---

## Iter #18 · lib/screens/premium_screen.dart · cut-list-clarity

- **severity**: high
- **location**: lib/screens/premium_screen.dart:332-343 (sample prompt teaser)
- **issue**: The single sample prompt "Preheat dla P91 grubość 25 mm?" is too narrow — a typical fitter doesn't weld P91 (that's a power-plant chrome-moly grade); fitters work S235/304L/316L. The hero teaser fails to telegraph that AI handles fitter-level questions (cut list math, fit-up gaps, offset takeoff).
- **why it matters**: Workshop floor user reads the example, decides "this AI is for boiler welders, not me", scrolls past Premium. Premium conversion depends on the example landing in their daily reality.
- **suggested fix**: Rotate 2-3 sample prompts (cycle on rebuild or Timer.periodic): one cut-list ("Ile rur Ø88,9 z 6 m by zostało <300 mm odpadu?"), one fit-up ("Szczelina root pass dla 4 mm wall 304L?"), one preheat.
- **effort**: M

- **severity**: high
- **location**: lib/screens/premium_screen.dart:426-446 (plan cards row)
- **issue**: Row + Expanded with two _PlanCard children — on narrow screens (360 dp phones held in glove) the badge "OSZCZĘDZASZ 35% · POPULARNE" overflows because the yearly badge text is much longer than the card body. No Wrap fallback, no FittedBox on the badge.
- **why it matters**: Workshop floor phones are typically older Android (Samsung A-series, Xiaomi Redmi) at 360-393 dp. Glove use forces portrait. A clipped badge destroys the "popular" social proof signal — the highest-LTV plan choice.
- **suggested fix**: Wrap badge text in FittedBox(fit: BoxFit.scaleDown) OR shorten badge to two-line ("OSZCZĘDZASZ 35%\nPOPULARNE") with maxLines 2.
- **effort**: S

- **severity**: high
- **location**: lib/screens/premium_screen.dart:449-456 (Stripe footnote)
- **issue**: The "Płatność: Stripe (karta, BLIK, Apple Pay, Google Pay). Anuluj w każdej chwili." footnote does NOT mention VAT/invoicing. Polish self-employed welders (JDG) need to know if they get a faktura VAT — without it, they can't expense 19 PLN/mc against their business.
- **why it matters**: ~30% of Polish fitters/welders are self-employed. "Czy dostanę fakturę?" is the #1 pre-purchase friction. If not addressed, they email support instead of clicking Wybierz.
- **suggested fix**: Add second line: "Faktura VAT na żądanie — napisz po zakupie." Or wire to Fakturownia per CLAUDE.md plan and say "Automatyczna faktura na e-mail".
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:395-402 (job listing feature tile)
- **issue**: "1 darmowe ogłoszenie/mc w Pracy" promises an OPP value of 19 PLN — but that matches the entire monthly Premium price, implying cost-equivalence of zero. Reads like a math trick; a fast-scanning fitter may think "if it pays for itself just on this, what's the catch?" and bounce.
- **why it matters**: Plan-picker confidence — clarity beats cleverness on a workshop floor when the user has 30s between cuts to decide.
- **suggested fix**: Reword to "1 darmowy post miesięcznie (wartość ~19 PLN)" without parity claim, OR own it explicitly: "Roczny plan = posty za darmo cały rok."
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:411-418 (Bez reklam tile order)
- **issue**: "Bez reklam" listed last in feature tiles — but for a workshop welder mid-cut with an AdMob banner taking 50 dp of screen height, this is the most viscerally valuable feature ("the banner blocks my pipe schedule"). Ordering buries it.
- **why it matters**: Conversion psychology — lead with pain relief, not aspirational features. The cut-list screens already have an AdMob banner that interrupts the cut summary.
- **suggested fix**: Move "Bez reklam" tile to position 2 (right after AI Assistant); follow with feature-tool tiles.
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:258-351 (Try AI demo button → AiChatScreen)
- **issue**: Tapping "Wypróbuj AI Asystenta" pushes AiChatScreen for non-PRO users; per the comment on line 256-257, "PremiumGate around AiChatScreen will route non-PRO users back here automatically". That is a jarring loop — user taps Try, sees a gate dialog, gets bounced back to Premium screen they were already on. No actual demo.
- **why it matters**: The "Try" CTA is a trust-builder; if it actually delivers a paywall round-trip, the user feels deceived. Workshop floor users don't have patience for navigation games.
- **suggested fix**: Either (a) gate the demo to 1 free Q&A per device (deviceId-keyed) and serve a canned response, or (b) rename CTA to "Zobacz przykład" and show a static modal with prompt+response screenshot.
- **effort**: M

- **severity**: med
- **location**: lib/screens/premium_screen.dart:124 (_kVerifyBudget 15s)
- **issue**: 15s wall-clock cap for Stripe webhook verification. On a workshop with cellular signal (LTE in basement, EDGE on offshore platform), webhook + backend round-trip can legitimately exceed this; user gets "Nie zarejestrowaliśmy płatności" snackbar despite having paid. Then they see Premium screen unchanged → assume payment failed → re-attempt → double charge risk.
- **why it matters**: Workshop floor reality: cellular signal is the worst variable. A false-negative on payment verification is far worse than a longer overlay.
- **suggested fix**: Raise budget to 30-45s; OR change end-of-budget snackbar to "Płatność przetwarzana — sprawdź za chwilę w Profilu" (deferred reassurance, not negation). Include a "Już zapłaciłem" button that re-polls.
- **effort**: M

- **severity**: med
- **location**: lib/screens/premium_screen.dart:226-241 (AppBar title PREMIUM only)
- **issue**: AppBar title is just "PREMIUM" in gradient — no current status indicator. An already-Premium user landing here (deep link, accidental tap on "Premium" badge elsewhere) sees the same plan picker UI as a free user. There is NO "Aktywne · do 2027-06-07" badge anywhere on screen.
- **why it matters**: Active Premium subscribers re-landing here are confused → may click Wybierz again and start a second checkout. Also: no easy access to "manage subscription / cancel" — Stripe Customer Portal link is hidden.
- **suggested fix**: At top of body, conditionally render a green status card if PremiumService.instance.status.isActive showing plan + renewal date + "Zarządzaj subskrypcją" link to Stripe portal.
- **effort**: M

- **severity**: med
- **location**: lib/screens/premium_screen.dart:537-547 (stripeBackendLive guard)
- **issue**: When BackendConfig.stripeBackendLive is false, user taps "Wybierz" and gets snackbar "Płatności w przygotowaniu — wkrótce uruchomimy Premium." But the plan cards STILL show 19/149 PLN prices with active CTAs. There is no upfront signal that the entire flow is disabled.
- **why it matters**: A dev/staging build accidentally shipped to a TestFlight tester wastes the tester's tap and erodes trust. Workshop fitters value "what you see is what you get".
- **suggested fix**: When !stripeBackendLive, prepend a yellow banner at top of ListView: "Płatności włączymy w aktualizacji X.Y.Z." Disable the FilledButton onPressed (set to null) so the button is visually disabled.
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:430-444 (price strings hardcoded)
- **issue**: "19 PLN" and "149 PLN" are hardcoded strings inline in the widget tree. Currency localization: an iOS App Store reviewer from another EU country may want EUR. More critically: a price change (promo 99 PLN/yr) requires touching the widget, not config.
- **why it matters**: Workshop-floor clarity — if a user in EUR-pricing region sees "19 PLN" they have to mentally convert at fitting time. Also: A/B testing prices means rebuild + ship.
- **suggested fix**: Move prices to PremiumPlan enum or BackendConfig; fetch displayPrice from server (backend already knows the Stripe Price object). Format with NumberFormat.currency.
- **effort**: M

- **severity**: low
- **location**: lib/screens/premium_screen.dart:36-42 (color constants)
- **issue**: Hardcoded color palette duplicates constants likely defined in app theme. _kGold, _kCard, _kBorder, _kTextSec mirror values used in other screens; per prior audit iterations, theme tokens should be centralized.
- **why it matters**: Cross-screen consistency — a slightly off gold on Premium vs cut-list screens looks unpolished.
- **suggested fix**: Source from Theme.of(context).extension<AppColors>() or a shared lib/theme/colors.dart.
- **effort**: S

- **severity**: low
- **location**: lib/screens/premium_screen.dart:567 (url == null path)
- **issue**: If createCheckoutSession returns null, snackbar says "Nie udało się utworzyć sesji płatności." but does NOT offer a Retry action (unlike the catch block at line 622-626 which DOES have Ponów). Inconsistent UX.
- **why it matters**: Workshop user on flaky signal gets two different recovery paths for the same logical failure.
- **suggested fix**: Add SnackBarAction(label: 'Ponów', onPressed: () => _startCheckout(context, plan)) to the null-url snackbar.
- **effort**: S

- **severity**: low
- **location**: lib/screens/premium_screen.dart:178-181 (Navigator.maybePop after success)
- **issue**: After successful payment verification, Navigator.maybePop(context) after 900ms — this pops back to wherever the user came from. But if they tapped Premium from app drawer or settings, popping returns to that menu, not to the killer feature they just paid for (AI Chat).
- **why it matters**: Newly-paid user is most likely to try AI Chat first; bouncing them back to settings creates a "where do I go now?" moment.
- **suggested fix**: After success, replace current route with AiChatScreen (or show a "Co dalej?" sheet with quick links to AI Chat, Coping, Torque calc).
- **effort**: M

- **severity**: low
- **location**: lib/screens/premium_screen.dart:451-452 (EN footnote omits BLIK)
- **issue**: PL: "karta, BLIK, Apple Pay, Google Pay" — EN: "card, Apple Pay, Google Pay" (BLIK omitted in English). For Polish users using app in EN (bilingual workshops, EN-set phones), they lose visibility of BLIK as a payment option.
- **why it matters**: BLIK is the dominant mobile payment in PL workshops; if EN-locale Polish welder doesn't see it advertised, they may assume only credit card is available (which they don't have).
- **suggested fix**: EN: "card, BLIK (Polish bank app), Apple Pay, Google Pay".
- **effort**: S

- **severity**: low
- **location**: lib/screens/premium_screen.dart:460-530 (verification overlay box)
- **issue**: Overlay's dialog box uses padding 28x24 with mainAxisSize.min but no maxWidth constraint — on tablet landscape (iPad as workshop reference) the dialog stretches the full overlay width because the parent Container has no width cap, and the Cancel button can be off-canvas vertically if text wraps.
- **why it matters**: Tablet landscape showing a stretched/clipped dialog = Cancel may be hard to find; user locked in until wall-clock budget elapses.
- **suggested fix**: Wrap dialog Column in SingleChildScrollView and constrain maxWidth (e.g. 360 via ConstrainedBox) so it stays card-like.
- **effort**: S

--- end block ---

## Iter #19 · lib/screens/ai_chat_screen.dart · glove-48dp
- **severity**: high
  - **location**: lib/screens/ai_chat_screen.dart:581-591
  - **issue**: Send button uses default `IconButton` inside a circular Container with no explicit size constraint. Default IconButton tap target is 48dp, but with no `iconSize` override and `BoxShape.circle` wrapping, the visible/tappable circle relies on default 48dp; however no `constraints:` is set on IconButton so on dense Material themes the tap target can collapse below 48dp. Also no `padding` override — the visible circular target may appear smaller than 48dp with gloves.
  - **why it matters**: Sending a question is the primary action; a fitter wearing welding/work gloves needs an obviously large hit target. A near-48dp button risks mis-taps that drop the question they just typed.
  - **suggested fix**: Wrap in `SizedBox(width: 56, height: 56)` or set explicit `IconButton.constraints: BoxConstraints.tightFor(width: 56, height: 56)` + `iconSize: 26`.
  - **effort**: S
- **severity**: high
  - **location**: lib/screens/ai_chat_screen.dart:174-189
  - **issue**: AppBar `IconButton` (refresh / clear chat) — single tap clears entire conversation with NO confirmation dialog. A gloved bump on the AppBar wipes the whole exchange.
  - **why it matters**: On a workshop floor users brush the top of the screen with the back of a glove. Losing a long Q&A thread with citations because of an accidental tap is destructive and unrecoverable.
  - **suggested fix**: Add `showDialog` confirmation ("Wyczyść rozmowę? / Clear chat?") with PL/EN buttons before clearing.
  - **effort**: S
- **severity**: high
  - **location**: lib/screens/ai_chat_screen.dart:332-356
  - **issue**: Citation chips (`📖 §C`) have only `vertical: 3` + `horizontal: 8` padding and font size 10 — total tap area ~22dp tall. Far below 48dp.
  - **why it matters**: Citations are the trust-anchor for the AI's answer — a welder verifying "skąd to wiesz?" needs to be able to actually hit the chip with gloves. At ~22dp it's basically untappable.
  - **suggested fix**: Wrap the InkWell in a `SizedBox(height: 48)` or increase padding to `vertical: 14, horizontal: 12` + bump font to 12.
  - **effort**: S
- **severity**: med
  - **location**: lib/screens/ai_chat_screen.dart:546-578
  - **issue**: `TextField` `contentPadding: vertical: 10` with `fontSize: 14` and `minLines: 1` yields a touch target of ~40dp before user has typed. Hint text "Zapytaj o WPS…" is at fontSize 13 — small for a workshop screen viewed at arm's length with a face shield.
  - **why it matters**: Tapping into the input is the second-most common action. With gloves and a face shield, a 40dp field with 13pt hint is hard to acquire and read.
  - **suggested fix**: Raise `contentPadding` to `vertical: 14`, hint text to fontSize 15. Confirms ≥48dp tappable input row.
  - **effort**: S
- **severity**: med
  - **location**: lib/screens/ai_chat_screen.dart:264-269
  - **issue**: Citation dialog `TextButton` "OK" has no explicit `minimumSize` / padding — default TextButton is ~36dp tall.
  - **why it matters**: Dismissing the citation explanation requires a precise tap with gloves; a 36dp button is borderline.
  - **suggested fix**: Wrap with `TextButton(style: TextButton.styleFrom(minimumSize: Size(88, 48)), ...)`.
  - **effort**: S
- **severity**: med
  - **location**: lib/screens/ai_chat_screen.dart:108-121
  - **issue**: SnackBar Retry `SnackBarAction` is the only recovery path for a failed AI call. SnackBar duration is 4s, then it disappears — a user reading the error bubble may miss the Retry window entirely (gloves, slow head-up from work piece).
  - **why it matters**: On a noisy workshop floor with gloves on, 4s is too short to read, lift hand, and tap. Losing the retry forces user to retype the question.
  - **suggested fix**: Either extend duration to 8-10s OR show a persistent inline "Ponów" button on the error bubble itself.
  - **effort**: M
- **severity**: med
  - **location**: lib/screens/ai_chat_screen.dart:494-512
  - **issue**: Suggestion chips use `GestureDetector` (not `InkWell`/`Material`) — no ripple feedback on tap. With gloves, haptic + visual confirmation is critical because tactile feel through a glove is muted.
  - **why it matters**: A welder can't feel whether their tap registered through a thick TIG glove; visual ripple is the only confirmation. Silent GestureDetector leaves them guessing.
  - **suggested fix**: Replace `GestureDetector` with `Material(color: _kCard, child: InkWell(...))` and/or call `HapticFeedback.selectionClick()` in `onTap`.
  - **effort**: S
- **severity**: med
  - **location**: lib/screens/ai_chat_screen.dart:318-325
  - **issue**: `SelectableText` for message body at fontSize 14 with no `textScaler` clamp. Workshop users often raise system font size; long-press to select with gloves is unreliable but is the only way to copy a calc result (e.g. preheat temp) into another app.
  - **why it matters**: A fitter who wants to copy "Preheat: 250°C min, P91, t=12mm" into a WhatsApp message to the foreman needs reliable selection. Long-press through gloves often misfires.
  - **suggested fix**: Add an explicit "Copy" IconButton (≥48dp) on each assistant bubble, plus haptic on long-press.
  - **effort**: M
- **severity**: low
  - **location**: lib/screens/ai_chat_screen.dart:288-298, 364-374
  - **issue**: Avatar circles (bot / user) are 32×32 — decorative, not tappable, but they consume horizontal space that pushes the bubble width down. With short message bubbles on small phones the bubble can become narrow enough that wrapped citation chips overflow oddly.
  - **why it matters**: Minor — affects readability on small workshop-issued phones; not a tap issue but a glove-context layout concern.
  - **suggested fix**: Optional — hide avatars when `MediaQuery.size.width < 360`.
  - **effort**: S
- **severity**: low
  - **location**: lib/screens/ai_chat_screen.dart:153-170
  - **issue**: DEMO badge in AppBar at fontSize 10 — informational only, not tappable, but easy to miss when wearing safety glasses. Could mislead a user into trusting demo responses as real RAG output.
  - **why it matters**: Misreading demo vs live mode = potentially trusting fake calc answers in the field.
  - **suggested fix**: Raise fontSize to 11 and add stronger contrast border, or move badge to subtitle line.
  - **effort**: S

--- end block ---

## Iter #20 · lib/screens/chat_screen.dart · outdoor-visibility
- **severity**: high
- **location**: lib/screens/chat_screen.dart:585-592
- **issue**: Message body text uses fontSize 13 with color 0xFFE8ECF0 on bubble that may be just _kCard (dark) — small body text on dark in sunlight is the chat's primary content.
- **why it matters**: Spawacz pod gołym niebem nie odczyta treści wiadomości od kolegi (np. instrukcja spawu, numer telefonu) na słońcu — to sedno czatu.
- **suggested fix**: Podnieść fontSize do 15-16 i upewnić się, że background ma wystarczający kontrast (np. _kCard z mocniejszym borderem); pogrubić do w500.
- **effort**: S

- **severity**: high
- **location**: lib/screens/chat_screen.dart:594-597 (_formatTime label in bubble)
- **issue**: Timestamp używa fontSize 10 z _kTextMut (0xFF55607A) — bardzo niski kontrast na _kCard tła.
- **why it matters**: W warsztacie/słońcu nie da się odczytać "kiedy kolega napisał", a w czacie technicznym czas wiadomości jest istotny (np. najnowsza odpowiedź na pytanie spawalnicze).
- **suggested fix**: fontSize 12, kolor _kTextSec zamiast _kTextMut.
- **effort**: S

- **severity**: high
- **location**: lib/screens/chat_screen.dart:273-274 (_RoomTile desc)
- **issue**: Opis pokoju ma fontSize 12 z color _kTextSec (0xFF9BA3C7) na _kCard — sekundarny tekst pomocny przy wyborze pokoju.
- **why it matters**: Monter wybiera kanał (np. "Spawanie TIG" vs "Konstrukcje") na podstawie opisu — w jasnym świetle warsztatu nieczytelny opis = wybór zły lub klikanie po kolei.
- **suggested fix**: fontSize 13, color 0xFFB8C0D8 (jaśniejszy sekundarny).
- **effort**: S

- **severity**: high
- **location**: lib/screens/chat_screen.dart:577-583 (nickname w bańce)
- **issue**: Ksywka nadawcy ma fontSize 11 — bardzo małe nawet jeśli kolorem _kAccent (purple).
- **why it matters**: W kanale grupowym ważne kto pisze (np. "Krzysiek 304L" — autorytet w temacie); fitter w rękawicach z brudnymi okularami przy słońcu nie odczyta autora.
- **suggested fix**: fontSize 12-13, FontWeight.w800 zachować.
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:652-660 (_Composer TextField hint)
- **issue**: TextField nie ma jawnie ustawionego stylu tekstu wpisywanego — używa domyślnego, który może być za mały na słońcu; hint też domyślny rozmiar.
- **why it matters**: Spawacz pisze wiadomość trzymając telefon w warsztacie — musi widzieć co wpisuje, kiedy ma zaparowane okulary lub patrzy z odległości.
- **suggested fix**: style: TextStyle(fontSize: 16, color: Color(0xFFE8ECF0)); hintStyle z fontSize 15.
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:665-674 (Send IconButton)
- **issue**: Ikona wysyłania (Icons.send_rounded) używa domyślnej wielkości IconButton (~24dp) bez touch target ekspansji — może być za mała dla palca w rękawicy.
- **why it matters**: Spawacz w rękawicach roboczych musi trafić "Wyślij" jednym tapnięciem — mały target = frustracja, kilkukrotne tapnięcia, pomyłki.
- **suggested fix**: iconSize: 28, splashRadius zwiększyć, padding EdgeInsets.all(12) na IconButton.
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:278 (chevron_right _RoomTile)
- **issue**: Chevron color _kTextMut (0xFF55607A) — afordancja "klikalne, idź dalej".
- **why it matters**: Brak czytelnego wskaźnika "wejdź do pokoju" w jasnym świetle = niepewność czy tile jest interaktywny.
- **suggested fix**: Zmienić na _kTextSec lub _kAccent (mocniejszy kontrast jako wskaźnik akcji).
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:204-219 (_ErrorRetry message)
- **issue**: Tekst sekundarny "Sprawdź połączenie..." fontSize 12 _kTextSec; ikona cloud_off color _kTextMut size 40 — error state w słońcu nieczytelny.
- **why it matters**: Gdy czat nie działa (typowe na budowie z marnym WiFi/zasięgiem), użytkownik musi szybko zrozumieć dlaczego — nieczytelny komunikat = panika lub niewłaściwa decyzja.
- **suggested fix**: fontSize 14 dla opisu, ikonę cloud_off w _kTextSec size 48.
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:166-183 (_ChatComingSoon)
- **issue**: Opis "Backend nie jest jeszcze włączony" fontSize 13 _kTextSec — i nawet tytuł 18 może być za mały dla informacyjnego ekranu.
- **why it matters**: Coming-soon ekran musi być czytelny natychmiast — w jasnym świetle bez wytężania.
- **suggested fix**: Tytuł 22, opis 15.
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:544 (own message bubble color)
- **issue**: Własne wiadomości mają tło _kAccent.withValues(alpha: 0.25) — purple przezroczyste, na _kBg 0xFF0F1117 wychodzi bardzo ciemne purple/szare; w słońcu trudno odróżnić od cudzej wiadomości (_kCard).
- **why it matters**: W czacie grupowym musisz natychmiast odróżnić "to ja pisałem" od cudzych — w warsztacie pod słońcem różnica musi być jednoznaczna.
- **suggested fix**: alpha 0.45-0.55, lub jaśniejszy purple jako tło własnego dymka (np. 0xFF6A3A85 solid).
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:427-436 (SnackBar przy błędzie wysyłki)
- **issue**: Domyślny SnackBar przy 4s nie ma jawnych stylów — krótki czas + domyślny niski kontrast.
- **why it matters**: Spawacz z laser-helmet odsłaniającym ekran na chwilę nie zdąży przeczytać domyślnego SnackBara w warsztacie.
- **suggested fix**: Wydłużyć do 6s; backgroundColor mocniejszy (czerwonawy dla błędu), textStyle fontSize 15.
- **effort**: S

- **severity**: low
- **location**: lib/screens/chat_screen.dart:268-271 (_RoomTile name)
- **issue**: Nazwa pokoju fontSize 15 — graniczna dla outdoor.
- **why it matters**: Lista pokoi to nawigacja — większe nazwy ułatwiają orientację w warsztacie.
- **suggested fix**: fontSize 16-17.
- **effort**: S

- **severity**: low
- **location**: lib/screens/chat_screen.dart:568 (border alpha 0.7)
- **issue**: Granica dymka _kBorder.withValues(alpha:0.7) — gdy alpha < 1 na ciemnym tle, kontur się zaciera w pełnym słońcu.
- **why it matters**: Wizualne rozgraniczenie dymków zanika; ciąg wiadomości "zlewa się" w jedną plamę.
- **suggested fix**: alpha 1.0 lub border o jaśniejszym tonie 0xFF3A4570.
- **effort**: S

--- end block ---

## Iter #21 · lib/screens/home_screen.dart · mixed-units

- **severity**: med
- **location**: lib/screens/home_screen.dart:709 (`_ProjectTile` subtitle string)
- **issue**: Project subtitle is hard-coded `'Ø$dStr mm  ·  t $tStr mm'` — diameter and wall thickness always display in millimetres, with no respect for an inch/imperial preference. There is no `context.language`/`unitSystem` branch despite the project having a known industry split (UK/US/offshore fitters work in NPS inches + schedule, EU in mm). The literal `mm` is also outside the i18n helper (`context.tr(pl:..., en:...)`).
- **why it matters**: A pipefitter scanning the recent-projects list on an offshore or US jobsite sees `Ø168.3 mm · t 7.1 mm` for what they think of as `6" SCH 40`. They have to do mental conversion or open the project to confirm — wastes 5-15 s per glance, and erodes trust ("does the app even know what 6-inch is?"). Mixing units silently is the classic mixed-units bug class on a workshop floor.
- **suggested fix**: Read user unit preference (add if missing) and render either `Ø{d} mm · t {t} mm` or `Ø{NPS}" · SCH {sch}` (or `Ø{in}" · t {in}"`). Wrap the literal `mm` token via `context.tr` so EN locale users at least see a non-Polish-context unit string.
- **effort**: M

- **severity**: med
- **location**: lib/screens/home_screen.dart:707-709
- **issue**: `d.toStringAsFixed(1)` and `t.toStringAsFixed(1)` force a single decimal regardless of unit system. For mm this is fine; if the same code path were reused for inches (e.g. `0.280"` wall), one decimal truncates the meaningful third decimal (`0.28"` vs `0.280"` schedule rounding). Also `toStringAsFixed` uses the system default locale-agnostic dot — PL convention prefers comma decimals in workshop documents.
- **why it matters**: When the user later exports/copies a project name from the recent tile (or screenshots it for a foreman), the decimal-style mismatch with their drawing/PDF can cause misreads on the floor (`168.3` vs `168,3` — looks unfamiliar). Sub-issue: when mixed-units fix lands, fixed(1) becomes wrong for inch precision.
- **suggested fix**: Introduce a `formatLength(value, unit, {precision})` helper that picks precision per unit (mm→1, in→3) and decimal separator per `AppLanguage`. Use it here and in any other tile/header that surfaces lengths.
- **effort**: S

- **severity**: low
- **location**: lib/screens/home_screen.dart:445-449 (`_StatChip` for Segments)
- **issue**: Segment count `_StatChip` shows a unitless integer (`$totalSegments`). With mixed-units in scope, there is no breakdown of how many segments are mm-based vs inch-based — the user cannot tell from the hero whether their workspace is unit-consistent. Minor for v1 but lens-relevant.
- **why it matters**: A fitter who switched units mid-project (common when imported drawings are inches but their pipe inventory is mm) gets no early warning that half their segments are in the "wrong" unit. By the time they open a project they have to per-row verify.
- **suggested fix**: Optional: add a tiny unit-mix indicator (e.g. `120 (mm)` / `8 (in)`) under the Segments chip, OR a small warning dot when both unit systems coexist across recent projects.
- **effort**: M

- **severity**: low
- **location**: lib/screens/home_screen.dart:196,229 (subtitles "Ogłoszenia 49 PLN", "AI + pełne tools")
- **issue**: Currency `49 PLN` is hard-coded in the menu-card subtitle, including in the EN translation (`'Listings 49 PLN'`). For EN users (UK/IE/DE/US fitters) the natural currency would be EUR/GBP/USD. While not a measurement unit per se, this is the same "single hard-coded unit for everyone" anti-pattern the mixed-units lens catches.
- **why it matters**: A UK fitter sees `49 PLN` and has to Google what that is in GBP — friction at the very moment we're trying to convert them into a paying job-board user. Conversion lost.
- **suggested fix**: Either localise price by `context.language` (`pl: '49 zł'`, `en: '~£10'`/`'~$13'`) or drop the absolute number from the home subtitle and show price inside JobsScreen where you can localise properly.
- **effort**: S

- **severity**: low
- **location**: lib/screens/home_screen.dart:402-408 ("Aktywny"/"Active" pill) and 415-418 ("Witaj, Spawaczu" greeting)
- **issue**: No mixed-units exposure here directly, but the hero copy assumes one role ("Spawaczu"/"Welder") regardless of whether the user's last activity was fitter or welder. Lens-adjacent observation: a fitter who works purely in mm/NPS sees a welder-oriented banner. Not unit-mixing, but role-mixing — flagged low as the lens asked for breadth.
- **why it matters**: Minor UX dissonance; not a unit safety issue.
- **suggested fix**: Cycle greeting between `Spawaczu`/`Monterze` based on which menu was opened last, or use neutral `Fachowcu`/`Pro`.
- **effort**: S

--- end block ---

## Iter #30 · lib/screens/job_add_screen.dart · i18n-coverage

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:476-485 (_SectionLabel.build → text.toUpperCase())
- **issue**: All five section labels ("Stanowisko/Job", "Wymagania/Requirements", "Opis/Description", "Kontakt/Contact", "Płatność/Payment") are run through Dart's locale-independent `String.toUpperCase()` without a locale argument. Polish has no diacritics in this particular set, but the helper is reused for any label string and will mis-cap Turkish/German future locales (e.g. "ß" → "SS" in PL casing vs. "ẞ" in DE upper-tier; "i" → "I" in TR vs. "İ"). Today the bug is dormant for PL/EN, but the next locale rollout (DE is plausible for a welder app servicing Bayern) will surface it.
- **why it matters**: Localization expansion to DE/AT — likely given the app targets monter/spawacz market — will hit casing bugs on labels rendered in workshop docs/screenshots.
- **suggested fix**: Accept the label already upper-cased in the source `tr` string, or use an `Intl`-aware upper helper. Avoid casing transformation in widget build entirely.
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:241-242 (AppBar title)
- **issue**: AppBar title uses two `context.tr` calls inside a ternary (`isEdit ? tr(...) : tr(...)`). The PL phrasing "Edytuj ogłoszenie" / "Nowe ogłoszenie" diverges from the "ogłoszenie pracy" noun used on the parent JobsScreen, so the product term drifts between screens within the same flow.
- **why it matters**: Fitter who saw "Dodaj ogłoszenie pracy" on the parent screen sees only "Nowe ogłoszenie" here — momentary "is this the right place?" friction on a paid (49 PLN) flow.
- **suggested fix**: Standardize on `pl: 'Nowe ogłoszenie pracy', en: 'New job listing'` and `pl: 'Edytuj ogłoszenie pracy', en: 'Edit job listing'`; align with parent screen title.
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:445-447 (Tooltip interpolation `pl: 'Dodaj $tag do wymagań'`)
- **issue**: PL templated tooltip "Dodaj $tag do wymagań" — Polish grammar requires the noun "wymagań" to be in genitive plural, which is correct here. However, when the interpolated tag is an acronym noun like "PED" or "WPS/WPQR", the sentence reads as a bare acronym in the middle of a Polish phrase. Native PL convention would quote the token: `Dodaj "PED" do wymagań`. EN has no analogous issue.
- **why it matters**: Tooltips have low UX weight, but inconsistent quoting of acronym tokens is a visible polish gap for PL users.
- **suggested fix**: Wrap tag in quotation marks in both locales: `pl: 'Dodaj "$tag" do wymagań', en: 'Add "$tag" to requirements'`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:462-467 (_req validator)
- **issue**: Generic "Pole wymagane" / "Required" error message is reused across the title, company, location, and description fields. When the user submits with multiple fields blank, every TextFormField shows identical red text, but the user has to scroll to find which one needs attention. The EN "Required" is so terse it provides no actionable context.
- **why it matters**: Welder on a glove-keyboard who taps "Opłać 49 PLN i opublikuj" with 3 blanks gets 3 identical "Required" labels and must hunt the form for which one needs attention — frustrating on a small screen with bright workshop lighting.
- **suggested fix**: Pass the field name into `_req` and include it: `pl: 'Pole "${label}" wymagane', en: '"${label}" required'`. Even `pl: 'Uzupełnij to pole', en: 'Please fill in this field'` is more directive than "Required".
- **effort**: M

- **severity**: med
- **location**: lib/screens/job_add_screen.dart:256-257 (`pl: 'np. Spawacz TIG 141 — rurociągi SS', en: 'e.g. TIG 141 welder — SS piping'`)
- **issue**: "SS" in EN means "stainless steel" but reads as the Nazi-SS abbreviation when a German recruiter (the obvious EN-locale audience for a Polish welder app) reads it. The PL hint shares the same string but Polish convention is more often "rurociągi nierdzewne" or "rurociągi INOX". Politically sensitive abbreviation choice in DE-adjacent market.
- **why it matters**: A Polish welder app marketed in the EN locale is overwhelmingly serving DE/AT/CH employers — using "SS" without expansion is a real PR/UX risk on a hint that thousands of recruiters will see.
- **suggested fix**: `pl: 'np. Spawacz TIG 141 — rurociągi INOX', en: 'e.g. TIG 141 welder — stainless steel piping'`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:131
- **issue**: "Wróć do edycji" / "Keep editing" — PL "Wróć do edycji" is fine but inconsistent with the rest of the app's TextButton conventions on modal dialogs (typically just verbs: "Anuluj", "Zamknij"). Material PL convention for the same action is "Anuluj".
- **why it matters**: Tonal inconsistency across modal dialogs throughout the app.
- **suggested fix**: `pl: 'Anuluj', en: 'Cancel'` — shorter, conventional, no ambiguity.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:117-127 (Discard dialog)
- **issue**: Dialog title "Porzucić zmiany?" — PL infinitive question ("To discard changes?") sounds bureaucratic. Modern Material PL uses imperatives or shorter forms.
- **why it matters**: Tone matches older Windows-style dialogs rather than 2026 mobile UX. Minor.
- **suggested fix**: `pl: 'Odrzucić wpisane dane?', en: 'Discard your changes?'`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:294-307 (helper-text Row with touch_app_outlined icon)
- **issue**: Overlaps with Iter #5 chip-jargon finding. Additionally, the leading icon (touch_app_outlined) has no semanticLabel/Tooltip, so a screen-reader user gets the translated copy but no narration about the tap-gesture cue. i18n-coverage extends to assistive labels per locale.
- **why it matters**: Accessibility parity across locales — PL/EN VoiceOver users miss the tap-cue altogether.
- **suggested fix**: Add `semanticLabel: context.tr(pl: 'Wskazówka', en: 'Hint')` to the Icon, or wrap the icon in a `Semantics` widget.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:421-427 (footer disclaimer — overlap with Iter #5)
- **issue**: Beyond the "MVP" leak already flagged in Iter #5, the EN footer ends "...arrive in the next update." while PL ends "...pojawią się w kolejnej aktualizacji." — both promise a delivery timeline without committing one. In EN copywriting for paid features this triggers consumer-protection concerns (FTC: forward-looking statements need basis). PL has similar exposure under UOKiK rules. Low because area is duplicate, but i18n-coverage requires BOTH locales adopt disclaimer-safe phrasing.
- **why it matters**: Both PL and EN versions make an unbacked promise on a paid (49 PLN) screen.
- **suggested fix**: Replace with hedged copy: `pl: '...mogą pojawić się w kolejnych aktualizacjach.', en: '...may arrive in a future update.'`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:217 (`label: context.tr(pl: 'Ponów', en: 'Retry')`)
- **issue**: SnackBarAction label "Ponów" alone in PL is grammatically incomplete (Ponów co? — "Retry what?"). EN "Retry" works as a button verb. PL convention on SnackBar actions is to use slightly longer noun ("Ponów próbę") or imperative ("Spróbuj ponownie").
- **why it matters**: PL UX hygiene; SnackBar actions feel half-translated.
- **suggested fix**: `pl: 'Spróbuj ponownie', en: 'Retry'`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:438-460 (_chipCache — single-slot per language)
- **issue**: Iter #5 flagged this as a foot-gun if _commonReqs becomes dynamic. Additional i18n-coverage angle: the cache invalidation depends on `_chipCacheLang != lang`, which is set on first build per language. If the user switches PL→EN→PL within the same screen lifetime (a translator QA-ing copy), the cache rebuilds twice — minor perf cost. No correctness bug, but i18n-related rebuild work is duplicated.
- **why it matters**: Tiny perf regression on rapid PL/EN toggles during settings exploration.
- **suggested fix**: Cache per-language: `Map<AppLanguage, List<Widget>>` instead of single-slot.
- **effort**: S

- **severity**: low
- **location**: lib/screens/job_add_screen.dart:194-198, 211-214 (SnackBar error copy)
- **issue**: Two snackbar messages — PL/EN both end with full-stops. Punctuation treatment is consistent here but the project elsewhere mixes punctuation in SnackBars (some end in period, some not). i18n-coverage flags punctuation consistency across screens as a translator-facing concern when PO/ARB files are exported.
- **why it matters**: Visible to QA/translators auditing exported translation files; suggests no project-wide style guide.
- **suggested fix**: Adopt one project-wide rule (Material PL/EN guidelines: full sentences keep period, fragments drop it) and document it in an i18n style guide.
- **effort**: S

--- end block ---

## Iter #31 · lib/screens/saddle_template_screen.dart · perf-rebuilds

- **severity**: med
- **location**: saddle_template_screen.dart:871-880 (_drawText inside paint loop)
- **issue**: `_drawText` is called 5 times per paint (one per phi label 0°/90°/180°/270°/360°), and each call allocates a fresh `TextPainter` + `TextSpan` + `TextStyle` and runs `.layout()`. None of the text content/style depends on dynamic state across the 5 labels except for the digit string — yet a brand-new TextStyle is built for each.
- **why it matters**: a fitter dragging the angle slider triggers the painter (~60 fps target) — 5 fresh TextPainter constructions + layouts per frame = ~300 allocations/sec on hot path. Visible jank on low-end Android in the workshop preview redraw.
- **suggested fix**: cache a single `TextStyle` const at file level; build TextPainter once per label and reuse, or pre-compute the 5 phi positions/strings once per template change.
- **effort**: S

- **severity**: med
- **location**: saddle_template_screen.dart:731-779 (_PreviewCard always constructs new painter)
- **issue**: `_PreviewCard.build` unconditionally instantiates `_CutProfilePainter(template)` on every build. Although `shouldRepaint` correctly compares 3 scalar fields, RenderCustomPaint still pays the cost of attaching/detaching the new painter instance and running the equality check on every rebuild — including unrelated rebuilds from `_exporting` flip and TextField focus changes.
- **why it matters**: each unrelated rebuild during typing/exporting still does painter-swap work. Compounded with the parent ListView rebuilding everything, the preview card pays redundant overhead during a multi-tap typing burst.
- **suggested fix**: cache the painter on `_template` in the parent state (recreate only inside `_recompute`), or wrap `_PreviewCard` in a `RepaintBoundary` + `ValueListenableBuilder<SaddleTemplate?>`.
- **effort**: M

- **severity**: med
- **location**: saddle_template_screen.dart:239, 241, 587, 618, 620, 864, 903, 905, 972 (`Color.withValues(alpha: ...)` in build)
- **issue**: every `withValues(alpha: ...)` call allocates a brand-new `Color` instance on each rebuild — _kGold (×2 in AppBar), _kAccent (×3 in callout/chip), Color(0xFFE57373) (×2 in ErrorBox), _kTextMut (×1 in painter), _kAccentDim already const but other alpha derivations are not.
- **why it matters**: per-frame allocations during slider drag (~60 hz) — many short-lived Color objects compound GC pressure on a Snapdragon 4xx-class device used on the floor.
- **suggested fix**: pre-compute alpha-modulated colors as top-level `const` Color literals (e.g. `const _kGold15 = Color(0x26E8C14B);`) so they're const-folded and reused.
- **effort**: S

- **severity**: med
- **location**: saddle_template_screen.dart:269-276 (_TrySomethingCallout always rendered)
- **issue**: the "first-time coaching" callout renders on every visit to the screen unconditionally, even after the welder has used the tool dozens of times. Each visit rebuilds the Container + Wrap + 3 `_TryChip` widgets + Icon + 2 Text(tr) entries — and re-evaluates `AppLanguageController.isEnglish` inline.
- **why it matters**: not a one-shot — every recompute (typing, slider drag) rebuilds the callout's 3 chips and 2 Text(tr) lookups even though it never changes. UX wise the seasoned welder also stares at "first-time" coaching they don't need.
- **suggested fix**: gate behind a "seen" flag in SharedPreferences (dismiss on first chip pick or after first PDF export), AND isolate it as a `const`-constructible widget that doesn't sit inside the same ListView rebuild fan-out.
- **effort**: M

- **severity**: low
- **location**: saddle_template_screen.dart:391-422 (`Builder` wrapper around marker-step hint)
- **issue**: a `Builder` is used purely to access `ctx.tr(...)` for the i18n call — but the outer build already has the same `context` available via `_SaddleTemplateScreenState.build(BuildContext context)`. The `Builder` adds an unnecessary Element layer and child rebuilds it on every parent rebuild.
- **why it matters**: extra Element in the tree means an extra rebuild step; marginal, but compounds with the Iter #6 marker-hint finding about the same area.
- **suggested fix**: drop the `Builder`, use the outer `context` directly, OR extract as a real `StatelessWidget` taking pre-computed `stepMm`/`stepDeg`.
- **effort**: S

- **severity**: low
- **location**: saddle_template_screen.dart:817-838 (two separate for-loops over template.points)
- **issue**: the painter iterates `template.points` twice — once to build the fill path, once for the stroke path — recomputing `pad + p.xMm * sx` and `baselineY - p.depthMm * sy` for each of 72 points in both passes.
- **why it matters**: cheap math but doubles trig-free arithmetic per repaint; during slider scrubbing (forced repaints via new template) this is 144 multiply-add ops per frame instead of 72.
- **suggested fix**: combine into one loop that adds points to both paths simultaneously, or pre-compute the `Offset` list once and feed both `fillPath.addPolygon` and `strokePath.addPolygon`.
- **effort**: S

- **severity**: low
- **location**: saddle_template_screen.dart:524-566 (_NumField rebuilds on every parent setState)
- **issue**: `_NumField` is a `StatelessWidget` containing a heavy `TextField` + `InputDecoration` + 3 `OutlineInputBorder`s + 3 `BorderSide`s. Whenever `_SaddleTemplateScreenState.setState` runs (every keystroke from EITHER field, every slider tick, every export flag flip), both `_NumField` instances rebuild their full `InputDecoration` tree.
- **why it matters**: a welder typing 5-digit OD on phone triggers ~5 setStates; each rebuilds both number fields' full decoration even though only one field's text changed.
- **suggested fix**: extract `InputDecoration` to a top-level `const` factory (or `const InputDecorationTheme` on the Scaffold), wrap each `_NumField` in a `RepaintBoundary`, and consider passing `decoration` as constructor arg so const-folding kicks in.
- **effort**: M

- **severity**: low
- **location**: saddle_template_screen.dart:957-985 (_TryChip rebuilds with every parent rebuild)
- **issue**: each `_TryChip` instance rebuilds its Container + BoxDecoration + Border + Text on every parent rebuild — even though label/onTap never change once user enters the screen.
- **why it matters**: 3 chip widgets × N setStates during typing burst — minor churn but compounds.
- **suggested fix**: mark `_TryChip` constructor `const` (it already could be — fields are final), and ensure all child literals (TextStyle, BoxDecoration colors) are `const`. Combined with the callout isolation fix above eliminates the rebuild path entirely.
- **effort**: S

- **severity**: low
- **location**: saddle_template_screen.dart:646-669 (_MetricsRow uses inline `Row` + Expanded)
- **issue**: `_MetricsRow.build` allocates a fresh `Row` with 3 `Expanded` + 3 `_Metric` widgets every rebuild. The `_Metric` widget itself rebuilds its full `Container`/`BoxDecoration`/`Column` tree even when `value` hasn't changed.
- **why it matters**: overlaps with Iter #6 finding but adds the angle that `_Metric` is not const-constructed and `_mmAsInches`/`_mmAsFeetInches` string allocs happen at every parent rebuild.
- **suggested fix**: mark `_Metric` and `_MetricsRow` constructors `const`, hoist formatted strings into the parent state and pass as const-friendly args.
- **effort**: S

--- end block ---

## Iter #32 · lib/screens/rolling_offset_screen.dart · edge-case-zero-one

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:48
- **issue**: Validation rejects spread==0 OR rise==0 as a hard error. A real fitter routing pipe around a single obstruction often has only vertical offset (spread=0) or only horizontal offset (rise=0) — a "simple offset" not "rolling". The calculator could still handle it (trueOffset = max(rise,spread)) but instead refuses to compute.
- **why it matters**: Worker on the floor with a pure vertical bypass gets "Enter Rise and Spread > 0" and has to switch to the regular Simple Offset screen, losing the angle-selection workflow.
- **suggested fix**: Allow rise>=0 and spread>=0 with at least one >0; document that rolling formula degenerates correctly when one is zero.
- **effort**: S

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:28,48
- **issue**: _parse() returns 0 silently for malformed input ("1.2.3", ".", ",", "1e2"). Validation then says "Enter Rise and Spread > 0", but the fitter DID type something — error message misleads them into re-typing the same characters thinking they hit zero by accident.
- **why it matters**: In gloves on a noisy site, a typo like "1,2,3" (decimal+thousands habit) gives a confusing error; fitter wastes 30s trying to figure out what went wrong.
- **suggested fix**: Distinguish "empty/zero" from "unparseable" — if controller.text is non-empty but _parse returns 0, show "Invalid number format" instead.
- **effort**: S

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:67,74-78
- **issue**: Lower boundary check `angleDeg <= 0` allows angle=0.0001 → multiplier=1/sin(0.0001°)≈573000 → travel=573000×trueOffset. No realistic plumbing elbow exists below ~11.25°; absurd output silently produced.
- **why it matters**: Fitter typing "11" but accidentally getting "0.11" sees a 4-figure mm travel and may cut a 500m pipe before noticing.
- **suggested fix**: Enforce a sane lower bound (e.g. angle >= 5° or warn if <11.25°) AND/OR show a yellow banner when multiplier > 10.
- **effort**: S

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:67
- **issue**: Upper boundary `angleDeg >= 90` rejects 90° as invalid, but 90° is a perfectly valid pipe configuration (Travel = TrueOffset, Run = 0, Multiplier = 1). Excluding it forces fitters to either pick 89° (and get slightly wrong Run≈8.7mm phantom) or skip the tool entirely.
- **why it matters**: 90° elbow rolling-offset jobs are common (mating a vertical riser to an offset horizontal); rejecting the calculator pushes worker to mental arithmetic.
- **suggested fix**: Allow `angleDeg <= 90`; clamp `run = (angleDeg==90) ? 0 : trueOffset/tan(rad)`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/rolling_offset_screen.dart:80-86
- **issue**: When validation succeeds the result fields are updated; when validation FAILS (return at line 65/71) the previous run's result fields remain populated. Fitter changes Rise from 300→3000, mis-types angle, sees the validation snackbar, but the old "True Offset = 500.0" is still showing — easy to copy stale value.
- **why it matters**: Stale numbers in result cells are read as fresh by anyone glancing at the screen mid-task; clipboard copy on stale data leads to wrong cut.
- **suggested fix**: Clear all four result controllers at the start of _calculate() (or before the early-return guards), so any failure leaves results blank.
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:75,80
- **issue**: trueOffset.toStringAsFixed(1) — with sub-millimeter rise/spread (e.g. rise=0.3, spread=0.4 → trueOffset=0.5), the display rounds to "0.5" mm and multiplier path still works; but with rise=0.01, spread=0.01 → trueOffset≈0.014 → displays "0.0" mm yet Travel still shows a non-zero figure. Inconsistent presentation.
- **why it matters**: Unlikely in field work (mm precision is the norm) but inconsistent rounding undermines trust in the calculator.
- **suggested fix**: Use toStringAsFixed(2) for sub-1mm values, or warn if trueOffset < 1mm.
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:44-46
- **issue**: When `_selectedAngle == 'custom'` but `_customAngleController.text` is empty, _parse returns 0 → caught by line 67 with generic "Angle must be between 1° and 89°". Doesn't distinguish "you forgot to type the custom angle" from "you typed an invalid value".
- **why it matters**: Glove-typing user with empty field gets the same error as someone who typed "100" — minor UX friction.
- **suggested fix**: If custom selected and field empty, show "Type a custom angle (1° - 89°)" instead.
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:265
- **issue**: Regex `r'^\d*[.,]?\d*'` permits the empty string and a lone `.` or `,`. _parse(".") returns 0 silently. While the > 0 check catches it, the formatter could pre-block lone-separator input to give clearer typing feedback.
- **why it matters**: Minor; user who taps "." and pauses doesn't get a hint that the value is invalid until pressing CALCULATE.
- **suggested fix**: Switch to TextInputFormatter that requires at least one digit, e.g. `r'^\d+([.,]\d*)?'` (or accept this is acceptable trade-off for typing-in-progress UX).
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:90-93
- **issue**: _isDirty considers only Rise/Spread/customAngle inputs. If the user CALCULATES, then clears Rise (leaving Spread + results), _isDirty stays true via spread — fine. But if they clear ALL inputs after calculating, the results remain visible yet _isDirty is false → swipe-back loses the still-visible results with no warning.
- **why it matters**: Fitter who computes, then clears inputs to "prep next job" but hasn't copied the result yet, can accidentally back out with no prompt.
- **suggested fix**: Include `_trueOffsetController.text.isNotEmpty` in _isDirty so results in view also block silent back-swipe.
- **effort**: S

- **severity**: low
- **location**: lib/screens/rolling_offset_screen.dart:162-166
- **issue**: Switching from "custom" back to a preset (45/60/30) hides the custom-angle field but does NOT clear `_customAngleController`. If user types 22 in custom, taps 45, then CALCULATE, the 45 is used (correct). But the dirty-guard still flags customAngleController as non-empty → back-button warns about "lost custom angle" that's no longer in the workflow.
- **why it matters**: Mildly confusing confirm dialog after switching away from custom; not data-loss but extra tap.
- **suggested fix**: Clear `_customAngleController` whenever `_selectedAngle` changes away from 'custom' (or exclude it from _isDirty when not selected).
- **effort**: S

--- end block ---

## Iter #33 · lib/screens/hydrotest_screen.dart · discoverability
- **severity**: high
- **location**: hydrotest_screen.dart:139-165
- **issue**: Test factor chips (1.5×, 1.3×, 1.43×) have no header/label explaining what they are — fitter sees just three boxes with cryptic codes after the design pressure field
- **why it matters**: A welder/fitter on a workshop floor may not know "ASME B31.3" vs "PED gas" vs "B31.1 steam" intuitively; without an explicit prompt like "Wybierz normę" / "Choose standard" they may tap the wrong one and get wrong test pressure
- **suggested fix**: Add a small section label "WSPÓŁCZYNNIK PRÓBY / TEST FACTOR" or inline helper text "Wybierz normę zgodnie z dokumentacją" above the chips
- **effort**: S

- **severity**: high
- **location**: hydrotest_screen.dart:84-100 (AppBar)
- **issue**: No info/help button in AppBar — there is no entry point to explain inputs, units, what hydrostatic test is, when to use 1.5× vs 1.3×, formula source
- **why it matters**: First-time user opening this calculator has no way to discover the methodology behind it; they cannot verify with senior engineer that they entered values correctly
- **suggested fix**: Add IconButton with Icons.info_outline opening a bottom sheet/dialog explaining hydrotest basics, ASME ref, when to use each factor
- **effort**: M

- **severity**: med
- **location**: hydrotest_screen.dart:108-126 (geometry inputs)
- **issue**: OD/Wall/Length fields lack contextual discoverability — no quick "load from previous job" or "from pipe schedule" shortcut even though OD/wall combos are standardized (DN50 sch40 = 60.3/3.91)
- **why it matters**: Workshop floor user types 60.3 and 3.91 manually every time even though those are NPS 2" sch40 — adds friction and typo risk vs a "pick from schedule" affordance
- **suggested fix**: Add a small "📋 DN / Sch" button next to OD that opens a picker (DN15-DN300 × sch10/40/80) auto-filling OD+wall
- **effort**: M

- **severity**: med
- **location**: hydrotest_screen.dart:243-251 (minimum hold time)
- **issue**: "10 min minimum hold time" is shown only as a result row after calculation — not discoverable as a standalone reference, and only appears once user has entered enough geometry+pressure data
- **why it matters**: A fitter might open the screen just to check "how long do I hold?" but has to fill out the entire form to see the answer
- **suggested fix**: Show the 10-min hold time card always (even before data entered) or add to the info dialog
- **effort**: S

- **severity**: med
- **location**: hydrotest_screen.dart:88-98 (copy report button)
- **issue**: Copy report icon (Icons.copy_all_outlined) in AppBar is the only export affordance — no obvious "Share via SMS/WhatsApp" or "Save as PDF" pathway, even though hydrotest reports are commonly emailed to QC
- **why it matters**: Workshop user copies text but then has to switch apps to paste into messenger or email — share sheet would be one tap
- **suggested fix**: Add Share button next to copy, using Share.share() to invoke native share sheet
- **effort**: S

- **severity**: med
- **location**: hydrotest_screen.dart:36 (flow rate default)
- **issue**: Default pump flow of 40 L/min is pre-filled with no explanation of where the number comes from or whether to change it; no preset chips (e.g., 20/40/60/100 L/min for typical pumps)
- **why it matters**: User may not realize they can change it, or change it without knowing realistic ranges for their pump — fill time estimate will be off
- **suggested fix**: Add small preset chips below flow field: "20 / 40 / 60 / 100 L/min" with labels (manualna pompa / elektryczna / przemysłowa)
- **effort**: S

- **severity**: med
- **location**: hydrotest_screen.dart:270-281 (safety warning text)
- **issue**: Critical BHP/SAFETY warning appears only AFTER calculation succeeds — users who enter invalid data or just browse never see the safety reminder
- **why it matters**: A worker viewing the screen out of curiosity or to estimate before filling in data misses the safety message which is the most important content here
- **suggested fix**: Show safety banner at top of screen always, regardless of calculation state; or as collapsible header
- **effort**: S

- **severity**: low
- **location**: hydrotest_screen.dart:38-39 (default factor comment)
- **issue**: The "1.5× ASME B31.3" default is selected silently — no visual hint/badge such as "DEFAULT" or "DOMYŚLNIE" indicating that this is pre-selected
- **why it matters**: User opening the screen might not realize a factor is already selected and the result already reflects it
- **suggested fix**: Add small "domyślnie" badge or initial focus indicator to the selected chip
- **effort**: S

- **severity**: low
- **location**: hydrotest_screen.dart:208-209 (PSI conversion)
- **issue**: PSI/MPa conversions shown only in sub-row of test pressure result; OD-only psi/MPa conversion not shown for design pressure input
- **why it matters**: Fitter reading instructions in different units (US shop) may want to verify design pressure entered matches the spec in psi/MPa before relying on calc
- **suggested fix**: Add live unit conversion hint below design pressure field as well
- **effort**: S

- **severity**: low
- **location**: hydrotest_screen.dart:36 (flow controller default text)
- **issue**: _flowCtrl has hardcoded default '40' but the units (L/min) shown only in field label; no tooltip clarifies on which pump model 40 L/min is typical
- **why it matters**: Cross-unit confusion possible if user thinks 40 means gal/min
- **suggested fix**: Tooltip or helper text confirming "L/min" unit explicitly
- **effort**: S

- **severity**: low
- **location**: hydrotest_screen.dart:101-104 (ListView padding)
- **issue**: No scroll affordance / no progress indicator that more results exist below the fold when keyboard is open — long results may be hidden
- **why it matters**: On small screens, after typing values the keyboard covers results; user may not realize results appeared
- **suggested fix**: Auto-scroll to results card after focus loss; or add small "→ wyniki niżej" hint when results computed but off-screen
- **effort**: M

- **severity**: low
- **location**: hydrotest_screen.dart:208-209 (test pressure result)
- **issue**: ASME § 345.4.2 reference is shown only in "Minimum hold time" row; the 1.5× factor source isn't repeated in the test-pressure row, weakening discoverability of "why this number"
- **why it matters**: Auditor or senior reviewing the calc may want to see formula source next to the prime result
- **suggested fix**: Add small "= ${design} × ${factor} (ASME B31.3 § 345.4.2)" subtitle under test pressure value
- **effort**: S

--- end block ---

## Iter #34 · lib/screens/pipe_route_calculator_screen.dart · settings-persistence

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:15-25, 35-99
- **issue**: Zero persistence of `R` (elbow takeout) and zero persistence of last inputs (H1/H2/X/Y) or results — already raised in Iter #9 findings #1 and #2. Re-confirmed at Iter #34: file imports only `dart:math`, `flutter/material.dart`, `app_language.dart`, `clipboard_helper.dart`, `help_button.dart` — no `shared_preferences`, no service-layer call, no `prefs_route_*` key. Still the odd-one-out vs bolt_torque / pipe_schedule / material_list / iso_notebook which DO use SharedPreferences (grep-confirmed at audit time).
- **why it matters**: Same workshop pain as before — welder re-types CLR radius (e.g. 57.2 for 1.5×DN 38) for every spool of a 20-route iso; phone backgrounded for foreman SMS → all 5 numbers lost on State rebuild.
- **suggested fix**: As Iter #9 — `SharedPreferences` round-trip on all 5 input controllers + R, restored in `initState()`. Marked low severity per duplicate-guard (already in raw_findings).
- **effort**: M

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:92
- **issue**: Decimal-separator choice still hard-coupled to `AppLanguageController.isEnglish` with no persisted user override — Iter #9 finding #3. No regression but no fix landed either.
- **why it matters**: PL welder on an EN iso drawing cannot pin "dot separator always" — every UI-language toggle silently swaps result formatting.
- **suggested fix**: Persisted `prefs_decimal_separator` (auto/dot/comma) read here instead of `isEnglish`.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:20 (`_rController = TextEditingController(text: '0')`)
- **issue**: `R = 0` is treated as the implicit, undocumented default — but there is no persisted "default takeout strategy" preference (e.g. "always preload last-used R", "always start from 0 / C-C", or "preload from selected pipe schedule's CLR table"). A persisted policy flag would let the welder pick once whether each new entry should default to 0 (C-C mode) or to their last-used elbow radius. Distinct from Iter #9 finding #1 (persist last value) — here the issue is the *behaviour choice* on app start when no last value exists, AND when the user changes DN on the Schedule screen.
- **why it matters**: A shop that exclusively does C-C ISO drawings wants R=0 forever; a shop running LR 90° SCH40 carbon every shift wants R prefilled to their stock elbow. No way to express this preference today.
- **suggested fix**: Add `prefs_pipe_route_R_default_mode` (`zero` | `last` | `schedule_clr`) + optional `prefs_pipe_route_R_value`; default to `zero` for backwards compat, surface in global Settings.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:27 (`_parse`), 92-96 (formatters)
- **issue**: `_parse` accepts both `.` and `,` as decimal separators (good), but does NOT reject thousand-separators (`1,234.5` → silently parsed as `1.234.5` → `0`) and does NOT trim units (welder pastes "57.2 mm" from another app → parsed as 0). No persisted "strict parsing" preference and no warning. Settings layer could expose a strict-mode toggle for sites where copy-paste from spreadsheets is common.
- **why it matters**: Silent zero from a pasted "1,234.5" or "57.2 mm" gives a bogus segment length with no feedback — exactly the failure mode that scraps pipe on the floor.
- **suggested fix**: Strip trailing units (mm/in) and a single thousand-separator before parse; if result is still NaN show explicit SnackBar; OR persist a `prefs_strict_numeric_input` flag.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:118 (`HelpButton(help: kHelpPipeRoute)`)
- **issue**: Confirmed by inspecting `lib/widgets/help_button.dart`: pure `StatelessWidget` with no SharedPreferences interaction — no "Don't show again" checkbox in the bottom sheet, no `help_seen_<id>` flag, no first-run auto-pop either. So Iter #9 finding #6 was half-resolved (no auto-pop nuisance) but the inverse problem stands: a confused first-time user has no persisted "I've read this, hide the help icon" affordance. Settings persistence layer is incomplete app-wide.
- **why it matters**: For a multi-user shared tablet (common on fab shop floors), every welder either re-reads help or there's no way to mark "training done". Settings persistence layer is incomplete.
- **suggested fix**: Add optional persisted `help_dismissed_<screenKey>` set in `HelpButton`, and a "Don't show again" checkbox in `_HelpSheet`. Defaults preserve current behaviour.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pipe_route_calculator_screen.dart:101-110 (`dispose`)
- **issue**: `dispose()` does NOT flush pending input state to persistence before tearing down controllers. If persistence is added per prior recommendations, the welder typing the 5th value when the OS backgrounds the activity (Android `onSaveInstanceState` path) loses keystrokes between last `_calculate()` and screen kill, because save only fires inside `_calculate()`. No `WidgetsBindingObserver.didChangeAppLifecycleState(AppLifecycleState.paused) → _save()` hook.
- **why it matters**: Workshop phones swap apps frequently (camera, WhatsApp, iso PDF) — losing the last 2-3 typed digits means re-measuring with calipers, costing minutes per spool.
- **suggested fix**: Implement `WidgetsBindingObserver`, persist all controller texts on `AppLifecycleState.paused`/`inactive`, restore in `initState()`. Standard Flutter pattern.
- **effort**: S

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:88,96 (`toStringAsFixed(1)`)
- **issue**: Iter #9 finding #4 (no persisted precision pref) — unchanged. Re-confirmed: literal `1` decimal place still hard-coded for all 4 outputs.
- **why it matters**: Same as Iter #9 — chalk-on-pipe vs CNC layouts want different decimals.
- **suggested fix**: As Iter #9 — `prefs_route_decimals` (0/1/2).
- **effort**: S

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:69-79 (Reset-R / Undo SnackBar actions)
- **issue**: Iter #9 finding #5 (Reset-R / Undo bypass persistence helper) — unchanged. Code still mutates `_rController.text` directly without any save() call. Latent bug the moment persistence ships.
- **why it matters**: Non-deterministic saved R state if persistence is wired only into `_calculate()`.
- **suggested fix**: Centralised `_saveSettings()` called from all 3 sites.
- **effort**: S

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart (whole file)
- **issue**: No "named presets" persistence (e.g. "Loop A — galley header", "Riser 3rd deck") — useful when a shop fabricates the same spool family weekly. Distinct from Iter #9's calculation-history idea: presets are user-named and reusable, history is auto-recorded chronological.
- **why it matters**: On marine / process EPCs the same spool geometry recurs across hulls — typing the same H1/H2/X/Y five Mondays in a row is wasted floor time.
- **suggested fix**: Persist `List<{name, h1, h2, x, y, r}>` in `SharedPreferences` under `pipe_route_presets`; AppBar gets a `bookmark` icon for save/load.
- **effort**: L

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:267-302 (`_showTotalFormulaDialog`)
- **issue**: Formula dialog has no persisted "Mark as understood / don't show formula tooltip badge" flag. The `info_outline` icon (line 224) is therefore visually identical for first-time vs returning users — no progressive disclosure.
- **why it matters**: Minor; visual clutter for an experienced welder who knows the formula by heart, indistinguishable from new-user state.
- **suggested fix**: Persist `prefs_pipe_route_formula_seen` bool, dim the info icon by 40 % opacity once true.
- **effort**: S

- **severity**: low
- **location**: lib/screens/pipe_route_calculator_screen.dart:312-325 (`_field` keyboardType)
- **issue**: Iter #9 finding #9 (no persisted unit-system pref) — unchanged. Imperial / metric flag still not in scope but still missing.
- **why it matters**: As Iter #9.
- **suggested fix**: As Iter #9 — `prefs_unit_system`.
- **effort**: XL

--- end block ---

## Iter #35 · lib/screens/orbital_tig_screen.dart · first-time-ux

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:310-324 (`_field` helper for OD/wall/Volts)
- **issue**: All numeric fields use `TextInputType.numberWithOptions(decimal: true)` with no `textInputAction` and no `FocusNode`/next-field chain. A first-time welder typing OD on Android sees a keyboard with a green checkmark "Done" that dismisses the keyboard instead of advancing to the wall field. The keyboard then has to be re-opened to type the wall thickness.
- **why it matters**: On the workshop floor with gloves half-removed, every extra keyboard tap costs 3-4 seconds. The first-time user reads the dismissal as "the app didn't accept my number" and retypes — leading to wrong values being committed to a coupon.
- **suggested fix**: Pass `textInputAction: TextInputAction.next` for OD + wall, `TextInputAction.done` for volts, and wire FocusNodes so OD→wall→volts traversal is one tap each.
- **effort**: S

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:310-324 (`_field` regex `[0-9.,]`)
- **issue**: Input formatter allows BOTH `.` and `,` and any count of them. A welder used to a PL keyboard may type "25,4,0" or "25..4" by mistake; `_p()` only swaps the first comma to a dot and `double.tryParse` returns null silently → `_error` says "Podaj średnicę zewnętrzną" even though they DID type something. Looks like the field does not read what was typed.
- **why it matters**: First-time users blame themselves or the app when valid-looking input produces a "missing value" error. They retype, fail again, abandon.
- **suggested fix**: Tighten regex to a single-separator pattern via a custom `TextInputFormatter`, or normalize multiple separators in `_p()` and show a friendlier error "Niepoprawny format liczby (np. 25.4)".
- **effort**: S

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:50-77 (`_calc` blind to voltage out of physical range)
- **issue**: `_calc()` only validates `od > 0`, `wall > 0` and `wall <= od/2`. It accepts arc voltage of 0, 999, or negative-via-future-input without warning, and feeds it straight into `estimateOrbital`. A first-timer who fat-fingers `100` into the V field gets a heat-input result silently 10x off the realistic range — no indication the value is suspect.
- **why it matters**: Heat input Q goes onto the WPS log / coupon traceability. A 10x-wrong Q passed up to QC is a real workshop incident risk for somebody new to the tool.
- **suggested fix**: After parsing, clamp `v` to a plausible orbital TIG range (e.g. 6-14V) OR show a yellow inline warning "Napięcie poza typowym zakresem 8-12 V — sprawdź odczyt z głowicy" while still computing.
- **effort**: S

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:153-165 (Stempel/WPS free-text with `textCapitalization: characters` and no `inputFormatters`)
- **issue**: The trace field auto-capitalizes everything, allows newlines, emoji and arbitrarily long strings. The copy template embeds raw `_trace.text.trim()` straight into the clipboard payload. A first-timer who pastes a multi-line WPS card snippet (common on tablets that auto-paste from emails) gets a 20-line clipboard blob the foreman has to clean up.
- **why it matters**: First impression on the foreman receiving the paste is "this welder does not know how to send parameters". Damages trust in the tool output.
- **suggested fix**: Add `inputFormatters: [LengthLimitingTextInputFormatter(40), FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))]` and add helper text "max 40 znaków, bez Enter".
- **effort**: S

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:87-90 (no `keyboardDismissBehavior` on ListView)
- **issue**: ListView has no `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`. A first-time user filling the form, then trying to swipe down to peek at the result card below, finds the keyboard stays glued to the screen covering the bottom half. They cannot see the L3/L4 currents and the copy button without hunting for the keyboard dismiss key.
- **why it matters**: On 5.5" workshop phones the keyboard eats 45% of the viewport; not auto-dismissing on drag is the top source of "I cannot see my result" complaints from first-time mobile-calc users.
- **suggested fix**: Add `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` to the ListView, OR wrap the body in a `GestureDetector(onTap: () => FocusScope.of(context).unfocus(), behavior: HitTestBehavior.translucent)`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/orbital_tig_screen.dart:385-393 (`CopyOnLongPress` on each amp value)
- **issue**: Each level row uses `CopyOnLongPress` with no visible affordance — no tiny copy icon, no underline, no haptic-on-press hint, no tooltip. A first-time user has no way to discover that long-pressing the orange "82 A" text copies it. The bulk "Kopiuj wszystkie parametry" button below is visible, but per-row copy is invisible until accidentally discovered.
- **why it matters**: For multi-pass jobs the welder often wants to load only one level value into the head; not knowing per-row copy exists forces them to copy-all then manually clean up text before pasting. They give up and type the number manually instead.
- **suggested fix**: Add a faint trailing `Icons.copy_outlined` (size 14, _kMuted) next to each amps reading; or add an onboarding tooltip on first-mount "Przytrzymaj wartość, aby skopiować pojedynczo".
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:87-90 (ListView padding `EdgeInsets.fromLTRB(16, 16, 16, 24 + bottom)`)
- **issue**: There is no extra bottom padding when the keyboard is open. With `MediaQuery.viewInsetsOf(context).bottom` not added, the copy button can sit underneath the keyboard for short-screen devices once the user re-focuses a field after a result is shown.
- **why it matters**: First-timer types a stamp/WPS string after viewing results, then tries to tap "Kopiuj wszystkie parametry" — the button is hidden under the IME and they think the app forgot the values.
- **suggested fix**: Replace `viewPaddingOf` with `viewPaddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom` so padding grows with the IME.
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:230-238 (header line in copy payload)
- **issue**: Copy template header uses `${od?.toStringAsFixed(1)}` — if `od`/`wall` are somehow null at copy-time (e.g. user cleared a field after computing) the clipboard gets `"OD null x t null mm"`. Defensive but ugly for a first-time foreman receiving the paste.
- **why it matters**: Very rare edge case but produces an embarrassing first impression for the WPS reviewer.
- **suggested fix**: Compute `od` and `wall` from `_est` directly (already validated) or guard `if (od == null || wall == null) return;` before building the string.
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:175-185 (red error block — overlaps Iter#10)
- **issue**: Error container has no Semantics live-region — a screen-reader user (rare in workshops, common for accessibility audits / Polish WCAG 2.1) does not get the validation error announced.
- **why it matters**: Compliance + edge accessibility; not core workshop first-use, but flagged for completeness.
- **suggested fix**: Wrap error Container in `Semantics(liveRegion: true, child: ...)`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/orbital_tig_screen.dart:8-15 (private color constants — overlaps prior consolidation findings)
- **issue**: File redeclares its own palette; cross-screen-consistency was already flagged in earlier iterations for sibling screens. First-time user moving from heat_input → orbital_tig may notice a slightly different green/orange tone but it is low-impact for first-use.
- **why it matters**: Overlap with prior synthesis; mark low.
- **suggested fix**: Adopt `lib/theme/app_colors.dart` when the global refactor is rolled out.
- **effort**: M

--- end block ---

## Iter #36 · lib/screens/pre_weld_checklist_screen.dart · cross-screen-consistency

- **severity**: high
- **location**: lib/screens/pre_weld_checklist_screen.dart:178 (Scaffold without `backgroundColor: _kBg`)
- **issue**: Every sibling tool screen (heat_input, hydrotest, bolt_torque, saddle_template, job_add, jobs, ai_chat, help, etc.) declares `const _kBg = Color(0xFF0F1117)` and sets `Scaffold(backgroundColor: _kBg, ...)`. This screen omits both — the `_kBg` constant is not declared and Scaffold falls back to the global theme background. Navigating Home → Pre-weld Checklist → Heat Input shows a visible brightness flash because the Scaffold default can render differently from `#0F1117`.
- **why it matters**: A welder swiping between the checklist (before strike) and the heat-input calc (set machine parameters) sees a tone shift on every navigation — outdoors in shop lighting the flash reads as "app glitched / lost state", undermining trust in the just-ticked checklist persistence (especially since state IS in-memory only).
- **suggested fix**: Add `const _kBg = Color(0xFF0F1117);` to the palette block and `backgroundColor: _kBg,` to the Scaffold at line 178.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:245-266 (ChoiceChip strip vs. heat_input_screen.dart:442-455)
- **issue**: Material picker chip pattern diverges from heat_input_screen which uses `Wrap(spacing: 6, runSpacing: 6)` with `labelPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)`. This screen uses a horizontally-scrolling `ListView` inside a fixed `SizedBox(height: 48)` with no `labelPadding`. Same MaterialCatalog data, two different shapes — the heat_input version is fully visible on first glance whereas the checklist version hides grades behind a horizontal scroll with no fade-edge indicator.
- **why it matters**: A welder who just used Heat Input to pick "P91" sees the grade upfront; switching to Pre-weld Checklist they reach for the same chip and find it scrolled off-right. Discovery failure on a safety-critical control (P91 chip gates the CRITICAL preheat 200-250 °C and mandatory PWHT lines 46-51).
- **suggested fix**: Replace SizedBox+ListView with `Wrap(spacing: 6, runSpacing: 6, children: [...])` matching heat_input pattern; add the same `labelPadding` to every ChoiceChip.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:7-12 (palette block — no `_kBg`, name drift vs. sibling screens)
- **issue**: Local palette declares `_kCard`, `_kBorder`, `_kOrange`, `_kGreen`, `_kSec`, `_kMuted` — overlaps with identically-named constants in heat_input_screen.dart, hydrotest_screen.dart, bolt_torque_screen.dart, orbital_tig_screen.dart. The `_kSec` value here is `Color(0xFF9BA3C7)` which matches heat_input but heat_input calls the same value `_kTextSec` — naming drift makes a single-file refactor brittle.
- **why it matters**: When a future audit converges all screens to a single theme, this file's palette will conflict on names (`_kSec` vs `_kTextSec`) and miss `_kBg` entirely. Today the visible impact is the missing background (already flagged high); medium severity captures the naming drift.
- **suggested fix**: Rename `_kSec` -> `_kTextSec`, `_kMuted` -> `_kTextMut` to match heat_input_screen.dart; add `const _kBg = Color(0xFF0F1117);`. Better long-term: import from a single `app_colors.dart`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:178-189 (AppBar — no Copy/Share action vs. siblings)
- **issue**: Every other parameter-bearing screen exposes a `Copy/Share report` action in the AppBar (hydrotest:88-98 `Icons.copy_all_outlined`, heat_input has copy buttons, orbital_tig has bulk copy, bolt_torque has copy). This checklist's AppBar exposes only a Reset TextButton — there is no way to copy the ticked-state summary (e.g. `"P91 · 11/11 OK · 2026-06-07 · welder ID"`) to attach to the WPS coupon record.
- **why it matters**: A QC inspector touring the line asks "did you run pre-weld?" The welder wants to paste a one-line confirmation into the weld journal (`weld_journal_screen.dart` exists in the app). Without copy-action there is no audit trail — the file header at line 21 says "it is a live check, not a record" which is correct philosophy, but the inability to optionally export breaks workflow continuity with sibling screens (weld_journal, coupon_log).
- **suggested fix**: Add `IconButton(Icons.copy_all_outlined)` next to Reset that builds a one-liner: `"Pre-weld ${_material?.key ?? 'generic'} ${_done.length}/${_all.length} ${all ? 'OK' : 'INCOMPLETE'}"` and writes via `ClipboardHelper.copy()`. Disabled when `_done.isEmpty`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:255-266 (Tooltip on ChoiceChip — pattern not used by heat_input_screen for the same material chips)
- **issue**: Long-press tooltip surfaces preheat note + °F conversion — a genuinely useful affordance — but heat_input_screen.dart:442-455 (the OTHER place these material chips live) does NOT have a tooltip. A welder who learns the long-press hint here will try it on Heat Input and find nothing happens. Inconsistency in chip-affordance across the same source data.
- **why it matters**: Tool affordances must be consistent — if the chip behaves differently in two screens, the welder cannot predict where to find info. The °F conversion (lines 117-127) is also calculated here but absent in heat_input, even though heat_input has more horizontal space to show a tooltip card.
- **suggested fix**: Extract `_preheatFahrenheit` + tooltip into a shared widget used by both screens, OR mirror the tooltip into heat_input_screen so welder-discoverable behavior matches across the app.
- **effort**: M

- **severity**: med
- **location**: lib/screens/pre_weld_checklist_screen.dart:241-271 (no scroll-edge fade on horizontal material strip)
- **issue**: Iter #1 already flagged the iso_notebook toolbar for "no fade-edge gradient, no scroll-indicator". Same antipattern repeats here: `ListView(scrollDirection: Axis.horizontal, ...)` with 6+ material chips has no visible affordance that content extends past the right edge. The welder may believe only "wszystkie / P1 / P4 / P5" are available and never discover P10 (Duplex) or P43 (Inconel).
- **why it matters**: Duplex/Inconel checks (lines 67-85) are the highest-risk grade-specific items in the file — interpass MAX 150 °C, ferrite check, low HI <1.5 kJ/mm. Hiding the chip that gates them behind a hidden horizontal scroll = the checks never fire for the welder who needs them most (a P91 expert touching their first Duplex joint).
- **suggested fix**: Add a `ShaderMask` (linear gradient from opaque to transparent on right edge) wrapping the ListView, OR switch to `Wrap` (matching heat_input — solves this AND finding #2 in one change).
- **effort**: S

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:283-310 (divider label `Specyficzne · ${_material!.key}` — no app-wide divider pattern)
- **issue**: Custom divider with orange-uppercase letter-spacing label is unique to this screen. Heat_input uses `_SectionCard` widget for sectioning; jobs_screen / job_add use plain Dividers. There is no shared "category divider" widget — three different visual languages in the app for "this section is different from the previous one".
- **why it matters**: Low — design language drift is mostly cosmetic, but a fitter scanning multiple tools per shift unconsciously learns visual cues; inconsistent dividers slow that learning.
- **suggested fix**: Extract `_SectionDivider({required String label})` into `lib/widgets/section_divider.dart` and adopt in this screen + future tools.
- **effort**: M

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:175,354 (mixed i18n style — `isPl ? c.pl : c.en` vs `context.tr`)
- **issue**: Mixed i18n style — line 175 reads the language directly, then line 354 uses `isPl ? c.pl : c.en` for inline strings while line 180/186/213/216 use the `context.tr(pl:..., en:...)` helper. Sibling screens (heat_input, hydrotest) use only `context.tr(...)`. The `_tr` lambda alias pattern in hydrotest_screen.dart:41 is yet another style.
- **why it matters**: Low — both styles compile and produce correct translations; mostly a code-review consistency concern when a third translator joins (e.g. DE/UA support) and has to find every translatable string.
- **suggested fix**: Drop `final isPl = ...` and replace `isPl ? c.pl : c.en` with `context.tr(pl: c.pl, en: c.en)` — matches sibling-screen idiom and survives future language additions without code churn.
- **effort**: S

- **severity**: low
- **location**: lib/screens/pre_weld_checklist_screen.dart:88-111,143-150 (universal `_checks` list — no `key`/id for each item)
- **issue**: Each check is identified only by its list index. If `_pNumberExtras` is reordered, the in-memory `_done` set (tracking ticked indices) silently shifts. Sibling list-based screens (jobs_screen, coupon_log) use stable keys. The comment at lines 143-150 says "Index 0..len-1 stays consistent across builds because we never re-order" — but that is a fragile contract.
- **why it matters**: Low while state is purely in-memory (resets on screen pop). If a future iteration persists ticked-state (e.g. resume after app suspend or QC export), index-based identity will silently corrupt records when the catalog is updated.
- **suggested fix**: Convert `_Check` to `_Check(this.id, this.pl, this.en)` and store `_done` as `Set<String>` keyed by id. Also future-proofs export/copy (finding #4).
- **effort**: M

--- end block ---


## Iter #37 · lib/screens/elbow_takeout_screen.dart · backend-robustness

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:37-50 (_rows getter)
- **issue**: Cache invalidation key is `_cachedQ == _q` but `_cachedQ` defaults to '' and `_cachedRows` defaults to `kElbowTakeouts`. First read with `_q==''` is correctly served from cache. However, if the underlying `kElbowTakeouts` is ever mutated at runtime (e.g. future hot-reload of localized NPS strings, or a feature flag that adds DN700/DN800 entries), the cache silently serves a stale reference because invalidation is keyed only on query string, not on a data version. There is also no defensive copy — `_cachedRows = kElbowTakeouts` returns the const list directly; any accidental mutation downstream would throw `Unsupported operation: Cannot modify an unmodifiable list` (acceptable) but a sorted/grouped variant introduced later would mutate caller's view.
- **why it matters**: Today benign because list is const. Becomes a silent-stale-data bug the moment a future iteration adds e.g. unit toggle (mm/inch) that rewrites entries — fitter sees old mm values after switch.
- **suggested fix**: Add a `_dataVersion` int bumped when source changes (or simply key cache on `(query, kElbowTakeouts.length)`); return `List.unmodifiable(...)` from the getter.
- **effort**: S

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:40-47 (_rows filter predicate)
- **issue**: Filter does case-insensitive substring on `nps` and lowercased dn, but query `_q` is `.trim().toLowerCase()` only after the `_cachedQ == _q` check. The cache key (`_cachedQ`) is stored as the RAW trimmed value from `onChanged` (already trimmed at line 81), but `q` used in the filter is `_q.trim().toLowerCase()` — so cache key and filter input diverge in case: querying `DN50` (caps) vs `dn50` (lower) produces same filter results but two cache misses + recomputes. Worse: NPS column contains spaces ("1 1/2", "2 1/2") and slashes; user typing `1 1/2"` (with smart quote from autocorrect) misses because the haystack contains no `"` character.
- **why it matters**: Phone autocorrect frequently inserts smart quotes around fraction sizes (1½, 1 1/2"). Fitter searches and gets zero results despite DN40 matching — looks like a missing-data bug, undermines trust in the table.
- **suggested fix**: Normalise both haystack and needle: strip `["\u2032\u00bd\u00bc\u00be]`, collapse whitespace, then substring. Also store `_q` as already-lowercased so cache hits are stable.
- **effort**: S

- **severity**: med
- **location**: lib/screens/elbow_takeout_screen.dart:44-47 (NPS search) cross-ref lib/data/elbow_takeouts.dart:11-32
- **issue**: Filter does not normalise fraction characters. Data uses ASCII fractions like `1 1/2`, `2 1/2`, `3 1/2`. iOS Smart Punctuation auto-converts `1/2` to `½`. Searching `1½` returns empty list. No `replaceAll('½', '1/2')` etc. Also no acceptance of decimal form `1.5` -> `1 1/2`.
- **why it matters**: On a workshop iPhone with smart punctuation ON (default), typing fractions becomes Unicode glyphs that never match. Lookup fails silently → fitter walks back to the laminated catalogue.
- **suggested fix**: Add a normalisation step that maps `½ → 1/2`, `¼ → 1/4`, `¾ → 3/4`, strips quote chars, before substring match. Also accept input `1.5` and map to `1 1/2`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:11 (data source) cross-ref lib/data/elbow_takeouts.dart:11-32 and :51-62
- **issue**: Table is hard-coded const with no schema-version field, no assert on ordering by DN, no uniqueness guard. If a future PR appends DN15 twice or out-of-order, the filter still works but `closestByDn` does a linear scan returning the FIRST tied-distance match — duplicates would silently bias results.
- **why it matters**: Indirect — affects any future screen that calls `closestByDn` (e.g. a future "auto-suggest from pipe scanner" feature). Defensive assert would catch test-time regressions.
- **suggested fix**: Add `assert` in a `_validate()` static or unit test for monotonic DN and uniqueness; introduce `static const int schemaVersion = 1` on the model class for future migrations.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:91-93 (ListView.builder, no Key)
- **issue**: No `Key` on `_Row` children. With cached filtered list and rapidly changing `_q`, Flutter element reuse may keep `RichText` widget state if a row data changes but position stays the same (e.g. DN50 row becomes DN65 row after filter). The `_Cell.CopyOnLongPress` long-press recogniser is tied to the Element, so a fast filter change mid-long-press can copy the wrong value to clipboard.
- **why it matters**: Edge case — fitter starts long-press on DN100 row (152 mm), the row gets recycled to DN125 (190 mm) before release, snackbar shows "190 mm" copied. Wrong number sent to foreman = wrong cut.
- **suggested fix**: `itemBuilder: (_, i) => _Row(key: ValueKey(_rows[i].dn), e: _rows[i])`. Also makes filter animations cleaner.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:88-94 (no empty-state)
- **issue**: When filter yields 0 rows the `ListView.builder` renders nothing — blank gray area below the legend bar. No `Brak wyników` feedback. Combined with the smart-quote/fraction bugs above, a real user query that should match often produces a void.
- **why it matters**: Silent failure mode. Fitter cannot tell whether the app crashed, the data is missing, or the typo is theirs. Trust erosion.
- **suggested fix**: After `_rows.isEmpty`, render a centred icon + `context.tr(pl: 'Brak wyników', en: 'No results')` with a `Wyczyść filtr` button calling `_filter.clear()` + `setState(()=>_q='')`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:193-195 (_Cell value formatting)
- **issue**: `'${e.lr90}'`, `'${e.sr90}'`, `'${e.lr45}'` interpolate raw ints with no defensive handling if a future data row holds a sentinel like `-1` for "not standard at this DN" — it would render as `-1 mm` and be copyable as `-1` to clipboard. Fitter pastes `-1` into chat as a "cut length" — embarrassing at minimum. Also missing `maxLines`/`overflow` on the value Text — large values (>9999) breaking the 3-column `Expanded` layout would chop digits mid-character with no visual hint.
- **why it matters**: Speculative today (all values >0) but a robustness lens flags it. Forward-looking guard against bad data and oversized rendering.
- **suggested fix**: Guard rendering: `value <= 0 ? '—' : '$value'`; add `maxLines: 1, overflow: TextOverflow.visible, softWrap: false` to surface overflows visibly during dev.
- **effort**: S

- **severity**: low
- **location**: lib/screens/elbow_takeout_screen.dart:23 (no error boundary)
- **issue**: Screen has no `try/catch` around the lazy filter or list rendering. Today bulletproof because data is const. But if `kElbowTakeouts` is ever populated from JSON/remote-config in a future iteration, an exception during `_rows.where(...)` would surface as a red-screen-of-death inside the AppBar — no friendly fallback.
- **why it matters**: Forward-looking robustness. If data ever moves to a Firebase-Remote-Config sync (likely given user's stack defaults), a malformed payload kills the screen.
- **suggested fix**: Wrap body Column in a small ErrorBoundary widget (or Builder + try/catch) that renders `Tabela kolan chwilowo niedostępna — przeładuj` with a retry button.
- **effort**: M

--- end block ---

## Iter #38 · lib/screens/cut_list_summary_screen.dart · permission-ux
- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:78-93 (_exportPdf)
- **issue**: No `ShareResult` capture — `PdfExportService.exportCutList()` returns void, share_plus result is discarded. Fitter who taps PDF then dismisses the iOS share sheet (or whose AirDrop permission prompt fires and is denied) gets no snackbar. Permission-flow visibility = zero. (overlaps iter #13 finding 1 — kept low per duplicate guard)
- **why it matters**: On iOS 17 / Android 14 first share invocation may trigger "Allow Fitter Welder Pro to share via AirDrop / Nearby Share?" — if user denies, app shows no recovery hint.
- **suggested fix**: Have `exportCutList` return `ShareResult`; map status (success/dismissed/unavailable) to PL/EN snackbars in `_exportPdf` so worker sees closed loop.
- **effort**: S

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:78-93, 255-279 (export trio)
- **issue**: No haptic on PDF export action (only `Haptic.copied()` on share/CSV). Glove-wearing welder tapping PDF icon gets visual spinner only — no tactile confirmation. If transient OS permission overlay (notifications/share) covers the spinner, user has no signal the tap registered, and re-taps potentially fire concurrent share sheets / clipboard reads triggering OS "app accessed clipboard" banners.
- **why it matters**: Double-tapping a slow-export button can stack OS-level privacy banners (share sheet up + clipboard read) and look like data exfiltration. Haptic gives instant "tap accepted" feedback even when screen is occluded.
- **suggested fix**: Add `await Haptic.tap()` at start of `_exportPdf` (before await) and short-circuit double-tap via `onPressed: _exporting ? null : _exportPdf` during share-sheet up-time.
- **effort**: S

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:255-279 (clipboard writes — no project-name redaction)
- **issue**: `_buildTextSummary` and `_buildCsv` push the full project name (potentially client/contract name like "Orlen Płock Unit 7 – pipe rack 14") onto system clipboard. On shared shop-floor phones with multi-app clipboard managers (Gboard clipboard, SwiftKey, OEM Samsung Clipboard) this data persists across users + apps, surfacing privacy/NDA exposure that worker did not consent to. No in-app rationale before copy fires.
- **why it matters**: Welders/fitters frequently sign confidentiality on industrial sites (refinery, nuclear, military). Cut-list project names can be sensitive. Silent clipboard write that later auto-pastes into a foreman's WhatsApp suggestion bar is a data-leak risk that needs UX surfacing.
- **suggested fix**: Before first session-copy, show one-shot dialog: PL "Skopiujemy listę do schowka. Może być widoczna w innych aplikacjach (klawiatura, schowek systemowy). Kontynuować?" / EN equivalent with "Nie pokazuj więcej". Persist via SharedPreferences `cut_list_clipboard_consent`.
- **effort**: M

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:118 (Icons.picture_as_pdf_outlined)
- **issue**: Bare PDF icon with no visible badge/label. On a 4.7" shop phone with smudged screen and gloves the icon is indistinguishable from "share" and "table_view" outlined siblings. Mis-tap to share sheet on first use = OS permission prompt user wasn't expecting (e.g. iOS Contacts access for share-via-Messages). (overlaps iter #13 finding 2 — kept low)
- **why it matters**: Distinguishing PDF (in-app render → temp file → share sheet) from "share text" (clipboard only — no system permission) by icon alone fails the gloved-welder test.
- **suggested fix**: Use filled `Icons.picture_as_pdf` (solid orange) for primary export to differentiate from outlined sibling icons; or color-tint PDF icon orange and leave others gray.
- **effort**: S

- **severity**: med
- **location**: lib/screens/cut_list_summary_screen.dart:78-93 (no notification permission rationale)
- **issue**: When share_plus hands off PDF to e.g. Outlook/WhatsApp on Android 13+, that target app may need POST_NOTIFICATIONS permission for welder to see "PDF sent" toasts. App makes no effort to inform user that *the receiving app's* permissions affect whether they see delivery confirmation — they may interpret silence as "PDF didn't go out" and re-export, triggering duplicate share sheets / OS banner stacking.
- **why it matters**: Workshop user who thinks PDF didn't send will tap export 3-4 times, generating 4 temp files (cleanup never wired — see `getTemporaryDirectory` in pdf_export_service.dart:82) AND 4 share-sheet OS prompts that may chain together as "this app keeps asking permission".
- **suggested fix**: After successful share, show snackbar PL "PDF wysłany — sprawdź wybraną aplikację (Outlook/WhatsApp). Jeśli nie widzisz, sprawdź powiadomienia." with longer (5s) duration so worker doesn't immediately re-tap.
- **effort**: M

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:107-132 (AppBar actions — no semantics labels)
- **issue**: IconButtons use `tooltip:` but `Semantics(label:)` is not set. TalkBack/VoiceOver on a phone where welder has accessibility services on (e.g. magnification for older eyes) reads only raw icon name "picture as pdf outlined" — a confused user may invoke screen-reader-driven exploration that triggers haptic-feedback / clipboard side-effects without intent. (overlaps iter #13 finding 5 — kept low)
- **why it matters**: Accessibility-driven mis-activation of share / clipboard actions = unexpected OS permission prompts for users who never explicitly tapped.
- **suggested fix**: Wrap each AppBar IconButton in `Semantics(label: context.tr(pl:..., en:...), button: true)` matching the tooltip text.
- **effort**: S

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart (no temp-file cleanup)
- **issue**: Every PDF export creates `CutList_<name>_<epoch>.pdf` in `getTemporaryDirectory()` and never deletes it. On a workshop phone with 16GB storage and 50 cut-list exports per week the temp dir balloons; iOS/Android may eventually surface "Storage almost full — allow app to clean?" system prompts that welder cannot link back to "the cut-list app". No in-app rationale for why an export-only screen needs ongoing storage budget.
- **why it matters**: System-level storage-warning prompts are the most confusing class of OS dialog for non-technical workshop users; tying them to an export action they don't recall ever consenting to erodes trust.
- **suggested fix**: After successful `Share.shareXFiles`, delete the temp file (in `PdfExportService.exportCutList`), or schedule pruning of files older than 7 days on `_load`. Document in file header.
- **effort**: S

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart:85-89 (snackbar uses raw exception)
- **issue**: `SnackBar(content: Text('PDF błąd: $e'))` echoes raw exception. If `PathAccessException` fires (Android MDM-locked corporate phones do block temp dirs), welder sees "PDF błąd: PathAccessException: ..." — confusing AND it does NOT direct them toward "your IT may have locked file writes — call admin". Permission-related errors deserve a permission-specific recovery hint. (overlaps iter #13 finding 4 — kept low)
- **why it matters**: Enterprise MDM (Intune/Workspace ONE) deployments to construction firms are growing — exception messages need to map to permission-friendly recovery copy.
- **suggested fix**: Switch on exception type; for `PathAccessException`/`FileSystemException(errno=13)` show PL "Brak uprawnień do zapisu — skontaktuj się z administratorem urządzenia służbowego." with copy-debug-info action.
- **effort**: S

- **severity**: low
- **location**: lib/screens/cut_list_summary_screen.dart (whole file — no policy comment)
- **issue**: No header comment documenting "this screen MUST NOT require runtime permissions". A future contributor adding "save PDF to Downloads folder" feature will silently add WRITE_EXTERNAL_STORAGE on Android <11 and break the zero-permission UX. (overlaps iter #13 finding 8 — kept low)
- **why it matters**: Codebase guardrail against permission creep.
- **suggested fix**: Add file-top doc comment: `// EXPORT POLICY: temp dir + share_plus + clipboard only. No runtime permissions. Do NOT add permission_handler, WRITE_EXTERNAL_STORAGE, or scoped MediaStore writes here — workshop users on enterprise MDM phones must see ZERO OS permission dialogs from the cut-list screen.`
- **effort**: S

--- end block ---

---

## Iter #39 · lib/screens/material_list_screen.dart · snackbar-quality

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:38-62 (_load)
- **issue**: `_builder.buildForProject(pid)` and the two `SharedPreferences` calls are awaited without any try/catch. If the DAO throws (corrupt DB row from a partial save, schema mismatch after upgrade, locked sqlite file) the exception silently bubbles up — `_loading` stays `true`, the spinner spins forever, and no SnackBar tells the welder "BOM nie mógł się zbudować, sprawdź segmenty".
- **why it matters**: On the shop floor a frozen spinner reads as "the app is thinking" — the fitter waits 30s, kills the app, reopens, lands on the same spinner, blames the phone. A one-line error SnackBar with a Retry action would let them either retry or back out to fix the offending segment.
- **suggested fix**: Wrap the build/prefs in try/catch, in the catch reset `_loading=false`, set `_items=[]`, and call `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(pl:'Nie udało się zbudować listy materiałowej', en:'Failed to build material list')), action: SnackBarAction(label: tr(pl:'Ponów', en:'Retry'), onPressed: _load)))`.
- **effort**: S

- **severity**: med
- **location**: lib/screens/material_list_screen.dart:44-47 (empty pid recovery branch)
- **issue**: When `widget.projectId.isEmpty` AND the prefs key is also empty, `_items` quietly becomes `[]` and the user sees the generic "Brak danych (dodaj segmenty)" empty state — which lies, because the real cause is "we lost your project id, no data could be looked up". No SnackBar distinguishes "missing project context" from "project has no segments yet".
- **why it matters**: A welder following the empty-state coaching ("open ISO and add pipes") will add segments to whichever project they last had open, then come back and still see empty — because this screen never resolved to their project. Wrong-project data corruption on the shop floor.
- **suggested fix**: After the recovery branch, if pid still empty show a one-shot SnackBar `tr(pl:'Nie można ustalić projektu BOM. Wróć do listy projektów.', en:'Cannot resolve BOM project. Go back to project list.')` with action "Wstecz" that pops the route.
- **effort**: S

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:64-70 (_fmtLen)
- **issue**: Non-finite total length silently renders as `— m` with no operator feedback. The welder gets no hint that an upstream segment has bad data (NaN propagated from a divide-by-zero on radius=0 or similar) — a SnackBar/banner would alert them that "X rows have invalid lengths — review ISO".
- **why it matters**: Silently hiding `NaN m` means a real cutting list goes to the saw under-by-an-unknown-amount; the bug never surfaces until the pipe is delivered short.
- **suggested fix**: Track a `_hasNonFiniteRows` flag while iterating `_items`; if true, show one persistent SnackBar (or MaterialBanner) `tr(pl:'Niektóre długości są nieprawidłowe — sprawdź segmenty', en:'Some lengths are invalid — check segments')` on first build.
- **effort**: M

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:134-154 (ListView.separated rows)
- **issue**: Rows are pure `ListTile` with no `onTap`, no `onLongPress`, no copy-to-clipboard. There's no SnackBar feedback because there's nothing to confirm — but the BOM is the document a welder reads aloud to the storeman ("DN50 RURA 12.500 m"). Long-press copy + SnackBar `tr(pl:'Skopiowano do schowka', en:'Copied to clipboard')` is shop-floor standard pattern used elsewhere in this app (clipboard_helper.dart per MEMORY.md).
- **why it matters**: Welders frequently text/WhatsApp the BOM row to the warehouse. Without copy, they retype on a 5" screen with gloves — error-prone.
- **suggested fix**: Wrap each ListTile in InkWell long-press → `ClipboardHelper.copyWithToast(context, '$catLabel ${it.description} ${qty/length}')` which already shows a SnackBar.
- **effort**: S

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:73-78 (AppBar actions)
- **issue**: No "share/export BOM" action and consequently no success/failure SnackBar for export. Sibling screens (per other iterations) carry PDF/CSV export with SnackBar feedback; this BOM screen is the natural destination for "send to procurement" and currently provides no operator feedback for that flow because the flow itself is missing.
- **why it matters**: BOM is the artifact that triggers material ordering — being unable to share it from the screen forces screenshot-and-crop on a gloved hand.
- **suggested fix**: Add IconButton(Icons.share) → CSV/PDF export, on completion `ScaffoldMessenger.showSnackBar(tr(pl:'Lista wysłana', en:'BOM shared'))` with action "Otwórz" linking to the file. (Scope creep beyond pure snackbar lens — note as adjacent.)
- **effort**: L

- **severity**: low
- **location**: lib/screens/material_list_screen.dart:38-62 (_load)
- **issue**: After a successful refresh there is no subtle confirmation SnackBar (e.g. when user pulled-to-refresh — which itself is missing). Even on the first cold load, knowing "BOM built from 12 segments" would orient a fitter who just edited the ISO; right now load completion is invisible except for the spinner dismissing.
- **why it matters**: Trust calibration — a silent rebuild after an ISO edit leaves the welder unsure whether the list reflects their latest segment or a stale snapshot.
- **suggested fix**: On non-initial reloads, show short SnackBar `tr(pl:'Zaktualizowano BOM (${_items.length} pozycji)', en:'BOM updated (${_items.length} items)')` with 2s duration.
- **effort**: S

--- end block ---

## Iter #40 · lib/screens/quick_converter_screen.dart · help-tooltips
- **severity**: med
- **location**: quick_converter_screen.dart:26-38
- **issue**: AppBar has no info/help action (no IconButton with `?` or `i` icon explaining what the converter does, decimal separator rules, copy-on-long-press behavior). First-time users must discover behavior by trial and error.
- **why it matters**: Welder on shop floor opening tool with greasy hands wants instant clarity — a quick help bottom-sheet/tooltip explaining "comma or dot OK, long-press to copy, switch source unit on the right" prevents bounce.
- **suggested fix**: Add `AppBar.actions` `IconButton(Icons.help_outline)` opening a bottom-sheet with bilingual usage tips covering all 4 tabs.
- **effort**: M

- **severity**: med
- **location**: quick_converter_screen.dart:171-182, 259-275, 350-360, 433-443
- **issue**: All four `TextField`s lack `Tooltip` wrap, lack `helperText`, and have no example hint (`hintText`). Empty field shows only label "Wartość/Value" — no example like "12,5" indicating decimals/comma support.
- **why it matters**: Polish users type comma, English/imported PWPS uses dot. Without `hintText: '12,5 / 12.5'` or helper, users hesitate or type invalid chars (which formatter then silently swallows — confusing).
- **suggested fix**: Add `hintText: '12,5'` and `helperText: context.tr(pl: 'Kropka lub przecinek', en: 'Dot or comma')` to each TextField's InputDecoration.
- **effort**: S

- **severity**: med
- **location**: quick_converter_screen.dart:185-194, 277-288, 362-369, 445-452
- **issue**: Source-unit `DropdownButtonFormField`s have no `Tooltip`, no label ("Source unit" / "Jednostka źródłowa"), and no semanticLabel. A novice may not understand they pick *what they're typing*, not the target unit.
- **why it matters**: A misread leads to wrong unit interpretation — psi treated as bar is a 14× error on hydrotest, dangerous in pipe work.
- **suggested fix**: Wrap each Dropdown in `Tooltip(message: context.tr(pl: 'Jednostka, w której wpisujesz wartość', en: 'Unit you are typing in'))` and add `decoration: InputDecoration(labelText: ...)`.
- **effort**: S

- **severity**: med
- **location**: quick_converter_screen.dart:200-207, 294-299, 375-382, 458-464
- **issue**: Result `_Row`s have no per-unit tooltip explaining context (e.g. tap "in" to learn it's decimal inch not fractional like 1/4"). The single `_SmallHint` at bottom of each card is informative but doesn't bind to specific units.
- **why it matters**: Inch in pipe work is normally fractional (1¼", 1½"). Decimal-inch result (1.250) without tooltip "= 1 1/4 cala" risks misreading; same with cfh vs scfh confusion.
- **suggested fix**: Wrap each `_Row` in `Tooltip` (or extend `_Row` to take `tooltip` param) with unit definition; e.g. for `in` tooltip: 'Cale dziesiętne — 1.25" = 1 1/4"'.
- **effort**: M

- **severity**: med
- **location**: quick_converter_screen.dart:18 (class doc) and 114-124 (`_SmallHint` widget)
- **issue**: `_SmallHint` rendered at 11px italic muted gray (`_kMuted = 0xFF55607A` on `_kCard = 0xFF1A1D26`) is hard to read in workshop lighting (low contrast ratio ~3.8:1, fails WCAG AA for small text). Critical guidance like "Argon/M21 12-18 l/min" essentially invisible.
- **why it matters**: Welder squinting at phone under welding hood needs visible reference values. Muted italic hint = ignored hint.
- **suggested fix**: Bump to 12-13px, color `_kSec` instead of `_kMuted`, remove italic; or render as `InfoBanner`/`Tooltip` icon next to title row.
- **effort**: S

- **severity**: low
- **location**: quick_converter_screen.dart:204 (`in (")` row)
- **issue**: Label `in (")` shows `"` as quote — that's a hint at fractional inches but unexplained. No tooltip clarifies decimal vs fractional inch, and no fractional conversion is provided (common request: "1.375 in = 1 3/8\"").
- **why it matters**: Pipe fitters spec sizes in fractional inches (½", ¾", 1¼"). Showing only 1.250 without 1¼" forces mental math.
- **suggested fix**: Add small subscript with fractional approximation (nearest 1/16") or tooltip "1.250 ≈ 1 1/4\"".
- **effort**: M

- **severity**: low
- **location**: quick_converter_screen.dart:266-273 (Kelvin error)
- **issue**: `errorText` for `K < 0` is shown only inline; no tooltip/info icon explaining *why* (absolute zero). For users who never heard of Kelvin in physics-class context, "K nie może być ujemna" without "(zero absolutne)" expansion may confuse — fix is present but no follow-up tooltip.
- **why it matters**: Less critical (PWPS preheat almost never in K), but discoverability of *why* the input is rejected matters for user trust.
- **suggested fix**: Already present — copy is fine; consider adding info `?` icon next to dropdown when `K` selected linking to short explainer sheet.
- **effort**: S

- **severity**: low
- **location**: quick_converter_screen.dart:81-90 (`CopyOnLongPress` wrap)
- **issue**: Long-press-to-copy behavior is announced only via `_SmallHint` at card bottom. No visual affordance on the value itself (no copy icon, no underline-on-hover, no haptic on press-start). First-time user has no idea the value is copyable.
- **why it matters**: Welder will type/transcribe value manually if affordance hidden, defeating purpose of converter.
- **suggested fix**: Add small `Icons.copy` (12px, `_kMuted`) after each value, or wrap value in `Tooltip(message: context.tr(pl: 'Przytrzymaj aby skopiować', en: 'Long-press to copy'))`.
- **effort**: S

- **severity**: low
- **location**: quick_converter_screen.dart:29-37 (TabBar)
- **issue**: TabBar labels are bare text without leading icons (no thermometer icon for Temperature, no gauge for Pressure, no wind for Gas flow). No tooltip on tabs either.
- **why it matters**: Mid-glance from welding position, icons are faster to scan than Polish/English text labels. Especially "Przepływ gazu" (12 chars) competes with other tabs in scrollable bar.
- **suggested fix**: Use `Tab(icon: Icon(...), text: ...)` with `Icons.straighten`, `Icons.thermostat`, `Icons.compress`, `Icons.air` respectively; add `Tooltip` via `Semantics.tooltip`.
- **effort**: S

- **severity**: low
- **location**: quick_converter_screen.dart:402-407 (`_toLpm`)
- **issue**: `l/min == slpm` comment is in code only; UI shows two identical rows (l/min and slpm both displaying same value) with no tooltip explaining "slpm = standard l/min @ 0°C/1 atm, same as rotameter reading on site". Looks like a bug to user.
- **why it matters**: User sees duplicate "12.0" rows and may distrust the converter; same for cfh/scfh.
- **suggested fix**: Add `Tooltip` on slpm/scfh rows with one-liner explaining "Identyczne z l/min przy warunkach normalnych — rotametry tak są kalibrowane" and consider collapsing into a single row with both labels.
- **effort**: S

--- end block ---

## Iter #41 · lib/screens/heat_input_screen.dart · asme-iso-fidelity

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:140-150 + 161 (preheat thickness consumption)
- **issue**: `_preheatRecommendation(ce, thickness)` is called with `thickness = _parse(_thicknessCtrl)` (line 160-161), but the `_PreheatRec` returned for CE in 0.35-0.45, 0.45-0.55, >0.55 ranges ignores the thickness argument entirely. Function signature takes thickness but logic only uses it inside the `ce < 0.35` branch. AWS D1.1 Annex H and ASME B31.3 Table 330.1.1 require preheat to scale with thickness across ALL CE bands (e.g., A516-70 at 25 mm needs 80 °C; at 50 mm needs 120 °C; same CE).
- **why it matters**: Fabricator with two pipes — DN50 sched 40 (5 mm) and DN200 sched XXS (45 mm) — same A106 B chemistry gets identical preheat advice, leading to underheat on the heavy pipe and HAZ hydrogen cracking 24-72 h post-weld (delayed cracking on radiograph).
- **suggested fix**: Implement BS EN 1011-2 Method B combined-thickness lookup; minimally apply a linear bias on `tempC` for `t > 25 mm` (e.g., add 25 °C per 10 mm above 25 mm cap at 300 °C).
- **effort**: M

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:140-150 (preheat branches by CE only)
- **issue**: Preheat logic uses neither hydrogen scale (H1/H2/H3/H4 per EN 1011-2) nor consumable type. Same CE 0.48 with H4 low-hydrogen rod (E7018-1 H4R) needs ~75 °C; with H10 rutile (E6013) at same CE needs ~175 °C. App returns 175 °C regardless. Welder using fresh-baked vacuum-pack low-H electrodes is told to burn propane he does not need.
- **why it matters**: At a pipe shop with E7018-1 H4R (standard for pressure work) the welder loses 30-60 min preheat time per joint. Multiply by 20 joints/day across 5 fitters — entire shift lost to over-conservative app advice.
- **suggested fix**: Add a `HydrogenScale` chip selector (H4, H5, H10, H15) defaulting to H10 for SMAW and H4 for GMAW/FCAW with low-H wire; reduce `tempC` by ~25-50 °C when H4 selected.
- **effort**: M

- **severity**: high
- **location**: lib/screens/heat_input_screen.dart:120-127 (heat input formula — no pulsed-current handling)
- **issue**: HI calculation uses RMS-equivalent (V × I × 60 / s) which is correct for steady DC SMAW/SAW/conventional GMAW, but invalid for pulsed-GMAW and pulsed-GTAW where peak current >> mean current and inverter sets report two distinct values (Ip + Ib + duty). ISO/IEC 1011-1 §6 and AWS D1.1 C-6.5 require either the inverter-displayed kJ value or a duty-weighted average I_eff = √(Ip² × duty + Ib² × (1-duty)). Process selector lists 'GMAW' / 'GTAW' but does not distinguish pulse modes.
- **why it matters**: A welder running pulsed-MIG on duplex 2205 at displayed I_avg 110 A but I_peak 280 A / duty 35% has true I_eff ~ 175 A — actual HI is ~60% higher than the app shows. They run hotter, exceed the 2.5 kJ/mm σ-phase ceiling, weld fails ASTM A923 method B at QC.
- **suggested fix**: Add a "Pulsed" toggle next to GMAW/GTAW that exposes Ipeak/Ibase/duty fields, computes I_eff with the RMS formula, or simply allows direct entry of the inverter's displayed kJ value.
- **effort**: L

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:140-150 + reference table 678-682
- **issue**: No interpass temperature check or display. ISO 15614-1 §6.4 and ASME IX QW-406.1 treat interpass as a separate essential variable; for P91 a 250-300 °C interpass ceiling is mandatory (any colder = no martensite tempering; any hotter = δ-ferrite formation). `MaterialCatalog` stores "interpass <175 °C" in the preheat note for SS but the screen does not surface it as a distinct field next to preheat.
- **why it matters**: P91 welder at 350 °C interpass (forgot to wait) produces δ-ferrite, weld fails creep at first hydrotest. The catalog has the data but the UI does not present it as actionable.
- **suggested fix**: Parse `preheatNote` into preheat + interpass components, render two separate metric cards ("Preheat min" / "Interpass max"); add interpass to clipboard payload.
- **effort**: M

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:89-95 (efficiency map) + 124 (lookup)
- **issue**: Efficiency map keys hard-code single process tags, but ASME IX QW-409.1 / ISO/TR 17671-1 differentiate η for tubular-cored vs metal-cored FCAW (FCAW-G with M21 vs FCAW-S self-shielded) — typically 0.80 vs 0.75. Single 'FCAW' bucket forces both to 0.80 and overstates self-shielded HI by ~6%.
- **why it matters**: Site fitter on structural D1.1 work using Innershield NR-232 (FCAW-S) believes they hit HI 2.0 kJ/mm; true value is 1.88. WPS lower bound at 1.5 still met so safety stays, but range margins blur and an inspector pulling out the η value will flag the mismatch.
- **suggested fix**: Split 'FCAW' into 'FCAW-G' (0.80) and 'FCAW-S' (0.75); update process selector + dialog text.
- **effort**: S

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:97-98 (`_parse` accepts any double, silently zeroes)
- **issue**: `_parse` returns 0.0 for invalid OR negative input. A welder typing "-110" for amps yields HI=0 silently (line 125 guards `if (i <= 0) return 0`); same for travel speed "0". The result card shows 0.000 kJ/mm and "OUT of range" without explaining that the input itself is sign- or zero-invalid.
- **why it matters**: Junior welder typing 0 by accident on travel-speed sees a 0.000 kJ/mm warning and panics, thinking the WPS rejects them, when they just need a positive number.
- **suggested fix**: Surface validation messages inline: "Travel speed must be > 0", "Current must be > 0", rather than producing 0 silently.
- **effort**: S

- **severity**: med
- **location**: lib/screens/heat_input_screen.dart:74-87 (`_applyMaterial` overwrites WPS range)
- **issue**: When the user selects a material preset, `_wpsMinCtrl` / `_wpsMaxCtrl` are overwritten with catalog defaults (lines 84-85), but AWS D1.1 Annex H / ASME IX QW-409.1 HI windows are procedure-specific — the catalog's hiMin/hiMax are TYPICAL, not normative. If the welder has a real WPS in front of them showing 1.2-2.0 for A106 B, picking the chip silently clobbers the entered range with 1.0-2.5.
- **why it matters**: Welder switches between materials to compare, comes back to A106 B, finds their hand-entered shop WPS range gone — annoying at best; at worst they validate against the wrong range without noticing.
- **suggested fix**: Only auto-fill `hiMin`/`hiMax` when both fields are empty or still at catalog defaults; or show a confirmation snackbar "WPS range overwritten — undo?".
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:367-372 (Polish/English string with raw double interpolation)
- **issue**: `wpsMin` / `wpsMax` are doubles and interpolated raw (e.g., "1.0 - 2.5"). If the welder enters "1.50" the number reads "1.5" (Dart double formatting); "1.25" reads "1.25". Inconsistent precision within the same message. ISO 15614-1 convention is one decimal place for kJ/mm.
- **why it matters**: Inspector reads inconsistent numbers and questions data quality.
- **suggested fix**: Format `wpsMin.toStringAsFixed(1)` / `wpsMax.toStringAsFixed(1)` in the message strings.
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:343-351 (HI displayed as `toStringAsFixed(3)`)
- **issue**: HI reported to 3 decimal places (e.g., 1.452 kJ/mm). ASME IX QW-409.1 and ISO 15614-1 record HI to 1-2 decimal places; 3 decimals implies precision that the V/I/travel inputs do not support (V ±0.5 V, I ±5 A → HI ±5%). Fake precision misleads the welder about confidence in the number.
- **why it matters**: Senior welder sees "1.452" and either smirks at the fake precision or treats it as a meaningful figure when adjusting parameters by tiny increments.
- **suggested fix**: Display `hi.toStringAsFixed(2)`.
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:31-39 + 309 + 779 (color palette reuse)
- **issue**: Red `_kAccent` (0xFFEF5350) is used both for "out of WPS range" (line 309) and for "critical CE >0.55" (line 779). Same visual cue for two unrelated severity meanings dilutes the safety-color semantics that workshop floors rely on.
- **why it matters**: Under fluorescent shop lighting, red reads as "stop, fault" — the same red appearing on out-of-range HI vs critical preheat creates pattern fatigue and welders start ignoring the warning.
- **suggested fix**: Use distinct colors for "process out of bounds" (red/accent) vs "material critical" (deep orange/dark red); align with ISO 3864 safety colors for full normative alignment.
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:50-67 (initial values, no persistence)
- **issue**: Default V/I/travel/chemistry inputs reset on every navigation away from the screen — controllers are recreated. ASME IX QW-409.1 record-keeping requires the last calculation be referenceable for the day's WPQR. Screen state is throwaway.
- **why it matters**: Welder leaves the screen to check tungsten size, comes back, all 8 chemistry fields are blanked back to defaults. They retype, possibly with errors.
- **suggested fix**: Persist last values via SharedPreferences or the job-log service used elsewhere in the app; restore on screen mount.
- **effort**: M

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:63 (`_thicknessCtrl` default '15')
- **issue**: Thickness default is 15 mm but the unit is not labelled near the default — only the `_NumField` suffix shows "mm". For a US site fitter the default "15" with no immediate unit cue is a 2-second question every visit. The CE reference table mixes mm and inch ("25 mm (~1\")"); the thickness input does not.
- **why it matters**: Mixed unit cues across the same screen → mental friction; shop-floor wrong-unit entries (15 inch != 15 mm).
- **suggested fix**: Mirror dual-unit notation in the thickness label: "Grubość [mm / in]"; or accept both.
- **effort**: S

- **severity**: low
- **location**: lib/screens/heat_input_screen.dart:691-695 (P91/P22 footnote) vs material_catalog.dart:109 (P91 PWHT note)
- **issue**: P91 PWHT range listed as "730-760 °C" in the screen footnote, but the MaterialCatalog at material_catalog.dart:109 says "PWHT 750–770 °C / 1 h-cal". Two different ranges for the same procedure, in two files. ASME B31.3 Table 331.1.1 calls 740-775 °C for P5B; EPRI guideline narrows to 750-770. The discrepancy makes either source untrustworthy.
- **why it matters**: Welder cross-checks the two screens, finds different numbers, picks one — may be wrong for the inspector's reference standard.
- **suggested fix**: Consolidate the P91 PWHT range to a single source-of-truth string ("PWHT 750-770 °C per ASME B31.3 Table 331.1.1, 1 h/inch min 1 h"); reference it from both UI and catalog.
- **effort**: S

--- end block ---

## Iter #42 · lib/screens/tungsten_screen.dart · weld-traceability

- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:36 + lib/data/tungsten.dart:90-97 (sizeForCurrent fallback path)
- **issue**: When amps fall below the lowest band (e.g. 10 A) or above the highest (e.g. 450 A), sizeForCurrent silently returns the boundary electrode (Ø 1.0 or Ø 3.2) with no UI signal that the returned pick is a fallback. The orange tick row looks identical to a legitimate in-band hit. A welder glancing at the highlighted row sees "10 A -> Ø 1.0 mm WL20" with the same visual confidence — no asterisk, no shading change.
- **why it matters**: A traceability log later contains the fallback pick indistinguishable from a true match. Auditors and the welder themselves cannot reconstruct whether 10 A was deliberate (micro-TIG instrument tubing) or a typo. ISO 3834-2 requires recorded electrical parameters to be linkable to a qualified WPS range.
- **suggested fix**: Compute outOfBand = a < firstMin || a > lastMax in build(), and when true render the highlighted row with an amber striped border + "POZA ZAKRESEM / OUT-OF-BAND" caption instead of the tick — and disable any future save action while flag is set.
- **effort**: S

- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:34-59 (input wiring) + state model
- **issue**: There is no captured operator-note on why a non-standard current was chosen. The screen is a pure stateless calculator: input -> highlight. Nothing in state allows the welder to record context (root pass thin wall, codex tube end, etc.) at the moment of the decision. The decision evaporates the instant they navigate away.
- **why it matters**: For pharma tubing and food-grade stainless, the reason behind the parameter choice is part of the joint record (EN ISO 15614-1). A bare amps number with no rationale is half a trace entry. Welders typing a note on a sweaty phone in a workshop need a single field, not a 5-step form.
- **suggested fix**: Add a 1-line Notatka / Note TextField under the amps input (maxLength ~60) bound to a state field. Persist alongside amps/jointId in the trace entry produced by Iter #17 save action.
- **effort**: S

- **severity**: high
- **location**: lib/screens/tungsten_screen.dart:73-109 (size rows) + lib/data/tungsten.dart:22-27 (band data)
- **issue**: The size rows show ONLY the current band (e.g. 70-150 A) with no indication of the gas flow rate or cup size required for that diameter. Tungsten diameter, gas cup (#5/#6/#7/#8) and Ar flow (L/min) are coupled — picking Ø 2.4 mm with a #5 cup at 5 L/min is a defect waiting to happen, but the app does not surface this.
- **why it matters**: A trace entry "I=180 A, Ø=2.4 mm, WL20" without cup/gas is technically incomplete for stainless orbital work — backing gas requirements feed off cup choice. The welder cannot reproduce the weld parameters on the next joint without remembering the cup they happened to use.
- **suggested fix**: Extend TungstenSize with recommendedCup (e.g. #6-#7) and argonFlow (8-10 L/min); render as a small secondary row inside each size card. Carry these into any future trace export.
- **effort**: M

- **severity**: med
- **location**: lib/data/tungsten.dart:22-27 (current bands)
- **issue**: The bands overlap at boundaries (Ø 1.0 ends 80 A; Ø 1.6 starts 70 A — overlap 70-80 A; Ø 1.6 ends 150 A; Ø 2.4 starts 150 A — overlap at single point). sizeForCurrent returns the FIRST matching band in iteration order, so at 75 A the user always gets Ø 1.0 even though Ø 1.6 is technically also valid. Trace records will systematically bias toward the smaller diameter at every overlap.
- **why it matters**: Same physical job welded by two different fitters using the same calculator at 75 A produces Ø 1.0 in one log and Ø 1.6 in the other if a fitter manually overrode. The data the company aggregates from trace becomes inconsistent without anyone realising the calculator has a hidden tie-break behaviour.
- **suggested fix**: Either (a) return ALL matching bands and let the UI present them as co-equal (welder picks + logs the choice), or (b) document the tie-break rule prominently in the UI (Przy nakładających się prądach wybieramy mniejszą średnicę / Smaller diameter wins on overlap).
- **effort**: M

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:73-109 (size cards) + lib/data/tungsten.dart:8-19 (TungstenSize model)
- **issue**: No record of the electrode tip geometry the picked diameter is rated for in the displayed band. Grind angle hint exists in a separate static panel at lines 113-140, but it is not bound to the specific picked size — yet thinner electrodes (Ø 1.0) physically cannot hold a 60° blunt tip on a sane current, and Ø 3.2 mm at 20° will overheat instantly. The user-visible link "this band assumes this tip geometry" is missing.
- **why it matters**: An audited trace entry showing "Ø 1.0 mm at 75 A, 60° tip" is mechanically inconsistent (the tip would melt) — QC reviewing trace data cannot flag it as an obvious typo without knowing the manufacturer-rated tip range per diameter.
- **suggested fix**: Add a tipAngleRange to TungstenSize (e.g. 20-30° for Ø 1.0; 30-45° for Ø 1.6; etc.) and surface it as a sub-line in the card. Tie the grind-angle chooser proposed in Iter #17 to a per-size constrained dropdown rather than free choice.
- **effort**: M

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:33-37 (no semantic announcement of pick change)
- **issue**: When the amps value changes and the pick row swaps, no SemanticsService.announce or live region fires. Screen-reader users (and the rare welder using TalkBack with hearing-impaired access) get no notification that the picked electrode just changed from Ø 1.6 to Ø 2.4 at 150 A. They might log the wrong diameter because they were still on the old row.
- **why it matters**: Traceability is only as accurate as what the user perceives — a silent UI change at the boundary creates exactly the conditions where the wrong electrode gets recorded in the joint log.
- **suggested fix**: After setState(() {}) inside the onChanged callback, if pick.diaMm changed from the previous value, call SemanticsService.announce with localized string e.g. "Pick: Ø 1.6 mm, WL20".
- **effort**: S

- **severity**: med
- **location**: lib/screens/tungsten_screen.dart:171-242 (electrode type list - hardcoded ordering)
- **issue**: The type list is rendered in the catalogue order from kTungstenTypes (WL20, WL15, WC20, WT20, WP). For a stainless DC- workflow this is fine, but the order is not driven by the currently entered current. WC20 is best at low current (<60 A, instrument tubing), WL20 at mid, WT20 holds up better at higher loads — yet the screen presents the catalogue identically at 15 A and 250 A. The welder is left to pick by reading every note.
- **why it matters**: A welder at 30 A who skims the first row (WL20) and uses it loses a measurable arc-start advantage that WC20 would give, then the trace records WL20 — masking the fact that the calculator nudged them to a sub-optimal electrode at that current. The bestForSs badge is binary and current-agnostic.
- **suggested fix**: Surface a contextual "Najlepszy dla tego prądu / Best for this current" sub-badge that promotes the type whose strength matches the input amps (WC20 at <60 A, WL20 at 60-200, WL15/WT20 above 200). Keep the static list but flag dynamically.
- **effort**: M

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:35 (parsing) + lib/data/tungsten.dart:90 (sizeForCurrent)
- **issue**: Iter #17 already flagged the missing out-of-band warning chip — keeping this as a duplicate-guard note. The clamp inside sizeForCurrent still hides the boundary semantics from the UI, and any saved trace entry will lose the out-of-WPS-envelope flag unless both data layer and screen layer are touched together.
- **why it matters**: Same as Iter #17 — auditor cannot tell typo from override. Listed here to keep the data+UI coupling visible.
- **suggested fix**: Make sizeForCurrent return a small struct {size, outOfBand: bool} rather than just size, so the screen never has to re-derive the flag.
- **effort**: S

- **severity**: low
- **location**: lib/screens/tungsten_screen.dart:24 (no controller initial value restore)
- **issue**: Duplicate of Iter #17 amps-input-is-volatile finding — still true, no shared-prefs restore. Restating because it directly affects the recoverability of the last unsaved trace candidate.
- **why it matters**: Same as Iter #17.
- **suggested fix**: As per Iter #17 — persist last amps in shared prefs, restore in initState.
- **effort**: S

--- end block ---

## Iter #43 · lib/screens/premium_screen.dart · cut-list-clarity

- **severity**: high
- **location**: lib/screens/premium_screen.dart:434-446 (yearly _PlanCard "149 PLN /rok")
- **issue**: Yearly plan shows "149 PLN /rok" but no per-month equivalent (149/12 = 12.42 PLN/mc) shown alongside. The "OSZCZEDZASZ 35%" badge tells percentage but a fitter doing mental math on a workshop floor needs the apples-to-apples monthly number to compare against the 19 PLN monthly card next to it.
- **why it matters**: Workshop floor decision is "which is cheaper per month?" — without the 12.42 PLN/mc the user has to divide in their head while holding a phone in greasy gloves. Most don't bother and pick the cheaper-LOOKING 19 PLN monthly, costing the app lifetime revenue and conversion to the better-margin yearly plan.
- **suggested fix**: Below the "149 PLN /rok" price, add a small grey line "ok. 12 PLN/mc" or "12,42 zl/mc" — instant visual comparison with the 19 PLN monthly card.
- **effort**: S

- **severity**: high
- **location**: lib/screens/premium_screen.dart:322-323, 357-363 (AI feature blurbs)
- **issue**: Both AI promos boast "baza 270 KB wiedzy" / "270 KB knowledge base". "270 KB" is engineer-speak (kilobytes of source text); a fitter has no mental model for KB-of-text. It either reads as tiny (270 KB = a small image) or meaningless. Should be in human units: "1500 standardow branzowych" / "kompendium 80 stron normy" / "10 lat doswiadczenia welder-inspectora".
- **why it matters**: Premium pitch hinges on "the AI knows real standards" — saying "270 KB" undersells that. Workshop user doesn't think in bytes; they think in pages, standards, years of experience.
- **suggested fix**: Replace "baza 270 KB wiedzy" -> "kompendium 30+ norm (ASME, EN, AWS, NACE)" or "wiedza z 1500 stron standardow". Quantify what they ACTUALLY get.
- **effort**: S

- **severity**: high
- **location**: lib/screens/premium_screen.dart:355-418 (entire feature tile list, no Free vs Premium comparison)
- **issue**: The screen lists 7 Premium features but never shows what FREE users already have. No comparison table, no "vs Free" markers, no strikethrough of free-tier limits. A user pulled to Premium from a feature gate has zero context for the upgrade delta.
- **why it matters**: Workshop fitter scanning "Co dostajesz" can't tell which features are NEW vs which they already use freely. "Cloud sync" — do I not have that now? "Bez reklam" — implies I currently have ads, OK. But "Bolt torque chart" / "Coping templates" — am I already using simpler versions? Clarity demands the delta.
- **suggested fix**: Add a 2-column "Free | Premium" mini-table above feature tiles, OR add a green check "NOWE" pill on tiles that are exclusively Premium. Workshop users need the upgrade-delta visible at a glance.
- **effort**: M

- **severity**: high
- **location**: lib/screens/premium_screen.dart:380-383 (bolt torque feature body "B7/B7M/B16/B8M")
- **issue**: Bolt-grade abbreviations "B7/B7M/B16/B8M" listed without spelling out what they are (ASTM A193 grades). Same row mentions "Flange + klasa" (klasa what — ASME 150/300?). A fitter who works with carbon-steel pipe daily may know B7 but a younger journeyman or pipefitter from a different sector (HVAC) will not. The blurb gates comprehension to senior welders.
- **why it matters**: Premium pricing screen must sell breadth, not gate it. If the feature description reads like a WPS spec sheet, less-credentialed users scroll past convinced this is "not for me".
- **suggested fix**: Soften: "B7, B7M, B16, B8M (sruby ASME A193)" — adds the catalog name. Also rewrite "Flange + klasa + gatunek srub" -> "Kolnierz + klasa cisnieniowa + gatunek srub".
- **effort**: S

- **severity**: high
- **location**: lib/screens/premium_screen.dart:369-373 (Coping templates body) — language mix
- **issue**: PL body: "Generuj szablony do owiniecia na rurze przed cieciem fish-mouth. Druk 1:1 dla dowolnej kombinacji DN/kat." mixes PL with English "fish-mouth" and abbreviation "DN" without explanation. PL fitters call this "pyszczek rybi" or simply "wyciecie", and DN is fine but mixing reads sloppy.
- **why it matters**: Premium copy that mixes languages reads as auto-translated; degrades trust in the very feature you are charging for. Workshop floor language is colloquial-PL, not engineering-EN.
- **suggested fix**: PL: "Generuj szablony do owiniecia rury przed wycieciem rybiego pyszczka (fish-mouth). Druk 1:1 dla dowolnej srednicy nominalnej (DN) i kata odgalezienia." — explains FOR a Polish workshop reader.
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:439-441 (badge text "OSZCZEDZASZ 35% . POPULARNE")
- **issue**: Badge merges two distinct claims with " . " separator: a savings claim (35%) and a social-proof claim (popular). Visually this reads as a single noisy phrase rather than two independent endorsements. Also "POPULARNE" without numbers is empty social proof ("popular according to whom?").
- **why it matters**: Workshop user scanning quickly sees a long string and ignores it. Two compact, separate badges would each register. Empty "popular" claim from an unknown app is suspicious.
- **suggested fix**: Split into two pills stacked: green "-35%" and (only if real) blue "78% wybiera ten plan" with real data. Or drop POPULARNE entirely until you have data.
- **effort**: M

- **severity**: med
- **location**: lib/screens/premium_screen.dart:333-343 (sample prompt teaser fontSize 11 + italic + gold color)
- **issue**: Sample prompt 'Sprobuj tego: "Preheat dla P91 grubosc 25 mm?"' rendered at fontSize 11, italic, in _kGold (0xFFE8C14B) on dark background. Italic+gold+11px is the worst-case readability combo for an older welder (avg 40-55 y/o on Polish workshop floors) under fluorescent light.
- **why it matters**: Workshop floor demographic skews >40 y/o with mild presbyopia. 11px italic on a low-contrast gold-on-dark is hard to read with hardhat-mounted safety glasses. The ONE concrete example they need to "get" the AI value prop becomes the hardest text on the page to parse.
- **suggested fix**: Bump to fontSize 12-13, remove italic (keep quotation marks for "example" cue), use lighter gold (0xFFF5D87A) or off-white for contrast.
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:227-241 (AppBar ShaderMask gradient on "PREMIUM" title)
- **issue**: AppBar title "PREMIUM" rendered with ShaderMask gradient orange->gold over bold w900 letter-spacing 2. On phone screens in bright outdoor light (workshop yard, scaffolding) the gradient reduces effective contrast vs the dark background — a flat solid color reads better in harsh light.
- **why it matters**: AppBar title is the screen identity anchor; users navigating back-and-forth from gates need instant recognition. A fancy gradient that loses contrast in sun = wasted designer move.
- **suggested fix**: Either replace gradient with solid _kGold for legibility (gradient still works on Hero card below), OR keep gradient but increase font weight black + add subtle text shadow for outdoor legibility.
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:397-401 ("1 darmowe ogloszenie/mc w Pracy")
- **issue**: PL title says "1 darmowe ogloszenie/mc w Pracy" — "w Pracy" capitalised mid-sentence is confusing. Reader doesn't know if "Praca" is a module name in this app or a literal "at work". EN version "1 free job listing/mo" doesn't have this ambiguity but is also vague.
- **why it matters**: Workshop user reads "darmowe ogloszenie" -> "of what?" -> "w Pracy" -> "where?". A second of confusion on a value-prop tile during 30-second scan = skipped feature.
- **suggested fix**: PL: "1 darmowy post w module Praca / miesiac" — make it clear "Praca" is an app section. Or rename to "Tablica ogloszen: 1 post/mc gratis".
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:653-660 (Hero title "Fitter Welder Pro+")
- **issue**: Hero title uses "Fitter Welder Pro+" (with plus sign) — but the AppBar app title elsewhere reads "Fitter Welder Pro" (no plus). The "+" is the Premium suffix convention (like Apple Music+ / YouTube Premium+) but a workshop user not in Premium ecosystem may parse it as "Pro Plus" version of a different SKU. No tooltip or expansion of what "+" denotes.
- **why it matters**: Brand consistency — non-Premium user opens screen, sees a different product name, wonders if they are looking at the wrong app. Cut-list clarity demands product identity is stable across screens.
- **suggested fix**: Either rename to "Fitter Welder Pro PREMIUM" or add subtitle "(wersja Premium)". Make the "+" meaning explicit.
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:451-452 (Stripe footnote text contrast)
- **issue**: Footnote "Platnosc: Stripe (karta, BLIK, Apple Pay, Google Pay). Anuluj w kazdej chwili." is a single dense line at fontSize 11 _kTextMut (0xFF55607A = dark grey on dark bg). On the lowest-contrast color in the palette, the cancellation guarantee — a major trust signal — is functionally invisible.
- **why it matters**: "Anuluj w kazdej chwili" is the #1 friction-reducer for first-time SaaS subscribers. Hiding it in 11px dim grey wastes the trust signal. Workshop floor users want big visible "cancel anytime" assurance.
- **suggested fix**: Promote "Anuluj w kazdej chwili" to its own line at fontSize 13 lighter color (_kTextSec); demote payment method list to small print below.
- **effort**: S

- **severity**: med
- **location**: lib/screens/premium_screen.dart:451 (no trial mention)
- **issue**: Pricing screen has NO free-trial offer or money-back guarantee. SaaS conversion best practice for a workshop tool is "7 dni za darmo" or "30-day money back". Hard sell of 19 PLN/mc upfront for users who have not experienced AI Chat yet is a friction wall.
- **why it matters**: Polish workshop users are price-sensitive; B2B SaaS norms show 2-3x conversion with a trial. Without it, the Premium screen funnels purely impulse buyers.
- **suggested fix**: Add "Pierwsze 7 dni za darmo" badge on yearly plan (Stripe supports trial_period_days). At minimum, add a "30-dniowa gwarancja zwrotu" line in the footnote area.
- **effort**: M

- **severity**: low
- **location**: lib/screens/premium_screen.dart:451-452 (no faktura VAT mention) — duplicate guard
- **issue**: Already raised in Iter #18 (lines 1438-1443). Re-noting at low severity per dedup policy: the faktura VAT path is still not in copy as of this read.
- **why it matters**: Same as Iter #18 finding.
- **suggested fix**: See Iter #18.
- **effort**: S

- **severity**: low
- **location**: lib/screens/premium_screen.dart:498-504 (verification overlay sub-text "Stripe potwierdza zakup")
- **issue**: No progress signal on the verification overlay — just spinner + "give it a moment". With 15s budget (line 124) the user has no idea if they are at second 2 or second 14. No countdown, no dots animation, no "Proba 3/6".
- **why it matters**: Workshop floor user waiting on a stalled overlay assumes app is frozen, force-closes — then has to deal with the cold-start recovery code path (lines 82-105). Better to show progress.
- **suggested fix**: Add a thin LinearProgressIndicator at top of overlay tracking against _kVerifyBudget, OR rotate sub-text ("Sprawdzam... (2/8)", "Czekam na webhook...").
- **effort**: S

- **severity**: low
- **location**: lib/screens/premium_screen.dart:355-418 (no testimonials/social proof)
- **issue**: Zero social proof on Premium screen: no user count ("3000 spawaczy uzywa Pro+"), no testimonials, no app-store rating display, no logos of recognizable workshops/companies. Pure feature-list selling.
- **why it matters**: Workshop floor users distrust app subscriptions ("kolejna kasa miesiecznie"). Social proof from peers (another fitter, recognisable Polish welder influencer/YT channel) is the highest-converting trust signal for this demographic.
- **suggested fix**: Add a single quote card between feature tiles and plan cards: "[avatar] [name, role, company] - '[testimonial]'". Pull from real beta users once available; meanwhile use rating: "4.8 w App Store / Google Play (120 opinii)".
- **effort**: M

- **severity**: low
- **location**: lib/screens/premium_screen.dart:411-418 ("Bez reklam" body "Czyste UI bez bannerow i interstitial")
- **issue**: Mixed PL/EN: "bez bannerow i interstitial". "Interstitial" is English ad-tech term unfamiliar to a typical fitter. PL equivalent is "reklamy pelnoekranowe" or just "wyskakujace reklamy".
- **why it matters**: Mixed-language copy on a sales screen reads as low-effort or auto-translated. Premium positioning demands polished native-language copy.
- **suggested fix**: "Czyste UI bez bannerow i reklam pelnoekranowych."
- **effort**: S

- **severity**: low
- **location**: lib/screens/premium_screen.dart:632-675 (_Hero subtitle value-prop hierarchy)
- **issue**: Hero card has a single line of value prop "Pelen arsenal monterski + AI asystent w jednej apce" — that's the whole pitch above the fold. No hierarchy: no "Save X PLN/mc" big number, no "1 minute payback per shift" — just one undifferentiated line. Wasted prime real estate on a paywall.
- **why it matters**: First 3 seconds on Premium screen decide conversion. Hero must hit the strongest concrete benefit, not a vague "arsenal" metaphor.
- **suggested fix**: Replace subtitle with rotating concrete benefits: "Coping template w 30s zamiast 10 min recznie", "Preheat dla 50 stali w 2 sekundy", "AI odpowiada szybciej niz senior welder".
- **effort**: M

--- end block ---

## Iter #44 · lib/screens/ai_chat_screen.dart · glove-48dp
- **severity**: high
- **location**: lib/screens/ai_chat_screen.dart:332-356
- **issue**: Citation chips `📖 $c` have only 8x3 px padding and 10pt text — tap target ~22dp tall, way under 48dp minimum
- **why it matters**: A welder reading an AI answer on a dusty workshop floor with gloves cannot reliably tap a tiny citation pill to verify the source — they will mash the wrong chip or hit empty space
- **suggested fix**: Wrap in `Container(constraints: BoxConstraints(minHeight: 48))` and bump font to 12pt, padding to horizontal:12 vertical:10
- **effort**: S

- **severity**: high
- **location**: lib/screens/ai_chat_screen.dart:174-189
- **issue**: AppBar refresh `IconButton` clears chat WITHOUT confirmation
- **why it matters**: A gloved hand mis-tapping the refresh icon (top-right, near system back) instantly wipes a 5-minute conversation about preheat tables — that's lost work in the middle of a job
- **suggested fix**: Add a `showDialog` confirmation when `_messages.length > 1`, with 48dp-tall PL/EN actions
- **effort**: S

- **severity**: high
- **location**: lib/screens/ai_chat_screen.dart:586-590
- **issue**: Send `IconButton` uses default Material constraints (~40dp tap target) inside a circular container with no explicit minimum size
- **why it matters**: The send button is the most frequently tapped control in this screen — gloved welders need an unambiguous, oversized target; default IconButton sizing is borderline
- **suggested fix**: Wrap IconButton with `SizedBox(width: 56, height: 56)` or set `constraints: BoxConstraints(minWidth: 56, minHeight: 56)` and `iconSize: 28`
- **effort**: S

- **severity**: high
- **location**: lib/screens/ai_chat_screen.dart:506-509
- **issue**: Suggestion chip text uses 12pt font; while chip min-height was raised to 48dp, the visible label is still tiny under workshop lighting
- **why it matters**: Welder squinting at "Heat input dla SMAW 110A" through a face shield needs at least 14pt to scan quickly; tiny labels force re-reads and fumbled taps
- **suggested fix**: Bump `fontSize: 12` to `fontSize: 14` and `fontWeight: w600`
- **effort**: S

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:546-578
- **issue**: TextField uses 14pt input font with 13pt hint and 10dp vertical content padding — total field height ~40dp
- **why it matters**: Composer is constantly tapped; with gloves on, hitting the field reliably and seeing typed text mid-conversation requires a taller, more visible input
- **suggested fix**: Raise `contentPadding` vertical to 14, font to 16pt; bump hint to 14pt
- **effort**: S

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:318-325
- **issue**: Message body text is 14pt with `height: 1.5` — readable but at the lower bound; SelectableText also reduces tap-to-scroll area by enabling text selection on touch
- **why it matters**: A welder skimming a 200-word AI answer about ASME B31.3 needs 15-16pt minimum to read mid-task; current 14pt is hard with sweat-spattered safety glasses
- **suggested fix**: Bump message font to 15pt and add a long-press to copy alternative so single taps scroll cleanly
- **effort**: S

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:108-121
- **issue**: SnackBar Retry action has only 4-second duration
- **why it matters**: A welder who notices the failure but needs to put down a torch first will miss the 4-second window and have to retype the question
- **suggested fix**: Extend `duration: Duration(seconds: 8)` and ensure SnackBarAction respects ≥48dp tap height
- **effort**: S

- **severity**: med
- **location**: lib/screens/ai_chat_screen.dart:264-268
- **issue**: Citation dialog only has a single `TextButton` "OK" — default TextButton is ~36dp tall
- **why it matters**: Dismissing the dialog with gloves on requires a precise tap; under-sized button leads to mis-tap on backdrop or dialog body
- **suggested fix**: Replace with `FilledButton` styled to `minimumSize: Size(120, 48)`
- **effort**: S

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:485-486
- **issue**: SizedBox height of 64 for suggestion strip with chip minHeight 48 leaves only 16dp vertical margin total (8 top + 8 bottom)
- **why it matters**: Edge-adjacent chips at strip top/bottom are easy to miss with thick gloves where finger pad extends well beyond the visible chip
- **suggested fix**: Increase strip height to 72 and chip minHeight to 52 for safer hit zone
- **effort**: S

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:153-170
- **issue**: DEMO badge in AppBar uses 10pt font with 6x2 padding — purely informational but tiny
- **why it matters**: A welder needs to instantly know whether they're talking to live AI or a demo stub; 10pt is illegible at arm's length
- **suggested fix**: Raise font to 12pt and padding to 10x4; not strictly a tap target but visibility matters
- **effort**: S

- **severity**: low
- **location**: lib/screens/ai_chat_screen.dart:296-298,372-373
- **issue**: Avatar circles (32x32) with 18pt icons are pure decoration — not interactive
- **why it matters**: Visual scan only; flagging because someone might later expect to tap an avatar (e.g. "who said this?") and the current size would block that use case
- **suggested fix**: Document as decorative or bump to 40x40 if avatars become interactive
- **effort**: S

--- end block ---

## Iter #45 · lib/screens/chat_screen.dart · outdoor-visibility
- **severity**: high
- **location**: lib/screens/chat_screen.dart:75 (AppBar Icons.person_outline nickname action)
- **issue**: IconButton w AppBar dla edycji ksywki używa domyślnego rozmiaru ikony (~24dp) bez explicit iconSize i bez wyraźnego color — na _kCard ciemnym AppBarze, na słońcu, ikona „person_outline" zlewa się z tłem.
- **why it matters**: Edycja ksywki to jedyny widoczny CTA w listy pokoi — fitter musi go znaleźć od razu (np. żeby zmienić "anonim123" na "Krzysiek TIG" przed pierwszym postem); niewidoczny = nikt go nie znajdzie.
- **suggested fix**: iconSize: 28, color jaśniejszy (np. Color(0xFFE8ECF0) lub _kAccent dla afordancji akcji).
- **effort**: S

- **severity**: high
- **location**: lib/screens/chat_screen.dart:124-126 (_editNickname dialog hintText)
- **issue**: Dialog edycji ksywki — TextField nie definiuje style ani hintStyle, używa domyślnej Material — w trybie ciemnym dialog może być jasnym kontenerem z hintText szarym low-contrast.
- **why it matters**: Pierwsza interakcja użytkownika z czatem (ustawienie ksywki) musi być bezbłędna pod słońcem — niewidoczny placeholder = wpisuje ksywki bezsensownie, frustracja.
- **suggested fix**: style: TextStyle(fontSize: 17, color: Color(0xFFE8ECF0)), hintStyle: TextStyle(fontSize: 15, color: _kTextSec); rozważyć jawny dark dialogTheme.
- **effort**: S

- **severity**: high
- **location**: lib/screens/chat_screen.dart:565-568 (_MessageBubble border)
- **issue**: Granica bańki (_kBorder.withValues(alpha: 0.7)) jest bardzo cienka i ledwie widoczna; gdy wiadomość ma tło zbliżone do tła scaffold, brzeg dymka znika w słońcu.
- **why it matters**: Bez wyraźnej krawędzi wiadomości się zlewają — spawacz nie wie gdzie kończy się jedna a zaczyna druga, czyta jedną długą ścianę tekstu.
- **suggested fix**: alpha 1.0 + grubsze border (width: 1.2), lub dodać subtle shadow/elevation 1.
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:69, 487 (Scaffold backgroundColor 0xFF0F1117)
- **issue**: Tło scaffold to bardzo ciemny granat (#0F1117); pełen ciemny ekran na słońcu w warsztacie z wszystkimi refleksami i tłustymi palcami robi z czytania powolne wyzwanie — pełna ciemność maksymalizuje refleks na powłoce ekranu.
- **why it matters**: Refleks szyby/słońce na 100% jasności ekranu robi z czarnego tła lustro; dla fittera trzymającego telefon w warsztacie chat jest praktycznie nieczytelny.
- **suggested fix**: Rozważyć w trybie outdoor light theme z jasnym tłem dla czatu, lub dodać global Brightness toggle w AppBar (high-contrast / outdoor mode); minimum podnieść tło do #15192A dla zmniejszenia refleksu.
- **effort**: L

- **severity**: med
- **location**: lib/screens/chat_screen.dart:316 (Timer.periodic 8s poller)
- **issue**: Polling co 8 sekund + nie ma widocznego wskaźnika "loading new" — użytkownik na słońcu nie wie czy świeże wiadomości się ładują czy nie.
- **why it matters**: W warsztacie spawacz wraca do telefonu po skończeniu spawu i nie wie czy patrzy na świeży snapshot czy 7-sekundowo opóźniony — brak feedbacku.
- **suggested fix**: Mały spinner/dot w AppBar gdy poll w toku; lub stale widoczny "last updated Xs ago" w tytule.
- **effort**: M

- **severity**: med
- **location**: lib/screens/chat_screen.dart:546-547 (GestureDetector onLongPress jako jedyna afordancja report)
- **issue**: Report wiadomości tylko przez long-press, bez żadnego wizualnego wskaźnika że można — niewidzialna funkcja.
- **why it matters**: W warsztacie z rękawicami long-press jest trudny do trafienia; brak ikonki "..." = nikt nie zgłosi spamu, czat się zaśmieci.
- **suggested fix**: Dodać małą ikonę more_vert (size 18, _kTextSec) w prawym rogu cudzego dymka jako alternatywne wywołanie reportu.
- **effort**: M

- **severity**: med
- **location**: lib/screens/chat_screen.dart:402-414 (SnackBar treść — rate limit / banned / network)
- **issue**: SnackBar po błędach wysyłki używa domyślnego stylu Material, fontSize ~14, biały tekst na ciemnoszarym — na słońcu marny kontrast i 4s na przeczytanie.
- **why it matters**: Po "429" spawacz musi zrozumieć "max 8/min" — jeśli nie odczyta to będzie tap-tap-tap zwiększając rate-limit i frustrację.
- **suggested fix**: SnackBar z backgroundColor: Color(0xFF7A1E1E) dla błędów, textStyle: TextStyle(fontSize: 16, fontWeight: w600), duration 7s, behavior: floating.
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:67, 158 (AppBar title)
- **issue**: AppBar title używa domyślnego stylu z motywu — może mieć fontSize 18-20 bez explicit, w słońcu niewystarczające.
- **why it matters**: Nazwa ekranu / nazwa pokoju to pierwsza kotwica wzroku — spawacz w 0.5s musi wiedzieć "jestem w Spawanie MIG" a nie w innym pokoju.
- **suggested fix**: title: Text(..., style: TextStyle(fontSize: 20, fontWeight: w700, color: Color(0xFFE8ECF0))).
- **effort**: S

- **severity**: med
- **location**: lib/screens/chat_screen.dart:556 (maxWidth 0.78 * screen)
- **issue**: Maks szerokość dymka 78% ekranu — dla długich wiadomości technicznych (np. lista parametrów) wciąż line-wrap będzie częsty, a wąska linia tekstu zmusza do scrollu i utrudnia odczyt w słońcu.
- **why it matters**: Fitter dzieli się specyfikacją (np. „prąd 90A, gaz 12 l/min, drut 1.0") — zwięzła linia musi się zmieścić bez wrapów, inaczej w warsztacie scrolluje na łokciu, lub trzeba dwóch tapów żeby przeczytać.
- **suggested fix**: maxWidth 0.85, lub auto na podstawie długości tekstu (do 0.92 dla krótkich).
- **effort**: S

- **severity**: low
- **location**: lib/screens/chat_screen.dart:585-592 (message body text fontSize 13)
- **issue**: Treść wiadomości — fontSize 13 na ciemnym tle — sedno czatu nadal małe.
- **why it matters**: Już zgłoszone w Iter #20; przypominam jako duplikat dla synthesis.
- **suggested fix**: fontSize 15-16, weight w500.
- **effort**: S

- **severity**: low
- **location**: lib/screens/chat_screen.dart:594-597 (timestamp fontSize 10 _kTextMut)
- **issue**: Timestamp 10pt z najniższym kontrastem _kTextMut.
- **why it matters**: Duplikat z Iter #20.
- **suggested fix**: 12pt, _kTextSec.
- **effort**: S

- **severity**: low
- **location**: lib/screens/chat_screen.dart:273-274 (_RoomTile desc fontSize 12 _kTextSec)
- **issue**: Opis pokoju 12pt _kTextSec.
- **why it matters**: Duplikat z Iter #20.
- **suggested fix**: fontSize 13, jaśniejszy color.
- **effort**: S

- **severity**: low
- **location**: lib/screens/chat_screen.dart:577-583 (nickname fontSize 11)
- **issue**: Ksywka 11pt — duplikat Iter #20.
- **why it matters**: Już raportowane.
- **suggested fix**: 13pt.
- **effort**: S

- **severity**: low
- **location**: lib/screens/chat_screen.dart:665-674 (Send IconButton small touch)
- **issue**: Touch target ikony "Wyślij" mały dla rękawic.
- **why it matters**: Duplikat z Iter #20.
- **suggested fix**: iconSize 28, padding all(12).
- **effort**: S

--- end block ---

## Iter #46 · lib/screens/home_screen.dart · mixed-units

- **severity**: low
- **location**: lib/screens/home_screen.dart:709 (`_ProjectTile` subtitle "Ø$dStr mm · t $tStr mm")
- **issue**: Project subtitle hard-codes the `mm` unit token regardless of any user/project unit preference. The literal `mm` is also not routed through `context.tr`, so an EN locale user gets the same string. Duplicate of Iter #21 finding — re-flagged at low severity per duplicate guard.
- **why it matters**: A UK/US/offshore pipefitter scanning recent projects sees `Ø168.3 mm · t 7.1 mm` instead of `Ø6" SCH 40` — silent mixed-units anti-pattern on the home tile.
- **suggested fix**: Branch on a stored `project.unitSystem` (or user preference) and render `Ø{NPS}" · SCH {sch}` for imperial projects; gate the `mm` literal through a helper like `formatDiameter(d, system)`.
- **effort**: M

- **severity**: med
- **location**: lib/screens/home_screen.dart:444-449 (`_StatChip` for Segments — `value: '$totalSegments'`)
- **issue**: `_load()` sums `segLists.fold((n, s) => n + s.length)` blindly across all projects. The hero "Segments" KPI mixes mm-based and inch-based segment counts into one number with no unit indication. If half of a fitter's projects use NPS/inches and half mm, the chip says `Segmenty 47` but the underlying lengths cannot be compared, summed, or trusted as a single workload metric.
- **why it matters**: A workshop foreman glancing the home screen for "how much pipe work do I have queued?" gets a misleading single integer — the count is real but suggests homogeneity that doesn't exist. The dashboard becomes a false-confidence signal. On a busy day this is exactly the kind of "47 segments? must be a half-day" gut estimate that goes wrong.
- **suggested fix**: Either split the chip into `Segmenty (mm)` / `Segmenty (in)` when both exist, or annotate with mix ratio (`47 · 60% mm`). At minimum, when computing `segs` track per-unit counts and surface a tooltip.
- **effort**: M

- **severity**: med
- **location**: lib/screens/home_screen.dart:697-710 (`_ProjectTile` subtitle builder closure)
- **issue**: The closure reads `project.diameterMm` and `project.wallThicknessMm` — both fields are *named* `Mm` in the model. There is no escape hatch: even if the project was created from an ISO drawing in inches, the model forces mm storage; the home tile then has no way to know "this was originally 6 inch" and the user lost the canonical unit at save-time. The home screen is the symptom; the root smell is the model itself reading `Mm`-suffixed properties unconditionally.
- **why it matters**: An imperial-shop fitter who enters `6"` sees it converted and stored as `168.3 mm`. Round-trip back to the tile shows `168.3 mm` not `6"` — silent rounding (Ø168.275 → 168.3) plus unit-system loss. On safety-critical pipe spec lookups (SCH 40 vs SCH 80, X42 vs X52), this introduces a 0.1-0.3 mm drift that does not exist in their drawing.
- **suggested fix**: Add a `project.originalUnit` ('mm'|'in') and/or canonical numeric + display unit pair to `Project`; in the tile read whichever the project was authored in. Document that the home tile must NEVER convert silently.
- **effort**: L

- **severity**: med
- **location**: lib/screens/home_screen.dart:51-68 (`_load()`)
- **issue**: `_totalSegments` is computed by summing `s.length` across project segment lists without considering each segment's unit. There is no equivalent KPI for total *length* (`Σ length_mm`) or total *weight* — both of which a fitter would care about more than raw count. As soon as that is added, the same mixed-units risk applies: cannot sum `12000 mm` + `40 ft` without converting via a canonical unit. The current code structure does not gate against it.
- **why it matters**: As soon as v2 adds a `Total length` chip (a natural next ask from a foreman), summing inch-stored and mm-stored segments will silently miscompute by 30x. The current per-project sum loop is exactly where this bug class will be born.
- **suggested fix**: When/if length totals are introduced, convert per-segment to canonical mm (or m) before summing; assert each segment carries a unit field; add a unit-mix detector that flags `totalSegments` when projects span both unit systems.
- **effort**: M (preventive)

- **severity**: low
- **location**: lib/screens/home_screen.dart:155 (`childAspectRatio: 1.55`) and 195-197 (`'Ogłoszenia 49 PLN' / 'Listings 49 PLN'`)
- **issue**: Currency hard-coded as `49 PLN` in both PL and EN strings. Duplicate of Iter #21 — re-flagged at low. Additionally `childAspectRatio: 1.55` is a unitless layout number tightly coupled to the 2-line subtitle length — once a localised price string grows (`'~£10 (49 PLN)'`) it ellipsises asymmetrically; a mixed-units lens treats currency-per-locale as a unit decision.
- **why it matters**: EN-locale user (DE/UK/US shop) sees a Polish-złoty price with no conversion and has to mentally translate before committing to the JOBS tap. Friction at the paid-conversion moment.
- **suggested fix**: Localize price string per language (or drop the number from home and show inside JobsScreen), AND once string lengths vary loosen `childAspectRatio` or move to `GridView.builder` with intrinsic height.
- **effort**: S

- **severity**: low
- **location**: lib/screens/home_screen.dart:303-307 (empty-state coaching text "Zajmuje 30 s." / "Takes 30 s.")
- **issue**: Time unit `30 s` is written abbreviated and identically in both locales. Polish convention typically writes `30 sek.` or `30 sekund` in instructional copy; EN-US/UK convention writes `30 seconds` in user-facing UX. The bare `s` symbol is correct SI but stylistically jarring in onboarding microcopy — and crucially, mixed with the `mm` and `49 PLN` patterns elsewhere in this file, reinforces a pattern of leaking SI/abbreviations through user copy without per-locale styling.
- **why it matters**: Mixed-units is not only about length — it includes time, currency, and abbreviation conventions on the workshop floor where the foreman may be glancing for 0.5 s. Inconsistent abbreviation style across the home screen looks unpolished and erodes the "this app is built for me" feeling.
- **suggested fix**: Use `pl: '~30 sek.'` / `en: '~30 seconds'`; introduce a `formatDuration(seconds, lang)` helper and reuse anywhere else home references time.
- **effort**: S

- **severity**: low
- **location**: lib/screens/home_screen.dart:649 (`project.materialGroup == 'SS' ? _kBlue : _kOrange`)
- **issue**: Material group is a string-literal comparison against `'SS'` (stainless). Material group is not a unit per se, but in the mixed-units family — material affects density (used for kg/m), so when weight chips/exports are added later, this same string compare needs to map to a density value with units (kg/m³). Hardcoding `'SS'` here without a central material→density+unit table guarantees the same divergence will appear in the weight calculator.
- **why it matters**: When the welder asks "how heavy is my recent pipe project?", inconsistent material-group classification between home tile color and calculator weight will produce visible mismatches (badge says `SS` but weight uses carbon-steel density 7.85 kg/dm³ vs 7.93 kg/dm³).
- **suggested fix**: Introduce `MaterialSpec` enum/class with `densityKgPerM3` field and consume in both home tile color and any weight calculator; drop the bare `'SS'` literal.
- **effort**: M

--- end block ---

## Iter #47 · lib/screens/help_screen.dart · pdf-print-quality

- **severity**: med
- **location**: lib/screens/help_screen.dart (entire file — no export/print/share path exists for the knowledge base content)
- **issue**: The Help screen renders a sizeable, dual-language workshop knowledge base (TIG, materials, NACE, PWHT, NDT, ASME/API codes, BHP) but offers ZERO printable/PDF output for any entry. A fitter on the floor often needs to print a one-page "preheat table" or "purge gas spec" and pin it next to the welding bay. There is no "Print this entry", no "Export to PDF", no "Share as PDF" anywhere — the content is locked inside a scrollable dark-mode card.
- **why it matters**: Workshop floors regularly run without phones in the welding cell (sparks, magnetic fields, gloves). The most valuable knowledge-base items (PWHT temperature charts, preheat for X52 vs X65, NACE MR0175 quick-ref) are exactly the things a welder wants on paper, laminated, next to the bench. Today they have to screenshot → email → print, which mangles formatting and loses dual-language pairing.
- **suggested fix**: Add a `Icons.picture_as_pdf` action on each `_EntryRow` (when expanded) and on the `_SearchResultCard`; on tap, generate a single-page A4 PDF using the `pdf` + `printing` packages with: title, bilingual Q/A body, tags, category badge, and a footer "FitterWelderPro · printed YYYY-MM-DD". Reuse the existing PDF service used elsewhere in the app (calc reports / ISO exports).
- **effort**: L

- **severity**: med
- **location**: lib/screens/help_screen.dart:24-29 (`_kBg = 0xFF0F1117`, `_kCard = 0xFF1A1D26`, `_kTextSec = 0xFF9BA3C7`, `_kTextMut = 0xFF55607A`)
- **issue**: All content colors are deep-dark theme constants baked into the screen. If a print/PDF action is added later (see prior finding), naive `Printing.layoutPdf` rendering of the same widget tree would emit white-text-on-near-black PDFs that waste ink and become unreadable on a printed sheet. There is no `printable` variant of the entry body and no toner/paper-friendly color mapping.
- **why it matters**: A welder hitting "print" expects black-on-white that survives a 600 dpi laser, smudges from a gloved thumb, and overhead halogen glare in the shop. Dark-mode PDFs on white paper either (a) reverse-blast the page with toner (cost + dries cracking on folds) or (b) drop colors and become illegible grey-on-white. Either way the help entry becomes useless print output.
- **suggested fix**: When wiring print/PDF later, build a dedicated `HelpEntryPdfTheme` with pure-black titles `#000`, dark-grey body `#333`, accent only as a thin colored rule at top (no full-bleed fills). Never render `_kBg`/`_kCard` into the PDF canvas — convert to white-paper palette at the boundary.
- **effort**: M (preventive — only matters once print is added; flagged as part of this lens)

- **severity**: med
- **location**: lib/screens/help_screen.dart:243-253 (`_showAbout` content text)
- **issue**: The About dialog body interpolates live counts (`${kHelpCategories.fold...}`) into a Polish/English description. If a user ever exports/shares this for documentation purposes (e.g. forwarding to QA inspector or printing as a knowledge-base cover sheet), there is no static, dated, versioned variant. The text reads "Baza zawiera 47 tematów" with no date stamp — printed and pinned to a board, it ages silently and becomes inaccurate without anyone noticing.
- **why it matters**: Welding shops audited under ISO 3834 / ASME IX appreciate paper artefacts that carry a date + version. A knowledge-base cover sheet someone prints today and pins by the WPS binder will, a year later, mislead a new hire who assumes "47 topics" is still current.
- **suggested fix**: When (or before) adding print, append `· wersja {APP_VERSION} · stan na {YYYY-MM-DD}` to the About body; render this footer at the bottom of any printed/exported sheet too.
- **effort**: S

- **severity**: low
- **location**: lib/screens/help_screen.dart:486-495, 510-519 (`_HighlightedText` body with `fontSize: 13`, `height: 1.5`)
- **issue**: Body text is `fontSize: 13` with line-height 1.5 on a dark `_kBg`. For any future "print this entry" PDF flow, 13pt translates poorly to print-friendly point sizes (10-11pt is the typical A4 letterpress body minimum, 12pt for shop-floor readability under poor lighting). The screen-pixel size translates directly to print point size if the PDF generator naively reuses these styles.
- **why it matters**: Shop-floor reading distance ~50-70 cm with welding goggles or safety glasses + greasy gloves on the paper. 13pt at 1.5 line-height with dark theme reversed to ink looks "cramped and fuzzy" on a printed reference card; a welder squints, misreads `175°C` as `1.5°C`, sets the wrong preheat.
- **suggested fix**: When wiring print, build a `printableBodyStyle` with min 11pt for QA references, 12pt for shop-pinned cards, line-height 1.35-1.4; do NOT pass the screen `TextStyle` straight into the `pw.Text` PDF widget.
- **effort**: S (preventive)

- **severity**: low
- **location**: lib/screens/help_screen.dart:520-543 (tag chips Wrap) and 414-427 (category count badge)
- **issue**: Tag chips render with `accent.withValues(alpha: 0.10)` background — readable on dark theme but invisible on white paper if a `RepaintBoundary`-to-PDF screenshot path were used. The category count pill uses similar low-alpha fills. Today there is no PDF path; the moment print/export ships, these "soft tint" chips silently disappear into the page, dropping context (the entry tag set, its category badge).
- **why it matters**: Tags like `#preheat`, `#WPS`, `#NACE-MR0175` are how a welder cross-references printed sheets in a binder. Losing them on the printed copy strands the document — it cannot be re-found, refiled, or audit-trailed back to the digital source.
- **suggested fix**: For print, render tags as bordered outline chips with solid 1pt black border + black text (no fill), and the count badge as a solid black-outline circle with the integer in bold; reserve alpha-tinted fills for screen only.
- **effort**: S (preventive)

- **severity**: low
- **location**: lib/screens/help_screen.dart:485-495 (`entry.question(lang)`) + 510-519 (`entry.answer(lang)`)
- **issue**: Only ONE language is rendered per expanded entry (PL or EN, depending on `AppLanguage`). For a printable/exportable knowledge-base sheet aimed at multi-national crews (PL welder + DE foreman + EN-speaking QA inspector — a common combo on shipyard and pipeline jobs), there is no "print both languages side-by-side" option. The current UI structurally cannot produce a bilingual page even if a PDF export is added without restructuring.
- **why it matters**: Bilingual PL/EN is a stated core value of the app. On printed shop-floor cards in real-world EU welding jobs (mixed-nationality crews), the bilingual layout is the killer feature versus a single-language paper print. Without it the help base loses its multi-crew advantage at the print boundary.
- **suggested fix**: When adding PDF export, build a two-column page layout: PL left, EN right, shared figure/table center; expose a "Bilingual / PL only / EN only" toggle on the print dialog. Requires `entry.question(AppLanguage.pl)` AND `entry.question(AppLanguage.en)` in the same render pass.
- **effort**: M (preventive)

- **severity**: low
- **location**: lib/screens/help_screen.dart:649-695 (`_HighlightedText` build — search-term highlight)
- **issue**: Search highlight uses `highlightColor.withValues(alpha: 0.15)` as `backgroundColor` on the matched span. If a user prints the currently-displayed expanded entry while a search term is active, the printed sheet would show alpha-tinted highlights — on white paper these emerge as a faded color wash that the toner can render unpredictably (some printers ignore <20% alpha entirely, others rasterize it as solid pastel).
- **why it matters**: The search highlight is a UX cue for the screen, not a permanent annotation on a binder copy. A welder who prints "purge gas" search results expects clean paragraphs, not yellowed key-terms that look like a hand-marker the previous shift used.
- **suggested fix**: Strip highlight spans before PDF rendering; if highlighting is preserved deliberately, switch to underline or a small `[*]` margin marker instead of color background for the printable variant.
- **effort**: S (preventive)

- **severity**: low
- **location**: lib/screens/help_screen.dart:155-173 (horizontal filter chips ListView)
- **issue**: The category filter chips row is a `ListView` of horizontal chips. There is no equivalent "category index" or "table of contents" surface that could be rendered as a printed cover page for an exported binder. A multi-entry export (e.g. "print all PWHT entries") would not naturally carry a paginated TOC because the screen has no concept of one.
- **why it matters**: A foreman who decides to print the full TIG knowledge base for the welding cell wall needs a 1-page index up front: category → entry → page-N. Without it the printed bundle is a loose 30-page stack with no navigation.
- **suggested fix**: When/if multi-entry PDF export ships, generate a TOC page from `kHelpCategories` flat-mapped over entries; reserve room in the entry header for a page number. Build an in-app preview using the same model so the foreman can choose what to print.
- **effort**: M (preventive)

--- end block ---

## Iter #48 · lib/services/prefab_engine.dart · offline-resilience

- **severity**: low
- **location**: lib/services/prefab_engine.dart:1-81 (whole file)
- **issue**: No findings under offline-resilience lens. `PrefabEngine` is a pure, synchronous, stateless math kernel (`const PrefabEngine._()` with two static methods `cutLengthMm` and `needsDimRefPicker`). Zero I/O surface: no `dart:io`, no `http`, no `SharedPreferences`, no Firestore, no platform channels, no async, no streams, no isolates, no filesystem, no clock/date dependency. Only import is `../models/prefab/dim_ref.dart` (a plain enum). All inputs are primitives passed in by the caller; all outputs are pure numeric returns. NaN guard at line 47 already handles malformed numeric input deterministically. Null-safety on optional `leftCteMm`/`rightCteMm`/`leftPhysicalLenMm`/`rightPhysicalLenMm` via `?? 0` at lines 49-52 means partial component data (e.g. fitting catalog missing one CTE) degrades gracefully without throwing — which IS the offline-relevant behavior, and it is already correct.
- **why it matters**: A welder on a workshop floor with no signal will run cut-length math entirely client-side. This kernel guarantees that — there is no path through `PrefabEngine` that can touch a network or fail due to missing connectivity. Already maximally offline-resilient by construction.
- **suggested fix**: none — covered by design. (If anything is ever added here that touches I/O, the lens should re-fire.)
- **effort**: S

--- end block ---

## Iter #49 · lib/services/iso_pdf_export.dart · a11y-semantics

- **severity**: high
- **location**: lib/services/iso_pdf_export.dart:30-36, 82
- **issue**: Rasterized canvas image is embedded in the PDF as a bare `pw.Image` with no alt text / figure description. Screen readers (NVDA, JAWS, VoiceOver on macOS Preview, TalkBack on Android via PDF viewer) announce nothing — a fitter / brygadzista with low vision who receives the PDF on phone or laptop gets a silent block where the isometric drawing should be described.
- **why it matters**: A spawacz with reading glasses pressure or a brygadzista using PDF readers in noisy workshop conditions (with audio output through Bluetooth headset under helmet) cannot get any verbal cue identifying this as the isometric drawing. PDF/UA accessibility requires every figure to carry alt text describing it.
- **suggested fix**: At minimum, add a small caption immediately under the image (e.g. `pw.Text('Rysunek izometryczny — $projectName', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic))`) so screen-reader text extraction reaches a textual fallback; longer term, pass figure semantics via the pdf package's structure-tree API if available.
- **effort**: S

- **severity**: high
- **location**: lib/services/iso_pdf_export.dart:51
- **issue**: `pw.Document(theme: theme)` is constructed without any document metadata — no `title`, no `author`, no `subject`, no `keywords`, no `creator`. PDF readers announce document title aloud and use it in the tab/window bar; without it, the user hears the temp filename (`ISO_xxx_1717000000000.pdf`), which is meaningless.
- **why it matters**: Brygadzista getting a stack of ISO PDFs over WhatsApp / e-mail needs the title for screen-reader identification and to find the right ISO among 5+ open tabs. Empty metadata = uniformly unidentified docs.
- **suggested fix**: `pw.Document(theme: theme, title: 'ISO — $projectName', author: 'Fitter Welder Pro', subject: 'Rysunek izometryczny + cut list + BOM', creator: 'FitterWelderPro', keywords: 'isometric,pipe,fitter,welder,cut list,BOM')`.
- **effort**: S

- **severity**: high
- **location**: lib/services/iso_pdf_export.dart:59-137
- **issue**: PDF is generated without language tag (`lang: 'pl-PL'`). Screen readers default to system language and may mispronounce Polish words like "Wygenerowano", "zestawienie materiałowe", "Szt."
- **why it matters**: A Polish-speaking monter on a German job site whose laptop has German locale will hear German TTS pronounce "zestawienie materiałowe" — garbled and useless. PDF needs to declare content language so the reader switches voice.
- **suggested fix**: Set language metadata at document level (the pdf package exposes this via `PdfDocument` config or theme); document the limitation in code comment if API unavailable in current version.
- **effort**: M

- **severity**: high
- **location**: lib/services/iso_pdf_export.dart:97-105
- **issue**: Cut list uses `pw.Font.courier()` at fontSize 9. That courier face is the package-bundled Latin-1 Courier — NO Polish diacritic coverage. The comment at lines 39-42 explicitly explains why prior exports rendered Polish chars as blanks, yet the cut list ignores the bundled Roboto and reverts to Courier. If `cutListLines` contains "Ø", "ćwierć", "wąsko" or "łuk" they will render as blank boxes — failing the very fix the comment claims to address.
- **why it matters**: Cut list lines are the actionable data the welder/monter carries to the saw. A blank where "Ø42 ćwierć-łuk" should be becomes a cut error. It is also an a11y regression — missing-glyph boxes are unreadable by humans and by PDF text-extraction (screen-reader copy/paste).
- **suggested fix**: Bundle Roboto-Mono (`assets/fonts/RobotoMono-Regular.ttf`) and use `pw.Font.ttf(monoBytes)` for the cut list, OR fall back to `font: baseFont` (Roboto) and accept slight loss of monospace alignment.
- **effort**: S

- **severity**: med
- **location**: lib/services/iso_pdf_export.dart:114-133
- **issue**: BOM table uses `pw.TableHelper.fromTextArray` without `headerCount: 1` and without table caption / summary. PDF/UA requires `<TH>` vs `<TD>` tagging so assistive tech can read "Komponent: Kolano 90°, Sztuk: 4" in associated pairs rather than orphaned cell content.
- **why it matters**: Brygadzista reviewing BOM via screen reader hears "Kolano 90° 4 Tee 2 Reducer 1" — numbers detached from labels. With proper header semantics the reader announces "Komponent Kolano 90°, Sztuk 4" per row — actionable hands-free.
- **suggested fix**: Add `headerCount: 1`, prepend `pw.Text('BOM — zestawienie materiałowe (${bom.length} pozycji)')` caption, and consider switching to manual `pw.Table` with `pw.TableRow(repeat: true)` for proper repeating header semantics on multi-page BOMs.
- **effort**: M

- **severity**: med
- **location**: lib/services/iso_pdf_export.dart:97-105
- **issue**: Cut list rendered as a vertical stack of `pw.Text` lines in a generic `pw.Column`. No list-like structure (`pw.Bullet` or numbered list). PDF/UA wants ordered/unordered list tagging so screen readers announce "lista 8 elementów, element 1 z 8: ...". Currently it's a wall of free text.
- **why it matters**: A monter on a phone with VoiceOver needs item-by-item navigation (swipe right per line). Without list semantics the entire block is a single text node — top-to-bottom listen-through with no skip.
- **suggested fix**: Wrap each line in `pw.Bullet(text: l, style: ...)` or use a numbered Row pattern (`pw.Row(children: [pw.Text('${i+1}.'), pw.Expanded(child: pw.Text(l))])`).
- **effort**: S

- **severity**: med
- **location**: lib/services/iso_pdf_export.dart:70, 206, 210
- **issue**: Footer text and header timestamp use `#9BA3C7` at fontSize 8 on white — contrast ratio ~3.0:1, fails WCAG AA for text under 18pt (needs 4.5:1). Timestamp ("Wygenerowano 2026-06-07 14:30") and page count ("str. 1/2") are below threshold.
- **why it matters**: Workshop lighting is often poor (overhead sodium, dusty PDFs printed on lower-quality paper, smudges from oily hands). Low-contrast small print becomes invisible. Timestamp matters when brygadzista verifies the ISO is from today, not last week's revision.
- **suggested fix**: Change `#9BA3C7` to `#5A6280` (~5.5:1 on white), passes WCAG AA. Optionally bump fontSize from 8 to 9.
- **effort**: S

- **severity**: med
- **location**: lib/services/iso_pdf_export.dart:161-163
- **issue**: Share sheet `subject` / `text` use literal placeholder "(bez nazwy)" when projectName is empty. Screen reader on the receiving device announces "ISO — bez nazwy — wygenerowany w Fitter Welder Pro" with em-dash and parens read as punctuation noise. No fallback to a date-based label.
- **why it matters**: Brygadzista receiving multiple unnamed ISOs via WhatsApp can't distinguish them. A semantic auto-label like "ISO z 7 czerwca 2026" would be screen-reader friendly and self-identifying.
- **suggested fix**: When projectName is empty, use `'ISO z ${stamp.split(" ").first}'` (e.g. "ISO z 2026-06-07") as fallback, drop the parens.
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:64-72
- **issue**: Footer is a single text line ("Fitter Welder Pro · isometric notebook") repeated on every page; no page numbers in footer (count IS in header line 209 but if header is cut on misconfigured printer the pagination is lost).
- **why it matters**: When brygadzista duplex-prints and a cover sheet jams, having pagination ONLY in the header means a misfed sheet loses its identity. A page-N-of-M in the footer is a redundant safety net.
- **suggested fix**: Add `pw.Text('str. ${ctx.pageNumber}/${ctx.pagesCount}', ...)` to the footer alongside the brand text. One-line change, dramatic improvement.
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:118
- **issue**: BOM header uses abbreviation "Szt." for "Sztuk" (pieces). Polish TTS engines may read this as "S Z T" letter-by-letter or as "shtuck" — undefined cross-engine.
- **why it matters**: Brygadzista listening to the PDF hears unclear unit label, has to guess "pieces or kg?". A monter ordering from BOM needs unambiguous unit.
- **suggested fix**: Expand the header label to "Sztuk" (full word) or add a clear unit column.
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:241-246
- **issue**: `_safeFileName` strips ALL non-ASCII characters via `[^a-zA-Z0-9_-]`. Polish project names like "Linia chłodząca 3" become "Linia_ch_odz_ca_3". Screen readers announce verbatim — "Linia podkreślenie ch podkreślenie odz podkreślenie ca podkreślenie 3" — unreadable. The brygadzista cannot find "Linia chłodząca" by searching their download folder.
- **why it matters**: Filename a11y matters when assistive tech reads file lists. Polish diacritic loss also breaks search/sort.
- **suggested fix**: Transliterate Polish chars (ą→a, ć→c, ę→e, ł→l, ń→n, ó→o, ś→s, ź→z, ż→z) before sanitizing, OR use a Unicode word-class regex (`RegExp(r'[^\p{L}\p{N}_-]', unicode: true)`).
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:154-157
- **issue**: User-facing error message "PDF zapisany niepoprawnie — sprawdz miejsce na dysku" — note "sprawdz" missing diacritic (should be "sprawdź"). Polish TTS engines depend on diacritics for correct phonetic stress.
- **why it matters**: A monter using Polish TTS hears "spravdz" instead of "sprawdź" — slightly off but cumulative across the app suggests poor localization quality.
- **suggested fix**: Change to "sprawdź miejsce na dysku".
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:33, 154, 252, 254, 259
- **issue**: All `StateError` messages are English ("Canvas capture failed", "Repaint boundary not mounted", "PNG conversion failed"). These propagate to the UI where they may surface in SnackBars to a Polish monter who has no idea what "Repaint boundary not mounted" means.
- **why it matters**: A fitter on the workshop floor seeing "Canvas capture failed — no PNG bytes returned" in a SnackBar taps it away in frustration. For screen-reader users — incomprehensible English jargon announced mid-Polish UI flow disorients them.
- **suggested fix**: Catch in calling screen and translate to "Nie udało się wygenerować PDF — spróbuj ponownie" with full diacritics; or move user-facing strings to Polish here directly.
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:30
- **issue**: Hardcoded `pixelRatio: 2.0` for canvas capture. On high-DPI accessibility scaling (system text scale 1.5×+ or iOS Display Zoom) the captured image may be insufficient and produces a blurry canvas when the user zooms in.
- **why it matters**: Brygadzista zooming into the ISO drawing on tablet to read fitting callouts (especially with vision impairment requiring system text scale increase) sees pixelation. A11y depends on rendered output remaining crisp at high zoom.
- **suggested fix**: Use `max(2.0, MediaQuery.of(context).devicePixelRatio)` if context is available, capping at 3.0 for memory safety. Or document the tradeoff with a TODO.
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:97-105
- **issue**: Cut list lines rendered without explicit `softWrap`/`overflow` handling. Long lines (e.g. "Odcinek 1: Ø168.3 × 7.1 stal P235GH długość 2340mm z ukosem 30°") at fontSize 9 mono may overflow the page width and mid-break a dimension ("2340m\nm").
- **why it matters**: A welder misreading "2340m\nm" as 2340m + m suffix = catastrophic cut error. Soft-wrap defaults are font-dependent and not guaranteed safe.
- **suggested fix**: Set explicit `softWrap: true, overflow: pw.TextOverflow.visible` on each `pw.Text`, or pre-wrap lines in the formatter to a known width.
- **effort**: S

- **severity**: low
- **location**: lib/services/iso_pdf_export.dart:59-137
- **issue**: No alternate "high-contrast B&W only" export mode. Code comment at lines 232-234 acknowledges the orange section header renders as ~30% gray on mono printers — but only the text color is preserved, the background still prints gray and the section header card becomes a low-contrast block.
- **why it matters**: A brygadzista with monochromacy or printing on a workshop B&W laser sees the orange band become mid-gray that competes with navy text — exactly the failure mode the comment flags.
- **suggested fix**: Add `static Future<void> exportBW(...)` opt-in variant that swaps orange `#F5A623` for plain black border with white fill + bold uppercase text.
- **effort**: M

--- end block ---

## Iter #50 · lib/services/premium_service.dart · undo-coverage
- **severity**: high
- **location**: lib/services/premium_service.dart:107-117 (`init()`)
- **issue**: When the persisted deviceId is shorter than 16 chars, `init()` silently overwrites it with a freshly generated one and writes it to SharedPreferences. There is no backup of the old id and no way to undo this — a fitter who paid via Stripe with the old `client_reference_id` would be permanently disconnected from their subscription after one app update that tightened the length check.
- **why it matters**: A welder on the workshop floor who already paid 149 PLN/year sees the PRO badge disappear after an app update and has no path to recover — there is no "previous device id" to fall back to and no UI to paste it back.
- **suggested fix**: Before overwriting, copy the old id to a `fitter_device_id_previous` key; add a `restorePreviousDeviceId()` method and surface it on the Premium screen ("Stracony dostęp? Przywróć poprzednie urządzenie").
- **effort**: M

- **severity**: high
- **location**: lib/services/premium_service.dart:217-248 (`refreshFromBackend()`)
- **issue**: A single backend response with `is_active: false` immediately calls `applyStatus(PremiumStatus.free())` and broadcasts a downgrade. There is no undo, no grace period, and no "we'll keep your PRO until you confirm" buffer. A backend hiccup or webhook race condition strips PRO from the UI with no rollback path; the user must restart, refresh, and hope the next response is correct.
- **why it matters**: A monter mid-job opens a PRO calculator (e.g. AI rurowy chat), the background refresh fires, backend returns stale `is_active:false` for 3 seconds, and the gated screen slams shut mid-calculation. No "undo" button, no toast with "Coś poszło nie tak — przywróć?". Trust in the paywall collapses.
- **suggested fix**: Keep the previous `PremiumStatus` in a `_previousStatus` field; if a refresh downgrades from active→free, schedule a 2-minute grace window and a second confirmation refresh before broadcasting. Expose `revertLastRefresh()` for the UI.
- **effort**: M

- **severity**: med
- **location**: lib/services/premium_service.dart:146-149 (`applyStatus()`)
- **issue**: `applyStatus()` overwrites `_current` with no history stack. Every caller (Stripe webhook listener, Firestore listener, dev override, restore-purchases) can wipe the previous status with no audit trail. There is no `undo` on the service itself.
- **why it matters**: If two competing async paths fire (Stripe webhook + restore-purchases on iOS) and one races to set free while the other sets lifetime, the loser silently wins. No history → no way to ask "what was the status 5 seconds ago?" in support tickets.
- **suggested fix**: Maintain a bounded ring buffer (`List<PremiumStatus> _history`, max 8 entries) updated inside `applyStatus`; add `Future<void> undoLastStatusChange()` that pops the buffer and re-broadcasts.
- **effort**: S

- **severity**: med
- **location**: lib/services/premium_service.dart:153-162 (`debugUnlockPro()` / `debugClear()`)
- **issue**: Debug helpers flip status with no confirmation and no undo. A field tester who taps "debugClear" on a long-press hidden gesture cannot get back to the previously-unlocked test state without restarting the app and waiting for the next backend refresh.
- **why it matters**: QA on the workshop floor (or a beta fitter clicking around) accidentally hits the debug clear, loses PRO mid-test, and has to leave the welding bay to ping support. With an undo they could just tap "Cofnij".
- **suggested fix**: Cache the pre-debug status in `_preDebugStatus` and add `debugRestorePreDebugStatus()`; show a SnackBar with "Cofnij" action on every debug toggle.
- **effort**: S

- **severity**: med
- **location**: lib/services/premium_service.dart:97-98 (StreamController + `_current`)
- **issue**: The stream is one-way: subscribers can react to a status change but cannot replay or rewind. There is no `BehaviorSubject`-style "current + previous" snapshot; widgets that mount after a downgrade only see the new state and cannot offer an "undo this change" affordance.
- **why it matters**: Premium screen built after a backend-initiated downgrade has no way of knowing the user was PRO 2 seconds ago, so it cannot render an inline "Wróć do PRO (cofnij ostatnią zmianę)" CTA — the fitter has to navigate to Stripe portal and rebuy.
- **suggested fix**: Switch `_controller` to emit `PremiumStatusChange { previous, next }` records, or expose `PremiumStatus? get previousStatus`.
- **effort**: M

- **severity**: low
- **location**: lib/services/premium_service.dart:174-194 (`createCheckoutSession()`)
- **issue**: No cancellation/undo for an in-flight checkout. Once the URL is returned and the user is bounced to Stripe, there is no client-side `abortCheckoutSession()` call to the backend to mark the session voided. If the user backs out, the session remains open server-side until Stripe timeout.
- **why it matters**: A welder taps "kup PRO miesięczny", sees the price in PLN on Stripe, decides to switch to yearly instead, comes back — the old session lingers. No "Anuluj rozpoczęty zakup" button is wired.
- **suggested fix**: Return a `{checkoutUrl, sessionId}` pair and add `cancelCheckoutSession(sessionId)` that hits `/api/fitter/billing/checkout/cancel`.
- **effort**: M

- **severity**: low
- **location**: lib/services/premium_service.dart:199-210 (`createPortalSession()`)
- **issue**: No equivalent undo if a subscription is cancelled via Stripe portal — the client never proactively offers "Przywróć anulowaną subskrypcję" before period end. Stripe supports reactivation but the service has no helper.
- **why it matters**: A monter cancels in the portal in a panic about a bill, gets paid two days later, wants PRO back instantly, but the app gives no path to undo the cancel before period end.
- **suggested fix**: Add `Future<bool> reactivateSubscription()` calling a backend endpoint that flips `cancel_at_period_end` back to false; surface in Premium screen when status shows pending-cancel.
- **effort**: M

- **severity**: low
- **location**: lib/services/premium_service.dart:97 (`StreamController.broadcast()` without `onListen` replay)
- **issue**: New subscribers do not receive the last-emitted status until the next change. Combined with no undo, a screen rebuilt after a hot-reload or navigation cannot show "the change you just saw — cofnij?" because it never received that change event.
- **why it matters**: Reactive paywall UIs miss the transient downgrade event and so cannot offer undo affordances.
- **suggested fix**: Replace `StreamController.broadcast()` with `rxdart.BehaviorSubject<PremiumStatus>.seeded(_current)`, or manually re-emit `_current` in a custom `statusStream` getter via `Stream.value` + concat.
- **effort**: S

--- end block ---
