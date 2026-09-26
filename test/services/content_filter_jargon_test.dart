// Filtr czatu a żargon spawacza i montera.
//
// Filtr łapie wyzwiska po RDZENIU słowa, więc każde branżowe słowo, które
// zaczyna się tak samo jak wyzwisko, jest odrzucane jako obraźliwe. Tak było z
// „pedałem" od TIG-a (pedał nożny, foot pedal) i z „sutkami" (złączki
// nyplowe). Ten plik pilnuje, żeby codzienne słownictwo z budowy przechodziło,
// a wyzwiska — dalej nie.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/content_filter.dart';

void main() {
  group('żargon spawacza i montera przechodzi', () {
    // Każda pozycja to słowo z budowy, które w innym kontekście bywa
    // wyzwiskiem albo zaczyna się jak rdzeń z listy blokad.
    const jargon = <String>[
      'Mam problem z pedałem od TIG-a, prąd skacze.',
      'Pedał nożny do Kempy — ktoś ma na sprzedaż?',
      'Wciśnij pedał do końca, zanim zajarzysz.',
      'Na pedale trzymam 120 A, na rurze 3 mm wystarcza.',
      'Foot pedal amperage for 2 mm stainless?',
      'Which TIG pedal do you run with the Miller?',
      'Pedały do TIG-a padają od kurzu, przedmuchaj je.',
      'Potrzebuję trzy sutki 1/2 cala i mufę.',
      'Sutek ocynk 3/4 — ile kosztuje w hurtowni?',
      'Weź szmatę i przetrzyj rowek przed spawaniem.',
      'Szmata z acetonem na nierdzewkę, nie z benzyną.',
      'Dziad w kolanie — kolano 90° się wykręciło.',
      'Postaw rurę na koziołku, będzie łatwiej wyrównać.',
      'Kozioł pod rurę DN300 ma 1,2 m wysokości.',
      'Pałka elektrody 3,2 poszła w 2 minuty.',
      'Pała do gięcia rur leży w kontenerze.',
      'Fire retardant coating on the pipe rack.',
      'Retarder w farbie opóźnia schnięcie.',
      'Idiotoodporne złącze — nie da się źle wkręcić.',
      'Kurek kulowy DN50 cieknie na dławicy.',
      'Nypel, trójnik, redukcja — lista na jutro.',
      'Spaw doczołowy, butt weld, 100% RT.',
      'Mufa i nypel na gwint stożkowy.',
      'Ciotka Ani spawa lepiej niż niejeden.',
      'Chełm, Kraków, Gdańsk — wszędzie ta sama stal.',
      'DN100, ścianka 6 mm, takeout 45° to 64 mm.',
      'S355 i 316L — jaki drut do mieszanego złącza?',
      'P91 25 mm, preheat 200 °C, PWHT 760 °C.',
    ];

    for (final text in jargon) {
      test('„$text"', () {
        expect(
          ContentFilter.firstOffense(text),
          isNull,
          reason: 'filtr odrzucił słowo z budowy',
        );
      });
    }
  });

  group('wyzwiska dalej nie przechodzą', () {
    const insults = <String>[
      'ty pedale jeden',
      'Ty pedał jesteś',
      'ty pedzio',
      'pedryl jeden',
      'kurwa mać',
      'chujowa robota',
      'ty debilu',
      'idiota z ciebie',
      'jebany spawacz',
      'fuck this weld',
      'you retard',
      'retarded fitter',
    ];

    for (final text in insults) {
      test('„$text"', () {
        expect(
          ContentFilter.isObjectionable(text),
          isTrue,
          reason: 'wyzwisko przeszło przez filtr',
        );
      });
    }
  });

  test('wyjątki nie otwierają furtki: sam rdzeń dalej łapany', () {
    // „idiotoodporny" przechodzi, ale „idiota" nie.
    expect(ContentFilter.isObjectionable('idiotoodporny'), isFalse);
    expect(ContentFilter.isObjectionable('idiota'), isTrue);
    // „retardant" przechodzi, „retard" nie.
    expect(ContentFilter.isObjectionable('retardant'), isFalse);
    expect(ContentFilter.isObjectionable('retard'), isTrue);
  });
}
