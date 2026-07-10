import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../services/legal_consent.dart';
import '../services/user_profile.dart';
import '../utils/haptic.dart';
import 'legal_screen.dart';

// First-run onboarding. Captures the user's first + last name BEFORE the app
// opens, so their public chat messages are signed with a real identity
// ("widać, że to ja piszę"). Mandatory: the RootGate keeps showing this until
// a valid profile is saved. Purely additive — touches no calculator logic.

const _kBg = Color(0xFF0B0E13);
const _kCard = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kGold = Color(0xFFE8C14B);
const _kOrange = Color(0xFFFF8E1E);
const _kText = Color(0xFFE7ECF3);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF5A6478);

// Unicode-aware: allow letters (incl. Polish diacritics), spaces, apostrophe
// and dash (e.g. "Anna-Maria", "O'Brien"). Min 2 chars.
final RegExp _kNameAllowed = RegExp(r"^[\p{L} '\-]{2,}$", unicode: true);

class OnboardingNameScreen extends StatefulWidget {
  /// Called once a valid profile has been saved so the gate can rebuild
  /// into the home screen.
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

  /// Bez zaznaczenia nie da się wejść — Apple wymaga akceptacji zasad, zanim
  /// użytkownik cokolwiek opublikuje na publicznym czacie.
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
      return context.tr(pl: 'To pole jest wymagane.', en: 'This field is required.');
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
      backgroundColor: _kBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Language toggle — a first-run user may prefer EN.
                    Align(
                      alignment: Alignment.centerRight,
                      child: _LangToggle(
                        lang: lang,
                        onChanged: context.setLanguage,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Brand mark.
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _kOrange.withValues(alpha: 0.22),
                              _kGold.withValues(alpha: 0.10),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _kGold.withValues(alpha: 0.35), width: 1.5),
                        ),
                        child: const Icon(Icons.engineering_outlined,
                            color: _kGold, size: 36),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [_kOrange, _kGold],
                      ).createShader(b),
                      child: Text(
                        context.tr(pl: 'Witaj na pokładzie', en: 'Welcome aboard'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
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
                          fontSize: 13, color: _kTextSec, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                        pl: 'Nie ma anonimowej ksywki — na budowie odpowiadasz '
                            'za to, co mówisz.',
                        en: 'There is no anonymous nickname — on site you answer '
                            'for what you say.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: _kTextMut, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    _FieldLabel(context.tr(pl: 'Imię', en: 'First name')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _firstCtrl,
                      focusNode: _firstFocus,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      autofocus: true,
                      style: const TextStyle(color: _kText, fontSize: 16),
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
                      style: const TextStyle(color: _kText, fontSize: 16),
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
                      children: [
                        const Icon(Icons.lock_outline, size: 14, color: _kTextMut),
                        const SizedBox(width: 6),
                        Expanded(
                          // Uczciwie i konkretnie. Poprzednia wersja mówiła
                          // „dane zostają na Twoim telefonie" — a nazwisko leci
                          // na serwer z każdą wiadomością na czacie — oraz
                          // odsyłała do ustawień, których w aplikacji nie było.
                          child: Text(
                            context.tr(
                              pl: 'Twoje projekty i obliczenia zostają na '
                                  'telefonie. Imię i nazwisko wysyłamy tylko '
                                  'wtedy, gdy napiszesz na czacie. Zmienisz je '
                                  'w profilu.',
                              en: 'Your projects and calculations stay on this '
                                  'phone. Your name is sent only when you post '
                                  'in chat. You can change it in your profile.',
                            ),
                            style: const TextStyle(
                                fontSize: 11, color: _kTextMut, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _ConsentRow(
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v),
                      onTerms: () =>
                          Navigator.push(context, LegalScreen.route(termsOfUse)),
                      onPrivacy: () => Navigator.push(
                          context, LegalScreen.route(privacyPolicy)),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: (_saving || !_accepted) ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kGold,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: _kGold.withValues(alpha: 0.4),
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
                                context.tr(pl: 'Zaczynamy', en: "Let's go"),
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
            );
          },
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
      prefixIcon: Icon(icon, color: _kTextSec, size: 20),
      filled: true,
      fillColor: _kCard,
      hintStyle: const TextStyle(color: _kTextMut),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kOrange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE57373)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE57373), width: 1.5),
      ),
    );
  }
}

/// Zgoda na zasady w tym samym kroku, w którym monter się przedstawia.
/// Odnośniki są klikalne — regulamin dostępny bez Internetu, wprost z aplikacji.
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
      fontSize: 12,
      color: _kGold,
      height: 1.45,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: _kGold,
    );
    const bodyStyle = TextStyle(fontSize: 12, color: _kTextSec, height: 1.45);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          height: 30,
          child: Checkbox(
            value: value,
            activeColor: _kGold,
            checkColor: Colors.black,
            onChanged: (v) => onChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text.rich(
              TextSpan(
                style: bodyStyle,
                children: [
                  TextSpan(
                    text: context.tr(
                      pl: 'Mam ukończone $kMinimumAge lat i akceptuję ',
                      en: 'I am at least $kMinimumAge years old and I accept the ',
                    ),
                  ),
                  TextSpan(
                    text: context.tr(pl: 'Regulamin', en: 'Terms of Use'),
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()..onTap = onTerms,
                  ),
                  TextSpan(text: context.tr(pl: ' oraz ', en: ' and the ')),
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
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _kTextSec,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _LangToggle extends StatelessWidget {
  final AppLanguage lang;
  final ValueChanged<AppLanguage> onChanged;
  const _LangToggle({required this.lang, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
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
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kOrange.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? _kOrange : _kTextMut,
          ),
        ),
      ),
    );
  }
}
