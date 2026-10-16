// Pomoc ekranu wycen (przycisk „?" w pasku).

import '../../widgets/help_button.dart';

const ScreenHelp kHelpQuotes = ScreenHelp(
  titlePl: 'Wyceny spawalnicze',
  titleEn: 'Welding quotes',
  bodyPl:
      'Policz, ile kosztuje wykonanie roboty spawalniczej, zanim podasz cenę. '
      'Aplikacja liczy z geometrii rowka masę stopiwa, a z niej czas łuku, '
      'czas spawania, zużycie spoiwa, gazu i prądu. Do tego przygotowanie '
      'złączy, badania NDT, pozycje dodatkowe, koszty ogólne, zysk i VAT. '
      'Ofertę wyślesz klientowi jako PDF albo tekst.',
  bodyEn: 'Work out what a welding job costs before you give a price. The app '
      'takes the weld metal from the groove geometry and from it the arc '
      'time, welding time, filler, gas and power. Add joint prep, NDT, extra '
      'items, overhead, profit and VAT. Send the quote to the client as a PDF '
      'or as text.',
  stepsPl: [
    HelpStep('1️⃣',
        'Spoiny: dodaj pozycje — rodzaj złącza, DN i Sch z tabeli (albo wymiary ręcznie), liczba, pozycja spawania.'),
    HelpStep('🔥',
        'Metoda: grań TIG + wypełnienie MMA/FCAW/MAG albo jeden proces. Grań to ~3 mm od dna rowka.'),
    HelpStep('💰',
        'Koszty: Twoje stawki za godzinę, ceny spoiwa, gazu i prądu, NDT, koszty ogólne, zysk i VAT. „Zapamiętaj jako moje" — następne wyceny wystartują z tymi stawkami.'),
    HelpStep('📏',
        'Wynik: cena netto/brutto, roboczogodziny, dni pracy, kilogramy spoiwa, butle gazu, zł na spoinę i na cal-średnicę (DI).'),
    HelpStep('📄',
        '„Oferta PDF dla klienta" pokazuje zakres i cenę — bez Twoich stawek, narzutu i zysku. „Kosztorys wewnętrzny" pokazuje wszystko.'),
    HelpStep('🔒',
        'Wycena pamięta stawki z dnia utworzenia — zmiana „moich stawek" nie zmienia ofert już wysłanych.'),
    HelpStep('🎯',
        'Założenia procesów (wydajność stapiania, uzysk, jarzenie łuku) to typowe wartości. Po kilku zleceniach porównaj z rzeczywistością i popraw.'),
  ],
  stepsEn: [
    HelpStep('1️⃣',
        'Welds: add items — joint type, DN and schedule from the table (or type the dimensions), count, welding position.'),
    HelpStep('🔥',
        'Method: TIG root + MMA/FCAW/MAG fill, or a single process. The root is ~3 mm from the groove bottom.'),
    HelpStep('💰',
        'Costs: your hourly rates, filler, gas and power prices, NDT, overhead, profit and VAT. "Save as mine" — next quotes start with these rates.'),
    HelpStep('📏',
        'Result: net/gross price, man-hours, working days, kilograms of filler, gas cylinders, price per weld and per dia-inch (DI).'),
    HelpStep('📄',
        '"Client quote PDF" shows the scope and price — without your rates, overhead and profit. "Internal cost estimate" shows everything.'),
    HelpStep('🔒',
        'A quote keeps the rates from the day it was created — changing "my rates" does not change quotes already sent.'),
    HelpStep('🎯',
        'Process assumptions (deposition rate, efficiency, arc duty) are typical values. After a few jobs compare with reality and adjust.'),
  ],
);
