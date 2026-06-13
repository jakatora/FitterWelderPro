# FitterWelderPro - promo_assets

Source SVG package for FitterWelderPro store listings, social posts, and press kit. All assets are illustrative mockups built from the brand palette - they are NOT exports from a real device. For genuine App Store / Play Store submission, see the "Real-device capture" note at the bottom.

## How to view

1. Open `index.html` in any modern browser (no server, no remote resources needed):
   - Windows: double-click `index.html`, or `start index.html` from PowerShell in this folder.
   - macOS / Linux: `open index.html` / `xdg-open index.html`.
2. The viewer shows screenshots 4-per-row, then banners grouped by landscape / square / portrait. Each tile has a `Download SVG` link.

## How to export PNG

```powershell
# from this folder
powershell -ExecutionPolicy Bypass -File .\convert_to_png.ps1
# force overwrite if PNGs already exist:
powershell -ExecutionPolicy Bypass -File .\convert_to_png.ps1 -Force
```

The script:

1. Tries `inkscape` from `PATH` (preferred - clean vector rasterizer, exact viewBox dimensions).
2. Falls back to `msedge.exe --headless=new --screenshot` with each SVG wrapped in a tiny temp HTML at the SVG's native viewBox size.

Output is written to `promo_assets/png/` (created if missing). Per-file progress is printed and a final `converted / failed` summary is shown at the end.

### Install Inkscape (optional, recommended)

- Winget: `winget install --id Inkscape.Inkscape`
- Or download: <https://inkscape.org/release/>

## Asset inventory

### Screenshots (1290 x 2796 px, iPhone 6.9" App Store class)

| File                              | Spec               | PL caption                                                                                              | EN caption                                                                                | Suggested use                              |
|-----------------------------------|--------------------|---------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|--------------------------------------------|
| `screenshots/fwp_screen_01.svg`   | 1290 x 2796 SVG    | Stempel spawacza JK-014, lista skrotow do narzedzi (ISO scanner, lista ciec, dziennik spoin).           | Welder stamp JK-014 home with shortcuts to ISO scanner, cut list, welding log.            | App Store screenshot #1, store hero        |
| `screenshots/fwp_screen_02.svg`   | 1290 x 2796 SVG    | Lista ciec z parsera ISO - 5 odcinkow DN150 SCH40, suma 1450 mm.                                        | Cut list from ISO parser - 5 pieces DN150 SCH40, total 1450 mm.                           | App Store screenshot #2                    |
| `screenshots/fwp_screen_03.svg`   | 1290 x 2796 SVG    | Rolling offset - rise / spread / advance dla skosu rurowego DN150.                                      | Rolling offset calculator - rise / spread / advance for DN150 pipe takeoff.               | App Store screenshot #3                    |
| `screenshots/fwp_screen_04.svg`   | 1290 x 2796 SVG    | Szablon siodelka - OD main 168.3, OD branch 60.3 (Stempel JK-014).                                      | Saddle template - OD main 168.3, OD branch 60.3 (Stamp JK-014).                           | App Store screenshot #4                    |
| `screenshots/fwp_screen_05.svg`   | 1290 x 2796 SVG    | Dziennik spoin SP-2026-014 - statusy PENDING, w NDT, do poprawy, TOTAL.                                 | Welding log SP-2026-014 - statuses PENDING, in NDT, rework, TOTAL.                        | App Store screenshot #5                    |
| `screenshots/fwp_screen_06.svg`   | 1290 x 2796 SVG    | Chat AI - tutor spawalniczy (P-No, preheat, PWHT, WPS, ISO 5817), oparty o Claude Haiku.                | AI chat - welding tutor (P-No, preheat, PWHT, WPS, ISO 5817), powered by Claude Haiku.    | App Store screenshot #6, "AI" highlight    |
| `screenshots/fwp_screen_07.svg`   | 1290 x 2796 SVG    | Heat input - kalkulator energii liniowej, tolerancja WPS +/-10% (ISO/TR 17671-1).                       | Heat input calculator with WPS +/-10% band per ISO/TR 17671-1.                            | App Store screenshot #7                    |
| `screenshots/fwp_screen_08.svg`   | 1290 x 2796 SVG    | Ciecie z pretow - 12 m pret O 60.3 x 3.2 S235, rzaz pily 2 mm, optymalizacja odpadu.                    | Bar nesting - 12 m bar O 60.3 x 3.2 S235, 2 mm saw kerf, scrap optimization.              | App Store screenshot #8                    |

### Banners

