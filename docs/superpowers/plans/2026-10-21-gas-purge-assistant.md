# Gas and purge assistant integration — 2026-10-21

Added `gas.consumption` and `purge.estimate`, using the existing welding domain functions and actual WelderToolsScreen forms. The public catalog includes six PL/EN examples and three rejection cases for each capability. Native gas/purge inputs are validated before changing tabs or controllers; the existing timer input contract is preserved.

Gas consumption requires weld count, time and torch flow. Existing app presets for pre/post-flow and cylinders are stated in the answer. A partial purge flow/time pair asks for the missing value. Purge estimation requires an explicit O₂ target, reports the assumed initial concentration and does not start a timer. It is an estimate requiring analyser/WPS verification.

Selected gas/purge tabs expose their actual fields through InputToolHandle. Timer and pressure tabs expose only their tab discriminator. Numeric controller assignments use decimalInputText to preserve finite exponent values without falling back to presets.

Verification: 2582 tests passed, 38 pre-existing missing-example fixture skips, zero failures. Scope: full assistant, welding gas/purge domain, welder calculator fixes and timer screens. Log: build/welder-gas-final-regression.log. Router: 500 utterances in 671 ms. Five changed Dart files pass dart analyze --fatal-infos (build/welder-gas-final-analyze.log). After the full regression only a local argument was renamed for lint compliance.

Ten new integration cases cover independent arithmetic, invalid payloads, required O₂ target, incorrect units, pending replies, actual native text and mocked-speech execution, controlled AI edits, late responses after a same-handle tab change, and decimal input precision. These are not physical microphone or new live-provider evidence. Earlier failing logs include a parser boundary regression and a fake-frame test wait; the final run supersedes them.

Deployment remains unverified. CLI authentication timed out previously; a fresh browser inspection also showed signed-out Railway and GitHub. No credentials were entered or infrastructure changed; the browser returned to Railway activation. Backend main remains 3db3277, and the last production assistant endpoint probe returned 404.

The full goal remains active. Remaining examples: spoken flow units beyond canonical L/min, contextual purge-timer start, standalone cylinder-remaining calculation, native pressure-tab controls, other module actions/inputs, compound requests, standalone ordered ISO handoff, account-local record ownership, topology audit, real-provider/production deployment and physical microphone/iOS acceptance. The shared automatic-open heuristic does not yet include estimate/oszacuj, although the new skills answer them and expose ShowInModule.
