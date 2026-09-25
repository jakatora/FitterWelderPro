// Parser lokalny asystenta (tryb „Wykonaj"): deterministyczny, offline, PL i EN.
// Tabela zdań → intencja + pola. Sprawdzamy tylko wymienione pola; brak klucza
// w `absent` znaczy, że parser NIE może go zgadywać.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/assistant_intents.dart';
import 'package:cut_list_app/assistant/assistant_parser.dart';

class _Case {
  final String text;
  final String intent;
  final Map<String, Object?> fields;
  final Set<String> absent;
  const _Case(this.text, this.intent,
      [this.fields = const {}, this.absent = const {}]);
}

const _save = kIntentSaveWeldParameter;
const _open = kIntentOpenTool;
const _unknown = kIntentUnknown;

const _plCases = <_Case>[
  // Przykład ze specyfikacji §6 — dosłownie.
  _Case(
      'Zapisz, że spawam stal nierdzewną, ściankę 2 mm, TIG bez drutu na 60 amperach',
      _save,
      {
        'material': 'SS',
        'process': 'TIG',
        'filler': false,
        'wall_mm': 2.0,
        'current_a': 60.0,
      },
      {'diameter_mm', 'position', 'gas', 'flow_lpm', 'electrode_mm', 'joint'}),
  _Case(
      'Zapisz: nierdzewka, ścianka dwa milimetry, TIG bez drutu, sześćdziesiąt amperów',
      _save,
      {'material': 'SS', 'process': 'TIG', 'filler': false, 'wall_mm': 2.0, 'current_a': 60.0}),
  _Case('Zapamiętaj stal czarna, MAG, ścianka 4 mm, 180 A', _save,
      {'material': 'CS', 'process': 'MIG_MAG', 'filler': true, 'wall_mm': 4.0, 'current_a': 180.0}),
  _Case('Dodaj parametr: 316L, 141 z drutem, ścianka 2,77 mm, 85 A', _save,
      {'material': 'SS', 'process': 'TIG', 'filler': true, 'wall_mm': 2.77, 'current_a': 85.0}),
  _Case('Zapisz TIG bez drutu 304 ścianka półtora milimetra 45 amper', _save,
      {'material': 'SS', 'process': 'TIG', 'filler': false, 'wall_mm': 1.5, 'current_a': 45.0}),
  _Case('zapisz rura 60,3 ścianka 2 mm nierdzewka TIG na sucho 58 A', _save, {
    'diameter_mm': 60.3,
    'material': 'SS',
    'process': 'TIG',
    'filler': false,
    'wall_mm': 2.0,
    'current_a': 58.0,
  }),
  _Case('zapisz fi 60 ścianka 2 TIG z prętem stal węglowa 90 amperów', _save, {
    'diameter_mm': 60.0,
    'wall_mm': 2.0,
    'material': 'CS',
    'process': 'TIG',
    'filler': true,
    'current_a': 90.0,
  }),
  _Case('Zapisz DN50 ścianka 3,91 mm stal czarna 141 z drutem 110 A', _save, {
    'diameter_mm': 60.3,
    'wall_mm': 3.91,
    'material': 'CS',
    'process': 'TIG',
    'filler': true,
    'current_a': 110.0,
  }),
  _Case(
      'Zapisz duplex, TIG z drutem, ścianka trzy milimetry, sto dwadzieścia amperów',
      _save,
      {'material': 'DUPLEX', 'process': 'TIG', 'filler': true, 'wall_mm': 3.0, 'current_a': 120.0}),
  _Case('Zapisz aluminium MIG ścianka 5 mm 150 A', _save,
      {'material': 'AL', 'process': 'MIG_MAG', 'filler': true, 'wall_mm': 5.0, 'current_a': 150.0}),
  _Case('Zapisz elektroda 111 stal czarna ścianka 6 mm 95 amperów', _save,
      {'material': 'CS', 'process': 'MMA', 'filler': true, 'wall_mm': 6.0, 'current_a': 95.0}),
  _Case(
      'Zapisz spawanie elektrodą otuloną, stal węglowa, ścianka 8 mm, elektroda 3,2, 110 A',
      _save,
      {
        'material': 'CS',
        'process': 'MMA',
        'filler': true,
        'wall_mm': 8.0,
        'current_a': 110.0,
        'electrode_mm': 3.2,
      }),
  _Case('Zapisz TIG autogenicznie nierdzewka ścianka 1,5 mm 40 A pozycja PF', _save,
      {'material': 'SS', 'process': 'TIG', 'filler': false, 'wall_mm': 1.5, 'current_a': 40.0, 'position': 'PF'}),
  _Case(
      'Zapisz TIG z drutem nierdzewka ścianka 2 mm 70 A argon 8 litrów na minutę',
      _save,
      {'filler': true, 'current_a': 70.0, 'gas': 'AR', 'flow_lpm': 8.0}),
  _Case(
      'Zapisz MAG 135 stal czarna ścianka 10 mm 220 A gaz M21 przepływ 15 l/min',
      _save,
      {'process': 'MIG_MAG', 'material': 'CS', 'wall_mm': 10.0, 'current_a': 220.0, 'gas': 'M21', 'flow_lpm': 15.0}),
  _Case('Zapisz TIG bez drutu nierdzewka ścianka 2 mm 60 A wolfram 2,4 mm', _save,
      {'wall_mm': 2.0, 'current_a': 60.0, 'electrode_mm': 2.4}),
  _Case(
      'Zapisz TIG z drutem stal nierdzewna ścianka 3 mm 90 A spoina doczołowa pozycja 6G',
      _save,
      {'material': 'SS', 'joint': 'BUTT', 'position': '6G', 'current_a': 90.0}),
  _Case(
      'Zapisz MAG stal czarna ścianka 5 mm 160 A spoina pachwinowa pozycja PB',
      _save,
      {'joint': 'FILLET', 'position': 'PB', 'wall_mm': 5.0}),
  _Case(
      'Zapisz TIG nierdzewka ścianka dwa i pół milimetra bez drutu sześćdziesiąt pięć amperów',
      _save,
      {'wall_mm': 2.5, 'current_a': 65.0, 'filler': false}),
  _Case('Zapisz TIG z drutem nierdzewka ścianka 2 mm prąd 75', _save,
      {'current_a': 75.0, 'wall_mm': 2.0}),
  _Case('Zapisz TIG bez drutu kwasówka ścianka 1,2 mm 35A', _save,
      {'material': 'SS', 'wall_mm': 1.2, 'current_a': 35.0}),
  _Case('Zapisz 136 drut proszkowy stal czarna ścianka 12 mm 200 A', _save,
      {'process': 'MIG_MAG', 'filler': true, 'wall_mm': 12.0, 'current_a': 200.0}),
  _Case('Zapisz nierdzewka TIG z drutem ścianka 2mm 80 A rura fi 88,9', _save,
      {'wall_mm': 2.0, 'current_a': 80.0, 'diameter_mm': 88.9}),
  _Case(
      'Zapisz MIG aluminium ścianka cztery milimetry sto czterdzieści amperów',
      _save,
      {'material': 'AL', 'wall_mm': 4.0, 'current_a': 140.0}),
  _Case(
      'Zapisz TIG z drutem stal S355 ścianka 6 mm 130 A pozycja pionowa w górę',
      _save,
      {'material': 'CS', 'position': 'PF', 'current_a': 130.0}),
  // Brak trybu z drutem / bez — parser nie zgaduje (walidator zapyta).
  _Case('Zapisz: stal nierdzewna, TIG, ścianka 2 mm, 60 A', _save,
      {'material': 'SS', 'process': 'TIG', 'wall_mm': 2.0, 'current_a': 60.0},
      {'filler'}),
  // Brak ścianki — też bez zgadywania.
  _Case('Zapisz stal nierdzewną TIG bez drutu 60 amperów', _save,
      {'current_a': 60.0}, {'wall_mm', 'diameter_mm'}),
  // Bez czasownika, ale ewidentnie parametr spawania.
  _Case('Spawam nierdzewkę TIG bez drutu ścianka 2 mm na 60 amperach', _save,
      {'material': 'SS', 'process': 'TIG', 'filler': false, 'wall_mm': 2.0, 'current_a': 60.0}),
  _Case('Zapisz TIG bez drutu nierdzewka ścianka 2 mm 5000 A', _save,
      {'current_a': 5000.0}),
  _Case(
      'Zapisz TIG bez drutu nierdzewka ścianka 0,8 mm czterdzieści pięć amperów',
      _save,
      {'wall_mm': 0.8, 'current_a': 45.0}),
  _Case(
      'zapisz stal czarna TIG z drutem, grubość ścianki 3,6 mm, natężenie 100 A',
      _save,
      {'material': 'CS', 'wall_mm': 3.6, 'current_a': 100.0}),
  _Case('Zapisz TIG bez drutu nierdzewka ścianka dwa przecinek siedem milimetra 62 A',
      _save, {'wall_mm': 2.7, 'current_a': 62.0}),
  _Case('Zapisz TIG bez drutu 1.4404 ścianka 2 mm na sześćdziesięciu amperach',
      _save, {'material': 'SS', 'current_a': 60.0}),
  // Otwieranie narzędzi.
  _Case('Otwórz kalkulator heat input', _open,
      {'query': 'kalkulator heat input'}),
  _Case('Pokaż szablon siodła', _open, {'query': 'szablon siodła'}),
  _Case('Otwórz dziennik spoin', _open, {'query': 'dziennik spoin'}),
  _Case('Proszę, włącz mi konwerter jednostek', _open,
      {'query': 'konwerter jednostek'}),
  // Pytanie wiedzowe — nie operacja.
  _Case('Jaki preheat dla P91?', _unknown),
  _Case('Co to jest NACE?', _unknown),
];

