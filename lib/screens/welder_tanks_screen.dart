import 'package:flutter/material.dart';

import '../database/tandem_tig_param_dao.dart';
import '../domain/welding/tandem_currents.dart';
import '../i18n/app_language.dart';
import '../models/tandem_tig_param.dart';
import 'welder_pipes_screen.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

/// WELDER -> Zbiorniki
///
/// - Tandem TIG (2 osoby): zewnętrzny z drutem (większy prąd), wewnętrzny bez drutu (mniejszy).
/// - "Startowe" (read-only): punkty startowe tandemu, user nie może ich usuwać.
class WelderTanksScreen extends StatefulWidget {
  const WelderTanksScreen({super.key});

  @override
  State<WelderTanksScreen> createState() => _WelderTanksScreenState();
}

class _WelderTanksScreenState extends State<WelderTanksScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('ZBIORNIKI', 'TANKS')),
        actions: [
          HelpButton(help: kHelpWelderTanks),
          IconButton(
            tooltip: _tr('Przejdź do Rury (AMP/Gazy/Startowe)', 'Go to Pipes (AMP/Gases/Starting points)'),
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelderPipesScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            const Tab(text: 'Tandem'),
            Tab(text: _tr('Startowe', 'Starting points')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _TandemTab(),
          _ApprovedTab(),
        ],
      ),
    );
  }
}

class _TandemTab extends StatefulWidget {
  const _TandemTab();

  @override
  State<_TandemTab> createState() => _TandemTabState();
}

class _TandemTabState extends State<_TandemTab> {
  final _dao = TandemTigParamDao();

  String _position = 'HORIZONTAL';
  String _jointType = 'BUTT';
  double _land = 3.0;
  final _gapCtrl = TextEditingController(text: '0.0');

  final _t1Ctrl = TextEditingController(text: '3.0');
  final _t2Ctrl = TextEditingController(text: '3.0');

