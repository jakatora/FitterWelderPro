import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/help_button.dart';

/// Skąd był mierzony wymiar (dotyczy obu boków)
enum _RefType { inner, center, outer }

class RouteMeasureScreen extends StatefulWidget {
  const RouteMeasureScreen({super.key});

  @override
  State<RouteMeasureScreen> createState() => _RouteMeasureScreenState();
}

class _RouteMeasureScreenState extends State<RouteMeasureScreen> {
  // ── pola wejściowe ─────────────────────────────────────────────────────────
  final _longCtrl   = TextEditingController(); // bok długi  (a)
  final _shortCtrl  = TextEditingController(); // bok krótki (b)
  final _odCtrl     = TextEditingController(); // OD rury
  final _elbowCtrl  = TextEditingController(); // wymiar kolanka do osi (jeden dla obu)

  _RefType _refType = _RefType.center;

  // ── wyniki ─────────────────────────────────────────────────────────────────
  double? _a;      // bok długi C-C
  double? _b;      // bok krótki C-C
  double? _c;      // skos (przekątna) C-C
  double? _alpha;  // kąt naprzeciw boku długiego
  double? _beta;   // kąt naprzeciw boku krótkiego
  double? _cutA;   // cięcie rury A
  double? _cutB;   // cięcie rury B
  String? _error;

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // Korekcja na jeden wymiar: wew. → +OD/2, oś → 0, zew. → -OD/2
  double _corr(double od) {
    switch (_refType) {
      case _RefType.inner:  return  od / 2.0;
      case _RefType.center: return  0.0;
      case _RefType.outer:  return -od / 2.0;
    }
  }

