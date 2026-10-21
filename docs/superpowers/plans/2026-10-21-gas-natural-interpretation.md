# Natural gas commands — 2026-10-21

Gas and purge commands now normalize spoken flow units (including litres per hour/second and millilitres per minute) into native L/min. Complete supported commands remain local. Partially understood quantities and arithmetic go through the existing cheap AI interpreter; absent consent, unavailable AI, or an unnormalized model echo cannot execute a partial calculation.

The core exposes an opt-in interpretation requirement. Gas/purge contextual edits use the actual visible input snapshot through AI rather than silently replaying stale conversation values. This policy is not yet enabled for every calculator. Pending scalar replies cannot discard additional unknown quantities. Exact supported composite replies remain local. A strong new gas command supersedes an old ISO question and its queued drawing actions.

Validation: 2604 tests passed, 38 pre-existing fixture skips, zero failures (build/gas-interpretation-final-regression.log). Router: 500 utterances in 699 ms. Five changed Dart files pass analyze --fatal-infos (build/gas-interpretation-final-analyze.log). Twenty-two new tests cover native text/mocked speech, conversions, ambiguous values, controlled AI normalization, native form context, unavailable AI, pending question preservation and ISO queue cancellation.

These tests use a controlled interpreter, not a new live-provider or physical microphone run. No backend/model/budget changes: chat and command defaults remain claude-haiku-5-5. Production interpreter deployment is still unverified: last endpoint probe was 404 and Railway authentication needs renewal. The overall assistant goal remains active.
