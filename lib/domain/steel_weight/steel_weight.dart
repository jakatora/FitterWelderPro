/// Ciężar stali: masa pozycji, lista materiałowa, koszt zamówienia.
///
/// Ścieżka liczenia jednej pozycji:
///   kształtownik walcowany → kg/m z tabeli (steel_sections.dart) · ρ/7850,
///   profil zamknięty       → pole z wzoru EN 10219-2 · ρ,
///   płaskownik / pręt      → pole z wymiarów (krawędzie ostre) · ρ,
///   blacha                 → grubość · szerokość · długość · ρ;
///   masa pozycji = kg/m · długość · sztuki.
///
/// Pieniądze w GROSZACH (int), jak w wycenach: koszt każdej pozycji
/// zaokrąglony do grosza w chwili powstania, suma na groszach, zapas %
/// doliczany do sumy ([percentOf]).
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import '../quotes/quote_calculator.dart' show costGrosze, percentOf;
import 'steel_sections.dart';

/// Gęstość, dla której liczone są tabele kształtowników (EN 10365,
/// EN 10056-1, EN 10219-2): 7,85 kg/dm³.
const double kTableDensity = 7850;

/// Materiał pozycji. Gęstości [kg/m³]:
/// - stal węglowa / konstrukcyjna: 7850 (podstawa tablic mas EN);
/// - nierdzewna austenityczna 1.4301 (304): 7900 (EN 10088-1, zał. A);
/// - kwasoodporna 1.4404 (316L): 8000 (EN 10088-1, zał. A);
/// - aluminium (stopy 6060 / 6082): 2700.
enum SteelMaterial {
  carbon(7850, 'Stal konstrukcyjna', 'Structural steel', ''),
  stainless304(
      7900, 'Nierdzewna 1.4301 (304)', 'Stainless 1.4301 (304)', '1.4301'),
  stainless316(
      8000, 'Kwasoodporna 1.4404 (316L)', 'Stainless 1.4404 (316L)', '1.4404'),
  aluminium(2700, 'Aluminium', 'Aluminium', 'Al');

  final double density;
  final String labelPl;
  final String labelEn;

  /// Krótki dopisek do nazwy pozycji (pusty dla stali konstrukcyjnej).
  final String tag;

  const SteelMaterial(this.density, this.labelPl, this.labelEn, this.tag);

  String label(bool english) => english ? labelEn : labelPl;

  static SteelMaterial byName(String? name) => SteelMaterial.values
      .firstWhere((m) => m.name == name, orElse: () => SteelMaterial.carbon);
}

/// Jednostka ceny pozycji.
enum PriceUnit { perKg, perM }

/// Dlaczego pozycji nie da się policzyć.
enum SteelItemProblem {
  /// Nie wybrano wymiaru z tabeli (albo nazwy nie ma w tabeli).
  noSection,

  /// Wymiar przekroju ≤ 0 albo pusty.
  badDimensions,

  /// Profil zamknięty: ścianka za gruba do boków.
  wallTooThick,

  /// Długość ≤ 0.
  noLength,

  /// Liczba sztuk < 1.
  noCount,
}

/// Jedna pozycja listy materiałowej.
///
/// Wymiary [a], [b], [t] w mm, znaczenie zależy od [shape]:
/// - profil zamknięty: a = H, b = B, t = ścianka;
/// - płaskownik: a = szerokość, t = grubość;
/// - pręt okrągły: a = średnica; pręt kwadratowy: a = bok;
/// - blacha: a = szerokość arkusza, t = grubość ([lengthMm] = długość arkusza).
/// Dla kształtownika z tabeli wymiar wskazuje [section] (nazwa wiersza).
class SteelItem {
  final SteelShape shape;
  final String? section;
  final double a;
  final double b;
  final double t;

  /// Długość jednej sztuki [mm] (blacha: długość arkusza).
  final double lengthMm;
  final int count;
  final SteelMaterial material;

  /// Własna cena pozycji (null → cena za kg z listy).
  final double? unitPrice;
  final PriceUnit priceUnit;

  const SteelItem({
    required this.shape,
    this.section,
    this.a = 0,
    this.b = 0,
    this.t = 0,
    this.lengthMm = 6000,
    this.count = 1,
    this.material = SteelMaterial.carbon,
    this.unitPrice,
    this.priceUnit = PriceUnit.perKg,
  });

