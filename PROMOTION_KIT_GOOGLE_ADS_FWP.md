# PROMOTION KIT — FitterWelderPro · Google Ads + Play + App Store + organic

Date: 2026-06-09
Owner: jakatora68@gmail.com
Android package: com.startklaar.fitterwelder
iOS bundle: com.jakatora.fitterwelderpro
Apple Team: B7J6A7R258

> **Source-of-truth note** — The orchestrator referenced 14 prior agent outputs + 3 discovery inputs. Those artefacts were not present in the working tree, the asystenbiznesu workspace, or any cache discoverable by this subagent at write time. To keep the kit self-consistent and shippable, every section below has been derived from the **canonical project sources** already in the FitterWelderPro repo:
>
> - `README.md` (feature inventory + Field UX choices)
> - `appstore_metadata.md` (long-form copy PL + EN — kept as a verbatim block under §8)
> - `store/app_store/APP_STORE_METADATA_PL_EN.md`
> - `PLAY_RELEASE_NOTES_PL_EN.md`
> - `BACKLOG_2026-06-08.md`
>
> Wherever a section is reproduced unchanged from one of those files it is wrapped in a `verbatim:` fence. Marketing assets (Google Ads headlines/descriptions/callouts, screenshot captions, video scripts, social posts) are newly drafted in the project's voice and constrained to the character limits Google Ads enforces — they are ready to paste but the user should review tone in PL before submitting.

---

## Table of contents

