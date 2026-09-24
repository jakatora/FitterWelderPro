# FitterWelder Pro 0.3.0 — What's New / informacje o wersji

Przygotowano 2026-09-24 · wersja `0.3.0+16` · bez emoji · wklejaj zawartość bloku kodu.

Gdzie wkleić:
- **App Store Connect** → wersja 0.3.0 → każda lokalizacja → „What's New in This Version” (limit 4000). Polski = sekcja PL; English (U.S.) i English (U.K.) = ta sama sekcja EN; German = sekcja DE. Apple wymaga tego pola w każdej lokalizacji przy aktualizacji.
- **Google Play Console** → wydanie → „Informacje o wersji” (limit **500 znaków na język**). Najprościej wkleić gotowy blok z tagami językowymi z końca pliku.

**WARUNEK — punkt o usuwaniu danych z serwera.** W aplikacji „Usuń moje dane” woła `DELETE /api/fitter/me`, ale na żywym backendzie tej trasy jeszcze nie ma (sprawdzone 2026-09-24: `/privacy` i `/data-deletion` zwracają 404, czyli nowy backend nie jest wdrożony). Aplikacja sama uczciwie mówi wtedy, że serwer nie obsługuje usuwania. Jeśli w dniu wydania nowy backend nadal nie działa, **usuń ten punkt** we wszystkich sekcjach (ostatni punkt w „Dokumenty i dane” oraz ostatni punkt w notatkach Google Play). Limity zostaną zachowane.

---

## App Store — What's New

### What's New (PL) — limit 4000 — 1559/4000 znaków

```text
Wersja 0.3.0: dokładniejsze obliczenia, lepsze dokumenty i kopia zapasowa.

OBLICZENIA
• Wymiary kształtek wg ASME B16.9, B16.5 i B16.10: poprawione m.in. trójnik DN100, zaślepki, kołnierze z szyjką (WN) i zawory zwrotne DN200–300.
• Kołnierz domyślnie wymiarowany do czoła uszczelnienia.
• Wstawka liczona z tabel ASME B16.9, rolling offset z kątem obrotu.
• Szczeliny spoin w długości cięcia liczone na obu końcach odcinka.
• Zmiana ustawień projektu od razu przelicza długości cięcia.
• Lista materiałowa nie liczy już trójnika podwójnie.
• Heat input osobno wg EN (z η) i ASME (bez η), podgrzewanie metodą Seferiana, poprawiona liczba butli gazu, P91 jako P-No. 15E.
• Moment śrub z przekroju czynnego gwintu wg ASME B1.1, także dla gwintów 8UN.
• Przebarwienia wg AWS D18.2.

PRÓBA CIŚNIENIOWA
• Ciśnienie próby wg B31.3 (z ST/S), B31.1, EN 13480 / PED i ASME VIII.
• Protokół PDF z polami do uzupełnienia na obiekcie.

DOKUMENTY I DANE
• PDF z polskimi znakami we wszystkich eksportach.
• Etykiety odcinków na sztangach, eksport CSV jako plik.
• Autozapis szkicu w zeszycie ISO i lista zapisanych szkiców.
• Kopia zapasowa projektów, dziennika spoin i zdjęć do jednego pliku, z przywracaniem także na innym telefonie.
• Usuwanie Twoich danych z serwera czatu: Twój profil > Usuń moje dane.

WYGODA
• Nowe menu pogrupowane tematycznie, z wyszukiwarką narzędzi, przypiętymi i ostatnio używanymi narzędziami.
• Aplikacja startuje od razu; imię i nazwisko podajesz dopiero przy wejściu na czat.
• Aplikacja pamięta wybrany język, a tekst ma lepszy kontrast.
```

### What's New (EN — English U.S. i English U.K.) — limit 4000 — 1561/4000 znaków

