# Production assistant probe — 2026-11-02

Against backend `750cecd`, three explicit HTTP requests to the authenticated audit endpoint completed with HTTP 200:

1. DN definition.
2. “A NPS 1?” with the first exchange in history.
3. P91 PWHT excursion question in a fresh topic.

Manual review found preserved conversation and no module-selection detour. The P91 response reflected the corrected distinction between procedure limits and Ac1. This was ordinary knowledge answering, with no external research trace. Installation registration and deletion both succeeded; private fixture credentials were removed. No automatic retries or quota bypass occurred. Exact monetary charges were not exposed by these responses.

Evidence: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/live-assistant-quality-20261102.json`, including the full replies, context titles, cleanup status and source checks. This is a backend probe, not physical app/microphone validation or proof of all answer correctness.

The first DN response retrieved an unrelated refractory-pipe context first. A regression reproduced that ranking, then backend `6617d7f` added DN/NPS nominal-size query expansion. The same query now ranks nominal-size knowledge first locally; all 526 backend tests passed. The three live outputs precede this ranking change; no claim that the changed ranking has already had a second paid live-model test.