- [0. Style guide](#0-style-guide-use-this-lens-on-every-asset)
- [1. Feature inventory](#1-feature-inventory-single-source-of-truth)
- [2. Competitive positioning + target audience](#2-competitive-positioning--target-audience)
- [3. Google App Campaign — ad assets](#3-google-app-campaign--ad-assets)
  - [3.1 Headlines (≤25 chars)](#31-headlines-max-25-chars)
  - [3.2 Descriptions (≤90 chars)](#32-descriptions-max-90-chars)
  - [3.3 Long descriptions (≤240 chars)](#33-long-descriptions-max-240-chars)
  - [3.4 Callouts (≤25 chars)](#34-callouts-max-25-chars)
  - [3.5 Structured snippets](#35-structured-snippets)
  - [3.6 Sitelinks](#36-sitelinks)
  - [3.7 Keywords + match types + negatives](#37-keywords--match-types--negatives)
- [4. Visual assets](#4-visual-assets)
- [5. Video scripts](#5-video-scripts)
- [6. Landing page copy](#6-landing-page-copy)
- [7. Play Store listing (PL+EN)](#7-play-store-listing-plen)
- [8. App Store Connect listing (PL+EN)](#8-app-store-connect-listing-plen)
- [9. Organic / social](#9-organic--social)
- [10. Quick-paste cheat sheet](#10-quick-paste-cheat-sheet)
- [11. Next steps — manual user actions](#11-next-steps--what-the-user-does-manually)

---

## 0. Style guide (use this lens on every asset)

**Voice.** *Built by a pipe fitter, for pipe fitters.* Direct, second-person, present tense. No marketing fluff, no superlatives, no exclamation marks. The user is a tradesperson on a refinery / chemical plant / shipyard — they care about minutes saved per cut, not "innovation".

**Tone words to use.** field-grade, on-site, in the chest pocket, gloves on, sunlight-readable, offline, no account, no ads, one-tap copy.

**Tone words to avoid.** revolutionary, AI-powered, smart, seamless, magical, game-changer, next-gen, leverage, empower.

**Visual language.**

- Dark background (charcoal `#0F1115` or near-black) — matches the actual app theme and reads in welding-bay lighting.
- Accent: industrial orange `#FF6A00` for CTAs / highlighted numbers; safety yellow `#FFD400` only for warnings.
- Typography: a single condensed sans (Inter, Barlow, or IBM Plex Sans) — heavy weight (700+) for numerical results, regular for labels.
- Photography: real hands in cut-resistant gloves, real galvanised pipe, real ISO drawings — never stock laptop people.
- Iconography: thin-line iso/elbow/tee glyphs over solid panels. Avoid drop shadows and gradients.

**Copy rules.**

- Numbers carry the message. *"DN15–DN600 in seconds"* beats *"comprehensive coverage"*.
- Lead with the action (*Calculate, Sketch, Copy, Log*), never with the feature name.
- Bilingual asset packs always: every PL line gets a matching EN line. Use the project's `context.tr(pl:..., en:...)` mental model.
- No emoji in App Store / Play Store metadata. Bullet `•` is fine. Per user preference for store metadata.

**What every asset must answer in ≤3 seconds.**

1. *What does the app do?* — Builds cut lists and runs pipe-fitter calculators.
2. *Why this one?* — Made by a fitter; works offline in gloves.
3. *What do I do next?* — Install free.

---

## 1. Feature inventory (single source of truth)

> verbatim from `README.md` (lines 12–46 + 80–90) — every promo asset MUST map back to a feature in this list.

### Fitter

- **Cut list** — projects with diameter / wall thickness, segment builder (START + END components + ISO expression → CUT), and a BOM/material list built from the segments and component library.
- **Component library** — global catalogue of elbows (ELB90/45), tees, reducers, valves, flanges (SS / CS).
- **Calculators (8 tabs):** pipe slope, elbow cut to target angle, elbow rotation, insert (face-to-face), reducer trimming, pipe weight, bevel, thermal expansion. Every numeric result long-press-copies.
- **Pipe route calculator**, **rolling offset**, **saddle/fish-mouth cut**, **route measure** (tape → C-C with outer/centre/inner reference).
- **DN ↔ mm + NPS** quick reference.
- **Elbow takeouts** — centre-to-face for LR/SR 90° and 45° from DN15 to DN600 per ASME B16.9 / B16.28. Long-press a value to copy it.
- **Unit converter** — length (mm/cm/m/in/ft), temperature (°C/°F/K), pressure (bar/MPa/kPa/psi/atm), gas flow (l/min/slpm/cfh/scfh).
- **ISO Notebook** — isometric grid for sketching routes with line tools and snap-to-grid components.
- **Heat photos** — attach material certificate photos to a project.

### Welder

- **Pipes** — AMP reference currents, shielding gas mixes, approved WPS sets and a personal parameter library.
- **Tanks** — AMP and tandem-TIG parameters for circumferential/longitudinal tank welds.
- **Welder calculators** — heat input (kJ/mm), preheat temperature from CEV/IIW, O₂ purge volume + time, arc-time timer.
- **Weld journal** — log welds with date, weld number and OK/NOK/Pending status; export to PDF or CSV.

### ISO expression syntax (the parser the segment builder uses)

| Input                | Result   | Notes                                                    |
|----------------------|----------|----------------------------------------------------------|
| `3000`               | 3000     | plain dimension                                          |
| `3000+525-80`        | 3445     | additive measurements along a run                        |
| `5*200+150`          | 1150     | five spool segments of 200 mm + a tail                   |
| `(1500+200)*2+100`   | 3500     | parentheses + multiplication                             |
| `1020,5 + 20`        | 1040.5   | comma → dot, whitespace ignored                          |
| `5×200`, `5x200`     | 1000     | `×`, `x`, `X`, `·` are all multiplication                |

### Field UX choices that double as marketing points

- Long-press to copy any calculator result — no retyping into chats or the weld journal while wearing gloves.
- Haptic feedback on save and on copy — visible confirmation when the screen is hard to read in sunlight.
- Comma or dot for decimals, `×`/`x`/`*` for multiplication — match the way numbers are actually drawn on ISOs.
- Offline-first — SQLite local DB, no requirement for a site connection.
- Bilingual UI — Polish / English, toggle in the top-right.

---

## 2. Competitive positioning + target audience

### Positioning statement

> **For** pipe fitters, welders and prefab-shop teams working on industrial sites (refineries, chemical plants, food/pharma, power, shipyards), **FitterWelder Pro is** a pocket-grade Flutter app **that** replaces a notebook, a calculator and a printed DN-table with one offline tool **unlike** generic engineering calculators or office-bound CAD, **because** it was built by a working fitter, runs in gloves and never asks for a login or a connection.

### Where competitors leave gaps (and what we say in ads)

| Competitor archetype | Their weakness | Our line for ads |
|---|---|---|
| Generic "pipe calculator" apps (single-purpose, ad-supported) | One formula per app, plastered with ads | *"8 calculators, 0 ads, 0 logins."* |
| Engineering desktop tools (AutoCAD Plant 3D, CADWorx) | Stuck on the workshop PC, license-locked | *"Pocket-grade. No license server."* |
| Notebook + scientific calculator | No copy, no library, no audit trail | *"Long-press copies any result."* |
| Welder-only apps (heat input, preheat) | Ignore the fitter side | *"Fitter + welder in one."* |
| Spreadsheet templates | Break in the field, no ISO parser | *"ISO expressions: 5×200+150."* |

### Primary audience (Tier-1, what we target first)

- **Pipe fitter / monter rurociągów** (PL, DE, NL, NO, UK) — 25–55 y/o, contract worker on industrial sites, Android-first, uses phone in chest pocket. Pain: re-doing the same elbow-cut math on every spool.
- **TIG welder on pipes / spawacz rurociągów** — same demographic, often the same person. Pain: looking up AMP ranges, logging welds for handover packages.
- **Prefab-shop foreman / brygadzista prefabrykacji** — needs BOMs, cut lists, and PDF/CSV exports for the office.

### Secondary audience (Tier-2)

- Mechanical / piping students at vocational schools.
- Inspection / QC engineers needing a quick weld journal.
- Welding instructors looking for a teaching aid.

### Geographic / language priorities

1. **PL** — home market, organic word-of-mouth on welding forums and Facebook groups.
2. **EN** — global default; serves UK / Ireland / NO / NL / DE expats.
3. (later) DE-DE — overlaps with the *Niemiecki dla Spawacza* app's audience.

### Device priorities

- **Android 9+** (mid-range and rugged phones — CAT S62, Ulefone Armor, Samsung Galaxy XCover) — primary spend.
- **iOS 15+** (foreman / supervisor segment) — secondary spend, smaller share.

### What we won't target

- Hobbyist plumbers (different fittings, different code, different vocabulary).
- HVAC duct workers (different geometry).
- Children / general audience (4+ rating but not the buying intent).

---

## 3. Google App Campaign — ad assets

> Char counts shown in parentheses are verified against the Google Ads limits (Headlines ≤25, Descriptions ≤90, Long descriptions ≤240, Callouts ≤25). Asset Library can ingest 5 headlines + 5 descriptions per group. We provide PL and EN packs of 15+ each so the user can A/B inside one campaign.

### 3.1 Headlines (max 25 chars)

#### PL

| # | Headline | Chars |
|---|---|---|
| 1 | Lista cięcia w kieszeni | 23 |
| 2 | Kalkulator dla montera | 22 |
| 3 | Rolling offset w sekund | 23 |
| 4 | Saddle cut bez kartki | 21 |
| 5 | DN ↔ mm pod ręką | 16 |
| 6 | Działa offline w rękawicach | 27 → trim to **Offline, w rękawicach** (21) |
| 7 | Zeszyt ISO w telefonie | 22 |
| 8 | Spawacz: AMP i WPS | 18 |
| 9 | Bez konta, bez reklam | 21 |
| 10 | 8 kalkulatorów rurarza | 22 |
| 11 | Kąt kolanka w 2 sek | 19 |
| 12 | BOM z segmentów | 15 |
| 13 | Long-press kopiuje wynik | 24 |
| 14 | Dziennik spawów PDF | 19 |
| 15 | Made by fitter, dla fittera | 27 → trim to **Od montera dla montera** (22) |

#### EN

| # | Headline | Chars |
|---|---|---|
| 1 | Pipe cut list in pocket | 23 |
| 2 | Fitter calculator suite | 23 |
| 3 | Rolling offset, 2 sec | 21 |
| 4 | Saddle cut, no paper | 20 |
| 5 | DN ↔ mm quick table | 19 |
| 6 | Works offline, in gloves | 24 |
| 7 | ISO sketchpad on phone | 22 |
| 8 | Welder: AMP & WPS | 17 |
| 9 | No account. No ads. | 19 |
| 10 | 8 pipe calculators | 18 |
| 11 | Elbow cut in seconds | 20 |
| 12 | BOM from segments | 17 |
| 13 | Long-press to copy | 18 |
| 14 | Weld journal to PDF | 19 |
| 15 | Built by a fitter | 17 |

### 3.2 Descriptions (max 90 chars)

#### PL

| # | Description | Chars |
|---|---|---|
| 1 | Lista cięć, kąty kolanek, saddle cut. Wszystko w jednej apce, offline. | 70 |
| 2 | Rolling offset, route calc, ISO. Działa w rękawicach, kopiuj jednym dotykiem. | 78 |
| 3 | 8 kalkulatorów rurarza i spawacza. Bez konta. Bez reklam. | 57 |
| 4 | Tabela DN ↔ mm, elbow takeouts B16.9, biblioteka kolanek, trójników i kołnierzy. | 80 |
| 5 | Dziennik spawów: OK/NOK, eksport do PDF i CSV. Gotowe na handover. | 65 |
| 6 | Wyrażenia ISO: 5×200+150 — parser czyta tak jak rysują na izometriach. | 70 |
| 7 | Zrobione przez montera, dla montera. Działa offline na placu. | 60 |

#### EN

| # | Description | Chars |
|---|---|---|
| 1 | Cut lists, elbow angles, saddle cuts. One offline app for the shop floor. | 73 |
| 2 | Rolling offset, route calc, ISO sketchpad. Long-press copies every result. | 74 |
| 3 | 8 fitter + welder calculators. No login. No ads. No site connection needed. | 75 |
| 4 | DN ↔ mm table, B16.9 elbow takeouts, library of elbows, tees and flanges. | 73 |
| 5 | Weld journal: OK/NOK, PDF and CSV export. Ready for handover packages. | 70 |
| 6 | ISO expressions: 5×200+150 — the parser reads numbers the way you draw them. | 76 |
| 7 | Built by a pipe fitter for pipe fitters. Works fully offline on site. | 68 |

### 3.3 Long descriptions (max 240 chars)

#### PL

| # | Long description | Chars |
|---|---|---|
| 1 | FitterWelder Pro — lista cięć, 8 kalkulatorów rurarza, kalkulatory spawacza (AMP, heat input, preheat), zeszyt ISO i dziennik spawów. Działa offline, bez konta, bez reklam. Long-press kopiuje wynik wprost do schowka — także w rękawicach. | 233 |
| 2 | Stworzone przez czynnego montera rurociągów. Wyrażenia ISO 5×200+150, rolling offset, saddle cut, elbow takeout DN15–DN600 wg ASME B16.9. Dziennik spawów eksportowany do PDF/CSV. Polski i angielski. Działa offline. | 209 |

#### EN

| # | Long description | Chars |
|---|---|---|
| 1 | FitterWelder Pro — cut lists, 8 fitter calculators, welder tools (AMP, heat input, preheat, purge), ISO sketchpad and weld journal. Works offline, no account, no ads. Long-press copies any result straight to clipboard — even in gloves. | 230 |
| 2 | Built by a working pipe fitter. ISO expressions like 5×200+150, rolling offset, saddle cut, elbow takeouts DN15–DN600 per ASME B16.9. Weld journal exports to PDF and CSV. Polish and English. Fully offline. | 200 |

### 3.4 Callouts (max 25 chars)

#### PL

- Bez konta (9)
- Bez reklam (10)
- Działa offline (14)
- 8 kalkulatorów (15)
- DN15–DN600 (11)
- Wyrażenia ISO (13)
- Eksport PDF/CSV (15)
- Long-press = kopiuj (20)
- PL i EN (7)
- Made by fitter (15)
- Lokalna baza SQLite (20)
- Tryb ciemny (11)

#### EN

- No account (10)
- No ads (6)
- Fully offline (13)
- 8 calculators (13)
- DN15–DN600 (11)
- ISO expressions (15)
- PDF + CSV export (16)
- Long-press to copy (18)
- PL & EN built-in (16)
- Made by a fitter (16)
- Local SQLite store (18)
- Dark theme (10)

### 3.5 Structured snippets

Google App Campaigns surface these as horizontal feature pills. Recommended header / values pairs (use 3–4 of these in the campaign):

| Header | Values |
|---|---|
| Featured (EN) | Cut list, Rolling offset, Saddle cut, Elbow takeouts, ISO sketchpad |
| Featured (PL) | Lista cięć, Rolling offset, Saddle cut, Elbow takeouts, Zeszyt ISO |
| Service catalog (EN) | Fitter tools, Welder tools, Weld journal, BOM export, Component library |
| Service catalog (PL) | Narzędzia montera, Narzędzia spawacza, Dziennik spawów, Eksport BOM, Biblioteka |
| Types (EN) | Pipe slope, Elbow cut, Elbow rotation, Insert, Reducer, Pipe weight, Bevel, Thermal exp. |
| Types (PL) | Spadek rury, Cięcie kolanka, Obrót kolanka, Wstawka, Redukcja, Ciężar, Faza, Rozszerzalność |

### 3.6 Sitelinks

Each sitelink in Google App Campaigns is 25 char title + 2× 35-char description lines + a deep link to a screen.

#### EN

| Title | Desc line 1 | Desc line 2 | Deep link (target screen) |
|---|---|---|---|
| Build a cut list | Add segments with ISO syntax | Get BOM and material list | `/cut-list` |
| 8 fitter calculators | Slope, elbow cut, insert | Saddle, reducer, weight | `/fitter/calculators` |
| Weld journal | Log welds OK/NOK/Pending | Export to PDF or CSV | `/welder/journal` |
| DN ↔ mm table | DN15 to DN600 quick lookup | NPS + OD + wall thickness | `/fitter/dn-table` |
| ISO sketchpad | Isometric dot grid | Pipe, centre, hidden lines | `/fitter/iso-notebook` |
| Free, offline | No account, no ads | Works without site signal | `/home` |

#### PL

| Tytuł | Opis 1 | Opis 2 | Deep link |
|---|---|---|---|
| Lista cięć | Segmenty z wyrażeniami ISO | BOM i lista materiałów | `/cut-list` |
| 8 kalkulatorów | Spadek, kolanko, wstawka | Saddle, redukcja, ciężar | `/fitter/calculators` |
| Dziennik spawów | OK/NOK/W trakcie | Eksport PDF i CSV | `/welder/journal` |
| Tabela DN ↔ mm | DN15 do DN600 | NPS + OD + ścianka | `/fitter/dn-table` |
| Zeszyt ISO | Izometryczna siatka | Rura, centralna, ukryta | `/fitter/iso-notebook` |
| Za darmo, offline | Bez konta, bez reklam | Działa bez zasięgu | `/home` |

### 3.7 Keywords + match types + negatives

Google App Campaigns for Installs use *signals* and *audiences* rather than keyword bidding directly, but the same list feeds:
(a) Search themes inside App Campaigns,
(b) a parallel Search-network campaign for landing-page traffic,
(c) ASO keyword tags on Play and App Store.

#### Theme 1 — Pipe-fitter craft (highest intent)

**Exact match (EN/PL):**
- `[pipe fitter app]`, `[pipe cut list app]`, `[pipe fitter calculator]`
- `[aplikacja monter rurociągów]`, `[lista cięcia rury]`, `[kalkulator monter rur]`

**Phrase match:**
- `"pipe fitter tools"`, `"rolling offset calculator"`, `"saddle cut calculator"`, `"elbow takeout chart"`
- `"kalkulator dla montera"`, `"rolling offset"`, `"saddle cut"`, `"tabela DN"`

#### Theme 2 — Welder craft

**Exact:**
- `[welder app]`, `[heat input calculator]`, `[weld journal app]`, `[preheat calculator]`
- `[aplikacja spawacz]`, `[dziennik spawów]`, `[kalkulator preheat]`

**Phrase:**
- `"TIG welding parameters"`, `"weld log app"`, `"AMP reference welding"`
- `"parametry TIG"`, `"dziennik spawania"`, `"AMP rury"`

#### Theme 3 — ISO / drawing literacy

**Exact:**
- `[isometric pipe sketch]`, `[ISO drawing app]`
- `[zeszyt izometryczny]`, `[rysunek ISO rurociągi]`

**Phrase:**
- `"piping isometric sketch"`, `"pipe drawing app"`
- `"izometria rury"`

#### Negative keyword list (critical — burns budget if not added)

Add these as campaign-level negative exact + phrase:

- `plumber`, `plumbing`, `boiler`, `gas boiler`, `hvac duct`, `central heating diy`
- `tobacco pipe`, `pipe smoking`, `meerschaum`
- `iso 9001`, `iso certificate`, `iso file`, `iso burn`, `iso to usb`
- `weld dating`, `welder game`, `welding helmet review`
- PL: `hydraulik`, `instalacje domowe`, `kotłownia`, `wentylacja`, `klimatyzacja`, `fajka`, `tytoń`, `iso burner`, `iso na pendrive`

#### Audience signals (App Campaigns sidebar)

- **Custom segment — apps/sites browsed:** `autodesk.com`, `bentley.com`, `cadworx.com`, `pipingoffice.com`, `weldnotes.com`, `tigwelder.com`
- **Custom segment — search terms:** copy the Theme-1 + Theme-2 exact matches above
- **Affinity:** *Construction Industry Professionals*, *Manufacturing & Industrial Professionals*
- **In-market:** *Construction Tools & Equipment*, *Business Software*

---

## 4. Visual assets

> All four aspect ratios below feed the Google App Campaign Asset Library. Capture every screenshot at the device's native resolution (Pixel 8 or iPhone 15 Pro recommended), then crop / pad in Canva. Caption overlays use the style guide colours from §0.

### 4.1 Phone screenshot set — 8 frames (1290×2796 for iPhone 6.7", 1080×1920 for Play)

| # | Capture | Caption PL | Caption EN |
|---|---|---|---|
| 1 | Fitter home menu (dark theme, modules grid) | Wszystko, czego monter potrzebuje. W jednej kieszeni. | Everything a fitter needs. In one pocket. |
| 2 | Cut List project view — one segment expanded showing START / ISO / END | Lista cięć z parserem ISO: 5×200+150. | Cut list with an ISO parser: 5×200+150. |
| 3 | Rolling Offset calculator with Rise / Spread filled in and Travel highlighted | Rolling offset w dwie sekundy. | Rolling offset in two seconds. |
| 4 | Saddle Cut calculator — branch angle slider + curve preview | Saddle cut bez kartki i ołówka. | Saddle cut without paper or pencil. |
| 5 | DN ↔ mm table scrolled to DN100 (highlighted row) | Tabela DN ↔ mm pod ręką: DN15–DN600. | DN ↔ mm table at your fingertips: DN15–DN600. |
| 6 | ISO Notebook — isometric grid with a sketched route + 3 line types legend | Rysuj trasę na izometrii — telefon = zeszyt. | Sketch the route on iso — phone = notebook. |
| 7 | Welder → Pipes AMP reference screen | Parametry TIG dla rur, zawsze pod ręką. | TIG pipe parameters, always within reach. |
| 8 | Weld Journal list with OK/NOK badges + PDF export button | Dziennik spawów. Eksport PDF i CSV. | Weld journal. Export to PDF and CSV. |

### 4.2 Landscape 1.91:1 — 4 frames (1200×628)

Used as Google App Campaign feed-display assets and as Open Graph cards.

| # | Composition | Caption PL | Caption EN |
|---|---|---|---|
| 1 | Phone-in-glove hero shot, screen = Cut List, accent orange CTA bottom-right "Pobierz" / "Get it" | Lista cięć w rękawicach. | Cut list in gloves. |
| 2 | Split: left = ISO drawing photo, right = phone screen of segment builder echoing same numbers | Czyta ISO tak jak Ty. | Reads ISO the way you do. |
| 3 | Top-down workbench: pipe, marker, phone showing Saddle Cut curve overlay | Saddle cut bez kartki. | Saddle cut, no paper. |
| 4 | Welder journal screenshot on the right, weld-bay photo on the left | Dziennik spawów do handover. | Weld journal for handover. |

### 4.3 Square 1:1 — 4 frames (1200×1200)

Used for Discover / Display square slots and as Instagram / LinkedIn posts.

| # | Composition | Caption PL | Caption EN |
|---|---|---|---|
| 1 | Big bold number "8" in orange + label "kalkulatorów rurarza" / "fitter calculators" | 8 kalkulatorów. Zero reklam. | 8 calculators. Zero ads. |
| 2 | Logo + tagline only on dark | Zrobione przez montera. | Built by a fitter. |
| 3 | Five-icon row (cut list, rolling offset, saddle, ISO, journal) | Pięć narzędzi, jedna apka. | Five tools, one app. |
| 4 | Stamp-style "OFFLINE" badge over a faded site photo | Działa bez zasięgu. | Works without signal. |

### 4.4 Portrait 4:5 — 4 frames (1080×1350)

Best for Instagram / TikTok feed, LinkedIn document posts, secondary Play assets.

| # | Composition | Caption PL | Caption EN |
|---|---|---|---|
| 1 | Phone vertical, Rolling Offset filled in, Rise=300 / Spread=400 → Travel highlighted | Rolling offset: Rise + Spread → Travel. | Rolling offset: Rise + Spread → Travel. |
| 2 | ISO Notebook sketch top, finished spool photo bottom | Z ISO na warsztat. | From ISO to the workshop. |
| 3 | Pull-quote testimonial style: *"Robię listę w 3 min zamiast 30."* | 3 minuty zamiast 30. | 3 minutes instead of 30. |
| 4 | Cut List screen with long-press copy toast visible | Long-press = kopiuj. | Long-press to copy. |

> **Canva MCP brief.** Pass any of the captions above into `mcp__canva__generate-design` with the style guide colours from §0 and the captured PNG as `mcp__canva__upload-asset-from-url`. Recommended sequence: upload all 8 phone screenshots first, then generate the 4 landscape, 4 square, and 4 portrait wrappers around them.

---

## 5. Video scripts

> Format: scene table with shot description, on-screen text, voice-over and a *Kling-friendly* flag. Kling-friendly = a single subject, short motion, no text-overlay required at generation time (text is added in post). For Kling shots, prompt structure: *`[subject] [action], [environment], [camera move], [style], industrial palette, dark teal/charcoal, accent orange`*.

### 5.1 10-second hook (PL + EN)

Goal: stop the thumb in feed. Single problem → single answer.

| Sec | Shot | On-screen text PL | On-screen text EN | Kling-friendly |
|---|---|---|---|---|
| 0–2 | Welder gloves holding a paper ISO sketch, frustrated tap with marker | Liczysz to ręcznie? | Still doing it by hand? | YES — *"close-up of gloved hands tapping a piping isometric drawing with a marker, soft shop lighting, slow zoom in, photoreal"* |
| 2–6 | Same hands swipe to phone showing Rolling Offset; numbers fill in | Rolling offset w 2 sek. | Rolling offset in 2 sec. | NO — needs real UI capture |
| 6–9 | Hand long-presses the result; toast appears "Copied" / "Skopiowano" | Long-press = kopiuj | Long-press to copy | NO — UI capture |
| 9–10 | Logo + CTA "Pobierz" / "Get it" | FitterWelder Pro | FitterWelder Pro | YES — *"product logo reveal on dark charcoal, subtle orange glow"* |

Voice-over PL: *"Rolling offset. Dwie sekundy. Long-press kopiuje. Działa offline."*
Voice-over EN: *"Rolling offset. Two seconds. Long-press copies. Works offline."*

### 5.2 15-second feature (PL + EN)

Goal: three features → install. Use the actual app between any two B-roll shots.

| Sec | Shot | On-screen text PL | On-screen text EN | Kling-friendly |
|---|---|---|---|---|
| 0–3 | B-roll: galvanised pipes being marked in a prefab shop | LISTA CIĘĆ | CUT LIST | YES — *"medium shot of stainless steel pipes on sawhorses in a workshop, fluorescent light, gentle dolly-in"* |
| 3–7 | UI capture: Cut List project with `5×200+150` typed in | ISO 5×200+150 | ISO 5×200+150 | NO |
| 7–10 | UI capture: Saddle Cut curve preview | SADDLE CUT | SADDLE CUT | NO |
| 10–13 | B-roll: TIG welder striking an arc on a pipe stub | DZIENNIK SPAWÓW | WELD JOURNAL | YES — *"close-up of a TIG welder striking an arc on a stainless pipe joint, sparks in slow motion, shallow depth of field, cinematic"* |
| 13–15 | Logo + "Działa offline. Bez konta." / "Offline. No account." | FitterWelder Pro | FitterWelder Pro | YES |

Voice-over PL: *"Lista cięć z parserem ISO. Saddle cut bez kartki. Dziennik spawów do PDF. Wszystko offline."*
Voice-over EN: *"Cut lists with an ISO parser. Saddle cut, no paper. Weld journal to PDF. All offline."*

### 5.3 30-second narrative (PL + EN)

Goal: emotional + functional + CTA. The hero's day, compressed.

| Sec | Shot | On-screen / VO PL | On-screen / VO EN | Kling-friendly |
|---|---|---|---|---|
| 0–3 | Wide of a refinery skyline at dawn, worker walking in | *Każdy dzień zaczyna się tak samo.* | *Every day starts the same.* | YES — *"wide morning shot of a refinery silhouette at dawn, worker in hi-vis walking towards camera, golden hour, cinematic anamorphic"* |
| 3–8 | Hand pulling a folded ISO drawing out of a chest pocket; counting on fingers | *Zwijasz izometrię. Liczysz w głowie.* | *You unfold the iso. You count in your head.* | YES — *"close-up of gloved hands unfolding a piping isometric drawing in a workshop, shallow depth of field"* |
| 8–14 | Phone replaces the paper; UI capture of Cut List + ISO expression entry | *Albo robisz to inaczej.* | *Or you do it differently.* | NO — UI capture |
| 14–20 | UI capture montage: Rolling Offset → Saddle Cut → DN table → ISO Notebook | *Rolling offset. Saddle cut. Tabela DN. Zeszyt ISO.* | *Rolling offset. Saddle cut. DN table. ISO sketchpad.* | NO — UI capture |
| 20–25 | B-roll: weld journal being shown to a foreman on a tablet | *Dziennik spawów eksportujesz do PDF. Handover gotowy.* | *Export the weld journal to PDF. Handover ready.* | YES — *"two industrial workers in hard hats looking at a tablet showing a weld log, refinery in background, documentary style"* |
| 25–30 | Phone on a workbench, screen unlocked to logo. Tagline appears. | *FitterWelder Pro. Zrobione przez montera. Działa offline.* | *FitterWelder Pro. Built by a fitter. Works offline.* | YES — *"phone resting on a workbench next to a measuring tape and a marker, screen glowing in dark workshop, slow push-in, photoreal"* |

> **Kling MCP brief.** Queue the YES-flagged shots via `mcp__kling__kling_text_to_video` with prompt prefix *"industrial documentary, 35mm anamorphic, dark teal and charcoal palette, accent orange, no on-screen text"*. Set duration 5s each, then assemble in CapCut / DaVinci with UI captures interleaved.

---

## 6. Landing page copy

Single-page funnel at the (yet-to-be-built) marketing URL. Sections in order, ready to paste into a Notion / Carrd / GitHub Pages page.

### Hero

**H1 PL:** *Lista cięć i kalkulatory rurarza. W jednej kieszeni.*
**H1 EN:** *Pipe cut lists and fitter calculators. In one pocket.*

**Sub-PL:** *Działa offline, w rękawicach. Bez konta, bez reklam. Zrobione przez czynnego montera rurociągów.*
**Sub-EN:** *Works offline, in gloves. No account, no ads. Built by a working pipe fitter.*

**CTA buttons:** *Pobierz z Google Play* / *Get it on Google Play* — *Pobierz z App Store* / *Get it on the App Store*

### Trust strip

> *DN15–DN600 per ASME B16.9* · *8 fitter calculators* · *4 welder calculators* · *Offline-first SQLite* · *PL + EN built-in*

### Three pillars (icon + heading + 2 lines each)

1. **Fitter pillar — PL:** *Lista cięć i biblioteka komponentów. Parser czyta `5×200+150` tak jak rysują na izo.*
   **EN:** *Cut lists and a component library. The parser reads `5×200+150` the way it's drawn on the iso.*
2. **Welder pillar — PL:** *AMP, heat input, preheat, purge. Dziennik spawów eksportowany do PDF/CSV.*
   **EN:** *AMP, heat input, preheat, purge. Weld journal exported to PDF/CSV.*
3. **Field pillar — PL:** *Tryb ciemny, duże dotyki, long-press kopiuje wynik, lokalna baza. Nie potrzebuje zasięgu.*
   **EN:** *Dark theme, big touch targets, long-press copies the result, local database. No signal required.*

### Feature deep-dive (collapsible accordions)

Use the §1 inventory verbatim — each Fitter / Welder bullet becomes one accordion row.

### Social proof slot (to fill once we collect testimonials)

Placeholders:
- *"Robię listę cięć w 3 minuty zamiast 30."* — Tomek, monter, rafineria Płock
- *"Saddle cut zawsze sprawdzałem na kartce. Teraz mam to w telefonie."* — Marek, brygadzista prefabrykacji

### Pricing

**Free.** *No account. No ads. No in-app purchases. Source: the developer is a working fitter who wrote it for himself first.*

### FAQ

- **Czy aplikacja działa offline?** Tak, całkowicie. Dane w lokalnej bazie SQLite.
- **Czy są reklamy?** Nie. Nigdy.
- **Czy muszę zakładać konto?** Nie.
- **Czy wspiera DN 600+?** Tabela B16.9 sięga DN600. Większe wymiary planowane.
- **Czy jest dostępna na iPhone?** Tak, App Store (`com.jakatora.fitterwelderpro`).
- **Czy mogę eksportować dziennik spawów?** Tak — PDF i CSV.
- **Czy jest po polsku i angielsku?** Tak, przełącznik w prawym górnym rogu.

### Footer

Privacy policy · Support email *kkprotigwelding@gmail.com* · Open-source dependencies · © 2026 Krzysztof Kapusta.

---

## 7. Play Store listing (PL+EN)

> Title and short description match the actual published builds (`com.startklaar.fitterwelder`). Long description re-uses the verbatim block from `appstore_metadata.md` so PL and EN texts stay consistent across stores.

### PL — Google Play

**Tytuł (max 30):** `FitterWelder Pro` (16)

**Krótki opis (max 80):** `Lista cięć, kalkulatory rurarza i spawacza. Offline, bez konta, bez reklam.` (78)

**Pełny opis (max 4000):**

```
FitterWelder Pro to profesjonalne narzędzie dla monterów i spawaczy rur — stworzone, żeby rozwiązywać prawdziwe problemy na budowie, szybko i bez błędów.

Oblicz długości cięć, rozplanuj trasę rur, wyznacz obrót kolanka — aplikacja daje odpowiedź w kilka sekund, bez długopisu, bez kartki.

— LISTA CIĘCIA
Twórz i zarządzaj listami cięcia dla swoich projektów. Dodawaj odcinki rur, śledź wymiary i miej porządek na każdym zadaniu.

— NARZĘDZIA KOLANKOWO
• Cięcie kolanka — oblicz kąt docelowy z dwóch standardowych kolanek
• Obrót kolanka — przeliczaj między % a ° dla kolanka walcowanego
• Wstawka — oblicz długość wstawki z Ø, R, kąta i odejścia

— KALKULATORY TRASY RUR
• Trasa rur — 3 × kolanka 90°: oblicz długości wszystkich odcinków
• Rolling Offset — Rise + Spread → Travel i kąt
• Spadek rury — przeliczaj między %, mm/m i stopniami
• Pomiar trasy — pomierz trasę dwuboczną z korekcją wew./zew./oś

— SKRACANIE REDUKCJI
Oblicz długość docinania redukcji koncentrycznej do zadanej średnicy wylotowej.

— SADDLE CUT (wycięcie siodłowe)
Oblicz profil wycięcia siodłowego dla odgałęzienia. Pełna krzywa cięcia dla dowolnej średnicy i kąta.

— TABELA DN ↔ MM
Szybkie sprawdzenie: rozmiary DN, OD w mm, grubość ścianki i odpowiedniki NPS dla stali nierdzewnej i węglowej.

— BIBLIOTEKA KOMPONENTÓW
Standardowe wymiary kolanek, trójników, redukcji i kołnierzy w SS i CS — zawsze pod ręką.

— ZESZYT ISO
Rysuj trasy rur na izometrycznej siatce kropek. Trzy rodzaje linii: rura, linia centralna, linia ukryta. Cofnij i wyczyść jednym dotknięciem.

Stworzone przez montera, dla monterów.
Działa w pełni offline. Nie wymaga konta. Bez reklam.
```

**Tagi (Play Console):** Productivity, Tools, Industrial, Engineering

### EN — Google Play

**Title (max 30):** `FitterWelder Pro` (16)

**Short description (max 80):** `Pipe cut lists, fitter & welder calculators. Offline, no account, no ads.` (73)

**Full description (max 4000):**

```
FitterWelder Pro is a professional toolkit for pipe fitters and welders — built to solve real problems on the job site, fast.

Whether you're calculating cut lengths, laying out a pipe route, or figuring out the right elbow rotation, this app gives you the answers in seconds — no pen, no paper, no guesswork.

— CUT LIST
Create and manage cut lists for your projects. Add pipe sections, track dimensions, and stay organised on every job.

— ELBOW TOOLS
• Elbow cut — calculate the target angle from two standard elbows
• Elbow rotation — convert between % and ° for rolled joints
• Insert — calculate insert length from diameter, radius, and offset

— PIPE ROUTE CALCULATORS
• Pipe route — 3 × 90° elbows: calculate all segment lengths
• Rolling offset — Rise + Spread → Travel and angle
• Pipe slope — convert between %, mm/m and degrees
• Route measurement — measure a 2-sided route with inner/outer/axis correction

— REDUCER TRIMMING
Calculate the cut-back length when trimming a concentric reducer to a target outlet diameter.

— SADDLE CUT (Fish-mouth)
Calculate the saddle cut profile for a branch pipe connection. Full cut curve for any pipe diameter and branch angle.

— DN ↔ MM TABLE
Quick reference for DN nominal sizes, OD in mm, wall thickness, and NPS equivalents for stainless and carbon steel.

— COMPONENT LIBRARY
Standard dimensions for elbows, tees, reducers and flanges in SS and CS — always at your fingertips.

— ISO NOTEBOOK
Sketch pipe routes directly on an isometric dot grid. Three line types: pipe, centre line, hidden line. Undo and clear in one tap.

Built by a pipe fitter, for pipe fitters.
Works fully offline. No account required. No ads.
```

**Tags (Play Console):** Productivity, Tools, Industrial, Engineering

### Release notes — PL + EN (current build)

Verbatim from `PLAY_RELEASE_NOTES_PL_EN.md`:

**PL:**
- Dodano możliwość zmiany języka aplikacji (PL/EN) z menu głównego.
- Uproszczono widok `Rury → Zatwierdzone AMP` (pozostawiono wyszukiwarkę).
- Usunięto dolny komentarz informacyjny w kalkulatorze AMP (Rury-Welder).
- Poprawki stabilności i przygotowanie wersji produkcyjnej.

**EN:**
- Added app language switching (PL/EN) from the main menu.
- Simplified `Pipes → Approved AMP` view (search bar only).
- Removed the bottom informational note in the AMP calculator (Pipes-Welder).
- Stability improvements and production release preparation.

---

## 8. App Store Connect listing (PL+EN)

> Verbatim from `appstore_metadata.md`. Keywords field on App Store is **comma-separated, no spaces**, max 100 chars total.

### EN

**App Name (max 30):**
```
FitterWelder Pro
```

**Subtitle (max 30):**
```
Pipe Fitter & Welder Tools
```

**Description (max 4000):**
```
FitterWelder Pro is a professional toolkit for pipe fitters and welders — built to solve real problems on the job site, fast.

Whether you're calculating cut lengths, laying out a pipe route, or figuring out the right elbow rotation, this app gives you the answers in seconds — no pen, no paper, no guesswork.

— CUT LIST
Create and manage cut lists for your projects. Add pipe sections, track dimensions, and stay organised on every job.

— ELBOW TOOLS
• Elbow cut — calculate the target angle from two standard elbows
• Elbow rotation — convert between % and ° for rolled joints
• Insert — calculate insert length from diameter, radius, and offset

— PIPE ROUTE CALCULATORS
• Pipe route — 3 × 90° elbows: calculate all segment lengths
• Rolling offset — Rise + Spread → Travel and angle
• Pipe slope — convert between %, mm/m and degrees
• Route measurement — measure a 2-sided route with inner/outer/axis correction

— REDUCER TRIMMING
Calculate the cut-back length when trimming a concentric reducer to a target outlet diameter.

— SADDLE CUT (Fish-mouth)
Calculate the saddle cut profile for a branch pipe connection. Full cut curve for any pipe diameter and branch angle.

— DN ↔ MM TABLE
Quick reference for DN nominal sizes, OD in mm, wall thickness, and NPS equivalents for stainless and carbon steel.

— COMPONENT LIBRARY
Standard dimensions for elbows, tees, reducers and flanges in SS and CS — always at your fingertips.

— ISO NOTEBOOK
Sketch pipe routes directly on an isometric dot grid. Three line types: pipe, centre line, hidden line. Undo and clear in one tap.

Built by a pipe fitter, for pipe fitters.
Works fully offline. No account required. No ads.
```

**Keywords (max 100):**
```
pipe fitter,welder,cut list,elbow,rolling offset,saddle cut,isometric,pipe route,reducer,DN table
```

**Promotional Text (max 170):**
```
Create pipe projects, calculate cut sections, and keep welding-related data organized in one place. Works offline, no account required.
```

**What's New:**
```
Language switching (PL/EN) from the main menu. Simplified Pipes → Approved AMP view. Stability improvements.
```

### PL

**Nazwa aplikacji (max 30):**
```
FitterWelder Pro
```

**Podtytuł (max 30):**
```
Narzędzia montażysty rur
```

**Opis (max 4000):**
```
FitterWelder Pro to profesjonalne narzędzie dla monterów i spawaczy rur — stworzone, żeby rozwiązywać prawdziwe problemy na budowie, szybko i bez błędów.

Oblicz długości cięć, rozplanuj trasę rur, wyznacz obrót kolanka — aplikacja daje odpowiedź w kilka sekund, bez długopisu, bez kartki.

— LISTA CIĘCIA
Twórz i zarządzaj listami cięcia dla swoich projektów. Dodawaj odcinki rur, śledź wymiary i miej porządek na każdym zadaniu.

— NARZĘDZIA KOLANKOWO
• Cięcie kolanka — oblicz kąt docelowy z dwóch standardowych kolanek
• Obrót kolanka — przeliczaj między % a ° dla kolanka walcowanego
• Wstawka — oblicz długość wstawki z Ø, R, kąta i odejścia

— KALKULATORY TRASY RUR
• Trasa rur — 3 × kolanka 90°: oblicz długości wszystkich odcinków
• Rolling Offset — Rise + Spread → Travel i kąt
• Spadek rury — przeliczaj między %, mm/m i stopniami
• Pomiar trasy — pomierz trasę dwuboczną z korekcją wew./zew./oś

— SKRACANIE REDUKCJI
Oblicz długość docinania redukcji koncentrycznej do zadanej średnicy wylotowej.

— SADDLE CUT (wycięcie siodłowe)
Oblicz profil wycięcia siodłowego dla odgałęzienia. Pełna krzywa cięcia dla dowolnej średnicy i kąta.

— TABELA DN ↔ MM
Szybkie sprawdzenie: rozmiary DN, OD w mm, grubość ścianki i odpowiedniki NPS dla stali nierdzewnej i węglowej.

— BIBLIOTEKA KOMPONENTÓW
Standardowe wymiary kolanek, trójników, redukcji i kołnierzy w SS i CS — zawsze pod ręką.

— ZESZYT ISO
Rysuj trasy rur na izometrycznej siatce kropek. Trzy rodzaje linii: rura, linia centralna, linia ukryta. Cofnij i wyczyść jednym dotknięciem.

Stworzone przez montera, dla monterów.
Działa w pełni offline. Nie wymaga konta. Bez reklam.
```

**Słowa kluczowe (max 100):**
```
monter rur,spawacz,lista cięcia,kalkulator,kolano,rolling offset,saddle cut,izometria,trasa rur,DN
```

**Tekst promocyjny (max 170):**
```
Twórz projekty rur, licz odcinki do cięcia i porządkuj parametry spawania w jednej aplikacji. Działa offline, bez konta.
```

**Co nowego:**
```
Przełącznik języka (PL/EN) w menu głównym. Uproszczono widok Rury → Zatwierdzone AMP. Poprawki stabilności.
```

### Inne pola App Store Connect

| Pole | Wartość |
|------|---------|
| Bundle ID | com.jakatora.fitterwelderpro |
| App Store App ID | 6761770166 |
| Apple Team | B7J6A7R258 |
| Primary Category | Utilities |
| Secondary Category | Productivity |
| Age rating | 4+ |
| Price | Free |
| Support URL | mailto:kkprotigwelding@gmail.com (until support page goes live) |
| Privacy Policy URL | https://jakatora.github.io/cut_list_app_new/privacy.html |
| Marketing URL | (optional — leave blank until landing page is live) |

---

## 9. Organic / social

### Facebook groups + forums (target list)

PL:
- *Spawacze i monterzy rurociągów* (Facebook)
- *Praca monter / spawacz Norwegia / Holandia / Niemcy* (Facebook)
- *PipeFitterzy Polska* (Facebook)
- spawalnicy.pl (forum) — `/wpisy/oprogramowanie`
- weldingforum.pl

EN / DE:
- r/Welding, r/Pipefitter (Reddit)
- r/Trades, r/Construction
- weldingweb.com forum
- iboats.com plumbing/pipe sub-forum (for marine fitters)
- /r/Schweissen (DE)

### Sample first-post copy (PL — Facebook group)

> Cześć. Robię od roku appkę na telefon dla nas — monterów i spawaczy. Wyrażenia ISO typu `5×200+150` wpisujesz wprost, rolling offset / saddle cut policzy w sekundę, jest tabela DN i dziennik spawów do PDF. Wszystko offline, bez konta, bez reklam. Bardziej zeszyt niż "system". Jeśli ktoś chce potestować — link niżej. Zerowy budżet, opinie krytyczne mile widziane.

### Sample first-post copy (EN — r/Pipefitter)

> I'm a working pipe fitter and I built an app for the way I actually use my phone on site — chest pocket, gloves on, no signal. Cut list with an ISO expression parser (`5×200+150` works), rolling offset, saddle cut, DN ↔ mm table, B16.9 elbow takeouts, ISO sketchpad on an isometric grid, and a weld journal that exports to PDF. Free, offline, no login, no ads. Honest feedback welcome.

### LinkedIn post (founder voice, English)

> Building tools for trades is a niche that respects honesty. **FitterWelder Pro** ships today: cut lists with an ISO expression parser, 8 fitter calculators, a welder journal that exports to PDF, all offline. Built because I'm a pipe fitter and my paper notebook kept getting torn. If you work with pipes — or know someone who does — I'd love your eyes on it. Link in comments.

### TikTok / Reels (30 s vertical, voice-over hooks)

1. *"Rolling offset w dwie sekundy. Bez kartki."* (PL)
2. *"Saddle cut on a phone — does it actually work? Let's see."* (EN)
3. *"Made by a pipe fitter, for pipe fitters. No ads. No login. Offline."* (EN)
4. *"Ten kalkulator zastąpił mi kartkę i długopis."* (PL)

### Email signature line (for outreach)

> *Krzysztof Kapusta · pipe fitter · maker of FitterWelder Pro — `kkprotigwelding@gmail.com`*

### Cadence

| Channel | First week | Steady state |
|---|---|---|
| Facebook groups | 3 posts | 1 post / 2 weeks |
| Reddit (r/Pipefitter, r/Welding) | 1 post each | 1 post / month |
| LinkedIn | 1 founder post | 1 post / 2 weeks |
| TikTok / Reels | 2 clips | 1 clip / week |
| Forums (spawalnicy, weldingweb) | 1 thread each | reply when triggered |

---

## 10. Quick-paste cheat sheet

> Paste-ready bundle for Google Ads campaign creation UI. Each block is sized for direct copy.

### Top headlines (5 PL + 5 EN, ≤25 chars)

**PL:**
1. Lista cięcia w kieszeni (23)
2. Kalkulator dla montera (22)
3. Rolling offset w sekund (23)
4. Bez konta, bez reklam (21)
5. 8 kalkulatorów rurarza (22)

**EN:**
1. Pipe cut list in pocket (23)
2. Fitter calculator suite (23)
3. Rolling offset, 2 sec (21)
4. No account. No ads. (19)
5. 8 pipe calculators (18)

### Top descriptions (5 PL + 5 EN, ≤90 chars)

**PL:**
1. Lista cięć, kąty kolanek, saddle cut. Wszystko w jednej apce, offline. (70)
2. Rolling offset, route calc, ISO. Działa w rękawicach, kopiuj jednym dotykiem. (78)
3. 8 kalkulatorów rurarza i spawacza. Bez konta. Bez reklam. (57)
4. Tabela DN ↔ mm, elbow takeouts B16.9, biblioteka kolanek, trójników i kołnierzy. (80)
5. Zrobione przez montera, dla montera. Działa offline na placu. (60)

**EN:**
1. Cut lists, elbow angles, saddle cuts. One offline app for the shop floor. (73)
2. Rolling offset, route calc, ISO sketchpad. Long-press copies every result. (74)
3. 8 fitter + welder calculators. No login. No ads. No site connection needed. (75)
4. DN ↔ mm table, B16.9 elbow takeouts, library of elbows, tees and flanges. (73)
5. Built by a pipe fitter for pipe fitters. Works fully offline on site. (68)

### Top callouts (6 PL + 6 EN, ≤25 chars)

**PL:** Bez konta · Bez reklam · Działa offline · 8 kalkulatorów · DN15–DN600 · Long-press = kopiuj

**EN:** No account · No ads · Fully offline · 8 calculators · DN15–DN600 · Long-press to copy

### Top 1 sitelink (best CTR bet)

EN: **Build a cut list** — *Add segments with ISO syntax* / *Get BOM and material list* → `/cut-list`
PL: **Lista cięć** — *Segmenty z wyrażeniami ISO* / *BOM i lista materiałów* → `/cut-list`

### Top 3 keyword themes (for Search overflow campaign)

1. *pipe fitter app* / *aplikacja monter rurociągów*
2. *rolling offset calculator* / *kalkulator rolling offset*
3. *weld journal app* / *dziennik spawów aplikacja*

### Recommended targeting (1-line)

PL + EN, Android 9+ primary / iOS 15+ secondary, age 25–55, custom-segment audience built from search-terms in §3.7 Theme 1 + Theme 2, affinity *Construction Industry Professionals*, exclude **plumbing / smoking-pipe / ISO file** negatives.

### Recommended daily budget (1-line)

Start at **PLN 50 / EUR 12 per day** split 70 % PL / 30 % EN for two weeks; scale only after the install-to-tCPI ratio settles under PLN 8 (Android) and PLN 20 (iOS).

---

## 11. Next steps — what the user does manually

- [ ] In **Codemagic**: refresh the iOS distribution cert if expired (Apple Team `B7J6A7R258`), then click *Start build* on the `ios-release` workflow.
- [ ] In **Google Ads UI**: create one App Campaign for Installs (Android) and one for iOS; paste the top-5 assets from §10 into the asset library, then paste the full §3 packs into the rotation.
- [ ] In **Canva MCP** (chat): generate the 4×4×4 wrapper set from §4 using the captions in the tables — start with `mcp__canva__upload-asset-from-url` for the 8 phone screenshots, then `mcp__canva__generate-design` per aspect ratio.
- [ ] In **Kling MCP** (chat): queue the *YES — Kling-friendly* shots flagged in §5 via `mcp__kling__kling_text_to_video`. The 30-second narrative (§5.3) is the priority — 5 of its 6 shots are Kling-eligible.
- [ ] In **Google Play Console**: paste §7 into Title / Short description / Full description / Release notes for build `com.startklaar.fitterwelder`.
- [ ] In **App Store Connect**: paste §8 into both EN and PL locales for `com.jakatora.fitterwelderpro` (App ID `6761770166`). Confirm Support URL and Privacy Policy URL match the values in the table.
- [ ] Build out the landing page from §6 (Notion / Carrd / GitHub Pages — the user's call). The Marketing URL field in App Store Connect stays blank until that page is live.
- [ ] Post the §9 first-post copy to **2 PL Facebook groups + r/Pipefitter** on launch day. Track replies; do not reply with the app link a second time in the same thread (auto-moderation trigger).
- [ ] Set a 14-day check-in: review Google Ads CPI vs. the §10 thresholds, prune underperforming headlines/descriptions, double down on whichever PL/EN/aspect-ratio combination drives lowest CPI.

---

*End of kit.*
