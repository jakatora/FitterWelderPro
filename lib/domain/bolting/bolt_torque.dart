/// Moment dokręcania śrub kołnierzowych — czysta arytmetyka, bez UI.
///
/// Wydzielone z `bolt_torque_screen.dart`, żeby liczby dało się sprawdzić
/// tabelarycznie (`test/domain/bolting/bolt_torque_test.dart`).
///
/// Model (podejście ASME PCC-1, moment z siły napięcia wstępnego):
///   F   = frac · SMYS · A_s               [N]   (MPa · mm²)
///   T   = K · F · d                        [N·m] (d w metrach)
///   A_s = 0,7854 · (d − 0,9743/n)²         [in²] — ASME B1.1, pole przekroju
///         czynnego gwintu calowego UN; d = średnica nominalna [in],
///         n = liczba zwojów na cal.
///
/// Poprzednia wersja ekranu liczyła A_s wzorem metrycznym ISO 898-1
/// (d − 0,9382·p) i dla śrub > 1" brała skok z szeregu UNC. ASME B16.5 wymaga
/// dla śrub dwustronnych gwintu UNC-2A do 1" włącznie, a powyżej 1" szeregu
/// 8UN-2A (8 zw./cal) — stąd [kFlangeBoltSizes].
///
/// Uwaga (do weryfikacji, nie zmienione): ASME B1.1 podaje ten wzór na A_s dla
/// stali o Rm ≤ 100 ksi; dla wyższych wytrzymałości (np. A193 B7, Rm 125 ksi)
/// norma przewiduje osobny wzór oparty na min. średnicy podziałowej. W praktyce
/// kołnierzowej (tabele B16.5/PCC-1) używa się wzoru 0,7854·(d − 0,9743/n)².
library;

/// 1 in = 25,4 mm (definicja), więc 1 in² = 645,16 mm².
const double kMmPerInch = 25.4;

/// N·m na 1 ft·lbf. 1 ft·lbf = 1,3558179 N·m; ekran od zawsze dzielił przez
/// 1,3558 i tak zostaje, żeby ft·lb na karcie i w udostępnionej notatce były
/// liczone jednym przelicznikiem.
const double kNmPerFtLb = 1.3558;

/// Jeden rozmiar śruby kołnierzowej wraz z szeregiem gwintu.
class FlangeBoltSize {
  /// Etykieta jak w katalogu kołnierzy (`flange_catalog.dart`), np. `1-1/8`.
  final String label;

  /// Średnica nominalna w calach.
  final double diameterIn;

  /// Liczba zwojów na cal.
  final int threadsPerInch;

  /// `UNC` albo `8UN`.
  final String series;

  const FlangeBoltSize(
    this.label,
    this.diameterIn,
    this.threadsPerInch,
    this.series,
  );

  /// Średnica nominalna w milimetrach (dokładnie: cale × 25,4).
  double get diameterMm => diameterIn * kMmPerInch;

  /// Oznaczenie gwintu, np. `5/8"-11 UNC`, `1-1/2"-8 UN`.
  String get threadDesignation =>
      '$label"-$threadsPerInch ${series == '8UN' ? 'UN' : series}';
}

/// Śruby kołnierzowe 1/2"…2" z gwintem wg ASME B16.5:
/// UNC-2A do 1" włącznie, 8UN-2A powyżej 1".
const List<FlangeBoltSize> kFlangeBoltSizes = [
  FlangeBoltSize('1/2', 0.5, 13, 'UNC'),
  FlangeBoltSize('5/8', 0.625, 11, 'UNC'),
  FlangeBoltSize('3/4', 0.75, 10, 'UNC'),
  FlangeBoltSize('7/8', 0.875, 9, 'UNC'),
  FlangeBoltSize('1', 1.0, 8, 'UNC'),
  FlangeBoltSize('1-1/8', 1.125, 8, '8UN'),
  FlangeBoltSize('1-1/4', 1.25, 8, '8UN'),
  FlangeBoltSize('1-3/8', 1.375, 8, '8UN'),
  FlangeBoltSize('1-1/2', 1.5, 8, '8UN'),
  FlangeBoltSize('1-5/8', 1.625, 8, '8UN'),
  FlangeBoltSize('1-3/4', 1.75, 8, '8UN'),
  FlangeBoltSize('1-7/8', 1.875, 8, '8UN'),
  FlangeBoltSize('2', 2.0, 8, '8UN'),
];

/// Rozmiar po etykiecie albo `null`, gdy go nie ma w [kFlangeBoltSizes].
FlangeBoltSize? flangeBoltSize(String label) {
  for (final s in kFlangeBoltSizes) {
    if (s.label == label) return s;
  }
  return null;
}

/// Pole przekroju czynnego gwintu UN wg ASME B1.1 [in²]:
/// A_s = 0,7854 · (d − 0,9743/n)².
double tensileStressAreaIn2(double diameterIn, int threadsPerInch) {
  if (!(diameterIn > 0) || !diameterIn.isFinite) {
    throw ArgumentError.value(diameterIn, 'diameterIn', 'musi być > 0');
  }
  if (threadsPerInch <= 0) {
    throw ArgumentError.value(threadsPerInch, 'threadsPerInch', 'musi być > 0');
  }
  final dEff = diameterIn - 0.9743 / threadsPerInch;
  if (dEff <= 0) {
    throw ArgumentError('d = $diameterIn in za małe dla $threadsPerInch zw./cal');
  }
  return 0.7854 * dEff * dEff;
}

/// [tensileStressAreaIn2] w mm².
double tensileStressAreaMm2(FlangeBoltSize size) =>
    tensileStressAreaIn2(size.diameterIn, size.threadsPerInch) *
    kMmPerInch *
    kMmPerInch;

/// Wynik obliczenia momentu dla jednej śruby.
class BoltTorqueResult {
  final double stressAreaMm2;
  final double preloadN;
  final double torqueNm;

  const BoltTorqueResult({
    required this.stressAreaMm2,
    required this.preloadN,
    required this.torqueNm,
  });

  double get torqueFtLb => torqueNm / kNmPerFtLb;
  double get preloadKN => preloadN / 1000.0;
}

/// T = K · F · d, F = frac · SMYS · A_s.
///
/// [smysMpa] — minimalna granica plastyczności śruby [MPa],
/// [nutFactor] — współczynnik K (zależny od smaru),
/// [preloadFraction] — docelowy ułamek SMYS (0 < frac ≤ 1).
BoltTorqueResult boltTorque({
  required FlangeBoltSize size,
  required double smysMpa,
  required double nutFactor,
  required double preloadFraction,
}) {
  if (!(smysMpa > 0) || !smysMpa.isFinite) {
    throw ArgumentError.value(smysMpa, 'smysMpa', 'musi być > 0');
  }
  if (!(nutFactor > 0) || nutFactor >= 1 || !nutFactor.isFinite) {
    throw ArgumentError.value(nutFactor, 'nutFactor', 'oczekiwane 0 < K < 1');
  }
  if (!(preloadFraction > 0) || preloadFraction > 1) {
    throw ArgumentError.value(
        preloadFraction, 'preloadFraction', 'oczekiwane 0 < frac ≤ 1');
  }
  final asMm2 = tensileStressAreaMm2(size);
  final fN = smysMpa * preloadFraction * asMm2;
  final tNm = nutFactor * fN * (size.diameterMm / 1000.0);
  return BoltTorqueResult(stressAreaMm2: asMm2, preloadN: fN, torqueNm: tNm);
}