const _enCases = <_Case>[
  _Case('Save stainless steel, 2 mm wall, TIG without filler at 60 amps', _save,
      {'material': 'SS', 'process': 'TIG', 'filler': false, 'wall_mm': 2.0, 'current_a': 60.0}),
  _Case('Remember carbon steel MAG 4 mm wall 180 A', _save,
      {'material': 'CS', 'process': 'MIG_MAG', 'filler': true, 'wall_mm': 4.0, 'current_a': 180.0}),
  _Case('Save TIG with filler, 316L, wall two millimeters, sixty five amps', _save,
      {'material': 'SS', 'filler': true, 'wall_mm': 2.0, 'current_a': 65.0}),
  _Case('Store duplex TIG autogenous wall 1.5 mm 45 amps position 5G', _save, {
    'material': 'DUPLEX',
    'filler': false,
    'wall_mm': 1.5,
    'current_a': 45.0,
    'position': '5G',
  }),
  _Case(
      'Save stick welding carbon steel 8 mm wall electrode 3.2 mm 110 amps',
      _save,
      {'process': 'MMA', 'material': 'CS', 'wall_mm': 8.0, 'current_a': 110.0, 'electrode_mm': 3.2}),
  _Case('Save aluminium MIG wall 5 mm 150 A argon flow 14 l/min', _save,
      {'material': 'AL', 'gas': 'AR', 'flow_lpm': 14.0, 'current_a': 150.0}),
  _Case('Save TIG stainless pipe 60.3 wall 2 mm no filler 58 amps', _save,
      {'diameter_mm': 60.3, 'wall_mm': 2.0, 'filler': false, 'current_a': 58.0}),
  _Case(
      'Save TIG stainless wall two and a half millimeters without filler one hundred amps',
      _save,
      {'wall_mm': 2.5, 'current_a': 100.0}),
  _Case('Save stainless TIG with wire wall 3 mm 90 A fillet weld uphill', _save,
      {'joint': 'FILLET', 'position': 'PF', 'filler': true}),
  _Case('Save carbon steel TIG with filler wall 4 mm current 120', _save,
      {'current_a': 120.0, 'wall_mm': 4.0}),
  _Case('Open heat input', _open, {'query': 'heat input'}),
  _Case('Show me the bolt torque calculator', _open,
      {'query': 'bolt torque calculator'}),
  _Case('What preheat for P91?', _unknown),
];

