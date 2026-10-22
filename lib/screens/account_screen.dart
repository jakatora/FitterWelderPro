import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../services/account_service.dart';
import '../services/ai_professional_context.dart';
import '../legal/legal_texts.dart';
import 'legal_screen.dart';
import '../widgets/number_field.dart';
import '../feedback/feedback_consent.dart';
import '../feedback/feedback_uploader.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.initialRegister = false});
  final bool initialRegister;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final service = AccountService.instance;
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final profession = TextEditingController();
  final qualifications = TextEditingController();
  final stamp = TextEditingController();
  final years = TextEditingController(text: '0');
  final Set<String> processes = {};
  bool acceptedPolicy = false;
  bool registering = false,
      busy = true,
      publicProfile = false,
      feedbackGranted = false;
  String? error;
  int _sessionRevision = 0;
  @override
  void initState() {
    super.initState();
    registering = widget.initialRegister;
    _sessionRevision = service.sessionRevision;
    service.addListener(_sessionChanged);
    _load();
  }

  void _sessionChanged() {
    if (!mounted || _sessionRevision == service.sessionRevision) return;
    _sessionRevision = service.sessionRevision;
    setState(() {
      _fill();
      password.clear();
      error = null;
    });
  }

  Future<void> _load() async {
    await _run(() async {
      await service.load();
      await AiProfessionalContext.instance.load();
      if (service.needsIdentityRefresh) await service.refreshIdentity();
      feedbackGranted = await FeedbackConsent.instance.isGranted();
      _fill();
    });
  }

  void _fill() {
    final a = service.account;
    name.text = a?['displayName'] as String? ?? '';
    profession.text = a?['profession'] as String? ?? '';
    qualifications.text = a?['qualifications'] as String? ?? '';
    stamp.text = a?['stamp'] as String? ?? '';
    years.text = '${a?['experienceYears'] ?? 0}';
    publicProfile = a?['publicProfile'] == true;
    processes
      ..clear()
      ..addAll((a?['processes'] as List? ?? []).cast<String>());
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        error = e is AccountException
            ? e.message
            : context.tr(
                pl: 'Brak połączenia. Spróbuj ponownie.',
                en: 'Connection failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    service.removeListener(_sessionChanged);
    for (final c in [
      email,
      password,
      name,
      profession,
      qualifications,
      stamp,
      years
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(TextEditingController c, String pl, String en,
          {bool secret = false, int max = 80, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
            controller: c,
            obscureText: secret,
            enableSuggestions: !secret,
            autocorrect: !secret,
            maxLength: max,
            keyboardType: keyboard,
            inputFormatters:
                c == years ? numberInputFormatters(decimal: false) : null,
            decoration: InputDecoration(
                labelText: context.tr(pl: pl, en: en),
                border: const OutlineInputBorder(),
                counterText: '')),
      );
  @override
  Widget build(BuildContext _) {
    final a = service.account;
    return Scaffold(
        appBar: AppBar(
            title: Text(
                context.tr(pl: 'Konto i zawód', en: 'Account and profession'))),
        body: AbsorbPointer(
            absorbing: busy,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr(
                      pl: 'Pomóż ulepszać asystenta',
                      en: 'Help improve the assistant')),
                  subtitle: Text(context.tr(
                      pl: 'Wysyłaj zamaskowane zgłoszenia niezrozumianych poleceń i brakujących funkcji. Widzi je tylko administrator. Bez nagrań głosu. Zgodę możesz cofnąć.',
                      en: 'Send redacted reports of unrecognized commands and missing features. Only the administrator can see them. No voice recordings. You can withdraw consent.')),
                  value: feedbackGranted,
                  onChanged: (v) => _run(() async {
                        if (v) {
                          if (!await FeedbackConsent.instance.grant()) {
                            throw AccountException(
                                'Nie zapisano zgody / Consent was not saved');
                          }
                        } else {
                          await FeedbackConsent.instance.revoke();
                        }
                        feedbackGranted =
                            await FeedbackConsent.instance.isGranted();
                        if (feedbackGranted) {
                          await FeedbackUploader.instance.flush();
                        }
                      })),
              if (a == null && service.needsIdentityRefresh) ...[
                Text(context.tr(
                    pl: 'Nie udało się pobrać profilu. Twoja sesja została zachowana. Spróbuj ponownie po odzyskaniu połączenia.',
                    en: 'Could not load your profile. Your session has been retained. Try again when the connection is restored.')),
                const SizedBox(height: 16),
                OutlinedButton(
                    key: const Key('account-retry-profile'),
                    onPressed: _load,
                    child: Text(context.tr(
                        pl: 'Ponów odczyt profilu',
                        en: 'Retry loading profile'))),
                TextButton(
                    key: const Key('account-offline-guest'),
                    onPressed: () => _run(service.forgetSession),
                    child: Text(context.tr(
                        pl: 'Wyloguj na tym telefonie i korzystaj jako gość',
                        en: 'Sign out on this phone and continue as guest'))),
              ] else if (a == null) ...[
                Text(context.tr(
                    pl: 'Konto synchronizuje Twój profil. Kalkulatory działają też bez konta.',
                    en: 'Your account synchronizes your profile. Calculators also work without an account.')),
                const SizedBox(height: 24),
                field(email, 'E-mail', 'Email',
                    max: 254, keyboard: TextInputType.emailAddress),
                field(password, 'Hasło (minimum 12 znaków)',
                    'Password (at least 12 characters)',
                    secret: true, max: 128),
                if (registering)
                  field(name, 'Imię i nazwisko na czacie', 'Chat display name'),
                if (registering)
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.tr(
                          pl:
                              'Akceptuję regulamin i politykę prywatności konta',
                          en: 'I accept account terms and privacy policy')),
                      value: acceptedPolicy,
                      onChanged: (v) =>
                          setState(() => acceptedPolicy = v ?? false)),
                Wrap(children: [
                  TextButton(
                      onPressed: () => Navigator.of(context)
                          .push(LegalScreen.route(privacyPolicy)),
                      child: Text(context.tr(pl: 'Prywatność', en: 'Privacy'))),
                  TextButton(
                      onPressed: () => Navigator.of(context)
                          .push(LegalScreen.route(termsOfUse)),
                      child: Text(context.tr(pl: 'Regulamin', en: 'Terms')))
                ]),
                FilledButton(
                    onPressed: () => _run(() async {
                          if (registering && !acceptedPolicy) {
                            throw AccountException(context.tr(
                                pl: 'Przeczytaj i zaakceptuj zasady konta.',
                                en: 'Read and accept the account terms.'));
                          }
                          await service.signIn(email.text, password.text,
                              displayName: registering ? name.text : null);
                          password.clear();
                          _fill();
                        }),
                    child: Text(registering
                        ? context.tr(pl: 'Załóż konto', en: 'Create account')
                        : context.tr(pl: 'Zaloguj się', en: 'Sign in'))),
                TextButton(
                    onPressed: () => setState(() {
                          registering = !registering;
                          error = null;
                        }),
                    child: Text(registering
                        ? context.tr(
                            pl: 'Mam już konto',
                            en: 'I already have an account')
                        : context.tr(
                            pl: 'Utwórz konto', en: 'Create an account'))),
              ] else ...[
                Text(a['email'] as String),
                const SizedBox(height: 20),
                field(name, 'Imię i nazwisko na czacie', 'Chat display name'),
                field(profession, 'Zawód (np. spawacz, monter)',
                    'Profession (e.g. welder, fitter)'),
                field(years, 'Lata doświadczenia', 'Years of experience',
                    max: 2, keyboard: numberKeyboard(decimal: false)),
                Text(context.tr(
                    pl: 'Procesy spawania', en: 'Welding processes')),
                Wrap(spacing: 8, children: [
                  for (final p in [
                    '111',
                    '114',
                    '121',
                    '131',
                    '135',
                    '136',
                    '138',
                    '141',
                    '311'
                  ])
                    FilterChip(
                        label: Text(p),
                        selected: processes.contains(p),
                        onSelected: (v) => setState(() {
                              v ? processes.add(p) : processes.remove(p);
                            }))
                ]),
                const SizedBox(height: 16),
                field(qualifications, 'Uprawnienia i kwalifikacje',
                    'Qualifications',
                    max: 500),
                field(stamp, 'Numer stempla', 'Welder stamp', max: 40),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr(
                        pl: 'Pokazuj profil zawodowy na czacie',
                        en: 'Show professional profile in chat')),
                    value: publicProfile,
                    onChanged: (v) => setState(() => publicProfile = v)),
                SwitchListTile(
                    key: const Key('account-ai-professional-context'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr(pl: 'Dopasuj asystenta AI do mojego zawodu',
                        en: 'Adapt the AI assistant to my profession')),
                    subtitle: Text(context.tr(
                        pl: 'Po włączeniu Railway i Anthropic otrzymają z zapisanego profilu zawód, procesy i lata doświadczenia. Bez nazwiska, e-maila, kwalifikacji i stempla. Ustawienie dotyczy tego konta na tym telefonie.',
                        en: 'When enabled, Railway and Anthropic receive your saved profession, processes and years of experience. Your name, email, qualifications and stamp are excluded. This setting applies to this account on this phone.')),
                    value: AiProfessionalContext.instance.enabled,
                    onChanged: (value) => _run(() => AiProfessionalContext.instance.setEnabled(value))),
                FilledButton(
                    onPressed: () => _run(() async {
                          final experience = int.tryParse(years.text);
                          if (experience == null ||
                              experience < 0 ||
                              experience > 80) {
                            throw AccountException(context.tr(
                                pl: 'Podaj doświadczenie od 0 do 80 lat.',
                                en: 'Enter experience from 0 to 80 years.'));
                          }
                          await service.saveProfile({
                            'displayName': name.text,
                            'profession': profession.text,
                            'experienceYears': experience,
                            'processes': processes.toList(),
                            'qualifications': qualifications.text,
                            'stamp': stamp.text,
                            'publicProfile': publicProfile
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(context.tr(
                                    pl: 'Profil zapisany',
                                    en: 'Profile saved'))));
                          }
                        }),
                    child: Text(
                        context.tr(pl: 'Zapisz profil', en: 'Save profile'))),
                if (service.isAdmin)
                  ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: Text(context.tr(
                          pl: 'Raporty administratora',
                          en: 'Administrator reports')),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const AdminReportsScreen()))),
                TextButton(
                    onPressed: _changePassword,
                    child: Text(
                        context.tr(pl: 'Zmień hasło', en: 'Change password'))),
                TextButton(
                    onPressed: () => _run(() async {
                          await service.signOut();
                          password.clear();
                        }),
                    child: Text(context.tr(pl: 'Wyloguj się', en: 'Sign out'))),
                const Divider(),
                field(password, 'Hasło — wymagane do usunięcia konta',
                    'Password — required to delete account',
                    secret: true, max: 128),
                TextButton(
                    onPressed: () => _delete(),
                    child: Text(
                        context.tr(pl: 'Usuń konto', en: 'Delete account'))),
              ],
            ])));
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final values = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(context.tr(pl: 'Zmień hasło', en: 'Change password')),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                field(current, 'Obecne hasło', 'Current password',
                    secret: true, max: 128),
                field(next, 'Nowe hasło (minimum 12 znaków)',
                    'New password (at least 12 characters)',
                    secret: true, max: 128),
                Text(context.tr(
                    pl: 'Zmiana wyloguje Cię na wszystkich urządzeniach.',
                    en: 'Changing your password signs you out on all devices.')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
                TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, [current.text, next.text]),
                    child: Text(
                        context.tr(pl: 'Zmień hasło', en: 'Change password')))
              ],
            ));
    // Keep controllers alive through the dialog's closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    current.dispose();
    next.dispose();
    if (!mounted || values == null) return;
    await _run(() async {
      await service.request('POST', '/password',
          {'currentPassword': values[0], 'password': values[1]});
      await service.invalidateSession();
      password.clear();
    });
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(
                    context.tr(pl: 'Usunąć konto?', en: 'Delete account?')),
                content: Text(context.tr(
                    pl: 'Profil i wszystkie sesje zostaną usunięte. Wiadomości konta na czacie również zostaną usunięte.',
                    en: 'Your profile and all sessions will be deleted. Account chat messages will also be deleted.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(context.tr(pl: 'Usuń', en: 'Delete')))
                ]));
    if (yes == true && mounted) {
      await _run(() async {
        await service.request('DELETE', '/me', {'password': password.text});
        await service.invalidateSession();
        password.clear();
      });
    }
  }
}

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final service = AccountService.instance;
  int _sessionRevision = 0;
  bool _wasAdmin = false;
  int _generation = 0;
  List<dynamic>? items;
  String? error;
  bool saving = false;
  bool fetching = false;
  int? nextBefore;
  @override
  void initState() {
    super.initState();
    _sessionRevision = service.sessionRevision;
    _wasAdmin = service.isAdmin;
    service.addListener(_sessionChanged);
    if (service.isAdmin) _load();
  }

  void _sessionChanged() {
    if (!mounted ||
        (_sessionRevision == service.sessionRevision &&
            _wasAdmin == service.isAdmin)) {
      return;
    }
    _sessionRevision = service.sessionRevision;
    _wasAdmin = service.isAdmin;
    _generation++;
    setState(() {
      items = null;
      nextBefore = null;
      error = null;
      saving = false;
      fetching = false;
    });
    if (service.isAdmin) _load();
  }

  @override
  void dispose() {
    service.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (fetching || !service.isAdmin) return;
    final generation = _generation;
    fetching = true;
    try {
      final r = await service.request(
          'GET',
          more && nextBefore != null
              ? '/reports?before=$nextBefore'
              : '/reports');
      if (mounted && generation == _generation && service.isAdmin) {
        setState(() {
          items =
              more ? [...?items, ...r['items'] as List] : r['items'] as List;
          nextBefore = r['nextBefore'] as int?;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation && service.isAdmin) {
        setState(() => error = context.tr(
            pl: 'Nie udało się pobrać raportów. Sprawdź połączenie i uprawnienia.',
            en: 'Could not load reports. Check connection and permissions.'));
      }
    } finally {
      if (generation == _generation) fetching = false;
    }
  }

  @override
  Widget build(BuildContext _) => Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Raporty administratora', en: 'Administrator reports')),
          actions: [
            IconButton(
                onPressed: service.isAdmin ? _load : null,
                icon: const Icon(Icons.refresh))
          ]),
      body: !service.isAdmin
          ? Center(
              child: Text(context.tr(
                  pl: 'Dostęp tylko dla administratora.',
                  en: 'Administrator access only.')))
          : error != null
              ? Center(child: Text(error!))
              : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items!.isEmpty
                      ? Center(
                          child: Text(context.tr(
                              pl: 'Brak raportów', en: 'No reports')))
                      : ListView(children: [
                          for (final raw in items!)
                            Builder(builder: (_) {
                              final r = raw as Map;
                              return Card(
                                  margin: const EdgeInsets.all(12),
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                '${r['tool'] ?? r['kind']} · ${r['occurrences']}×',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            const SizedBox(height: 8),
                                            SelectableText('${r['text']}'),
                                            Text(
                                                '${r['receivedAt']} · ${r['app']} · ${r['platform']}'),
                                            DropdownButton<String>(
                                                value: r['status'] as String,
                                                items: [
                                                  DropdownMenuItem(
                                                      value: 'new',
                                                      child: Text(context.tr(
                                                          pl: 'Nowy',
                                                          en: 'New'))),
                                                  DropdownMenuItem(
                                                      value: 'in_progress',
                                                      child: Text(context.tr(
                                                          pl: 'W realizacji',
                                                          en: 'In progress'))),
                                                  DropdownMenuItem(
                                                      value: 'implemented',
                                                      child: Text(context.tr(
                                                          pl: 'Wdrożony',
                                                          en: 'Implemented'))),
                                                ],
                                                onChanged: saving
                                                    ? null
                                                    : (v) async {
                                                        if (v == null) return;
                                                        final generation =
                                                            _generation;
                                                        setState(() =>
                                                            saving = true);
                                                        try {
                                                          await service.request(
                                                              'PUT',
                                                              '/reports/${r['id']}',
                                                              {'status': v});
                                                          if (mounted &&
                                                              generation ==
                                                                  _generation &&
                                                              service.isAdmin) {
                                                            await _load();
                                                          }
                                                        } catch (_) {
                                                          if (mounted &&
                                                              generation ==
                                                                  _generation &&
                                                              service.isAdmin) {
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(SnackBar(
                                                                    content: Text(context.tr(
                                                                        pl: 'Nie zapisano statusu.',
                                                                        en: 'Status was not saved.'))));
                                                          }
                                                        } finally {
                                                          if (mounted &&
                                                              generation ==
                                                                  _generation) {
                                                            setState(() =>
                                                                saving = false);
                                                          }
                                                        }
                                                      }),
                                          ])));
                            }),
                          if (nextBefore != null)
                            TextButton(
                                onPressed: () => _load(more: true),
                                child: Text(context.tr(
                                    pl: 'Starsze raporty',
                                    en: 'Older reports'))),
                        ]));
}
