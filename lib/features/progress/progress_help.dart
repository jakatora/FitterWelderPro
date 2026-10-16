// Pomoc ekranu „Postęp robót" (przycisk „?" w pasku).

import '../../widgets/help_button.dart';

const ScreenHelp kHelpProgress = ScreenHelp(
  titlePl: 'Postęp robót i wydajność',
  titleEn: 'Work progress and output',
  bodyPl:
      'Ile dziś zrobiliśmy, kiedy skończymy pakiet i kto ma najwięcej napraw — '
      'policzone ze spoin, które już są w dzienniku spoin. Nic nie wpisujesz '
      'drugi raz: ekran tylko czyta dziennik.',
  bodyEn: 'How much we did today, when the package will be finished and who '
      'has the most repairs — worked out from the welds already in the weld '
      'journal. Nothing is typed twice: this screen only reads the journal.',
  stepsPl: [
    HelpStep('🔎',
        'Zakres: projekt, pakiet testowy, warsztat albo obiekt i okres (dziś, ten tydzień, ten miesiąc, całość, własny).'),
    HelpStep('📏',
        'DI (cal-średnica) = rozmiar NPS spoiny w calach z jej OD (tabela B36.10M/B36.19M). OD spoza tabeli liczymy jako OD / 25,4 i oznaczamy „≈". Spoina bez OD nie ma DI.'),
    HelpStep('✅',
        'Spoina wykonana = wpis w dzienniku (każdy status — PENDING też jest zespawana). Naprawa to ta sama spoina, nie liczy się drugi raz.'),
    HelpStep('👷',
        'Spoina z dwoma spawaczami (grań i lico) jest w wierszu każdego z nich, ale DI dzielimy po równo, a suma brygady liczy ją raz.'),
    HelpStep('🩻',
        'Odsetek napraw = spoiny odrzucone w RT lub UT ÷ spoiny zbadane RT lub UT. Liczy się też wynik sprzed naprawy. Bez badań RT/UT odsetka nie ma.'),
    HelpStep('📈',
        'Tempo = DI z ostatnich N dni roboczych ÷ N. Dziś wlicza się, gdy ma już wpisy. Soboty — przełącznik w prognozie.'),
    HelpStep('🏁',
        'Prognoza: wpisz, ile DI (albo spoin) liczy cały pakiet. Zobaczysz % wykonania, datę końca przy obecnym tempie i ile trzeba robić dziennie, żeby zdążyć na termin. Zakres zapamiętuje się dla projektu i pakietu.'),
    HelpStep('📤',
        'Raport dla szefa: tekstem (SMS, WhatsApp) albo PDF — za okres wybrany u góry (dziś = dzienny, ten tydzień = tygodniowy).'),
  ],
  stepsEn: [
    HelpStep('🔎',
        'Scope: project, test package, shop or field and period (today, this week, this month, everything, custom).'),
    HelpStep('📏',
        'DI (dia-inch) = the weld\'s NPS size in inches from its OD (B36.10M/B36.19M table). An OD outside the table counts as OD / 25.4 and is marked "≈". A weld without OD has no DI.'),
    HelpStep('✅',
        'Weld done = an entry in the journal (any status — PENDING is welded too). A repair is the same weld and is not counted again.'),
    HelpStep('👷',
        'A weld with two welders (root and cap) shows under each of them, but its DI is split equally and the crew total counts it once.'),
    HelpStep('🩻',
        'Repair rate = welds rejected by RT or UT ÷ welds examined by RT or UT. A result recorded before a repair counts too. Without RT/UT there is no rate.'),
    HelpStep('📈',
        'Pace = DI of the last N working days ÷ N. Today counts once it has entries. Saturdays — switch in the forecast.'),
    HelpStep('🏁',
        'Forecast: enter how many DI (or welds) the whole package has. You get % done, the finish date at the current pace and the daily output needed to meet a deadline. The scope is remembered per project and package.'),
    HelpStep('📤',
        'Report for the boss: as text (SMS, WhatsApp) or PDF — for the period chosen at the top (today = daily, this week = weekly).'),
  ],
);