  double _parseD(String s) => parseDecimal(s) ?? 0.0;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _t1Ctrl.dispose();
    _t2Ctrl.dispose();
    _gapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t1 = _parseD(_t1Ctrl.text);
    final t2 = _parseD(_t2Ctrl.text);
    final tEff = (t1 > t2 ? t1 : t2);
    final gap = _parseD(_gapCtrl.text);

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tr('Tandem TIG (SS) - 2 osoby', 'Tandem TIG (SS) - 2 people'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'VERTICAL', label: Text(_tr('Pion', 'Vertical'))),
                    ButtonSegment(value: 'HORIZONTAL', label: Text(_tr('Poziom', 'Horizontal'))),
                  ],
                  selected: {_position},
                  onSelectionChanged: (s) => setState(() => _position = s.first),
                  // Glove-friendly: ensure 48dp minimum hit target for gloved fingertips.
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(const Size(48, 48)),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _t1Ctrl,
                        keyboardType: numberKeyboard(),
                        inputFormatters: numberInputFormatters(),
                        decoration: InputDecoration(labelText: _tr('Ścianka 1 (t1) [mm]', 'Wall 1 (t1) [mm]')),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _t2Ctrl,
                        keyboardType: numberKeyboard(),
                        inputFormatters: numberInputFormatters(),
                        decoration: InputDecoration(labelText: _tr('Ścianka 2 (t2) [mm]', 'Wall 2 (t2) [mm]')),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _jointType,
                  items: [
                    DropdownMenuItem(value: 'BUTT', child: Text(_tr('Na styk (bez szczeliny)', 'Butt joint (no gap)'))),
                    DropdownMenuItem(value: 'GAP', child: Text(_tr('Na szczelinę', 'Gap joint'))),
                    DropdownMenuItem(value: 'BEVEL', child: Text(_tr('Fazowane (land)', 'Bevelled (land)'))),
                  ],
                  onChanged: (v) => setState(() {
                    _jointType = v ?? 'BUTT';
                    if (_jointType == 'GAP' && _parseD(_gapCtrl.text) <= 0) {
                      _gapCtrl.text = '3.0';
                    }
                    if (_jointType == 'BUTT') {
                      _gapCtrl.text = '0.0';
                    }
                  }),
                  decoration: InputDecoration(labelText: _tr('Typ złącza', 'Joint type')),
                ),
                if (_jointType != 'BUTT') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _gapCtrl,
                    keyboardType: numberKeyboard(),
                    inputFormatters: numberInputFormatters(),
                    decoration: InputDecoration(labelText: _tr('Szczelina [mm]', 'Gap [mm]')),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_jointType == 'BEVEL') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<double>(
                    initialValue: _land,
                    items: const [
                      DropdownMenuItem(value: 1.0, child: Text('Land 1 mm')),
                      DropdownMenuItem(value: 2.0, child: Text('Land 2 mm')),
                      DropdownMenuItem(value: 3.0, child: Text('Land 3 mm')),
                    ],
                    onChanged: (v) => setState(() => _land = v ?? 3.0),
                    decoration: InputDecoration(labelText: _tr('Land (mm)', 'Land (mm)')),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        FutureBuilder<_TandemResult>(
          future: (tEff > 0)
              ? _calcTandem(
                  t1: t1,
                  t2: t2,
                  position: _position,
                  jointType: _jointType,
                  landMm: _jointType == 'BEVEL' ? _land : null,
                  gapMm: gap,
                )
              : Future.value(_TandemResult.none(_tr('Podaj grubości ścianek.', 'Enter wall thicknesses.'))),
          builder: (context, snap) {
            final r = snap.data ?? const _TandemResult.none('...');
            return _TandemResultCard(result: r);
          },
        ),
      ],
    );
  }

  static TandemPoint _pt(TandemTigParam p) => TandemPoint(
        t1: p.wallThicknessMm,
        t2: p.wallThickness2Mm ?? p.wallThicknessMm,
        outsideA: p.outsideAmps,
        insideA: p.insideAmps,
      );

  Future<_TandemResult> _calcTandem({
    required double t1,
    required double t2,
    required String position,
    required String jointType,
    required double? landMm,
    required double? gapMm,
  }) async {
    Future<List<TandemPoint>> load(String pos) async => (await _dao.listApprovedFiltered(
          materialGroup: 'SS',
          position: pos,
          jointType: jointType,
          landMm: landMm,
          gapMm: gapMm,
        ))
            .map(_pt)
            .toList();

    final hPts = await load('HORIZONTAL');
    final TandemEstimate est;
    if (position == 'HORIZONTAL') {
      est = estimateTandem(hPts, t1, t2);
    } else {
      final vPts = await load('VERTICAL');
      final own = estimateTandem(vPts, t1, t2);
      est = own.hasResult
          ? own
          : estimateTandemVerticalFromHorizontal(horizontal: hPts, vertical: vPts, t1: t1, t2: t2);
    }
    return _TandemResult(est: est, source: describeTandem(est));
  }

  static String _trStatic(String pl, String en) => AppLanguageController.isEnglish ? en : pl;

  static String _fmtPair(double t1, double? t2) {
    final b = (t2 ?? t1);
    // Locale-aware decimal: PL welders read "3,0" on calipers/drawings, EN keep ".".
    final dec = AppLanguageController.isEnglish ? '.' : ',';
    final a = t1.toStringAsFixed(1).replaceAll('.', dec);
    if ((b - t1).abs() < 0.0001) return '$a/$a mm';
    return '$a/${b.toStringAsFixed(1).replaceAll('.', dec)} mm';
  }

  static String _fmtMm(double v) {
    final dec = AppLanguageController.isEnglish ? '.' : ',';
    return v.toStringAsFixed(1).replaceAll('.', dec);
  }

  static String _ptLine(TandemPoint p) =>
      '${_fmtPair(p.t1, p.t2)} → ${p.outsideA.toStringAsFixed(0)}/${p.insideA.toStringAsFixed(0)} A';

  /// Opis pochodzenia wyniku (widoczny pod liczbą).
  static String describeTandem(TandemEstimate e) {
    final lines = <String>[];
    switch (e.status) {
      case TandemStatus.exact:
        lines.add('${_trStatic('Punkt startowy dla tej pary', 'Starting point for this pair')}: ${_ptLine(e.low!)}');
      case TandemStatus.sameEffective:
        lines.add(_trStatic(
          'Brak wpisu dla tej pary t1/t2 — użyto punktu o tej samej grubości efektywnej t = max(t1, t2) = ${_fmtMm(e.effMm)} mm: ${_ptLine(e.low!)}',
          'No entry for this t1/t2 pair — used the point with the same effective thickness t = max(t1, t2) = ${_fmtMm(e.effMm)} mm: ${_ptLine(e.low!)}',
        ));
      case TandemStatus.interpolated:
        lines.add(_trStatic(
          'Interpolacja liniowa po t = max(t1, t2) = ${_fmtMm(e.effMm)} mm między punktami startowymi: ${_ptLine(e.low!)} oraz ${_ptLine(e.high!)} (k = ${e.k!.toStringAsFixed(2)})',
          'Linear interpolation by t = max(t1, t2) = ${_fmtMm(e.effMm)} mm between starting points: ${_ptLine(e.low!)} and ${_ptLine(e.high!)} (k = ${e.k!.toStringAsFixed(2)})',
        ));
      case TandemStatus.scaledFromHorizontal:
        final v = e.verticalRef!;
        final h = e.horizontalRef!;
        lines.add(_trStatic(
          'Pion: brak własnego wpisu — poziom ${e.horizontal!.outsideA!.toStringAsFixed(0)}/${e.horizontal!.insideA!.toStringAsFixed(0)} A przeskalowany parą odniesienia ${_fmtPair(v.t1, v.t2)}: zewn. × ${v.outsideA.toStringAsFixed(0)}/${h.outsideA.toStringAsFixed(0)}, wewn. × ${v.insideA.toStringAsFixed(0)}/${h.insideA.toStringAsFixed(0)}.',
          'Vertical: no own entry — horizontal ${e.horizontal!.outsideA!.toStringAsFixed(0)}/${e.horizontal!.insideA!.toStringAsFixed(0)} A scaled by the reference pair ${_fmtPair(v.t1, v.t2)}: OUT × ${v.outsideA.toStringAsFixed(0)}/${h.outsideA.toStringAsFixed(0)}, IN × ${v.insideA.toStringAsFixed(0)}/${h.insideA.toStringAsFixed(0)}.',
        ));
      case TandemStatus.outOfRange:
        final range = (e.minEffMm! - e.maxEffMm!).abs() < 0.0001
            ? '${_fmtMm(e.minEffMm!)} mm'
            : '${_fmtMm(e.minEffMm!)}–${_fmtMm(e.maxEffMm!)} mm';
        lines.add(_trStatic(
          'Brak danych dla tej grubości: t = max(t1, t2) = ${_fmtMm(e.effMm)} mm, a punkty startowe obejmują t = $range. Aplikacja nie ekstrapoluje — ustal prąd na próbce i wpisz go do WPS.',
          'No data for this thickness: t = max(t1, t2) = ${_fmtMm(e.effMm)} mm, while the starting points cover t = $range. The app does not extrapolate — set the current on a test piece and record it in the WPS.',
        ));
      case TandemStatus.noData:
        lines.add(_trStatic(
          'Brak danych dla tej pozycji i złącza. Aplikacja nie zgaduje prądu — ustal go na próbce i wpisz do WPS.',
          'No data for this position and joint. The app does not guess the current — set it on a test piece and record it in the WPS.',
        ));
    }
    if (e.hasResult && e.nonMonotonic) {
      lines.add(_trStatic(
        'Uwaga: w danych prąd maleje przy rosnącej grubości w tym przedziale — punkty startowe są ze sobą sprzeczne. Sprawdź na próbce.',
        'Warning: in the data the current drops as thickness grows in this range — the starting points contradict each other. Check on a test piece.',
      ));
    }
    if (e.hasResult && e.conflicting) {
      lines.add(_trStatic(
        'Uwaga: kilka punktów o tej samej grubości ma różne prądy — pokazano średnią.',
        'Warning: several points with the same thickness have different currents — the average is shown.',
      ));
    }
    return lines.join('\n');
  }
}

