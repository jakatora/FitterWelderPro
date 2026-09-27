# Deklaracje prywatności w sklepach — co wpisać

Stan na 2026-09-25 (polityka `kLegalVersion = 3`). Dane na serwer wysyłają:
**publiczny czat**, **skaner ISO** (darmowy z dziennym limitem,
`kAiScannerFreeTier = true`) i **asystent AI** (tryb „Odpowiedz” i polecenia,
których telefon sam nie rozpozna). Płatności nadal wyłączone
(`kPaidFeaturesEnabled = false`). Sekcja „Kiedy deklaracje trzeba rozszerzyć”
z wersji 2026-09-24 jest dla skanera i asystenta już **aktualna** — niżej
wpisane w tabele.

Dziś obie karty sklepowe mówią „nie zbieramy danych” — to nieprawda od wersji
0.2.0 (czat wysyła imię i nazwisko). Poprawić **przed** wysłaniem kolejnej wersji
do recenzji.

## Co naprawdę opuszcza telefon (sprawdzone w kodzie)

| Dane | Kiedy | Dokąd | Po co |
|---|---|---|---|
| Imię i nazwisko z profilu | przy każdej wiadomości czatu | backend Fittera (Railway) | podpis wiadomości |
| Treść wiadomości | przy wysłaniu | backend Fittera | czat publiczny |
| Identyfikator instalacji (losowy, generowany w apce; nie IMEI, nie ID reklamowe) | przy czacie i zgłoszeniu | backend Fittera | własne wiadomości, blokady, zgłoszenia |
| Zgłoszenie wiadomości | gdy użytkownik zgłasza | backend Fittera | moderacja |
| Zdjęcie rysunku izometrycznego (zmniejszone do 2576 px) + identyfikator i sekret instalacji | po zgodzie w oknie skanera, przy każdym skanie | backend Fittera → **Anthropic** (tylko obraz) | odczyt wymiarów i elementów |
| Treść pytania do asystenta, kilka ostatnich wiadomości rozmowy, język + identyfikator i sekret | tryb „Odpowiedz” i polecenia nierozpoznane na telefonie | backend Fittera → **Anthropic** (tylko tekst) | odpowiedź asystenta |

Serwer **nie zapisuje** zdjęć, pytań ani odpowiedzi (sprawdzone w
`backend/src/routes/fitterScan.js`, `services/fitterScan.js`,
`routes/fitterAi.js`: obraz tylko w pamięci, w logach rozmiar i typ; w bazie
`ai_usage` tylko model, tokeny i koszt — bez treści i bez identyfikatora; w
`rate_counter` skróty HMAC identyfikatora i IP, usuwane po 2 dobach).
Anthropic przechowuje dane z API przez ograniczony czas wg swojej polityki (nie
trenuje na nich) — dlatego to **nie** jest przetwarzanie „ulotne” (ephemeral)
w rozumieniu sklepów i trzeba je zadeklarować.

Mowa: mikrofon tylko po naciśnięciu; rozpoznawanie mowy robi system telefonu
(Google na Androidzie, Apple na iOS). Aplikacja nie odczytuje ani nie wysyła
nagrania — do naszego serwera trafia wyłącznie rozpoznany tekst.

Nic więcej: projekty, dziennik spoin, zdjęcia wytopów, parametry — tylko lokalnie.
Brak analityki, reklam, śledzenia i raportów awarii.

Od wersji z zabezpieczonym backendem (polityka `kLegalVersion = 2`) dochodzą
dane techniczne, nadal tylko po zgodzie na czat:

- **sekret instalacji** (losowy, generowany w aplikacji, wysyłany razem z
  identyfikatorem instalacji) — potwierdza, że wiadomość pisze to samo
  urządzenie; w deklaracjach mieści się w *User ID* / *Device or other IDs*;
- **skróty adresów IP** (nie surowe IP) do limitów nadużyć — cel
  *Fraud prevention / security*; nie łączone z profilem.
Rejestracja urządzenia na serwerze następuje dopiero po zgodzie na czat.

