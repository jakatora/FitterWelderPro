# Profile field dialogue — 2026-10-22

## Behavior
A natural request such as “Zmień mój zawód” is normalized by the cheap model to the minimal native command “Ustaw w moim profilu zawód”. The app asks for the missing value, retains the field/account session, accepts the user's literal typed/spoken reply, and prepares the existing native confirmation. Only a successful acknowledged write advances the workflow.

The same flow covers profession, years of experience, processes, qualifications and stamp. Process questions retain replace/add/remove. A reply “TIG i MAG” can ask a second question about 135/136/138 while retaining TIG and the original operation. “Zmień mój zawód i potem zmień mój stempel” asks and confirms each field separately, executing the two writes once in order after one initial interpretation.

Complete natural requests such as “Zmień moje doświadczenie na osiem lat” use the same source-bound values without unnecessary questions. Explicit text field/value boundaries preserve the whole literal RHS, including titles such as Change Manager, and never authorize the model to drop trailing words or choose a different value. Quoted short text values are data; unquoted question/command/cancel prefixes are not consumed as literal fields. This classification is bounded native grammar, not universal language understanding.

## Contract
- New optional `professional_field_questions: true` on writable `account.professional.edit` / `professional_profile`, only with nonempty declared `professional_profile_fields`.
- Server prompt gives minimal commands only for declared fields; flag omission keeps older clients on clarification. Existing MAG opt-in remains independent.
- Native question state/immutable process selections/AccountService reference/session revision are local. Only question descriptor and explicit choices go to the interpreter. No old private profile is used to fill missing values.
- Literal text is preserved. Experience accepts exactly one whole number0..80 with closed optional words; relations/multiple numbers/negative or fractional values are not silently treated as their first number. Process codes are closed native selections.
- AI reply normalization must equal the source value or process selection. Invalid/unknown replies do not become invented model values. Questions, navigation, cancel and session change are covered by tests.
- Existing credential guards, clean-draft/native editor checks, final confirmation and narrow atomic compare-and-set endpoint remain in force. No roles, identity, visibility or AI-consent writes are added.
- Haiku model, low effort, budget reservations, quotas, pricing and no-paid-retry policy are unchanged. Valid direct replies need no extra provider call.

## Evidence
- New missing-profession widget case failed before implementation and passed after.
- Final focused profile suite72 PASS, including the real widget flow for the quoted job title Change Manager. Includes seven missing-value operations in typed and simulated-voice form, final voice Tak, nested MAG, five session-change refusals, knowledge/navigation/cancel, unknown AI-invented reply, five complete natural edits, and two queued confirmed writes.
- Backend253 PASS / zero skips. New HTTP test preserves optional metadata/minimal command and rejects invalid scopes/false/missing field declarations before a provider call; legacy omission is accepted.
- 2026-10-22T13:06:48.941Z exact Flutter-captured interpreter and confirmed-write requests replayed through real local Express/SQLite. Seven missing-value cases (profession, experience, qualifications, stamp, replace/add/remove processes) each return interpreter/write/readback200, one injected Haiku/low/0retry request. Requests681–693B, writes50–96B. Existing five complete operations, four explicit clears, MAG and auth/conflict/role checks also pass. Backend working tree then contained the tested changes atop618c6ba; repeat against clean merged main before final report.
- Provider and widget speech adapter are injected. This is not live Anthropic quality, actual microphone/phone or production acceptance.

## Full goal remains open
User's later instruction to use AI for natural conversation supersedes the original2026-10-19 spec's local-only/AI-off-by-default iteration. Existing code/native invariants still ground calculations and confirmed writes. Full deployment/legal6, dedicated provider key/quality evaluation, phone/voice/ISO/account/profile/private-admin-report acceptance and command coverage need evidence.

The37 old field-contract skips mean no field-bearing catalog example in those fixtures. They are not37 proven missing actions, nor proof of full action coverage: classify them against actual module behavior in the next coverage audit rather than automatically inventing fields for every skipped module.


## Final state and deployment boundary
- Final combined assistant/feedback/ISO/steel/native steel/account/profile/registration/popup regression3785 PASS with37 pre-existing field-contract skips, exit0. Those skips are lack of fixture examples, not acceptance of the skipped behavior. Final source also passes four-file `dart analyze --fatal-infos`; diff check clean. Dart fixes were narrowly limited to curly braces in the changed skill/test (7/6 changes); adjacent strings fixed locally. No Dart/test files edited during a live Flutter test.
- Backend PR18 https://github.com/jakatora/fitter-welder-pro-backend/pull/18 merged and attached. Main `9a78d434d2cd1eba6b9ac61321ad375ce2a10f00` has the same tree as tested `f951bbfe1442c0193e4449489aa6b6471b790216`. Exact head and mergeabletrue/clean checked before API merge. Statuspending/zero entries and check-runs403 are not proof of green hosted CI.
- Replay repeated against clean merged main at2026-10-22T13:15:27.757Z: all seven owned-question cases and the previous writes/readbacks return200; existing conflict409/retry200/anon401/roleinjection400/reports403 hold. No paid calls. Full80-capability catalogs validate through HTTP at13:14:50.473Z: PL36874B / EN36104B, both200.
- Production at2026-10-22T13:14:51.833659Z: empty invalid unauthenticated POSTs `/ai/assistant` and `/account/profile/assistant` still404. Railway browser still shows Activate Device / Sign in or create account; marked Handoff. Existing login question unanswered; no live pairing process. Vault dedicatedFWPAnthropicPresentfalse. No borrowed key, deployment, new APK, production profile changes or live model/phone claims.
- Foreign macOS registrant/pubspec.lock/.atlas changes preserved. Full vision remains active, with further actual action/AI coverage audit and live acceptance required.
