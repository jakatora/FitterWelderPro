# Physical Android assistant QA

This branch contains a diagnostic integration-test build based on release source 0.5.16. It does not change the production `lib/` sources and is not a replacement release APK. Keep the integration SDK and instrumentation setup isolated from production packaging until separately reviewed.

`live_assistant_test.dart` boots the actual app, opens the assistant, enters a DN question, accepts the consent screen, uses the real HTTP transport and verifies the returned answer on screen. There are no mocked provider, platform or backend responses. It allows one explicit AI request and no retry. The microphone is not tested.

The test refuses to run without `FWP_LIVE_AI_QA=true` and valid `FWP_QA_DEVICE_ID` / `FWP_QA_INSTALL_SECRET` values. Supply these from a private JSON file **outside the repository** via `--dart-define-from-file`; generate a disposable UUID and random installation secret, never use an account or a real user's installation. Retain the private file until cleanup is confirmed, for recovery if the device process crashes. The test checks that preferences are empty before seeding only that disposable identity. The app still performs its real consent and request flow. It deletes only its own installation through `/api/fitter/me` in cleanup.

Android instrumentation follows the installed Flutter SDK integration_test example: AndroidJUnitRunner and FlutterTestRunner with MainActivityTest. Debug and androidTest configurations use matching runner/Espresso versions to satisfy AGP consistent dependency resolution. Both the app APK and Android Test APK must be built with the same private Dart defines and verified before dispatch. Run only the MainActivityTest class, no sharding or flaky retries. Observe an existing matrix rather than launching again after an observation timeout.

A real Test Lab run on physical Pixel 8 / API35 / pl_PL succeeded on 2026-11-02: matrix `matrix-1if37wiuxrmr7`, one native testcase, zero failures/skips, one real `/api/fitter/ai/chat` HTTP200 response displayed in the UI, cleanup HTTP200/ok. The test logs base64 chunks prefixed `FWP_DEVICE_QA_REPORT`; they contain only the response and non-secret outcome metadata. Independently inspected video shows the response in the assistant panel. This does not prove release-AOT behavior, voice recognition, all conversational flows or arbitrary technical correctness.

Artifacts and build history are in the local `G:/Projekty/FitterWelderPro-artifacts/2026-11-02` directory. Test Lab: https://console.firebase.google.com/project/fitter-welder-pro/testlab/histories/bh.b011b172b6d018b9/matrices/7979772547584698356

## Two-turn conversation scenario (not yet device-verified)

Set `FWP_QA_FOLLOWUP=true` in addition to the existing explicit QA opt-in. This scenario permits at most two real chat requests with no retry. After the DN question it asks a contextual follow-up without repeating DN. It asserts the actual outgoing second JSON request contains the exact previous user/assistant exchange, the backend returns a direct answer, and both answers appear in the real UI. Request evidence records only message/history, never identity or headers. Each response is recorded for independent semantic review. The same fresh-install and owned-fixture cleanup protections apply.

Use new guarded build, upload and matrix intents for this changed test; previous single-turn success does not prove this scenario. This scenario does not test microphone or app navigation.