  SteelItem copyWith({
    SteelShape? shape,
    String? section,
    double? a,
    double? b,
    double? t,
    double? lengthMm,
    int? count,
    SteelMaterial? material,
    double? unitPrice,
    bool clearPrice = false,
    PriceUnit? priceUnit,
  }) =>
      SteelItem(
        shape: shape ?? this.shape,
        section: section ?? this.section,
        a: a ?? this.a,
        b: b ?? this.b,
        t: t ?? this.t,
        lengthMm: lengthMm ?? this.lengthMm,
        count: count ?? this.count,
        material: material ?? this.material,
        unitPrice: clearPrice ? null : (unitPrice ?? this.unitPrice),
        priceUnit: priceUnit ?? this.priceUnit,
      );

  /// Wiersz tabeli (tylko kształtowniki walcowane).
  SteelSection? get tableSection =>
      shape.tabulated ? sectionByName(shape, section) : null;

  SteelItemProblem? get problem {
    if (shape.tabulated) {
      if (tableSection == null) return SteelItemProblem.noSection;
    } else {
      bool pos(double v) => v.isFinite && v > 0;
      switch (shape) {
        case SteelShape.hollow:
          if (!pos(a) || !pos(b) || !pos(t)) {
            return SteelItemProblem.badDimensions;
          }
          if (!hollowGeometryOk(a, b, t)) return SteelItemProblem.wallTooThick;
        case SteelShape.flat:
        case SteelShape.plate:
          if (!pos(a) || !pos(t)) return SteelItemProblem.badDimensions;
        default:
          if (!pos(a)) return SteelItemProblem.badDimensions;
      }
    }
    if (!(lengthMm.isFinite && lengthMm > 0)) return SteelItemProblem.noLength;
    if (count < 1) return SteelItemProblem.noCount;
    return null;
  }

  bool get isValid => problem == null;

  /// Pole przekroju [mm²] liczone z geometrii (null dla tabel).
  double? get _geometricAreaMm2 => switch (shape) {
        SteelShape.hollow => hollowAreaMm2(a, b, t),
        SteelShape.flat || SteelShape.plate => a * t,
        SteelShape.roundBar => math.pi * a * a / 4,
        SteelShape.squareBar => a * a,
        _ => null,
      };

  /// Masa 1 m [kg/m] (blacha: 1 m długości arkusza o szerokości [a]).
  /// 0, gdy pozycja nie jest kompletna.
  double get kgPerM {
    final section = tableSection;
    if (section != null) {
      return section.kgPerM * material.density / kTableDensity;
    }
    final area = _geometricAreaMm2;
    if (area == null || !area.isFinite || area <= 0) return 0;
    return area * 1e-6 * material.density;
  }

  /// Blacha: masa 1 m² [kg/m²].
  double get kgPerM2 => t * 1e-3 * material.density;

  double get pieceKg => isValid ? kgPerM * lengthMm / 1000 : 0;

  double get totalKg => pieceKg * count;

  /// Długość łączna [m].
  double get totalLengthM => isValid ? lengthMm / 1000 * count : 0;

  /// Blacha: powierzchnia arkuszy [m²] (jedna strona).
  double get plateAreaM2 =>
      shape == SteelShape.plate && isValid ? a * lengthMm * 1e-6 * count : 0;

  /// Powierzchnia malowania [m²/m] (cały obwód) albo null.
  double? get paintM2PerM {
    final section = tableSection;
    if (section != null) return section.paintM2PerM;
    return switch (shape) {
      SteelShape.hollow => hollowPerimeterMm(a, b, t) / 1000,
      SteelShape.flat || SteelShape.plate => 2 * (a + t) / 1000,
      SteelShape.roundBar => math.pi * a / 1000,
      SteelShape.squareBar => 4 * a / 1000,
      _ => null,
    };
  }

  /// Powierzchnia malowania całej pozycji [m²] albo null.
  double? get totalPaintM2 {
    final p = paintM2PerM;
    if (p == null || !isValid) return null;
    return p * totalLengthM;
  }

