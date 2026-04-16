# App Store Privacy And Review - Suggested Answers

Ten plik zawiera gotowe odpowiedzi pomocnicze do App Store Connect. Przed wysylka sprawdz je jeszcze raz pod finalna konfiguracje aplikacji.

## 1. App Privacy

Zakladam aktualny stan projektu:

- aplikacja przechowuje dane lokalnie na urzadzeniu,
- nie ma logowania kont,
- nie ma reklam,
- nie ma trackingu reklamowego,
- nie ma zewnetrznej analityki marketingowej,
- nie udostepnia danych brokerom danych.

### Tracking

- Does this app track users? `No`

### Data linked to the user

- `None`, o ile nie dodasz logowania, analityki, crash reporting z identyfikatorem uzytkownika albo sync do chmury.

### Data not linked to the user

- `User Content` tylko wtedy, jezeli uznasz, ze App Store Connect wymaga zadeklarowania danych wpisywanych przez uzytkownika, mimo ze zostaja lokalnie na urzadzeniu.
- W praktyce dla tej aplikacji najbezpieczniej przyjac: brak zbierania danych przez wydawce, bo dane nie sa wysylane poza urzadzenie w standardowym scenariuszu.

### Purchase data

- `No`

### Contact info

- `No`

### Identifiers

- `No`

### Usage data

- `No`

### Diagnostics

- `No`, jezeli nie dodasz crash analytics.

## 2. Content Rights

Suggested answer: `Yes, I own or have licensed all rights necessary for the app content and branding.`

## 3. Export Compliance

Suggested answer dla standardowej aplikacji Flutter bez custom crypto:

- `No`, the app does not use proprietary or specially controlled encryption beyond standard Apple/OS-provided encryption.

Jesli dodasz niestandardowe szyfrowanie albo biblioteki security wykraczajace poza standard platformy, trzeba to zaktualizowac.

## 4. Review Notes

Wklej do sekcji `Notes for Review`:

`Cut List App is a productivity tool for creating local pipe cut lists and related workshop data. The app works without user registration and stores project data locally on the device. No paid content, account login, or hidden functionality is required for review.`

## 5. Demo Account

- `Not required`

## 6. Support Answer If Apple Asks About Data

Suggested answer:

`The app stores user-entered project data locally on the device using on-device storage. In the current release, the app does not require sign-in, does not use advertising SDKs, and does not transmit user data to our servers as part of its standard workflow.`

## 7. Important project-specific blocker

Przed wysylka sprawdz finalna konfiguracje iOS:

- bundle ID w projekcie: `com.jakatora.fitterwelderpro`
- Apple Team ID: `B7J6A7R258`
- App Store app ID: `6761770166`

Na Macu nadal musisz miec poprawne provisioning profiles / Automatic Signing oraz klucz App Store Connect do uploadu.
