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

Plus: karta „Nowe w aplikacji” na ekranie głównym, kategoria „Wyceny i koszty”
w Pomocy, poprawiony wpis pomocy o PWHT P91 (wg B31.3 2014+).

Rozszerzenia istniejących ekranów:

- **Wycena → Zakres → Importuj spoiny** — pozycje wyceny z zapisanego skanu
  izometryku albo z dziennika spoin (grupowanie po rodzaju, wymiarze
  i pozycji; spoiny bez wymiaru pomijane z powodem, nie zgadywane).
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

Pełny zestaw po scaleniu modułów: **3012 zielonych** (przed falą: 2751).
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

**PL (Google Play / App Store — bez emoji):**

Wyceny spawalnicze: policz koszt roboty z wymiarów spoin — robocizna, spoiwo,
gaz, prąd, badania NDT, narzut, zysk i VAT — i wyślij klientowi ofertę PDF.
Nowe narzędzia: ile brać za godzinę, dobór spoiwa (EN ISO i AWS), plan PWHT
wg ASME B31.3, odbiór spoin wg ISO 5817, czytnik symboli spawalniczych,
postęp robót z dziennika spoin, rejestr przyrządów i kalibracji, kolano
segmentowe z szablonem 1:1 oraz ciężar profili stalowych. Wszystko działa
bez internetu.

**EN:**

Welding quotes: work out the job cost from the weld sizes — labour, filler,
gas, power, NDT, overhead, profit and VAT — and send the client a PDF quote.
New tools: hourly rate calculator, filler metal selector (EN ISO and AWS),
PWHT plan per ASME B31.3, ISO 5817 weld acceptance, welding symbol reader,
work progress from the weld journal, instrument and calibration register,
mitred bend with a 1:1 template, and steel section weights. Everything works
offline.
