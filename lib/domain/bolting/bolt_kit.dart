/// Komplet do zamówienia: lista połączeń kołnierzowych ASME B16.5
/// (DN × Class × przylga × materiał śrub × liczba połączeń) → szpilki,
/// nakrętki (2 na szpilkę) i uszczelki, opcjonalnie z zapasem % (zawsze
/// w górę). Czysta domena: model, zestawienie, JSON, teksty PL/EN.
///
/// Liczba i średnica szpilek — [FlangeCatalog] (przez [lookupAsmeStud]),
/// długość — `stud_length.dart`. Zapis listy: `bolt_kit_store.dart` obok
/// ekranu (SharedPreferences), eksport: `lib/services/bolt_kit_export.dart`.
library;

import 'dart:convert';

import 'bolt_torque.dart';
import 'stud_length.dart';

export 'stud_length.dart';

String _t(bool en, String pl, String e) => en ? e : pl;

// ═══════════════════════════════════════════════════════════════════════════
// MATERIAŁY I USZCZELKI
// ═══════════════════════════════════════════════════════════════════════════

/// Para szpilka / nakrętka. Nakrętki heavy hex (ASME B18.2.2).
enum BoltMaterial {
  /// Stal stopowa — ogólne zastosowanie.
  b7('A193 B7', 'A194 2H', 'B7'),

  /// Obniżona twardość — środowisko kwaśne (NACE MR0175 / MR0103).
  b7m('A193 B7M', 'A194 2HM', 'B7M'),

  /// Nierdzewna 316.
  b8m('A193 B8M', 'A194 8M', 'B8M'),

  /// Niskie temperatury.
  l7('A320 L7', 'A194 7', null);

  const BoltMaterial(this.stud, this.nut, this.torqueGrade);

  /// Gatunek szpilki, np. `A193 B7`.
  final String stud;

  /// Gatunek nakrętki, np. `A194 2H`.
  final String nut;

  /// Gatunek w kalkulatorze „Moment śrub” albo `null`, gdy go tam nie ma.
  final String? torqueGrade;

  /// `A193 B7 / A194 2H`.
  String get pair => '$stud / $nut';
}

/// Uszczelka do przylgi RF (RTJ → zawsze pierścień, [ringJointNumber]).
enum RfGasket { spiralWound, kammprofile, sheet }

String rfGasketLabel(RfGasket g, {required bool en}) => switch (g) {
      RfGasket.spiralWound =>
        _t(en, 'spiralna (ASME B16.20)', 'spiral-wound (ASME B16.20)'),
      RfGasket.kammprofile =>
        _t(en, 'kammprofile (ASME B16.20)', 'kammprofile (ASME B16.20)'),
      RfGasket.sheet => _t(en, 'płaska (ASME B16.21)', 'sheet (ASME B16.21)'),
    };

/// Numer pierścienia RTJ (ASME B16.20 / B16.5) dla DN × Class albo `null`
/// (Class 150 NPS ½ i ¾ — brak RTJ; DN × Class spoza katalogu). Źródło:
/// DNOW „Number and Size of Bolts for Flanged Joints — ASME B16.5” (wiersz
/// „Ring No.”). Class 300 i 600 mają te same pierścienie; Class 900 NPS
/// ½–2½ — jak Class 1500.
String? ringJointNumber(int dn, int cls) => _kRings['${dn}_$cls'];

