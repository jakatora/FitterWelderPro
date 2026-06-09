import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/help_button.dart';

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
  final _rController  = TextEditingController(text: '0');

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

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // Route: horizontal X → vertical |H1−H2| → horizontal Y
  // 3 × 90° elbows. Pipe segments between elbows (face-to-face, not C-C):
  //   Segment1 = X − R          (from wall/reference to face of elbow 1)
  //   Segment2 = |H1−H2| − 2R   (between face of elbow 1 and face of elbow 2)
  //   Segment3 = Y − R          (from face of elbow 2 to wall/reference)
  // where R = elbow takeout (centre-to-face). For LR 90° elbow: takeout = R_CLR.
  void _calculate() {
    final h1 = _parse(_h1Controller.text);
    final h2 = _parse(_h2Controller.text);
    final x  = _parse(_xController.text);
    final y  = _parse(_yController.text);
    final r  = _parse(_rController.text);

    if (x <= 0 || y <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Wpisz X i Y > 0', en: 'Enter X and Y > 0')),
      ));
      return;
    }
    if (r < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'R (takeout) nie może być ujemne',
          en: 'R (takeout) cannot be negative',
        )),
      ));
      return;
    }
    if (r > x || r > y || 2 * r > (h1 - h2).abs()) {
      final messenger = ScaffoldMessenger.of(context);
      final prevR = _rController.text;
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'R za duże dla podanych wymiarów (odcinek wyszedłby ujemny)',
          en: 'R too large for given dimensions (segment would be negative)',
        )),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: context.tr(pl: 'Wyzeruj R', en: 'Reset R'),
          onPressed: () {
            _rController.text = '0';
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(
              content: Text(context.tr(pl: 'R = 0. Policz ponownie.', en: 'R = 0. Recalculate.')),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: context.tr(pl: 'Cofnij', en: 'Undo'),
                onPressed: () => _rController.text = prevR,
              ),
            ));
          },
        ),
      ));
      return;
    }

    final seg1  = x - r;
    final seg2  = (h1 - h2).abs() - 2 * r;
    final seg3  = y - r;
    final total = math.max(0, seg1) + math.max(0, seg2) + math.max(0, seg3);

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
  // 5 inputs (H1, H2, X, Y) + R get cleared (R restored to its default '0'),
  // and the 4 result controllers (seg1, seg2, seg3, total) wipe so the
  // empty-state placeholder reappears. Multi-job shift = 3-4 calcs back-to-back;
  // manual field clearing in gloves is painful and inconsistent.
  void _clearAll() {
    _h1Controller.clear();
    _h2Controller.clear();
    _xController.clear();
    _yController.clear();
    _rController.text = '0';
    _seg1Controller.clear();
    _seg2Controller.clear();
    _seg3Controller.clear();
    _totalController.clear();
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
      final dsep = prefs.getString(_kPrefDecimalSeparator);
      final dec  = prefs.getInt(_kPrefRouteDecimals);
      setState(() {
        if (h1 != null) _h1Controller.text = h1;
        if (h2 != null) _h2Controller.text = h2;
        if (x  != null) _xController.text  = x;
        if (y  != null) _yController.text  = y;
        if (r  != null && r.isNotEmpty) _rController.text = r;
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
      _seg1Controller, _seg2Controller, _seg3Controller, _totalController,
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
        title: Text(context.tr(pl: 'Trasa rur – 3 kolanka 90°', en: 'Pipe route – 3 × 90° elbows')),
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

              _field(_rController,
                focusNode: _rFocus,
                label: context.tr(
                  pl: 'R – takeout kolanka 90° (C-F)',
                  en: 'R – elbow 90° takeout (C-F)',
                ),
                suffix: 'mm',
                helper: context.tr(
                  pl: 'Dla kolanka LR: takeout = promień CLR. Wpisz 0 jeśli liczysz C-C.',
                  en: 'For LR elbow: takeout = CLR radius. Enter 0 if calculating C-C.',
                ),
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
                            pl: 'Wpisz H1, H2, X, Y (i opcjonalnie R), potem OBLICZ.',
                            en: 'Enter H1, H2, X, Y (and optionally R), then CALCULATE.',
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
                _result(_seg1Controller,
                  label: context.tr(pl: 'Odcinek 1 (poziomy, X−R)', en: 'Segment 1 (horizontal, X−R)')),
                const SizedBox(height: 12),
                _result(_seg2Controller,
                  label: context.tr(pl: 'Odcinek 2 (pionowy, |H1−H2|−2R)', en: 'Segment 2 (vertical, |H1−H2|−2R)')),
                const SizedBox(height: 12),
                _result(_seg3Controller,
                  label: context.tr(pl: 'Odcinek 3 (poziomy, Y−R)', en: 'Segment 3 (horizontal, Y−R)')),
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
                  pl: 'Wzór: Odcinek = wymiar C-C − takeout. Takeout dla LR 90° = promień CLR (np. 1,5×DN).',
                  en: 'Formula: Segment = C-C dimension − takeout. Takeout for LR 90° = CLR radius (e.g. 1.5×DN).',
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              // ASME/ISO iso convention: each joint between segments is a weld;
              // mark FW (field weld, open flag) vs SW (shop weld, filled dot) so the
              // welder knows what to weld on site. 3 elbows = 4 joints in this route.
              Text(
                context.tr(
                  pl: 'Spoiny: 4 złącza (zw. spoin obwodowych). Oznacz na izometryku FW – spoina montażowa (flaga), SW – spoina warsztatowa (kropka).',
                  en: 'Welds: 4 joints (circumferential butts). Mark on iso as FW – field weld (open flag), SW – shop weld (filled dot).',
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

  void _showTotalFormulaDialog(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text(ctx.tr(pl: 'Wzór – SUMA rur', en: 'Formula – TOTAL pipe')),
        content: SingleChildScrollView(
          child: Text(
            ctx.tr(
              pl: 'Suma = Odc.1 + Odc.2 + Odc.3 [mm]\n\n'
                  'Odc.1 = X − R\n'
                  'Odc.2 = |H1 − H2| − 2·R\n'
                  'Odc.3 = Y − R\n\n'
                  'R = takeout kolanka 90° (centre-to-face). Dla LR 90°: R = CLR ≈ 1,5·DN.\n\n'
                  'UWAGA: suma to długość prostych odcinków rury (bez łuków kolanek). '
                  'Aby dostać długość rozwiniętą rury z łukami, dodaj 3 × (π·R/2) ≈ 3 × 1,5708·R.\n\n'
                  'Jednostki: wszystkie wymiary i wynik w mm.',
              en: 'Total = Seg.1 + Seg.2 + Seg.3 [mm]\n\n'
                  'Seg.1 = X − R\n'
                  'Seg.2 = |H1 − H2| − 2·R\n'
                  'Seg.3 = Y − R\n\n'
                  'R = 90° elbow takeout (centre-to-face). For LR 90°: R = CLR ≈ 1.5·DN.\n\n'
                  'NOTE: total is straight pipe length only (excludes elbow arcs). '
                  'For developed pipe length including arcs, add 3 × (π·R/2) ≈ 3 × 1.5708·R.\n\n'
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
      {required String label, String? suffix, String? helper, FocusNode? focusNode}) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
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

// P1-33: tiny inline route sketch. Three 90° elbows connecting two horizontal
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
    final corner1X = w * 0.40;
    final corner2X = w * 0.60;
    final yEnd = w - padX;
    final r = 8.0; // visual elbow radius

    final path = Path()
      ..moveTo(xStart, topY)
      ..lineTo(corner1X - r, topY)
      ..quadraticBezierTo(corner1X, topY, corner1X, topY + r)
      ..lineTo(corner1X, botY - r)
      ..quadraticBezierTo(corner1X, botY, corner1X + r, botY)
      ..lineTo(corner2X - r, botY)
      // second corner here would route back up; instead we go horizontal
      // along bottom to Y end (3 × 90° elbows = up→over→down style), but for
      // a flat sketch we simplify to "across top → down → across bottom".
      ..lineTo(yEnd, botY);
    canvas.drawPath(path, pipe);

    // Dimension ticks (very small)
    canvas.drawLine(Offset(xStart, topY - 6), Offset(xStart, topY + 6), dim);
    canvas.drawLine(Offset(corner1X, topY - 6), Offset(corner1X, topY + 6), dim);
    canvas.drawLine(Offset(corner2X, botY - 6), Offset(corner2X, botY + 6), dim);
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
    label('Y', Offset((corner2X + yEnd) / 2, botY + 8));
    // H1 at start, H2 at end
    label('H1', Offset(xStart, topY + 12));
    label('H2', Offset(yEnd, botY - 12));
    // R near corners
    label('R', Offset(corner1X - 12, topY + 12));
    label('R', Offset(corner2X + 12, botY - 12));
  }

  @override
  bool shouldRepaint(covariant _RouteSketchPainter old) =>
      old.pipeColor != pipeColor || old.labelColor != labelColor || old.dimColor != dimColor;
}