class _ApprovedTab extends StatefulWidget {
  const _ApprovedTab();

  @override
  State<_ApprovedTab> createState() => _ApprovedTabState();
}

class _ApprovedTabState extends State<_ApprovedTab> {
  final _dao = TandemTigParamDao();
  final _q = TextEditingController();

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TandemTigParam>>(
      future: _dao.listApproved(materialGroup: 'SS'),
      builder: (context, snap) {
        final items = snap.data ?? const <TandemTigParam>[];
        final query = _q.text.trim().toLowerCase();
        final filtered = items.where((p) {
          if (query.isEmpty) return true;
          final landTxt = (p.landMm ?? 0).toStringAsFixed(0);
          final gapTxt = (p.gapMm ?? 0).toStringAsFixed(1);
          final hay = '${p.position} ${p.jointType} land=$landTxt gap=$gapTxt ${p.wallThicknessMm} ${p.wallThickness2Mm ?? p.wallThicknessMm} ${p.outsideAmps} ${p.insideAmps} ${p.note ?? ''}'.toLowerCase();
          return hay.contains(query);
        }).toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            TextField(
              controller: _q,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: _tr('Szukaj (punkty startowe) - tylko odczyt', 'Search (starting points) - read only')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (snap.connectionState == ConnectionState.done && filtered.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        query.isEmpty ? Icons.list_alt_outlined : Icons.search_off,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        query.isEmpty
                            ? _tr('Brak punktów startowych dla zbiorników.', 'No starting points for tanks.')
                            : _tr('Brak wyników dla "$query".', 'No results for "$query".'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        query.isEmpty
                            ? _tr('Punkty startowe są tylko do odczytu (to nie WPS). Użyj zakładki "Tandem", aby policzyć prądy z grubości ścianek.', 'Starting points are read-only (not a WPS). Use the "Tandem" tab to calculate amps from wall thicknesses.')
                            : _tr('Wyczyść pole wyszukiwania lub spróbuj innych słów (np. "Pion", "BUTT", "3.0").', 'Clear the search field or try other terms (e.g. "Vertical", "BUTT", "3.0").'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      ),
                      if (query.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () {
                            _q.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                          label: Text(_tr('Wyczyść', 'Clear')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            for (final p in filtered)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text('${_pos(p.position)} | ${_pair(p.wallThicknessMm, p.wallThickness2Mm)} | ${_jt(p)}'),
                  subtitle: Text('${_tr('Zewn.', 'OUT')} ${p.outsideAmps.toStringAsFixed(0)} A | ${_tr('Wewn.', 'IN')} ${p.insideAmps.toStringAsFixed(0)} A${(p.note ?? '').trim().isNotEmpty ? "\n${p.note}" : ""}'),
                  isThreeLine: true,
                ),
              ),
          ],
        );
      },
    );
  }

  static String _pos(String p) => p == 'VERTICAL' ? (AppLanguageController.isEnglish ? 'Vertical' : 'Pion') : (AppLanguageController.isEnglish ? 'Horizontal' : 'Poziom');

  static String _pair(double t1, double? t2) {
    final b = (t2 ?? t1);
    if ((b - t1).abs() < 0.0001) return '${t1.toStringAsFixed(1)}/${t1.toStringAsFixed(1)}';
    return '${t1.toStringAsFixed(1)}/${b.toStringAsFixed(1)}';
  }

  static String _jt(TandemTigParam p) {
    if (p.jointType == 'BEVEL') return '${AppLanguageController.isEnglish ? 'Bevel' : 'Faza'} land=${(p.landMm ?? 0).toStringAsFixed(0)}';
    if (p.jointType == 'GAP') return AppLanguageController.isEnglish ? 'Gap' : 'Szczelina';
    return AppLanguageController.isEnglish ? 'Butt joint' : 'Na styk';
  }
}

class _TandemResultCard extends StatelessWidget {
  final _TandemResult result;
  const _TandemResultCard({required this.result});

