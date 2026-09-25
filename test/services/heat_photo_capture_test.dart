// Zdjęcie numeru wytopu: skąd (aparat / galeria / plik) i w jakim rozmiarze.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cut_list_app/services/heat_photo_capture.dart';

class _RecordingImagePicker extends ImagePicker {
  ImageSource? source;
  double? maxWidth;
  double? maxHeight;
  int? imageQuality;
  bool? requestFullMetadata;
  String? result = '/cache/image_picker123.jpg';

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    this.imageQuality = imageQuality;
    this.requestFullMetadata = requestFullMetadata;
    return result == null ? null : XFile(result!);
  }
}

void main() {
  group('źródła zdjęcia na platformie', () {
    test('telefon: aparat i galeria (aparat pierwszy)', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(heatPhotoSourcesFor(isWeb: false, platform: platform),
            [HeatPhotoSource.camera, HeatPhotoSource.gallery],
            reason: '$platform');
      }
    });

    test('Windows, web i desktop: tylko plik', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(heatPhotoSourcesFor(isWeb: false, platform: platform),
            [HeatPhotoSource.files],
            reason: '$platform');
      }
      // Przeglądarka na telefonie też nie ma aparatu przez image_picker.
      expect(
          heatPhotoSourcesFor(isWeb: true, platform: TargetPlatform.android),
          [HeatPhotoSource.files]);
    });
  });

  group('SystemHeatPhotoPicker', () {
    test('aparat: zdjęcie zmniejszone do ~2000 px, JPEG 85, bez metadanych',
        () async {
      final ip = _RecordingImagePicker();
      final path =
          await SystemHeatPhotoPicker(imagePicker: ip).pick(HeatPhotoSource.camera);
      expect(path, '/cache/image_picker123.jpg');
      expect(ip.source, ImageSource.camera);
      expect(ip.maxWidth, 2000);
      expect(ip.maxHeight, 2000);
      expect(ip.imageQuality, 85);
      expect(ip.requestFullMetadata, isFalse,
          reason: 'iOS nie pyta wtedy o dostęp do całej biblioteki');
    });

    test('galeria: te same limity rozmiaru', () async {
      final ip = _RecordingImagePicker();
      await SystemHeatPhotoPicker(imagePicker: ip).pick(HeatPhotoSource.gallery);
      expect(ip.source, ImageSource.gallery);
      expect(ip.maxWidth, kHeatPhotoMaxSide);
      expect(ip.imageQuality, kHeatPhotoQuality);
    });

    test('anulowany aparat = null', () async {
      final ip = _RecordingImagePicker()..result = null;
      expect(
          await SystemHeatPhotoPicker(imagePicker: ip)
              .pick(HeatPhotoSource.camera),
          isNull);
    });
  });
}
