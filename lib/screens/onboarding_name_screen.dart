import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../services/legal_consent.dart';
import '../services/user_profile.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import 'legal_screen.dart';

// Przedstaw się, zanim napiszesz na czacie: imię, nazwisko i akceptacja zasad
// w jednym kroku. Imię i nazwisko podpisują publiczne wiadomości („widać, że
// to ja piszę").
//
// NIE jest już bramą startową aplikacji — kalkulatory działają bez konta.
// Pokazuje ją bramka przed czatem (lib/widgets/community_gate.dart), a
// [onDone] zamyka ten krok i wpuszcza dalej. Purely additive — touches no
// calculator logic.

const _kErrorRed = Color(0xFFE57373);

// Unicode-aware: allow letters (incl. Polish diacritics), spaces, apostrophe
// and dash (e.g. "Anna-Maria", "O'Brien"). Min 2 chars.
final RegExp _kNameAllowed = RegExp(r"^[\p{L} '\-]{2,}$", unicode: true);

class OnboardingNameScreen extends StatefulWidget {
  /// Called once a valid profile has been saved and the rules accepted.
  final VoidCallback onDone;

  const OnboardingNameScreen({super.key, required this.onDone});

  @override
  State<OnboardingNameScreen> createState() => _OnboardingNameScreenState();
}