const Map<String, String> _kRings = {
  '25_150': 'R15', '32_150': 'R17', '40_150': 'R19', '50_150': 'R22',
  '65_150': 'R25', '80_150': 'R29', '100_150': 'R36', '150_150': 'R43',
  '200_150': 'R48', '250_150': 'R52', '300_150': 'R56',
  //
  '15_300': 'R11', '20_300': 'R13', '25_300': 'R16', '32_300': 'R18',
  '40_300': 'R20', '50_300': 'R23', '65_300': 'R26', '80_300': 'R31',
  '100_300': 'R37', '150_300': 'R45', '200_300': 'R49', '250_300': 'R53',
  '300_300': 'R57',
  //
  '15_600': 'R11', '20_600': 'R13', '25_600': 'R16', '32_600': 'R18',
  '40_600': 'R20', '50_600': 'R23', '65_600': 'R26', '80_600': 'R31',
  '100_600': 'R37', '150_600': 'R45', '200_600': 'R49', '250_600': 'R53',
  '300_600': 'R57',
  //
  '15_900': 'R12', '20_900': 'R14', '25_900': 'R16', '32_900': 'R18',
  '40_900': 'R20', '50_900': 'R24', '65_900': 'R27', '80_900': 'R31',
  '100_900': 'R37', '150_900': 'R45', '200_900': 'R49', '250_900': 'R53',
  '300_900': 'R57',
  //
  '15_1500': 'R12', '20_1500': 'R14', '25_1500': 'R16', '32_1500': 'R18',
  '40_1500': 'R20', '50_1500': 'R24', '65_1500': 'R27', '80_1500': 'R35',
  '100_1500': 'R39', '150_1500': 'R46', '200_1500': 'R50', '250_1500': 'R54',
  '300_1500': 'R58',
};

// ═══════════════════════════════════════════════════════════════════════════
// POŁĄCZENIE NA LIŚCIE
// ═══════════════════════════════════════════════════════════════════════════

/// Najwięcej połączeń jednego rodzaju na liście (więcej = literówka).
const int kMaxJointCount = 999;

/// Dozwolone zapasy [%].
const List<int> kSpareOptions = [0, 5, 10, 15, 20];

bool isValidJointCount(int n) => n >= 1 && n <= kMaxJointCount;

class BoltKitJoint {
  final String id;
  final int dn;
  final int cls;
  final FlangeFacing facing;
  final BoltMaterial material;

  /// Tylko dla RF (RTJ — pierścień).
  final RfGasket gasket;

  /// Liczba takich połączeń.
  final int count;

  const BoltKitJoint({
    required this.id,
    required this.dn,
    required this.cls,
    required this.facing,
    required this.material,
    this.gasket = RfGasket.spiralWound,
    required this.count,
  });

  BoltKitJoint copyWith({int? count}) => BoltKitJoint(
        id: id,
        dn: dn,
        cls: cls,
        facing: facing,
        material: material,
        gasket: gasket,
        count: count ?? this.count,
      );

  /// To samo połączenie (poza liczbą i id) — dodanie scala pozycje.
  bool sameKindAs(BoltKitJoint o) =>
      dn == o.dn &&
      cls == o.cls &&
      facing == o.facing &&
      material == o.material &&
      (facing == FlangeFacing.rtj || gasket == o.gasket);

  StudLookup get lookup => lookupAsmeStud(dn, cls, facing);

  /// Szpilki z tabeli albo `null`, gdy połączenia nie ma w B16.5 / katalogu.
  AsmeStud? get stud => switch (lookup) {
        StudFound(:final stud) => stud,
        StudNotFound() => null,
      };

  Map<String, Object?> toJson() => {
        'id': id,
        'dn': dn,
        'cls': cls,
        'facing': facing.name,
        'material': material.name,
        'gasket': gasket.name,
        'count': count,
      };

  /// `null`, gdy wpis jest uszkodzony albo nie istnieje w tabeli B16.5
  /// (nie zgadujemy szpilek dla nieznanego połączenia).
  static BoltKitJoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final dn = json['dn'];
    final cls = json['cls'];
    final count = json['count'];
    if (id is! String || id.isEmpty) return null;
    if (dn is! int || cls is! int || count is! int) return null;
    if (!isValidJointCount(count)) return null;
    final facing =
        FlangeFacing.values.where((f) => f.name == json['facing']).firstOrNull;
    final material = BoltMaterial.values
        .where((m) => m.name == json['material'])
        .firstOrNull;
    final gasket =
        RfGasket.values.where((g) => g.name == json['gasket']).firstOrNull;
    if (facing == null || material == null || gasket == null) return null;
    final j = BoltKitJoint(
      id: id,
      dn: dn,
      cls: cls,
      facing: facing,
      material: material,
      gasket: gasket,
      count: count,
    );
    return j.stud == null ? null : j;
  }
}

