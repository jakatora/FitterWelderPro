# Exact signed-release native smoke test

This standalone Android host exists ONLY to compile the instrumentation APK. NEVER upload/install/distribute its host APK. Test Lab must receive the already verified shipped FitterWelder Pro0.5.20 APK as appApk, with the unchanged SHA256 hardcoded by the test. Both APK signatures must match the existing release certificate.

The test asserts the installed APK hash and non-debuggable flag, seeds only a fresh owned installation identity, disables device networking, navigates the actual release UI through Android accessibility navigation and focused keyboard input, and checks native pipe mass. No Dart integration code, response mocks, AI requests or public-room interactions. Finally networking is restored and the owned installation is deleted. A recovery credential file is retained ONLY if cleanup fails; it is not logged and must be fetched privately and cleaned before removing it.

Code uses framework UiAutomation rather than a modified Flutter app. Native result/screenshot/report support this narrow offline release-runtime scope, not microphone, AI conversation, iOS or16KB runtime.

Validated2026-11-02 on virtual ARM64/API35: matrix-2isgs4zu4saaz SUCCESS, exact shipped SHA256 matched, offline mass5.541kg/m and11.08kg for2x1000mm, owned-fixture cleanup200 and recovery file removed. Earlier harness failures and their fixes are retained in release-native-qa-attempt-history.json in the dated artifacts directory. Numeric input uses END+32 DEL followed by typing; every focused field must contain the exact requested text before result checks.
