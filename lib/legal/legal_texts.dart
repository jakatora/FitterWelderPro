import 'package:flutter/widgets.dart';

import '../config/app_links.dart';
import '../i18n/app_language.dart';

// Regulamin i polityka prywatności — jedno źródło prawdy dla ekranów w aplikacji.
// Wersję hostowaną (URL-e dla sklepów, AppLinks) serwuje backend:
// `backend/src/routes/publicPages.js` (/privacy, /data-deletion). Oba teksty
// muszą mówić to samo — zmieniasz jeden, zmień drugi.
//
// ZASADA: ten tekst musi opisywać to, co aplikacja NAPRAWDĘ robi. Poprzednia
// polityka twierdziła, że apka „nie zbiera, nie przechowuje i nie przesyła
// żadnych danych osobowych", podczas gdy czat wysyła imię i nazwisko oraz
// identyfikator urządzenia na serwer. Jeśli zmieniasz zachowanie aplikacji —
// zmień najpierw ten plik i podnieś [kLegalVersion].
//
// Wersja 2 (2026-09-24): sekret instalacji i rejestracja urządzenia dopiero
// przy czacie, skróty adresów IP na serwerze, pseudonim autora zamiast
// identyfikatora, usuwanie danych z serwera przyciskiem w profilu.

/// Podniesienie tej liczby wymusza ponowną akceptację u wszystkich użytkowników.
/// Blokuje to tylko czat (community_gate.dart) — kalkulatory działają dalej.
const int kLegalVersion = 2;

const String kLegalUpdated = '2026-09-24';

/// Minimalny wiek. Czat jest publiczny i nie moderujemy go całodobowo.
const int kMinimumAge = 16;

class LegalSection {
  final String heading;
  final String body;
  const LegalSection(this.heading, this.body);
}

