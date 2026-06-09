import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../services/orbital_tig.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

// P1-14: in-screen Help content — wired into AppBar via HelpButton so the
// welder can glance at what the calc actually estimates (Cunningham band per
// level, autogenous thin-wall assumption) without leaving the screen.
final _kHelpOrbital = ScreenHelp(
  titlePl: 'Orbital TIG — parametry startowe',
  titleEn: 'Orbital TIG — starting parameters',
  bodyPl:
      'Szacuje prąd na 4 poziomach orbity (płasko, w dół, w górę, pułapowo), '
      'prędkość obrotu, czas spoiny i energię liniową dla cienkościennej rury '
      'spawanej autogenicznie (bez drutu). Wartości startowe — produkcja zawsze wg WPS.',
  bodyEn:
      'Estimates current at 4 orbital levels (flat, down, up, overhead), '
      'travel speed, weld time and heat input for thin-wall autogenous tube '
      '(no filler). Starting values — production parameters always per the WPS.',
  stepsPl: [
    HelpStep('OD', 'Średnica zewnętrzna rury w mm (np. 25.4).'),
    HelpStep('t', 'Grubość ścianki w mm (np. 1.65). Musi być < OD/2.'),
    HelpStep('V', 'Napięcie łuku 6–20 V (typowo 8–12 V dla 316L).'),
    HelpStep('OK', 'Przed zajarzeniem: przedmuch gazem, O₂ < 50 ppm, fit-up ≈ 0.'),
  ],
  stepsEn: [
    HelpStep('OD', 'Tube outside diameter in mm (e.g. 25.4).'),
    HelpStep('t', 'Wall thickness in mm (e.g. 1.65). Must be < OD/2.'),
    HelpStep('V', 'Arc voltage 6–20 V (typically 8–12 V for 316L).'),
    HelpStep('OK', 'Before arc start: gas purge, O₂ < 50 ppm, fit-up ≈ 0.'),
  ],
);

/// Orbital TIG starting-parameter helper for thin-wall stainless tube.
class OrbitalTigScreen extends StatefulWidget {
  const OrbitalTigScreen({super.key});

  @override
  State<OrbitalTigScreen> createState() => _OrbitalTigScreenState();
}

class _OrbitalTigScreenState extends State<OrbitalTigScreen> {
  final _od = TextEditingController();
  final _wall = TextEditingController();
  final _volts = TextEditingController(text: '10');
  // Welder stamp / WPS ref — optional traceability tag stamped onto the
  // copied parameter string so a foreman receiving the paste knows WHO ran
  // the head and against WHICH procedure. Kept as one free-text field to
  // avoid adding rows the welder must tap through in gloves.
  final _trace = TextEditingController();

