# CUT LIST Prefab Engine — Design Document

**Status:** DRAFT 2026-05-31 · waiting for go-ahead before any code lands
**Scope:** Architecture rebuild of CUT LIST math inside `lib/screens/iso_notebook_screen.dart` and its supporting data model. NOT a new module — replacing the oversimplified subtraction in the existing ISO Notebook.
**Why now:** Current model assumes every dimension is centre-to-centre and every component is axial. Real shop iso drawings mix five different dimension references (CTC, CTF, FTF, FTE, CTE) and have non-axial components (flange, reducer, valve, cap) whose subtraction depends on what the dimension was measured to. Today's app silently produces wrong cut lengths on any drawing more complex than the demo case.

---

## 1. Vision

The notebook becomes a *smart prefab engine* rather than a sketch pad with a calculator on the side. Goals:

1. **CUT-list math that matches what a real fitter does on paper** — including reducers, flanges, valves, mixed dim references and propagated diameter changes.
2. **Auto-weld detection** at every component / pipe / component-to-component boundary, with sequential weld numbering and shop-vs-field type.
3. **Spooling-aware** data model — every weld, segment and component belongs to a spool, BOM and weld map roll out of the same source of truth.
4. **Open to future extensions** without rework: gap/shrinkage/bevel allowances, PCF export, weld-map QC, MTO, IFC.

Non-goals: 3D, AR, automatic spool nesting, automatic line-number recognition.

## 2. Data model

### 2.1 Dimension references

```dart
/// What the on-drawing ISO dimension is measured between.
/// Fitter taps this when entering the dim; default at creation is CTC.
enum DimRef {
  centreToCentre,  // CTC — two axial fittings, centre-to-centre
  centreToFace,    // CTF — axial centre to physical face
  faceToFace,      // FTF — two physical faces
  faceToEnd,       // FTE — physical face to a pipe cut end
  centreToEnd,     // CTE — axial centre to a pipe cut end
}
```

### 2.2 Component behaviour class

```dart
/// How the component contributes to CUT-list math. NOT the same as its
/// visual type (elbow, tee, flange...). Multiple visual types can share
/// the same behaviour (e.g. tee + lateral + olet are all axial-with-branch).
enum ComponentBehaviour {
  axialCenter,        // elbow 90/45, tee run, lateral — has CTE only
  axialWithBranch,    // tee branch, olet — separate branch CTE
  physicalLength,     // reducer, valve, strainer, expansion joint
  faceOnly,           // flange (one face), cap (one face)
  diameterChange,     // reducer / swage — also propagates DN downstream
  zeroLength,         // weld point, instrument tap — no length contribution
}
```

### 2.3 Connection type per component end

```dart
/// What kind of joint forms at each component end. Drives weld point
/// auto-insertion AND the take-out math (a socket-weld flange has zero
/// take-out from the centre of the pipe; a slip-on has insertion depth).
enum EndConnection {
  buttWeld,
  socketWeld,
  threaded,
  slipOn,
  lapJoint,
  weldNeck,
  groove,
  none,   // bare pipe end (open, hydrotest cap, etc.)
}
```

### 2.4 Tee sides

```dart
/// Tee / lateral / olet sides — needed so the algorithm knows which
/// take-out to apply when the segment enters from one direction and
/// continues out a different one. The drawing direction picks the side.
enum TeeSide { runLeft, runRight, branch }
```

### 2.5 Component model

```dart
class PrefabComponent {
  final String id;             // UUID
  final ComponentBehaviour behaviour;
  final String spec;           // e.g. "ELBOW90-LR", "REDUCER-CONC", "FLG-WN-150"
  final int dnIn;              // inlet DN in mm
  final int dnOut;             // outlet DN (== dnIn unless behaviour=diameterChange)
  final EndConnection endA;
  final EndConnection endB;

  // Axial / branch CTE (millimetres)
  final int? cteA;             // CTE on side A — required for axial behaviours
  final int? cteB;             // CTE on side B
  final int? cteBranch;        // for axialWithBranch only

  // Physical-length components: face-to-face / face-to-end values
  final int? physicalLength;   // mm — required for physicalLength behaviours
  final int? faceOffsetA;      // distance from face A to the pipe cut, if any
  final int? faceOffsetB;

  // For tee: which side is the segment entering / exiting through
  final TeeSide? entrySide;
  final TeeSide? exitSide;

  // Position is still the on-canvas snap point inherited from `_Comp`
  final Offset pos;
  final int dir;
  final int? dir2;
}
```