  /// Nazwa wyrobu bez długości: „HEB 200", „SHS 100×100×4",
  /// „Płaskownik 80×10 · 1.4301".
  String label({bool english = false}) {
    final base = switch (shape) {
      _ when shape.tabulated => section ?? '?',
      SteelShape.hollow =>
        '${a == b ? 'SHS' : 'RHS'} ${fmtDim(a)}×${fmtDim(b)}×${fmtDim(t)}',
      SteelShape.flat =>
        '${english ? 'Flat bar' : 'Płaskownik'} ${fmtDim(a)}×${fmtDim(t)}',
      SteelShape.roundBar => '${english ? 'Round bar' : 'Pręt'} Ø${fmtDim(a)}',
      SteelShape.squareBar =>
        '${english ? 'Square bar' : 'Pręt kw.'} ${fmtDim(a)}',
      SteelShape.plate => '${english ? 'Plate' : 'Blacha'} '
          '${fmtDim(t)}×${fmtDim(a)}×${fmtDim(lengthMm)}',
      _ => '?',
    };
    return material.tag.isEmpty ? base : '$base · ${material.tag}';
  }

  /// Klucz grupowania „ten sam profil": nazwa + materiał (blachy różnej
  /// długości arkusza to osobne grupy — tak się je zamawia).
  String get groupKey => '${label()}|${material.name}';

  Map<String, dynamic> toJson() => {
        'shape': shape.name,
        if (section != null) 'section': section,
        'a': a,
        'b': b,
        't': t,
        'len': lengthMm,
        'n': count,
        'mat': material.name,
        if (unitPrice != null) 'price': unitPrice,
        'pu': priceUnit.name,
      };

  /// null, gdy wpis jest nieczytelny (np. nieznany rodzaj).
  static SteelItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    SteelShape? shape;
    for (final s in SteelShape.values) {
      if (s.name == raw['shape']) shape = s;
    }
    if (shape == null) return null;
    double d(Object? v) => v is num ? v.toDouble() : 0;
    final price = raw['price'];
    final item = SteelItem(
      shape: shape,
      section: raw['section'] is String ? raw['section'] as String : null,
      a: d(raw['a']),
      b: d(raw['b']),
      t: d(raw['t']),
      lengthMm: d(raw['len']),
      count: raw['n'] is num ? (raw['n'] as num).toInt() : 0,
      material: SteelMaterial.byName(raw['mat'] as String?),
      unitPrice: price is num ? price.toDouble() : null,
      priceUnit:
          raw['pu'] == PriceUnit.perM.name ? PriceUnit.perM : PriceUnit.perKg,
    );
    return item.isValid ? item : null;
  }
}

/// Koszt pozycji w groszach albo null (brak ceny).
int? itemCostGrosze(SteelItem item, double? listPricePerKg) {
  if (!item.isValid) return null;
  final own = item.unitPrice;
  if (own != null && own.isFinite && own >= 0) {
    return item.priceUnit == PriceUnit.perM
        ? costGrosze(item.totalLengthM, own)
        : costGrosze(item.totalKg, own);
  }
  if (listPricePerKg != null &&
      listPricePerKg.isFinite &&
      listPricePerKg >= 0) {
    return costGrosze(item.totalKg, listPricePerKg);
  }
  return null;
}

/// Lista materiałowa z ceną i zapasem.
class SteelOrder {
  final List<SteelItem> items;

  /// Cena stali [zł/kg] dla pozycji bez własnej ceny (null = brak).
  final double? pricePerKg;

  /// Zapas na odpady / cięcie [%] doliczany do zamówienia.
  final double wastePct;

  const SteelOrder({
    this.items = const [],
    this.pricePerKg,
    this.wastePct = 5,
  });

  SteelOrder copyWith({
    List<SteelItem>? items,
    double? pricePerKg,
    bool clearPrice = false,
    double? wastePct,
  }) =>
      SteelOrder(
        items: items ?? this.items,
        pricePerKg: clearPrice ? null : (pricePerKg ?? this.pricePerKg),
        wastePct: wastePct ?? this.wastePct,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'items': [for (final i in items) i.toJson()],
        if (pricePerKg != null) 'priceKg': pricePerKg,
        'waste': wastePct,
      };

  static SteelOrder fromJson(Object? raw) {
    if (raw is! Map) return const SteelOrder();
    final list = raw['items'];
    final price = raw['priceKg'];
    final waste = raw['waste'];
    return SteelOrder(
      items: [
        if (list is List)
          for (final e in list.map(SteelItem.fromJson))
            if (e != null) e,
      ],
      pricePerKg: price is num ? price.toDouble() : null,
      wastePct: waste is num && waste >= 0 ? waste.toDouble() : 5,
    );
  }
}

/// Suma jednego profilu na liście („HEB 200: 18 m, 3 szt., 1 103 kg").
class SteelOrderGroup {
  final String label;
  final SteelShape shape;
  final int pieces;
  final double lengthM;
  final double kg;

