# Reguly R8/ProGuard dla Fitter Welder Pro.
# Wtyczka Flutter Gradle sama dodaje keepy dla silnika i zarejestrowanych
# pluginow, ale ponizej trzymamy jawnie rzeczy, ktore R8 lubi wyciac przez
# refleksje albo o ktore sypie ostrzezeniami przy budowie.

# ── Flutter engine ─────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── Google Play Core / feature delivery ────────────────────────────────────
# Flutter odwoluje sie do Play Core (deferred components / SplitCompat). Nawet
# gdy apka ich nie uzywa, R8 sypie "missing class" i wywala build — wyciszamy.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# ── Zachowaj adnotacje i sygnatury (potrzebne wtyczkom natywnym) ────────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ── Wtyczki natywne uzywane w apce ─────────────────────────────────────────
# image_picker / file_picker / share_plus / path_provider / sqflite /
# url_launcher / shared_preferences — komunikuja sie przez MethodChannel i sa
# objete keepami Fluttera, ale nie ruszamy ich klas API na wszelki wypadek.
-keep class androidx.lifecycle.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Kotlin metadata (bez tego niektore biblioteki gubia informacje o typach).
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
