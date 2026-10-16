// Równoważniki chromu i niklu wg Schaefflera oraz skład stopiwa z
// rozcieńczeniem. Czysty Dart.
//
//   Cr_eq = Cr + Mo + 1,5·Si + 0,5·Nb
//   Ni_eq = Ni + 30·C + 0,5·Mn
//
// (A. L. Schaeffler, „Constitution diagram for stainless steel weld metal”,
// Metal Progress 56 (1949) 680 — równoważniki użyte na osiach wykresu.)
//
// Stopiwo to mieszanina spoiwa i stopionego materiału rodzimego:
//
//   skład = (1 − D)·spoiwo + D·(s·A + (1 − s)·B)
//
// D — rozcieńczenie (udział materiału rodzimego w spoinie), s — udział
// materiału A w stopionym materiale rodzimym. Równoważniki są liniowe w
// składzie, więc Cr_eq stopiwa = ta sama mieszanina Cr_eq składników.
//
// CZEGO TU NIE MA — świadomie: granic obszarów wykresu (A, A+F, F, M…).
// Nie mamy zweryfikowanych współrzędnych linii wykresu, a zgadywanie granic
// dałoby fałszywą „ocenę”. Aplikacja podaje równoważniki; punkt na wykres
// nanosi technolog. Schaeffler nie uwzględnia azotu — przy dupleksie
// technolog sięga zwykle po wykres WRC-1992.

/// Skład chemiczny w % masowych — tylko pierwiastki z równoważników.
class WeldComposition {
  final double c;
  final double si;
  final double mn;
  final double cr;
  final double mo;
  final double ni;
  final double nb;

  const WeldComposition({
    this.c = 0,
    this.si = 0,
    this.mn = 0,
    this.cr = 0,
    this.mo = 0,
    this.ni = 0,
    this.nb = 0,
  });

  List<double> get _all => [c, si, mn, cr, mo, ni, nb];

  /// Każda zawartość w 0–100 % i suma ≤ 100 %.
  bool get isValid {
    final all = _all;
    if (all.any((v) => !v.isFinite || v < 0 || v > 100)) return false;
    return all.fold<double>(0, (s, v) => s + v) <= 100 + 1e-9;
  }

  double get crEq => cr + mo + 1.5 * si + 0.5 * nb;
  double get niEq => ni + 30 * c + 0.5 * mn;

  WeldComposition _scaled(double k) => WeldComposition(
        c: c * k,
        si: si * k,
        mn: mn * k,
        cr: cr * k,
        mo: mo * k,
        ni: ni * k,
        nb: nb * k,
      );

  WeldComposition _plus(WeldComposition o) => WeldComposition(
        c: c + o.c,
        si: si + o.si,
        mn: mn + o.mn,
        cr: cr + o.cr,
        mo: mo + o.mo,
        ni: ni + o.ni,
        nb: nb + o.nb,
      );
}

/// Para równoważników jednego składu.
class SchaefflerPoint {
  final double crEq;
  final double niEq;
  const SchaefflerPoint(this.crEq, this.niEq);

  factory SchaefflerPoint.of(WeldComposition x) =>
      SchaefflerPoint(x.crEq, x.niEq);
}

/// Skład stopiwa: [dilution] i [shareA] jako ułamki 0–1. `null`, gdy któryś
/// skład albo ułamek jest poza zakresem.
WeldComposition? weldMetalComposition({
  required WeldComposition filler,
  required WeldComposition baseA,
  required WeldComposition baseB,
  required double dilution,
  double shareA = 0.5,
}) {
  if (!filler.isValid || !baseA.isValid || !baseB.isValid) return null;
  if (!dilution.isFinite || dilution < 0 || dilution > 1) return null;
  if (!shareA.isFinite || shareA < 0 || shareA > 1) return null;
  final base = baseA._scaled(shareA)._plus(baseB._scaled(1 - shareA));
  return filler._scaled(1 - dilution)._plus(base._scaled(dilution));
}
