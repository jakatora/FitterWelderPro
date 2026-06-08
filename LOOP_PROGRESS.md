# Loop Progress — iteracje analizy + ulepszania

Wersja: 2026-05-28 (kontynuacja po pierwszej iteracji). Każda iteracja:
research wbudowanej wiedzy o sektorze rurociągów + konkretne ulepszenie
w kodzie. Auto-mode classifier zablokował autonomiczne 100 iteracji w
pętli — wykonuję wsadowo, ty oceniasz po każdym pakiecie.

---

## Iter 1 — Klasyfikator osi iso + kompas legend

`iso_notebook_screen.dart`:
- `_classifyAxis(a, b)` — wykrywa czy linia leży na osi I (0°), II (60°),
  III (120°) z tolerancją ±6°; reszta = off-axis.
- `_drawAxisTag` — kolorowy chip I/II/III na każdej rurze, off-axis = ⚠.
- `_AxisCompass` — floating widget top-right pokazujący 3 osie ze
  strzałkami i legendą.

## Iter 2 — North arrow → mapowanie N/E/Up

`iso_notebook_screen.dart`:
- `_AxisMapping` z 6 iso-headings (3 osie × 2 końce).
- `_symNorth` przerysowany: dir=0 = wzdłuż osi I (zamiast pionowego up),
  rotacja 60° cyklicznie chodzi po 6 iso-kierunkach.
- `_currentMapping` getter — szuka pierwszej strzałki N na canvasie i
  buduje mapping; bez N — osie pozostają anonimowe (I/II/III).
- `labelForLine(a, b)` — zwraca N/S, E/W, ↑/↓ dla linii zgodnie z
  kierunkiem +N strzałki.
- Kompas legend przełącza I/II/III ↔ N/E/U po umieszczeniu strzałki N.

## Iter 3 — Take-out catalog DN (ASME B16)

Nowy plik `services/takeout_catalog.dart`:
- DN15..DN300, każdy z 10 kategoriami komponentów (LR/SR 90°, 45°, tee,
  reducer, cap, flange WN cl.150, gate/ball/check valve cl.150).
- Wartości CTE/FTF z B16.5/B16.9/B16.10.

`iso_notebook_screen.dart`:
- "Katalog ASME" button w dialogu cut-calc → 2-step bottom sheet:
  najpierw DN, potem komponent → row z auto-wypełnionym name+value.
- `_lastCatalogDn` zapamiętuje ostatnie DN żeby DN100 fab nie wymagał
  re-pickingu.

## Iter 4 — Axis-lock przy rysowaniu rury

`iso_notebook_screen.dart`:
- `_axisLock` (default true) — zmusza nową rurę do leżenia dokładnie na
  jednej z 3 iso-osi (z 6 prymarnych kierunków).
- `_axisSnap(from, target)` — projekcja na każdy z 6 heading-ów, wybór
  najbliższego do palca + integer k grid-steps.
- IconButton w app barze (`Icons.lock` / `lock_open`) do wyłączenia gdy
  user musi rysować linie sloped (drain falls).

## Iter 5 — Bolt Torque flange preset (B16.5)

Nowy plik `services/flange_catalog.dart`:
- DN15..DN300 × Class 150/300/600/900/1500 → bolt count + bolt size.
- Pełne tablice z B16.5 Table 11.

`bolt_torque_screen.dart`:
- Nowa sekcja "Preset kołnierza" — 2 dropdowny (DN + Class), automatycznie
  ustawia bolt size i wyświetla "8× 5/8\" śrub".
- Wynik card pokazuje "8 śrub × 95 N·m, gwiazda 25/50/75/100%" — monter
  od razu wie ile razy nakręcić klucz dynamometryczny.

## Iter 6 — Heat Input material catalog

Nowy plik `services/material_catalog.dart`:
- 15 najczęstszych gatunków w piping: A106 B, A53 B, A516 70, A335 P1/P11/P22/P91,
  410 SS, 304/316/321/347, 2205/2507 Duplex, Inconel 625, Monel 400.
- Każdy: ASME P-No, skład typowy, WPS HI window kJ/mm, preheat note,
  uwagi praktyczne (np. "P91 PWHT obowiązkowe").

`heat_input_screen.dart`:
- Sekcja "Materiał" w tab Preheat/CE — chipy z gatunkami; klik → wypełnia
  C/Mn/Cr/Mo/V/Ni/Cu + WPS HI range + pokazuje highlight z preheat
  rekomendacją i notesem.

## Iter 7 — Pre-weld checklist P-No specific

