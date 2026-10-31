import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../assistant/assistant_history.dart';
import '../database/local_record_owner.dart';
import '../config/app_links.dart';
import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../services/blocked_users.dart';
import '../services/data_backup.dart';
import '../services/legal_consent.dart';
import '../services/premium_service.dart';
import '../services/server_data_deletion.dart';
import '../services/user_profile.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart';
import '../utils/haptic.dart';
import '../widgets/scan_consent_gate.dart';
import '../widgets/wpqr_chip.dart';
import 'legal_screen.dart';
import 'account_screen.dart';
import 'onboarding_name_screen.dart'
    show describeNameProblem, fullNameTooLongMessage;
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

class ProfileScreen extends StatefulWidget {
  /// Otwiera od razu okno „Usunąć moje dane?" (wejście z wyszukiwarki na
  /// ekranie głównym). Nic nie znika bez potwierdzenia w tym oknie.
  final bool openDeleteOnStart;

  const ProfileScreen({super.key, this.openDeleteOnStart = false});

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

  // Backup/restore blocks the whole screen while it runs: both operations
  // touch every table, and a second tap mid-restore would race the first.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserProfileService.instance.get();
    await BlockedUsers.instance.load();
    await LegalConsent.instance.load();
    await ScanConsent.load();
    if (!mounted) return;
    setState(() {
      _firstCtrl.text = profile?.firstName ?? '';
      _lastCtrl.text = profile?.lastName ?? '';
      _loading = false;
    });
    if (widget.openDeleteOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _deleteMyData();
      });
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Ten sam walidator co krok imienia przed czatem (user_profile.dart).
    final firstErr =
        describeNameProblem(context, checkNamePart(_firstCtrl.text));
    var lastErr = describeNameProblem(context, checkNamePart(_lastCtrl.text));
    if (firstErr == null &&
        lastErr == null &&
        fullNameTooLong(_firstCtrl.text, _lastCtrl.text)) {
      lastErr = fullNameTooLongMessage(context);
    }
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

  // ───────────────────────── Kopia zapasowa / restore ─────────────────────
  //
  // Do tej pory dane montera nie miały jak wyjść z telefonu: bazy SQLite i
  // zdjęcia certyfikatów wytopu żyły wyłącznie w piaskownicy aplikacji, więc
  // nie dało się ani oddać dokumentacji brygadziście na koniec kontraktu, ani
  // przejść z Androida na iOS, ani odzyskać czegokolwiek po zgubieniu
  // telefonu. Obie pozycje siedzą w profilu, bo to jedyny ekran, który już
  // dziś mówi wprost „to są Twoje dane i to z nimi robimy".
  //
  // Plik nigdzie nie leci sam: powstaje w katalogu tymczasowym i trafia
  // prosto do systemowego arkusza udostępniania. Dokąd pójdzie dalej,
  // decyduje monter — żadnej chmury, żadnego backendu.

  /// Renders a service-level failure in the user's language.
  ///
  /// Reads the language from the controller's static rather than from
  /// `context.tr`, because this runs after an `await` when the screen may
  /// already be gone and an `InheritedWidget` lookup would throw on top of
  /// the error we are trying to report.
  String _describeBackupError(Object error) {
    if (error is BackupFormatException) {
      return AppLanguageController.isEnglish
          ? error.messageEn
          : error.messagePl;
    }
    return '$error';
  }

  /// Runs [task] behind a non-dismissible progress dialog.
  ///
  /// Returns false when [task] threw — the reason is shown in a snackbar
  /// before returning, so every caller can simply bail out on false.
  Future<bool> _runBlocking(String label, Future<void> Function() task) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: kArc),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );

    Object? failure;
    try {
      await task();
    } catch (e) {
      failure = e;
    }

    // Take the dialog down BEFORE the snackbar, otherwise the explanation
    // lands behind the barrier and the user only sees a spinner vanish.
    if (navigator.canPop()) navigator.pop();
    if (mounted) setState(() => _busy = false);
    if (failure == null) return true;

    Haptic.error();
    messenger.showSnackBar(SnackBar(
      content: Text(_describeBackupError(failure)),
      duration: const Duration(seconds: 8),
    ));
    return false;
  }

  Future<void> _backup() async {
    final messenger = ScaffoldMessenger.of(context);
    final ready = context.tr(
      pl: 'Kopia gotowa. Wybierz, gdzie ją zapisać albo komu wysłać.',
      en: 'Backup ready. Choose where to save it or who to send it to.',
    );

    File? archive;
    final built = await _runBlocking(
      context.tr(pl: 'Pakuję kopię zapasową…', en: 'Packing your backup…'),
      () async {
        archive = await DataBackup.createBackupFile();
      },
    );
    final file = archive;
    if (!built || file == null || !mounted) return;

    Haptic.saved();
    messenger.showSnackBar(SnackBar(content: Text(ready)));
    // Sharing happens with the progress dialog already dismissed, so the
    // system sheet is the only thing on screen.
    try {
      await DataBackup.shareBackupFile(file);
    } catch (error) {
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(_describeBackupError(error))));
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;

    // No extension filter on purpose: iOS reports the archive as
    // `public.zip-archive` and Android hands back a `content://` URI whose
    // name may carry no extension at all, so a filter would hide the very
    // file this app wrote. The archive proves its own identity instead —
    // DataBackup.inspect() reads the manifest and refuses a foreign file
    // without touching anything.
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    final picked = result?.files.single;
    final path = picked?.path;
    if (picked == null || path == null || !mounted) return;
    final pickedName = picked.name;

    BackupContents? found;
    LocalRecordOwner? approvedOwner;
    final read = await _runBlocking(
      context.tr(pl: 'Sprawdzam plik…', en: 'Checking the file…'),
      () async {
        approvedOwner = await LocalRecordOwner.capture();
        found = await DataBackup.inspect(path);
        approvedOwner!.requireCurrent();
      },
    );
    final contents = found;
    final ownerAtApproval = approvedOwner;
    if (!read || contents == null || ownerAtApproval == null || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        // Same reason as the delete dialog below: this is a warning about an
        // irreversible operation, and a non-scrollable dialog truncates it on
        // a small phone or at a large system font size.
        scrollable: true,
        title: Text(context.tr(
            pl: 'Nadpisać dane z tego pliku?',
            en: 'Overwrite with this file?')),
        content: Text(context.tr(
          pl: 'Plik: $pickedName\n'
              'Zapisany: ${formatBackupTimestamp(contents.manifest.createdAt)}\n'
              'Zdjęcia wytopów w pliku: ${contents.photoCount}.\n\n'
              'Przywracanie NADPISZE lokalne dane z kopii — '
              'projekty, cut listy, dziennik spoin, zdjęcia, rejestr uprawnień '
              'spawacza i Bibliotekę WPS — i wstawi w to miejsce zawartość '
              'pliku. Parametry spawania i szkice ISO zastąpi tylko na obecnym koncie '
              'lub w trybie gościa; parametry i szkice innych kont pozostaną '
              'bez zmian. Tego nie da się cofnąć, więc jeśli '
              'masz tu coś, czego w pliku nie ma, najpierw zrób kopię.\n\n'
              'Nic nie ruszymy, dopóki nie przeczytamy całego pliku do końca. '
              'Jeśli jest uszkodzony albo obcy — powiemy o tym i zostawimy '
              'Twoje dane w spokoju.\n\n'
              'Kopia nie zawiera Twojego imienia, stempla spawacza ani zgody '
              'na zasady — te zostają takie, jakie są na tym telefonie.',
          en: 'File: $pickedName\n'
              'Created: ${formatBackupTimestamp(contents.manifest.createdAt)}\n'
              'Heat photos in the file: ${contents.photoCount}.\n\n'
              'Restoring will OVERWRITE the local data covered by this backup — '
              'projects, cut lists, weld journal, photos, the welder '
              'qualification register and the WPS library — and replace it '
              'with the contents of the file. Welding parameters and ISO sketches are replaced '
              'only for the current account or guest; other accounts’ saved '
              'parameters and sketches remain unchanged. This cannot be undone, so if '
              'you have anything here that is not in the file, back it up '
              'first.\n\n'
              'Nothing is touched until the whole file has been read. If it '
              'is damaged or foreign we will say so and leave your data '
              'alone.\n\n'
              'The backup does not carry your name, your welder stamp or your '
              'consent — those stay exactly as they are on this phone.',
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
            child: Text(context.tr(pl: 'Nadpisz', en: 'Overwrite')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    RestoreReport? outcome;
    final restored = await _runBlocking(
      context.tr(pl: 'Przywracam dane…', en: 'Restoring your data…'),
      () async {
        outcome =
            await DataBackup.restore(path, expectedOwner: ownerAtApproval);
      },
    );
    final report = outcome;
    if (!restored || report == null || !mounted) return;

    // Kopia z nowszej wersji aplikacji mogła nieść tabele albo kolumny, których
    // ta wersja nie ma — tych danych nie przywróciliśmy. Snackbar znika po
    // kilku sekundach, a to jest informacja o brakujących danych, więc okno
    // czeka na potwierdzenie, ZANIM przebudujemy aplikację.
    if (!report.isComplete) {
      await showRestoreWarning(context, report);
      if (!mounted) return;
    } else {
      Haptic.saved();
    }
    messenger.showSnackBar(SnackBar(
      // Liczby podane w formie „etykieta: N", bo polska odmiana rzeczownika
      // po liczbie (1 rekord / 2 rekordy / 5 rekordów) i tak nie zmieści się
      // w jednym stringu, a „1 rekordów" wygląda jak błąd aplikacji.
      content: Text(context.tr(
        pl: 'Przywrócono. Rekordy: ${report.rowCount}. '
            'Zdjęcia: ${report.photoCount}.',
        en: 'Restored. Records: ${report.rowCount}. '
            'Photos: ${report.photoCount}.',
      )),
      duration: const Duration(seconds: 6),
    ));
    // Every screen underneath is rendering rows that no longer exist. Same
    // exit as „usuń moje dane": rebuild the app from the gate.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootGate()),
      (route) => false,
    );
  }

  /// Google Play wymaga ścieżki usunięcia danych, gdy aplikacja cokolwiek
  /// wysyła. Kolejność ma znaczenie:
  ///   1. `DELETE /api/fitter/me` — serwer rozpoznaje nas po device_id i
  ///      sekrecie instalacji, więc to musi pójść, ZANIM je skasujemy;
  ///   2. dane na telefonie;
  ///   3. podsumowanie: co zniknęło z serwera, a co z telefonu.
  /// Stary backend (404) nie umie usuwać — wtedy mówimy wprost, że wiadomości
  /// z czatu usuwamy mailowo, zamiast udawać, że przycisk cofnął to, co
  /// zobaczyli inni. Bez sieci pytamy, czy usunąć tylko lokalnie.
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
          pl: 'Najpierw usuniemy z serwera Twoje wiadomości z czatu, '
              'zgłoszenia, ogłoszenia oraz identyfikator i sekret instalacji.\n\n'
              'Potem skasujemy z tego telefonu Twoje imię i nazwisko, zgodę na '
              'zasady, zgodę na wysyłkę zdjęć do skanera, historię asystenta, '
              'listę zablokowanych i zgłoszonych wiadomości, tożsamość '
              'spawacza (stempel i e-mail) oraz rejestr uprawnień spawacza '
              '(certyfikaty, zdjęcia, przypomnienia). Nowe spoiny przestaną '
              'się podpisywać Twoim stemplem.\n\n'
              'Projekty, cut listy, Biblioteka WPS i zapisane spoiny zostają '
              '— razem ze stemplem, którym już je podpisałeś.\n\n'
              'Na koniec pokażemy, co dokładnie usunęliśmy na serwerze, a co na '
              'telefonie.',
          en: 'First we delete from the server your chat messages, reports, job '
              'listings and your installation identifier and secret.\n\n'
              'Then we erase from this phone your name, your consent to the '
              'rules, your consent to send photos to the scanner, the '
              'assistant history, your block list and reported messages, '
              'your welder identity (stamp and e-mail) and the '
              'welder qualification register (certificates, photos, '
              'reminders). New welds will no longer be signed with your '
              'stamp.\n\n'
              'Projects, cut lists, the WPS library and saved welds stay — '
              'including the stamp you already signed them with.\n\n'
              'At the end we show exactly what was deleted on the server and '
              'what on the phone.',
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

    // 1. Serwer — przed skasowaniem identyfikatora instalacji.
    ServerDeletionResult? outcome;
    final ran = await _runBlocking(
      context.tr(
          pl: 'Usuwam dane z serwera…',
          en: 'Deleting your data from the server…'),
      () async {
        outcome = await ServerDataDeletion.deleteMyServerData();
      },
    );
    final server = outcome;
    if (!ran || server == null || !mounted) return;

    switch (server.status) {
      case ServerDeletionStatus.rateLimited:
        // Nic nie kasujemy: identyfikator instalacji musi zostać, żeby
        // ponowienie później mogło usunąć dane z serwera.
        await _showDeletionInfo(
          title: context.tr(pl: 'Spróbuj później', en: 'Try again later'),
          body: context.tr(
            pl: 'Serwer chwilowo nie przyjmuje kolejnych próśb o usunięcie '
                'danych z tej sieci. Spróbuj później (najpóźniej jutro) albo '
                'napisz na ${AppLinks.supportEmail}.\n\n'
                'Na telefonie niczego nie usunęliśmy.',
            en: 'The server is not accepting more deletion requests from this '
                'network right now. Try again later (tomorrow at the latest) '
                'or write to ${AppLinks.supportEmail}.\n\n'
                'Nothing was deleted on the phone.',
          ),
        );
        return;
      case ServerDeletionStatus.offline:
      case ServerDeletionStatus.rejected:
      case ServerDeletionStatus.failed:
        final localOnly = await _askDeleteLocalOnly(server.status);
        if (localOnly != true || !mounted) return;
      case ServerDeletionStatus.deleted:
      case ServerDeletionStatus.nothingToDelete:
      case ServerDeletionStatus.notSupported:
        break;
    }
    if (!mounted) return;

    // Identyfikator instalacji łączy telefon z aktywną subskrypcją (Stripe
    // client_reference_id). Póki ona trwa, nie odcinamy od niej płacącego.
    final keepIdentity =
        server.premiumRetained || PremiumService.instance.isPremium;
    final summaryTitle = server.serverDataDeleted ||
            server.status == ServerDeletionStatus.nothingToDelete
        ? context.tr(pl: 'Dane usunięte', en: 'Data deleted')
        : context.tr(
            pl: 'Usunięto tylko z telefonu', en: 'Deleted from the phone only');
    final summaryBody =
        '${_serverSummary(server)}\n\n${_localSummary(keepIdentity)}';
    final gotIt = context.tr(pl: 'Rozumiem', en: 'Got it');

    // 2. Telefon.
    final localOk = await _eraseLocalData(resetIdentity: !keepIdentity);
    if (!mounted) return;
    if (!localOk) {
      await _showDeletionInfo(
        title: context.tr(
            pl: 'Niepełne usunięcie danych', en: 'Data deletion incomplete'),
        body: '${_serverSummary(server)}\n\n${context.tr(
          pl: 'Nie udało się usunąć z telefonu całej historii asystenta, oznaczeń zgłoszonych wiadomości, blokad autorów, zgody skanera lub tożsamości i uprawnień spawacza imienia i nazwiska, zgody na zasady lub identyfikatora instalacji. Ponów usunięcie danych.',
          en: 'Could not delete reported message markers, blocked authors, assistant history, scanner consent or welder identity and qualifications profile name, rules consent or installation identifier from this phone. Retry data deletion.',
        )}',
      );
      return;
    }
    if (!mounted) return;
    Haptic.saved();
    // Wracamy na ekran główny od nowa. Kalkulatory działają dalej; czat przy
    // następnym wejściu zapyta o imię, nazwisko i zasady (community_gate.dart).
    final navigator = Navigator.of(context);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootGate()),
      (route) => false,
    );
    // 3. Podsumowanie nad świeżym ekranem głównym (ten ekran już nie żyje,
    // więc teksty są policzone wyżej). Okno, nie snackbar — to informacja o
    // danych, której nie wolno przegapić.
    unawaited(showDialog<void>(
      context: navigator.context,
      builder: (dctx) => AlertDialog(
        scrollable: true,
        title: Text(summaryTitle),
        content: Text(summaryBody,
            style: const TextStyle(color: kText, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(gotIt),
          ),
        ],
      ),
    ));
  }

  /// Co stało się na serwerze — jednym akapitem, po ludzku.
  String _serverSummary(ServerDeletionResult server) {
    final byMail = context.tr(
      pl: 'Żeby je usunąć, napisz na ${AppLinks.supportEmail} i podaj imię i '
          'nazwisko, którym podpisywałeś wiadomości, oraz przybliżone daty. '
          'Usuniemy je najpóźniej w ciągu 30 dni.',
      en: 'To delete them, write to ${AppLinks.supportEmail} with the name you '
          'signed your messages with and approximate dates. We delete them '
          'within 30 days at the latest.',
    );
    switch (server.status) {
      case ServerDeletionStatus.deleted:
        // „Etykieta: N" zamiast odmiany — polska liczba mnoga po liczbie nie
        // zmieści się w jednym stringu („1 wiadomości" wygląda jak błąd).
        final premium = server.premiumRetained
            ? context.tr(
                pl: '\n\nDane aktywnej subskrypcji Premium zostają na serwerze '
                    'do jej zakończenia — anuluj ją w „Zarządzaj subskrypcją", '
                    'a potem ponów usunięcie.',
                en: '\n\nThe data of your active Premium subscription stays on '
                    'the server until it ends — cancel it in "Manage '
                    'subscription", then delete again.',
              )
            : '';
        return context.tr(
              pl: 'Z serwera usunęliśmy Twoje dane. '
                  'Wiadomości z czatu: ${server.count('chat_messages')}. '
                  'Zgłoszenia: ${server.count('chat_reports')}. '
                  'Ogłoszenia: ${server.count('job_listings')}. '
                  'Do tego identyfikator i sekret instalacji oraz liczniki '
                  'limitów.',
              en: 'We deleted your data from the server. '
                  'Chat messages: ${server.count('chat_messages')}. '
                  'Reports: ${server.count('chat_reports')}. '
                  'Job listings: ${server.count('job_listings')}. '
                  'Plus your installation identifier and secret and the '
                  'rate-limit counters.',
            ) +
            premium;
      case ServerDeletionStatus.nothingToDelete:
        return context.tr(
          pl: 'Ta instalacja nie wysyłała danych na serwer — nie było tam '
              'czego usuwać.',
          en: 'This installation never sent data to the server — there was '
              'nothing to delete there.',
        );
      case ServerDeletionStatus.notSupported:
        return context.tr(
              pl: 'Serwer nie obsługuje jeszcze usuwania danych z aplikacji, '
                  'więc Twoje wiadomości z czatu są na nim nadal. ',
              en: 'The server does not support deletion from the app yet, so '
                  'your chat messages are still there. ',
            ) +
            byMail;
      case ServerDeletionStatus.offline:
      case ServerDeletionStatus.rejected:
      case ServerDeletionStatus.failed:
      case ServerDeletionStatus.rateLimited:
        return context.tr(
              pl: 'Danych na serwerze NIE usunęliśmy (wiadomości z czatu, '
                  'zgłoszenia). ',
              en: 'We did NOT delete your data on the server (chat messages, '
                  'reports). ',
            ) +
            byMail;
    }
  }

  String _localSummary(bool identityKept) => identityKept
      ? context.tr(
          pl: 'Z telefonu usunęliśmy: imię i nazwisko, zgodę na zasady, zgodę '
              'skanera (wysyłka zdjęć), historię asystenta, listę '
              'zablokowanych i zgłoszonych, tożsamość spawacza (stempel, '
              'e-mail) i rejestr uprawnień (certyfikaty, zdjęcia, '
              'przypomnienia). Identyfikator instalacji zostaje, bo łączy '
              'telefon z aktywną subskrypcją Premium. Projekty, cut listy i '
              'dziennik spoin zostają.',
          en: 'Deleted from the phone: your name, your consent to the rules, '
              'your scanner consent (photo upload), the assistant history, '
              'your block and report lists, your welder identity (stamp, '
              'e-mail) and the qualification register (certificates, photos, '
              'reminders). The installation identifier stays because it '
              'links the phone to your active Premium subscription. Projects, '
              'cut lists and the weld journal stay.',
        )
      : context.tr(
          pl: 'Z telefonu usunęliśmy: imię i nazwisko, zgodę na zasady, zgodę '
              'skanera (wysyłka zdjęć), historię asystenta, listę '
              'zablokowanych i zgłoszonych, tożsamość spawacza (stempel, '
              'e-mail), rejestr uprawnień (certyfikaty, zdjęcia, '
              'przypomnienia) oraz identyfikator i sekret instalacji. '
              'Projekty, cut listy i dziennik spoin zostają.',
          en: 'Deleted from the phone: your name, your consent to the rules, '
              'your scanner consent (photo upload), the assistant history, '
              'your block and report lists, your welder identity (stamp, '
              'e-mail), the qualification register (certificates, photos, '
              'reminders) and the installation identifier and secret. '
              'Projects, cut lists and the weld journal stay.',
        );

  /// Serwer nie usunął danych (brak sieci, odrzucona instalacja, błąd).
  /// Pytamy, czy mimo to usunąć dane z telefonu — i mówimy, jak potem
  /// usunąć te z serwera.
  Future<bool?> _askDeleteLocalOnly(ServerDeletionStatus status) {
    final reason = switch (status) {
      ServerDeletionStatus.offline => context.tr(
          pl: 'Nie udało się połączyć z serwerem, więc Twoich danych z czatu '
              'jeszcze nie usunęliśmy.',
          en: 'We could not reach the server, so your chat data has not been '
              'deleted yet.',
        ),
      ServerDeletionStatus.rejected => context.tr(
          pl: 'Serwer nie rozpoznał tej instalacji aplikacji, więc nie usunął '
              'Twoich danych z czatu.',
          en: 'The server did not recognise this app installation, so it did '
              'not delete your chat data.',
        ),
      _ => context.tr(
          pl: 'Serwer odpowiedział błędem, więc nie usunął Twoich danych z '
              'czatu.',
          en: 'The server answered with an error, so it did not delete your '
              'chat data.',
        ),
    };
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        scrollable: true,
        title: Text(status == ServerDeletionStatus.offline
            ? context.tr(pl: 'Brak połączenia', en: 'No connection')
            : context.tr(
                pl: 'Serwer nie usunął danych',
                en: 'The server did not delete your data')),
        content: Text(
          reason +
              context.tr(
                pl: '\n\nAnuluj i spróbuj ponownie później (np. w zasięgu) — '
                    'wtedy aplikacja usunie je sama.\n\n'
                    'Możesz też usunąć dane tylko z tego telefonu. Dane z '
                    'serwera usuniesz wtedy już tylko mailowo: napisz na '
                    '${AppLinks.supportEmail}, podaj imię i nazwisko, którym '
                    'podpisywałeś wiadomości, i przybliżone daty.',
                en: '\n\nCancel and try again later (e.g. with signal) — the '
                    'app will then delete it itself.\n\n'
                    'You can also delete the data from this phone only. The '
                    'server data can then be deleted only by e-mail: write to '
                    '${AppLinks.supportEmail} with the name you signed your '
                    'messages with and approximate dates.',
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.tr(
                pl: 'Usuń tylko z telefonu', en: 'Delete from phone only')),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeletionInfo(
      {required String title, required String body}) {
    return showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(context.tr(pl: 'Rozumiem', en: 'Got it')),
          ),
        ],
      ),
    );
  }

  /// Dane na telefonie: profil, zgody (zasady i skaner), historia asystenta,
  /// tożsamość spawacza, blokady, zgłoszone wiadomości i — gdy
  /// [resetIdentity] — identyfikator i sekret instalacji (nowa para powstanie
  /// dopiero przy następnym kontakcie z serwerem; nic nie leci na serwer).
  Future<bool> _eraseLocalData({required bool resetIdentity}) async {
    final profileCleared = await UserProfileService.instance.clear();
    final legalCleared = await LegalConsent.instance.clear();
    // Zgoda na wysyłkę zdjęć do skanera to osobna zgoda — bez tego skaner po
    // „usuń moje dane" dalej wysyłał zdjęcia bez pytania.
    final scanCleared = await ScanConsent.clear();
    // Historia asystenta trzyma opisy zapisanych operacji (parametry, notatki).
    final historyCleared = await AssistantHistoryStore.instance.clear();
    final reportedCleared = await ReportedMessages.instance.clear();
    // Tego brakowało. Bez tego wywołania „usuń moje dane" zostawiało na
    // telefonie komplet danych spawacza (stempel, nr WPQR, e-mail), a
    // weld_journal_screen dalej pre-wypełniał nimi pole „spawacz" — nowe
    // spoiny podpisywały się człowiekiem, który właśnie kazał się usunąć.
    // WelderIdentityService.clear() istniał od P0-08 i nie wołał go NIKT.
    final identityCleared = await WelderIdentityService.instance.clear();
    final blockedCleared = await BlockedUsers.instance.clear();
    final installationCleared =
        !resetIdentity || await PremiumService.instance.resetIdentity();
    return installationCleared &&
        legalCleared &&
        profileCleared &&
        scanCleared &&
        historyCleared &&
        reportedCleared &&
        blockedCleared &&
        identityCleared;
  }

  // ───────────────────────────── Zgody ─────────────────────────────────────
  //
  // RODO art. 7 ust. 3: wycofanie zgody ma być tak łatwe jak jej wyrażenie.
  // Wycofanie działa na przyszłość — dane już wysłane na serwer usuwa
  // „Usuń moje dane", i okno mówi to wprost.

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _withdrawConsent({required bool scanner}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        scrollable: true,
        title: Text(context.tr(pl: 'Wycofać zgodę?', en: 'Withdraw consent?')),
        content: Text(scanner
            ? context.tr(
                pl: 'Skaner nie wyśle żadnego zdjęcia, dopóki znowu się nie '
                    'zgodzisz — zapyta o to przy następnym skanie. Ręczne '
                    'wpisywanie wymiarów działa bez zgody.',
                en: 'The scanner will not send any photo until you agree '
                    'again — it asks before the next scan. Typing dimensions '
                    'by hand works without consent.',
              )
            : context.tr(
                pl: 'Czat i odpowiedzi asystenta zapytają o akceptację zasad '
                    'przy następnym użyciu. Kalkulatory działają bez niej.\n\n'
                    'To, co już wysłałeś, zostaje na serwerze — żeby to '
                    'usunąć, użyj „Usuń moje dane".',
                en: 'Chat and assistant answers will ask you to accept the '
                    'rules the next time you use them. The calculators work '
                    'without it.\n\n'
                    'What you already sent stays on the server — to remove '
                    'it, use "Delete my data".',
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
            child: Text(context.tr(pl: 'Wycofaj', en: 'Withdraw')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var persisted = true;
    if (scanner) {
      persisted = await ScanConsent.clear();
    } else {
      persisted = await LegalConsent.instance.clear();
    }
    if (!mounted) return;
    Haptic.saved();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(persisted
          ? context.tr(pl: 'Zgoda wycofana.', en: 'Consent withdrawn.')
          : context.tr(
              pl: 'Zgoda wycofana w tej sesji. Nie udało się usunąć zapisu z telefonu. Ponów wycofanie przed zamknięciem aplikacji.',
              en: 'Consent withdrawn for this session. Could not delete the saved consent from this phone. Retry before closing the app.',
            )),
    ));
  }

  Widget _consentTile({
    required String keyId,
    required IconData icon,
    required String title,
    required DateTime? acceptedAt,
    required bool accepted,
    bool withdrawalPending = false,
    required VoidCallback onWithdraw,
  }) {
    final status = withdrawalPending
        ? context.tr(
            pl: 'Wycofana w tej sesji — ponów usunięcie zapisu z telefonu',
            en: 'Withdrawn for this session — retry deleting the saved consent',
          )
        : accepted
            ? context.tr(
                pl: acceptedAt == null
                    ? 'Udzielona (zasady w wersji $kLegalVersion)'
                    : 'Udzielona ${_formatDate(acceptedAt)} '
                        '(zasady w wersji $kLegalVersion)',
                en: acceptedAt == null
                    ? 'Given (rules version $kLegalVersion)'
                    : 'Given ${_formatDate(acceptedAt)} '
                        '(rules version $kLegalVersion)',
              )
            : context.tr(
                pl: 'Nie udzielona — zapytamy, gdy będzie potrzebna',
                en: 'Not given — we ask when it is needed');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCard,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kBorder),
        ),
        child: ListTile(
          minVerticalPadding: 12,
          leading: Icon(icon, color: kTextSec, size: 20),
          title: Text(title,
              style: const TextStyle(
                  color: kText, fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(status,
              style: const TextStyle(color: kTextMut, fontSize: 12)),
          trailing: accepted || withdrawalPending
              ? TextButton(
                  key: ValueKey('consent-withdraw-$keyId'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                  ),
                  onPressed: onWithdraw,
                  child: Text(
                    withdrawalPending
                        ? context.tr(pl: 'Ponów', en: 'Retry')
                        : context.tr(pl: 'Wycofaj', en: 'Withdraw'),
                    style: const TextStyle(
                        color: kArc, fontWeight: FontWeight.w700),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Future<void> _unblock(BlockedUser u) async {
    final persisted = await BlockedUsers.instance.unblock(u.deviceId);
    if (!mounted) return;
    Haptic.saved();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(persisted
          ? context.tr(pl: 'Odblokowano ${u.name}.', en: 'Unblocked ${u.name}.')
          : context.tr(
              pl: 'Odblokowano w tej sesji. Nie udało się zapisać zmiany na później.',
              en: 'Unblocked for this session. Could not save the change for later.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final blocked = BlockedUsers.instance.all;
    final fullName =
        '${_firstCtrl.text.trim()} ${_lastCtrl.text.trim()}'.trim();

    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(pl: 'Twój profil', en: 'Your profile'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _Identity(name: fullName),
                ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(context.tr(
                        pl: 'Konto i profil zawodowy',
                        en: 'Account and professional profile')),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const AccountScreen()))),
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
                      pl: 'Co zostaje na telefonie',
                      en: 'What stays on your phone'),
                  body: context.tr(
                    pl: 'Projekty, cut listy, dziennik spoin, zdjęcia wytopów i '
                        'wyniki kalkulatorów. Nic z tego nie trafia na nasz '
                        'serwer. Na serwer idzie tylko to, co sam wyślesz: '
                        'wiadomość na czacie, zdjęcie rysunku do skanera albo '
                        'pytanie do asystenta.',
                    en: 'Projects, cut lists, weld journal, heat photos and '
                        'calculator results. None of it goes to our server. '
                        'Only what you send goes there: a chat message, a '
                        'drawing photo for the scanner or a question for the '
                        'assistant.',
                  ),
                ),
                const SizedBox(height: 26),

                _Label(context.tr(pl: 'Imię', en: 'First name')),
                const SizedBox(height: 8),
                TextField(
                  controller: _firstCtrl,
                  textCapitalization: TextCapitalization.words,
                  maxLength: kNamePartMaxLength,
                  decoration:
                      InputDecoration(errorText: _firstError, counterText: ''),
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
                  maxLength: kNamePartMaxLength,
                  decoration:
                      InputDecoration(errorText: _lastError, counterText: ''),
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
                        pl: 'Nikogo nie zablokowałeś. Na czacie stuknij ⋮ przy '
                            'wiadomości (albo ją przytrzymaj), żeby zgłosić ją '
                            'lub zablokować autora.',
                        en: 'You have not blocked anyone. In chat, tap ⋮ next '
                            'to a message (or long-press it) to report it or '
                            'block its author.',
                      ),
                      style: const TextStyle(
                          color: kTextSec, fontSize: 13, height: 1.5),
                    ),
                  )
                else
                  ...blocked.map((u) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      // Material (not a DecoratedBox) so the tile's ink
                      // splash stays visible on the card background.
                      child: Material(
                        color: kCard,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: kBorder),
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
                            style:
                                const TextStyle(color: kTextMut, fontSize: 12),
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
                      ))),

                const SizedBox(height: 32),
                _Label(context.tr(pl: 'Twoje dane', en: 'Your data')),
                const SizedBox(height: 8),
                _Notice(
                  icon: Icons.inventory_2_outlined,
                  accent: kTextSec,
                  title: context.tr(
                      pl: 'Co jest w kopii', en: "What's in the backup"),
                  body: context.tr(
                    pl: 'Jeden plik ZIP: projekty, cut listy, dziennik spoin, '
                        'zdjęcia wytopów, rejestr uprawnień spawacza '
                        '(certyfikaty ze zdjęciami) i Biblioteka WPS (z '
                        'plikami). Otworzysz go na komputerze bez tej '
                        'aplikacji. Powstaje w telefonie i idzie prosto do '
                        'arkusza udostępniania — sami nie wysyłamy go nigdzie. '
                        'Nie ma w nim Twojego imienia, stempla spawacza ani '
                        'zgody na zasady; te zostają na telefonie.',
                    en: 'One ZIP file: projects, cut lists, weld journal, heat '
                        'photos, the welder qualification register '
                        '(certificates with photos) and the WPS library (with '
                        'files). It opens on a computer without this app. '
                        'It is built on the phone and handed straight to the '
                        'share sheet — we never send it anywhere ourselves. It '
                        'does not carry your name, your welder stamp or your '
                        'consent; those stay on the phone.',
                  ),
                ),
                const SizedBox(height: 10),
                _LinkTile(
                  icon: Icons.save_alt,
                  label:
                      context.tr(pl: 'Kopia zapasowa', en: 'Back up my data'),
                  subtitle: context.tr(
                      pl: 'Zapisz wszystko do jednego pliku',
                      en: 'Save everything to one file'),
                  onTap: _busy ? null : _backup,
                ),
                _LinkTile(
                  icon: Icons.settings_backup_restore,
                  label: context.tr(
                      pl: 'Przywróć z pliku', en: 'Restore from a file'),
                  subtitle: context.tr(
                      pl: 'Nadpisze dane na tym telefonie',
                      en: 'Overwrites the data on this phone'),
                  onTap: _busy ? null : _restore,
                ),

                const SizedBox(height: 32),
                _Label(context.tr(pl: 'Zgody', en: 'Consents')),
                const SizedBox(height: 8),
                _consentTile(
                  keyId: 'rules',
                  icon: Icons.gavel_outlined,
                  title: context.tr(
                      pl: 'Zasady (czat i asystent)',
                      en: 'Rules (chat and assistant)'),
                  acceptedAt: LegalConsent.instance.acceptedAt,
                  accepted: LegalConsent.instance.isAccepted,
                  withdrawalPending: LegalConsent.instance.withdrawalPending,
                  onWithdraw: () => _withdrawConsent(scanner: false),
                ),
                _consentTile(
                  keyId: 'scanner',
                  icon: Icons.document_scanner_outlined,
                  title: context.tr(
                      pl: 'Wysyłka zdjęć do skanera',
                      en: 'Sending photos to the scanner'),
                  acceptedAt: ScanConsent.acceptedAt,
                  accepted: ScanConsent.isAccepted,
                  withdrawalPending: ScanConsent.withdrawalPending,
                  onWithdraw: () => _withdrawConsent(scanner: true),
                ),

                const SizedBox(height: 32),
                _Label(context.tr(
                    pl: 'Zasady i prywatność', en: 'Rules and privacy')),
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

