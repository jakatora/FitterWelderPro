/// Kod kolorów pasów EN 1492-1 (płaskie) i EN 1492-2 (okrągłe): kolor
/// podpowiada WLL przy podnoszeniu prostym. DECYDUJE ETYKIETA, NIE KOLOR —
/// pas bez etykiety (albo z nieczytelną) to STOP bez względu na kolor.
///
/// Wartości: DGUV Information 209-021 (08/2021) — fioletowy 1000 kg,
/// zielony 2000, żółty 3000, szary 4000, czerwony 5000, brązowy 6000,
/// niebieski 8000, pomarańczowy 10 000; wartości pośrednie (np. 1,5 t,
/// 2,5 t) nie mają koloru z normy. Pomarańczowy = 10 t i więcej (CERTEX,
/// Mennens, Dolezych: 10–40 t). Kolor etykiety mówi o materiale: niebieska
/// PES, zielona PA, brązowa PP — to nie jest kod nośności.
///
/// Czysty Dart.
library;

enum SlingColour {
  violet(1, 0xFF8E44AD, 'fioletowy', 'violet'),
  green(2, 0xFF2E9E4F, 'zielony', 'green'),
  yellow(3, 0xFFF4D03F, 'żółty', 'yellow'),
  grey(4, 0xFF95A5A6, 'szary', 'grey'),
  red(5, 0xFFD64541, 'czerwony', 'red'),
  brown(6, 0xFF8D5524, 'brązowy', 'brown'),
  blue(8, 0xFF2E86DE, 'niebieski', 'blue'),
  orange(10, 0xFFF39C12, 'pomarańczowy', 'orange'),

  /// Inny kolor (beżowy, biały, czarny…) — poza kodem normy.
  other(null, 0xFF5D6D7E, 'inny', 'other');

  const SlingColour(this.nominalT, this.argb, this.labelPl, this.labelEn);

  /// WLL z kodu kolorów [t] (dla pomarańczowego — DOLNA granica: 10 t
  /// i więcej). `null` — kolor spoza kodu.
  final double? nominalT;

  /// Kolor próbki na ekranie.
  final int argb;
  final String labelPl;
  final String labelEn;

  String label({required bool en}) => en ? labelEn : labelPl;

  /// Pomarańczowy obejmuje 10 t i więcej.
  bool get orAbove => this == orange;
}

/// Czy WLL z etykiety [kg] zgadza się z kolorem pasa. Kolor spoza kodu →
/// `null` (nie da się sprawdzić). Niezgodność = sygnał, że to może być inny
/// pas albo etykieta nie od tego pasa — decyduje etykieta.
bool? colourMatchesWll(SlingColour colour, double wllKg) {
  final t = colour.nominalT;
  if (t == null || !wllKg.isFinite || wllKg <= 0) return null;
  final nominalKg = t * 1000;
  if (colour.orAbove) return wllKg >= nominalKg;
  return (wllKg - nominalKg).abs() < 0.5;
}
