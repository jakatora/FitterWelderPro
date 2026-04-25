import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

/// Skąd był mierzony wymiar po skosie
enum _RefType { inner, center, outer }

/// Który parametr trójkąta znamy (poza przekątną)
enum _Mode { angle, horizontal, vertical }

class RouteMeasureScreen extends StatefulWidget {
  const RouteMeasureScreen({super.key});

  @override
  State<RouteMeasureScreen> createState() => _RouteMeasureScreenState();
}

class _RouteMeasureScreenState extends State<RouteMeasureScreen> {
  // ── kontrolery ─────────────────────────────────────────────────────────────
  final _hypCtrl    = TextEditingController(); // zmierzony skos
  final _odCtrl     = TextEditingController(); // OD rury
  final _inputCtrl  = TextEditingController(); // kąt lub bok a lub bok b
  final _elbowACtrl = TextEditingController(); // wymiar kolanka do osi – bok a
  final _elbowBCtrl = TextEditingController(); // wymiar kolanka do osi – bok b

  _RefType _refType = _RefType.center;
  _Mode    _mode    = _Mode.angle;

  // ── wyniki ─────────────────────────────────────────────────────────────────
  double? _ccc;   // skos oś-oś po korekcji
  double? _a;     // bok poziomy
  double? _b;     // bok pionowy
  double? _alpha; // kąt α
  double? _beta;  // kąt β
  double? _cutA;  // wymiar cięcia rury A
  double? _cutB;  // wymiar cięcia rury B
  String? _error;

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // ── korekcja ───────────────────────────────────────────────────────────────
  // Wewnętrzna: taśma przy wew. ściance rury → dodajemy OD/2 z każdej strony = +OD
  // Oś:        taśma do osi → brak korekcji = 0
  // Zewnętrzna: taśma przy zew. ściance rury → odejmujemy OD/2 z każdej strony = -OD
  double _correction(double od) {
    switch (_refType) {
      case _RefType.inner:  return  od;
      case _RefType.center: return  0.0;
      case _RefType.outer:  return -od;
    }
  }

