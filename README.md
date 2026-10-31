# Fitter Welder Pro

A field-grade Flutter app for pipe fitters and welders on industrial sites
(refineries, chemical plants, food/pharma, power). It turns a phone in a
chest pocket into a cut-list builder, a notebook of pipe routes, and a
pocket reference for the calculations everyone redoes a dozen times a day.

Built for hands in gloves: dark theme, large touch targets, long-press to
copy any result to the clipboard, haptic confirmation on save, fully
offline-capable (local SQLite).

## Modules

### Fitter

- **Cut list** — projects with diameter / wall thickness, segment builder
  (START + END components + ISO expression → CUT), and a BOM/material list
  built from the segments and component library.
- **Component library** — global catalogue of elbows (ELB90/45), tees,
  reducers, valves, flanges (SS / CS).
- **Calculators (8 tabs):** pipe slope, elbow cut to target angle, elbow
  rotation, insert (face-to-face), reducer trimming, pipe weight, bevel,
  thermal expansion. Every numeric result long-press-copies.
- **Pipe route calculator**, **rolling offset**, **saddle/fish-mouth cut**,
  **route measure** (tape → C-C with outer/centre/inner reference).
- **DN ↔ mm + NPS** quick reference.
- **Elbow takeouts** — centre-to-face for LR/SR 90° and 45° from DN15 to
  DN600 per ASME B16.9 / B16.28. Long-press a value to copy it.
- **Unit converter** — length (mm/cm/m/in/ft), temperature (°C/°F/K),
  pressure (bar/MPa/kPa/psi/atm), gas flow (l/min/slpm/cfh/scfh).
- **ISO Notebook** — isometric grid for sketching routes with line tools
  and snap-to-grid components.
- **Heat photos** — attach material certificate photos to a project.

### Welder

- **Pipes** — AMP reference currents, shielding gas mixes, approved WPS sets
  and a personal parameter library.
- **Tanks** — AMP and tandem-TIG parameters for circumferential/longitudinal
  tank welds.
- **Welder calculators** — heat input (kJ/mm), preheat temperature from
  CEV/IIW, O₂ purge volume + time, arc-time timer.
- **Weld journal** — log welds with date, weld number and OK/NOK/Pending
  status; export to PDF or CSV.

## ISO expression syntax

The segment builder accepts the same expressions a fitter reads from an ISO:

| Input                | Result   | Notes                                                    |
|----------------------|----------|----------------------------------------------------------|
| `3000`               | 3000     | plain dimension                                          |
| `3000+525-80`        | 3445     | additive measurements along a run                        |
| `5*200+150`          | 1150     | five spool segments of 200 mm + a tail                   |
| `(1500+200)*2+100`   | 3500     | parentheses + multiplication                             |
| `1020,5 + 20`        | 1040.5   | comma → dot, whitespace ignored                          |
| `5×200`, `5x200`     | 1000     | `×`, `x`, `X`, `·` are all multiplication                |

## Run

Verified toolchain: Flutter 3.47.5 with Dart 3.13.4. The committed dependency
lock requires Flutter ≥ 3.44.0 and Dart ≥ 3.12.0. Use the same SDK for dependency
resolution, analysis, tests and builds. Desktop targets are enabled for
Windows / Linux / macOS so the same code runs on a workshop laptop.

```bash
flutter pub get
flutter run -d windows   # or -d android, -d ios, -d linux, -d macos
```

Release builds:

```bash
flutter build apk --release          # Android sideload
flutter build appbundle              # Play Store
flutter build windows --release      # Desktop
```

iOS builds run through the `ios-testflight` workflow in `codemagic.yaml`
on Codemagic.

For the verified Windows setup, the Android debug helper selects the SDK
explicitly and handles the Java socket fallback:

```powershell
.\scripts\build_android_debug_windows.ps1
```

## Field UX choices

- **Long-press to copy** any calculator result — no retyping into chats or
  the weld journal while wearing gloves.
- **Haptic feedback** on save and on copy — visible confirmation when the
  screen is hard to read in sunlight.
- **Comma or dot** for decimals, `×`/`x`/`*` for multiplication — match the
  way numbers are actually drawn on ISOs.
- **Offline-first** — SQLite local DB, no requirement for a site connection.
- **Bilingual UI** — Polish / English, toggle in the top-right.

## Code layout

```
lib/
  app.dart                 # Material theme + AppLanguageScope
  main.dart                # entry; FFI bootstrap on desktop
  data/                    # NPS table, elbow takeouts, AppDatabase
  database/                # DAOs (sqflite)
  i18n/, l10n/             # PL / EN
  models/                  # Project, Segment, LibraryComponent, WeldParam…
  screens/                 # All UI screens (one per route)
  services/                # iso_parser, cut_calculator, bar_nesting,
                           # material_list_builder, pdf_export, auth, …
  utils/                   # haptic, clipboard_helper, validators, rod_optimizer
  widgets/                 # HelpButton, ComponentIcon, Pipe3DPreview, …
test/                      # Dart unit tests
```

## Tests

```bash
flutter analyze
flutter test --concurrency=1
```

The serial test command is used for the full suite in the verified Windows
environment. Tests cover calculators and ISO parsing, database migrations and
backup restoration, account boundaries, reminders, exports, assistant actions
and widget flows. Passing tests and builds do not replace runtime checks on
a device for system notifications, camera access or other platform features.

## Releases

See `RELEASE_CHECKLIST.md`, `PLAY_RELEASE_NOTES_PL_EN.md`, and the iOS
notes in `appstore_metadata.md`.
