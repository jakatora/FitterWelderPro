import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../services/legal_consent.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import 'legal_screen.dart';

// Zgoda dla osób, które mają już profil, ale nie akceptowały zasad — albo
// akceptowały ich starszą wersję. Nowi użytkownicy zgadzają się w onboardingu.
//
// Ekran jest bramą: bez akceptacji nie ma czatu, bo nie ma czatu bez zasad.

class ConsentScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  const ConsentScreen({super.key, required this.onAccepted});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _checked = false;
  bool _saving = false;

  Future<void> _accept() async {
    if (!_checked) {
      Haptic.error();
      return;
    }
    setState(() => _saving = true);
    await LegalConsent.instance.accept();
    if (!mounted) return;
    Haptic.saved();
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          children: [
            Center(
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: kArc.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kArc.withValues(alpha: 0.4), width: 1.5),
                ),
                child: const Icon(Icons.gavel_outlined, color: kArc, size: 30),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.tr(pl: 'Zasady i prywatność', en: 'Rules and privacy'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: kText, fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              context.tr(
                pl: 'Zmieniliśmy zasady. Zanim napiszesz na czacie, przeczytaj '
                    'je i zaakceptuj.',
                en: 'The rules have changed. Read and accept them before you post '
                    'in chat.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 26),
            const _Bullets(),
            const SizedBox(height: 22),
            _DocButton(
              icon: Icons.description_outlined,
              label: context.tr(pl: 'Regulamin', en: 'Terms of Use'),
              onTap: () => Navigator.push(context, LegalScreen.route(termsOfUse)),
            ),
            const SizedBox(height: 8),
            _DocButton(
              icon: Icons.privacy_tip_outlined,
              label: context.tr(pl: 'Polityka prywatności', en: 'Privacy Policy'),
              onTap: () =>
                  Navigator.push(context, LegalScreen.route(privacyPolicy)),
            ),
            const SizedBox(height: 20),
            _ConsentCheckbox(
              value: _checked,
              onChanged: (v) => setState(() => _checked = v),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: kMinTapTarget + 6,
              child: FilledButton(
                onPressed: (_checked && !_saving) ? _accept : null,
                style: FilledButton.styleFrom(
                  backgroundColor: kArc,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: kArc.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.black),
                      )
                    : Text(
                        context.tr(pl: 'Akceptuję', en: 'I accept'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15.5),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trzy zdania, które naprawdę zmieniają zachowanie użytkownika. Nikt nie czyta
/// regulaminu — ale to przeczyta.
class _Bullets extends StatelessWidget {
  const _Bullets();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      (
        Icons.badge_outlined,
        context.tr(
          pl: 'Piszesz pod własnym imieniem i nazwiskiem. Nie ma anonimowych ksywek.',
          en: 'You post under your own first and last name. No anonymous nicknames.',
        )
      ),
      (
        Icons.block,
        context.tr(
          pl: 'Zero tolerancji dla wyzwisk, nękania i treści seksualnych. '
              'Zgłoszenia rozpatrujemy w 24 godziny.',
          en: 'Zero tolerance for insults, harassment and sexual content. We review '
              'reports within 24 hours.',
        )
      ),
      (
        Icons.engineering_outlined,
        context.tr(
          pl: 'Wyniki kalkulatorów sprawdzaj z WPS i normą. Za spoinę odpowiada '
              'człowiek, nie aplikacja.',
          en: 'Verify calculator results against your WPS and the standard. A person '
              'is responsible for the weld, not the app.',
        )
      ),
    ];

    return Column(
      children: [
        for (final (icon, text) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: kArc),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                        color: kTextSec, fontSize: 13.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DocButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DocButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget + 6),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: kTextSec),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right, size: 20, color: kTextMut),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ConsentCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                activeColor: kArc,
                checkColor: Colors.black,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr(
                    pl: 'Mam ukończone $kMinimumAge lat, przeczytałem Regulamin '
                        'i Politykę prywatności i akceptuję je.',
                    en: 'I am at least $kMinimumAge years old, I have read the Terms '
                        'of Use and the Privacy Policy, and I accept them.',
                  ),
                  style: const TextStyle(
                      color: kTextSec, fontSize: 13, height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
