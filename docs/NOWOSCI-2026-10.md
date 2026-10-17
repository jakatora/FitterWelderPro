# Nowości — gałąź `feat/wyceny-i-moduly` (2026-10-16/17)

Gałąź wychodzi z `fix/audyt-2026-08-29` (c701680) i jest **tylko lokalnie** —
nic nie wypchnięte, nic nie wydane. Wszystkie nowe moduły działają offline,
**bez zmian w backendzie**.

## Nowe narzędzia

| Narzędzie | Gdzie w menu | Co rozwiązuje |
|---|---|---|
| Wyceny spawalnicze | ekran główny (kafel WYCENY), Spawacz → Wyceny i koszty | koszt roboty z geometrii spoin: robocizna, spoiwo, gaz, prąd, NDT, narzut, zysk, VAT; oferta PDF dla klienta i kosztorys wewnętrzny; lista zakupów |
| Ile brać za godzinę | Spawacz → Wyceny i koszty | minimalna stawka z kosztów firmy, podatku i godzin fakturowanych |
| Dobór spoiwa | Spawacz → Parametry spawania | spoiwo EN ISO + AWS, gaz, formowanie; połączenia różnoimienne (309L itd.) |
| Obróbka cieplna po spawaniu | Spawacz → Kalkulatory | plan PWHT wg ASME B31.3 (2020/2024) i B31.1-2022, wykres cyklu, PDF |
| Odbiór spoin ISO 5817 | Spawacz → Kontrola i dokumentacja | limity B/C/D niezgodności VT i ocena pomiaru |
| Symbole spawalnicze | Spawacz → Kontrola i dokumentacja | czytnik symbolu z rysunku (ISO 2553 / AWS A2.4), a↔z |
| Postęp robót | Spawacz → Kontrola i dokumentacja; dziennik spoin → Więcej | DI dziennie, spawacze, odsetek napraw, prognoza końca, raport |
| Przyrządy i kalibracja | Spawacz → Kontrola i dokumentacja | terminy kalibracji/walidacji, przypomnienia, rejestr PDF/CSV |
| Segmentowe kolana | Monter → Kolana i kształtki | kolano z segmentów rury: kąt cięcia, długości, szablon 1:1 |
| Ciężar stali — profile | Monter → Tabele i przeliczniki | IPE/HEA/HEB/UPN, kątowniki, profile zamknięte, blachy; lista i koszt |
| Czas stygnięcia t8/5 | Spawacz → Kalkulatory | EN 1011-2 zał. D: t8/5 z Q, T0 i grubości (2D/3D), okno stali, odwrotnie: zakres Q dla okna |
| Prace pożarowo niebezpieczne | Spawacz → Kontrola i dokumentacja | checklista stanowiska (rozp. MSWiA § 36, BHP spawalnicze), pomiar % DGW (próg 0–10 %), dozór, protokół PDF; „jak wczoraj” |
| Elektrody zasadowe: czas i suszenie | Spawacz → Kontrola i dokumentacja | limit na powietrzu wg AWS D1.1 Tab. 7.1, piecyk, ponowne suszenie, przypomnienia, dziennik QC (PDF) |
| Odbiór połączenia kołnierzowego | Monter → Podpory i kołnierze | osiowość, równoległość, otwory i szczelina wg ASME PCC-1 zał. E, lista montażu, protokół PDF |
| Warunki do spawania | Spawacz → Kontrola i dokumentacja | mróz, wiatr (AWS D1.1: 8 km/h dla metod gazowych), opad, punkt rosy i szronu; werdykt, warunki do odhaczenia, historia, PDF |
| Rozwinięcie stożka i przejść | Monter → Kolana i kształtki | stożek ścięty, mimośrodowy, kwadrat–koło: wymiary do trasowania, podział na części, tabela rzędnych, szablon 1:1 A4/A3 |
| Słownik spawalniczy | Monter → Tabele i przeliczniki | PL · EN · DE · NL · NO offline: 246 terminów (procesy ISO 4063, niezgodności ISO 6520-1, złącza, pozycje, rury, BHP) + 58 zwrotów na budowę; tryb „pokaż rozmówcy” |
| Nośność spoiny pachwinowej | Spawacz → Kalkulatory | EN 1993-1-8 (metoda uproszczona i kierunkowa): nośność, wykorzystanie %, wymagane a (w górę), spoina obwodowa rury; szacunek, nie projekt |
| Twardość: przelicznik i limity | Spawacz → Kontrola i dokumentacja | HV/HB/HRC/HRB wg ISO 18265 tab. A.1 (bez ekstrapolacji), seria pomiarów vs limit: NACE MR0175/ISO 15156-2 (250 HV / 22 HRC), EN ISO 15614-1, ASME B31.3-2008…2012, własny |