| File                                     | Spec               | PL caption                                                                                | EN caption                                                                            | Suggested use                              |
|------------------------------------------|--------------------|-------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------|--------------------------------------------|
| `banners/fwp_banner_01_landscape.svg`    | 1200 x 628 SVG     | Hero: piping + ISO + welding log, projekt RUR-2026-014 (12 poz., ISO 3834 ready).         | Hero: piping + ISO + welding log, project RUR-2026-014 (12 pos., ISO 3834 ready).     | OG image, Facebook/X share, blog hero      |
| `banners/fwp_banner_02_landscape.svg`    | 1200 x 628 SVG     | Claim "Czyta ISO tak jak Ty" - LINE 14-A, DN80 S/40, REV.02, takeoff 1450 mm.             | Claim "Reads ISO the way you do" - LINE 14-A, DN80 S/40, REV.02, 1450 mm takeoff.     | LinkedIn link preview, OG image variant    |
| `banners/fwp_banner_03_square.svg`       | 1200 x 1200 SVG    | 90 kalkulatorow, OFFLINE READY, v2.4 PL/EN/DE, zero reklam.                               | 90 calculators, OFFLINE READY, v2.4 PL/EN/DE, zero ads.                               | Instagram feed, LinkedIn carousel cover    |
| `banners/fwp_banner_04_square.svg`       | 1200 x 1200 SVG    | Pipe Fitter & Welder Toolkit - stempel JK-014/WP-022, kafelki Cut list / Welding log.     | Pipe Fitter & Welder Toolkit - stamp JK-014/WP-022, Cut list / Welding log tiles.     | Instagram feed, App Store promo square     |
| `banners/fwp_banner_05_portrait.svg`     | 1200 x 1500 SVG    | Opinia terenowa: DN 150 SCH 40 A106 GR.B, L = 2350 mm, amp 145, weld JK-014.              | Field testimonial: DN 150 SCH 40 A106 GR.B, L = 2350 mm, amp 145, weld JK-014.        | Instagram Stories, Pinterest pin           |
| `banners/fwp_banner_06_portrait.svg`     | 1200 x 1500 SVG    | Compliance pillar - ISO 3834 Part 2 + EN ISO 9606, "AUDIT READY".                         | Compliance pillar - ISO 3834 Part 2 + EN ISO 9606, "AUDIT READY".                     | LinkedIn portrait, sales deck cover        |

## Brand palette

| Token              | Hex       | Use                                              |
|--------------------|-----------|--------------------------------------------------|
| `accent`           | `#F5A623` | Primary orange (CTAs, headings, brand mark)      |
| `accent-2`         | `#E8C14B` | Gold gradient stop, hover state                  |
| `accent-deep`      | `#D88A12` | Glove / pipe shadow (banner illustrations)       |
| `accent-darkest`   | `#A86508` | Deep shadow on saturated orange surfaces         |
| `bg`               | `#0F1115` | Page background (true workshop dark)             |
| `panel`            | `#1A1D26` | Tile/panel base                                  |
| `panel-2`          | `#1F2330` | Tile gradient top stop                           |
| `border`           | `#2C3354` | Hairline borders, grid pattern                   |
| `text`             | `#E8ECF0` | Primary text                                     |
| `muted`            | `#8A93A8` | Captions, secondary labels                       |
| `ok`               | `#2ECC71` | Battery / success indicators                     |

Typography in the SVGs: `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif` - no external webfonts, so the assets render identically on any modern OS.

## Real-device capture (for the actual store submission)

The SVGs in this folder are **promotional mockups**, not real device output. App Store Connect and Play Console reviewers expect screenshots from a real device or an official simulator. For FitterWelderPro:

### iOS (1290 x 2796 - iPhone 6.9" required size class)

1. Run the app on iPhone 16 Pro Max simulator in Xcode, or on a real iPhone 15/16 Pro Max.
2. In simulator: `Device -> Trigger Screenshot` (saves to Desktop at exactly 1290 x 2796).
3. On real device: side button + volume up, then AirDrop to Mac.
4. Drop into App Store Connect -> Media Manager -> "iPhone 6.9 Display".

For our flow, iOS builds go through **Codemagic** (Team ID `B7J6A7R258`, profiles in `codemagic.yaml`) - do not attempt local iOS archives.

### Android (1290 x 2796 acceptable, or use a Pixel emulator)

1. In Android Studio: `Tools -> Device Manager -> Create Device -> Pixel 8 Pro` (1344 x 2992).
2. Run the release APK (`build_apk_release.bat` at repo root). Keystore is in `c:\Users\Startklaar\Documents\cut_list_app_new\upload-keystore.jks` - copy to `android/key.properties` if missing.
3. In the emulator toolbar (camera icon) or via `adb exec-out screencap -p > shot.png`.
4. Upload to Play Console -> Store presence -> Main store listing -> Phone screenshots.

### General checklist before submission

- [ ] Replace mockup screenshots in store listings with real-device captures (8 per platform).
- [ ] Verify status bar reads `9:41` (iOS convention) or hide it for Android with `adb shell settings put global sysui_demo_allowed 1` + demo mode.
- [ ] Keep banner SVGs for OG image / social - reviewers don't see them, so mockups are fine here.
- [ ] App Store metadata: NO emojis in Subtitle / Promo Text / Description / What's New / Keywords. Bullet `*` is OK. (See user memory note `feedback_no_emoji_app_store`.)
