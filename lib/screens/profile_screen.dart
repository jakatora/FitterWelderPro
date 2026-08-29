import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_links.dart';
import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../services/blocked_users.dart';
import '../services/legal_consent.dart';
import '../services/user_profile.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import '../widgets/wpqr_chip.dart';
import 'legal_screen.dart';
import 'root_gate.dart';

// Twój profil.
//
// Powstał, bo onboarding obiecywał „możesz je później zmienić w ustawieniach",
// a żadnych ustawień nie było. Obietnica bez pokrycia w aplikacji, w której
// Twoje imię widzą inni ludzie, to nie drobiazg.
//
// Ekran robi trzy rzeczy i nic więcej:
//   1. mówi wprost, co jest publiczne, a co zostaje na telefonie,
//   2. pozwala poprawić imię i nazwisko,
//   3. pokazuje, kogo zablokowałeś, i pozwala odblokować.

final RegExp _kNameAllowed = RegExp(r"^[\p{L} '\-]{2,}$", unicode: true);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();

  String? _firstError;
  String? _lastError;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserProfileService.instance.get();
    await BlockedUsers.instance.load();
    if (!mounted) return;
    setState(() {
      _firstCtrl.text = profile?.firstName ?? '';
      _lastCtrl.text = profile?.lastName ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
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

  Future<void> _save() async {
    final firstErr = _validate(_firstCtrl.text);
    final lastErr = _validate(_lastCtrl.text);
    setState(() {
      _firstError = firstErr;
      _lastError = lastErr;
    });
    if (firstErr != null || lastErr != null) {
      Haptic.error();
      return;
    }

    setState(() => _saving = true);
    final ok = await UserProfileService.instance.save(UserProfile(
      firstName: _firstCtrl.text.trim(),
      lastName: _lastCtrl.text.trim(),
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(pl: 'Zapisano.', en: 'Saved.')),
    ));
  }

  Future<void> _contact() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppLinks.supportEmail,
      queryParameters: {'subject': 'Fitter Welder Pro'},
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok || !mounted) return;
    // Bez klienta poczty i tak musi zobaczyć adres — inaczej kontakt jest fikcją.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(
        pl: 'Napisz na ${AppLinks.supportEmail}',
        en: 'Write to ${AppLinks.supportEmail}',
      )),
      duration: const Duration(seconds: 6),
    ));
  }

  /// Google Play wymaga ścieżki usunięcia danych, gdy aplikacja cokolwiek
  /// wysyła. Kasujemy wszystko, co lokalne. Wiadomości już opublikowane na
  /// czacie usuwa moderacja na wniosek — mówimy o tym wprost, zamiast udawać,
  /// że jeden przycisk cofa to, co zobaczyli inni.
  Future<void> _deleteMyData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        // Wyliczenka urosła o tożsamość spawacza, a to jest ostrzeżenie przed
        // nieodwracalnym kasowaniem — na małym telefonie albo przy dużej
        // czcionce systemowej niescrollowalny dialog ucina tekst zamiast go
        // pokazać. Scrollowalny nie ucina nigdy.
        scrollable: true,
        title: Text(context.tr(pl: 'Usunąć moje dane?', en: 'Delete my data?')),
        // Tekst wymieniał trzy rzeczy, a tożsamości spawacza nie — bo kod jej
        // nie kasował. Stempel, nr WPQR i e-mail to dane osobowe w rozumieniu
        // RODO i JEDYNA rzecz, którą aplikacja przykleja do każdej spoiny;
        // przemilczenie ich przy „usuń moje dane" było i błędem, i obietnicą
        // bez pokrycia.
        content: Text(context.tr(
          pl: 'Skasujemy z tego telefonu Twoje imię i nazwisko, zgodę na zasady, '
              'listę zablokowanych oraz tożsamość spawacza: stempel, numer WPQR, '
              'datę ważności uprawnienia, jednostkę certyfikującą i e-mail. '
              'Nowe spoiny przestaną się podpisywać Twoim stemplem.\n\n'
              'Projekty, cut listy i zapisane spoiny zostają — razem ze '
              'stemplem, którym już je podpisałeś.\n\n'
              'Wiadomości, które już wysłałeś na czat, widzą inni — o ich '
              'usunięcie poproś na ${AppLinks.supportEmail}.',
          en: 'We will erase your name, your consent, your block list and your '
              'welder identity from this phone: stamp, WPQR number, expiry '
              'date, certification body and e-mail. New welds will no longer '
              'be signed with your stamp.\n\n'
              'Projects, cut lists and saved welds stay — including the stamp '
              'you already signed them with.\n\n'
              'Messages you already posted are visible to others — ask us to '
              'remove them at ${AppLinks.supportEmail}.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await UserProfileService.instance.clear();
    await LegalConsent.instance.clear();
    // Tego brakowało. Bez tego wywołania „usuń moje dane" zostawiało na
    // telefonie komplet danych spawacza (stempel, nr WPQR, e-mail), a
    // weld_journal_screen dalej pre-wypełniał nimi pole „spawacz" — nowe
    // spoiny podpisywały się człowiekiem, który właśnie kazał się usunąć.
    // WelderIdentityService.clear() istniał od P0-08 i nie wołał go NIKT.
    await WelderIdentityService.instance.clear();
    for (final u in BlockedUsers.instance.all) {
      await BlockedUsers.instance.unblock(u.deviceId);
    }
    if (!mounted) return;
    Haptic.saved();
    // Wracamy do bramy startowej: bez profilu i zgody aplikacja zaczyna od nowa.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootGate()),
      (route) => false,
    );
  }

  Future<void> _unblock(BlockedUser u) async {
    await BlockedUsers.instance.unblock(u.deviceId);
    if (!mounted) return;
    Haptic.saved();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(
        pl: 'Odblokowano ${u.name}.',
        en: 'Unblocked ${u.name}.',
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final blocked = BlockedUsers.instance.all;
    final fullName = '${_firstCtrl.text.trim()} ${_lastCtrl.text.trim()}'.trim();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr(pl: 'Twój profil', en: 'Your profile'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _Identity(name: fullName),
                // Ostrzeżenie o uprawnieniu tuż pod nazwiskiem, bo to ten sam
                // temat: czym się podpisujesz. Znika samo, gdy WPQR jest
                // ważny albo nie ma daty — i znika od razu po „usuń moje
                // dane", bo słucha strumienia zmian tożsamości.
                const WpqrChipLive(padding: EdgeInsets.only(top: 16)),
                const SizedBox(height: 20),

                // Uczciwość zamiast ogólników: dokładnie co widzą inni.
                _Notice(
                  icon: Icons.visibility_outlined,
                  accent: kArc,
                  title: context.tr(pl: 'Co widzą inni', en: 'What others see'),
                  body: context.tr(
                    pl: 'Twoje imię i nazwisko pojawia się przy każdej '
                        'wiadomości, którą wyślesz na czacie. Nie ma anonimowej '
                        'ksywki — na budowie odpowiadasz za to, co mówisz.',
                    en: 'Your first and last name appears next to every message '
                        'you post in chat. There is no anonymous nickname — on '
                        'site you answer for what you say.',
                  ),
                ),
                const SizedBox(height: 10),
                _Notice(
                  icon: Icons.phone_iphone,
                  accent: kTextSec,
                  title: context.tr(
                      pl: 'Co zostaje na telefonie', en: 'What stays on your phone'),
                  body: context.tr(
                    pl: 'Projekty, cut listy, dziennik spoin, zdjęcia i wyniki '
                        'kalkulatorów. Nic z tego nie trafia na serwer.',
                    en: 'Projects, cut lists, weld journal, photos and calculator '
                        'results. None of it goes to a server.',
                  ),
                ),
                const SizedBox(height: 26),

                _Label(context.tr(pl: 'Imię', en: 'First name')),
                const SizedBox(height: 8),
                TextField(
                  controller: _firstCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(errorText: _firstError),
                  onChanged: (_) {
                    if (_firstError != null) setState(() => _firstError = null);
                    setState(() {}); // odśwież podgląd podpisu
                  },
                ),
                const SizedBox(height: 16),
                _Label(context.tr(pl: 'Nazwisko', en: 'Last name')),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(errorText: _lastError),
                  onChanged: (_) {
                    if (_lastError != null) setState(() => _lastError = null);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: kMinTapTarget + 4,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: kArc,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.black),
                          )
                        : Text(
                            context.tr(pl: 'Zapisz', en: 'Save'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                  ),
                ),

                const SizedBox(height: 32),
                _Label(context.tr(pl: 'Zablokowani', en: 'Blocked')),
                const SizedBox(height: 8),
                if (blocked.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder),
                    ),
                    child: Text(
                      context.tr(
                        pl: 'Nikogo nie zablokowałeś. Na czacie przytrzymaj '
                            'wiadomość, żeby zgłosić ją lub zablokować autora.',
                        en: 'You have not blocked anyone. In chat, long-press a '
                            'message to report it or block its author.',
                      ),
                      style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.5),
                    ),
                  )
                else
                  ...blocked.map((u) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.block, color: kFail),
                          title: Text(u.name,
                              style: const TextStyle(
                                  color: kText, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            context.tr(
                                pl: 'Jego wiadomości są ukryte',
                                en: 'Their messages are hidden'),
                            style: const TextStyle(color: kTextMut, fontSize: 12),
                          ),
                          trailing: TextButton(
                            onPressed: () => _unblock(u),
                            child: Text(
                              context.tr(pl: 'Odblokuj', en: 'Unblock'),
                              style: const TextStyle(
                                  color: kArc, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      )),

                const SizedBox(height: 32),
                _Label(context.tr(pl: 'Zasady i prywatność', en: 'Rules and privacy')),
                const SizedBox(height: 8),
                _LinkTile(
                  icon: Icons.description_outlined,
                  label: context.tr(pl: 'Regulamin', en: 'Terms of Use'),
                  onTap: () =>
                      Navigator.push(context, LegalScreen.route(termsOfUse)),
                ),
                _LinkTile(
                  icon: Icons.privacy_tip_outlined,
                  label: context.tr(
                      pl: 'Polityka prywatności', en: 'Privacy Policy'),
                  onTap: () =>
                      Navigator.push(context, LegalScreen.route(privacyPolicy)),
                ),
                _LinkTile(
                  icon: Icons.mail_outline,
                  label: context.tr(pl: 'Kontakt', en: 'Contact'),
                  subtitle: AppLinks.supportEmail,
                  onTap: _contact,
                ),
                _LinkTile(
                  icon: Icons.delete_outline,
                  label: context.tr(pl: 'Usuń moje dane', en: 'Delete my data'),
                  danger: true,
                  onTap: _deleteMyData,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    context.tr(
                        pl: 'Zasady w wersji $kLegalVersion · $kLegalUpdated',
                        en: 'Rules version $kLegalVersion · $kLegalUpdated'),
                    style: const TextStyle(color: kTextMut, fontSize: 11),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? kFail : kText;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(icon, color: danger ? kFail : kTextSec, size: 20),
        title: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!,
                style: const TextStyle(color: kTextMut, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: kTextMut, size: 20),
        onTap: onTap,
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  final String name;
  const _Identity({required this.name});

  String get _initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kArc.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: kArc.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Text(
            _initials,
            style: const TextStyle(
                color: kArc, fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty
                    ? context.tr(pl: 'Bez nazwy', en: 'Unnamed')
                    : name,
                style: const TextStyle(
                    color: kText, fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                context.tr(
                    pl: 'Tak podpisane są Twoje wiadomości',
                    en: 'This signs your messages'),
                style: const TextStyle(color: kTextMut, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  const _Notice({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body,
              style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: kTextSec,
        letterSpacing: 1.2,
      ),
    );
  }
}
