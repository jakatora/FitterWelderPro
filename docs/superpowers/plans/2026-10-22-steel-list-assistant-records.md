# Native assistant steel-list records — 2026-10-22

Status: implemented and locally verified; production rollout remains pending Railway authentication/recovery.

`steel.item.add` prepares an immutable native summary from the visible Steel weight Profile draft. The assistant asks for confirmation before saving. AI can normalize ordinary PL/EN prose, but cannot supply record IDs, prices or callbacks. Requests that change quantities, dimensions, materials, recipients or another record cannot be silently reduced to this operation.

The prepared action captures the account, page generation, draft fields and edit revision. Native UUID identity makes concurrent execution and retries idempotent. Saving waits for prior edits, rereads persisted state, preserves other rows and prices, writes, then verifies persisted content before reporting success. Cancellation after an uncertain disk failure does not claim that nothing was saved. Unacknowledged mutations are not silently retried by autosave.

Undo removes only the exact tagged record; identical manual rows and later unrelated records remain. An externally edited tagged row is not removed. Identity changes reject stale confirmations and Undo. Normal account switches wait for an in-flight save; forced revocation cannot redirect an old write into the new account.

Bound stores serialize writes and use optimistic baseline checks. Fresh reads alone do not rebase a stale page. Conflicts expose an explicit reload action. Corrupt saved data and invalid IDs are not normalized into destructive overwrites. Invalid geometry, non-finite prices and values exceeding exact integer monetary range are rejected before saving. Existing item/list price bases, allowance and grosz formulas are retained; no Stripe operations or price-setting AI action were added.

## Verification

- 1359 Flutter tests passed, zero skipped: record actions, account ownership, steel draft/domain, router/brain, confirmations, queued AI, sessions, speech and wire export.
- Ten changed Dart files analyzed with `--fatal-infos`: no issues.
- Native SteelWeightPage smoke test at text scale 1.3 passed.
- Full catalog contract: 75 capabilities, PL 35653 bytes / EN 34918 bytes; local real Express/SQLite backend c376dead13b97c31a7a589db2fe2189d6183bf0a returned HTTP 200 with injected provider. Asserted model `claude-haiku-5-5`, low effort and zero retries. No paid AI calls.
- Controlled preferences tests cover rejection before persistence, false after persistence, acknowledgment without persistence, retry, concurrent confirmation, stale state, edited Undo target and pending account changes. Simulated speech confirms quantity-plus-add and local confirmation with one injected AI call.

## Limits

Storage is local and scoped by account, not cloud synchronization. Tests use controlled preferences and simulated speech, not a physical phone or live model. Existing forced revocation may discard debounce-only manual edits; forced programmatic disposal is not asserted lossless. Railway OTP recovery and updated legal-consent backend deployment remain prerequisites for distributing a new APK. Production model configuration has not been verified. Full assistant scope remains active.
