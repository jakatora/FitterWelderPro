# Conversational development edits — 2026-10-22

The AI interpreter may normalize conversational PL/EN references to the active development (for example, “Zrób go wyższego o 10 cm” / “Make it taller by 10 cm”). The native executor verifies direction, amount, units and the current valid geometry independently. A guessed amount cannot pass the source guard.

For “Zrób go trochę wyższego”, AI may propose `Zwiększ wysokość`. This opens a native `amount` question without changing geometry. A subsequent explicit length fills only that owned slot. The question retains the current canonical input snapshot; changing geometry before answering rejects the operation. Cancel leaves inputs unchanged. Negative/missing/duplicated units, mixed dimensions, negation, translation and advice do not authorize a change. This extends height editing, not arbitrary natural-language control of all fields.

Validation:
- 1125 tests passed, no skips: conversational/relative/absolute height, development Undo, wire fixtures, core brain and router corpus (`build/development-conversational-regression.log`).
- New widget tests operate the actual native calculator for concentric/eccentric cones and rectangle-circle transitions. They cover a two-turn question, manual changes while waiting, simulated microphone input and deliberately incorrect model arithmetic. The AI response is injected; no actual provider-quality or hardware claim.
- Fatal-info analysis of both changed Dart files passed (`build/development-conversational-analyze.log`).
- Generated full catalog requests accepted by the real local backend HTTP handler: PL34986bytes/EN34285bytes, 72 capabilities, both200, backend main c054320 (`build/development-conversational-wire.log`). Provider injected, zero paid calls.

Cost review: no provider invocation, model setting, reservation, retry or accounting path changed. Explicit local follow-up values need no extra paid call. Current source defaults both chat and intent to claude-haiku-5-5. Official model ID and pricing rechecked at https://platform.claude.com/docs/en/models/haiku-5-5/overview on 2026-10-22: $0.10 input/$0.50 output per million tokens up to100000 prompt tokens; higher-context tier $0.50/$2.50. Existing backend pricing matches those tiers. Live provider credentials and production environment remain unverified.

Railway recheck: existing activate tab is still the six-field Magic OTP form for the known owner. No OTP extraction/resend, credential changes or deployment attempted. User handoff remains pending. Registration legal6 requires updated backend before distributing a new APK. Full assistant goal remains open.
