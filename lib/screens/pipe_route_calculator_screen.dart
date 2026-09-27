import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/elbow_takeouts.dart';
import '../i18n/app_language.dart';
import '../services/takeout_catalog.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

/// Straight-pipe lengths of the route X (horizontal) → |H1−H2| (vertical) →
/// Y (horizontal): TWO 90° elbows, three pipe segments, four butt welds at
/// the elbows (+ two at the route ends when X / Y are measured to a face).
class PipeRouteResult {
  /// X − R − g (− g at the start weld): reference → face of elbow 1.
  final double seg1;

  /// |H1−H2| − 2R − 2g: between the faces of elbow 1 and elbow 2.
  final double seg2;

  /// Y − R − g (− g at the end weld): face of elbow 2 → reference.
  final double seg3;

  /// Σ of the (non-negative) straight segments — what goes on the saw.
  final double total;

  /// Number of 90° elbows in this route.
  final int elbowCount;

  /// Number of butt welds whose root gap was deducted.
  final int weldCount;

  /// Centreline arc length of the elbows: 2 × (π·R/2) = π·R.
  final double arcsMm;

  /// Developed centreline length: straights + weld gaps + arcs
  /// (= X + |H1−H2| + Y − (4 − π)·R for positive segments).
  final double developedMm;

  const PipeRouteResult({
    required this.seg1,
    required this.seg2,
    required this.seg3,
    required this.total,
    required this.elbowCount,
    required this.weldCount,
    required this.arcsMm,
    required this.developedMm,
  });
}

/// Pure calculation behind [PipeRouteCalculatorScreen]; [r] is the take-out
/// (centre-to-face) of one 90° elbow — for an LR elbow its CLR radius, ASME
/// B16.9 dimension A. [gapMm] is the weld root gap deducted at every butt
/// weld: the 4 elbow welds always, the 2 route-end welds when [endWelds]
/// (X and Y measured to the face of a flange / pipe that gets welded on).
PipeRouteResult computePipeRoute({
  required double h1,
  required double h2,
  required double x,
  required double y,
  required double r,
  double gapMm = 0,
  bool endWelds = false,
}) {
  const elbows = 2;
  final endGap = endWelds ? gapMm : 0.0;
  final seg1 = x - r - gapMm - endGap;
  final seg2 = (h1 - h2).abs() - 2 * r - 2 * gapMm;
  final seg3 = y - r - gapMm - endGap;
  final total = math.max(0.0, seg1) + math.max(0.0, seg2) + math.max(0.0, seg3);
  final welds = 2 * elbows + (endWelds ? 2 : 0);
  final arcs = elbows * (math.pi * r / 2);
  return PipeRouteResult(
    seg1: seg1,
    seg2: seg2,
    seg3: seg3,
    total: total,
    elbowCount: elbows,
    weldCount: welds,
    arcsMm: arcs,
    developedMm: total + welds * gapMm + arcs,
  );
}

class PipeRouteCalculatorScreen extends StatefulWidget {
  const PipeRouteCalculatorScreen({super.key});

  @override
  State<PipeRouteCalculatorScreen> createState() => _PipeRouteCalculatorScreenState();
}

