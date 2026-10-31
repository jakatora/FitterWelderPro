import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../services/legal_consent.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import 'legal_screen.dart';

// Zgoda dla osób, które mają już profil, ale nie akceptowały zasad — albo
// akceptowały ich starszą wersję. Kto jeszcze się nie przedstawił, zgadza się
// w kroku imienia i nazwiska (onboarding_name_screen.dart).
//
// Ekran jest bramą CZATU, nie aplikacji: bez akceptacji nie ma czatu, bo nie
// ma czatu bez zasad — ale kalkulatory działają dalej. Pokazuje go bramka
// lib/widgets/community_gate.dart.

/// Po co pytamy o zgodę — od tego zależy, co ekran mówi. Zgoda jest jedna
/// (LegalConsent, bieżąca wersja zasad), ale użytkownik ma wiedzieć, na co
/// się zgadza W TYM miejscu: czat publikuje imię i nazwisko, asystent wysyła
/// treść pytań do Anthropic bez nazwiska. (Skaner ma własne okno zgody na
/// zdjęcie — `scan_consent_gate.dart`.)
enum ConsentPurpose {
  /// Czat: wiadomości publiczne, podpisane imieniem i nazwiskiem.
  chat,

  /// Asystent AI: treść pytań idzie na serwer i do Anthropic, bez nazwiska.
  assistant,
}

class ConsentScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  final ConsentPurpose purpose;
  const ConsentScreen({
    super.key,
    required this.onAccepted,
    this.purpose = ConsentPurpose.chat,
  });

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _checked = false;
  bool _saving = false;

  Future<void> _accept() async {
    // Przycisk wyłącza się dopiero po przebudowie ekranu. Dwa szybkie
    // stuknięcia przed kolejną klatką nie mogą zapisać zgody dwa razy ani
    // dwa razy przełączyć bramy startowej.
    if (_saving) return;
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
    // Zgoda była, ale na starszą wersję zasad — mówimy „zmieniliśmy". Kto
    // zgody nigdy nie dał (np. wpisał imię w profilu), słyszy, po co ona jest.
    final rulesChanged = LegalConsent.instance.acceptedAt != null &&
        !LegalConsent.instance.isAccepted;
    final assistant = widget.purpose == ConsentPurpose.assistant;
    final String lead;
    if (assistant) {
      lead = rulesChanged
          ? context.tr(
              pl: 'Zmieniliśmy zasady. Zanim zadasz pytanie asystentowi, '
                  'przeczytaj je i zaakceptuj.',
              en: 'The rules have changed. Read and accept them before you '
                  'ask the assistant.',
            )
          : context.tr(
              pl: 'AI pomaga rozumieć polecenia i odpowiadać na pytania. Do serwera '
                  'wysyłamy treść, kilka ostatnich wymian rozmowy i udostępnione dane bieżącego kalkulatora. Gdy wiedza aplikacji nie wystarczy, AI może wyszukać informacje w internecie i wskazać źródła. Przeczytaj i zaakceptuj zasady. Polecenia '
                  'rozpoznane na telefonie działają bez tego.',
              en: 'AI helps understand commands and answer questions. We send the text, '
                  'a few recent conversation turns and shared inputs of the current calculator to our server. If app knowledge is insufficient, AI can search the web and cite sources. Read and accept the rules first. Commands recognised '
                  'on the phone work without this.',
            );
    } else {
      lead = rulesChanged
          ? context.tr(
              pl: 'Zmieniliśmy zasady. Zanim napiszesz na czacie, '
                  'przeczytaj je i zaakceptuj.',
              en: 'The rules have changed. Read and accept them before '
                  'you post in chat.',
            )
          : context.tr(
              pl: 'Na czacie piszesz pod własnym nazwiskiem. Zanim '
                  'napiszesz, przeczytaj zasady i zaakceptuj je. '
                  'Kalkulatory działają bez tego.',
              en: 'In chat you post under your own name. Read and '
                  'accept the rules before you post. The calculators '
                  'work without this.',
            );
    }
    return Scaffold(
      backgroundColor: kBg,
      // Krok otwierany z ekranu głównego — musi dać się z niego wycofać.
      appBar: AppBar(backgroundColor: kBg),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          children: [
            Center(
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: kArc.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: kArc.withValues(alpha: 0.4), width: 1.5),
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
              lead,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: kTextSec, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 26),
            _Bullets(purpose: widget.purpose),
            const SizedBox(height: 22),
            _DocButton(
              icon: Icons.description_outlined,
              label: context.tr(pl: 'Regulamin', en: 'Terms of Use'),
              onTap: () =>
                  Navigator.push(context, LegalScreen.route(termsOfUse)),
            ),
            const SizedBox(height: 8),
            _DocButton(
              icon: Icons.privacy_tip_outlined,
              label:
                  context.tr(pl: 'Polityka prywatności', en: 'Privacy Policy'),
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
  final ConsentPurpose purpose;
  const _Bullets({required this.purpose});

  @override
  Widget build(BuildContext context) {
    final items = purpose == ConsentPurpose.assistant
        ? <(IconData, String)>[
            (
              Icons.cloud_upload_outlined,
              context.tr(
                pl: 'Treść pytania (i kilka ostatnich wiadomości rozmowy) '
                    'wysyłamy na nasz serwer, a stamtąd do Anthropic (model '
                    'Claude), który przygotuje odpowiedź. Nie zapisujemy pytań '
                    'ani odpowiedzi.',
                en: 'We send the question (and a few recent messages of the '
                    'conversation) to our server and on to Anthropic (the '
                    'Claude model), which prepares the answer. We do not '
                    'store questions or answers.',
              )
            ),
            (
              Icons.person_off_outlined,
              context.tr(
                pl: 'Nie wysyłamy imienia ani nazwiska — serwer widzi tylko '
                    'identyfikator instalacji. Nie wpisuj w pytaniach danych '
                    'osobowych.',
                en: 'We do not send your name — the server only sees the '
                    'installation identifier. Do not put personal data in '
                    'your questions.',
              )
            ),
            (
              Icons.engineering_outlined,
              context.tr(
                pl: 'Odpowiedzi AI mogą zawierać błędy — sprawdzaj je z WPS i '
                    'normą. Za spoinę odpowiada człowiek, nie aplikacja.',
                en: 'AI answers can be wrong — check them against your WPS '
                    'and the standard. A person is responsible for the weld, '
                    'not the app.',
              )
            ),
          ]
        : <(IconData, String)>[
            (
              Icons.badge_outlined,
              context.tr(
                pl: 'Piszesz pod własnym imieniem i nazwiskiem — widzi je każdy '
                    'użytkownik czatu. Nie ma anonimowych ksywek.',
                en: 'You post under your own first and last name — every chat '
                    'user sees it. No anonymous nicknames.',
              )
            ),
            (
              Icons.block,
              context.tr(
                pl: 'Zero tolerancji dla wyzwisk, nękania i treści seksualnych. '
                    'Zgłoszoną wiadomość od razu ukrywamy u zgłaszającego, a '
                    'po 3 zgłoszeniach — u wszystkich.',
                en: 'Zero tolerance for insults, harassment and sexual content. '
                    'A reported message is hidden for the reporter right away, '
                    'and after 3 reports — for everyone.',
              )
            ),
            (
              Icons.engineering_outlined,
              context.tr(
                pl: 'Wyniki kalkulatorów sprawdzaj z WPS i normą. Za spoinę '
                    'odpowiada człowiek, nie aplikacja.',
                en: 'Verify calculator results against your WPS and the '
                    'standard. A person is responsible for the weld, not the '
                    'app.',
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
  const _DocButton(
      {required this.icon, required this.label, required this.onTap});

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
                        color: kText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
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
    // Cały wiersz jest celem dotyku (min. 48 dp), nie tylko pole wyboru.
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTapTarget),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              activeColor: kArc,
              checkColor: Colors.black,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 4, bottom: 8),
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