Plus: karta „Nowe w aplikacji” na ekranie głównym, kategoria „Wyceny i koszty”
w Pomocy, poprawiony wpis pomocy o PWHT P91 (wg B31.3 2014+), polskie nazwy
niezgodności w odbiorze ISO 5817 wg PN-EN ISO 6520-1 (509 „zwis”, nie „wyciek”).

Rozszerzenia istniejących ekranów:

- **Wycena → Zakres → Importuj spoiny** — pozycje wyceny z zapisanego skanu
  izometryku, z dziennika spoin albo z projektu CUT (lista cięć: spoina na
  każdym końcu odcinka przy kształtce, podziały sztangi; typ kołnierzy
  i zaworów wybierany w podglądzie). Grupowanie po rodzaju, wymiarze
  i pozycji; spoiny bez wymiaru albo niepewne trafiają do „do sprawdzenia”
  z powodem, nie są zgadywane.
- **Próba ciśnieniowa → manometr z rejestru przyrządów** — numer i termin
  kalibracji wpisują się z rejestru; przyrządy po terminie są oznaczone
  w wyborze.
- **Gaz, formowanie i timer → „Na ile starczy tej butli?”** — z pojemności
  wodnej, ciśnienia na manometrze i przepływu: litry, minuty łuku, liczba
  spoin (rezerwa ciśnienia i pre/post-flow uwzględnione).

## Baza danych

- **v26** — `weld_quotes` (wyceny; kwoty w groszach, treść w JSON).
- **v27** — `instruments` (rejestr przyrządów).

Obie tabele nowe i puste; migracja niczego nie rusza; obie w kopii zapasowej.
Test migracji (`test/database/migration_test.dart`) pilnuje kształtu.

## Testy

Pełny zestaw po scaleniu wszystkich modułów i poprawek z przeglądów:
**3637 zielonych** (przed falą: 2751). Każdy moduł z werdyktem
(prace pożarowe, t8/5, elektrody, kołnierze, warunki do spawania, stożek)
przeszedł niezależny przegląd kodu; znalezione błędy poprawiono z testami
regresji (m.in. werdykt zależny od przełącznika jednostek, ostatnio dopisany
zamiast najpóźniejszego pomiaru DGW, „ożywianie” przekroczonej partii
elektrod).
`flutter analyze` — 0 problemów. Moduły z normami (PWHT, ISO 5817, dobór
spoiwa, ciężar stali) mają w kodzie komentarze ze źródłem każdej liczby;
wartości z norm sprawdzano na tekstach norm z nieoficjalnych kopii — przed
wydaniem warto porównać z licencjonowanym egzemplarzem (PWHT, ISO 5817).

## Do zrobienia przy wydaniu (ręcznie)

1. Zdecydować o numerze wersji (`pubspec.yaml`: dziś `0.3.0+17`, a 0.3.0
   z poprzedniej fali też czeka na wydanie — można wydać razem jako 0.4.0+18).