### 2.6 Segment model

A **segment** is the bounded run between two prefab components (or between a component and a free end). The segment is what gets cut.

```dart
class PipeSegment {
  final String id;
  final String spoolId;        // see §5
  final PrefabComponent? compA; // null when free end
  final PrefabComponent? compB;
  final IsoDim? isoDim;         // user-entered dimension + ref type
  final int dn;                 // current diameter at this segment — set from
                                // diameterChange propagation
  final String? schedule;       // e.g. "Sch 40", "Sch 80S"
  final String? material;       // e.g. "A106-B", "316L"
  final List<WeldPoint> welds;  // auto-populated
  final Offset a, b;            // canvas geometry from existing _Seg
}

class IsoDim {
  final double valueMm;
  final DimRef ref;
}
```

### 2.7 Weld point

```dart
class WeldPoint {
  final String id;
  final String spoolId;
  final String number;           // "W-001", "F-002" (F = field), or spool-scoped
  final WeldType type;           // shop, field
  final EndConnection joint;     // butt, socket, etc.
  final String? componentAId;    // component on one side, may be null on a stub
  final String? componentBId;    // component on the other side
  final String? segmentId;       // segment the weld terminates, if applicable
  final int dn;                  // DN at the weld location (post-reducer DN
                                 // when the weld is downstream of a reducer)
  final String? schedule;
  final String? material;
  final NdtStatus? nde;          // RT, UT, MT, PT, VT — optional, for QC export
}

enum WeldType { shop, field }
```

### 2.8 Spool

```dart
class Spool {
  final String id;
  final String name;             // "SP-001"
  final String? lineNumber;      // e.g. '6"-CS-1001-A-150'
  final List<String> segmentIds;
  final List<String> componentIds;
  final List<String> weldIds;
}
```

## 3. Algorithm

### 3.1 Segmentation pass (rebuild after every mutation)

Walk the on-canvas items list and build segments by traversing adjacent items (component → pipe → component) along axis directions:

```
function buildSegments(items):
    segments := []
    visited := {}
    for each pipe in items where pipe.type == pipe:
        if pipe in visited: continue
        s := new Segment(pipe.a, pipe.b)
        s.compA := nearestComponentAt(pipe.a)
        s.compB := nearestComponentAt(pipe.b)
        s.dn    := inferDnFromUpstream(s)   // see 3.3
        s.welds := computeAutoWelds(s)      // see 3.4
        segments.add(s)
        visited.add(pipe)
    return segments
```

### 3.2 CUT-LENGTH math per segment

The dim is interpreted according to its `DimRef`. Pseudo-code:

```
function cutLength(segment):
    iso := segment.isoDim
    if iso == null: return UNDEF

    // Step 1 — subtract axial CTEs based on dim reference
    cut := iso.valueMm
    if iso.ref in [CTC, CTE]:
        if segment.compA != null and isAxial(segment.compA):
            cut -= cteOn(segment.compA, side facing segment)
        if segment.compB != null and isAxial(segment.compB):
            cut -= cteOn(segment.compB, side facing segment)
    elif iso.ref == CTF:
        // CTC on the axial side, physical face on the other
        if isAxial(segment.compA):
            cut -= cteOn(segment.compA, side facing segment)
        // physical side contributes 0 because dim already terminates at face
    elif iso.ref == FTF:
        // both ends are physical faces — no axial subtraction
        // (the physical components themselves were measured between)
        nothing
    elif iso.ref == FTE:
        // one physical face, one cut end — subtract the physical face's
        // physicalLength only if the ISO INCLUDES the body of that
        // component (user has to confirm at entry time — see UI §4)
        if segment.compA != null and isPhysical(segment.compA) and
           userAnsweredIsoIncludesCompA:
            cut -= segment.compA.physicalLength
    elif iso.ref == CTE:
        // axial on one end, free pipe end on the other — only the axial
        // contributes
        if isAxial(segment.compA):
            cut -= cteOn(segment.compA, side facing segment)

    // Step 2 — physical-length components anywhere in this segment
    // (e.g. reducer mid-segment) ALWAYS subtract their physical length
    // because the pipe physically has to clear them.
    for c in segment.midComponents:
        if behaviour == physicalLength or diameterChange:
            cut -= c.physicalLength

    return cut
```

