// Pomoc ekranu „Akord: ile zarobiłem" (przycisk „?" w pasku).

import '../../widgets/help_button.dart';

const ScreenHelp kHelpPiecework = ScreenHelp(
  titlePl: 'Akord: ile zarobiłem',
  titleEn: 'Piecework: what I earned',
  bodyPl:
      'Ile wychodzi z akordu za spoiny wpisane w dzienniku — z rozbiciem na '
      'podstawę, dopłaty i potrącenia, żeby dało się sprawdzić rozliczenie od '
      'firmy spoina po spoinie. Ekran tylko czyta dziennik; stawki pamięta '
      'telefon.',
  bodyEn: 'What the piecework pays for the welds logged in the journal — split '
      'into base, surcharges and deductions, so you can check the company\'s '
      'settlement weld by weld. The screen only reads the journal; the rates '
      'are kept on the phone.',
  stepsPl: [
    HelpStep('💰',
        'Stawki: za cal-średnicę (zł/DI) albo za spoinę (zł/szt.). Dopłaty to % podstawy i sumują się: materiał (nierdzewna, inne), pozycja (2G, 5G, 6G), gruba ścianka (Sch 80+ albo próg w mm).'),
    HelpStep('📏',
        'DI = rozmiar NPS spoiny w calach z jej OD (tabela B36.10M/B36.19M) — ta sama reguła co w „Postępie robót". OD spoza tabeli: OD / 25,4, oznaczone „≈".'),
    HelpStep('⚠️',
        'Spoina bez OD w trybie DI NIE jest wliczana — jest na liście „pominięte". Uzupełnij wymiar w dzienniku, a kwota się zmieni.'),
    HelpStep('🩻',
        'Odrzucona spoina (naprawa R1+ albo NOK): potrącenie % jej wartości — 100% = 0 zł. Naprawa może być płatna osobno, % wartości za każdą naprawę.'),
    HelpStep('👷',
        'Spawacz: „ja" z profilu, ktoś z dziennika albo cała brygada. Spoina z dwoma spawaczami (grań i lico) — każdy dostaje połowę.'),
    HelpStep('⏱️',
        'Zł/godzinę: wpisz godziny okresu albo „godzin dziennie" w stawkach. Jeśli zapisałeś „Ile brać za godzinę", zobaczysz porównanie.'),
    HelpStep('📤',
        'Zestawienie tekstem albo PDF (spoina po spoinie) — do rozmowy z firmą.'),
  ],
  stepsEn: [
    HelpStep('💰',
        'Rates: per dia-inch (zł/DI) or per weld. Surcharges are % of the base and add up: material (stainless, other), position (2G, 5G, 6G), heavy wall (Sch 80+ or a mm threshold).'),
    HelpStep('📏',
        'DI = the weld\'s NPS size in inches from its OD (B36.10M/B36.19M table) — the same rule as in "Work progress". An OD outside the table: OD / 25.4, marked "≈".'),
    HelpStep('⚠️',
        'In DI mode a weld without an OD is NOT counted — it is on the "skipped" list. Fill in the size in the journal and the amount changes.'),
    HelpStep('🩻',
        'Rejected weld (repair R1+ or NOK): deduction as % of its value — 100% = 0 zł. A repair can be paid separately, % of the value per repair.'),
    HelpStep('👷',
        'Welder: "me" from the profile, anyone from the journal or the whole crew. A weld with two welders (root and cap) — each gets half.'),
    HelpStep('⏱️',
        'Per hour: enter the period\'s hours or "hours per day" in the rates. If "What to charge per hour" is saved, you get a comparison.'),
    HelpStep('📤',
        'Summary as text or PDF (weld by weld) — for the talk with the company.'),
  ],
);