## App Store Connect → App Privacy

- **Do you or your third-party partners collect data from this app?** → **Yes**
- Typy danych do zaznaczenia:

| Kategoria Apple | Typ | Linked to user | Used for tracking | Purpose |
|---|---|---|---|---|
| Contact Info | **Name** | Yes | No | App Functionality |
| User Content | **Other User Content** (wiadomości czatu) | Yes | No | App Functionality |
| Identifiers | **User ID** (identyfikator instalacji pełni rolę ID konta czatu) | Yes | No | App Functionality |
| User Content | **Photos or Videos** (zdjęcie rysunku do skanera) | No (do Anthropic idzie sam obraz, serwer nic nie zapisuje) | No | App Functionality |

- **Other User Content** obejmuje też pytania do asystenta (tekst idzie do
  Anthropic). Typ już jest zaznaczony dla czatu jako *Linked* — Apple łączy
  cele i powiązanie per typ danych, więc zostaje *Linked: Yes*, cel App
  Functionality.
- Anthropic (podmiot przetwarzający, API) to w pytaniu Apple „you and/or your
  third-party partners” zewnętrzny partner — deklarujemy dane, które do niego
  trafiają (wyżej); osobnego pola na nazwę partnera nie ma.
- **Audio Data — nie zaznaczać** (rekomendacja, decyzja właściciela niżej):
  aplikacja nie ma dostępu do nagrania i go nie wysyła; mowę przetwarza
  framework Apple (Speech) na zasadach Apple, który nie jest „third-party
  partnerem” aplikacji. Zgody systemowe mikrofonu i rozpoznawania mowy (Info.plist
  `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) muszą
  mówić, po co są. Jeśli asystent wymusi rozpoznawanie wyłącznie na urządzeniu
  (`requiresOnDeviceRecognition` / `onDevice: true`), temat znika całkiem.
- Niczego więcej nie zaznaczać (brak Diagnostics, Usage Data, Location, Device ID reklamowego).
- **Privacy Policy URL**: publiczny adres (patrz „URL-e” niżej).

## Google Play Console → Data safety

- **Does your app collect or share any of the required user data types?** → **Yes**
- **Is all of the user data collected by your app encrypted in transit?** → **Yes** (HTTPS)
- **Do you provide a way for users to request that their data is deleted?** → **Yes**
  (w aplikacji: Profil → „Usuń moje dane”; URL strony usuwania danych — niżej)

| Kategoria Google | Typ | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|---|
| Personal info | **Name** | Yes | No | Optional (tylko przy pisaniu na czacie) | App functionality |
| Messages | **Other in-app messages** | Yes | No | Optional | App functionality |
| Device or other IDs | **Device or other IDs** | Yes | No | Optional | App functionality, Fraud prevention/security (blokady, zgłoszenia, limity skanera i asystenta) |
| Photos and videos | **Photos** (zdjęcie rysunku do skanera) | Yes | No | Optional (tylko przy skanie) | App functionality |
| App activity | **Other user-generated content** (pytania do asystenta) | Yes | No | Optional (tylko tryb „Odpowiedz” / nierozpoznane polecenia) | App functionality |

„Shared = No”: dane trafiają na własny serwer, a dalej tylko do dostawców
usług przetwarzających je na nasze zlecenie — Railway (hosting) i **Anthropic**
(model Claude, umowa powierzenia / DPA). Google wprost wyłącza takie przekazanie
z „udostępniania” (*service provider*). Wcześniejsza notatka „Anthropic →
Shared” była zbyt ostrożna; jeśli właściciel woli ostrożniej, zaznaczyć
*Shared: Yes* dla Photos i Other user-generated content — to niczego nie psuje.

- **Audio — nie zaznaczać** (rekomendacja): aplikacja używa systemowego
  rozpoznawania mowy (`SpeechRecognizer` / usługa Google) i nie dostaje ani nie
  wysyła nagrania — dostaje tylko tekst. Dźwięk przetwarza system na zasadach
  Google. Aplikacja musi za to mieć uprawnienie `RECORD_AUDIO` z opisem w
  polityce (jest: sekcja „Asystent AI”).

## Manifesty w repo (2026-09-26)

- `ios/Runner/PrivacyInfo.xcprivacy` odpowiada tabeli App Privacy wyżej:
  Name, Other User Content, User ID (Linked), Photos or Videos (Not linked),
  wszystkie bez śledzenia, cel App Functionality. Required Reason API:
  UserDefaults `CA92.1` (shared_preferences) i File Timestamp `C617.1`
  (SQLite z `sqlite3_flutter_libs` bez własnego manifestu, `dart:io` w
  kontenerze aplikacji). Pilnuje `test/store/privacy_manifests_test.dart`.
- Android: `android:allowBackup="true"` z regułami (`res/xml/backup_rules.xml`,
  `res/xml/data_extraction_rules.xml`) — z kopii Google wypada plik
  SharedPreferences (identyfikator i sekret instalacji, imię, zgody), zostają
  projekty, dziennik i zdjęcia. Opis w polityce („Co zostaje na Twoim
  telefonie”). Data safety: kopia systemowa to kopia użytkownika, nie
  „zbieranie” przez aplikację.

## URL-e wymagane przez sklepy

- Polityka prywatności i strona usuwania danych — po wdrożeniu nowego backendu
  będą pod `https://fitter-welder-pro-backend-production.up.railway.app/privacy`
  i `/data-deletion` (już wpisane w `lib/config/app_links.dart`). Przed
  wydaniem sprawdzić, że odpowiadają 200, i wpisać je w obu konsolach.
  Źródłem tekstu jest teraz backend (`backend/src/routes/publicPages.js`) i
  `lib/legal/legal_texts.dart`; `privacy-policy.html` w repo jest nieaktualny.
- „Usuń moje dane” w aplikacji woła `DELETE /api/fitter/me` (czat, zgłoszenia,
  ogłoszenia, sekret) i dopiero potem czyści telefon — to jest ścieżka
  usunięcia danych wymagana przez Google Play.
- Alternatywa: GitHub Pages z `privacy-policy.html` (wymaga działającego pusha).

## Kiedy deklaracje trzeba rozszerzyć

- ~~Skaner ISO~~ i ~~asystent AI~~ — wpisane wyżej (2026-09-25).
- **Asystent wysyłający nagranie** (np. własne STT na serwerze zamiast
  systemowego): wtedy *Audio Data* (Apple) / *Voice or sound recordings*
  (Google) — Collected, cel App functionality, i poprawka polityki
  (`kLegalVersion` + 1).
- **Płatności**: *Purchase History*; przy IAP dane płatnicze obsługuje sklep.
- **Raporty awarii / statystyki** (Crashlytics, Firebase Analytics): *Crash Data*,
  *Performance Data*, *Product Interaction*; wcześniej poprawić politykę w
  `lib/legal/legal_texts.dart` i podnieść `kLegalVersion`.

## Decyzje dla właściciela

1. **Audio Data / Audio**: rekomendacja „nie deklarować” (powyżej). Ostrożna
   alternatywa: zadeklarować *Audio Data* (Apple, Not linked, App Functionality)
   i *Voice or sound recordings* (Google, Optional). Rozstrzyga ostatecznie
   sposób rozpoznawania mowy w asystencie (systemowy / na urządzeniu).
2. **Shared (Google) dla Anthropic**: rekomendacja „No” (service provider),
   alternatywa „Yes”.
3. Potwierdzić, że konto Anthropic (API) ma zaakceptowane warunki komercyjne z
   DPA i standardowymi klauzulami umownymi — polityka to deklaruje.

## Opis w App Store (What's New / Description)

Usunąć zdania „Works fully offline” i „No subscriptions/no data collected”.
Poprawna wersja: „Kalkulatory, projekty i dziennik spoin działają bez Internetu.
Internet jest potrzebny do czatu, skanera rysunków i odpowiedzi asystenta.”