### 3.3 Diameter propagation

A segment's `dn` is set by walking upstream from its compA along the drawing direction. If any prior component has `behaviour == diameterChange`, the segment's `dn` becomes that component's `dnOut`. Otherwise the project's default DN.

The same propagation feeds the weld map: a weld downstream of a reducer carries the downstream DN, not the upstream one.

### 3.4 Auto-weld pass

For every junction:

```
function computeAutoWelds(segment):
    welds := []
    if segment.compA != null:
        welds.add(WeldPoint(
            componentA = segment.compA,
            segment = segment,
            joint = segment.compA's end connection facing the segment,
            type = shop,                  // user can flip to field
            dn = segment.dn,
        ))
    if segment.compB != null:
        welds.add(WeldPoint(... similar ...))
    return welds
```

Component-to-component junctions (e.g. elbow → reducer without pipe between) also get one weld point inserted at the shared snap position.

Numbering: a separate pass after all segments are built sorts welds by `(spoolId, created_at)` and assigns `W-001`, `W-002` etc. Field welds prefix `F-` instead and increment a separate counter.

Special cases:
- Olet / sockolet / weldolet: TWO welds — `weldMain` (to the header pipe) and `weldBranch` (to the branch stub).
- Flange types: slipOn / weldNeck → 1 weld; lapJoint → 2 welds (stub end + lap ring); threaded → 0 welds.
- Cap: 1 weld (or 0 if threaded).

## 4. UI question flow

The notebook can't always infer `DimRef` — it depends on what the source drawing measured between. Defaults: CTC for axial-only segments, ask for everything else.

### 4.1 At pipe dim entry

When the user taps a pipe to enter a dim AND the segment touches at least one `physicalLength` or `faceOnly` component, the bottom-sheet adds a "Do jakiego punktu jest ten wymiar?" picker:

```
Wymiar ISO odnosi się do:
  ( ) osi obu komponentów                (CTC)
  ( ) osi jednego, czoła drugiego        (CTF)
  ( ) czoła obu                          (FTF)
  ( ) czoła i końca rury                 (FTE)
  ( ) osi i końca rury                   (CTE)
```

Pre-select CTC when both compA and compB are axial. Pre-select CTF when one is physical. The selection is saved per dim.

### 4.2 At reducer placement

A reducer cannot be placed silently. The tap-to-place flow opens:

```
Redukcja:
  z DN [dropdown]   →   do DN [dropdown]
  Długość: [   ] mm           (auto-fills from ASME B16.9 table)
  ISO uwzględnia długość redukcji?
    ( ) tak — odejmę długość
    ( ) nie — wymiar ISO kończy się przed redukcją
```

Same shape for valve, flange, strainer, expansion joint.

### 4.3 At tee placement

Tee orientation matters. The tap-to-place sheet shows the three sides and asks the user which is the run (segment entry / exit) and which is the branch. After placement, dragging a pipe out from the tee uses the chosen side's CTE.

## 5. Spool support

A spool is a contiguous prefab assembly. By default the notebook starts with one spool `SP-001`. The user can insert a **spool break** marker (already exists as `_Tool.spoolBreak`); welds on either side of a spool break become field welds (`F-NNN`) automatically.

`SpoolService.recompute(items)` walks the drawing, splits at spool-break markers and assigns every component / segment / weld to its spool.

## 6. Edge cases

