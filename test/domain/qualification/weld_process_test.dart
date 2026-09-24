import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/weld_process.dart';

void main() {
  group('processFamiliesIn — numery ISO 4063 i nazwy', () {
    for (final (text, expected) in <(String?, Set<WeldProcessFamily>)>[
      ('141', {WeldProcessFamily.gtaw}),
      ('142', {WeldProcessFamily.gtaw}),
      ('TIG', {WeldProcessFamily.gtaw}),
      ('Tandem', {WeldProcessFamily.gtaw}),
      ('GTAW', {WeldProcessFamily.gtaw}),
      ('MIG/MAG', {WeldProcessFamily.gmaw}),
      ('135', {WeldProcessFamily.gmaw}),
      ('138', {WeldProcessFamily.gmaw}),
      ('136', {WeldProcessFamily.fcaw}),
      ('114', {WeldProcessFamily.fcaw}),
      ('MMA', {WeldProcessFamily.smaw}),
      ('111', {WeldProcessFamily.smaw}),
      ('121', {WeldProcessFamily.saw}),
      ('141 + 111', {WeldProcessFamily.gtaw, WeldProcessFamily.smaw}),
      ('141/135', {WeldProcessFamily.gtaw, WeldProcessFamily.gmaw}),
      // „SAW" jako całe słowo — nie wolno go znaleźć w „SMAW".
      ('SMAW', {WeldProcessFamily.smaw}),
      // Rok i gatunek stali nie są procesem.
      ('2026 316L', <WeldProcessFamily>{}),
      ('', <WeldProcessFamily>{}),
      (null, <WeldProcessFamily>{}),
      ('spawanie', <WeldProcessFamily>{}),
    ]) {
      test('"$text" → $expected', () {
        expect(processFamiliesIn(text), expected);
      });
    }
  });

  group('matchProcess', () {
    for (final (weld, allowed, mutual, expected) in <(
      String?,
      String?,
      Map<int, Set<int>>,
      ProcessMatch
    )>[
      // Numer z numerem — ISO 9606-1 §5.2: 141 nie obejmuje 142.
      ('141', '141', const {}, ProcessMatch.covered),
      ('142', '141', const {}, ProcessMatch.notCovered),
      // Wpis dziennika bez numeru — tylko rodzina.
      ('TIG', '141', const {}, ProcessMatch.covered),
      ('MMA', '141', const {}, ProcessMatch.notCovered),
      // Pary wzajemne ISO 9606-1 tylko, gdy wołający je poda.
      ('138', '135', kIso9606MutualProcesses, ProcessMatch.covered),
      ('138', '135', const {}, ProcessMatch.notCovered),
      // Dwa procesy w spoinie — oba muszą być dopuszczone.
      ('141 + 111', '141, 111', const {}, ProcessMatch.covered),
      ('141 + 111', '141', const {}, ProcessMatch.notCovered),
      ('141 + MMA', '141, 111', const {}, ProcessMatch.covered),
      // Brak danych po którejś stronie — nie oceniamy.
      ('', '141', const {}, ProcessMatch.unknown),
      ('141', '', const {}, ProcessMatch.unknown),
      ('coś', '141', const {}, ProcessMatch.unknown),
    ]) {
      test('$weld vs $allowed → ${expected.name}', () {
        expect(matchProcess(weld, allowed, mutual: mutual), expected);
      });
    }
  });

  group('rodzaje złączy', () {
    test('kodowanie w stałej kolejności i tolerancyjny odczyt', () {
      expect(encodeJointKinds({WeldJointKind.fw, WeldJointKind.bw}), 'BW+FW');
      expect(encodeJointKinds(const {}), '');
      expect(decodeJointKinds('fw, bw'), {WeldJointKind.bw, WeldJointKind.fw});
      expect(decodeJointKinds('BW'), {WeldJointKind.bw});
      expect(decodeJointKinds('XX'), isEmpty);
      expect(decodeJointKinds(null), isEmpty);
    });
  });
}
