// Lista środków zapobiegania odkształceniom: każda sytuacja (element ×
// odkształcenie) ma ≥ 3 środki, każdy z „dlaczego” i źródłem, teksty PL i EN
// z tymi samymi liczbami, bez emoji; przyciski do energii liniowej
// i odbioru kołnierzy tam, gdzie trzeba; korekta (prostowanie) na końcu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/distortion_tips.dart';
import 'package:cut_list_app/domain/welding/distortion.dart';

Set<String> _numbers(String s) =>
    RegExp(r'\d+').allMatches(s).map((m) => m.group(0)!).toSet();

bool _hasEmoji(String s) => s.runes.any((r) =>
    (r >= 0x1F000 && r <= 0x1FAFF) ||
    (r >= 0x2600 && r <= 0x27BF) ||
    r == 0xFE0F);

DistortionMeasure _byId(String id) =>
    kDistortionMeasures.firstWhere((m) => m.id == id);

void main() {
  test('identyfikatory unikalne, wszystkie teksty i źródła niepuste', () {
    final ids = kDistortionMeasures.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final m in kDistortionMeasures) {
      for (final s in [
        m.titlePl,
        m.titleEn,
        m.howPl,
        m.howEn,
        m.whyPl,
        m.whyEn,
        m.source,
      ]) {
        expect(s.trim(), isNotEmpty, reason: m.id);
      }
      expect(m.elements, isNotEmpty, reason: m.id);
      expect(m.kinds, isNotEmpty, reason: m.id);
    }
  });

  test('każda sytuacja ma co najmniej 3 środki, każdy z „dlaczego”', () {
    for (final e in DistortionElement.values) {
      final kinds = kindsFor(e);
      expect(kinds, isNotEmpty, reason: e.name);
      for (final k in kinds) {
        final list = measuresFor(e, k);
        expect(list.length, greaterThanOrEqualTo(3), reason: '${e.name}/${k.name}');
        for (final m in list) {
          expect(m.whyPl.length, greaterThan(20), reason: m.id);
          expect(m.whyEn.length, greaterThan(20), reason: m.id);
        }
      }
    }
  });

  test('każdy środek trafia do co najmniej jednej sensownej sytuacji', () {
    for (final m in kDistortionMeasures) {
      final used = DistortionElement.values
          .any((e) => kindsFor(e).any((k) => m.appliesTo(e, k)));
      expect(used, isTrue, reason: m.id);
    }
    // I każdy rodzaj odkształcenia ma element.
    for (final k in DistortionKind.values) {
      expect(DistortionElement.values.any((e) => kindsFor(e).contains(k)),
          isTrue,
          reason: k.name);
    }
  });

  test('PL i EN mają te same liczby; bez emoji', () {
    for (final m in kDistortionMeasures) {
      final pl = _numbers('${m.titlePl} ${m.howPl} ${m.whyPl}');
      final en = _numbers('${m.titleEn} ${m.howEn} ${m.whyEn}');
      expect(pl, en, reason: m.id);
      for (final s in [m.titlePl, m.titleEn, m.howPl, m.howEn, m.whyPl, m.whyEn]) {
        expect(_hasEmoji(s), isFalse, reason: m.id);
      }
    }
    for (final e in DistortionElement.values) {
      expect(_hasEmoji(e.pl) || _hasEmoji(e.en), isFalse);
    }
  });

  test('liczby ze źródeł: rura, stopiwo, prostowanie płomieniem', () {
    final tacks = _byId('pipe-tacks');
    expect(tacks.howPl, contains('12, 3, 6 i 9'));
    expect(tacks.howPl, contains('5–10 %'));
    expect(tacks.source, contains('Pipe Welding'));
    final metal = _byId('less-metal');
    expect(metal.howPl, contains('57 %'));
    expect(metal.source, contains('Job Knowledge 34'));
    final flame = _byId('flame');
    expect(flame.correction, isTrue);
    expect(flame.howPl, contains('600–650 °C'));
    expect(flame.howEn, contains('600–650 °C'));
    expect(flame.howPl, contains('nierdzewna'));
    expect(flame.howPl, contains('WPS'));
    expect(flame.source, contains('Job Knowledge 37'));
    final longi = _byId('longitudinal');
    expect(longi.howPl, contains('3 mm na 3 m'));
    expect(longi.howPl, contains('0,8 mm na 3 m'));
    expect(longi.howEn, contains('0.8 mm per 3 m'));
  });

  test('ustawienie wstępne bez wymyślonego kąta', () {
    final preset = _byId('preset');
    expect(_numbers(preset.howPl + preset.whyPl), isEmpty);
    expect(preset.howPl, contains('spoinie próbnej'));
  });

  test('przyciski: energia liniowa i odbiór kołnierzy', () {
    expect(_byId('heat-input').link, MeasureLink.heatInput);
    expect(_byId('flange-check').link, MeasureLink.flangeCheck);
    expect(
        measuresFor(DistortionElement.plateButt, DistortionKind.angular)
            .map((m) => m.link),
        contains(MeasureLink.heatInput));
    expect(
        measuresFor(DistortionElement.flangeOnPipe, DistortionKind.flangeTilt)
            .map((m) => m.link),
        containsAll([MeasureLink.heatInput, MeasureLink.flangeCheck]));
  });

  test('kołnierz w skos: sczepy, naprzeciwległe odcinki, kontrola', () {
    final ids =
        measuresFor(DistortionElement.flangeOnPipe, DistortionKind.flangeTilt)
            .map((m) => m.id);
    expect(ids, containsAll(['pipe-tacks', 'opposite', 'flange-check']));
    expect(ids, isNot(contains('flame')));
  });

  test('korekta po spawaniu zawsze na końcu listy', () {
    for (final e in DistortionElement.values) {
      for (final k in kindsFor(e)) {
        final list = measuresFor(e, k);
        final firstCorrection = list.indexWhere((m) => m.correction);
        if (firstCorrection < 0) continue;
        expect(list.skip(firstCorrection).every((m) => m.correction), isTrue,
            reason: '${e.name}/${k.name}');
      }
    }
    final plate =
        measuresFor(DistortionElement.plateButt, DistortionKind.angular);
    expect(plate.last.id, 'flame');
  });
}
