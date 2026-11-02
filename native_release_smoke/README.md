# Exact signed-release native smoke test

This standalone Android host exists ONLY to compile the instrumentation APK. NEVER upload/install/distribute its host APK. Test Lab must receive the already verified shipped FitterWelder Pro0.5.20 APK as appApk, with the unchanged SHA256 hardcoded by the test. Both APK signatures must match the existing release certificate.

The test asserts the installed APK hash and non-debuggable flag, seeds only a fresh owned installation identity, disables device networking, navigates the actual release UI through Android accessibility actions, and checks native pipe mass. No Dart integration code, response mocks, AI requests or public-room interactions. Finally networking is restored and the owned installation is deleted. A recovery credential file is retained ONLY if cleanup fails; it is not logged and must be fetched privately and cleaned before removing it.

Code uses framework UiAutomation rather than a modified Flutter app. Native result/screenshot/report support this narrow offline release-runtime scope, not microphone, AI conversation, iOS or16KB runtime.
