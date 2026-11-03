# Local flutter_tts patch

Based on flutter_tts 4.2.5 from pub.dev; the upstream license is in LICENSE.
The app uses this local copy so the Windows MediaEnded callback can return
to the platform apartment before invoking a Flutter channel or completing a
method result. Late callbacks from closed players and destroyed plugins are
ignored, and a pending result is completed at most once. Speech synthesis
also returns to the platform apartment and checks that its player still
belongs to the active request before starting playback.

Re-evaluate this patch when upgrading flutter_tts. Android, iOS, macOS, and web
sources are copied from the same upstream version and are not modified here.
