# Steel list ownership before assistant record writes — 2026-10-22

A review of “add the current item to the material list” found a prerequisite: the existing steel list used one global SharedPreferences key. New assistant record writes must not make one user's order or prices visible to another account.

SteelOrderStore now binds a captured LocalRecordOwner to each page load and storage operation. Existing v1 data stays under the guest key; account lists use deterministic separate v2 keys and never copy guest data. Identity is checked around asynchronous preference access. A late A disk write can only address A's key; a revoked operation cannot report successful completion to B. A false SharedPreferences write result throws rather than claiming success. JSON prices, quantities, allowance and calculations are unchanged.

The open page registers an account-session preparer. Normal sign-in/sign-out freezes the page and awaits pending saves before changing identity; failed saves keep the old account and show retry. Session revision changes immediately clear old order and draft state, reload the new owner and close only owned steel dialogs. Stale dialog results and deferred navigation are generation-guarded. Unknown signed-in identity or read failure blocks the list instead of falling back to guest/empty data. Normal Back waits for persistence and stays on the page if saving fails.

Evidence:
-1218PASS0skip broad regression: steel account/page/domain/draft/full-skill tests, generic account isolation, ISO session save/animation/owner tests, speech session lifecycle, core brain and router. build/steel-owner-regression.log.
-Final11PASS ownership/session cases: guest legacy retention; A/B independence; captured-owner rejection; deliberately delayed actual in-memory preferences write; false disk result; live page A→B→A; pending autosave before B; failed save blocks activation/retries; forced revocation closes old edit dialog; unknown owner never reads guest; load retry; normal Back persistence. build/steel-owner-session-tests.log. The11 count includes store and widget scenarios; these are local fixture accounts, no production credentials.
-Seven changed Dart files fatal-info clean: build/steel-owner-analyze.log. Additional native SteelWeightPage smoke at text scale1.3 passed: build/steel-owner-smoke.log.
-Added only an existing resolved platform interface as a direct dev dependency for controlled preferences tests. Lock staging changes only that dependency's transitive→direct-dev metadata; unrelated pre-existing lock upgrades remain unstaged.

Test-fixture lesson: preserve existing seedGuestAccount/seedSignedInAccount helpers. Fresh widget account fixtures must not retain a storage-tail Future created in an outer real-async setup. Initialize them in the appropriate test zone and use bounded widget pumps for completion. A preferences-only widget suite must not reuse a settle helper that flushes SQLite without configuring a private test database. Corrected fixture failures are not production evidence; only final passing logs are acceptance.

Limits: local lists are partitioned on this phone, not synchronized to Railway. Old device lists remain accessible to the guest and are not automatically assigned to an account. Forced credential revocation can discard pending debounce-only edits; it never redirects them to the next owner. Programmatic forced disposal is not claimed lossless. Existing backup intentionally excludes all SharedPreferences. Actual hardware/storage failure behavior remains unverified.

No AI model, provider call, budget, pricing or backend changed. Production empty unauthenticated assistant request2026-10-22T07:20:43.418730Z still404 (build/steel-owner-production-probe.json). Railway OTP/platform recovery and legal6 production rollout remain pending; no new APK.

The assistant add-to-list command itself is not implemented by this prerequisite. Next: a native prepared record action with confirmation, captured owner/form snapshot, durable awaited save, idempotent retry and coherent Undo. Full assistant goal stays active. Prior5b2ee9c was verified progress.
