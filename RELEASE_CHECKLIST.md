# Release Checklist (Play + Windows)

Wersja: `0.1.2+3`
Data: `2026-03-28`

## 1) Stan techniczny

- [x] `flutter analyze` -> brak bledow
- [x] Build Android AAB (`flutter build appbundle --release`)
- [x] Build Windows Release (`flutter build windows --release`)

## 2) Artefakty

- [x] Android AAB gotowy: `build/app/outputs/bundle/release/app-release.aab`
- [x] Windows EXE gotowy: `build/windows/x64/runner/Release/cut_list_app.exe`
- [x] Do dystrybucji Windows: caly folder `build/windows/x64/runner/Release/`

## 3) Play Console (manual)

- [ ] Utworz nowy release na torze Production
- [ ] Wgraj `app-release.aab`
- [ ] Uzupelnij release notes (PL/EN)
- [ ] Sprawdz: Data safety
- [ ] Sprawdz: Content rating
- [ ] Sprawdz: Target audience
- [ ] Sprawdz: Permissions i deklaracje
- [ ] Zweryfikuj link do polityki prywatnosci
- [ ] Zatwierdz rollout (najlepiej etapowo)

## 4) Testy przed publikacja

- [ ] Szybki smoke test Android (nawigacja, zapisy, kalkulatory)
- [ ] Szybki smoke test Windows (start app, baza SQLite, glowny flow)
- [ ] Kontrola kluczowych ekranow po ostatnich zmianach (jezyk EN/PL, welder pipes)

## 5) Po publikacji

- [ ] Monitoruj crashe/ANR
- [ ] Monitoruj opinie i bledy z produkcji
- [ ] Zaplanuj kolejny bump wersji w `pubspec.yaml`
