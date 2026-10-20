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
//
// Wersja 3 (2026-09-25): skaner rysunków (darmowy, z dziennym limitem) i
// asystent AI (tryby „Wykonaj" / „Odpowiedz", mowa rozpoznawana przez system
// telefonu). Anthropic (Claude) jako podmiot przetwarzający. Treść zgodna z
// `backend/src/routes/publicPages.js` z 2026-09-25.
//
// Wersja 3, poprawki 2026-09-26 (bez ponownej akceptacji — doprecyzowania,
// nie nowe przetwarzanie): imię i nazwisko nie są już na liście „nie
// opuszczają telefonu" (czat je wysyła); opis kopii zapasowej Androida
// (manifest wyklucza z niej SharedPreferences z tożsamością instalacji);
// „Usuń moje dane" kasuje też zgodę skanera i historię asystenta; regulamin
// bez obietnic moderacji, których backend nie realizuje („24 godziny",
// „odbieramy dostęp") — jest ukrywanie po 3 zgłoszeniach, kolejka moderacji
// i usuwanie wiadomości autora. Wersję hostowaną (publicPages.js) trzeba
// zsynchronizować po stronie backendu.

/// Podniesienie tej liczby wymusza ponowną akceptację u wszystkich użytkowników.
/// Blokuje to czat (community_gate.dart) i skaner (scan_consent_gate.dart) —
/// kalkulatory działają dalej.
const int kLegalVersion = 4;

