# Natural ISO summary requests — 2026-10-22

Polite Polish/English requests to summarize the current drawing and count its pipes now use the native foreground snapshot directly. Examples: "Czy możesz podsumować aktualny rysunek ISO?", "Could you please summarize the current ISO drawing?" and "Powiedz mi ile rur jest w aktualnym szkicu". This avoids an AI interpretation request for these known read-only operations. Other prose can still use the AI proposal route; its numeric answer remains native.

Translation/explanation frames and English apostrophe negation cannot authorize a summary proposal merely because the source contains drawing/count keywords. Shared referencesInstruction detection is used before proposal acceptance.

Evidence: initial failing local-match test reproduced the polite-request gap. After implementation, the old integration expectation of one AI request failed with actual zero; updated integration scenarios explicitly verify zero for polite PL/EN, and one for a separate unrestricted paraphrase. Actual mounted ISO, native CUT calculation and real SQLite prove answer values and unchanged drawing JSON/identity/revision. Missing CUT, unavailable foreground, stale knowledge context, negation and instruction-reference regressions retained. Final 38 tests passed; three-file fatal analysis clean. No paid provider calls or model/budget configuration changes.

No APK delivered: the earlier registration-consent fix in this branch requires backend deployment first (see 2026-10-22-account-consent-version.md). Full live assistant/provider/device acceptance remains open.