class LegalDocument {
  final String title;
  final String intro;
  final List<LegalSection> sections;
  const LegalDocument({
    required this.title,
    required this.intro,
    required this.sections,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// POLITYKA PRYWATNOŚCI
// ─────────────────────────────────────────────────────────────────────────────
LegalDocument privacyPolicy(BuildContext c) => LegalDocument(
      title: c.tr(pl: 'Polityka prywatności', en: 'Privacy Policy'),
      intro: c.tr(
        pl: 'Krótko: kalkulatory i projekty zostają na Twoim telefonie. Na '
            'serwer wysyłamy dane tylko wtedy, gdy sam napiszesz na publicznym '
            'czacie. Nie ma reklam, analityki ani śledzenia.',
        en: 'In short: calculators and projects stay on your phone. We send data '
            'to a server only when you post in the public chat. No ads, no '
            'analytics, no tracking.',
      ),
      sections: [
        LegalSection(
          c.tr(pl: 'Co zostaje na Twoim telefonie', en: 'What stays on your phone'),
          c.tr(
            pl: 'Projekty, cut listy, dziennik spoin, zdjęcia numerów wytopu, '
                'parametry spawania, wyniki kalkulatorów, Twoja lista '
                'zablokowanych osób oraz imię i nazwisko z profilu. Te dane nie '
                'opuszczają urządzenia. Usuwają się razem z odinstalowaniem '
                'aplikacji.',
            en: 'Projects, cut lists, weld journal, heat-number photos, welding '
                'parameters, calculator results, your block list and the name in '
                'your profile. This data never leaves the device and is removed '
                'when you uninstall the app.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Co wysyłamy, gdy piszesz na czacie', en: 'What we send when you post in chat'),
          c.tr(
            pl: 'Wysyłamy treść wiadomości, Twoje imię i nazwisko z profilu, '
                'znacznik czasu oraz identyfikator instalacji aplikacji (losowy '
                'ciąg wygenerowany na Twoim urządzeniu — nie jest to numer '
                'telefonu, IMEI ani identyfikator reklamowy). Identyfikator służy '
                'do rozpoznania Twoich własnych wiadomości oraz do egzekwowania '
                'blokad i zgłoszeń. Innym użytkownikom nie pokazujemy Twojego '
                'identyfikatora — widzą tylko jego nieodwracalny skrót.',
            en: 'We send the message text, the first and last name from your '
                'profile, a timestamp and an installation identifier (a random '
                'string generated on your device — not a phone number, IMEI or '
                'advertising ID). The identifier lets the app recognise your own '
                'messages and lets us enforce blocks and reports. Other users '
                'never see your identifier — only an irreversible hash of it.',
          ),
        ),
        LegalSection(
          c.tr(
              pl: 'Kiedy aplikacja łączy się z serwerem',
              en: 'When the app contacts the server'),
          c.tr(
            pl: 'Kalkulatory, projekty i dziennik spoin działają bez serwera. '
                'Aplikacja przedstawia się serwerowi czatu (identyfikator i '
                'sekret instalacji) dopiero wtedy, gdy zaakceptujesz te zasady '
                'i wejdziesz na czat — a potem przy kolejnych uruchomieniach. '
                'Wcześniej nic nie wysyła.',
            en: 'Calculators, projects and the weld journal work without the '
                'server. The app introduces itself to the chat server '
                '(installation identifier and secret) only after you accept '
                'these rules and open the chat — and on later launches. Before '
                'that it sends nothing.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Czat jest publiczny', en: 'The chat is public'),
          c.tr(
            pl: 'Każdy użytkownik aplikacji widzi Twoje wiadomości razem z Twoim '
                'imieniem i nazwiskiem. Nie publikuj tam danych, których nie '
                'chcesz pokazać obcym: numerów telefonu, adresów, danych '
                'pracodawcy ani dokumentów.',
            en: 'Every user of the app can see your messages together with your '
                'first and last name. Do not post anything you would not show a '
                'stranger: phone numbers, addresses, employer data or documents.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Zgłoszenia i blokady', en: 'Reports and blocks'),
          c.tr(
            pl: 'Gdy zgłosisz wiadomość, wysyłamy jej numer i Twój identyfikator '
                'instalacji — żeby ta sama osoba nie zgłaszała wielokrotnie. '
                'Blokowanie użytkownika jest wyłącznie lokalne: lista zostaje na '
                'Twoim telefonie, a zablokowana osoba nie dowiaduje się o tym.',
            en: 'When you report a message we send its id and your installation '
                'identifier, so one person cannot report the same message many '
                'times. Blocking a user is entirely local: the list stays on your '
                'phone and the blocked person is not notified.',
          ),
        ),
        LegalSection(
          c.tr(
              pl: 'Dane techniczne na serwerze',
              en: 'Technical data on the server'),
          c.tr(
            pl: 'Żeby chronić czat przed spamem i nadużyciami, serwer przetwarza '
                'adres IP połączenia. Nie zapisujemy go wprost — w bazie trafia '
                'tylko jego jednokierunkowy skrót (HMAC): w licznikach limitów '
                '(usuwane po 2 dobach) oraz przy zgłoszeniu wiadomości (żeby '
                'liczyć zgłoszenia z różnych sieci; usuwany razem ze '
                'zgłoszeniem). Aplikacja wysyła też losowy sekret instalacji — '
                'przechowujemy wyłącznie jego skrót, żeby nikt nie mógł podszyć '
                'się pod Twój identyfikator. Dostawca hostingu (Railway) może '
                'przez krótki czas przechowywać techniczne logi połączeń. '
                'Podstawa: prawnie uzasadniony interes — bezpieczeństwo usługi '
                '(art. 6 ust. 1 lit. f RODO).',
            en: 'To protect the chat against spam and abuse, the server '
                'processes the IP address of the connection. We never store it '
                'in plain form — only a one-way hash (HMAC) in rate-limit '
                'counters (deleted after 2 days) and with a message report (to '
                'count reports from different networks; deleted with the '
                'report). The app also sends a random installation secret; we '
                'store only its hash, so nobody can impersonate your '
                'identifier. Our hosting provider (Railway) may keep technical '
                'connection logs for a short time. Legal basis: legitimate '
                'interest in service security (Art. 6(1)(f) GDPR).',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Kto przetwarza dane', en: 'Who processes the data'),
          c.tr(
            pl: 'Serwer czatu działa na infrastrukturze Railway. Nie sprzedajemy '
                'ani nie udostępniamy danych nikomu innemu. Nie używamy reklam, '
                'analityki, pikseli śledzących ani zewnętrznych SDK marketingowych.',
            en: 'The chat server runs on Railway infrastructure. We do not sell or '
                'share your data with anyone else. We use no ads, no analytics, no '
                'tracking pixels and no third-party marketing SDKs.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Jak długo przechowujemy wiadomości', en: 'How long we keep messages'),
          c.tr(
            pl: 'Wiadomości czatu przechowujemy tak długo, jak istnieje pokój, w '
                'którym je napisano, chyba że wcześniej usunie je moderacja albo '
                'Ty je usuniesz (niżej).',
            en: 'Chat messages are kept for as long as the room exists, unless '
                'they are removed earlier by moderation or by you (below).',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Jak usunąć swoje dane', en: 'How to delete your data'),
          c.tr(
            pl: 'W aplikacji: Profil → „Usuń moje dane". Najpierw usuwamy z '
                'serwera wszystkie Twoje wiadomości z czatu (podpis i treść), '
                'zgłoszenia, które złożyłeś, i zgłoszenia Twoich wiadomości, '
                'ogłoszenia, identyfikator i sekret instalacji oraz liczniki '
                'limitów. Potem z telefonu: imię i nazwisko, zgodę na zasady, '
                'listę zablokowanych i tożsamość spawacza. Aplikacja pokazuje, '
                'co usunęła na serwerze, a co na telefonie. Jeśli serwer jest '
                'niedostępny albo jeszcze nie obsługuje tej funkcji, powie Ci o '
                'tym.\n\n'
                'Mailowo (bez aplikacji lub w starszej wersji): napisz na '
                '${AppLinks.supportEmail}, podaj imię i nazwisko, którym '
                'podpisywałeś wiadomości, oraz przybliżone daty. Usuniemy dane '
                'z serwera najpóźniej w ciągu 30 dni i potwierdzimy to '
                'odpowiedzią.\n\n'
                'Projekty, cut listy i dziennik spoin są tylko na Twoim '
                'telefonie — usuniesz je, odinstalowując aplikację.',
            en: 'In the app: Profile → "Delete my data". First we delete from '
                'the server all your chat messages (name and text), reports you '
                'made and reports of your messages, your job listings, your '
                'installation identifier and secret and rate-limit counters. '
                'Then from the phone: your name, your consent, your block list '
                'and your welder identity. The app shows what it deleted on the '
                'server and what on the phone. If the server is unreachable or '
                'does not support this yet, the app tells you.\n\n'
                'By e-mail (without the app or with an older version): write to '
                '${AppLinks.supportEmail} with the name you signed your messages '
                'with and approximate dates. We delete your data from the '
                'server within 30 days at the latest and confirm by reply.\n\n'
                'Projects, cut lists and the weld journal exist only on your '
                'phone — uninstalling the app removes them.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Twoje prawa (RODO)', en: 'Your rights (GDPR)'),
          c.tr(
            pl: 'Masz prawo dostępu do swoich danych, ich sprostowania, usunięcia, '
                'ograniczenia przetwarzania i wniesienia sprzeciwu. Wystarczy '
                'napisać na ${AppLinks.supportEmail}. Odpowiadamy najpóźniej w '
                'ciągu 30 dni. Masz też prawo skargi do Prezesa Urzędu Ochrony '
                'Danych Osobowych.',
            en: 'You have the right to access, rectify, delete, restrict and object '
                'to the processing of your data. Write to ${AppLinks.supportEmail}. '
                'We answer within 30 days at the latest. You may also lodge a '
                'complaint with your data protection authority.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Płatności i funkcje AI', en: 'Payments and AI features'),
          c.tr(
            pl: 'Płatności (Stripe), asystent AI oraz skaner rysunków są w tej '
                'wersji WYŁĄCZONE i nie wysyłają żadnych danych. Jeśli je '
                'kiedyś włączymy, zaktualizujemy tę politykę i poprosimy Cię o '
                'ponowną akceptację, zanim z nich skorzystasz.',
            en: 'Payments (Stripe), the AI assistant and the drawing scanner are '
                'DISABLED in this version and send no data. If we ever enable them '
                'we will update this policy and ask you to accept it again before '
                'you use them.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Kontakt', en: 'Contact'),
          c.tr(
            pl: 'Administrator danych: autor aplikacji Fitter Welder Pro. '
                'Kontakt we wszystkich sprawach: ${AppLinks.supportEmail}.',
            en: 'Data controller: the author of Fitter Welder Pro. Contact for any '
                'matter: ${AppLinks.supportEmail}.',
          ),
        ),
      ],
    );

// ─────────────────────────────────────────────────────────────────────────────
// REGULAMIN
// ─────────────────────────────────────────────────────────────────────────────
LegalDocument termsOfUse(BuildContext c) => LegalDocument(
      title: c.tr(pl: 'Regulamin', en: 'Terms of Use'),
      intro: c.tr(
        pl: 'Aplikacja liczy i podpowiada. Odpowiedzialność za spoinę, cięcie i '
            'montaż zawsze zostaje po stronie człowieka, który je wykonuje.',
        en: 'The app calculates and suggests. Responsibility for the weld, the cut '
            'and the assembly always stays with the person doing the work.',
      ),
      sections: [
        LegalSection(
          c.tr(pl: 'Wyniki sprawdzaj z WPS i normą', en: 'Verify results against your WPS and the standard'),
          c.tr(
            pl: 'Kalkulatory są pomocą, nie dokumentem. Zanim utniesz rurę albo '
                'zajarzysz łuk, porównaj wynik z obowiązującą u Ciebie '
                'instrukcją technologiczną (WPS) i normą. Autor nie odpowiada za '
                'szkody wynikłe z użycia wyników bez weryfikacji.',
            en: 'The calculators are an aid, not a document. Before you cut a pipe '
                'or strike an arc, check the result against your welding procedure '
                'specification (WPS) and the applicable standard. The author is not '
                'liable for damage caused by using results without verification.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Wiek', en: 'Age'),
          c.tr(
            pl: 'Z aplikacji mogą korzystać osoby, które ukończyły $kMinimumAge lat. '
                'Czat jest publiczny i nie jest moderowany całodobowo.',
            en: 'You must be at least $kMinimumAge years old to use the app. The chat '
                'is public and is not moderated around the clock.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Zero tolerancji dla treści obraźliwych', en: 'Zero tolerance for objectionable content'),
          c.tr(
            pl: 'Nie ma zgody na wyzwiska, groźby, nękanie, treści seksualne, '
                'rasistowskie i dyskryminujące, spam ani reklamę. Nie publikuj '
                'cudzych danych osobowych. Treści łamiące te zasady usuwamy, a '
                'ich autorom odbieramy dostęp — bez ostrzeżenia i bez zwrotu '
                'jakichkolwiek opłat.',
            en: 'No insults, threats, harassment, sexual, racist or discriminatory '
                'content, spam or advertising. Do not post other people\'s personal '
                'data. Content breaking these rules is removed and its authors lose '
                'access — without warning and without any refund.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Zgłaszanie i blokowanie', en: 'Reporting and blocking'),
          c.tr(
            pl: 'Przytrzymaj wiadomość, żeby ją zgłosić lub zablokować jej autora. '
                'Zgłoszenia rozpatrujemy w ciągu 24 godzin i usuwamy treści, które '
                'łamią regulamin. Blokada działa natychmiast i tylko dla Ciebie — '
                'nie czekasz na naszą decyzję.',
            en: 'Long-press a message to report it or block its author. We review '
                'reports within 24 hours and remove content that breaks these terms. '
                'A block takes effect immediately and only for you — you do not wait '
                'for our decision.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Piszesz pod własnym nazwiskiem', en: 'You post under your own name'),
          c.tr(
            pl: 'Wiadomości podpisywane są imieniem i nazwiskiem z Twojego profilu. '
                'Nie ma anonimowych ksywek. Podszywanie się pod inną osobę jest '
                'zabronione.',
            en: 'Messages are signed with the first and last name from your profile. '
                'There are no anonymous nicknames. Impersonating another person is '
                'forbidden.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Dostępność usługi', en: 'Service availability'),
          c.tr(
            pl: 'Kalkulatory i projekty działają bez Internetu. Czat wymaga '
                'połączenia i może być niedostępny. Aplikacja jest dostarczana '
                '„tak jak jest", bez gwarancji ciągłości działania czatu.',
            en: 'Calculators and projects work without the Internet. Chat requires a '
                'connection and may be unavailable. The app is provided "as is", '
                'with no guarantee of uninterrupted chat availability.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Usunięcie danych', en: 'Deleting your data'),
          c.tr(
            pl: '„Usuń moje dane" w profilu usuwa Twoje dane z serwera (wiadomości '
                'z czatu, zgłoszenia, ogłoszenia, identyfikator i sekret '
                'instalacji), a potem z telefonu. Bez aplikacji albo w starszej '
                'wersji napisz na ${AppLinks.supportEmail}. Pozostałe dane '
                'lokalne usuniesz, odinstalowując aplikację.',
            en: '"Delete my data" in your profile deletes your data from the '
                'server (chat messages, reports, job listings, installation '
                'identifier and secret) and then from the phone. Without the '
                'app or with an older version, write to '
                '${AppLinks.supportEmail}. Other local data is removed when you '
                'uninstall the app.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Zmiany regulaminu', en: 'Changes to these terms'),
          c.tr(
            pl: 'Gdy zmienimy zasady w sposób istotny, poprosimy Cię o ponowną '
                'akceptację przy najbliższym wejściu na czat. Kalkulatory i '
                'projekty działają bez niej.',
            en: 'When we change these rules materially, we will ask you to accept '
                'them again the next time you open the chat. Calculators and '
                'projects work without it.',
          ),
        ),
      ],
    );