const String kLegalUpdated = '2026-10-20';

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
            'serwer wysyłamy dane, gdy założysz konto, zgodzisz się na zgłoszenia, napiszesz na publicznym '
            'czacie, zadasz pytanie asystentowi AI albo zeskanujesz rysunek — '
            'pytania i zdjęcia rysunków przekazujemy do Anthropic (model '
            'Claude) i ich nie zapisujemy. Nie ma reklam, analityki ani '
            'śledzenia.',
        en: 'In short: calculators and projects stay on your phone. We send data '
            'to a server when you create an account, consent to reports, post in the public chat, ask the AI '
            'assistant or scan a drawing — questions and drawing photos are '
            'passed to Anthropic (Claude model) and we do not store them. No '
            'ads, no analytics, no tracking.',
      ),
      sections: [
        LegalSection(
            c.tr(
                pl: 'Konto i profil zawodowy',
                en: 'Account and professional profile'),
            c.tr(
                pl: 'Dobrowolne konto zapisujemy na serwerze Railway: e-mail, bezpieczny skrót hasła, imię i nazwisko, zawód, procesy spawania, staż, kwalifikacje i stempel. Sesja wygasa po 30 dniach; token przechowujemy w bezpiecznym magazynie telefonu. E-mail pozostaje prywatny. Nazwa konta podpisuje wiadomości na czacie. Dane zawodowe są prywatne, dopóki nie włączysz ich widoczności. Konto i jego wiadomości usuniesz w Profil → Konto po potwierdzeniu hasłem. Kopie bezpieczeństwa mogą zachować dane do 30 dni. Kalkulatory nie wymagają konta. Raporty błędów są dostępne wyłącznie administratorowi; ich wysyłka wymaga osobnej zgody, bez nagrań głosu. Dane konta przechowujemy do jego usunięcia.',
                en: 'Optional accounts are stored on Railway: email, a secure password hash, display name, profession, welding processes, experience, qualifications and stamp. Sessions expire after 30 days; the token is kept in secure phone storage. Email remains private. The account name signs chat messages. Professional information stays private until you enable visibility. Delete the account and its messages under Profile → Account by confirming your password. Backups may retain data for up to 30 days. Calculators do not require an account. Error reports are available only to the administrator; uploading requires separate consent and never includes voice recordings. Account data is retained until deletion.')),
        LegalSection(
          c.tr(
              pl: 'Co zostaje na Twoim telefonie',
              en: 'What stays on your phone'),
          c.tr(
            pl: 'Projekty, cut listy, dziennik spoin, zdjęcia numerów wytopu, '
                'parametry spawania, wyniki kalkulatorów, historia asystenta i '
                'Twoja lista zablokowanych osób zostają na telefonie — nie '
                'wysyłamy ich na nasz serwer. Imię i nazwisko z profilu też '
                'zapisujemy tylko na telefonie, ale gdy piszesz na czacie, '
                'wysyłamy je jako podpis Twoich wiadomości na czacie (niżej).\n\n'
                'Kopia zapasowa. Dane aplikacji znikają z telefonu razem z jej '
                'odinstalowaniem. Jeśli masz włączoną kopię zapasową Androida '
                '(Google), system może zapisać projekty, dziennik spoin i '
                'zdjęcia na Twoim koncie Google i odtworzyć je na nowym '
                'telefonie — to Twoja kopia, nie mamy do niej dostępu. Imienia '
                'i nazwiska, zgód, identyfikatora ani sekretu instalacji '
                'aplikacja do tej kopii nie oddaje: na nowym telefonie zapyta '
                'o nie od nowa. Na iPhonie dane aplikacji może obejmować kopia '
                'iCloud albo kopia na komputerze, jeśli ją włączyłeś. Plik z '
                'kopią (ZIP) możesz też zrobić sam: Profil → „Kopia zapasowa".',
            en: 'Projects, cut lists, weld journal, heat-number photos, welding '
                'parameters, calculator results, the assistant history and your '
                'block list stay on your phone — we do not send them to our '
                'server. The name in your profile is also stored only on the '
                'phone, but when you post in chat we send it as the signature '
                'of your chat messages (below).\n\n'
                'Backups. The app data is removed from the phone when you '
                'uninstall the app. If Android backup (Google) is on, the '
                'system may save projects, the weld journal and photos to your '
                'Google account and restore them on a new phone — that is your '
                'backup and we have no access to it. The app does not put your '
                'name, consents, installation identifier or secret into that '
                'backup: on a new phone it asks for them again. On an iPhone '
                'the app data may be included in an iCloud or computer backup '
                'if you turned it on. You can also make a backup file (ZIP) '
                'yourself: Profile → "Back up my data".',
          ),
        ),
        LegalSection(
          c.tr(
              pl: 'Co wysyłamy, gdy piszesz na czacie',
              en: 'What we send when you post in chat'),
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
                'Aplikacja przedstawia się serwerowi (identyfikator i sekret '
                'instalacji) dopiero wtedy, gdy sam użyjesz funkcji, która go '
                'wymaga: wejdziesz na czat po zaakceptowaniu tych zasad, '
                'zeskanujesz rysunek po zgodzie w oknie skanera albo zadasz '
                'asystentowi pytanie, na które telefon sam nie odpowie — a przy '
                'czacie także przy kolejnych uruchomieniach. Wcześniej nic nie '
                'wysyła.',
            en: 'Calculators, projects and the weld journal work without the '
                'server. The app introduces itself to the server (installation '
                'identifier and secret) only when you use a feature that needs '
                'it: you open the chat after accepting these rules, scan a '
                'drawing after agreeing in the scanner, or ask the assistant '
                'something the phone cannot answer by itself — and, for the '
                'chat, on later launches. Before that it sends nothing.',
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
            pl: 'Żeby chronić czat i funkcje AI przed spamem i nadużyciami, '
                'serwer przetwarza adres IP połączenia. Nie zapisujemy go '
                'wprost — w bazie trafia tylko jego jednokierunkowy skrót '
                '(HMAC): w licznikach limitów '
                '(usuwane po 2 dobach) oraz przy zgłoszeniu wiadomości (żeby '
                'liczyć zgłoszenia z różnych sieci; usuwany razem ze '
                'zgłoszeniem). Aplikacja wysyła też losowy sekret instalacji — '
                'przechowujemy wyłącznie jego skrót, żeby nikt nie mógł podszyć '
                'się pod Twój identyfikator. Dostawca hostingu (Railway) może '
                'przez krótki czas przechowywać techniczne logi połączeń. '
                'Podstawa: prawnie uzasadniony interes — bezpieczeństwo usługi '
                '(art. 6 ust. 1 lit. f RODO).',
            en: 'To protect the chat and the AI features against spam and '
                'abuse, the server processes the IP address of the connection. '
                'We never store it in plain form — only a one-way hash (HMAC) '
                'in rate-limit '
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
            pl: 'Serwer działa na infrastrukturze Railway. Treść pytań do '
                'asystenta AI, polecenia wysłane na serwer (po rozpoznaniu mowy '
                'na tekst) oraz zdjęcia skanowanych rysunków przetwarza w naszym '
                'imieniu Anthropic PBC (USA) — dostawca modelu Claude — wyłącznie '
                'po to, żeby przygotować odpowiedź. Przekazanie poza EOG odbywa '
                'się na podstawie standardowych klauzul umownych z umowy '
                'powierzenia Anthropic. Dane przesyłane przez API nie służą do '
                'trenowania modeli; Anthropic przechowuje je przez ograniczony '
                'czas na zasadach swojej polityki prywatności. Nie sprzedajemy '
                'ani nie udostępniamy danych nikomu innemu. Nie używamy reklam, '
                'analityki, pikseli śledzących ani zewnętrznych SDK '
                'marketingowych.',
            en: 'The server runs on Railway infrastructure. Questions to the AI '
                'assistant, commands sent to the server (after speech-to-text) '
                'and photos of scanned drawings are processed on our behalf by '
                'Anthropic PBC (USA) — the provider of the Claude model — only '
                'to prepare the answer. Transfers outside the EEA rely on the '
                'standard contractual clauses in Anthropic\'s data processing '
                'agreement. Data sent through the API is not used to train '
                'models; Anthropic keeps it for a limited time under its privacy '
                'policy. We do not sell or share your data with anyone else. We '
                'use no ads, no analytics, no tracking pixels and no third-party '
                'marketing SDKs.',
          ),
        ),
        LegalSection(
          c.tr(
              pl: 'Jak długo przechowujemy wiadomości',
              en: 'How long we keep messages'),
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
                'zgodę na wysyłkę zdjęć do skanera, historię asystenta, listę '
                'zablokowanych i tożsamość spawacza. Aplikacja pokazuje, '
                'co usunęła na serwerze, a co na telefonie. Jeśli serwer jest '
                'niedostępny albo jeszcze nie obsługuje tej funkcji, powie Ci o '
                'tym.\n\n'
                'Mailowo (bez aplikacji lub w starszej wersji): napisz na '
                '${AppLinks.supportEmail}, podaj imię i nazwisko, którym '
                'podpisywałeś wiadomości, oraz przybliżone daty. Usuniemy dane '
                'z serwera najpóźniej w ciągu 30 dni i potwierdzimy to '
                'odpowiedzią.\n\n'
                'Projekty, cut listy i dziennik spoin są tylko na Twoim '
                'telefonie — usuniesz je, odinstalowując aplikację (i z '
                'systemowej kopii zapasowej, jeśli ją masz).',
            en: 'In the app: Profile → "Delete my data". First we delete from '
                'the server all your chat messages (name and text), reports you '
                'made and reports of your messages, your job listings, your '
                'installation identifier and secret and rate-limit counters. '
                'Then from the phone: your name, your consent to the rules, your '
                'consent to send photos to the scanner, the assistant history, '
                'your block list and your welder identity. The app shows what '
                'it deleted on the '
                'server and what on the phone. If the server is unreachable or '
                'does not support this yet, the app tells you.\n\n'
                'By e-mail (without the app or with an older version): write to '
                '${AppLinks.supportEmail} with the name you signed your messages '
                'with and approximate dates. We delete your data from the '
                'server within 30 days at the latest and confirm by reply.\n\n'
                'Projects, cut lists and the weld journal exist only on your '
                'phone — uninstalling the app removes them (and deleting the '
                'system backup, if you have one).',
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
          c.tr(pl: 'Asystent AI', en: 'AI assistant'),
          c.tr(
            pl: 'Asystent ma dwa tryby. „Wykonaj" rozpoznaje polecenia na '
                'telefonie (np. „otwórz kalkulator", „zapisz parametry '
                'spawania") — takie polecenie nie opuszcza urządzenia, a każdy '
                'zapis danych pokazuje podsumowanie do potwierdzenia. '
                '„Odpowiedz" oraz polecenia, których telefon sam nie rozpozna, '
                'wysyłają na nasz serwer treść pytania, kilka ostatnich '
                'wiadomości z bieżącej rozmowy (kontekst), wybrany język oraz '
                'identyfikator i sekret instalacji; serwer przekazuje treść do '
                'Anthropic (model Claude) i odsyła odpowiedź. Nie zapisujemy '
                'treści pytań, poleceń ani odpowiedzi — zostają tylko liczniki '
                'dziennych limitów (skróty HMAC, usuwane po 2 dobach) i zbiorczy '
                'koszt wywołań (bez treści i bez identyfikatora). Nie wpisuj w '
                'pytaniach danych osobowych.\n\n'
                'Mowa: mikrofon włącza się tylko po naciśnięciu przycisku '
                'mikrofonu. Mowę na tekst zamienia system telefonu (Google na '
                'Androidzie, Apple na iPhonie), który może w tym celu przesyłać '
                'dźwięk do swoich usług — na zasadach ich polityk prywatności. '
                'Nagranie nie trafia na nasz serwer; do nas trafia wyłącznie '
                'rozpoznany tekst i tylko w przypadkach opisanych wyżej.\n\n'
                'Odpowiedzi asystenta mogą zawierać błędy — wiążące są WPS i '
                'specyfikacja projektu. Podstawa: wykonanie usługi, o którą '
                'prosisz (art. 6 ust. 1 lit. b RODO).',
            en: 'The assistant has two modes. "Do" recognises commands on the '
                'phone (e.g. "open the calculator", "save welding parameters") '
                '— such a command never leaves the device, and every data '
                'change shows a summary to confirm. "Answer", and commands the '
                'phone cannot recognise by itself, send to our server the '
                'question, a few recent messages of the current conversation '
                '(context), the chosen language and the installation identifier '
                'and secret; the server passes the text to Anthropic (Claude '
                'model) and returns the answer. We do not store questions, '
                'commands or answers — only daily-limit counters (HMAC hashes, '
                'deleted after 2 days) and the total cost of calls (without '
                'content or identifier) remain. Do not put personal data in '
                'your questions.\n\n'
                'Speech: the microphone turns on only when you press the '
                'microphone button. Speech is turned into text by the phone\'s '
                'system (Google on Android, Apple on iPhone), which may send the '
                'audio to its own services for that — under their privacy '
                'policies. The recording never reaches our server; we receive '
                'only the recognised text, and only in the cases above.\n\n'
                'The assistant\'s answers can be wrong — your WPS and the project '
                'specification are binding. Legal basis: performing the service '
                'you ask for (Art. 6(1)(b) GDPR).',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Skaner rysunków', en: 'Drawing scanner'),
          c.tr(
            pl: 'Gdy skanujesz rysunek izometryczny (po zgodzie w oknie '
                'skanera), aplikacja wysyła na nasz serwer zdjęcie rysunku '
                'oraz identyfikator i sekret instalacji. Serwer przekazuje '
                'zdjęcie do Anthropic (model Claude), który odczytuje wymiary i '
                'elementy, a wynik wraca do aplikacji. Serwer nie zapisuje '
                'zdjęcia ani wyniku — obraz jest przetwarzany tylko w pamięci '
                'na czas analizy. Zostają wyłącznie liczniki limitów (skróty '
                'HMAC identyfikatora i adresu IP, usuwane po 2 dobach) i koszt '
                'wywołania. Skaner jest darmowy i ma dzienny limit skanów na '
                'telefon i na sieć. Nie fotografuj twarzy ani dokumentów z '
                'danymi osobowymi. Podstawa: art. 6 ust. 1 lit. b RODO.',
            en: 'When you scan an isometric drawing (after agreeing in the '
                'scanner), the app sends the photo of the drawing and the '
                'installation identifier and secret to our server. The server '
                'passes the photo to Anthropic (Claude model), which reads the '
                'dimensions and components, and the result goes back to the '
                'app. The server does not store the photo or the result — the '
                'image is processed in memory only for the analysis. Only limit '
                'counters (HMAC hashes of the identifier and the IP address, '
                'deleted after 2 days) and the cost of the call remain. The '
                'scanner is free with a daily limit of scans per phone and per '
                'network. Do not photograph faces or documents with personal '
                'data. Legal basis: Art. 6(1)(b) GDPR.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Płatności', en: 'Payments'),
          c.tr(
            pl: 'Płatności (Stripe) są w tej wersji WYŁĄCZONE i nie wysyłają '
                'żadnych danych. Jeśli je włączymy, zaktualizujemy tę politykę '
                'i poprosimy Cię o ponowną akceptację.',
            en: 'Payments (Stripe) are DISABLED in this version and send no '
                'data. If we enable them we will update this policy and ask you '
                'to accept it again.',
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
          c.tr(
              pl: 'Wyniki sprawdzaj z WPS i normą',
              en: 'Verify results against your WPS and the standard'),
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
          c.tr(pl: 'Skaner i asystent AI', en: 'Scanner and AI assistant'),
          c.tr(
            pl: 'Odczyt rysunku przez skaner i odpowiedzi asystenta przygotowuje '
                'model AI — mogą zawierać błędy. Wynik skanu sprawdź z '
                'rysunkiem: niepewne wartości są oznaczone i nie staną się '
                'długością cięcia bez Twojego potwierdzenia. Skaner jest darmowy '
                'z dziennym limitem; limit i dostępność funkcji AI mogą się '
                'zmienić, a gdy wyczerpie się miesięczny budżet AI, skaner i '
                'asystent mogą być chwilowo niedostępne.',
            en: 'The scanner\'s reading of a drawing and the assistant\'s '
                'answers are prepared by an AI model — they can be wrong. Check '
                'a scan against the drawing: uncertain values are flagged and '
                'never become a cut length without your confirmation. The '
                'scanner is free with a daily limit; the limit and the '
                'availability of AI features may change, and when the monthly '
                'AI budget runs out the scanner and the assistant may be '
                'temporarily unavailable.',
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
          c.tr(
              pl: 'Zero tolerancji dla treści obraźliwych',
              en: 'Zero tolerance for objectionable content'),
          c.tr(
            pl: 'Nie ma zgody na wyzwiska, groźby, nękanie, treści seksualne, '
                'rasistowskie i dyskryminujące, spam ani reklamę. Nie publikuj '
                'cudzych danych osobowych. Treści łamiące te zasady ukrywamy '
                'lub usuwamy bez ostrzeżenia, a przy poważnych naruszeniach '
                'możemy usunąć z serwera wszystkie wiadomości ich autora.',
            en: 'No insults, threats, harassment, sexual, racist or discriminatory '
                'content, spam or advertising. Do not post other people\'s personal '
                'data. Content breaking these rules is hidden or removed without '
                'warning, and for serious violations we may delete all of its '
                'author\'s messages from the server.',
          ),
        ),
        LegalSection(
          c.tr(pl: 'Zgłaszanie i blokowanie', en: 'Reporting and blocking'),
          c.tr(
            pl: 'Stuknij ⋮ przy wiadomości (albo ją przytrzymaj), żeby ją '
                'zgłosić lub zablokować jej autora. Zgłoszona wiadomość od razu '
                'znika u Ciebie, a po 3 zgłoszeniach od różnych osób — '
                'automatycznie u wszystkich. Zgłoszenia trafiają do kolejki '
                'moderacji; treści, które łamią regulamin, ukrywamy lub '
                'usuwamy. Czat nie jest moderowany całodobowo. Blokada działa '
                'natychmiast i tylko dla Ciebie — nie czekasz na naszą decyzję.',
            en: 'Tap ⋮ next to a message (or long-press it) to report it or '
                'block its author. A reported message disappears for you right '
                'away, and after 3 reports from different people it is hidden '
                'for everyone automatically. Reports go to a moderation queue; '
                'content that breaks these terms is hidden or removed. The chat '
                'is not moderated around the clock. A block takes effect '
                'immediately and only for you — you do not wait for our '
                'decision.',
          ),
        ),
        LegalSection(
          c.tr(
              pl: 'Piszesz pod własnym nazwiskiem',
              en: 'You post under your own name'),
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
            pl: 'Kalkulatory i projekty działają bez Internetu. Czat, skaner '
                'rysunków i odpowiedzi asystenta wymagają połączenia i mogą być '
                'niedostępne. Aplikacja jest dostarczana „tak jak jest", bez '
                'gwarancji ciągłości działania tych funkcji.',
            en: 'Calculators and projects work without the Internet. Chat, the '
                'drawing scanner and assistant answers require a connection and '
                'may be unavailable. The app is provided "as is", with no '
                'guarantee of uninterrupted availability of these features.',
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
                'akceptację przy najbliższym wejściu na czat albo skanie '
                'rysunku. Kalkulatory i projekty działają bez niej.',
            en: 'When we change these rules materially, we will ask you to accept '
                'them again the next time you open the chat or scan a drawing. '
                'Calculators and projects work without it.',
          ),
        ),
      ],
    );
