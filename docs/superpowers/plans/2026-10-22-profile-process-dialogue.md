# Profile process dialogue — 2026-10-22

## Behavior
A natural request such as “Dodaj MAG do mojego profilu” is normalized by Haiku into a source-bound native command. MAG without an explicit code is not guessed. The application asks which of 135/136/138 is intended; a short spoken or typed reply completes the original operation. Preserve add/remove/replace and all explicitly supplied codes, then use the existing credential-free professional editor and final native confirmation.

## Contract and boundaries
- New opt-in capability `professional_process_questions: true` is legal only on writable `account.professional.edit` / `professional_profile` with `processes` listed. Old clients do not advertise it.
- Server prompt instructs new clients to execute a minimal command retaining MAG; old clients get clarification instead. Unknown or contradictory processes are not silently dropped.
- Native pending state contains only requested codes/operation and a local AccountService/session binding. Existing process list, qualifications, stamp, credentials and account service object are never sent to the interpreter by this dialogue.
- Replies must explicitly select 135/136/138. Model normalization cannot replace a different/invalid user choice. Invalid replies and informational questions retain the question. Cancel drops it. Session changes invalidate it.
- Answering the owned question requires zero additional model calls. Existing budget reservation, daily limits, Haiku low effort and zero paid retries remain.
- Final writes use the narrow compare-and-set endpoint and require acknowledgement; no save directly from an AI proposal/question.

## Verification
- Initial missing-continuity widget case failed before implementation; same case passed afterwards.
- 37 profile tests passed: source/mode/code guards, short reply, all three operations with typed and simulated voice commands/confirmation, invalid model choice, session change, side knowledge question, cancellation, original five-field writes/conflicts/privacy.
- 252 backend tests passed, zero skips. New scope test checks HTTP preservation of the native question and rejection of false/out-of-scope/missing-process flags before provider calls. Legacy flag omission stays accepted.
- Real local Express/SQLite replay: run `node --disable-warning=ExperimentalWarning tool/verify_professional_profile_wire.mjs --fields --mag` after native capture. Provider alone is injected: no paid cloud call, production profile edit or physical-phone proof.

## Remaining full goal
Five-field missing-value conversations were subsequently implemented in `2026-10-22-profile-field-dialogue.md`. Broad natural-language/action coverage, dedicated-provider evaluation, production route deployment and physical phone/voice/ISO/account/report acceptance remain. This is not completion of the whole assistant vision.


Local proof 2026-10-22T12:49:51.002Z: exact captured MAG request (654 bytes) and confirmed process write (62 bytes) return interpreter/write/readback 200, one injected Haiku request, low effort, no retry or paid calls. Existing five-field operations and four clears also return write/readback 200; narrow-write auth/role/conflict checks remain 401/403/400/409 as expected.

Backend PR17 https://github.com/jakatora/fitter-welder-pro-backend/pull/17 merged into main `618c6ba1de89927ee957d87fb4d450f46bd3e5c1`; tree equal to tested `eab0fda41206f2463c9572b43ec550703c71c079`. GitHub mergeable true/clean checked with exact head. Commit status pending/zero entries and check-runs HTTP403 do not prove green hosted CI. Merge API accepted the explicit head.

Production check 2026-10-22T12:51:44.408552Z: empty invalid POSTs to `/ai/assistant` and `/account/profile/assistant` return 404. Railway browser still shows Activate Device / Sign in or create account. The existing login request has no reply. Vault inventory still has no dedicated FWP Anthropic key; no foreign project key reused. No deployment, APK or production profile mutation performed.


Final verification: broad assistant/feedback/ISO/steel/native steel/account/profile/registration/popup run completed exit0 with 3751 passed and 37 pre-existing field-contract skips (missing field-bearing examples; these are not acceptance proof). Narrow final profile suite passed 37 after three mechanical curly-brace fixes in its test file. Four changed Dart files pass `dart analyze --fatal-infos`. Local replay repeated against merged main at 2026-10-22T12:52:31.145Z with the same expected HTTP results. Full 80-capability catalog passes strict HTTP validation: PL36838 bytes / EN36068 bytes, both 200 (2026-10-22T12:52:49.397Z). No paid provider calls. Foreign macOS registrant, pubspec.lock and .atlas changes preserved.
