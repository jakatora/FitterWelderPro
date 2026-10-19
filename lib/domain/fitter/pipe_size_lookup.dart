// Rozmiary rur: DN / NPS → średnica zewnętrzna (OD), z serią wymiarową.
//
// Jedyne źródło liczb dla pytań „jaka średnica DN40" — ta sama tabela co
// ekran „DN ↔ mm" (lib/data/nps_dn_od_r.dart). Asystent nie ma własnych
// tabel: woła te funkcje.
//
// Seria główna DN: ASME + EN seria 1 → ASME → EN seria 1 → pierwsza w tabeli.
// Nieznany rozmiar → null / pusta lista (nie zgadujemy „najbliższego").

import '../../data/nps_dn_od_r.dart';

/// Źródło liczb DN → OD (normy wymiarowe rur, NIE ISO 6708 — ta definiuje
/// tylko samo oznaczenie DN).
const String kDnOdSourcePl = 'EN 10220 / ISO 4200 seria 1, ASME B36.10M';
const String kDnOdSourceEn = 'EN 10220 / ISO 4200 series 1, ASME B36.10M';

/// Jedna średnica zewnętrzna danego DN i seria, do której należy.
class OdOption {
  const OdOption(this.odMm, this.series);
  final double odMm;
  final OdSeries series;

  @override
  bool operator ==(Object other) =>
      other is OdOption && other.odMm == odMm && other.series == series;

  @override
  int get hashCode => Object.hash(odMm, series);

  @override
  String toString() => 'OdOption($odMm, ${series.name})';
}

/// Kolejność serii: główna (ASME/EN 1) najpierw, potem europejskie 1–3,
/// na końcu „inne" (sprawdź kartę wyrobu).
const List<OdSeries> _seriesOrder = [
  OdSeries.asmeAndEn1,
  OdSeries.asme,
  OdSeries.en1,
  OdSeries.en2,
  OdSeries.en3,
  OdSeries.other,
];

/// Wszystkie OD danego DN: seria główna pierwsza, dalej wg [_seriesOrder],
/// a w obrębie serii w kolejności tabeli. DN40 → [48,3 asmeAndEn1, 44,5 en3].
/// Nieznane DN → pusta lista.
List<OdOption> odSeriesForDn(int dn) {
  final rows = [for (final r in kNpsTable) if (r.dn == dn) r];
  if (rows.isEmpty) return const [];
  final sorted = [...rows]..sort((a, b) {
      final s = _seriesOrder
          .indexOf(a.series)
          .compareTo(_seriesOrder.indexOf(b.series));
      if (s != 0) return s;
      return kNpsTable.indexOf(a).compareTo(kNpsTable.indexOf(b));
    });
  return [for (final r in sorted) OdOption(r.odMm, r.series)];
}

/// OD serii głównej DN (ASME + EN 1 → ASME → EN 1 → pierwsza) albo null.
double? odForDn(int dn) {
  final s = odSeriesForDn(dn);
  return s.isEmpty ? null : s.first.odMm;
}

/// Rozmiar NPS w calach z zapisu tabeli („1 1/4"" = 1,25, „2"" = 2) albo null.
double? npsInchesOf(String nps) {
  final m = RegExp(r'^(?:(\d+)\s+)?(?:(\d+)/(\d+)|(\d+))"$').firstMatch(nps);
  if (m == null) return null;
  if (m[4] != null) return double.parse(m[4]!);
  final whole = m[1] == null ? 0 : int.parse(m[1]!);
  return whole + int.parse(m[2]!) / int.parse(m[3]!);
}

bool _sameInches(String nps, double inches) {
  final n = npsInchesOf(nps);
  return n != null && (n - inches).abs() <= 1e-6;
}

/// NPS (cale) → OD wg ASME B36.10M (wiersz ASME albo ASME + EN seria 1).
/// Rozmiar spoza tabeli → null (nie zgadujemy).
double? odForNps(double inches) {
  for (final r in kNpsTable) {
    if (!_sameInches(r.nps, inches)) continue;
    if (r.series == OdSeries.asmeAndEn1 || r.series == OdSeries.asme) {
      return r.odMm;
    }
  }
  return null;
}

/// NPS (cale) → DN albo null (rozmiar spoza tabeli).
int? dnForNps(double inches) {
  for (final r in kNpsTable) {
    if (_sameInches(r.nps, inches)) return r.dn;
  }
  return null;
}

/// DN → zapis NPS z tabeli („1 1/2"") albo null.
String? npsForDn(int dn) {
  for (final r in kNpsTable) {
    if (r.dn == dn) return r.nps;
  }
  return null;
}

/// Wszystkie DN z tabeli, rosnąco i bez powtórzeń.
List<int> get knownDns {
  final out = <int>{for (final r in kNpsTable) r.dn}.toList()..sort();
  return out;
}