  OrbitalEstimate? _est;
  String? _error;
  // P1-30: per-field error surfacing — keeps the cross-field banner free for the
  // real-vs-impossible (wall > OD/2) error while parse / range complaints show
  // under the offending field.
  String? _odError;
  String? _wallError;
  String? _voltsError;
  // P1-19: debounce mid-typing recompute so a welder paging through 25.4 doesn't
  // see the wall>OD/2 banner flash for one frame while the digits are still
  // being keyed in. Also lets us key the recompute off the SETTLED text rather
  // than every single character.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _od.dispose();
    _wall.dispose();
    _volts.dispose();
    _trace.dispose();
    super.dispose();
  }

  double? _p(String s) =>
      s.trim().isEmpty ? null : double.tryParse(s.replaceAll(',', '.'));

  // P1-19: schedule a recompute ~150 ms after the last keystroke. If another
  // keystroke arrives the prior timer is cancelled — only the trailing edge
  // fires _calc.
  void _scheduleCalc() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _calc);
  }

  void _calc() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _est = null;
      _odError = null;
      _wallError = null;
      _voltsError = null;
      final odTxt = _od.text.trim();
      final wallTxt = _wall.text.trim();
      final voltsTxt = _volts.text.trim();
      final od = _p(odTxt);
      final wall = _p(wallTxt);
      // P1-30: if the user typed something in volts that doesn't parse OR is
      // out of the 6–20 V band we flag it and DO NOT silently fall through to
      // the 10 V default. Empty stays 10 V (label hint communicates the range).
      double v = 10;
      if (voltsTxt.isNotEmpty) {
        final parsed = _p(voltsTxt);
        if (parsed == null) {
          _voltsError = context.tr(
              pl: 'Sprawdź wartość', en: 'Check value');
        } else if (parsed < 0) {
          // P1-30: reject negative V (no negative voltage on a constant-current
          // power source for orbital TIG).
          _voltsError = context.tr(
              pl: 'Napięcie nie może być ujemne',
              en: 'Voltage cannot be negative');
        } else if (parsed < 6 || parsed > 20) {
          _voltsError = context.tr(
              pl: 'Sprawdź wartość (6–20 V)',
              en: 'Check value (6–20 V)');
        } else {
          v = parsed;
        }
      }
      // P1-30: OD sanity band 0 < OD ≤ 1000 mm — covers everything from
      // hypodermic-tube up to small-bore process pipe; anything beyond is a
      // typo, not a real orbital head.
      if (odTxt.isNotEmpty) {
        if (od == null) {
          _odError = context.tr(pl: 'Sprawdź wymiar', en: 'Check value');
        } else if (od < 0) {
          _odError = context.tr(
              pl: 'OD nie może być ujemne', en: 'OD cannot be negative');
        } else if (od == 0 || od > 1000) {
          _odError = context.tr(pl: 'Sprawdź wymiar', en: 'Check value');
        }
      }
      // P1-30: wall sanity band 0 < t ≤ 25 mm.
      if (wallTxt.isNotEmpty) {
        if (wall == null) {
          _wallError = context.tr(pl: 'Sprawdź wymiar', en: 'Check value');
        } else if (wall < 0) {
          _wallError = context.tr(
              pl: 'Ścianka nie może być ujemna',
              en: 'Wall cannot be negative');
        } else if (wall == 0 || wall > 25) {
          _wallError = context.tr(pl: 'Sprawdź wymiar', en: 'Check value');
        }
      }
      // P1-19: don't surface "fill these in" / "wall>OD/2" while the welder is
      // still typing into an empty field — bail out silently and let the next
      // debounce tick re-evaluate.
      if (odTxt.isEmpty || wallTxt.isEmpty) {
        return;
      }
      if (_odError != null || _wallError != null || _voltsError != null) {
        return;
      }
      if (od == null || od <= 0) {
        _error = context.tr(
            pl: 'Podaj średnicę zewnętrzną rury OD (mm)',
            en: 'Enter tube outside diameter OD (mm)');
        return;
      }
      if (wall == null || wall <= 0) {
        _error = context.tr(
            pl: 'Podaj grubość ścianki (mm)',
            en: 'Enter wall thickness (mm)');
        return;
      }
      // P1-19: cross-field "wall > OD/2" only fires when BOTH fields are
      // settled and non-empty (guarded above). No more mid-typing flash.
      if (wall > od / 2) {
        _error = context.tr(
            pl: 'Ścianka nie może być większa niż połowa OD',
            en: 'Wall cannot exceed half the OD');
        return;
      }
      _est = estimateOrbital(odMm: od, wallMm: wall, arcVolts: v);
    });
  }

  // P1-04: AppBar "Wyczyść" handler — wipes every input controller and the
  // computed estimate so the welder can start a fresh tube without manually
  // long-pressing each field in gloves. _volts is restored to the documented
  // default (10 V) so the next calc still has a sane fallback.
  void _clearAll() {
    _debounce?.cancel();
    _od.clear();
    _wall.clear();
    _trace.clear();
    _volts.text = '10';
    setState(() {
      _est = null;
      _error = null;
      _odError = null;
      _wallError = null;
      _voltsError = null;
    });
    debugPrint('[orbital] cleared inputs');
  }

  @override
  Widget build(BuildContext context) {
    final e = _est;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Orbital TIG — parametry', en: 'Orbital TIG — parameters')),
        actions: [
          // P1-04: explicit reset/clear-all so the welder doesn't have to
          // long-press every TextField between back-to-back tube setups.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
            onPressed: _clearAll,
          ),
          // P1-14: in-AppBar Help — surfaces the assumptions (autogenous,
          // thin-wall, starting values only) without leaving the screen.
          HelpButton(help: _kHelpOrbital),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          // ── DISCLAIMER ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kOrange.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Icon(Icons.warning_amber_rounded,
                      color: _kOrange, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    label: context.tr(pl: 'Ostrzeżenie', en: 'Warning'),
                    child: Text(
                      context.tr(
                        pl: 'Wartości STARTOWE do ustawienia kuponu próbnego. '
                            'Parametry produkcyjne zawsze wg WPS i zatwierdzonej spoiny próbnej.',
                        en: 'STARTING values for setting up a test coupon. '
                            'Production parameters always per the WPS and a qualified test weld.',
                      ),
                      style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // P1-15: pin BHP / purge / O₂ / fit-up checklist ABOVE the inputs
          // — these are GO/NO-GO safety prerequisites that have to be true
          // BEFORE the welder reads the suggested current. Showing them only
          // after the result card is computed (the prior layout) buried them
          // exactly when they were most safety-critical.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tips_and_updates_outlined,
                    color: _kGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Sprawdź: przedmuchanie gazem formującym przed zajarzeniem, '
                          'O₂ < 50 ppm, szczelina fit-up ≈ 0, elektroda zaostrzona i czysta.',
                      en: 'Check: backing-gas purge before arc start, O₂ < 50 ppm, '
                          'fit-up gap ≈ 0, electrode ground sharp and clean.',
                    ),
                    style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── INPUTS ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _field(
                  _od,
                  context.tr(pl: 'OD rury (mm)', en: 'Tube OD (mm)'),
                  hint: '25.4',
                  errorText: _odError,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  _wall,
                  context.tr(pl: 'Ścianka (mm)', en: 'Wall (mm)'),
                  hint: '1.65',
                  errorText: _wallError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _field(
            _volts,
            context.tr(pl: 'Napięcie łuku (V)', en: 'Arc voltage (V)'),
            hint: '8–12',
            errorText: _voltsError,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _trace,
            textCapitalization: TextCapitalization.characters,
            // P1-13: cap stamp/WPS at 40 chars and deny newlines so the line
            // pasted into clipboard/PDF stays single-line and predictable —
            // a welder pasting a 200-char dump into the foreman chat would
            // break the parameter trace block in the messenger.
            maxLength: 40,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
            ],
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Stempel spawacza / WPS (opc.)',
                  en: 'Welder stamp / WPS (opt.)'),
              hintText: context.tr(
                  pl: 'np. PL-217 · WPS-316L-04',
                  en: 'e.g. PL-217 · WPS-316L-04'),
              hintStyle: const TextStyle(color: _kMuted),
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
                pl: 'Spawanie autogeniczne (bez drutu) — typowe dla cienkościennej rury 316L.',
                en: 'Autogenous welding (no filler) — typical for thin-wall 316L tube.'),
            style: const TextStyle(color: _kMuted, fontSize: 11),
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kRed.withValues(alpha: 0.3)),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: _kRed, fontSize: 13)),
            ),

          if (e != null) ...[
            _ResultCard(
              title: context.tr(pl: 'Prąd wg poziomu orbity', en: 'Current per orbital level'),
              children: [
                _LevelRow(level: 1, name: context.tr(pl: 'Płasko (dół)', en: 'Flat (down)'), amps: e.levelCurrentA[0]),
                _LevelRow(level: 2, name: context.tr(pl: 'Pionowo w dół', en: 'Vertical-down'), amps: e.levelCurrentA[1]),
                _LevelRow(level: 3, name: context.tr(pl: 'Pionowo w górę', en: 'Vertical-up'), amps: e.levelCurrentA[2]),
                _LevelRow(level: 4, name: context.tr(pl: 'Pułapowo (góra)', en: 'Overhead (top)'), amps: e.levelCurrentA[3]),
              ],
            ),
            const SizedBox(height: 12),
            _ResultCard(
              title: context.tr(pl: 'Geometria i czas', en: 'Geometry & time'),
              children: [
                _DataRow(
                    label: context.tr(pl: 'Obwód spoiny', en: 'Weld circumference'),
                    value: '${e.circumferenceMm.toStringAsFixed(1)} mm'),
                _DataRow(
                    label: context.tr(pl: 'Prędkość obrotu', en: 'Travel speed'),
                    value: '${e.travelSpeedMmMin.toStringAsFixed(0)} mm/min'),
                _DataRow(
                    label: context.tr(pl: 'Czas spoiny (1 obrót)', en: 'Weld time (1 rev)'),
                    value: '${e.weldTimeSec.toStringAsFixed(1)} s',
                    primary: true),
                _DataRow(
                    label: context.tr(pl: 'Liczba przejść', en: 'Passes'),
                    value: '${e.passes}'),
                _DataRow(
                    label: context.tr(pl: 'Energia liniowa (orient.)', en: 'Heat input (approx.)'),
                    value: '${e.heatInputKJmm.toStringAsFixed(2)} kJ/mm'),
              ],
            ),
            const SizedBox(height: 10),
            // Quick action: copy the whole parameter set in one tap so the
            // welder can paste it into a WPS form or a chat with the foreman
            // without long-pressing every row individually.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final od = _p(_od.text);
                  final wall = _p(_wall.text);
                  final v = _p(_volts.text) ?? 10;
                  final header = context.tr(
                      pl: 'Orbital TIG — OD ${od?.toStringAsFixed(1)} x t ${wall?.toStringAsFixed(2)} mm, U=${v.toStringAsFixed(0)} V',
                      en: 'Orbital TIG — OD ${od?.toStringAsFixed(1)} x t ${wall?.toStringAsFixed(2)} mm, U=${v.toStringAsFixed(0)} V');
                  final lvl = context.tr(
                      pl: 'L1 ${e.levelCurrentA[0].toStringAsFixed(0)}A · L2 ${e.levelCurrentA[1].toStringAsFixed(0)}A · L3 ${e.levelCurrentA[2].toStringAsFixed(0)}A · L4 ${e.levelCurrentA[3].toStringAsFixed(0)}A',
                      en: 'L1 ${e.levelCurrentA[0].toStringAsFixed(0)}A · L2 ${e.levelCurrentA[1].toStringAsFixed(0)}A · L3 ${e.levelCurrentA[2].toStringAsFixed(0)}A · L4 ${e.levelCurrentA[3].toStringAsFixed(0)}A');
                  final geo = context.tr(
                      pl: 'Obwód ${e.circumferenceMm.toStringAsFixed(1)} mm · v=${e.travelSpeedMmMin.toStringAsFixed(0)} mm/min · t=${e.weldTimeSec.toStringAsFixed(1)} s · ${e.passes} przejścia · Q=${e.heatInputKJmm.toStringAsFixed(2)} kJ/mm',
                      en: 'Circ ${e.circumferenceMm.toStringAsFixed(1)} mm · v=${e.travelSpeedMmMin.toStringAsFixed(0)} mm/min · t=${e.weldTimeSec.toStringAsFixed(1)} s · ${e.passes} passes · Q=${e.heatInputKJmm.toStringAsFixed(2)} kJ/mm');
                  final trace = _trace.text.trim();
                  final traceLine = trace.isEmpty
                      ? ''
                      : '\n${context.tr(pl: 'Stempel/WPS', en: 'Stamp/WPS')}: $trace';
                  // Guard the platform-channel clipboard call: on some devices
                  // (locked screens, restricted profiles) Clipboard.setData can
                  // throw and would otherwise surface as an unhandled async
                  // error in the gesture handler.
                  try {
                    await copyToClipboard(
                      context,
                      '$header\n$lvl\n$geo$traceLine',
                      label: context.tr(pl: 'Parametry', en: 'Parameters'),
                    );
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text(context.tr(
                            pl: 'Nie udało się skopiować do schowka',
                            en: 'Could not copy to clipboard')),
                        duration: const Duration(milliseconds: 1400),
                      ));
                  }
                },
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: Text(context.tr(
                    pl: 'Kopiuj wszystkie parametry',
                    en: 'Copy all parameters')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBlue,
                  side: BorderSide(color: _kBlue.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, String? errorText}) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      // P1-30: only digits + decimal separator allowed — no minus sign, so the
      // hardware keyboard cannot inject a negative OD/wall/V in the first
      // place. Defence-in-depth: _calc still rejects negatives in case the
      // controller is mutated programmatically.
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint == null
            ? null
            : context.tr(pl: 'np. $hint', en: 'e.g. $hint'),
        hintStyle: const TextStyle(color: _kMuted),
        // P1-30: per-field error surfaced inline (parse failure / out-of-band
        // / negative) so the welder sees WHICH field is the problem without
        // hunting through a single cross-field banner.
        errorText: errorText,
      ),
      // P1-19: debounced — coalesces a burst of digits into a single calc on
      // the trailing edge so the wall>OD/2 banner can't flash mid-typing.
      onChanged: (_) => _scheduleCalc(),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _ResultCard({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: _kMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  final int level;
  final String name;
  final double amps;
  const _LevelRow({required this.level, required this.name, required this.amps});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$level',
                style: const TextStyle(
                    color: _kBlue, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: const TextStyle(color: _kSec, fontSize: 13)),
          ),
          CopyOnLongPress(
            value: amps.toStringAsFixed(0),
            label: 'L$level',
            child: Text('${amps.toStringAsFixed(0)} A',
                style: const TextStyle(
                    color: _kOrange,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final bool primary;
  const _DataRow({required this.label, required this.value, this.primary = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: _kSec, fontSize: 13)),
          ),
          CopyOnLongPress(
            value: value,
            label: label,
            child: Text(value,
                style: TextStyle(
                    color: primary ? _kOrange : const Color(0xFFE8ECF0),
                    fontSize: primary ? 18 : 14,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