class _PipeRouteCalculatorScreenState extends State<PipeRouteCalculatorScreen>
    with WidgetsBindingObserver {
  final _h1Controller = TextEditingController();
  final _h2Controller = TextEditingController();
  final _xController  = TextEditingController();
  final _yController  = TextEditingController();
  // No default R: an empty R forces a choice (DN from ASME B16.9 or a typed
  // take-out). The old default 0 meant C-C dimensions = pipes cut too long.
  final _rController  = TextEditingController();
  final _gapController = TextEditingController();
  bool _endWelds = false;

  /// DN whose B16.9 LR 90° take-out (A) is in the R field; null = typed R.
  int? _dn;

  final _seg1Controller  = TextEditingController();
  final _seg2Controller  = TextEditingController();
  final _seg3Controller  = TextEditingController();
  final _totalController = TextEditingController();

  // P1-22: SharedPreferences persistence. Five input controllers + R survive
  // backgrounding ("paused"/"inactive") and successful `_calculate()` calls,
  // so a fitter mid-shift who gets a phone call doesn't lose the spool setup.
  static const _kPrefH1 = 'pipe_route.h1';
  static const _kPrefH2 = 'pipe_route.h2';
  static const _kPrefX  = 'pipe_route.x';
  static const _kPrefY  = 'pipe_route.y';
  static const _kPrefR  = 'pipe_route.r';
  static const _kPrefDn  = 'pipe_route.dn';
  static const _kPrefGap = 'pipe_route.gap';
  static const _kPrefEndWelds = 'pipe_route.end_welds';
  // P1-22: decimal-separator preference (auto follows app language, dot/comma
  // force one regardless of locale — auditors copying into mixed-locale
  // spreadsheets need this control).
  static const _kPrefDecimalSeparator = 'prefs_decimal_separator';
  // P1-22: route_decimals — how many fractional digits results render with
  // (0 = whole mm, 1 = default, 2 = sub-mm precision for stainless flanges).
  static const _kPrefRouteDecimals = 'prefs_route_decimals';

  // Values: 'auto' (follow PL/EN), 'dot', 'comma'.
  String _decimalSeparatorPref = 'auto';
  int _routeDecimals = 1;

  // P1-32: GlobalKey on the results block so we can scroll it on-screen after
  // `_calculate()` success and after the last input loses focus on small phones
  // where the keyboard collapse leaves TOTAL invisible below the fold.
  final GlobalKey _resultsKey = GlobalKey();
  final FocusNode _h1Focus = FocusNode();
  final FocusNode _h2Focus = FocusNode();
  final FocusNode _xFocus  = FocusNode();
  final FocusNode _yFocus  = FocusNode();
  final FocusNode _rFocus  = FocusNode();

  double? _parseOrNull(String v) =>
      v.trim().isEmpty ? null : parseDecimal(v);

  /// Last successful result — feeds the developed-length line in the
  /// formula dialog.
  PipeRouteResult? _last;

  /// R used for the last result (0 → C-C warning under the results).
  double? _lastR;

  void _error(String pl, String en) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(pl: pl, en: en)),
      duration: const Duration(seconds: 5),
    ));
  }

  void _pickDn(int? dn) {
    setState(() {
      _dn = dn;
      if (dn != null) {
        final t = b169ElbowTakeout(
            dn: dn, type: ElbowRadiusType.long15D, angleDeg: 90);
        if (t != null) _rController.text = '${t.a90Mm}';
      }
    });
  }

  // Route: horizontal X → vertical |H1−H2| → horizontal Y
  // 2 × 90° elbows (4 butt welds). Pipe segments between elbows
  // (face-to-face, not C-C):
  //   Segment1 = X − R          (from wall/reference to face of elbow 1)
  //   Segment2 = |H1−H2| − 2R   (between face of elbow 1 and face of elbow 2)
  //   Segment3 = Y − R          (from face of elbow 2 to wall/reference)
  // where R = elbow takeout (centre-to-face). For LR 90° elbow: takeout = R_CLR.
  void _calculate() {
    final h1 = _parseOrNull(_h1Controller.text);
    final h2 = _parseOrNull(_h2Controller.text);
    final x  = _parseOrNull(_xController.text);
    final y  = _parseOrNull(_yController.text);
    final r  = _parseOrNull(_rController.text);
    final gapText = _gapController.text.trim();
    final gap = gapText.isEmpty ? 0.0 : parseDecimal(gapText);

    if (h1 == null || h2 == null) {
      _error('Wpisz H1 i H2 (puste pole to nie 0)',
          'Enter H1 and H2 (an empty field is not 0)');
      return;
    }
    if ((h1 - h2).abs() < 1e-9) {
      _error('H1 = H2: brak odcinka pionowego — to nie jest trasa na 2 kolanach 90°',
          'H1 = H2: no vertical leg — this is not a 2 × 90° elbow route');
      return;
    }
    if (x == null || y == null || x <= 0 || y <= 0) {
      _error('Wpisz X i Y > 0', 'Enter X and Y > 0');
      return;
    }
    if (r == null) {
      _error('Wybierz DN kolan (R z ASME B16.9) albo wpisz R',
          'Pick the elbow DN (R from ASME B16.9) or enter R');
      return;
    }
    if (r < 0) {
      _error('R (takeout) nie może być ujemne', 'R (takeout) cannot be negative');
      return;
    }
    if (gap == null || gap < 0) {
      _error('Szczelina spoiny: wpisz ≥ 0 mm', 'Weld gap: enter ≥ 0 mm');
      return;
    }

    final res = computePipeRoute(
        h1: h1, h2: h2, x: x, y: y, r: r, gapMm: gap, endWelds: _endWelds);
    if (res.seg1 < 0 || res.seg2 < 0 || res.seg3 < 0) {
      // No "reset R" shortcut: R = 0 is a C-C route, not a fix — it gives
      // pipes too long by the take-out. The dimensions or the DN are wrong.
      _error(
          'R (take-out) + szczeliny za duże dla tych wymiarów — odcinek wyszedłby '
              'ujemny. Sprawdź X, Y, H1, H2 i DN kolan.',
          'R (take-out) + gaps too large for these dimensions — a segment would be '
              'negative. Check X, Y, H1, H2 and the elbow DN.');
      return;
    }
    _lastR = r;
    final seg1  = res.seg1;
    final seg2  = res.seg2;
    final seg3  = res.seg3;
    final total = res.total;
    _last = res;

    // P1-22: decimal separator follows the user's `prefs_decimal_separator`
    // pref. 'auto' falls back to PL/EN locale; explicit 'dot'/'comma' overrides
    // regardless of UI language so spreadsheet/clipboard interop stays sane.
    final String dec;
    switch (_decimalSeparatorPref) {
      case 'dot':   dec = '.'; break;
      case 'comma': dec = ','; break;
      default:      dec = AppLanguageController.isEnglish ? '.' : ',';
    }
    final digits = _routeDecimals.clamp(0, 2);
    _seg1Controller.text  = seg1.toStringAsFixed(digits).replaceAll('.', dec);
    _seg2Controller.text  = seg2.toStringAsFixed(digits).replaceAll('.', dec);
    _seg3Controller.text  = seg3.toStringAsFixed(digits).replaceAll('.', dec);
    _totalController.text = total.toStringAsFixed(digits).replaceAll('.', dec);

    setState(() {});

    // P1-22: persist all 5 inputs on _calculate success so a fitter who
    // backgrounds the app or kills it mid-shift recovers the spool setup.
    _saveSettings();

    // P1-32: keyboard collapses on `setState()` and the TOTAL card renders
    // off-screen on 360-dp phones. ensureVisible scrolls the WYNIKI block
    // back into view so the welder sees the result without manual scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _resultsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // P1-04: Wyczyść — reset all input + result controllers in one tap.
  // Inputs (H1, H2, X, Y, R, gap, DN) get cleared — R is left EMPTY (no C-C
  // default) — and the 4 result controllers wipe so the empty-state
  // placeholder reappears. Multi-job shift = 3-4 calcs back-to-back;
  // manual field clearing in gloves is painful and inconsistent.
  void _clearAll() {
    _h1Controller.clear();
    _h2Controller.clear();
    _xController.clear();
    _yController.clear();
    _rController.clear();
    _gapController.clear();
    _dn = null;
    _endWelds = false;
    _seg1Controller.clear();
    _seg2Controller.clear();
    _seg3Controller.clear();
    _totalController.clear();
    _last = null;
    _lastR = null;
    setState(() {});
    // P1-22: also wipe persisted inputs so a fresh launch starts clean.
    _saveSettings();
  }

  // P1-22: restore prefs on first build, attach lifecycle observer so we can
  // snapshot inputs on paused/inactive. Focus listeners power P1-32 auto-scroll
  // after the last input loses focus (welder taps "Done" on the keyboard).
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    for (final n in [_h1Focus, _h2Focus, _xFocus, _yFocus, _rFocus]) {
      n.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    // P1-32: when all input focus nodes lose focus AND we have a result already
    // computed, scroll the WYNIKI block on-screen. Same UX as the post-calc
    // path — the keyboard collapse otherwise hides the TOTAL card.
    final anyFocused = _h1Focus.hasFocus ||
        _h2Focus.hasFocus ||
        _xFocus.hasFocus ||
        _yFocus.hasFocus ||
        _rFocus.hasFocus;
    if (anyFocused) return;
    if (_totalController.text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _resultsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // P1-22: snapshot 5 inputs + R + the two display prefs on background — same
  // pattern as bolt_torque_screen._savePrefs. mounted-safe via try/catch (the
  // SharedPreferences future can fail on locked/full storage).
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefH1, _h1Controller.text);
      await prefs.setString(_kPrefH2, _h2Controller.text);
      await prefs.setString(_kPrefX,  _xController.text);
      await prefs.setString(_kPrefY,  _yController.text);
      await prefs.setString(_kPrefR,  _rController.text);
      await prefs.setString(_kPrefGap, _gapController.text);
      await prefs.setBool(_kPrefEndWelds, _endWelds);
      if (_dn == null) {
        await prefs.remove(_kPrefDn);
      } else {
        await prefs.setInt(_kPrefDn, _dn!);
      }
      await prefs.setString(_kPrefDecimalSeparator, _decimalSeparatorPref);
      await prefs.setInt(_kPrefRouteDecimals, _routeDecimals);
    } catch (_) {
      // Storage locked / full — silently skip; next session falls back to
      // defaults rather than crashing the calc screen.
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final h1 = prefs.getString(_kPrefH1);
      final h2 = prefs.getString(_kPrefH2);
      final x  = prefs.getString(_kPrefX);
      final y  = prefs.getString(_kPrefY);
      final r  = prefs.getString(_kPrefR);
      final gap = prefs.getString(_kPrefGap);
      final endWelds = prefs.getBool(_kPrefEndWelds);
      final dn = prefs.getInt(_kPrefDn);
      final dsep = prefs.getString(_kPrefDecimalSeparator);
      final dec  = prefs.getInt(_kPrefRouteDecimals);
      setState(() {
        if (h1 != null) _h1Controller.text = h1;
        if (h2 != null) _h2Controller.text = h2;
        if (x  != null) _xController.text  = x;
        if (y  != null) _yController.text  = y;
        // A stored "0" is the old default (C-C), not a choice — start empty.
        if (r != null && r.isNotEmpty && parseDecimal(r) != 0) {
          _rController.text = r;
        }
        if (gap != null) _gapController.text = gap;
        if (endWelds != null) _endWelds = endWelds;
        if (dn != null && elbowTakeoutForDn(dn) != null) _dn = dn;
        if (dsep == 'auto' || dsep == 'dot' || dsep == 'comma') {
          _decimalSeparatorPref = dsep!;
        }
        if (dec != null && dec >= 0 && dec <= 2) _routeDecimals = dec;
      });
    } catch (_) {
      // Fall back to defaults on storage error.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // P1-22: persist on paused/inactive too — backgrounding the app shouldn't
    // require a prior successful _calculate() to checkpoint half-typed inputs.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveSettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final n in [_h1Focus, _h2Focus, _xFocus, _yFocus, _rFocus]) {
      n.removeListener(_onFocusChange);
      n.dispose();
    }
    for (final c in [
      _h1Controller, _h2Controller, _xController, _yController, _rController,
      _gapController, _seg1Controller, _seg2Controller, _seg3Controller, _totalController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Trasa rur – 2 kolana 90°', en: 'Pipe route – 2 × 90° elbows')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _clearAll,
          ),
          HelpButton(help: kHelpPipeRoute),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (_, constraints) {
          // P1-33: narrow phones (< 380 dp) get a single-column stack so the
          // 168-dp labelText "X – bieg poziomy 1" doesn't ellipsize mid-edit.
          final bool narrow = constraints.maxWidth < 380;
          final h1Field = _field(_h1Controller,
              focusNode: _h1Focus,
              label: context.tr(pl: 'H1 – wys. startu', en: 'H1 – start height'), suffix: 'mm');
          final h2Field = _field(_h2Controller,
              focusNode: _h2Focus,
              label: context.tr(pl: 'H2 – wys. końca', en: 'H2 – end height'), suffix: 'mm');
          final xField = _field(_xController,
              focusNode: _xFocus,
              label: context.tr(pl: 'X – bieg poziomy 1', en: 'X – horizontal run 1'), suffix: 'mm');
          final yField = _field(_yController,
              focusNode: _yFocus,
              label: context.tr(pl: 'Y – bieg poziomy 2', en: 'Y – horizontal run 2'), suffix: 'mm');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // P1-33: small sketch above inputs showing what H1/H2/X/Y/R mean.
              // Welders on first launch couldn't tell which segment was X vs Y
              // without leaving the screen to consult help.
              _RouteSketch(
                tooltipPl: 'H1/H2 = wysokości startu/końca · X/Y = biegi poziome · R = takeout kolanka',
                tooltipEn: 'H1/H2 = start/end heights · X/Y = horizontal runs · R = elbow takeout',
              ),
              const SizedBox(height: 12),
              _sectionLabel(context.tr(pl: 'DANE WEJŚCIOWE', en: 'INPUT DATA')),
              const SizedBox(height: 12),

              if (narrow) ...[
                h1Field,
                const SizedBox(height: 12),
                h2Field,
                const SizedBox(height: 12),
                xField,
                const SizedBox(height: 12),
                yField,
              ] else ...[
                Row(children: [
                  Expanded(child: h1Field),
                  const SizedBox(width: 12),
                  Expanded(child: h2Field),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: xField),
                  const SizedBox(width: 12),
                  Expanded(child: yField),
                ]),
              ],
              const SizedBox(height: 12),

              DropdownButtonFormField<int?>(
                initialValue: _dn,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr(
                      pl: 'Kolana ASME B16.9 LR 90° — DN',
                      en: 'ASME B16.9 LR 90° elbows — DN'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      context.tr(pl: '— wpiszę R ręcznie', en: '— I will type R'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final e in kElbowTakeouts)
                    DropdownMenuItem<int?>(
                      value: e.dn,
                      child: Text('DN${e.dn} (${e.nps}") — R = ${e.lr90} mm',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _pickDn,
              ),
              const SizedBox(height: 12),
              _field(_rController,
                focusNode: _rFocus,
                label: context.tr(
                  pl: 'R – takeout kolanka 90° (C-F)',
                  en: 'R – elbow 90° takeout (C-F)',
                ),
                suffix: 'mm',
                helper: context.tr(
                  pl: 'Wybierz DN (R = wymiar A wg ASME B16.9) albo wpisz take-out z karty kolana.',
                  en: 'Pick the DN (R = dimension A per ASME B16.9) or type the take-out from the elbow datasheet.',
                ),
                onChanged: (v) {
                  if (_dn == null) return;
                  final a = elbowTakeoutForDn(_dn!)?.lr90;
                  if (a == null || parseDecimal(v) != a) setState(() => _dn = null);
                },
              ),
              const SizedBox(height: 12),
              _field(_gapController,
                label: context.tr(pl: 'Szczelina spoiny g', en: 'Weld gap g'),
                suffix: 'mm',
                helper: context.tr(
                  pl: 'Odejmowana przy każdej spoinie kolana (odc. 1 i 3: −g, odc. 2: −2g). Puste = 0.',
                  en: 'Deducted at every elbow weld (seg. 1 and 3: −g, seg. 2: −2g). Empty = 0.',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _endWelds,
                onChanged: (v) => setState(() => _endWelds = v),
                title: Text(context.tr(
                    pl: 'Spoiny także na obu końcach trasy',
                    en: 'Welds at both route ends too')),
                subtitle: Text(context.tr(
                    pl: 'X i Y mierzone do czoła rury / kołnierza, który się przyspawa — dodatkowe −g na odc. 1 i 3.',
                    en: 'X and Y measured to the face of a pipe / flange that gets welded on — extra −g on seg. 1 and 3.')),
              ),
              const SizedBox(height: 12),
              _buildDisplayPrefs(),
              const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: Text(context.tr(pl: 'OBLICZ', en: 'CALCULATE')),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),

              const SizedBox(height: 24),
              // P1-32: GlobalKey anchors `Scrollable.ensureVisible` so the
              // WYNIKI block scrolls on-screen after _calculate() success and
              // after the last input loses focus.
              KeyedSubtree(
                key: _resultsKey,
                child: _sectionLabel(context.tr(pl: 'WYNIKI – długości odcinków rur', en: 'RESULTS – pipe segment lengths')),
              ),
              const SizedBox(height: 12),

              if (_totalController.text.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.straighten,
                          size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            pl: 'Wpisz H1, H2, X, Y, wybierz DN kolan (lub wpisz R), potem OBLICZ.',
                            en: 'Enter H1, H2, X, Y, pick the elbow DN (or type R), then CALCULATE.',
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                if (_lastR == 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      context.tr(
                        pl: 'R = 0 → wymiary osiowe (C-C), NIE długości cięcia. Każda rura wyjdzie za długa o take-out kolana.',
                        en: 'R = 0 → centreline (C-C) dimensions, NOT cut lengths. Every pipe comes out too long by the elbow take-out.',
                      ),
                      style: TextStyle(color: Colors.orange.shade300, fontWeight: FontWeight.w600),
                    ),
                  ),
                _result(_seg1Controller,
                  label: context.tr(pl: 'Odcinek 1 (poziomy, X−R−g)', en: 'Segment 1 (horizontal, X−R−g)')),
                const SizedBox(height: 12),
                _result(_seg2Controller,
                  label: context.tr(pl: 'Odcinek 2 (pionowy, |H1−H2|−2R−2g)', en: 'Segment 2 (vertical, |H1−H2|−2R−2g)')),
                const SizedBox(height: 12),
                _result(_seg3Controller,
                  label: context.tr(pl: 'Odcinek 3 (poziomy, Y−R−g)', en: 'Segment 3 (horizontal, Y−R−g)')),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.straighten, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(
                            context.tr(pl: 'SUMA (bez kolanek)', en: 'TOTAL (excl. elbows)'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline, size: 20),
                            tooltip: context.tr(pl: 'Wzór', en: 'Formula'),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showTotalFormulaDialog(context),
                          ),
                        ]),
                        Text(
                          _totalController.text.isEmpty ? '—' : '${_totalController.text} mm',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 16),
              Text(
                context.tr(
                  pl: 'Wzór: Odcinek = wymiar C-C − takeout. Takeout kolana LR 90° = promień CLR = wymiar A wg ASME B16.9 (np. DN100 → 152 mm).',
                  en: 'Formula: Segment = C-C dimension − takeout. LR 90° elbow takeout = CLR radius = dimension A per ASME B16.9 (e.g. DN100 → 152 mm).',
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              // ASME/ISO iso convention: each joint between segments is a weld;
              // mark FW (field weld, open flag) vs SW (shop weld, filled dot) so the
              // welder knows what to weld on site. 2 elbows = 4 joints in this route.
              Text(
                context.tr(
                  pl: 'Spoiny: ${_endWelds ? 6 : 4} złącza (spoiny obwodowe doczołowe, szczelina g odjęta przy każdej). Oznacz na izometryku FW – spoina montażowa (flaga), SW – spoina warsztatowa (kropka).',
                  en: 'Welds: ${_endWelds ? 6 : 4} joints (circumferential butts, gap g deducted at each). Mark on iso as FW – field weld (open flag), SW – shop weld (filled dot).',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        }),
      ),
    );
  }

  // P1-22: display-prefs row — decimal separator (auto/dot/comma) + result
  // precision (0/1/2 decimal places). Persists via _saveSettings(). 48-dp
  // tap targets per project policy.
  Widget _buildDisplayPrefs() {
    final theme = Theme.of(context);
    Widget sepChip(String value, String labelPl, String labelEn) {
      final selected = _decimalSeparatorPref == value;
      return ChoiceChip(
        label: Text(context.tr(pl: labelPl, en: labelEn)),
        selected: selected,
        onSelected: (_) {
          setState(() => _decimalSeparatorPref = value);
          _saveSettings();
          if (_totalController.text.isNotEmpty) _calculate();
        },
      );
    }

    Widget decChip(int value) {
      final selected = _routeDecimals == value;
      return ChoiceChip(
        label: Text('$value'),
        selected: selected,
        onSelected: (_) {
          setState(() => _routeDecimals = value);
          _saveSettings();
          if (_totalController.text.isNotEmpty) _calculate();
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(pl: 'Separator dziesiętny', en: 'Decimal separator'),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              sepChip('auto', 'Auto (język)', 'Auto (language)'),
              sepChip('dot',  'Kropka (.)', 'Dot (.)'),
              sepChip('comma','Przecinek (,)','Comma (,)'),
            ]),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(pl: 'Miejsca po przecinku', en: 'Decimal places'),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              decChip(0), decChip(1), decChip(2),
            ]),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    final String dec;
    switch (_decimalSeparatorPref) {
      case 'dot':   dec = '.'; break;
      case 'comma': dec = ','; break;
      default:      dec = AppLanguageController.isEnglish ? '.' : ',';
    }
    return v.toStringAsFixed(_routeDecimals.clamp(0, 2)).replaceAll('.', dec);
  }

  void _showTotalFormulaDialog(BuildContext ctx) {
    final last = _last;
    final gapsMm = last == null ? 0.0 : last.developedMm - last.total - last.arcsMm;
    final gapsPl = gapsMm > 1e-9
        ? ' + szczeliny ${last!.weldCount} × g (${_fmt(gapsMm)})'
        : '';
    final gapsEn = gapsMm > 1e-9
        ? ' + gaps ${last!.weldCount} × g (${_fmt(gapsMm)})'
        : '';
    final currentPl = last == null
        ? ''
        : '\n\nDla bieżących danych: ${_fmt(last.total)} + π·R (${_fmt(last.arcsMm)})$gapsPl '
            '= ${_fmt(last.developedMm)} mm długości rozwiniętej.';
    final currentEn = last == null
        ? ''
        : '\n\nFor the current inputs: ${_fmt(last.total)} + π·R (${_fmt(last.arcsMm)})$gapsEn '
            '= ${_fmt(last.developedMm)} mm developed length.';
    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text(ctx.tr(pl: 'Wzór – SUMA rur', en: 'Formula – TOTAL pipe')),
        content: SingleChildScrollView(
          child: Text(
            ctx.tr(
              pl: 'Suma = Odc.1 + Odc.2 + Odc.3 [mm]\n\n'
                  'Odc.1 = X − R − g\n'
                  'Odc.2 = |H1 − H2| − 2·R − 2·g\n'
                  'Odc.3 = Y − R − g\n'
                  '(g = szczelina spoiny; ze spoinami na końcach trasy odc. 1 i 3 dodatkowo − g)\n\n'
                  'R = takeout kolanka 90° (centre-to-face). Dla LR 90°: R = CLR = wymiar A wg ASME B16.9 '
                  '(≈ 1,5 × NPS × 25,4; DN100 → 152 mm).\n\n'
                  'UWAGA: suma to długość prostych odcinków rury (bez łuków kolanek). '
                  'Trasa ma 2 kolana 90°, więc długość rozwinięta osi z łukami = suma + 2 × (π·R/2) = suma + π·R.'
                  '$currentPl\n\n'
                  'Jednostki: wszystkie wymiary i wynik w mm.',
              en: 'Total = Seg.1 + Seg.2 + Seg.3 [mm]\n\n'
                  'Seg.1 = X − R − g\n'
                  'Seg.2 = |H1 − H2| − 2·R − 2·g\n'
                  'Seg.3 = Y − R − g\n'
                  '(g = weld gap; with welds at the route ends seg. 1 and 3 get another − g)\n\n'
                  'R = 90° elbow takeout (centre-to-face). For LR 90°: R = CLR = dimension A per ASME B16.9 '
                  '(≈ 1.5 × NPS × 25.4; DN100 → 152 mm).\n\n'
                  'NOTE: total is straight pipe length only (excludes elbow arcs). '
                  'The route has 2 × 90° elbows, so the developed centreline length including arcs = total + 2 × (π·R/2) = total + π·R.'
                  '$currentEn\n\n'
                  'Units: all inputs and result in mm.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: Text(ctx.tr(pl: 'OK', en: 'OK')),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
    ),
  );

  Widget _field(TextEditingController ctrl,
      {required String label,
      String? suffix,
      String? helper,
      FocusNode? focusNode,
      ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      onChanged: onChanged,
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _result(TextEditingController ctrl, {required String label}) {
    return TextField(
      controller: ctrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'mm',
        border: const OutlineInputBorder(),
        filled: true,
        suffixIcon: IconButton(
          icon: const Icon(Icons.content_copy, size: 24),
          tooltip: context.tr(pl: 'Kopiuj', en: 'Copy'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          // P0-13: clipboard always carries an unambiguous canonical-dot
          // form. A PL-locale "1234,5" pasted into an EN-locale spreadsheet
          // imports as "12345" — off by an order of magnitude. The visible
          // field stays in the user's locale; only the clipboard payload
          // gets normalised.
          onPressed: ctrl.text.trim().isEmpty
              ? null
              : () => copyToClipboard(
                    context,
                    ctrl.text.replaceAll(',', '.'),
                    label: label,
                  ),
        ),
      ),
    );
  }
}

// P1-33: tiny inline route sketch. Two 90° elbows connecting two horizontal
// runs (X, Y) at different heights (H1, H2). Labels show which dimension is
// which so a first-time user can map the input fields to the physical route
// without leaving the screen for help.
class _RouteSketch extends StatelessWidget {
  const _RouteSketch({required this.tooltipPl, required this.tooltipEn});
  final String tooltipPl;
  final String tooltipEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: context.tr(pl: tooltipPl, en: tooltipEn),
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(8),
        child: CustomPaint(
          painter: _RouteSketchPainter(
            pipeColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.onSurface,
            dimColor: theme.colorScheme.outline,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RouteSketchPainter extends CustomPainter {
  _RouteSketchPainter({
    required this.pipeColor,
    required this.labelColor,
    required this.dimColor,
  });
  final Color pipeColor;
  final Color labelColor;
  final Color dimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final pipe = Paint()
      ..color = pipeColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dim = Paint()
      ..color = dimColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Route geometry inside the box (left to right):
    //   X horizontal at H1 (top), drop |H1-H2|, then Y horizontal at H2.
    final w = size.width;
    final h = size.height;
    final padX = 18.0;
    final padTop = 14.0;
    final padBot = 18.0;
    final topY = padTop;
    final botY = h - padBot;
    final xStart = padX;
    final corner1X = w * 0.40; // both elbows sit on this vertical
    final yEnd = w - padX;
    final r = 8.0; // visual elbow radius

    final path = Path()
      ..moveTo(xStart, topY)
      ..lineTo(corner1X - r, topY)
      ..quadraticBezierTo(corner1X, topY, corner1X, topY + r)
      ..lineTo(corner1X, botY - r)
      ..quadraticBezierTo(corner1X, botY, corner1X + r, botY)
      // Across top (X) → down (|H1−H2|) → across bottom (Y): two 90° elbows,
      // matching the segment formulas.
      ..lineTo(yEnd, botY);
    canvas.drawPath(path, pipe);

    // Dimension ticks (very small)
    canvas.drawLine(Offset(xStart, topY - 6), Offset(xStart, topY + 6), dim);
    canvas.drawLine(Offset(corner1X, topY - 6), Offset(corner1X, topY + 6), dim);
    canvas.drawLine(Offset(corner1X, botY - 6), Offset(corner1X, botY + 6), dim);
    canvas.drawLine(Offset(yEnd, botY - 6), Offset(yEnd, botY + 6), dim);

    // Labels
    void label(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // X spans top horizontal
    label('X', Offset((xStart + corner1X) / 2, topY - 8));
    // |H1-H2| spans vertical drop
    label('|H1−H2|', Offset(corner1X + 22, (topY + botY) / 2));
    // Y spans bottom horizontal
    label('Y', Offset((corner1X + yEnd) / 2, botY + 8));
    // H1 at start, H2 at end
    label('H1', Offset(xStart, topY + 12));
    label('H2', Offset(yEnd, botY - 12));
    // R near the two elbows
    label('R', Offset(corner1X - 12, topY + 12));
    label('R', Offset(corner1X + 12, botY - 12));
  }

  @override
  bool shouldRepaint(covariant _RouteSketchPainter old) =>
      old.pipeColor != pipeColor || old.labelColor != labelColor || old.dimColor != dimColor;
}
