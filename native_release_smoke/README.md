# Exact signed-release native smoke test

This standalone Android host exists ONLY to compile the instrumentation APK. NEVER upload/install/distribute its host APK. Test Lab must receive the already verified shipped FitterWelder Pro APK for the explicitly selected test class as appApk, with the unchanged SHA256 hardcoded by the test. Both APK signatures must match the existing release certificate.

The test asserts the installed APK hash and non-debuggable flag, seeds only a fresh owned installation identity, disables device networking, navigates the actual release UI through Android accessibility navigation and focused keyboard input, and checks native pipe mass. No Dart integration code, response mocks, AI requests or public-room interactions. Finally networking is restored and the owned installation is deleted. A recovery credential file is retained ONLY if cleanup fails; it is not logged and must be fetched privately and cleaned before removing it.

Code uses framework UiAutomation rather than a modified Flutter app. Native result/screenshot/report support this narrow offline release-runtime scope, not microphone, AI conversation, iOS or16KB runtime.

Validated2026-11-02 on virtual ARM64/API35: matrix-2isgs4zu4saaz SUCCESS, exact shipped SHA256 matched, offline mass5.541kg/m and11.08kg for2x1000mm, owned-fixture cleanup200 and recovery file removed. Earlier harness failures and their fixes are retained in release-native-qa-attempt-history.json in the dated artifacts directory. Numeric input uses END+32 DEL followed by typing; every focused field must contain the exact requested text before result checks.

For0.5.21 select ONLY `com.startklaar.fitterwelder.releaseqa.Release0521SmokeTest` as testTargets. The older ReleaseSmokeTest deliberately remains pinned to0.5.20; do not run both classes against one APK. Release0521SmokeTest verifies installed SHA2561f06bce690cedd4a1f48da582e3edfd0a1655f8040fe076b4bfa76c51a2f0037 and version0.5.21, searches DN50, checks the native DN50 field and OD60.30 table entry, returns to Home and checks offline mass5.541kg/m and11.08kg. Matrix-2phllj0l6e1ce passed on virtual ARM64/API35 on2026-11-02, with both native screenshots inspected and owned fixture cleanup200/recovery removed. This does not test retry drafts, AI conversation or voice. Detailed evidence is release0521-native-qa-verification.json in the dated artifacts directory.

For 0.5.23 select ONLY `com.startklaar.fitterwelder.releaseqa.Release0523SmokeTest`; it checks version 0.5.23 and SHA256 `20721f63c80c46ffc4c0cf978d7f8185d3d4b1f481eeb67e27f492d5e75eed02`. The instrumentation APK compiled on 2026-11-02; this alone is not an execution result.

For 0.5.24 select ONLY `com.startklaar.fitterwelder.releaseqa.Release0524SmokeTest`; it checks version 0.5.24 and SHA256 `a3802eb2430ac925bd2422f06a1fb4393f206ee23b3bb9952968af626d8da099`. Compiling the instrumentation APK is not evidence of execution.
