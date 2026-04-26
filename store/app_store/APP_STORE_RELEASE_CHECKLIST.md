# App Store Release Checklist - Cut List App

Wersja: `0.1.4+6`

## 1. Branding i dane wydawcy

- [ ] Ustal finalna nazwe wydawcy
- [x] Bundle ID ustawiony: `com.jakatora.fitterwelderpro`
- [x] Apple Team ID ustawiony: `B7J6A7R258`
- [ ] Potwierdz App Store app ID: `6761770166`
- [ ] Ustaw support URL
- [ ] Ustaw privacy policy URL
- [ ] Zweryfikuj nazwe aplikacji w metadanych i w polityce prywatnosci

## 2. Projekt iOS

- [ ] Uzupelnij `ios/Flutter/AppStore.xcconfig` (`APP_BUNDLE_IDENTIFIER`, `APPLE_TEAM_ID`)
- [ ] Otworz `ios/Runner.xcworkspace` i sprawdz Automatic Signing w Xcode
- [ ] Zweryfikuj `CFBundleDisplayName`
- [ ] Zbuduj aplikacje na realnym iPhonie lub symulatorze
- [ ] Przejdz podstawowy smoke test na iOS

## 3. Materialy App Store Connect

- [ ] Wklej tytul, subtitle, keywords i description z pakietu metadata
- [ ] Dodaj support URL
- [ ] Dodaj privacy policy URL
- [ ] Dodaj review contact
- [ ] Dodaj review notes
- [ ] Uzupelnij App Privacy zgodnie z `APP_STORE_PRIVACY_AND_REVIEW.md`
- [ ] W `App Information` uzupelnij `Content Rights`
- [ ] W `Pricing and Availability` wybierz `Price Tier`
- [ ] W `App Privacy` dodaj publiczny `Privacy Policy URL`
- [ ] Wybierz build w sekcji `Build` dla wersji aplikacji

## 4. Screenshoty

- [ ] iPhone 6.7 inch screenshots
- [ ] iPhone 6.5 inch screenshots lub aktualny zestaw wymagany przez App Store Connect
- [ ] iPad screenshots tylko jesli build wspiera iPad i chcesz publikowac jako universal w praktyce

## 5. Build i upload

- [ ] Na macOS uruchom `flutter build ios --release --no-codesign`
- [ ] Otworz `ios/Runner.xcworkspace` w Xcode
- [ ] Archive -> Validate App
- [ ] Archive -> Distribute App -> App Store Connect
- [ ] Alternatywnie uruchom fastlane: `bundle exec fastlane ios release`
- [ ] Zweryfikuj build processing w App Store Connect

## 6. Replit

- [ ] Wystaw publicznie `privacy-policy.html`
- [ ] Skopiuj publiczny URL do App Store Connect
- [ ] Jesli chcesz, wystaw tez support page

## 7. Blokery wykryte teraz

- [ ] `ios/Flutter/AppStore.xcconfig` wymaga uzupelnienia finalnym bundle ID i Apple Team ID
- [ ] Nie ma jeszcze gotowego publicznego URL polityki prywatnosci
- [ ] Finalny upload do App Store nie moze byc wykonany z samego Windows/Replit
