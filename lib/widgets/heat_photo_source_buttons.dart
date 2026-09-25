/// „Aparat / Galeria” dla zdjęcia numeru wytopu (heat) — duże przyciski
/// pod rękawice. Na Windows / web / desktopie jeden przycisk „Wybierz plik”.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../services/heat_photo_capture.dart';

/// Minimalna wysokość przycisku źródła zdjęcia (rękawice).
const double kHeatPhotoButtonHeight = 64;

String heatPhotoSourceLabel(BuildContext context, HeatPhotoSource source) =>
    switch (source) {
      HeatPhotoSource.camera => context.tr(pl: 'Aparat', en: 'Camera'),
      HeatPhotoSource.gallery => context.tr(pl: 'Galeria', en: 'Gallery'),
      HeatPhotoSource.files => context.tr(pl: 'Wybierz plik', en: 'Choose file'),
    };

IconData heatPhotoSourceIcon(HeatPhotoSource source) => switch (source) {
      HeatPhotoSource.camera => Icons.photo_camera,
      HeatPhotoSource.gallery => Icons.photo_library_outlined,
      HeatPhotoSource.files => Icons.folder_open,
    };

/// Otwiera wybrane źródło. `null` = anulowano albo błąd (komunikat
/// pokazany na dole ekranu).
Future<String?> pickHeatPhoto(BuildContext context, HeatPhotoSource source) async {
  try {
    return await HeatPhotoPicker.instance.pick(source);
  } on PlatformException catch (e) {
    debugPrint('pickHeatPhoto($source): ${e.code} ${e.message}');
    if (!context.mounted) return null;
    final text = switch (e.code) {
      'camera_access_denied' => context.tr(
          pl: 'Brak zgody na aparat — włącz ją w ustawieniach telefonu.',
          en: 'No camera permission — enable it in the phone settings.'),
      'no_available_camera' => context.tr(
          pl: 'Ten telefon nie ma dostępnego aparatu — wybierz z galerii.',
          en: 'No camera available on this device — pick from the gallery.'),
      _ => context.tr(
          pl: 'Nie udało się pobrać zdjęcia.', en: 'Could not get the photo.'),
    };
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
    return null;
  } catch (e) {
    debugPrint('pickHeatPhoto($source): $e');
    if (!context.mounted) return null;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie udało się pobrać zdjęcia.',
            en: 'Could not get the photo.'))));
    return null;
  }
}

/// Arkusz „Aparat / Galeria”; przy jednym źródle (desktop) od razu wybór
/// pliku, bez arkusza.
Future<String?> showHeatPhotoSourceSheet(BuildContext context) async {
  final sources = currentHeatPhotoSources();
  if (sources.length == 1) return pickHeatPhoto(context, sources.single);
  final source = await showModalBottomSheet<HeatPhotoSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ctx.tr(pl: 'Zdjęcie numeru wytopu / atestu', en: 'Heat number / certificate photo'),
              style: Theme.of(ctx).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            for (final s in sources) ...[
              SizedBox(
                height: 72,
                child: FilledButton.icon(
                  key: ValueKey('heat-photo-source-${s.name}'),
                  onPressed: () => Navigator.pop(ctx, s),
                  icon: Icon(heatPhotoSourceIcon(s), size: 30),
                  label: Text(heatPhotoSourceLabel(ctx, s),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  return pickHeatPhoto(context, source);
}

/// Przyciski źródeł w jednym rzędzie (np. w oknie „Dodaj HEAT”).
class HeatPhotoSourceButtons extends StatelessWidget {
  const HeatPhotoSourceButtons({super.key, required this.onPicked});

  /// Ścieżka pliku tymczasowego — trwałą kopię robi `persistPickedHeatPhoto`.
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final sources = currentHeatPhotoSources();
    return Row(
      children: [
        for (var i = 0; i < sources.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: kHeatPhotoButtonHeight,
              child: OutlinedButton.icon(
                key: ValueKey('heat-photo-source-${sources[i].name}'),
                icon: Icon(heatPhotoSourceIcon(sources[i]), size: 26),
                label: Text(heatPhotoSourceLabel(context, sources[i]),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                onPressed: () async {
                  final path = await pickHeatPhoto(context, sources[i]);
                  if (path != null) onPicked(path);
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