2. Scalić `feat/wyceny-i-moduly` do gałęzi wydania i wypchnąć; potem kroki
   z `docs/RELEASE-0.3.0.md` (backend, AAB, Codemagic).
3. Zrzuty ekranu sklepu — nowe ekrany: Wyceny (zakładka Wynik), Dobór
   spoiwa, Kolano segmentowe, Odbiór ISO 5817.

## Tekst „Co nowego” do sklepów

**Google Play, PL (limit 500 znaków, bez emoji):**

Wyceny spawalnicze z ofertą PDF i ile brać za godzinę. Nowe narzędzia: dobór
spoiwa, plan PWHT, odbiór spoin ISO 5817, symbole spawalnicze, czas stygnięcia
t8/5, nośność spoiny pachwinowej, twardość HV/HB/HRC z limitami NACE,
elektrody zasadowe (czas i suszenie), warunki do spawania, prace pożarowe,
odbiór kołnierzy PCC-1, rozwinięcie stożka z szablonem 1:1, słownik
spawalniczy PL/EN/DE/NL/NO i więcej. Działa bez internetu.

**Google Play, EN:**

Welding quotes with a PDF offer and an hourly rate calculator. New tools:
filler selector, PWHT plan, ISO 5817 acceptance, welding symbols, t8/5 cooling
time, fillet weld resistance, HV/HB/HRC hardness with NACE limits,
low-hydrogen electrode exposure, welding weather check, hot work permit,
PCC-1 flange joint check, cone layout with a 1:1 template, and a PL/EN/DE/NL/NO
welding dictionary. Works offline.

**App Store, PL (bez emoji; bullet dozwolony):**

Wyceny spawalnicze: policz koszt roboty z wymiarów spoin — robocizna, spoiwo,
gaz, prąd, badania NDT, narzut, zysk i VAT — i wyślij klientowi ofertę PDF.

Nowe narzędzia:
• Ile brać za godzinę
• Dobór spoiwa (EN ISO i AWS) i plan PWHT wg ASME B31.3
• Odbiór spoin wg ISO 5817 i czytnik symboli spawalniczych
• Czas stygnięcia t8/5 (EN 1011-2) i nośność spoiny pachwinowej (EN 1993-1-8)
• Twardość: przelicznik HV/HB/HRC/HRB i limity NACE MR0175, ISO 15614-1
• Elektrody zasadowe: czas na powietrzu, suszenie i przypomnienia
• Warunki do spawania: mróz, wiatr, opad, punkt rosy
• Prace pożarowo niebezpieczne: checklista, pomiar DGW, protokół PDF
• Odbiór połączenia kołnierzowego wg ASME PCC-1
• Rozwinięcie stożka i przejścia kwadrat–koło z szablonem 1:1
• Kolano segmentowe, ciężar profili stalowych, postęp robót
• Rejestr przyrządów i kalibracji
• Słownik spawalniczy PL, EN, DE, NL, NO ze zwrotami na budowę

Wszystko działa bez internetu.

**App Store, EN:**

Welding quotes: work out the job cost from the weld sizes — labour, filler,
gas, power, NDT, overhead, profit and VAT — and send the client a PDF quote.

New tools:
• Hourly rate calculator
• Filler metal selector (EN ISO and AWS) and PWHT plan per ASME B31.3
• ISO 5817 weld acceptance and welding symbol reader
• t8/5 cooling time (EN 1011-2) and fillet weld resistance (EN 1993-1-8)
• Hardness: HV/HB/HRC/HRB converter with NACE MR0175 and ISO 15614-1 limits
• Low-hydrogen electrodes: exposure time, re-drying and reminders
• Welding conditions: frost, wind, rain, dew point
• Hot work permit: checklist, gas test, PDF record
• Flange joint check per ASME PCC-1
• Cone and square-to-round layout with a 1:1 template
• Mitred bends, steel section weights, work progress
• Instrument and calibration register
• Welding dictionary in PL, EN, DE, NL, NO with site phrases

Everything works offline.
