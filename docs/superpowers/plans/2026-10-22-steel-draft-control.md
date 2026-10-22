# Live steel calculator control — 2026-10-22

The Steel weight page now exposes its visible Profile-tab inputs through InputToolHandle: shape, selected section, material, canonical dimensions, length and actual quantity. Prices, allowance, saved order items and identifiers are absent. Loading, inactive routes and the saved-list tab do not expose a valid draft. Direct application rejects a background or popup-obscured route.

New catalog capabilities:
- steel.draft.edit changes only explicit length (unit required) or positive whole quantity, merging it with actual current inputs. The existing steelDraftFromFields domain validates the complete result. An explicitly requested correction can repair its own invalid field; it cannot supply defaults for other invalid fields. No order save/add, price or allowance update.
- steel.draft.summary reads current total mass, count, per-piece length and material using the existing mass engine and its source standard/density. It has no form changes or navigation.

Conversational requests such as “potrzebuję5takich sztuk”, “niech długość wynosi3m” and “a długość3m” can be normalized by AI. The native source guard independently preserves the requested field/value/unit and refuses invented numbers, mixed fields, malformed units, negative lengths, noninteger counts, translations and advice. Generic edits do not steal another module. Canonical examples explicitly name steel; outside a visible calculator they return guidance, without claiming completion.

The old full SteelWeightSkill now marks visible-form continuations for AI instead of merging stale conversation values. Its model-proposal guard compares source and target parameters and rejects missing-data invention. Raw negative punctuation is retained as an invalid quantity instead of becoming positive during folding.

Evidence:
-1192PASS0skip: new live steel tests, prior full steel skill, domain mass/order tests, native page tests, full wire fixtures, core brain and global router corpus. Log build/steel-draft-regression.log.
-All13SteelShape values tested through actual page: shape/material/section preserved, length2m→3m and quantity2→5, readback agrees with domain mass, same handle, store.saves0. Existing saved IPE100 and price4.5 preserved.
-Actual UI count edits7/0 read correctly. Changing length with invalid quantity cannot silently repair it; explicitly setting quantity5 repairs only that field.
-Simulated speech with spoken Polish quantity rejects a model-invented6 and accepts5. Deferred AI responses are discarded after input changes. Continuation after an earlier IPE calculation uses manually changed hollow/aluminium inputs; a model replaying old IPE parameters is refused. Popup and saved-list tab guards verified.
-Five changed Dart files pass fatal-info analysis: build/steel-draft-analyze.log. No Dart changes after checks.
-Real local backend HTTP accepts updated74-capability catalog, PL35390bytes/EN34681bytes, both200, backendmainc376dead13b97c31a7a589db2fe2189d6183bf0a. Provider injected, zero paid calls: build/steel-draft-wire.log.

Cost/accounting review: no provider invocation, budget, retry, model, pricing or persisted order path changed. Literal calculator edits/readback are local; natural requests reuse the existing Haiku interpreter and its budget gate. Live provider behavior, hardware microphone and production billing remain unverified.

Production invalid-empty-body assistant probe2026-10-22T06:55:50.665320Z still404: build/steel-draft-production-probe.json. Railway OTP/recovery handoff remains pending. No new APK because registrationlegal6 requires server rollout first. Previous02b7440goal turn was verified progress; full goal remains active, including remaining app actions, real model/device verification and deployment.
