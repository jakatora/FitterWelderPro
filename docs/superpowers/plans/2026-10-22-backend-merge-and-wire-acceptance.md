# Backend merge and catalog acceptance — 2026-10-22

Backend [PR10](https://github.com/jakatora/fitter-welder-pro-backend/pull/10) was merged at c05432031707f00bb7892f39f40ab6ed8a4adca9 on 2026-10-22T06:03:06Z. GitHub connector checks before merge showed mergeable=true, no combined statuses and no pull-request workflow runs for expected head ebdd2db23deb24ccf4f99128c017f4be85f05d62. No successful CI run is claimed. The normal merge used the exact expected-head guard.

The complete backend suite was rerun under Node24.19.0:220 passed, zero skipped. Log: build/backend-pr10-premerge-verified.log. Tested source and merged main have identical tree7a3bd6b7dd5b1fd1f4f8ae3fb68da3e6c495fcc3. The clean nested backend/main checkout was fast-forwarded to the merge. The canonical worktree retains its original feature branch with the same source tree; future backend branches should start from updated main.

New cross-runtime acceptance exports the real current Flutter catalog with legacy actions and ISO, transition inputs, maximum-length text and six maximum-length synthetic Unicode history entries. Those exact PL/EN payloads pass through real local HTTP, Express, SQLite and device registration to an injected provider. No real account/profile data or paid calls are involved.

Both requests returned HTTP200:71 capabilities; PL34812UTF8bytes and EN34110UTF8bytes, below64000. Catalog, visible inputs and language reach the provider unchanged. Assertions cover claude-haiku-5-5, low effort, zero retries,25s timeout and released in-flight reservation. This proves transport/schema compatibility, not actual model understanding or production operation.

Reproduce from the app root: Flutter test test/assistant/assistant_wire_export_test.dart, then node tool/verify_assistant_wire.mjs backend (or an explicit backend path). Two fixture tests and11 existing interpreter tests passed; fixture analysis is clean. Logs: build/assistant-full-wire-export.log, assistant-current-wire-contract.log, assistant-wire-backend-acceptance.log and assistant-wire-export-analyze.log. Machine-readable proof: build/assistant-wire-backend-proof.json.

Deployment remains unverified: the production assistant endpoint returned404 at2026-10-22T06:03:34Z and Railway CLI is unauthorized. A project-specific Anthropic key is still absent from the vault. No deployment or new APK occurred; the registration-version6 client still needs server rollout. Latest delivered APK remains5806c1e. Full assistant scope, real model quality and phone acceptance remain open.