  /// Blachy: powierzchnia arkuszy [m²]; inne: 0.
  final double areaM2;

  const SteelOrderGroup({
    required this.label,
    required this.shape,
    required this.pieces,
    required this.lengthM,
    required this.kg,
    required this.areaM2,
  });
}

class SteelOrderSummary {
  /// Grupy w kolejności pierwszego wystąpienia na liście.
  final List<SteelOrderGroup> groups;
  final double netKg;

  /// Masa do zamówienia — z zapasem.
  final double orderKg;
  final double wasteKg;
  final double totalLengthM;

  /// Koszt pozycji z ceną [gr] (null, gdy żadna nie ma ceny).
  final int? netGrosze;
  final int? wasteGrosze;
  final int? orderGrosze;

  /// Pozycje bez ceny (nie wchodzą do kosztu).
  final int unpricedItems;

  /// Malowanie [m²] dla pozycji, które mają powierzchnię.
  final double paintM2;

  /// Pozycje bez powierzchni malowania (np. UPN 50).
  final int unpaintedItems;

  const SteelOrderSummary({
    required this.groups,
    required this.netKg,
    required this.orderKg,
    required this.wasteKg,
    required this.totalLengthM,
    required this.netGrosze,
    required this.wasteGrosze,
    required this.orderGrosze,
    required this.unpricedItems,
    required this.paintM2,
    required this.unpaintedItems,
  });
}

SteelOrderSummary summarizeOrder(SteelOrder order, {bool english = false}) {
  final groups = <String, SteelOrderGroup>{};
  var netKg = 0.0;
  var lengthM = 0.0;
  var paint = 0.0;
  var unpainted = 0;
  var unpriced = 0;
  int? net;
  for (final item in order.items) {
    if (!item.isValid) continue;
    netKg += item.totalKg;
    if (item.shape.hasLength) lengthM += item.totalLengthM;
    final p = item.totalPaintM2;
    if (p == null) {
      unpainted++;
    } else {
      paint += p;
    }
    final cost = itemCostGrosze(item, order.pricePerKg);
    if (cost == null) {
      unpriced++;
    } else {
      net = (net ?? 0) + cost;
    }
    final prev = groups[item.groupKey];
    groups[item.groupKey] = SteelOrderGroup(
      label: item.label(english: english),
      shape: item.shape,
      pieces: (prev?.pieces ?? 0) + item.count,
      lengthM: (prev?.lengthM ?? 0) + item.totalLengthM,
      kg: (prev?.kg ?? 0) + item.totalKg,
      areaM2: (prev?.areaM2 ?? 0) + item.plateAreaM2,
    );
  }
  final pct =
      order.wastePct.isFinite && order.wastePct > 0 ? order.wastePct : 0.0;
  final wasteKg = netKg * pct / 100;
  final wasteGr = net == null ? null : percentOf(net, pct);
  return SteelOrderSummary(
    groups: groups.values.toList(growable: false),
    netKg: netKg,
    orderKg: netKg + wasteKg,
    wasteKg: wasteKg,
    totalLengthM: lengthM,
    netGrosze: net,
    wasteGrosze: wasteGr,
    orderGrosze: net == null ? null : net + wasteGr!,
    unpricedItems: unpriced,
    paintM2: paint,
    unpaintedItems: unpainted,
  );
}

// ─── Formatowanie ───────────────────────────────────────────────────────────

/// Wymiar w mm bez zbędnych zer, przecinek dziesiętny: 6.3 → „6,3", 100 → „100".
String fmtDim(double v) {
  if (!v.isFinite) return '—';
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}

/// Liczba z [decimals] miejscami, spacją (twardą) co trzy cyfry i
/// przecinkiem (PL) albo kropką (EN): 1234.5 → „1 234,5".
String fmtNum(double v, {int decimals = 1, bool english = false}) {
  if (!v.isFinite) return '—';
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('\u00a0');
    buf.write(digits[i]);
  }
  final frac = parts.length > 1 ? '${english ? '.' : ','}${parts[1]}' : '';
  return '${neg ? '−' : ''}$buf$frac';
}

/// Masa w kg z dokładnością dopasowaną do wielkości: 0,88 / 22,4 / 1 234.
String fmtKg(double kg, {bool english = false}) {
  final a = kg.abs();
  final decimals = a < 10 ? 2 : (a < 1000 ? 1 : 0);
  return fmtNum(kg, decimals: decimals, english: english);
}
