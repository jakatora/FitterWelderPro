// Regresje z przeglądu modułu wycen (2026-10-17).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/quotes/hourly_rate.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';

void main() {
  test('rowek I z cienką ścianką i domyślnym progiem 1,5 mm da się zapisać',
      () {
    const j = QuoteJoint(
      id: 'i',
      kind: JointKind.pipeButt,
      odMm: 21.3,
      wallMm: 1.0,
      groove: GrooveType.square,
      rootFaceMm: 1.5,
      gapMm: 1,
    );
    expect(j.problems, isEmpty);
    // Ten sam próg przy rowku V nadal jest błędem (pole jest widoczne).
    expect(j.copyWith(groove: GrooveType.v).problems,
        contains(JointProblem.rootFace));
  });

  test('króciec: kąt fazy powyżej 80° jest błędem (tg β → ∞)', () {
    const j = QuoteJoint(
      id: 'b',
      kind: JointKind.branch,
      odMm: 60.3,
      wallMm: 3.91,
      headerOdMm: 168.3,
      angleDeg: 90,
    );
    expect(j.problems, contains(JointProblem.angle));
    expect(j.copyWith(angleDeg: 45).problems, isEmpty);
    // Rowek V doczołowy może mieć 90° (całkowity).
    expect(
        const QuoteJoint(
                id: 'v',
                kind: JointKind.pipeButt,
                odMm: 114.3,
                wallMm: 6,
                angleDeg: 90)
            .problems,
        isEmpty);
  });

  test('literówka w wymiarze (OD 114300) blokuje pozycję zamiast liczyć', () {
    const j = QuoteJoint(
        id: 't', kind: JointKind.pipeButt, odMm: 114300, wallMm: 6.02);
    expect(j.problems, contains(JointProblem.outOfRange));
    expect(j.copyWith(odMm: 114.3).problems, isEmpty);
  });

  test('poprawny JSON ze złym typem pola nie wywraca odczytu wyceny', () {
    final q = WeldQuote.fromRow(const {
      'id': 'x',
      'number': 'WYC/2026/001',
      'status': 7,
      'data_json': '{"material": 3, "scheme": false, "site": [],'
          ' "joints": [{"id": "j", "kind": 5, "groove": 1, "pos": {},'
          ' "scheme": 2, "od": 114.3, "t": 6}],'
          ' "rates": {"vat": 23, "filler": {"TIG": "drogo"}}}',
      'created_at': 1,
      'updated_at': 2,
    });
    expect(q.joints.single.kind, JointKind.pipeButt);
    expect(q.material, QuoteMaterial.carbon);
    expect(q.rates.vat, QuoteVat.vat23);
    expect(q.status, QuoteStatus.draft);
  });

  test('dniówka liczona z godzin dnia, nie ze stałych 8 h', () {
    final r = computeHourlyRate(
        const HourlyRateInput().copyWith(hoursPerDay: 10));
    expect(r.dayRate, closeTo(r.recommendedRate * 10, 1e-9));
  });
}