| Case | Handling |
| --- | --- |
| Two physical components touching with no pipe | One weld between them; CUT for any incoming/outgoing pipe ignores them in axial pass, subtracts both `physicalLength`s explicitly. |
| Very short pipe between fittings | Validate `cut > 0`; if negative, surface the "Components longer than ISO" warning (already exists) AND highlight the dimension chip in red. |
| Multiple reducers in one segment | Each contributes `physicalLength` to the cut math; `dn` propagation cascades through each. |
| Eccentric reducer | Same math as concentric; mark visually only. |
| Mixed units | Dim entry accepts `1500`, `'59"`, `4'11"` — parser normalises to mm internally. |
| Missing component data | Component flagged "missing CTE" inline; cut math returns UNDEF; user prompted on next dim edit. |
| Custom fittings | `PrefabComponent.spec = "CUSTOM"` + manual `cteA/cteB/physicalLength`. |
| Mirrored elbow orientation | Already handled by `_isoHeadings` 6-way snap; algorithm uses `entrySide`. |

## 7. Migration strategy

Don't tear down the existing `_Comp` / `_Seg` model. Land it in phases so the user keeps a working app at every step:

### Phase 1 — Dim ref (backwards-compatible)
- Add `DimRef` enum.
- Extend `_CutCalc` with `ref` field, defaulting to `DimRef.centreToCentre` so existing drawings continue to compute identically.
- Add the 5-option picker to the dim sheet.
- Math: implement `cutLength()` for each ref type. Behaviour for `centreToCentre` matches today.

### Phase 2 — Component behaviour class
- Add `ComponentBehaviour` + classification map for the 13 existing `_Tool` symbols.
- Reducer, valve, flange components get a small spec sheet at placement time (DN, length).
- Math now respects `physicalLength` for components mid-segment.

### Phase 3 — Auto-weld generation
- New `WeldPoint` model + persistence.
- Painter renders auto-detected welds as the existing weld-dot symbol.
- BOM and cut-list export start including the weld counts and numbers.

### Phase 4 — Spool support
- `Spool` model + recompute on every mutation.
- Existing `_Tool.spoolBreak` becomes a real spool boundary instead of a decoration.
- Cut list groups per spool.

### Phase 5 — Diameter propagation
- `dn` field on `_Seg` populated by walking upstream of the segment until a `diameterChange` component or a free end.
- BOM groups segments by `(dn, schedule)`.

### Phase 6 — Tee sides + olet branch welds
- TeeSide picker at placement.
- Olet branch weld added in auto-weld pass.

### Phase 7 — Extension hooks (no UI yet)
- `AllowanceModel` for gap / shrinkage / bevel — `cutLength()` calls a no-op default.
- PCF / IFC export adapters write from the new model without touching painter code.

## 8. Files touched (estimate)

| Layer | New | Modified | Notes |
| --- | --- | --- | --- |
| Models | `lib/models/prefab/*.dart` (component, segment, weld, spool) | — | Pure data classes |
| Logic | `lib/services/prefab_engine.dart` | — | Stateless pure functions |
| ISO Notebook UI | — | `iso_notebook_screen.dart` (~3000 lines today) | Replace `_CutCalc.cutMm` + `_autoElbowDeductFor` with calls into `PrefabEngine` |
| Catalogs | — | `services/takeout_catalog.dart`, `data/elbow_takeouts.dart` | Map to new `ComponentBehaviour` |
| Export | — | `services/iso_pdf_export.dart` | Cut list rendered from `PrefabEngine.summary()` |
| Persistence | — | (none today) | Drawings live in memory only — same here |
| Tests | `test/services/prefab_engine_test.dart` | — | Mandatory for this rewrite |

## 9. Risk + mitigation

| Risk | Mitigation |
| --- | --- |
| Breaks existing drawings | Phased migration; Phase 1 has identical behaviour on defaults. |
| User overwhelmed by question flow | Smart defaults per behaviour; the picker only opens for ambiguous cases. |
| Edge cases discovered mid-implementation | Write the `prefab_engine_test.dart` suite first; every spec example above becomes a test. |
| Painter perf regresses | Engine runs as a pure function over the items list, cached by a content hash. |

## 10. Out-of-scope for this design

Hand-waved for now, captured for later:
- 3D / AR visualisation
- Automatic stock-bar nesting
- NDE / QC scheduling
- Welder assignment + heat number tracking
- Multi-line drawing on one canvas

---

**Next step** before any code: user signs off on Phase 1 scope. We then implement Phase 1 + 2 together (smallest useful slice that captures the user's spec) and ship that. Phase 3-7 follow as separate PRs.
