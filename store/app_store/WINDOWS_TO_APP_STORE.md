# Windows To App Store

Jesli nie masz Maca, nie zrobisz lokalnie poprawnego builda iOS/App Store na Windows. Dla tego projektu sensowna sciezka to GitHub Actions z runnerem `macos-latest`.

## Ważne

Ten projekt jest aplikacja Flutter, a nie Expo / React Native.

To oznacza:

- nie uzywa `eas.json`,
- nie wymaga `eas build:configure`,
- nie powinien byc budowany przez Expo EAS.

Jesli widzisz blad typu `Failed to read "/eas.json"`, to uruchamiasz niewlasciwe narzedzie lub niewlasciwy workflow dla tego repo.

Repo ma juz gotowy workflow:

- `.github/workflows/ios-app-store.yml`

## Co potrzebujesz

1. Repo na GitHub.
2. Konto Apple Developer z dostepem do aplikacji.
3. Sekrety GitHub ustawione w repo.

## Wymagane GitHub Secrets

- `APP_BUNDLE_IDENTIFIER` = `com.jakatora.fitterwelderpro`
- `APPLE_TEAM_ID` = `B7J6A7R258`
- `APP_STORE_APP_ID` = `6761770166`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `BUILD_PROVISION_PROFILE_BASE64`
- `KEYCHAIN_PASSWORD`

Opcjonalne:

- `APP_STORE_CONNECT_APPLE_ID`
- `APP_STORE_CONNECT_TEAM_ID`

## Jak ustawic sekrety na GitHub

1. Otworz repo na GitHub.
2. Wejdz w `Settings` -> `Secrets and variables` -> `Actions`.
3. Dodaj wszystkie sekrety z listy wyzej.

## Jak przygotowac wartosci binarne

### `BUILD_CERTIFICATE_BASE64`

To jest Twoj certyfikat dystrybucyjny `.p12` zakodowany do base64.

Jesli masz plik `.p12`, zakoduj go poleceniem:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\sciezka\do\certyfikat.p12"))
```

### `BUILD_PROVISION_PROFILE_BASE64`

To jest provisioning profile `.mobileprovision` zakodowany do base64.

Zakoduj go poleceniem:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\sciezka\do\profil.mobileprovision"))
```

## Jak uruchomic build z Windows

1. Zacommituj i wypchnij zmiany do GitHub.
2. Otworz repo na GitHub.
3. Wejdz w `Actions`.
4. Wybierz workflow `iOS App Store Upload`.
5. Kliknij `Run workflow`.

Workflow zrobi:

1. checkout kodu,
2. przygotowanie Flutter,
3. instalacje certyfikatu i provisioning profile,
4. `bundle install`,
5. `bundle exec fastlane ios release`,
6. upload builda do TestFlight,
7. zapis `.ipa` jako artifact workflow.

## Gdzie znajdziesz artefakt

Po zakonczonym workflow wejdz w dany run i pobierz artifact `cut-list-app-ipa`.

## Najczestsze blokery

1. Zly `APP_STORE_CONNECT_PRIVATE_KEY`.
2. Certyfikat `.p12` nie pasuje do provisioning profile.
3. Bundle ID w provisioning profile nie zgadza sie z `com.jakatora.fitterwelderpro`.
4. Konto Apple nie ma uprawnien do uploadu builda.

## Najwazniejsze ograniczenie

Windows moze tylko uruchomic zdalny build na macOS runnerze. Sam lokalny build iOS/App Store na Windows nie jest wspierany przez Apple ani Flutter.
