# Szablon siodłowy: geometria i wydruk 1:1

Zakres: kontynuacja zatwierdzonej rozbudowy istniejącej aplikacji, bez usuwania modułów. Stan roboczy, bez publikacji i instalacji.

## Wdrożenie

- Wspólna geometria centralnego przecięcia zewnętrznych walców dla kalkulatora 90° i szablonu 15–90°.
- Głębokość od płaszczyzny najdłuższych końców ku korpusowi: t(phi) minus analityczne minimum całego konturu. Minimum nie pochodzi z próbkowania tabeli.
- Niezależne testy odtwarzają punkt w 3D i sprawdzają równanie walca. Referencje: OD 100/60 przy 90° -> maks. 10 mm; OD 200/100 przy 15° -> maks. 373,2050807569 mm.
- Tabela PDF zawsze 25 punktów co 15°, niezależnie od liczby punktów podglądu. Kontur zagęszczany osobno; dokładne końce przedziałów druku i punkty minimum.
- A4 poziomo, pola 260 x 140 mm, nakładanie 5 mm, podział w obu kierunkach bez skalowania. Maks. 100 pól; przekroczenie blokuje wydruk, nie podgląd.
- Osadzone polskie znaki, PL/EN, podziałki 100 mm X i Y na każdym polu, instrukcja orientacji i składania. PdfGraphics ma oś Y od dołu ku górze: R2 nad R1.
- Aktualizacja po zmianach kontrolerów, limit opisu, kontrola aktualności danych i obecności ekranu bezpośrednio przed udostępnieniem. Nieaktualny eksport jest anulowany.
- Układ przycisków zawija się przy dużej czcionce.
- Oba ekrany dopuszczają teraz równe OD. To celowo zastępuje wcześniejszy zakaz branch >= header zapisany w planie saddle-guidance; zabronione jest branch > header.

## Kontrola

- Rzeczywiste pliki aplikacji: 15° PL (8 stron), 90° PL (3), 75° EN z 26 punktami podglądu (4). Wszystkie 15 stron wyrenderowano i obejrzano.
- Niezależna inspekcja strumieni PDF i macierzy przekształceń: format A4, 25 wierszy tabeli, dwie linie 100 mm na każdej stronie szablonu, dokładne granice pól. Największa reszta równania walca na zapisanych wektorach <0,0009 mm².
- Przegląd niezależny potwierdził geometrię, układ współrzędnych i ochronę przed udostępnieniem starego wyniku.
- Równoległy pełny przebieg testów ujawnił konflikt wspólnego pliku testowej bazy cutlist.db (database is locked). Końcowy przebieg musi być wykonany z --concurrency=1; nie oznacza to naprawy izolacji bazy w istniejących testach.
- Wynik końcowy: flutter analyze --no-pub -> No issues found; flutter test --no-pub --concurrency=1 -> 716/716, exit 0, 1 min 43 s. Nadal występują ostrzeżenia o blokowaniu testowej bazy. Wcześniejszy przebieg równoległy: 714 sukcesów, 2 błędy blokady bazy. Testy równych średnic i anulowania nieaktualnego eksportu przeszły w pełnym przebiegu.

## Ograniczenia

Model nie obejmuje mimośrodu, grubości ścianki, przygotowania krawędzi, szczeliny ani naddatków. Nie jest zatwierdzoną technologią wykonania złącza. Użytkownik musi sprawdzić dokumentację, orientację, dopasowanie i obie podziałki na fizycznym wydruku. Nie wykonano próbnego cięcia ani kontroli rzeczywistej drukarki.

## Powtórzenie kontroli

flutter analyze --no-pub

flutter test --no-pub --concurrency=1 --reporter expanded

Osobne próbki: test_screenshots/saddle_pdf_preview_test.dart oraz saddle_template_shots_test.dart. Próbki PDF powstają z tego samego buildPdf, którego używa eksport aplikacji.
