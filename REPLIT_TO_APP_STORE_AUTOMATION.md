# Replit -> App Store Automation

To repo przygotowuje automatyczny upload iOS do App Store Connect, ale nie przez bezposredni build na Replit. Dziala to tak:

1. Edytujesz projekt na Replit.
2. Replit synchronizuje lub pushuje zmiany do GitHub.
3. GitHub Actions uruchamia macOS runner.
4. macOS runner buduje `.ipa` i wysyla build do TestFlight/App Store Connect.

## Pliki przygotowane pod ten flow

- `.github/workflows/ios-app-store.yml`
- `ios/Gemfile`
- `ios/fastlane/Appfile`
- `ios/fastlane/Fastfile`
- `ios/Runner/PrivacyInfo.xcprivacy`
- `ios/Flutter/AppStore.xcconfig.example`

## Sekrety GitHub, ktore musisz ustawic

- `APP_BUNDLE_IDENTIFIER`
- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_APPLE_ID`
- `APP_STORE_CONNECT_TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `BUILD_PROVISION_PROFILE_BASE64`
- `KEYCHAIN_PASSWORD`

## Skad wziac te rzeczy

- `APP_BUNDLE_IDENTIFIER`: twoje finalne bundle id z App Store Connect
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APP_STORE_CONNECT_*`: klucz API z App Store Connect
- `BUILD_CERTIFICATE_BASE64`: certyfikat dystrybucyjny `.p12` zakodowany base64
- `BUILD_PROVISION_PROFILE_BASE64`: provisioning profile `.mobileprovision` zakodowany base64

## Jak zakodowac pliki do base64 na Windows PowerShell

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\sciezka\cert.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\sciezka\profile.mobileprovision"))
```

## Co jeszcze musisz uzupelnic recznie

1. Ustaw finalne `APP_BUNDLE_IDENTIFIER`.
2. Dodaj certyfikat i provisioning profile do sekretow GitHub.
3. Podlacz repo z Replit do GitHub.
4. Uruchom workflow `iOS App Store Upload` recznie albo przez push na `main`.

## Ograniczenie

Sam Replit nie podpisze i nie wysle iOS builda do App Store. Ten zestaw plikow robi to przez GitHub Actions na macOS, co jest realna i dzialajaca alternatywa.