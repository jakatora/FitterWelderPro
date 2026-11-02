# Production assistant probe — 2026-11-02

Against backend `750cecd`, three explicit HTTP requests to the authenticated audit endpoint completed with HTTP 200:

1. DN definition.
2. “A NPS 1?” with the first exchange in history.
3. P91 PWHT excursion question in a fresh topic.

Manual review found preserved conversation and no module-selection detour. The P91 response reflected the corrected distinction between procedure limits and Ac1. This was ordinary knowledge answering, with no external research trace. Installation registration and deletion both succeeded; private fixture credentials were removed. No automatic retries or quota bypass occurred. Exact monetary charges were not exposed by these responses.

Evidence: `G:/Projekty/FitterWelderPro-artifacts/2026-11-02/live-assistant-quality-20261102.json`, including the full replies, context titles, cleanup status and source checks. This is a backend probe, not physical app/microphone validation or proof of all answer correctness.

The first DN response retrieved an unrelated refractory-pipe context first. A regression reproduced that ranking, then backend `6617d7f` added DN/NPS nominal-size query expansion. The same query now ranks nominal-size knowledge first locally; all 526 backend tests passed. The three live outputs precede this ranking change; no claim that the changed ranking has already had a second paid live-model test.


Retrieval follow-up: six PL/EN questions cover attached DN25/NPS1 and Schedule/pressure/wall-thickness queries. Two initially failed: English DN25 chose pulsation-dampener knowledge, and the English Schedule-pressure question lacked the pipe-Schedule section in the top four. Backend `05f17e7` extends nominal-size recognition to attached digits and maps explicitly numbered Schedule designators to pipe dimensions and their dimensional standards. All 532 backend tests passed. This does not add provider calls, change monthly/daily limits or assert a second live-model result. No general work-schedule phrase is expanded unless it has a numeric pipe-designator form.


Timed-schedule boundary: two queries about maintenance/work “schedule 40 hours” initially selected pipe-Schedule context. Backend `8f4577d` prevents pipe-designator expansion when the numeric value is immediately followed by a time unit. Existing dimensional queries remain covered. All 534 backend tests passed; this correction adds no provider calls. This is a local retrieval regression, not an additional paid live-model probe.
