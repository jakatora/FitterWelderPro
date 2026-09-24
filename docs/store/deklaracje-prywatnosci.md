# Deklaracje prywatności w sklepach — co wpisać

Stan na 2026-09-24. Dotyczy wersji, w której **skaner ISO i czat AI są ukryte**
(`kAiScannerReachable = false`, `kPaidFeaturesEnabled = false`). Jedyna funkcja
wysyłająca dane na serwer to **publiczny czat**. Po włączeniu skanera, czatu AI
albo płatności deklaracje trzeba rozszerzyć (sekcja na końcu).

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

Nic więcej: projekty, dziennik spoin, zdjęcia wytopów, parametry — tylko lokalnie.
Brak analityki, reklam, śledzenia i raportów awarii.

## App Store Connect → App Privacy

- **Do you or your third-party partners collect data from this app?** → **Yes**
- Typy danych do zaznaczenia:

| Kategoria Apple | Typ | Linked to user | Used for tracking | Purpose |
|---|---|---|---|---|
| Contact Info | **Name** | Yes | No | App Functionality |
| User Content | **Other User Content** (wiadomości czatu) | Yes | No | App Functionality |
| Identifiers | **User ID** (identyfikator instalacji pełni rolę ID konta czatu) | Yes | No | App Functionality |

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
| Device or other IDs | **Device or other IDs** | Yes | No | Optional | App functionality, Fraud prevention/security (blokady i zgłoszenia) |

„Shared = No”: dane trafiają tylko na własny serwer (Railway to dostawca usługi
przetwarzający na nasze zlecenie, nie „udostępnienie” w rozumieniu Google).

## URL-e wymagane przez sklepy

- Polityka prywatności i strona usuwania danych — po wdrożeniu nowego backendu
  będą pod `https://fitter-welder-pro-backend-production.up.railway.app/privacy`
  i `/data-deletion`. Po sprawdzeniu, że odpowiadają 200, wpisać je w
  `lib/config/app_links.dart` (`privacyPolicyUrl`, `dataDeletionUrl`) oraz w obu konsolach.
- Alternatywa: GitHub Pages z `privacy-policy.html` (wymaga działającego pusha).

## Kiedy deklaracje trzeba rozszerzyć

- **Skaner ISO**: zdjęcie rysunku → backend → Anthropic → dopisać *Photos* (User
  Content / Photos and videos), a Anthropic to **third-party partner** (Apple) /
  **Shared** (Google), cel: App functionality.
- **Czat AI**: treść pytań → Anthropic → *Other User Content* / *Other in-app
  messages* jako shared z Anthropic.
- **Płatności**: *Purchase History*; przy IAP dane płatnicze obsługuje sklep.
- **Raporty awarii / statystyki** (Crashlytics, Firebase Analytics): *Crash Data*,
  *Performance Data*, *Product Interaction*; wcześniej poprawić politykę w
  `lib/legal/legal_texts.dart` i podnieść `kLegalVersion`.

## Opis w App Store (What's New / Description)

Usunąć zdania „Works fully offline” i „No subscriptions/no data collected”.
Poprawna wersja: „Kalkulatory, projekty i dziennik spoin działają bez Internetu.
Internet jest potrzebny tylko do czatu.”