  void _showFormulaInfo(BuildContext context) {
    final isEn = AppLanguageController.isEnglish;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'How is this calculated?' : 'Skąd wynik?'),
        content: SingleChildScrollView(
          child: Text(
            isEn
                ? 'Tandem TIG (2 welders) on SS tanks. Units: amps [A], thickness [mm].\n\n'
                    '1) Effective thickness: t = max(t1, t2).\n'
                    '2) If a starting point matches exactly (position, joint, t1/t2, land, gap) -> its OUT/IN amps are used as-is.\n'
                    '3) Otherwise -> linear interpolation by t between the two neighbouring starting points — ONLY inside the range of the data.\n'
                    '4) Vertical without its own point -> Horizontal first, then scaled by the reference pair that exists in both positions (today 3/3 mm: V 70/40 A, H 140/72 A).\n'
                    '5) Outside the data range, or with no data for the filter, there is NO number: set the current on a test piece and record it in the WPS.\n'
                    '6) If the data show the current dropping as thickness grows, the result gets a warning.\n\n'
                    'OUT = wire-fed outer torch (higher current). IN = inner torch without wire (lower current).\n'
                    'These are starting values — the WPS is binding.'
                : 'Tandem TIG (2 spawaczy) na zbiornikach SS. Jednostki: amper [A], grubość [mm].\n\n'
                    '1) Grubość efektywna: t = max(t1, t2).\n'
                    '2) Jeśli istnieje punkt startowy dokładnie pasujący (pozycja, złącze, t1/t2, land, szczelina) -> jego prądy OUT/IN używamy wprost.\n'
                    '3) W przeciwnym razie -> interpolacja liniowa po t między dwoma sąsiednimi punktami — TYLKO w zakresie danych.\n'
                    '4) Pion bez własnego punktu -> najpierw Poziom, potem skalowanie parą odniesienia obecną w obu pozycjach (dziś 3/3 mm: Pion 70/40 A, Poziom 140/72 A).\n'
                    '5) Poza zakresem danych albo bez danych dla filtra NIE ma liczby: ustal prąd na próbce i wpisz go do WPS.\n'
                    '6) Jeśli w danych prąd maleje przy rosnącej grubości, wynik dostaje ostrzeżenie.\n\n'
                    'Zewn. = palnik zewnętrzny z drutem (większy prąd). Wewn. = palnik wewnętrzny bez drutu (mniejszy).\n'
                    'To wartości startowe — wiąże WPS.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = result.est;
    final has = e != null && e.hasResult;
    final warn = e != null && e.hasResult && (e.nonMonotonic || e.conflicting);
    final alert = (e != null && !has) || warn;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      has
                          ? '${context.tr(pl: 'Zewnętrzny', en: 'Outside')}: ${e.outsideA!.toStringAsFixed(0)} A   |   ${context.tr(pl: 'Wewnętrzny', en: 'Inside')}: ${e.insideA!.toStringAsFixed(0)} A'
                          : '${context.tr(pl: 'Zewnętrzny', en: 'Outside')}: —   |   ${context.tr(pl: 'Wewnętrzny', en: 'Inside')}: —',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: has ? null : scheme.outline,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: context.tr(pl: 'Jak liczymy ten wynik?', en: 'How is this calculated?'),
                  onPressed: () => _showFormulaInfo(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                result.source,
                style: TextStyle(
                  color: alert ? scheme.error : null,
                  fontWeight: alert ? FontWeight.w600 : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                context.tr(
                  pl: 'Wartości startowe z danych użytkownika, nie kwalifikacja. Wiąże WPS — sprawdź na próbce.',
                  en: 'Starting values from user data, not a qualification. The WPS is binding — check on a test piece.',
                ),
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TandemResult {
  final TandemEstimate? est;
  final String source;
  const _TandemResult({required this.est, required this.source});
  const _TandemResult.none(this.source) : est = null;
}

/// Opis pochodzenia wyniku tandemu (ten sam tekst co pod liczbą na ekranie).
String describeTandemEstimate(TandemEstimate e) => _TandemTabState.describeTandem(e);