/// Ostrzeżenie po przywróceniu kopii, z której części danych nie dało się
/// zapisać ([RestoreReport.isComplete] == false). Nic nie robi, gdy kopia
/// weszła w całości.
Future<void> showRestoreWarning(BuildContext context, RestoreReport report) {
  if (report.isComplete) return Future.value();
  Haptic.error();
  return showDialog<void>(
    context: context,
    builder: (dctx) => AlertDialog(
      // Lista pominiętych tabel bywa długa — przewijane okno jej nie utnie.
      scrollable: true,
      icon: const Icon(Icons.warning_amber_rounded, color: kWarn, size: 30),
      title: Text(context.tr(
          pl: 'Przywrócono, ale nie wszystko',
          en: 'Restored, but not everything')),
      content: Text(
        context.tr(pl: report.warningPl!, en: report.warningEn!),
        style: const TextStyle(color: kText, fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          ),
          onPressed: () => Navigator.pop(dctx),
          child: Text(context.tr(pl: 'Rozumiem', en: 'Got it')),
        ),
      ],
    ),
  );
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;

  /// Nullable so backup/restore can be greyed out while one of them is
  /// running — a second tap mid-restore would race the first over the same
  /// tables. A disabled tile that still looks tappable is worse than none.
  final VoidCallback? onTap;

  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = !enabled
        ? kTextMut
        : danger
            ? kFail
            : kText;
    // Material (not a DecoratedBox) so the tile's ink splash stays visible on
    // the card background — a tap needs visible feedback in gloves.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCard,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kBorder),
        ),
        child: ListTile(
          enabled: enabled,
          minVerticalPadding: 12,
          leading: Icon(icon,
              color: !enabled
                  ? kTextMut
                  : danger
                      ? kFail
                      : kTextSec,
              size: 20),
          title: Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!,
                  style: const TextStyle(color: kTextMut, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: kTextMut, size: 20),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  final String name;
  const _Identity({required this.name});

  String get _initials {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
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
                // Bez imienia aplikacja działa w całości — poza czatem, który
                // podpisuje wiadomości imieniem i nazwiskiem.
                name.isEmpty
                    ? context.tr(
                        pl: 'Potrzebne tylko do pisania na czacie',
                        en: 'Only needed to post in chat')
                    // Serwer trzyma podpis przy każdej wysłanej wiadomości —
                    // zmiana imienia dotyczy tylko nowych.
                    : context.tr(
                        pl: 'Tak podpisujesz nowe wiadomości',
                        en: 'This signs your new messages'),
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
              style:
                  const TextStyle(color: kTextSec, fontSize: 13, height: 1.5)),
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
