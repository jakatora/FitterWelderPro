import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/assistant/core/utterance.dart';

void main() {
  test(
      'serialized steps preserve standalone symbol orientation and every fitting size',
      () {
    const steps = <IsoStep>[
      IsoFitting('elbow45', dn: 50, symbolOnly: true, dir: IsoDir.up),
      IsoFitting('tee', dn: 100, dnOut: 80, symbolOnly: true, dir: IsoDir.back),
      IsoPipe(dir: IsoDir.right, lengthMm: 1234.5),
      IsoTurn(degrees: 45, toDir: IsoDir.forward, dn: 100),
      IsoPipe(lengthMm: 999),
      IsoFitting('reducer', dn: 100, dnOut: 80),
    ];
    final wire = jsonDecode(jsonEncode(encodeIsoSteps(steps)));
    expect((wire as List).first['symbol_only'], true);
    expect(wire.first['dir'], 'up');
    expect(decodeIsoSteps(wire), steps);
    expect(decodeIsoSteps(steps), steps);
    expect(encodeIsoSteps(decodeIsoSteps(wire)), encodeIsoSteps(steps));
  });
  test(
      'natural command symbols retain orientation through the same wire contract as routes',
      () {
    for (final (text, lang) in [
      ('narysuj symbol kolana 45 DN50 w górę', AppLanguage.pl),
      ('draw symbol of tee DN100 to DN80 back', AppLanguage.en),
      (
        'narysuj rura metr w prawo kolano 45 stopni DN100 w górę rura metr',
        AppLanguage.pl
      ),
    ]) {
      final command = parseIsoCommand(Utterance(text, lang: lang))!;
      expect(
          decodeIsoSteps(jsonDecode(jsonEncode(encodeIsoSteps(command.steps)))),
          command.steps,
          reason: text);
    }
  });
  final bad = <Object?>[
    'pipe',
    1,
    false,
    [1],
    {},
    {'kind': 'unknown'},
    {'kind': 'pipe', 'length_mm': 0},
    {'kind': 'pipe', 'length_mm': -1},
    {'kind': 'pipe', 'length_mm': double.nan},
    {'kind': 'pipe', 'length_mm': double.infinity},
    {'kind': 'pipe', 'length_mm': '1000'},
    {'kind': 'pipe', 'dir': 'north'},
    {'kind': 'pipe', 'dn': 100},
    {'kind': 'pipe', 'future': null},
    for (final value in [
      0,
      -1,
      50.2,
      45,
      double.nan,
      double.infinity,
      '50',
      true
    ])
      {'kind': 'turn', 'dn': value},
    {'kind': 'turn', 'degrees': 45.5},
    {'kind': 'turn', 'degrees': 30},
    {'kind': 'fitting', 'tool': 'unknown'},
    {'kind': 'fitting', 'tool': 10},
    {'kind': 'fitting', 'tool': 'tee', 'symbol_only': 'true'},
    {'kind': 'fitting', 'tool': 'tee', 'dir': 'up'},
    {'kind': 'fitting', 'tool': 'tee', 'dir': 'up', 'symbol_only': false},
    {'kind': 'fitting', 'tool': 'tee', 'dn': 50, 'dn_out': 100},
    {'kind': 'fitting', 'tool': 'tee', 'dn_out': 50},
    {'kind': 'fitting', 'tool': 'ballValve', 'dn_out': 50},
    const IsoPipe(lengthMm: -1),
    const IsoTurn(degrees: 30),
  ];
  for (var index = 0; index < bad.length; index++) {
    test(
        'malformed step $index is refused before a partial sequence is returned',
        () {
      final first = <String, Object?>{
        'kind': 'pipe',
        'dir': 'right',
        'length_mm': 1000
      };
      final input = [first, bad[index]];
      expect(() => decodeIsoSteps(input), throwsFormatException);
      expect(first, {'kind': 'pipe', 'dir': 'right', 'length_mm': 1000});
    });
  }
  test('legacy route maps retain 90 degree defaults and empty input', () {
    expect(decodeIsoSteps(null), isEmpty);
    expect(decodeIsoSteps([]), isEmpty);
    expect(
        decodeIsoSteps([
          {'kind': 'turn', 'dir': 'up', 'dn': 50}
        ]),
        [const IsoTurn(toDir: IsoDir.up, dn: 50)]);
  });
}