```text
Version 0.3.0: more accurate calculations, better documents and a one-file backup.

CALCULATIONS
• Fitting dimensions per ASME B16.9, B16.5 and B16.10, including corrected DN100 (4") tee, caps, weld neck flanges and DN200–300 check valves.
• Flanges are now dimensioned to the gasket face by default.
• Insert calculated from ASME B16.9 tables; rolling offset with roll angle.
• Weld gaps in a cut length are counted at both ends of the piece.
• Changing project settings recalculates cut lengths immediately.
• The bill of materials no longer counts a tee twice.
• Heat input per EN (with η) and ASME (without η), preheat by the Seferian method, corrected gas cylinder count, P91 listed as P-No. 15E.
• Bolt torque from the thread stress area per ASME B1.1, including 8UN threads.
• Heat tint per AWS D18.2.

PRESSURE TEST
• Test pressure per B31.3 (with ST/S), B31.1, EN 13480 / PED and ASME VIII.
• PDF test report with fields to fill in on site.

DOCUMENTS AND DATA
• PDF exports now show every character correctly, including Polish.
• Piece labels on stock lengths, CSV export as a file.
• ISO notebook sketches save automatically, with a list of saved sketches.
• One-file backup of projects, weld journal and photos, with restore on another phone.
• Delete your chat data from our server: Your profile > Delete my data.

EASIER TO USE
• New grouped menu with tool search, pinned tools and recently used tools.
• The app opens straight to the tools; your name is only needed when you join the chat.
• The app remembers your language; better text contrast.
```

### What's New (DE) — limit 4000 — 1762/4000 znaków

```text
Version 0.3.0: genauere Berechnungen, bessere Dokumente und Datensicherung.

BERECHNUNGEN
• Formstückmaße nach ASME B16.9, B16.5 und B16.10, unter anderem korrigiert: T-Stück DN100, Kappen, Vorschweißflansche (WN) und Rückschlagventile DN200–300.
• Flansche werden standardmäßig bis zur Dichtfläche bemaßt.
• Passstück aus den Tabellen ASME B16.9, Etage (Rolling Offset) mit Verdrehwinkel.
• Schweißspalte im Zuschnittmaß werden an beiden Enden des Teilstücks berücksichtigt.
• Änderungen an den Projekteinstellungen berechnen die Zuschnittmaße sofort neu.
• Die Materialliste zählt T-Stücke nicht mehr doppelt.
• Streckenenergie nach EN (mit η) und ASME (ohne η), Vorwärmen nach Seferian, korrigierte Anzahl der Gasflaschen, P91 als P-No. 15E.
• Anzugsmomente aus dem Spannungsquerschnitt nach ASME B1.1, auch für 8UN-Gewinde.
• Anlauffarben nach AWS D18.2.

DRUCKPRÜFUNG
• Prüfdruck nach B31.3 (mit ST/S), B31.1, EN 13480 / DGRL (PED) und ASME VIII.
• PDF-Protokoll mit Feldern zum Ausfüllen vor Ort.

DOKUMENTE UND DATEN
• PDF-Exporte zeigen alle Zeichen korrekt an, auch polnische.
• Beschriftete Teilstücke auf den Stangen, CSV-Export als Datei.
• ISO-Skizzen werden automatisch gespeichert, mit Liste der gespeicherten Skizzen.
• Datensicherung von Projekten, Schweißnahtbuch und Fotos in eine Datei, Wiederherstellung auch auf einem anderen Telefon.
• Chat-Daten auf unserem Server löschen: Your profile > Delete my data (die App ist auf Englisch oder Polnisch).

BEDIENUNG
• Neues, thematisch gegliedertes Menü mit Werkzeugsuche, angehefteten und zuletzt verwendeten Werkzeugen.
• Die App startet direkt mit den Werkzeugen; Vor- und Nachname brauchst du erst für den Chat.
• Die App merkt sich die Sprache (Polnisch oder Englisch); besserer Textkontrast.
```

---

## Google Play — informacje o wersji (limit 500 na język)

### Release notes (pl-PL) — limit 500 — 443/500 znaków