`pre_weld_checklist_screen.dart`:
- Material picker (chipy w pasku scrollable) — wybór gatunku dodaje
  P-No specific items do uniwersalnej checklisty.
- 6 P-No extras zdefiniowanych: P1 (low-H elektroda), P4 (preheat 150-200°C
  + PWHT slot), P5 (KRYT. preheat + E9015-B9 + PWHT), P8 (interpass
  <175°C + L-grade), P10 Duplex (interpass + N₂ purge + ferrite), P43
  (Inconel — niski HI + czysty Ar).
- Extra items oznaczone chipem "P91 · P5" itd. żeby monter wiedział
  skąd pochodzą.
- Liczność postępu dynamicznie się dopasowuje (`_done.length / list.length`).

---

## Pliki dodane (3)

- `lib/services/takeout_catalog.dart` (105 linii)
- `lib/services/flange_catalog.dart` (95 linii)
- `lib/services/material_catalog.dart` (160 linii)

## Pliki zmienione (4)

- `lib/screens/iso_notebook_screen.dart` (+iter 1-4, +540 linii)
- `lib/screens/bolt_torque_screen.dart` (+iter 5, +95 linii)
- `lib/screens/heat_input_screen.dart` (+iter 6, +110 linii)
- `lib/screens/pre_weld_checklist_screen.dart` (+iter 7, +130 linii)

## Iter 8 — Slope tag dla off-axis rur (drain/vent)

`iso_notebook_screen.dart`:
- `_Seg.slope` (String, default '') + `withSlope()` helper
- `_CalcResult.slope` — pole zwracane z dialogu
- `_askCalc(slope: ...)` — dialog ma sekcję "Spadek (drain/vent)" z polem
  tekstowym, hint "1:100, FALL 25mm, 5° w dół"
- `_drawSlope(canvas, seg)` — czerwony chip "↘ FALL 25mm" przy 1/4 odcinka
- Slope też loguje się w cut-list export (PDF i clipboard)

## Iter 9 — PDF export zeszytu ISO (KILLER FEATURE)

Nowy plik `services/iso_pdf_export.dart`:
- Capture canvasu via `RenderRepaintBoundary.toImage` (2× pixelRatio)
- A4 multi-page PDF: nagłówek (project name, data, str N/M),
  rasterised canvas image, cut list w monospaced bloku, BOM table
- Share przez `share_plus` (XFile)

`iso_notebook_screen.dart`:
- `_canvasKey` GlobalKey wokół CustomPaint w RepaintBoundary
- IconButton "Eksportuj PDF" (Icons.picture_as_pdf_outlined) w app barze
- `_exportPdf()`: pobiera boundary, buduje cutListLines + bomMap przed
  async gap, woła `IsoPdfExport.export()`
- `_cutListLines()` i `_bomMap()` — split z `_copySummary` żeby PDF
  i clipboard miały tę samą formatkę

## Iter 10 — Help search ze stemming PL

`services/help_search.dart`:
- `_stem(word)` — strip 30+ polskich końcówek (owanie, iastego, ami, ach,
  ów, em, …) z minimum 4-char zachowanej rdzeni
- `termStems` lista pairs (term + stem) — każdy term porównywany dwa razy
- Stem fallback: tag/question/answer przeszukiwane też po stem (połowa
  scoringu literalnego)
- AND bonus: `matched.length == terms.length` daje `+6 × |terms|`
  punktów żeby AND-matche biły OR-matche

Efekt: "kolano" wyszukuje "kolanka", "kolana", "kolanami"; "spawa"
wyszukuje "spawanie", "spawania", "spawaniu".

## Build status

- `flutter analyze` — 0 issues
- APK — build w toku (bmapu0dej)

## Kolejka na dalsze iteracje (gdy chcesz wrócić)

8. **Slope arrows + spadek tag** — drain lines z "FALL 25mm" lub "1:100",
   strzałka na canvasie.
9. **LR/SR elbow distinction w toolbarze** — osobne tooly dla LR i SR
   żeby auto-deduct użył poprawnej tabeli.
10. **Reducer DN1/DN2** — komponent reducer ma pole "size before" i
    "size after"; tag wyświetla "DN100→DN50".
11. **PDF export izometryku** — generowanie pełnego PDF z izo + BOM +
    cut list dla brygadzisty.
12. **Help search RAG poprawa** — lepsze retrieval z piping_knowledge.md.
13. **Saddle template — mitre + lateral types** — generator dla cięć
    nie tylko 90° branch.
14. **AI Chat history** — zapamiętywanie rozmów + powrót.
15. **Praca module backend** — schema, CRUD, Stripe one-time boost.
16. **Chat user-to-user backend** — Firestore + push + moderation.