/// Lista połączeń + zapas — to, co trafia do zapisu.
class BoltKitState {
  final List<BoltKitJoint> joints;
  final int sparePercent;

  const BoltKitState({this.joints = const [], this.sparePercent = 0});

  Map<String, Object?> toJson() => {
        'v': 1,
        'spare': sparePercent,
        'joints': [for (final j in joints) j.toJson()],
      };
}

String encodeBoltKit(BoltKitState s) => jsonEncode(s.toJson());

/// Wynik odczytu: stan i to, czy zapis był NIENARUSZONY (inaczej magazyn
/// robi kopię surowej wartości przed nadpisaniem).
class BoltKitDecoded {
  final BoltKitState state;
  final bool intact;
  const BoltKitDecoded(this.state, {required this.intact});
}

/// Nigdy nie rzuca: pusty → pusty stan (nienaruszony); nieczytelny JSON,
/// zły zapas, wpis uszkodzony albo spoza tabeli → pominięty, `intact: false`.
BoltKitDecoded decodeBoltKitReport(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const BoltKitDecoded(BoltKitState(), intact: true);
  }
  try {
    final json = jsonDecode(raw);
    if (json is! Map || json['joints'] is! List) {
      return const BoltKitDecoded(BoltKitState(), intact: false);
    }
    var intact = json['v'] == 1;
    final rawSpare = json['spare'];
    var spare = 0;
    if (rawSpare is int && kSpareOptions.contains(rawSpare)) {
      spare = rawSpare;
    } else {
      intact = false;
    }
    final out = <BoltKitJoint>[];
    final ids = <String>{};
    for (final e in json['joints'] as List) {
      final j = BoltKitJoint.fromJson(e);
      if (j != null && ids.add(j.id)) {
        out.add(j);
        // Wpis odczytany bez strat zapisuje się z powrotem identycznie;
        // nieznane pola (nowsza wersja) → kopia przed nadpisaniem.
        if (!_sameJson(j.toJson(), e)) intact = false;
      } else {
        intact = false;
      }
    }
    return BoltKitDecoded(BoltKitState(joints: out, sparePercent: spare),
        intact: intact);
  } catch (_) {
    return const BoltKitDecoded(BoltKitState(), intact: false);
  }
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_sameJson(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

// ═══════════════════════════════════════════════════════════════════════════
// ZESTAWIENIE DO ZAMÓWIENIA
// ═══════════════════════════════════════════════════════════════════════════

/// Ilość z zapasem [percent] — zawsze w górę, na liczbach całkowitych
/// (bez ułamków zmiennoprzecinkowych): 48 szt. + 10 % = 52,8 → 53.
int withSpare(int qty, int percent) {
  if (qty < 0 || percent < 0) {
    throw ArgumentError('qty=$qty, percent=$percent');
  }
  return (qty * (100 + percent) + 99) ~/ 100;
}

class StudOrderLine {
  final BoltMaterial material;
  final FlangeBoltSize size;
  final int lengthQuarterIn;
  final int qty;
  const StudOrderLine(this.material, this.size, this.lengthQuarterIn, this.qty);
}

class NutOrderLine {
  final BoltMaterial material;
  final FlangeBoltSize size;
  final int qty;
  const NutOrderLine(this.material, this.size, this.qty);
}

class GasketOrderLine {
  final int dn;
  final int cls;
  final FlangeFacing facing;

  /// Dla RF.
  final RfGasket? gasket;

  /// Dla RTJ, np. `R45`.
  final String? ring;
  final int qty;

  const GasketOrderLine({
    required this.dn,
    required this.cls,
    required this.facing,
    required this.gasket,
    required this.ring,
    required this.qty,
  });
}

class BoltKitOrder {
  final List<BoltKitJoint> joints;
  final List<StudOrderLine> studs;
  final List<NutOrderLine> nuts;
  final List<GasketOrderLine> gaskets;
  final int sparePercent;

  const BoltKitOrder({
    required this.joints,
    required this.studs,
    required this.nuts,
    required this.gaskets,
    required this.sparePercent,
  });

  bool get isEmpty => studs.isEmpty && gaskets.isEmpty;

  int spare(int qty) => withSpare(qty, sparePercent);

  int get totalJoints => joints.fold(0, (s, j) => s + j.count);
  int get totalStuds => studs.fold(0, (s, l) => s + l.qty);
  int get totalNuts => nuts.fold(0, (s, l) => s + l.qty);
  int get totalGaskets => gaskets.fold(0, (s, l) => s + l.qty);
}

/// Zestawienie: te same szpilki (materiał × średnica × długość), nakrętki
/// (materiał × średnica) i uszczelki (DN × Class × typ) sumowane. Zapas
/// liczony od sumy pozycji (nie od każdego połączenia osobno), w górę.
/// Połączenie spoza tabeli — pomijane (nie trafia na listę; [BoltKitJoint
/// .fromJson] go nie przepuszcza).
BoltKitOrder buildBoltKitOrder(List<BoltKitJoint> joints,
    {int sparePercent = 0}) {
  final studs = <String, StudOrderLine>{};
  final nuts = <String, NutOrderLine>{};
  final gaskets = <String, GasketOrderLine>{};
  final used = <BoltKitJoint>[];
  for (final j in joints) {
    final s = j.stud;
    if (s == null || !isValidJointCount(j.count)) continue;
    used.add(j);
    final studQty = s.boltCount * j.count;
    final sk = '${j.material.name}|${s.size.label}|${s.lengthQuarterIn}';
    final prevS = studs[sk];
    studs[sk] = StudOrderLine(
        j.material, s.size, s.lengthQuarterIn, (prevS?.qty ?? 0) + studQty);
    final nk = '${j.material.name}|${s.size.label}';
    nuts[nk] = NutOrderLine(
        j.material, s.size, (nuts[nk]?.qty ?? 0) + s.nutCount * j.count);
    final rtj = j.facing == FlangeFacing.rtj;
    final gk = '${j.dn}|${j.cls}|${j.facing.name}|${rtj ? '' : j.gasket.name}';
    gaskets[gk] = GasketOrderLine(
      dn: j.dn,
      cls: j.cls,
      facing: j.facing,
      gasket: rtj ? null : j.gasket,
      ring: rtj ? ringJointNumber(j.dn, j.cls) : null,
      qty: (gaskets[gk]?.qty ?? 0) + j.count,
    );
  }
  int bySize(FlangeBoltSize a, FlangeBoltSize b) =>
      a.diameterIn.compareTo(b.diameterIn);
  final studList = studs.values.toList()
    ..sort((a, b) {
      final m = a.material.index.compareTo(b.material.index);
      if (m != 0) return m;
      final d = bySize(a.size, b.size);
      return d != 0 ? d : a.lengthQuarterIn.compareTo(b.lengthQuarterIn);
    });
  final nutList = nuts.values.toList()
    ..sort((a, b) {
      final m = a.material.index.compareTo(b.material.index);
      return m != 0 ? m : bySize(a.size, b.size);
    });
  final gasketList = gaskets.values.toList()
    ..sort((a, b) {
      final c = a.cls.compareTo(b.cls);
      if (c != 0) return c;
      final d = a.dn.compareTo(b.dn);
      return d != 0 ? d : a.facing.index.compareTo(b.facing.index);
    });
  return BoltKitOrder(
    joints: used,
    studs: studList,
    nuts: nutList,
    gaskets: gasketList,
    sparePercent: kSpareOptions.contains(sparePercent) ? sparePercent : 0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// TEKSTY (ekran i eksport)
// ═══════════════════════════════════════════════════════════════════════════

/// NPS dla DN katalogu (z łącznikiem jak średnice śrub).
const Map<int, String> _kNps = {
  15: '1/2',
  20: '3/4',
  25: '1',
  32: '1-1/4',
  40: '1-1/2',
  50: '2',
  65: '2-1/2',
  80: '3',
  100: '4',
  150: '6',
  200: '8',
  250: '10',
  300: '12',
};

/// „DN150 (6")”.
String jointSizeLabel(int dn) {
  final n = _kNps[dn];
  return n == null ? 'DN$dn' : 'DN$dn ($n")';
}

/// „DN150 (6") · Class 300 · RF”.
String jointTitle(BoltKitJoint j) =>
    '${jointSizeLabel(j.dn)} · Class ${j.cls} · ${facingLabel(j.facing)}';

/// Uszczelka połączenia jednym słowem: „spiralna (ASME B16.20)” albo
/// „pierścień R45”.
String jointGasketLabel(BoltKitJoint j, {required bool en}) =>
    j.facing == FlangeFacing.rtj
        ? _t(en, 'pierścień ${ringJointNumber(j.dn, j.cls) ?? 'RTJ'}',
            'ring ${ringJointNumber(j.dn, j.cls) ?? 'RTJ'}')
        : rfGasketLabel(j.gasket, en: en);

/// „3/4" × 4-3/4" (120,65 mm) A193 B7”.
String studLineLabel(StudOrderLine l, {required bool en}) =>
    '${studDesignation(l.size, l.lengthQuarterIn)} '
    '(${formatMm(l.lengthQuarterIn * kMmPerQuarterInch, decimals: 2, en: en)}) '
    '${l.material.stud}';

/// „3/4" heavy hex A194 2H”.
String nutLineLabel(NutOrderLine l, {required bool en}) =>
    '${formatBoltDiameter(l.size)} heavy hex ${l.material.nut}';

/// „spiralna (ASME B16.20), NPS 6 Class 300” / „pierścień R45 (RTJ), NPS 6
/// Class 600”.
String gasketLineLabel(GasketOrderLine l, {required bool en}) {
  final size = 'NPS ${_nps(l.dn)} Class ${l.cls}';
  if (l.facing == FlangeFacing.rtj) {
    return _t(en, 'pierścień ${l.ring ?? 'RTJ'} (ASME B16.20), $size',
        'ring ${l.ring ?? 'RTJ'} (ASME B16.20), $size');
  }
  return '${rfGasketLabel(l.gasket ?? RfGasket.spiralWound, en: en)}, $size';
}

String _nps(int dn) => _kNps[dn] ?? 'DN$dn';

/// Ilość z zapasem: „48 szt.” albo „48 szt. + zapas 10 % = 53 szt.” (bez
/// strzałek — Roboto w PDF ich nie ma).
String qtyLabel(int qty, int sparePercent, {required bool en}) {
  final pcs = _t(en, '$qty szt.', '$qty pcs');
  if (sparePercent == 0) return pcs;
  final total = withSpare(qty, sparePercent);
  return _t(en, '$pcs + zapas $sparePercent % = $total szt.',
      '$pcs + $sparePercent % spare = $total pcs');
}

/// Uwaga o założeniach tabeli — pod zestawieniem i w eksporcie.
String boltKitAssumptionsNote({required bool en}) => _t(
    en,
    'Długości wg ASME B16.5 (przylga RF: 2 mm / 1/16" dla Class 150 i 300, '
        '7 mm / 1/4" od Class 400), mierzone bez ścięć. Nakrętki heavy hex, '
        '2 na szpilkę. Grubsze uszczelki, przekładki, zaślepki okularowe, '
        'zestawy izolujące — policz długość z wymiarów. Sprawdź ze '
        'specyfikacją projektu.',
    'Lengths per ASME B16.5 (RF: 2 mm / 1/16" for Class 150 and 300, '
        '7 mm / 1/4" from Class 400), measured without points. Heavy hex '
        'nuts, 2 per stud. Thicker gaskets, spacers, spectacle blinds, '
        'isolation kits — calculate the length from dimensions. Check against '
        'the project specification.');
