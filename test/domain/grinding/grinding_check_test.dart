// Tarcze i szlifierki — reguły zgodności: obroty (m/s albo obr./min,
// werdykt niezależny od jednostki), zaokrąglenia w stronę bezpieczeństwa,
// średnica, mocowanie, data ważności (wariant ostrzejszy: do początku
// miesiąca z nadruku), typ wobec pracy, osłona do cięcia, nierdzewka
// i aluminium. Brak danych ≠ OK.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/grinding/grinding_check.dart';

final _now = DateTime(2026, 10, 18, 9);

/// Zestaw w pełni zgodny: szlifierka Ø125 / 11 000 / M14, tarcza 41 Ø125
/// 80 m/s, otwór 22,23 pasujący do kołnierza, V 07/2027, cięcie z osłoną,
/// stal węglowa.
GrindingInput _ok({
  int? grinderRpm = 11000,
  double? grinderD = 125,
  SpindleThread? thread = SpindleThread.m14,
  DiscType? type = DiscType.t41,
  double? discD = 125,
  double? discV = 80,
  int? discN,
  DiscMount? mount = DiscMount.bore2223,
  bool? boreFits = true,
  YearMonth? expiry = const YearMonth(2027, 7),
  bool expiryUnreadable = false,
  bool noExpiry = false,
  SpeedStripe? stripe,
  GrindingOperation? op = GrindingOperation.cutting,
  bool? guard = true,
  WorkMaterial? material = WorkMaterial.carbonSteel,
  bool? marked,
  bool? usedOnCarbon,
}) =>
    GrindingInput(
      grinderRpm: grinderRpm,
      grinderDiameterMm: grinderD,
      spindleThread: thread,
      discType: type,
      discDiameterMm: discD,
      discSpeedMs: discV,
      discRpm: discN,
      discMount: mount,
      boreFitsFlange: boreFits,
      discExpiry: expiry,
      expiryUnreadable: expiryUnreadable,
      discNoExpiry: noExpiry,
      stripe: stripe,
      operation: op,
      cuttingGuard: guard,
      material: material,
      markedForMaterial: marked,
      usedOnCarbonSteel: usedOnCarbon,
    );

GrindingEvaluation _eval(GrindingInput i, [DateTime? now]) =>
    evaluateGrinding(i, now: now ?? _now);

FindingLevel? _level(GrindingInput i, FindingKind k, [DateTime? now]) =>
    _eval(i, now).levelOf(k);

