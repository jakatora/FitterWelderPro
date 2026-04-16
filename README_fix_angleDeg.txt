FIX for build error: 'angleDeg' required

Replace:
  lib/models/library_component.dart
with the one included in this zip.

It makes 'angleDeg' OPTIONAL (nullable) so existing code that creates LibraryComponent(...)
does not need to pass angleDeg.

Then run:
  flutter clean
  flutter pub get
  flutter run -d windows