class _OnboardingNameScreenState extends State<OnboardingNameScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _firstFocus = FocusNode();
  final _lastFocus = FocusNode();

  String? _firstError;
  String? _lastError;
  bool _saving = false;

  /// Bez zaznaczenia nie da się przejść dalej — Apple wymaga akceptacji zasad,
  /// zanim użytkownik cokolwiek opublikuje na publicznym czacie.
  bool _accepted = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _firstFocus.dispose();
    _lastFocus.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      return context.tr(
          pl: 'To pole jest wymagane.', en: 'This field is required.');
    }
    if (!_kNameAllowed.hasMatch(v)) {
      return context.tr(
        pl: 'Min. 2 litery, bez cyfr i znaków specjalnych.',
        en: 'Min. 2 letters, no digits or special characters.',
      );
    }
    return null;
  }

  Future<void> _submit() async {
    // Dwa szybkie stuknięcia nie mogą zapisać profilu dwa razy.
    if (_saving) return;
    final firstErr = _validate(_firstCtrl.text);
    final lastErr = _validate(_lastCtrl.text);
    setState(() {
      _firstError = firstErr;
      _lastError = lastErr;
    });
    if (firstErr != null || lastErr != null || !_accepted) {
      Haptic.error();
      return;
    }

    setState(() => _saving = true);
    final profile = UserProfile(
      firstName: _firstCtrl.text.trim(),
      lastName: _lastCtrl.text.trim(),
    );
    final ok = await UserProfileService.instance.save(profile);
    // Zgoda zapisywana razem z profilem: użytkownik zaakceptował zasady w tym
    // samym kroku, w którym się przedstawił.
    await LegalConsent.instance.accept();
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      Haptic.error();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Nie udało się zapisać. Spróbuj ponownie.',
          en: 'Could not save. Please try again.',
        )),
      ));
      return;
    }
    Haptic.saved();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.language;
    return Scaffold(
      backgroundColor: kBg,
      // Krok otwierany z ekranu głównego — musi dać się z niego wycofać.
      // Przełącznik języka siedzi w pasku, żeby nie zabierał miejsca formularzowi.
      appBar: AppBar(
        backgroundColor: kBg,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: _LangToggle(lang: lang, onChanged: context.setLanguage),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        // Cały formularz budowany od razu (nie leniwie jak ListView), żeby
        // przycisk na dole istniał także na niskim ekranie.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand mark.
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kArc.withValues(alpha: 0.22),
                        kGold.withValues(alpha: 0.10),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: kGold.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child:
                      const Icon(Icons.forum_outlined, color: kGold, size: 32),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr(
                    pl: 'Zanim napiszesz na czacie',
                    en: 'Before you post in chat'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: kText,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'Podaj imię i nazwisko — będą Twoim podpisem, '
                      'żeby na czacie było widać, że to Ty piszesz.',
                  en: 'Enter your first and last name — it becomes your '
                      'signature so others can see it is you on the chat.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, color: kTextSec, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'Nie ma anonimowej ksywki — na budowie odpowiadasz '
                      'za to, co mówisz.',
                  en: 'There is no anonymous nickname — on site you answer '
                      'for what you say.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: kTextMut, height: 1.4),
              ),
              const SizedBox(height: 24),
              _FieldLabel(context.tr(pl: 'Imię', en: 'First name')),
              const SizedBox(height: 8),
              TextField(
                controller: _firstCtrl,
                focusNode: _firstFocus,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                style: const TextStyle(color: kText, fontSize: 16),
                decoration: _decoration(
                  hint: context.tr(pl: 'np. Jan', en: 'e.g. John'),
                  icon: Icons.person_outline,
                  error: _firstError,
                ),
                onChanged: (_) {
                  if (_firstError != null) setState(() => _firstError = null);
                },
                onSubmitted: (_) => _lastFocus.requestFocus(),
              ),
              const SizedBox(height: 18),
              _FieldLabel(context.tr(pl: 'Nazwisko', en: 'Last name')),
              const SizedBox(height: 8),
              TextField(
                controller: _lastCtrl,
                focusNode: _lastFocus,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: kText, fontSize: 16),
                decoration: _decoration(
                  hint: context.tr(pl: 'np. Kowalski', en: 'e.g. Smith'),
                  icon: Icons.badge_outlined,
                  error: _lastError,
                ),
                onChanged: (_) {
                  if (_lastError != null) setState(() => _lastError = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.lock_outline, size: 14, color: kTextMut),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    // Uczciwie i konkretnie: nazwisko leci na serwer z każdą
                    // wiadomością na czacie, a nic poza tym.
                    child: Text(
                      context.tr(
                        pl: 'Kalkulatory, projekty i obliczenia działają bez '
                            'tego kroku i zostają na telefonie. Imię i nazwisko '
                            'wysyłamy tylko wtedy, gdy napiszesz na czacie. '
                            'Zmienisz je w profilu.',
                        en: 'Calculators, projects and results work without this '
                            'step and stay on this phone. Your name is sent only '
                            'when you post in chat. You can change it in your '
                            'profile.',
                      ),
                      style: const TextStyle(
                          fontSize: 12, color: kTextMut, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ConsentRow(
                value: _accepted,
                onChanged: (v) => setState(() => _accepted = v),
                onTerms: () =>
                    Navigator.push(context, LegalScreen.route(termsOfUse)),
                onPrivacy: () =>
                    Navigator.push(context, LegalScreen.route(privacyPolicy)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: (_saving || !_accepted) ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: kGold.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.black),
                        )
                      : Text(
                          context.tr(
                              pl: 'Zapisz i dalej', en: 'Save and continue'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    String? error,
  }) {
    return InputDecoration(
      hintText: hint,
      errorText: error,
      prefixIcon: Icon(icon, color: kTextSec, size: 20),
      filled: true,
      fillColor: kCard,
      hintStyle: const TextStyle(color: kTextMut),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kArc, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kErrorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kErrorRed, width: 1.5),
      ),
    );
  }
}

/// Zgoda na zasady w tym samym kroku, w którym monter się przedstawia.
///
/// Cały wiersz jest celem dotyku (min. 48 dp) — wcześniej trzeba było trafić
/// w pole 30×30, a stuknięcie w tekst nic nie robiło. Odnośniki w tekście
/// dalej otwierają regulamin i politykę (dostępne bez Internetu).
class _ConsentRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  const _ConsentRow({
    required this.value,
    required this.onChanged,
    required this.onTerms,
    required this.onPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      fontSize: 13,
      color: kGold,
      height: 1.45,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: kGold,
    );
    const bodyStyle = TextStyle(fontSize: 13, color: kTextSec, height: 1.45);

    return InkWell(
      key: const ValueKey('onboarding-consent-row'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                activeColor: kGold,
                checkColor: Colors.black,
                onChanged: (v) => onChanged(v ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 4),
                  child: Text.rich(
                    TextSpan(
                      style: bodyStyle,
                      children: [
                        TextSpan(
                          text: context.tr(
                            pl: 'Mam ukończone $kMinimumAge lat i akceptuję ',
                            en: 'I am at least $kMinimumAge years old and I '
                                'accept the ',
                          ),
                        ),
                        TextSpan(
                          text: context.tr(pl: 'Regulamin', en: 'Terms of Use'),
                          style: linkStyle,
                          recognizer: TapGestureRecognizer()..onTap = onTerms,
                        ),
                        TextSpan(
                            text: context.tr(pl: ' oraz ', en: ' and the ')),
                        TextSpan(
                          text: context.tr(
                              pl: 'Politykę prywatności', en: 'Privacy Policy'),
                          style: linkStyle,
                          recognizer: TapGestureRecognizer()..onTap = onPrivacy,
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: kTextSec,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// PL / EN. Każdy przycisk ma co najmniej 48×48 dp — wcześniej ok. 34 dp.
class _LangToggle extends StatelessWidget {
  final AppLanguage lang;
  final ValueChanged<AppLanguage> onChanged;
  const _LangToggle({required this.lang, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _langChip('PL', AppLanguage.pl),
          _langChip('EN', AppLanguage.en),
        ],
      ),
    );
  }

  Widget _langChip(String label, AppLanguage value) {
    final selected = lang == value;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('onboarding-lang-${value.name}'),
        borderRadius: BorderRadius.circular(11),
        onTap: () => onChanged(value),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: kMinTapTarget,
            minHeight: kMinTapTarget,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? kArc.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: selected ? kArc : kTextMut,
            ),
          ),
        ),
      ),
    );
  }
}