void main() {
  group('przeliczenia', () {
    test('obroty dopuszczalne z prędkości zaokrąglone W DÓŁ', () {
      // 80·60 000/(π·125) = 12 223,1 → 12 223 (nie 12 224).
      expect(maxRpmFromSpeed(80, 125), 12223);
      // 6 642,99 → 6 642 (tabela producenta podaje 6 650 — w górę).
      expect(maxRpmFromSpeed(80, 230), 6642);
      expect(maxRpmFromSpeed(50, 125), 7639);
      expect(maxRpmFromSpeed(100, 115), 16607);
    });

    test('prędkość obwodowa z obrotów zaokrąglona W GÓRĘ', () {
      // 71,9948 → 72,0; 79,9993 → 80,0; 80,0059 → 80,1.
      expect(peripheralSpeedUpMs(125, 11000), 72.0);
      expect(peripheralSpeedUpMs(125, 12223), 80.0);
      expect(peripheralSpeedUpMs(125, 12224), 80.1);
      expect(peripheralSpeedMs(125, 12224), greaterThan(80));
    });

    test('dane spoza zakresu nie dają obrotów', () {
      expect(maxRpmFromSpeed(800, 125), isNull);
      expect(maxRpmFromSpeed(80, 1250), isNull);
      expect(maxRpmFromSpeed(80, 0), isNull);
      expect(maxRpmFromSpeed(double.nan, 125), isNull);
    });
  });

  group('prędkość tarczy wobec obrotów szlifierki', () {
    test('zestaw zgodny → OK, z dopuszczalnymi obrotami i prędkością', () {
      final e = _eval(_ok());
      expect(e.verdict, GrindingVerdict.ok, reason: '${e.findings}');
      expect(e.allowedRpm, 12223);
      expect(e.grinderSpeedUpMs, 72.0);
    });

    test('STOP: tarcza 8 500 obr./min na szlifierce 11 000 obr./min', () {
      final e = _eval(_ok(discV: null, discN: 8500));
      expect(e.levelOf(FindingKind.speed), FindingLevel.stop);
      expect(e.verdict, GrindingVerdict.stop);
      expect(e.of(FindingKind.speed).single.pl, contains('8${kNbsp}500'));
    });

    test('STOP: tarcza 50 m/s Ø125 na 11 000 obr./min (72,0 > 50 m/s)', () {
      final e = _eval(_ok(discV: 50));
      expect(e.levelOf(FindingKind.speed), FindingLevel.stop);
      expect(e.allowedRpm, 7639);
      expect(e.of(FindingKind.speed).single.pl, contains('72 m/s'));
    });

    test('granica: 12 223 obr./min OK, 12 224 obr./min STOP (Ø125, 80 m/s)',
        () {
      expect(
          _level(_ok(grinderRpm: 12223), FindingKind.speed), FindingLevel.ok);
      expect(
          _level(_ok(grinderRpm: 12224), FindingKind.speed), FindingLevel.stop);
    });

    test(
        'werdykt niezależny od jednostki: m/s i obr./min dają ten sam '
        'werdykt dla tych samych danych', () {
      var cases = 0;
      for (final d in [100.0, 115.0, 125.0, 150.0, 180.0, 230.0]) {
        for (final v in [50.0, 63.0, 80.0, 100.0]) {
          final nMax = maxRpmFromSpeed(v, d)!;
          for (final g in [
            6600,
            8500,
            10000,
            11000,
            12000,
            13300,
            nMax - 1,
            nMax,
            nMax + 1,
          ]) {
            final byV = _level(
                _ok(grinderRpm: g, grinderD: 230, discD: d, discV: v),
                FindingKind.speed);
            final byN = _level(
                _ok(
                    grinderRpm: g,
                    grinderD: 230,
                    discD: d,
                    discV: null,
                    discN: nMax),
                FindingKind.speed);
            // Ten sam werdykt co porównanie dokładne w m/s.
            final exact = peripheralSpeedMs(d, g) <= v
                ? FindingLevel.ok
                : FindingLevel.stop;
            expect(byV, byN, reason: 'Ø$d $v m/s, $g obr./min');
            expect(byV, exact, reason: 'Ø$d $v m/s, $g obr./min');
            cases++;
          }
        }
      }
      expect(cases, 6 * 4 * 9);
    });

    test('obie wartości z etykiety: liczy się mniejsza', () {
      // Nadruk 12 250 obr./min (tabela zaokrągla w górę), z 80 m/s 12 223.
      final e = _eval(_ok(grinderRpm: 12240, discN: 12250));
      expect(e.allowedRpm, 12223);
      expect(e.levelOf(FindingKind.speed), FindingLevel.stop);
      // Same obroty z nadruku przepuściłyby 12 240.
      expect(
          _level(_ok(grinderRpm: 12240, discV: null, discN: 12250),
              FindingKind.speed),
          FindingLevel.ok);
      expect(_eval(_ok(discN: 12000)).allowedRpm, 12000);
    });

    test('brak prędkości z etykiety → brak werdyktu, nie OK', () {
      final e = _eval(_ok(discV: null, discN: null));
      expect(e.levelOf(FindingKind.speed), FindingLevel.missing);
      expect(e.verdict, GrindingVerdict.noVerdict);
      expect(e.allowedRpm, isNull);
    });

    test('prędkość m/s bez średnicy tarczy → brak werdyktu', () {
      final e = _eval(_ok(discD: null));
      expect(e.levelOf(FindingKind.speed), FindingLevel.missing);
      expect(e.verdict, GrindingVerdict.noVerdict);
    });

    test('brak obrotów szlifierki → brak werdyktu', () {
      final e = _eval(_ok(grinderRpm: null));
      expect(e.levelOf(FindingKind.speed), FindingLevel.missing);
      expect(e.verdict, GrindingVerdict.noVerdict);
    });

    test('literówka w prędkości nie chowa się za poprawnymi obrotami', () {
      final e = _eval(_ok(discV: 800, discN: 12000));
      expect(e.levelOf(FindingKind.speed), FindingLevel.missing);
      expect(e.allowedRpm, isNull);
      expect(e.verdict, GrindingVerdict.noVerdict);
    });

    test('obroty szlifierki spoza zakresu → brak werdyktu', () {
      expect(_level(_ok(grinderRpm: 110000), FindingKind.speed),
          FindingLevel.missing);
      expect(
          _level(_ok(grinderRpm: 11), FindingKind.speed), FindingLevel.missing);
    });

    test('etykieta niespójna o ponad 3 % → ostrzeżenie, mniejsza wartość', () {
      // Ø125 / 80 m/s = 12 223, wpisano 15 300 (obroty dla Ø100).
      final e = _eval(_ok(discN: 15300));
      expect(e.levelOf(FindingKind.labelConsistency), FindingLevel.warn);
      expect(e.of(FindingKind.labelConsistency).single.appRule, isTrue);
      expect(e.allowedRpm, 12223);
      expect(e.verdict, GrindingVerdict.caution);
      // 12 250 (0,2 %) to zwykłe zaokrąglenie nadruku — bez ostrzeżenia.
      expect(
          _eval(_ok(discN: 12250)).of(FindingKind.labelConsistency), isEmpty);
    });
  });

  group('paski barwne', () {
    test(
        'kolory: niebieski 50, żółty 63, czerwony 80, zielony 100, '
        'niebieski + żółty 125 m/s', () {
      expect({
        for (final s in SpeedStripe.values) s.name: s.speedMs
      }, {
        'blue': 50,
        'yellow': 63,
        'red': 80,
        'green': 100,
        'blueYellow': 125,
      });
    });

    test(
        'pasek niezgodny z wpisaną prędkością → ostrzeżenie (decyduje '
        'nadruk)', () {
      final e = _eval(_ok(stripe: SpeedStripe.green));
      expect(e.levelOf(FindingKind.stripe), FindingLevel.warn);
      expect(e.verdict, GrindingVerdict.caution);
      expect(
          _eval(_ok(stripe: SpeedStripe.red)).of(FindingKind.stripe), isEmpty);
    });

    test('sam pasek to nie dane z etykiety → brak werdyktu', () {
      final e = _eval(_ok(discV: null, stripe: SpeedStripe.red));
      expect(e.levelOf(FindingKind.speed), FindingLevel.missing);
      expect(e.verdict, GrindingVerdict.noVerdict);
    });

    test(
        'nadruk 63 m/s, pasek czerwony (80): do obliczeń idzie nadruk, '
        'ostrzeżenie zostaje', () {
      final e =
          _eval(_ok(grinderRpm: 9000, discV: 63, stripe: SpeedStripe.red));
      // 63·60 000/(π·125) = 9 625,7 → 9 625; z paska byłoby 12 223 (+27 %).
      expect(e.allowedRpm, 9625);
      expect(e.levelOf(FindingKind.stripe), FindingLevel.warn);
      expect(e.levelOf(FindingKind.speed), FindingLevel.ok);
      expect(e.verdict, GrindingVerdict.caution);
      // Szlifierka 11 000 — STOP wg nadruku, mimo że pasek „pozwalałby”.
      expect(_level(_ok(discV: 63, stripe: SpeedStripe.red), FindingKind.speed),
          FindingLevel.stop);
    });
  });

  group('średnica', () {
    test('STOP: tarcza 230 mm na szlifierce 125 mm', () {
      final e = _eval(_ok(discD: 230, discV: 80));
      expect(e.levelOf(FindingKind.diameter), FindingLevel.stop);
      expect(e.verdict, GrindingVerdict.stop);
    });

    test('mniejsza tarcza (115 na 125) — OK', () {
      expect(_level(_ok(discD: 115), FindingKind.diameter), FindingLevel.ok);
      expect(_level(_ok(discD: 125), FindingKind.diameter), FindingLevel.ok);
    });

    test('brak średnicy szlifierki albo tarczy → brak werdyktu', () {
      expect(_level(_ok(grinderD: null), FindingKind.diameter),
          FindingLevel.missing);
      expect(
          _level(_ok(discD: null), FindingKind.diameter), FindingLevel.missing);
      expect(
          _level(_ok(discD: 1250), FindingKind.diameter), FindingLevel.missing);
    });
  });

  group('mocowanie', () {
    test('gwint narzędzia ≠ gwint wrzeciona → STOP', () {
      final e = _eval(_ok(
          type: DiscType.wire,
          op: GrindingOperation.grinding,
          mount: DiscMount.m16,
          thread: SpindleThread.m14));
      expect(e.levelOf(FindingKind.mount), FindingLevel.stop);
    });

    test('gwint narzędzia bez gwintu wrzeciona → brak danych; zgodny → OK', () {
      expect(_level(_ok(mount: DiscMount.m14, thread: null), FindingKind.mount),
          FindingLevel.missing);
      expect(_level(_ok(mount: DiscMount.m14), FindingKind.mount),
          FindingLevel.ok);
      expect(
          _level(_ok(mount: DiscMount.unc58, thread: SpindleThread.unc58),
              FindingKind.mount),
          FindingLevel.ok);
    });

    test(
        'otwór 22,23 — OK także bez gwintu wrzeciona; brak mocowania → '
        'brak danych', () {
      expect(_level(_ok(thread: null), FindingKind.mount), FindingLevel.ok);
      expect(_level(_ok(mount: null), FindingKind.mount), FindingLevel.missing);
    });

    test(
        'otwór tarczy: bez potwierdzenia, że pasuje do kołnierza → brak '
        'danych, „nie pasuje” (Ø16 na kołnierzu 22,23) → STOP', () {
      for (final m in [DiscMount.bore2223, DiscMount.bore16]) {
        final unknown = _eval(_ok(mount: m, boreFits: null));
        expect(unknown.levelOf(FindingKind.mount), FindingLevel.missing,
            reason: m.name);
        expect(unknown.verdict, GrindingVerdict.noVerdict, reason: m.name);
        final no = _eval(_ok(mount: m, boreFits: false));
        expect(no.levelOf(FindingKind.mount), FindingLevel.stop,
            reason: m.name);
        expect(no.verdict, GrindingVerdict.stop, reason: m.name);
        expect(_level(_ok(mount: m, boreFits: true), FindingKind.mount),
            FindingLevel.ok,
            reason: m.name);
      }
    });

    test('tarcza gwintowana — pytanie o otwór nie ma znaczenia', () {
      expect(
          _level(_ok(mount: DiscMount.m14, boreFits: null), FindingKind.mount),
          FindingLevel.ok);
      expect(
          _level(_ok(mount: DiscMount.m14, boreFits: false), FindingKind.mount),
          FindingLevel.ok);
    });
  });

  group('data ważności', () {
    test('odczyt zapisu z pierścienia', () {
      expect(parseExpiry('07/2027'), const YearMonth(2027, 7));
      expect(parseExpiry('V07/2027'), const YearMonth(2027, 7));
      expect(parseExpiry(' v 7.2027 '), const YearMonth(2027, 7));
      expect(parseExpiry('07-27'), const YearMonth(2027, 7));
      expect(parseExpiry('2027-07'), const YearMonth(2027, 7));
      expect(parseExpiry('13/2027'), isNull);
      expect(parseExpiry('00/2027'), isNull);
      expect(parseExpiry('07/1999'), isNull);
      expect(parseExpiry('lipiec'), isNull);
      expect(parseExpiry(''), isNull);
      expect(parseExpiry(null), isNull);
    });

    test('tarcza po terminie → STOP', () {
      final e = _eval(_ok(expiry: const YearMonth(2026, 9)));
      expect(e.levelOf(FindingKind.expiry), FindingLevel.stop);
      expect(e.verdict, GrindingVerdict.stop);
    });

    test(
        'nieczytelna data („13/2027”, „07/2O27”) → brak werdyktu dla '
        'każdego typu, także listkowej, fibrowej i szczotki', () {
      expect(parseExpiry('07/2O27'), isNull);
      for (final t in DiscType.values) {
        final e = _eval(_ok(
            type: t,
            op: t.isCutOff
                ? GrindingOperation.cutting
                : GrindingOperation.grinding,
            expiry: null,
            expiryUnreadable: true));
        expect(e.levelOf(FindingKind.expiry), FindingLevel.missing,
            reason: t.name);
        expect(e.verdict, GrindingVerdict.noVerdict, reason: t.name);
      }
      // Bez typu też — nieczytelny wpis nie znika.
      expect(
          _level(_ok(type: null, expiry: null, expiryUnreadable: true),
              FindingKind.expiry),
          FindingLevel.missing);
      // „Brak daty na tarczy” wyłącza pole — liczy się to potwierdzenie.
      expect(
          _level(
              _ok(
                  type: DiscType.flap,
                  op: GrindingOperation.grinding,
                  expiry: null,
                  expiryUnreadable: true,
                  noExpiry: true),
              FindingKind.expiry),
          isNull);
    });

    test(
        'wariant ostrzejszy: tarcza ważna do początku miesiąca z nadruku '
        '(V 11/2026 — do 31.10.2026)', () {
      const v11 = YearMonth(2026, 11);
      expect(
          _level(_ok(expiry: v11), FindingKind.expiry,
              DateTime(2026, 10, 31, 23, 59)),
          FindingLevel.ok);
      expect(
          _level(_ok(expiry: v11), FindingKind.expiry, DateTime(2026, 11, 1)),
          FindingLevel.stop);
      // Miesiąc z nadruku już nieważny.
      expect(_level(_ok(expiry: const YearMonth(2026, 10)), FindingKind.expiry),
          FindingLevel.stop);
      expect(
          lastValidMonth(const YearMonth(2027, 1)), const YearMonth(2026, 12));
    });

    test(
        '41/42/27 bez wpisanej daty → brak werdyktu; „brak daty na '
        'tarczy” → STOP', () {
      for (final t in [DiscType.t41, DiscType.t42, DiscType.t27]) {
        expect(t.requiresExpiry, isTrue);
        expect(
            _level(_ok(type: t, expiry: null, op: GrindingOperation.cutting),
                FindingKind.expiry),
            FindingLevel.missing,
            reason: t.name);
        expect(
            _level(
                _ok(type: t, expiry: null, noExpiry: true), FindingKind.expiry),
            FindingLevel.stop,
            reason: t.name);
      }
    });

    test(
        'listkowa, fibrowa, szczotka: data nie wymagana, ale gdy jest '
        'i minęła → STOP', () {
      for (final t in [DiscType.flap, DiscType.fibre, DiscType.wire]) {
        final base = _ok(
            type: t, op: GrindingOperation.grinding, expiry: null, guard: null);
        expect(t.requiresExpiry, isFalse);
        expect(_eval(base).of(FindingKind.expiry), isEmpty, reason: t.name);
        expect(
            _level(
                _ok(
                    type: t,
                    op: GrindingOperation.grinding,
                    expiry: const YearMonth(2026, 3)),
                FindingKind.expiry),
            FindingLevel.stop,
            reason: t.name);
      }
    });

    test('data dalej niż 36 mies. od dziś (literówka) → brak werdyktu', () {
      expect(_level(_ok(expiry: const YearMonth(2029, 10)), FindingKind.expiry),
          FindingLevel.ok);
      expect(_level(_ok(expiry: const YearMonth(2029, 11)), FindingKind.expiry),
          FindingLevel.missing);
      expect(_level(_ok(expiry: const YearMonth(2072, 7)), FindingKind.expiry),
          FindingLevel.missing);
    });
  });

  group('typ tarczy wobec pracy', () {
    test('41 i 42: cięcie OK, szlifowanie bokiem STOP', () {
      for (final t in [DiscType.t41, DiscType.t42]) {
        expect(_level(_ok(type: t), FindingKind.operation), FindingLevel.ok);
        final e = _eval(_ok(type: t, op: GrindingOperation.grinding));
        expect(e.levelOf(FindingKind.operation), FindingLevel.stop,
            reason: t.name);
        expect(e.of(FindingKind.operation).single.source, contains('EN 12413'));
      }
    });

    test('27: szlifowanie OK, cięcie — ostrzeżenie', () {
      expect(
          _level(_ok(type: DiscType.t27, op: GrindingOperation.grinding),
              FindingKind.operation),
          FindingLevel.ok);
      final e = _eval(_ok(type: DiscType.t27));
      expect(e.levelOf(FindingKind.operation), FindingLevel.warn);
      expect(e.verdict, GrindingVerdict.caution);
    });

    test('listkowa, fibrowa, szczotka: szlifowanie OK, cięcie STOP', () {
      for (final t in [DiscType.flap, DiscType.fibre, DiscType.wire]) {
        expect(
            _level(_ok(type: t, op: GrindingOperation.grinding),
                FindingKind.operation),
            FindingLevel.ok,
            reason: t.name);
        expect(_level(_ok(type: t), FindingKind.operation), FindingLevel.stop,
            reason: t.name);
      }
    });

    test('brak typu albo rodzaju pracy → brak werdyktu', () {
      expect(_level(_ok(type: null), FindingKind.type), FindingLevel.missing);
      expect(_eval(_ok(type: null)).verdict, GrindingVerdict.noVerdict);
      expect(
          _level(_ok(op: null), FindingKind.operation), FindingLevel.missing);
    });
  });

  group('osłona do cięcia', () {
    test('cięcie: brak odpowiedzi → brak danych, „nie” → STOP, „tak” → OK', () {
      expect(_level(_ok(guard: null), FindingKind.guard), FindingLevel.missing);
      expect(_level(_ok(guard: false), FindingKind.guard), FindingLevel.stop);
      expect(_eval(_ok(guard: false)).verdict, GrindingVerdict.stop);
      expect(_level(_ok(guard: true), FindingKind.guard), FindingLevel.ok);
    });

    test('szlifowanie — bez pytania o osłonę do cięcia', () {
      final e = _eval(
          _ok(type: DiscType.t27, op: GrindingOperation.grinding, guard: null));
      expect(e.of(FindingKind.guard), isEmpty);
      expect(e.verdict, GrindingVerdict.ok, reason: '${e.findings}');
    });
  });

  group('nierdzewka i aluminium', () {
    GrindingInput inox(
            {DiscType type = DiscType.t41,
            bool? marked = true,
            bool? used = false}) =>
        _ok(
            type: type,
            op: type.isCutOff
                ? GrindingOperation.cutting
                : GrindingOperation.grinding,
            material: WorkMaterial.stainless,
            marked: marked,
            usedOnCarbon: used);

    test('tarcza używana wcześniej na stali węglowej → STOP na nierdzewce', () {
      final e = _eval(inox(used: true));
      expect(e.levelOf(FindingKind.material), FindingLevel.stop);
      expect(e.verdict, GrindingVerdict.stop);
    });

    test(
        'tarcza bez INOX → ostrzeżenie; INOX i nieużywana → OK z '
        'odsyłaczem do modułów', () {
      expect(
          _level(inox(marked: false), FindingKind.material), FindingLevel.warn);
      final ok = _eval(inox());
      expect(ok.levelOf(FindingKind.material), FindingLevel.ok);
      final text = ok.of(FindingKind.material).single.pl;
      expect(text, contains('„Przebarwienia”'));
      expect(text, contains('„Trawienie i pasywacja”'));
      expect(ok.of(FindingKind.material).single.source, contains('0,1 %'));
    });

    test('szczotka z drutu stalowego na nierdzewce → STOP', () {
      expect(
          _level(
              inox(type: DiscType.wire, marked: false), FindingKind.material),
          FindingLevel.stop);
    });

    test('nierdzewka bez odpowiedzi → brak werdyktu (dwa pytania)', () {
      final e = _eval(inox(marked: null, used: null));
      expect(e.levelOf(FindingKind.material), FindingLevel.missing);
      expect(
          e
              .of(FindingKind.material)
              .where((f) => f.level == FindingLevel.missing),
          hasLength(2));
    });

    test('aluminium: tarcza nie do aluminium albo po stali → ostrzeżenie', () {
      GrindingInput alu({bool? marked = true, bool? used = false}) => _ok(
          material: WorkMaterial.aluminium, marked: marked, usedOnCarbon: used);
      expect(_level(alu(), FindingKind.material), FindingLevel.ok);
      expect(
          _level(alu(marked: false), FindingKind.material), FindingLevel.warn);
      expect(_level(alu(used: true), FindingKind.material), FindingLevel.warn);
      expect(_level(alu(marked: null), FindingKind.material),
          FindingLevel.missing);
    });

    test('brak materiału → brak werdyktu', () {
      expect(_level(_ok(material: null), FindingKind.material),
          FindingLevel.missing);
    });
  });

  group('werdykt i formatowanie', () {
    test('kolejność: STOP przed brakiem danych przed ostrzeżeniem', () {
      // STOP (średnica) + brak danych (materiał) + ostrzeżenie (pasek).
      final e =
          _eval(_ok(discD: 230, material: null, stripe: SpeedStripe.green));
      expect(e.verdict, GrindingVerdict.stop);
      final m = _eval(_ok(material: null, stripe: SpeedStripe.green));
      expect(m.verdict, GrindingVerdict.noVerdict);
      expect(_eval(const GrindingInput()).verdict, GrindingVerdict.noVerdict);
    });

    test('liczby: PL 11 000 i 72,1; EN 11,000 i 72.1', () {
      expect(fmtRpm(11000, en: false), '11${kNbsp}000');
      expect(kNbsp.codeUnits, [0xA0]);
      expect(fmtRpm(11000, en: true), '11,000');
      expect(fmtRpm(850, en: false), '850');
      expect(fmtNum(72.1, en: false), '72,1');
      expect(fmtNum(72.1, en: true), '72.1');
      expect(fmtNum(80, en: false), '80');
    });

    test(
        'każdy wynik ma tekst PL i EN; STOP ma źródło albo regułę '
        'aplikacji', () {
      final inputs = [
        _ok(),
        _ok(discV: 50),
        _ok(discD: 230),
        _ok(op: GrindingOperation.grinding),
        _ok(type: DiscType.flap),
        _ok(guard: false),
        _ok(expiry: const YearMonth(2026, 1)),
        _ok(noExpiry: true, expiry: null),
        _ok(mount: DiscMount.m16),
        _ok(material: WorkMaterial.stainless, usedOnCarbon: true),
        const GrindingInput(),
      ];
      for (final i in inputs) {
        for (final f in _eval(i).findings) {
          expect(f.pl.trim(), isNotEmpty);
          expect(f.en.trim(), isNotEmpty);
          if (f.level == FindingLevel.stop) {
            expect(f.sourceLabel(en: false), isNotNull, reason: '$f');
          }
        }
      }
    });
  });
}