```text
• Wymiary kształtek wg ASME B16.9/B16.5/B16.10 i poprawione obliczenia: wstawka, szczeliny spoin, rolling offset z kątem obrotu, heat input EN/ASME, podgrzewanie, gaz, moment śrub.
• Próba ciśnieniowa wg B31.3, B31.1, EN 13480/PED, ASME VIII z protokołem PDF.
• PDF z polskimi znakami, autozapis szkicu ISO, kopia zapasowa danych.
• Nowe menu z wyszukiwarką i przypiętymi narzędziami.
• Usuwanie danych z serwera: Twój profil > Usuń moje dane.
```

### Release notes (en-US) — limit 500 — 423/500 znaków

```text
• Fitting dimensions per ASME B16.9/B16.5/B16.10 and corrected calculations: insert, weld gaps, rolling offset with roll angle, heat input EN/ASME, preheat, gas, bolt torque.
• Pressure test per B31.3, B31.1, EN 13480/PED, ASME VIII with a PDF report.
• Correct characters in PDFs, ISO sketch autosave, one-file backup.
• New menu with tool search and pinned tools.
• Delete your server data: Your profile > Delete my data.
```

### Release notes (de-DE) — limit 500 — 456/500 znaków

```text
• Formstückmaße nach ASME B16.9/B16.5/B16.10 und korrigierte Berechnungen: Passstück, Schweißspalte, Etage mit Verdrehwinkel, Streckenenergie EN/ASME, Vorwärmen, Gas, Anzugsmomente.
• Druckprüfung nach B31.3, B31.1, EN 13480/PED, ASME VIII mit PDF-Protokoll.
• Korrekte Zeichen in PDFs, automatisches Speichern der ISO-Skizze, Datensicherung.
• Neues Menü mit Werkzeugsuche und angehefteten Werkzeugen.
• Serverdaten löschen: Your profile > Delete my data.
```

### Gotowy blok do Play Console (wszystkie języki naraz)

Play Console przyjmuje jeden blok z tagami języków. Treść w tagach = trzy sekcje powyżej (liczniki jak wyżej, tagi się nie liczą).

```text
<pl-PL>
• Wymiary kształtek wg ASME B16.9/B16.5/B16.10 i poprawione obliczenia: wstawka, szczeliny spoin, rolling offset z kątem obrotu, heat input EN/ASME, podgrzewanie, gaz, moment śrub.
• Próba ciśnieniowa wg B31.3, B31.1, EN 13480/PED, ASME VIII z protokołem PDF.
• PDF z polskimi znakami, autozapis szkicu ISO, kopia zapasowa danych.
• Nowe menu z wyszukiwarką i przypiętymi narzędziami.
• Usuwanie danych z serwera: Twój profil > Usuń moje dane.
</pl-PL>
<en-US>
• Fitting dimensions per ASME B16.9/B16.5/B16.10 and corrected calculations: insert, weld gaps, rolling offset with roll angle, heat input EN/ASME, preheat, gas, bolt torque.
• Pressure test per B31.3, B31.1, EN 13480/PED, ASME VIII with a PDF report.
• Correct characters in PDFs, ISO sketch autosave, one-file backup.
• New menu with tool search and pinned tools.
• Delete your server data: Your profile > Delete my data.
</en-US>
<de-DE>
• Formstückmaße nach ASME B16.9/B16.5/B16.10 und korrigierte Berechnungen: Passstück, Schweißspalte, Etage mit Verdrehwinkel, Streckenenergie EN/ASME, Vorwärmen, Gas, Anzugsmomente.
• Druckprüfung nach B31.3, B31.1, EN 13480/PED, ASME VIII mit PDF-Protokoll.
• Korrekte Zeichen in PDFs, automatisches Speichern der ISO-Skizze, Datensicherung.
• Neues Menü mit Werkzeugsuche und angehefteten Werkzeugen.
• Serverdaten löschen: Your profile > Delete my data.
</de-DE>
```