  void _recalc() {
    final aRaw = _parse(_longCtrl.text);
    final bRaw = _parse(_shortCtrl.text);
    final od   = _parse(_odCtrl.text);
    final eA   = _parse(_elbowCtrl.text);
    final eB   = eA;

    if (aRaw <= 0 && bRaw <= 0) {
      setState(() {
        _a = _b = _c = _alpha = _beta = _cutA = _cutB = null;
        _error = null;
      });
      return;
    }

    // korekcja każdego boku: dodajemy/odejmujemy OD/2 z każdej strony
    final corr = _corr(od);
    final a = aRaw > 0 ? aRaw + 2 * corr : null; // oba końce boku korygowane
    final b = bRaw > 0 ? bRaw + 2 * corr : null;

    String? err;
    if (a != null && a <= 0) err = context.tr(
      pl: 'Bok długi po korekcji ≤ 0',
      en: 'Long side after correction ≤ 0',
    );
    if (b != null && b <= 0) err = context.tr(
      pl: 'Bok krótki po korekcji ≤ 0',
      en: 'Short side after correction ≤ 0',
    );

    double? c, alpha, beta;
    if (a != null && a > 0 && b != null && b > 0 && err == null) {
      c     = math.sqrt(a * a + b * b);
      alpha = math.atan2(b, a) * 180.0 / math.pi; // kąt przy boku długim
      beta  = 90.0 - alpha;
    }

    final cutA = (a != null && a > 0 && eA > 0) ? a - 2 * eA : null;
    final cutB = (b != null && b > 0 && eB > 0) ? b - 2 * eB : null;

    setState(() {
      _a     = (a != null && a > 0) ? a : null;
      _b     = (b != null && b > 0) ? b : null;
      _c     = c;
      _alpha = alpha;
      _beta  = beta;
      _cutA  = cutA;
      _cutB  = cutB;
      _error = err;
    });
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_longCtrl, _shortCtrl, _odCtrl, _elbowCtrl]) {
      c.addListener(_recalc);
    }
  }

  @override
  void dispose() {
    for (final c in [_longCtrl, _shortCtrl, _odCtrl, _elbowCtrl]) {
      c.removeListener(_recalc);
      c.dispose();
    }
    super.dispose();
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
          pl: 'Pomiar trasy',
          en: 'Route measurement',
        )),
        actions: [HelpButton(help: kHelpRouteMeasure)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 1. Wymiary boków ───────────────────────────────────────────
            _sectionLabel(context.tr(
              pl: '1. WYMIARY BOKÓW',
              en: '1. SIDE DIMENSIONS',
            )),
            const SizedBox(height: 10),
            _field(_longCtrl,
              label: context.tr(pl: 'Bok długi', en: 'Long side'),
              suffix: 'mm',
            ),
            const SizedBox(height: 10),
            _field(_shortCtrl,
              label: context.tr(pl: 'Bok krótki', en: 'Short side'),
              suffix: 'mm',
            ),
            const SizedBox(height: 24),

            // ── 2. Korekcja pomiaru ────────────────────────────────────────
            _sectionLabel(context.tr(
              pl: '2. KOREKCJA POMIARU',
              en: '2. MEASUREMENT CORRECTION',
            )),
            const SizedBox(height: 6),
            Text(
              context.tr(
                pl: 'Jak przyłożona była taśma miernicza do rury?',
                en: 'How was the tape measure applied to the pipe?',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _refSelector(cs),
            const SizedBox(height: 10),
            _field(_odCtrl,
              label: context.tr(
                pl: 'Zewnętrzna średnica rury OD',
                en: 'Pipe outer diameter OD',
              ),
              suffix: 'mm',
            ),
            const SizedBox(height: 8),
            _corrPreview(cs),
            const SizedBox(height: 24),

            // ── 3. Wyniki ──────────────────────────────────────────────────
            _sectionLabel(context.tr(pl: '3. WYNIKI', en: '3. RESULTS')),
            const SizedBox(height: 12),

            Row(children: [
              Expanded(child: _bigTile(
                label: context.tr(pl: 'Bok długi C-C', en: 'Long side C-C'),
                value: _a, cs: cs,
              )),
              const SizedBox(width: 10),
              Expanded(child: _bigTile(
                label: context.tr(pl: 'Bok krótki C-C', en: 'Short side C-C'),
                value: _b, cs: cs,
              )),
            ]),
            const SizedBox(height: 10),

            _infoTile(
              icon: Icons.straighten,
              label: context.tr(pl: 'Skos (przekątna) C-C', en: 'Diagonal C-C'),
              value: _c != null ? '${_c!.toStringAsFixed(1)} mm' : '—',
              cs: cs,
            ),
            const SizedBox(height: 10),

            Row(children: [
              Expanded(child: _infoTile(
                icon: Icons.rotate_right,
                label: context.tr(pl: 'Kąt α (przy boku długim)', en: 'Angle α (at long side)'),
                value: _alpha != null ? '${_alpha!.toStringAsFixed(2)}°' : '—',
                cs: cs,
              )),
              const SizedBox(width: 10),
              Expanded(child: _infoTile(
                icon: Icons.rotate_left,
                label: context.tr(pl: 'Kąt β (przy boku krótkim)', en: 'Angle β (at short side)'),
                value: _beta != null ? '${_beta!.toStringAsFixed(2)}°' : '—',
                cs: cs,
              )),
            ]),

            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBox(_error!, cs),
            ],

            const SizedBox(height: 28),

            // ── 4. Obliczanie cięcia rur ───────────────────────────────────
            _sectionLabel(context.tr(
              pl: '4. OBLICZANIE CIĘCIA RUR',
              en: '4. PIPE CUT LENGTHS',
            )),
            const SizedBox(height: 6),
            Text(
              context.tr(
                pl: 'Cięcie = bok C-C − kolanka − kolanka',
                en: 'Cut = side C-C − elbow − elbow',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _field(_elbowCtrl,
              label: context.tr(
                pl: 'Wymiar kolanka do osi',
                en: 'Elbow centre-to-end',
              ),
              suffix: 'mm',
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _cutTile(
                label: context.tr(pl: 'Cięcie rury A (długa)', en: 'Pipe A cut (long)'),
                value: _cutA, cs: cs,
              )),
              const SizedBox(width: 10),
              Expanded(child: _cutTile(
                label: context.tr(pl: 'Cięcie rury B (krótka)', en: 'Pipe B cut (short)'),
                value: _cutB, cs: cs,
              )),
            ]),

            const SizedBox(height: 28),
            _diagram(cs),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── widgety pomocnicze ─────────────────────────────────────────────────────

  Widget _refSelector(ColorScheme cs) {
    final opts = [
      (
        _RefType.inner,
        context.tr(pl: 'Od wew.\nścianki', en: 'From inner\nwall'),
        '+OD/2',
      ),
      (
        _RefType.center,
        context.tr(pl: 'Od osi\nrury', en: 'From pipe\naxis'),
        '0',
      ),
      (
        _RefType.outer,
        context.tr(pl: 'Od zew.\nścianki', en: 'From outer\nwall'),
        '−OD/2',
      ),
    ];

    return Row(
      children: opts.map((opt) {
        final sel = _refType == opt.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () { setState(() => _refType = opt.$1); _recalc(); },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: sel ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? cs.primary : cs.outlineVariant,
                    width: sel ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  Text(opt.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12,
                      color: sel ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(opt.$3,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: sel ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _corrPreview(ColorScheme cs) {
    final aRaw = _parse(_longCtrl.text);
    final bRaw = _parse(_shortCtrl.text);
    final od   = _parse(_odCtrl.text);
    if ((aRaw <= 0 && bRaw <= 0) || _refType == _RefType.center) {
      return const SizedBox.shrink();
    }
    final corr  = _corr(od);
    final total = 2 * corr;
    final sign  = total >= 0 ? '+' : '';
    final lines = <String>[];
    if (aRaw > 0) {
      lines.add('A: ${aRaw.toStringAsFixed(1)} $sign${total.toStringAsFixed(1)} = ${(aRaw + total).toStringAsFixed(1)} mm');
    }
    if (bRaw > 0) {
      lines.add('B: ${bRaw.toStringAsFixed(1)} $sign${total.toStringAsFixed(1)} = ${(bRaw + total).toStringAsFixed(1)} mm');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        lines.join('\n'),
        style: TextStyle(
          fontFamily: 'monospace', fontSize: 13,
          fontWeight: FontWeight.bold,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _bigTile({
    required String label,
    required double? value,
    required ColorScheme cs,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 11,
              color: cs.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value != null ? '${value.toStringAsFixed(1)} mm' : '—',
            style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.bold,
              color: cs.onTertiaryContainer, letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme cs,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text(value, style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface,
            )),
          ],
        )),
      ]),
    );
  }

  Widget _cutTile({
    required String label,
    required double? value,
    required ColorScheme cs,
  }) {
    final isNeg = value != null && value < 0;
    final bg = isNeg ? cs.errorContainer : cs.primaryContainer;
    final fg = isNeg ? cs.onErrorContainer : cs.onPrimaryContainer;

    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Icon(isNeg ? Icons.warning_amber_rounded : Icons.cut, color: fg, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: fg)),
            Text(
              value != null ? '${value.toStringAsFixed(1)} mm' : '—',
              style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold,
                color: fg, letterSpacing: -0.5,
              ),
            ),
            if (isNeg)
              Text(
                context.tr(
                  pl: 'Kolanka za duże — sprawdź wymiary',
                  en: 'Elbows too large — check dimensions',
                ),
                style: TextStyle(fontSize: 11, color: fg),
              ),
          ],
        )),
      ]),
    );
  }

  Widget _errorBox(String msg, ColorScheme cs) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cs.errorContainer, borderRadius: BorderRadius.circular(8),
    ),
    child: Row(children: [
      Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(msg,
        style: TextStyle(
          color: cs.onErrorContainer,
          fontWeight: FontWeight.bold, fontSize: 13,
        ))),
    ]),
  );

  Widget _diagram(ColorScheme cs) {
    final aStr = _a != null ? '${_a!.toStringAsFixed(1)} mm' : 'a';
    final bStr = _b != null ? '${_b!.toStringAsFixed(1)} mm' : 'b';
    final cStr = _c != null ? '${_c!.toStringAsFixed(1)} mm' : 'c';
    final alphaStr = _alpha != null ? '${_alpha!.toStringAsFixed(1)}°' : 'α';
    final betaStr = _beta  != null ? '${_beta!.toStringAsFixed(1)}°'  : 'β';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(pl: 'Schemat trasy', en: 'Route diagram'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            '*\n'
            '|  \\\n'
            '|    \\  $cStr (skos)\n'
            '| $betaStr \\\n'
            '|        \\\n'
            '+-- $alphaStr --*\n'
            '\n'
            '↕ $bStr (bok krótki B)\n'
            '↔ $aStr (bok długi A)',
            style: TextStyle(
              fontFamily: 'monospace', fontSize: 13,
              height: 1.75, color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.bold, letterSpacing: 0.4, fontSize: 13,
    ),
  );

  Widget _field(
    TextEditingController ctrl, {
    required String label,
    String? suffix,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
