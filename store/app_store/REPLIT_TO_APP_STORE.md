# Replit To App Store - Practical Workflow

Jesli chcesz wykorzystac Replit przy publikacji `Cut List App`, to sensowny podzial pracy jest taki:

## Co robisz w Replit

1. Trzymasz publiczna polityke prywatnosci.
2. Trzymasz strone supportu lub landing page.
3. Przechowujesz gotowe teksty metadata App Store.
4. Ewentualnie robisz web preview dokumentow release.

## Czego Replit nie zrobi

1. Nie podpisze iOS builda certyfikatem Apple.
2. Nie zrobi finalnego archiwum Xcode do App Store Connect.
3. Nie wysle aplikacji do App Store bez srodowiska Apple.

## Minimalna sciezka publikacji

1. Na Replit wystaw `privacy-policy.html` jako publiczny URL.
2. Skopiuj ten URL do App Store Connect.
3. Na Macu skopiuj `ios/fastlane/.env.appstore.example` do lokalnego `.env` Fastlane i uzupelnij klucz App Store Connect.
4. Na Macu sprawdz signing i bundle ID.
5. Zrob archive w Xcode.
6. Wyslij build do App Store Connect.

## Najprostsza opcja z Replit dla tej aplikacji

Jesli chcesz uzyc Replit tylko jako hostingu dokumentow, wrzuc tam:

- `privacy-policy.html`
- ewentualna strone `support.html`
- skopiowane teksty z `APP_STORE_METADATA_PL_EN.md`

## Suggested Replit file layout

```text
/
  index.html
  privacy-policy.html
  support.html
```

## Example support page content

Moze zawierac:

- nazwe aplikacji,
- adres kontaktowy,
- krotki opis zastosowania,
- link do polityki prywatnosci.

## Final note

Replit jest tutaj dodatkiem do hostingu i organizacji plikow. Finalna publikacja iOS nadal wymaga macOS + Xcode lub Transporter.
