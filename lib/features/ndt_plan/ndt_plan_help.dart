// Pomoc ekranu „Plan badań NDT" (przycisk „?" w pasku).

import '../../widgets/help_button.dart';

const ScreenHelp kHelpNdtPlan = ScreenHelp(
  titlePl: 'Plan badań NDT',
  titleEn: 'NDT plan',
  bodyPl:
      'Ile spoin trzeba jeszcze zbadać — na spawacza i linię, metoda po '
      'metodzie — które zlecić i czy linia jest gotowa do próby ciśnieniowej. '
      'Ekran tylko czyta dziennik spoin; reguły pamięta telefon, osobno dla '
      'każdego projektu.',
  bodyEn: 'How many welds still have to be examined — per welder and line, '
      'method by method — which ones to order and whether a line is ready for '
      'the pressure test. The screen only reads the weld journal; the rules '
      'are kept on the phone, per project.',
  stepsPl: [
    HelpStep('📋',
        'Wymagania: wybierz preset (ASME B31.3 normal fluid service, 100 % RT, 10 % RT + 100 % VT) albo wpisz reguły ze specyfikacji projektu: metoda, %, rodzaj spoiny (BW/FW/SW/BR), opcjonalnie materiał, podział na spawacza i/lub linię.'),
    HelpStep('🔢',
        'Wymagane = spoiny × %, zawsze w górę: 5 % z 1 spoiny to 1 badanie, z 21 spoin — 2. Spoina z dwoma spawaczami (grań i lico) liczy się każdemu z nich.'),
    HelpStep('🩻',
        'Zbadane = wynik OK albo NOK w dzienniku. Odrzucona próbka losowa = 2 dodatkowe badania tego spawacza tą metodą (B31.3 §341.3.4) — te wybiera inspektor.'),
    HelpStep('🎲',
        'Propozycja spoin do zlecenia jest powtarzalna (te same dane = ta sama lista) i woli spoiny jeszcze nie badane. „Losuj ponownie" daje inną listę.'),
    HelpStep('✅',
        'Linia jest „gotowa do próby" tylko przy komplecie: każda spoina ma spawacza, rodzaj i linię, brak otwartych napraw i badań bez wyniku, wszystkie grupy kompletne. Brak danych to nie „OK".'),
    HelpStep('📤',
        'Zlecenie badań tekstem albo PDF — dla laboratorium i inspektora. Po badaniu wpisz wyniki w dzienniku spoin.'),
  ],
  stepsEn: [
    HelpStep('📋',
        'Requirements: pick a preset (ASME B31.3 normal fluid service, 100 % RT, 10 % RT + 100 % VT) or enter the rules from the project specification: method, %, joint type (BW/FW/SW/BR), optionally material, split per welder and/or line.'),
    HelpStep('🔢',
        'Required = welds × %, always rounded up: 5 % of 1 weld is 1 examination, of 21 welds — 2. A weld with two welders (root and cap) counts for each of them.'),
    HelpStep('🩻',
        'Examined = an OK or NOK result in the journal. A rejected random sample = 2 additional examinations of the same welder by the same method (B31.3 §341.3.4) — the inspector picks them.'),
    HelpStep('🎲',
        'The proposed welds are repeatable (same data = same list) and prefer welds not examined yet. "Draw again" gives another list.'),
    HelpStep('✅',
        'A line is "ready for the test" only with complete data: every weld has a welder, joint type and line, no open repairs or pending results, every group complete. Missing data is never "OK".'),
    HelpStep('📤',
        'The examination order as text or PDF — for the NDT lab and the inspector. After the examination, enter the results in the weld journal.'),
  ],
);
