import 'package:flutter/material.dart';

import '../config/feature_flags.dart';
import '../services/scan_consent.dart';
export '../services/scan_consent.dart';
import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../screens/legal_screen.dart';

// Zgoda na wysyłkę zdjęcia rysunku — przed pierwszym skanem ISO.
//
// Decyzja (2026-09-25): skaner NIE przechodzi przez bramkę czatu
// (`community_gate.dart`: imię, nazwisko, zasady czatu). Zdjęcie rysunku nie
// jest publikowane ani podpisywane nazwiskiem, więc imię nie jest do niczego
// potrzebne, a zasady czatu (wyzwiska, zgłoszenia) go nie dotyczą. Potrzebna
// jest za to świadoma zgoda na jedno: zdjęcie trafi na nasz serwer i do
// Anthropic (Claude) do odczytu. O to pytamy — raz, tuż przed pierwszą
// wysyłką, a ponownie po podniesieniu [kLegalVersion] (zmiana zasad).
// Ręczne wpisywanie wymiarów na tym samym ekranie działa bez zgody.

/// `true`, gdy monter zgodził się na wysyłkę zdjęcia rysunku (teraz albo
/// wcześniej, na bieżącą wersję zasad). Pokazuje okno zgody, jeśli trzeba.
Future<bool> ensureScanConsent(BuildContext context) async {
  await ScanConsent.load();
  if (ScanConsent.isAccepted) return true;
  if (!context.mounted) return false;

  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => const _ScanConsentDialog(),
  );
  if (agreed != true) return false;
  await ScanConsent.accept();
  return ScanConsent.isAccepted;
}

class _ScanConsentDialog extends StatelessWidget {
  const _ScanConsentDialog();

  @override
  Widget build(BuildContext context) {
    String tr(String pl, String en) => context.tr(pl: pl, en: en);
    final points = <(IconData, String)>[
      (
        Icons.cloud_upload_outlined,
        tr(
          'Zdjęcie rysunku wyślemy na nasz serwer, a stamtąd do Anthropic '
              '(model Claude), który odczyta wymiary i elementy. Nasz serwer '
              'nie zapisuje zdjęcia — przetwarza je tylko na czas odczytu.',
          'The drawing photo goes to our server and on to Anthropic (the '
              'Claude model), which reads the dimensions and components. Our '
              'server does not store the photo — it only handles it while '
              'it is being read.',
        ),
      ),
      (
        Icons.visibility_off_outlined,
        tr(
          'Fotografuj sam rysunek. Nie wysyłaj zdjęć z twarzami, danymi '
              'osobowymi ani dokumentów, których nie wolno Ci udostępniać.',
          'Photograph the drawing only. Do not send photos with faces, '
              'personal data or documents you are not allowed to share.',
        ),
      ),
      (
        Icons.fact_check_outlined,
        tr(
          'Wynik trzeba sprawdzić z rysunkiem — niepewne wartości są '
              'oznaczone i nie trafią do listy cięć bez Twojego potwierdzenia.',
          'Check the result against the drawing — uncertain values are '
              'flagged and never reach the cut list without your '
              'confirmation.',
        ),
      ),
      (
        Icons.hourglass_bottom,
        tr(
          'Skaner jest darmowy z dziennym limitem '
              '($kAiScanDailyLimitPerDevice skanów na telefon).',
          'The scanner is free with a daily limit '
              '($kAiScanDailyLimitPerDevice scans per phone).',
        ),
      ),
    ];

    return AlertDialog(
      title: Text(tr('Zanim wyślesz zdjęcie', 'Before you send the photo')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (icon, text) in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(text,
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(LegalScreen.route(privacyPolicy)),
                icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                label: Text(tr('Polityka prywatności', 'Privacy Policy')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Anuluj', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Zgadzam się', 'I agree')),
        ),
      ],
    );
  }
}