void _runTable(List<_Case> cases) {
  for (final c in cases) {
    test(c.text, () {
      final p = parseAssistantCommand(c.text);
      expect(p.intent, c.intent, reason: 'intencja dla: ${c.text}');
      c.fields.forEach((key, value) {
        expect(p.fields[key], value, reason: '$key w: ${c.text}');
      });
      for (final key in c.absent) {
        expect(p.fields.containsKey(key), isFalse,
            reason: '$key nie powinno być zgadnięte w: ${c.text}');
      }
      // Parser zwraca tylko pola z dozwolonej listy intencji.
      if (c.intent != _unknown) {
        final spec = kAssistantIntentsV1[c.intent]!;
        expect(spec.allFields.containsAll(p.fields.keys), isTrue,
            reason: 'pole spoza listy: ${p.fields.keys}');
      }
    });
  }
}

void main() {
  test('tabela ma co najmniej 30 zdań PL i 10 EN', () {
    expect(_plCases.length, greaterThanOrEqualTo(30));
    expect(_enCases.length, greaterThanOrEqualTo(10));
  });

  group('PL', () => _runTable(_plCases));
  group('EN', () => _runTable(_enCases));

  group('liczby słownie', () {
    final cases = <String, double>{
      'sześćdziesiąt': 60,
      'sześćdziesięciu': 60,
      'sto dwadzieścia pięć': 125,
      'dwa i pół': 2.5,
      'półtora': 1.5,
      'trzy przecinek dwa': 3.2,
      'dwieście': 200,
      'tysiąc dwieście': 1200,
      'sixty five': 65,
      'one hundred and ten': 110,
      'two and a half': 2.5,
      'three point two': 3.2,
      '2,5': 2.5,
      '60.3': 60.3,
    };
    cases.forEach((text, value) {
      test(text, () => expect(parseSpokenNumber(text), value));
    });
    test('bez liczby → null', () {
      expect(parseSpokenNumber('stal'), isNull);
      expect(parseSpokenNumber(''), isNull);
    });
  });

  group('odpowiedź na pytanie o jedno pole', () {
    test('sama liczba trafia w pytane pole', () {
      expect(parseFieldAnswer('current_a', '60'), {'current_a': 60.0});
      expect(parseFieldAnswer('wall_mm', 'dwa milimetry'), {'wall_mm': 2.0});
      expect(parseFieldAnswer('wall_mm', '2,5'), {'wall_mm': 2.5});
    });
    test('tak/nie dla drutu', () {
      expect(parseFieldAnswer('filler', 'bez drutu'), {'filler': false});
      expect(parseFieldAnswer('filler', 'z drutem'), {'filler': true});
      expect(parseFieldAnswer('filler', 'without'), {'filler': false});
      expect(parseFieldAnswer('filler', 'nie'), {'filler': false});
      expect(parseFieldAnswer('filler', 'tak'), {'filler': true});
    });
    test('materiał i proces słowami', () {
      expect(parseFieldAnswer('material', 'nierdzewka'), {'material': 'SS'});
      expect(parseFieldAnswer('process', 'tig'), {'process': 'TIG'});
    });
    test('bełkot → pusto', () {
      expect(parseFieldAnswer('current_a', 'nie wiem'), isEmpty);
    });
  });
}
