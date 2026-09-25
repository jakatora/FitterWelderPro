/// Skąd bierzemy zdjęcie numeru wytopu (heat) / atestu: aparat, galeria
/// albo plik.
///
/// Monter stoi przy rurze z telefonem — zdjęcie etykiety robi się aparatem,
/// nie szuka potem w galerii. Na Androidzie / iOS: aparat i galeria przez
/// `image_picker`; na Windows, web i reszcie desktopu — tylko wybór pliku
/// (`file_picker`), bo tam nie ma systemowego okna aparatu.
///
/// Uprawnienia:
///  • Android — aparat przez intencję systemową (ACTION_IMAGE_CAPTURE),
///    galeria przez systemowy Photo Picker: BEZ uprawnienia CAMERA ani
///    READ_MEDIA_IMAGES. Uwaga: dopisanie CAMERA do manifestu (np. przez inną
///    wtyczkę) sprawi, że intencja aparatu będzie wymagać zgody — patrz
///    README image_picker.
///  • iOS — `NSCameraUsageDescription` w Info.plist (PL/EN). Galeria przez
///    PHPicker z `requestFullMetadata: false` nie pyta o dostęp do biblioteki.
///
/// Zdjęcie jest zmniejszane (dłuższy bok ≤ [kHeatPhotoMaxSide] px, JPEG
/// [kHeatPhotoQuality]) — numer wytopu nadal czytelny, a kopia zapasowa nie
/// puchnie o 5–10 MB na zdjęcie. Zwracana ścieżka to plik tymczasowy
/// wtyczki: trwałą kopię w `<documents>/heat_photos` robi
/// `persistPickedHeatPhoto` (heat_photo_storage.dart).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum HeatPhotoSource { camera, gallery, files }

/// Dłuższy bok zmniejszonego zdjęcia (px).
const double kHeatPhotoMaxSide = 2000;

/// Jakość JPEG zmniejszonego zdjęcia (0–100).
const int kHeatPhotoQuality = 85;

/// Źródła dostępne na platformie — kolejność = kolejność przycisków.
List<HeatPhotoSource> heatPhotoSourcesFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (!isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS)) {
    return const [HeatPhotoSource.camera, HeatPhotoSource.gallery];
  }
  return const [HeatPhotoSource.files];
}

/// Źródła na bieżącej platformie.
List<HeatPhotoSource> currentHeatPhotoSources() =>
    heatPhotoSourcesFor(isWeb: kIsWeb, platform: defaultTargetPlatform);

/// Wybór zdjęcia — interfejs, żeby testy podstawiły atrapę.
abstract class HeatPhotoPicker {
  /// Ścieżka wybranego / zrobionego zdjęcia albo `null` (anulowano).
  /// Może rzucić `PlatformException` (np. brak zgody na aparat).
  Future<String?> pick(HeatPhotoSource source);

  /// Android: zdjęcie z aparatu, którego wynik zginął, bo system zabił
  /// aplikację w trakcie robienia zdjęcia. `null` gdy nic nie czeka.
  Future<String?> retrieveLost();

  static HeatPhotoPicker instance = SystemHeatPhotoPicker();
}

class SystemHeatPhotoPicker implements HeatPhotoPicker {
  SystemHeatPhotoPicker({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<String?> pick(HeatPhotoSource source) async {
    switch (source) {
      case HeatPhotoSource.camera:
      case HeatPhotoSource.gallery:
        final file = await _imagePicker.pickImage(
          source: source == HeatPhotoSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: kHeatPhotoMaxSide,
          maxHeight: kHeatPhotoMaxSide,
          imageQuality: kHeatPhotoQuality,
          // Tylko obraz — bez pełnych metadanych iOS nie wymaga zgody na
          // dostęp do całej biblioteki zdjęć.
          requestFullMetadata: false,
        );
        return file?.path;
      case HeatPhotoSource.files:
        final picked = await FilePicker.platform
            .pickFiles(type: FileType.image, allowMultiple: false);
        if (picked == null || picked.files.isEmpty) return null;
        return picked.files.single.path;
    }
  }

  @override
  Future<String?> retrieveLost() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _imagePicker.retrieveLostData();
    if (response.isEmpty) return null;
    return response.file?.path;
  }
}
