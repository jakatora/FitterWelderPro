# OPERATIONS.md — Fitter Welder Pro

Operational reference. Read this whenever AGENTS.md says "use the project's own commands / config".

---

## Stack

- **Mobile**: Flutter 3.x (Material 3, dark scheme `#0F1117`). Repo: `jakatora/FitterWelderPro` (Android only for now; iOS via Codemagic later).
- **Backend**: Node 22 + Express 5 on Railway. Shared with PrzetargAI — Fitter routes mounted under `/api/fitter/*`, separate DB tables. Base URL: `https://backend-production-a43e3.up.railway.app`.
- **Database**: SQLite (`better-sqlite3`) on a Railway volume. Idempotent schema in `backend/src/db/schema.sql`.
- **AI**: Anthropic SDK. Models — Haiku 4.5 (`claude-haiku-4-5`) for chat + RAG. Sonnet 4.6 (`claude-sonnet-4-6`) for ISO vision scan.
- **Payments**: Stripe TEST mode for now. LIVE keys exist in vault but not configured on Railway.
- **No auth**: Fitter is anonymous-by-default. Device id (32-char hex in SharedPreferences) is the user identifier. Posted to Stripe as `client_reference_id` / metadata.

## Separation from PrzetargAI

This backend serves **two products** off one server. NEVER cross the streams:

| | PrzetargAI | Fitter Welder Pro |
| --- | --- | --- |
| Routes | `/api/auth`, `/api/billing`, `/matches` | `/api/fitter/*` only |
| Tables | `users`, `tenders`, `matches`, … | `fitter_premium`, `fitter_chat_message`, `fitter_job_listing` |
| Stripe metadata | (none / `user_id`) | `metadata.project = "fitter"` (premium) or `"fitter_jobs"` (job posts) |
| Auth | Firebase / email | none — device id |
| Webhook routing | `routes/webhooks.js` branches on `metadata.project` **first** | same file, fall-through if missing project tag |

**Rule**: any new Fitter feature gets a route prefixed `/api/fitter/`, a table prefixed `fitter_`, and (if Stripe involved) a `metadata.project` tag.

## Key files

```text
backend/src/
  app.js                      mount points + body-parser limits
  config/env.js               zod schema for all env vars
  db/schema.sql               idempotent table DDL
  db/repos.js                 lazy prepared statements per repo
  routes/fitterBilling.js     Stripe subscription checkout + status
  routes/fitterAi.js          /chat — Haiku + keyword RAG
  routes/fitterChat.js        public chat (4 rooms, 49 PLN/post)
  routes/fitterJobs.js        Praca module (49 PLN/listing)
  routes/fitterScan.js        ISO vision scan
  routes/webhooks.js          Stripe webhook dispatcher
  services/fitterAi.js        RAG retrieval + Claude call
  services/fitterScan.js      Claude Vision wrapper
  services/stripe.js          createFitterCheckoutSession + createFitterJobCheckoutSession
  data/piping_knowledge.md    1.2 MB curated standards corpus

lib/                          Flutter client
  config/backend_config.dart  ONE source of truth for URLs + feature flags
  services/                   premium / ai_chat / chat / jobs / iso_scanner_ai
  screens/                    home + 40+ tool screens
  utils/clipboard_helper.dart, haptic.dart
```

## Feature flags (`backend_config.dart`)

```text
stripeBackendLive = true    // Stripe Premium + Jobs are live
aiBackendLive     = true    // Claude Haiku chat is live
chatBackendLive   = true    // public chat is live (4 rooms)
jobsBackendLive   = false   // legacy flag, ignored — Praca routes through stripeBackendLive
```

## Stripe TEST products (current)

| Product | Price ID | Amount |
| --- | --- | --- |
| Fitter Premium Monthly | `price_1TbmxyAom97JfF2jzoBZQBIe` | 19 PLN/mo |
| Fitter Premium Yearly  | `price_1TbmxzAom97JfF2jtqUfZne9` | 149 PLN/yr |
| Fitter Job Posting     | `price_1TcVSYAom97JfF2jlzq7VkbV` | 49 PLN one-time |

Webhook (TEST): `we_1TaKsvAom97JfF2jmoJ5Hx4c` → `https://backend-production-a43e3.up.railway.app/webhooks/stripe`. Events: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`.

## Deploy backend

```text
cd c:\Users\Startklaar\Documents\przetarg-ai
git push origin main                                                  # GitHub
RAILWAY_TOKEN=<vault> railway up --service backend --detach --ci      # Railway
```

Railway service ID `8e42f2f6-1d80-40cd-a02d-3bf0d6b4c757`, env `cf9b7fcd-49fe-4ed6-a22a-fb02054625e6`. Token in `C:\Users\Startklaar\.api-keys\keys.env`.

Smoke probe after deploy: `curl https://backend-production-a43e3.up.railway.app/health` should return `{"status":"ok"...}`.

## Build APK

```text
cd c:\Users\Startklaar\Documents\FitterWelderPro
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (~62 MB).

## Run on emulator

```text
flutter emulators                                       # list
flutter emulators --launch Medium_Phone_API_36.1        # start it (only configured one)
flutter run                                             # attach with hot-reload
```

Screenshot:

```text
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png ./shot-<label>.png
```

Hot-reload first, full rebuild only when:

- Native code / Android manifest / asset bundle changed.
- A new package was added to `pubspec.yaml`.
- A `const` constructor was added/removed where it affects const evaluation.

## Test cards (Stripe TEST)

- Success: `4242 4242 4242 4242` + any future date + any CVC + any ZIP
- Decline: `4000 0000 0000 0002`
- 3DS challenge: `4000 0025 0000 3155`

## Conventions

- **Comments**: only when WHY isn't obvious (workaround, invariant, surprising behaviour). Never narrate WHAT — names should do that.
- **Strings**: every user-visible string is `context.tr(pl: '…', en: '…')`. Polish is the default; English is for screenshots / store listings only.
- **Errors**: never `Text('Error: $e')` in a snackbar. Always map common causes to actionable messages; raw exception goes to `debugPrint(...)`.
- **Backend errors**: `throw badRequest(...)` etc from `lib/errors.js` — never raw `Error()`.
- **No `flutter pub run build_runner`**: this repo doesn't use codegen.
- **`flutter analyze` must pass with 0 issues** before commit.

## Memory & references

- User API-key vault: `C:\Users\Startklaar\.api-keys\keys.env`. Check before asking for any key.
- Global memory: `C:\Users\Startklaar\.claude\projects\c--Users-Startklaar-Documents-asystenbiznesu\memory\MEMORY.md`. Load before starting a session.
- `LOOP_PROGRESS.md` in repo root tracks ISO Notebook iteration history.
- `BACKLOG.md` in repo root is the work queue (TODO / IN_PROGRESS / DONE per AGENTS.md).
- `CHANGELOG.md` in repo root is the audit trail of completed improvements.

## Things that almost-always go wrong

- **Express middleware order**: if you mount a route using `apiLimiter`, the rate-limiter must be declared first. Botched once (2026-05-28 scan-iso) → service crashed.
- **Webhook `metadata.project`**: forget the tag and Stripe webhook falls through to PrzetargAI's user-table lookup → "user not found" warn.
- **`String.fromEnvironment` defaults need const**: `BackendConfig.baseUrl` is const so it works. Don't pass non-const.
- **Body limit**: scan-iso photos can be 3-8 MB. Global `express.json({ limit: '1mb' })` rejects them; per-route 12 MB parser is layered before the limiter.
- **`Table.fromTextArray` deprecated**: use `TableHelper.fromTextArray` in the `pdf` package.
