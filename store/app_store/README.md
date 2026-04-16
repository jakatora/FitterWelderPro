# App Store Package

Ten folder zawiera gotowy pakiet plikow do publikacji `Cut List App` w Apple App Store.

## Co jest tutaj

- `APP_STORE_METADATA_PL_EN.md` - gotowe teksty do App Store Connect (PL/EN)
- `APP_STORE_PRIVACY_AND_REVIEW.md` - odpowiedzi do sekcji App Privacy i Review Notes
- `APP_STORE_RELEASE_CHECKLIST.md` - checklista od przygotowania builda do wysylki
- `REPLIT_TO_APP_STORE.md` - jak wykorzystac Replit do hostingu polityki prywatnosci i przygotowania materialow
- `ExportOptions-AppStore.plist` - szablon eksportu archiwum iOS do App Store
- `SUPPORT_PAGE_TEMPLATE.html` - gotowa strona support URL pod App Store Connect

## Ważne ograniczenie

Replit moze posluzyc do:

- hostingu publicznej polityki prywatnosci,
- przechowywania metadanych i materialow release,
- przygotowania landing page lub support page.

Replit nie zastapi finalnego kroku publikacji iOS. Wysylka do App Store wymaga macOS oraz Xcode lub aplikacji Transporter od Apple.

## Najpierw uzupelnij

1. `ios/Flutter/AppStore.xcconfig` i `ios/fastlane/.env.appstore.example` - projekt jest przygotowany pod bundle ID `com.jakatora.fitterwelderpro`, Team ID `B7J6A7R258` i App Store app ID `6761770166`.
2. Dane wydawcy: nazwa podmiotu, e-mail supportu, URL supportu, URL privacy policy.
3. Screenshoty iPhone/iPad oraz finalna ikona, jesli chcesz podmienic obecna.
