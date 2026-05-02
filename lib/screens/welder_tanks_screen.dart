import 'package:flutter/material.dart';

import '../database/tandem_tig_param_dao.dart';
import '../i18n/app_language.dart';
import '../models/tandem_tig_param.dart';
import 'welder_pipes_screen.dart';
import '../widgets/help_button.dart';

/// WELDER -> Zbiorniki
///
/// - Tandem TIG (2 osoby): zewnętrzny z drutem (większy prąd), wewnętrzny bez drutu (mniejszy).
/// - "Zatwierdzone parametry" (read-only): user nie może ich usuwać.
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
            tooltip: _tr('Przejdź do Rury (AMP/Gazy/Zatwierdzone AMP)', 'Go to Pipes (AMP/Gases/Approved AMP)'),
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelderPipesScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            const Tab(text: 'Tandem'),
            Tab(text: _tr('Zatwierdzone', 'Approved')),
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

  double _parseD(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0.0;

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
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _t1Ctrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: _tr('Ścianka 1 (t1) [mm]', 'Wall 1 (t1) [mm]')),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _t2Ctrl,
                        keyboardType: TextInputType.number,
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
                    keyboardType: TextInputType.number,
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
              : Future.value(_TandemResult(outsideA: 0, insideA: 0, source: _tr('Podaj grubości ścianek.', 'Enter wall thicknesses.'))),
          builder: (context, snap) {
            final r = snap.data ?? const _TandemResult(outsideA: 0, insideA: 0, source: '...');
            return _TandemResultCard(result: r);
          },
        ),
      ],
    );
  }

  Future<_TandemResult> _calcTandem({
    required double t1,
    required double t2,
    required String position,
    required String jointType,
    required double? landMm,
    required double? gapMm,
  }) async {
    final tEff = (t1 > t2 ? t1 : t2);

    // 1) Dokładny wpis zatwierdzony (order-insensitive)
    final exact = await _dao.getExactApproved(
      materialGroup: 'SS',
      position: position,
      jointType: jointType,
      landMm: landMm,
      gapMm: gapMm,
      wallThicknessMm: t1,
      wallThickness2Mm: t2,
    );
    if (exact != null) {
      return _TandemResult(
        outsideA: exact.outsideAmps,
        insideA: exact.insideAmps,
        source: '${_trStatic('Zatwierdzone (dokładnie)', 'Approved (exact)')}: ${_fmtPair(exact.wallThicknessMm, exact.wallThickness2Mm)} | ${_posLabel(exact.position)} | ${_jointLabel(exact)}',
      );
    }

    // 2) Kalkulator bazujący na zatwierdzonych parametrach
    if (position == 'HORIZONTAL') {
      final pts = await _dao.listApprovedFiltered(
        materialGroup: 'SS',
        position: 'HORIZONTAL',
        jointType: jointType,
        landMm: landMm,
        gapMm: gapMm,
      );
      if (pts.isEmpty) {
        return _fallback(t1, t2, position: 'HORIZONTAL');
      }
      final est = _interpByEff(pts, tEff);
      return _TandemResult(
        outsideA: est.outsideA,
        insideA: est.insideA,
        source: '${_trStatic('Poziom: brak dokładnego wpisu -> wyliczone z zatwierdzonych (interpolacja po t=max(t1,t2)=', 'Horizontal: no exact entry -> calculated from approved data (interpolation by t=max(t1,t2)=')}${tEff.toStringAsFixed(1)} mm).\n${est.source}',
      );
    }

    // PION:
    // - dla BUTT bazujemy na relacji pion/poziom w punkcie odniesienia:
    //   poziom 3/3 ≈ 138/68, pion 3/3 = 70/40
    // - najpierw liczymy poziom, potem skalujemy.
    if (jointType == 'BUTT') {
      final hPts = await _dao.listApprovedFiltered(
        materialGroup: 'SS',
        position: 'HORIZONTAL',
        jointType: 'BUTT',
        landMm: null,
        gapMm: 0.0,
      );
      if (hPts.isNotEmpty) {
        final hEst = _interpByEff(hPts, tEff);
        const hRefOut = 138.0;
        const hRefIn = 68.0;
        const vRefOut = 70.0;
        const vRefIn = 40.0;
        final outA = (hEst.outsideA * (vRefOut / hRefOut)).clamp(15.0, 260.0).toDouble();
        final inA = (hEst.insideA * (vRefIn / hRefIn)).clamp(15.0, 260.0).toDouble();
        return _TandemResult(
          outsideA: outA,
          insideA: inA,
          source: '${_trStatic('Pion: brak dokładnego wpisu -> skalowane z Poziom przez (70/138) i (40/68).', 'Vertical: no exact entry -> scaled from Horizontal by (70/138) and (40/68).')}\n${_trStatic('Szacowany poziom', 'Estimated horizontal')}: ${hEst.outsideA.toStringAsFixed(0)}/${hEst.insideA.toStringAsFixed(0)} A',
        );
      }
    }

    // 3) Ostateczny fallback: skalowanie liniowe z pion 3/3=70/40
    final x = (tEff > 0) ? (tEff / 3.0) : 1.0;
    final outA = (70.0 * x).clamp(15.0, 260.0).toDouble();
    final inA = (40.0 * x).clamp(15.0, 260.0).toDouble();
    return _TandemResult(
      outsideA: outA,
      insideA: inA,
      source: '${_trStatic('Pion: brak danych zatwierdzonych dla tego filtra -> fallback liniowy z 3/3 (70/40), x=', 'Vertical: no approved data for this filter -> linear fallback from 3/3 (70/40), x=')}${x.toStringAsFixed(2)}',
    );
  }

  static String _trStatic(String pl, String en) => AppLanguageController.isEnglish ? en : pl;

  /// Linear interpolation / extrapolation by effective thickness t=max(t1,t2).
  static _TandemResult _interpByEff(List<TandemTigParam> pts, double tEff) {
    final items = pts.toList()
      ..sort((a, b) {
        final ea = (a.wallThickness2Mm ?? a.wallThicknessMm) > a.wallThicknessMm ? (a.wallThickness2Mm ?? a.wallThicknessMm) : a.wallThicknessMm;
        final eb = (b.wallThickness2Mm ?? b.wallThicknessMm) > b.wallThicknessMm ? (b.wallThickness2Mm ?? b.wallThicknessMm) : b.wallThicknessMm;
        return ea.compareTo(eb);
      });

    double eff(TandemTigParam p) {
      final b = p.wallThickness2Mm ?? p.wallThicknessMm;
      return (p.wallThicknessMm > b) ? p.wallThicknessMm : b;
    }

    if (items.length == 1) {
      final p = items.first;
      return _TandemResult(
        outsideA: p.outsideAmps,
        insideA: p.insideAmps,
        source: '${_trStatic('Tylko 1 punkt zatwierdzony', 'Only 1 approved point')}: ${_fmtPair(p.wallThicknessMm, p.wallThickness2Mm)} -> ${p.outsideAmps.toStringAsFixed(0)}/${p.insideAmps.toStringAsFixed(0)} A',
      );
    }

    TandemTigParam? low;
    TandemTigParam? high;
    for (final p in items) {
      if (eff(p) <= tEff) low = p;
      if (eff(p) >= tEff) {
        high = p;
        break;
      }
    }
    low ??= items.first;
    high ??= items.last;

    // If exactly at boundary
    if ((eff(low) - tEff).abs() < 0.0001) {
      return _TandemResult(
        outsideA: low.outsideAmps,
        insideA: low.insideAmps,
        source: '${_trStatic('Najbliższy punkt (<=)', 'Nearest point (<=)')}: ${_fmtPair(low.wallThicknessMm, low.wallThickness2Mm)}',
      );
    }
    if ((eff(high) - tEff).abs() < 0.0001) {
      return _TandemResult(
        outsideA: high.outsideAmps,
        insideA: high.insideAmps,
        source: '${_trStatic('Najbliższy punkt (>=)', 'Nearest point (>=)')}: ${_fmtPair(high.wallThicknessMm, high.wallThickness2Mm)}',
      );
    }

    final x0 = eff(low);
    final x1 = eff(high);
    final k = (x1 - x0).abs() < 0.0001 ? 0.0 : ((tEff - x0) / (x1 - x0));
    final outA = (low.outsideAmps + (high.outsideAmps - low.outsideAmps) * k).clamp(15.0, 260.0).toDouble();
    final inA = (low.insideAmps + (high.insideAmps - low.insideAmps) * k).clamp(15.0, 260.0).toDouble();
    return _TandemResult(
      outsideA: outA,
      insideA: inA,
      source: '${_trStatic('Punkty', 'Points')}: ${_fmtPair(low.wallThicknessMm, low.wallThickness2Mm)} -> ${low.outsideAmps.toStringAsFixed(0)}/${low.insideAmps.toStringAsFixed(0)} A ${_trStatic('oraz', 'and')} ${_fmtPair(high.wallThicknessMm, high.wallThickness2Mm)} -> ${high.outsideAmps.toStringAsFixed(0)}/${high.insideAmps.toStringAsFixed(0)} A | k=${k.toStringAsFixed(2)}',
    );
  }

  static String _fmtPair(double t1, double? t2) {
    final b = (t2 ?? t1);
    if ((b - t1).abs() < 0.0001) return '${t1.toStringAsFixed(1)}/${t1.toStringAsFixed(1)} mm';
    return '${t1.toStringAsFixed(1)}/${b.toStringAsFixed(1)} mm';
  }

  static String _posLabel(String p) => p == 'VERTICAL' ? _trStatic('Pion', 'Vertical') : _trStatic('Poziom', 'Horizontal');

  static String _jointLabel(TandemTigParam p) {
    if (p.jointType == 'BEVEL') {
      final land = (p.landMm ?? 0).toStringAsFixed(0);
      final g = (p.gapMm ?? 0);
      if (g > 0) return '${_trStatic('Faza', 'Bevel')} land=$land + ${_trStatic('szczelina', 'gap')} ${g.toStringAsFixed(0)}';
      return '${_trStatic('Faza', 'Bevel')} land=$land';
    }
    if (p.jointType == 'GAP') {
      final g = (p.gapMm ?? 0);
      return g > 0 ? '${_trStatic('Szczelina', 'Gap')} ${g.toStringAsFixed(0)}' : _trStatic('Szczelina', 'Gap');
    }
    return _trStatic('Na styk', 'Butt joint');
  }

  static _TandemResult _fallback(double t1, double t2, {required String position}) {
    final t = (t1 > t2 ? t1 : t2);
    // Minimalny fallback – tylko żeby zawsze coś pokazać.
    double outA;
    double inA;
    if (position == 'VERTICAL') {
      // bazowo 3/3 => 70/40
      final x = (t > 0) ? (t / 3.0) : 1.0;
      outA = 70.0 * x;
      inA = 40.0 * x;
    } else {
      // bazowo 3/3 => 137.5/67.5
      final x = (t > 0) ? (t / 3.0) : 1.0;
      outA = 137.5 * x;
      inA = 67.5 * x;
    }
    return _TandemResult(
      outsideA: outA.clamp(15.0, 260.0).toDouble(),
      insideA: inA.clamp(15.0, 260.0).toDouble(),
      source: _trStatic('Orientacyjne (brak zatwierdzonych danych dla tego filtra).', 'Approximate (no approved data for this filter).'),
    );
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
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: _tr('Szukaj (zatwierdzone) - tylko odczyt', 'Search (approved) - read only')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (snap.connectionState == ConnectionState.done && filtered.isEmpty)
              Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_tr('Brak wpisów (zatwierdzonych) dla zbiorników.', 'No approved entries for tanks.')))),
            for (final p in filtered)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          '${context.tr(pl: 'Zewnętrzny', en: 'Outside')}: ${result.outsideA.toStringAsFixed(0)} A   |   ${context.tr(pl: 'Wewnętrzny', en: 'Inside')}: ${result.insideA.toStringAsFixed(0)} A',
        ),
        subtitle: Text(result.source),
      ),
    );
  }
}

class _TandemResult {
  final double outsideA;
  final double insideA;
  final String source;
  const _TandemResult({required this.outsideA, required this.insideA, required this.source});
}