  void _recalc() {
    final c     = _parse(_hypCtrl.text);
    final od    = _parse(_odCtrl.text);
    final input = _parse(_inputCtrl.text);
    final eA    = _parse(_elbowACtrl.text);
    final eB    = _parse(_elbowBCtrl.text);

    if (c <= 0) {
      setState(() {
        _ccc = _a = _b = _alpha = _beta = _cutA = _cutB = null;
        _error = null;
      });
      return;
    }

    final ccc = c + _correction(od);
    if (ccc <= 0) {
      setState(() {
        _ccc = null;
        _a = _b = _alpha = _beta = _cutA = _cutB = null;
        _error = 'C-C ≤ 0 – sprawdź wymiar i średnicę';
      });
      return;
    }

    double? a, b, alpha;
    String? err;

    switch (_mode) {
      case _Mode.angle:
        if (input > 0 && input < 90) {
          final rad = input * math.pi / 180.0;
          a     = ccc * math.cos(rad);
          b     = ccc * math.sin(rad);
          alpha = input;
        }
        break;

      case _Mode.horizontal:
        if (input > 0 && input < ccc) {
          b     = math.sqrt(ccc * ccc - input * input);
          a     = input;
          alpha = math.acos(input / ccc) * 180.0 / math.pi;
        } else if (input >= ccc) {
          err = context.tr(
            pl: 'a ≥ c — bok poziomy musi być krótszy od skosu',
            en: 'a ≥ c — horizontal side must be shorter than hypotenuse',
          );
        }
        break;

      case _Mode.vertical:
        if (input > 0 && input < ccc) {
          a     = math.sqrt(ccc * ccc - input * input);
          b     = input;
          alpha = math.asin(input / ccc) * 180.0 / math.pi;
        } else if (input >= ccc) {
          err = context.tr(
            pl: 'b ≥ c — bok pionowy musi być krótszy od skosu',
            en: 'b ≥ c — vertical side must be shorter than hypotenuse',
          );
        }
        break;
    }

    // Wymiary cięcia: bok – kolanka po obu stronach
    final cutA = (a != null && eA > 0) ? a - 2 * eA : null;
    final cutB = (b != null && eB > 0) ? b - 2 * eB : null;

    setState(() {
      _ccc   = ccc;
      _a     = a;
      _b     = b;
      _alpha = alpha;
      _beta  = alpha != null ? 90.0 - alpha : null;
      _cutA  = cutA;
      _cutB  = cutB;
      _error = err;
    });
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_hypCtrl, _odCtrl, _inputCtrl, _elbowACtrl, _elbowBCtrl]) {
      c.addListener(_recalc);
    }
  }

  @override
  void dispose() {
    for (final c in [_hypCtrl, _odCtrl, _inputCtrl, _elbowACtrl, _elbowBCtrl]) {
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
          pl: 'Pomiar trasy – obliczanie boków',
          en: 'Route measurement – side calculation',
        )),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 1. Zmierzony skos ──────────────────────────────────────────
            _sectionLabel(context.tr(
              pl: '1. ZMIERZONY SKOS',
              en: '1. MEASURED DIAGONAL',
            )),
            const SizedBox(height: 10),
            _field(_hypCtrl,
              label: context.tr(pl: 'Wymiar po skosie c', en: 'Diagonal c'),
              suffix: 'mm'),
            const SizedBox(height: 24),

            // ── 2. Korekcja pomiaru ────────────────────────────────────────
            _sectionLabel(context.tr(
              pl: '2. KOREKCJA POMIARU',
              en: '2. MEASUREMENT CORRECTION',
            )),
            const SizedBox(height: 6),
            Text(
              context.tr(
                pl: 'Jak przyłożona była taśma miernicza?',
                en: 'How was the tape measure applied?',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _refSelector(cs),
            const SizedBox(height: 12),
            _field(_odCtrl,
              label: context.tr(pl: 'Zewnętrzna średnica rury OD', en: 'Pipe outer diameter OD'),
              suffix: 'mm'),
            const SizedBox(height: 8),
            _correctionNote(cs),
            const SizedBox(height: 24),

            // ── 3. Znany parametr ──────────────────────────────────────────
            _sectionLabel(context.tr(
              pl: '3. ZNANY PARAMETR TRÓJKĄTA',
              en: '3. KNOWN TRIANGLE PARAMETER',
            )),
            const SizedBox(height: 8),
            _modeSelector(cs),
            const SizedBox(height: 10),
            _modeInputField(),
            const SizedBox(height: 24),

            // ── 4. Wyniki ──────────────────────────────────────────────────
            _sectionLabel(context.tr(pl: '4. WYNIKI', en: '4. RESULTS')),
            const SizedBox(height: 12),

            _infoTile(
              icon: Icons.straighten,
              label: context.tr(pl: 'Skos oś-oś  c (po korekcji)', en: 'Diagonal C-C (corrected)'),
              value: _ccc != null ? '${_ccc!.toStringAsFixed(1)} mm' : '—',
              cs: cs, warm: false,
            ),
            const SizedBox(height: 10),

            _bigTile(
              label: context.tr(pl: 'Bok poziomy  a', en: 'Horizontal side  a'),
              value: _a, cs: cs,
            ),
            const SizedBox(height: 10),

            _bigTile(
              label: context.tr(pl: 'Bok pionowy  b', en: 'Vertical side  b'),
              value: _b, cs: cs,
            ),
            const SizedBox(height: 10),

            Row(children: [
              Expanded(child: _infoTile(
                icon: Icons.rotate_right,
                label: 'α',
                value: _alpha != null ? '${_alpha!.toStringAsFixed(2)}°' : '—',
                cs: cs, warm: false,
              )),
              const SizedBox(width: 10),
              Expanded(child: _infoTile(
                icon: Icons.rotate_left,
                label: 'β',
                value: _beta != null ? '${_beta!.toStringAsFixed(2)}°' : '—',
                cs: cs, warm: false,
              )),
            ]),

            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBox(_error!, cs),
            ],

            const SizedBox(height: 28),

            // ── 5. Obliczanie cięcia rur ───────────────────────────────────
            _sectionLabel(context.tr(
              pl: '5. OBLICZANIE CIĘCIA RUR',
              en: '5. PIPE CUT LENGTHS',
            )),
            const SizedBox(height: 6),
            Text(
              context.tr(
                pl: 'Cięcie = bok − kolanka_do_osi − kolanka_do_osi',
                en: 'Cut = side − elbow_c_to_e − elbow_c_to_e',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // Bok A
            Text(
              context.tr(pl: 'Rura A (bok poziomy a)', en: 'Pipe A (horizontal side a)'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            _field(_elbowACtrl,
              label: context.tr(
                pl: 'Wymiar kolanka do osi – rura A',
                en: 'Elbow centre-to-end – pipe A',
              ),
              suffix: 'mm'),
            const SizedBox(height: 8),
            _cutResultTile(
              label: context.tr(pl: 'Cięcie rury A', en: 'Pipe A cut length'),
              value: _cutA,
              cs: cs,
            ),
            const SizedBox(height: 20),

            // Bok B
            Text(
              context.tr(pl: 'Rura B (bok pionowy b)', en: 'Pipe B (vertical side b)'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            _field(_elbowBCtrl,
              label: context.tr(
                pl: 'Wymiar kolanka do osi – rura B',
                en: 'Elbow centre-to-end – pipe B',
              ),
              suffix: 'mm'),
            const SizedBox(height: 8),
            _cutResultTile(
              label: context.tr(pl: 'Cięcie rury B', en: 'Pipe B cut length'),
              value: _cutB,
              cs: cs,
            ),

            const SizedBox(height: 28),

            // ── schemat ────────────────────────────────────────────────────
            _diagram(cs),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Widgety ─────────────────────────────────────────────────────────────────

  Widget _refSelector(ColorScheme cs) {
    final opts = [
      (
        _RefType.inner,
        context.tr(pl: 'Od wewnętrznej\nścianki', en: 'From inner\nwall'),
        context.tr(pl: '+OD (dodaj średnicę)', en: '+OD (add diameter)'),
      ),
      (
        _RefType.center,
        context.tr(pl: 'Od osi rury', en: 'From pipe\naxis'),
        context.tr(pl: 'brak korekcji', en: 'no correction'),
      ),
      (
        _RefType.outer,
        context.tr(pl: 'Od zewnętrznej\nścianki', en: 'From outer\nwall'),
        context.tr(pl: '−OD (odejmij średnicę)', en: '−OD (subtract diameter)'),
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
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
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
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: sel ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(opt.$3,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: sel ? cs.primary : cs.onSurfaceVariant,
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

  Widget _correctionNote(ColorScheme cs) {
    if (_ccc == null && _parse(_hypCtrl.text) <= 0) return const SizedBox.shrink();
    final c   = _parse(_hypCtrl.text);
    final od  = _parse(_odCtrl.text);
    if (c <= 0) return const SizedBox.shrink();
    final corr = _correction(od);
    final sign = corr >= 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${c.toStringAsFixed(1)}  $sign${corr.toStringAsFixed(1)}  =  '
        '${(c + corr).toStringAsFixed(1)} mm  (C-C)',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _modeSelector(ColorScheme cs) {
    final modes = [
      (_Mode.angle,      context.tr(pl: 'Kąt α', en: 'Angle α')),
      (_Mode.horizontal, context.tr(pl: 'Bok poziomy a', en: 'Horiz. side a')),
      (_Mode.vertical,   context.tr(pl: 'Bok pionowy b',  en: 'Vert. side b')),
    ];
    return Row(
      children: modes.map((m) {
        final sel = _mode == m.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () {
                setState(() => _mode = m.$1);
                _inputCtrl.clear();
                _recalc();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: sel ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? cs.primary : cs.outlineVariant),
                ),
                child: Text(m.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: sel ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _modeInputField() {
    switch (_mode) {
      case _Mode.angle:
        return _field(_inputCtrl,
          label: context.tr(pl: 'Kąt α (stopnie)', en: 'Angle α (degrees)'),
          suffix: '°');
      case _Mode.horizontal:
        return _field(_inputCtrl,
          label: context.tr(pl: 'Bok poziomy a', en: 'Horizontal side a'),
          suffix: 'mm');
      case _Mode.vertical:
        return _field(_inputCtrl,
          label: context.tr(pl: 'Bok pionowy b', en: 'Vertical side b'),
          suffix: 'mm');
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 12,
              color: cs.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value != null ? '${value.toStringAsFixed(1)} mm' : '—',
            style: TextStyle(
              fontSize: 30, fontWeight: FontWeight.bold,
              color: cs.onTertiaryContainer, letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cutResultTile({
    required String label,
    required double? value,
    required ColorScheme cs,
  }) {
    final isNeg = value != null && value < 0;
    final bg = isNeg ? cs.errorContainer : cs.primaryContainer;
    final fg = isNeg ? cs.onErrorContainer : cs.onPrimaryContainer;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            isNeg ? Icons.warning_amber_rounded : Icons.cut,
            color: fg, size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: TextStyle(fontSize: 11, color: fg),
                ),
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
    required bool warm,
  }) {
    final bg   = warm ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg   = warm ? cs.onPrimaryContainer : cs.onSurface;
    final fgS  = warm ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(icon, size: 20, color: fgS),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: fgS)),
            Text(value,
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: fg,
              )),
          ],
        )),
      ]),
    );
  }

  Widget _errorBox(String msg, ColorScheme cs) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cs.errorContainer,
      borderRadius: BorderRadius.circular(8),
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
    final cStr = _ccc != null ? '${_ccc!.toStringAsFixed(1)} mm' : 'c (C-C)';
    final αStr = _alpha != null ? '${_alpha!.toStringAsFixed(1)}°' : 'α';
    final βStr = _beta  != null ? '${_beta!.toStringAsFixed(1)}°'  : 'β';

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
            context.tr(pl: 'Schemat trójkąta trasy', en: 'Route triangle diagram'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            '* ← [$bStr]\n'
            '|  \\\n'
            '|    \\  $cStr (skos C-C)\n'
            '| $βStr  \\\n'
            '|        \\\n'
            '+-- $αStr --*\n'
            '   [$aStr]',
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
    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.4, fontSize: 13),
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
