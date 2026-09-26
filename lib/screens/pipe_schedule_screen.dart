import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pipe_schedules.dart';
import '../domain/fitter/size_query.dart';
import '../i18n/app_language.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/clipboard_helper.dart';

const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kBlue   = Color(0xFF4A9EFF);
const _kMuted  = kTextMut; // token motywu (kontrast ≥ 4,5:1)

/// What the table cells show.
enum ScheduleView { wall, inside, mass }

/// Wall thickness lookup per ASME B36.10M (CS: STD, 40, 80, 160, XS, XXS) and
/// ASME B36.19M (SS: 5S, 10S, 40S, 80S). Long-press a cell to copy.
/// The view chips switch the cells between wall, inside diameter (OD − 2t)
/// and kg/m — same table, the three readings a fitter actually asks for.
class PipeScheduleScreen extends StatefulWidget {
  const PipeScheduleScreen({super.key});

  @override
  State<PipeScheduleScreen> createState() => _PipeScheduleScreenState();
}

class _PipeScheduleScreenState extends State<PipeScheduleScreen> {
  String _q = '';
  ScheduleView _view = ScheduleView.wall;
  bool _stainless = false;
  final _filter = TextEditingController();

  // Autosave view mode so a fitter checking kg/m for SS pipe doesn't have to
  // re-toggle every time they switch tabs to glance at an iso or torque calc.
  static const _kPrefShowMass = 'pipe_schedule.show_mass';
  static const _kPrefView = 'pipe_schedule.view';
  static const _kPrefStainless = 'pipe_schedule.stainless';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final view = prefs.getString(_kPrefView);
    final showMass = prefs.getBool(_kPrefShowMass); // pre-ID versions
    final stainless = prefs.getBool(_kPrefStainless);
    if (view == null && showMass == null && stainless == null) return;
    setState(() {
      final byName = ScheduleView.values.where((v) => v.name == view);
      if (byName.isNotEmpty) {
        _view = byName.first;
      } else if (showMass == true) {
        _view = ScheduleView.mass;
      }
      if (stainless != null) _stainless = stainless;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefView, _view.name);
    await prefs.setBool(_kPrefShowMass, _view == ScheduleView.mass);
    await prefs.setBool(_kPrefStainless, _stainless);
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<PipeRow> get _rows => kPipeWalls
      .where((r) => sizeQueryMatches(_q, dn: r.dn, nps: r.nps))
      .toList();

  @override
  Widget build(BuildContext context) {
    final schedules = schedulesFor(stainless: _stainless);
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Grubości ścianek / Sch',
            en: 'Wall thickness / Sch')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _filter,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: context.tr(
                    pl: 'Szukaj: DN50, 2", 2 cale, 100…',
                    en: 'Search: DN50, 2", 2 in, 100…'),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text(context.tr(pl: 'CS — B36.10M', en: 'CS — B36.10M')),
                  selected: !_stainless,
                  onSelected: (_) {
                    setState(() => _stainless = false);
                    _savePrefs();
                  },
                ),
                ChoiceChip(
                  label: Text(context.tr(pl: 'SS — B36.19M', en: 'SS — B36.19M')),
                  selected: _stainless,
                  onSelected: (_) {
                    setState(() => _stainless = true);
                    _savePrefs();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final v in ScheduleView.values)
                  ChoiceChip(
                    label: Text(switch (v) {
                      ScheduleView.wall =>
                        context.tr(pl: 'Ścianka mm', en: 'Wall mm'),
                      ScheduleView.inside =>
                        context.tr(pl: 'ID mm', en: 'ID mm'),
                      ScheduleView.mass => 'kg/m',
                    }),
                    selected: _view == v,
                    onSelected: (_) {
                      setState(() => _view = v);
                      _savePrefs();
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _caption(context),
                style: const TextStyle(color: _kMuted, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _Header(schedules: schedules),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off,
                              size: 48, color: _kMuted),
                          const SizedBox(height: 12),
                          Text(
                            context.tr(
                                pl: 'Brak wyników dla "${_q.trim()}"',
                                en: 'No results for "${_q.trim()}"'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFE7ECF3),
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr(
                                pl: 'Spróbuj: DN50, 2", 100',
                                en: 'Try: DN50, 2", 100'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: _kMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _Row(
                      row: rows[i],
                      schedules: schedules,
                      view: _view,
                      stainless: _stainless,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _caption(BuildContext context) {
    final norm = _stainless
        ? context.tr(
            pl: 'ASME B36.19M (nierdzewna) — 40S/80S ≠ 40/80 od NPS 10–12',
            en: 'ASME B36.19M (stainless) — 40S/80S ≠ 40/80 from NPS 10–12')
        : context.tr(pl: 'ASME B36.10M (węglowa / stopowa)', en: 'ASME B36.10M (carbon / alloy)');
    return switch (_view) {
      ScheduleView.wall => norm,
      ScheduleView.inside => '$norm · ID = OD − 2t',
      ScheduleView.mass => _stainless
          ? '$norm · ρ 8,0 kg/dm³ (316/316L)'
          : '$norm · ρ 7,85 kg/dm³',
    };
  }
}

String? _cellText(PipeRow row, String s, ScheduleView view, bool stainless) {
  switch (view) {
    case ScheduleView.wall:
      return row.walls[s]?.toStringAsFixed(2);
    case ScheduleView.inside:
      return insideDiameterMm(row, s)?.toStringAsFixed(2);
    case ScheduleView.mass:
      return massPerMeter(row, s, stainless: stainless)?.toStringAsFixed(1);
  }
}

/// One-line "DN50 Ø60.3 (mm CS) | STD:3.91 40:3.91 …" summary the fitter
/// pastes into a chat to convey the full pipe spec without screenshotting.
String _rowSummary(PipeRow row,
    {required List<String> schedules,
    required ScheduleView view,
    required bool stainless}) {
  final unit = switch (view) {
    ScheduleView.wall => 'mm',
    ScheduleView.inside => 'ID mm',
    ScheduleView.mass => 'kg/m',
  };
  final tag = stainless ? ' SS B36.19M' : ' CS B36.10M';
  final parts = <String>[];
  for (final s in schedules) {
    final v = _cellText(row, s, view, stainless);
    if (v == null) continue;
    parts.add('$s:$v');
  }
  return 'DN${row.dn} Ø${row.od.toStringAsFixed(1)} ($unit$tag) | '
      '${parts.join(' ')}';
}

class _Header extends StatelessWidget {
  final List<String> schedules;
  const _Header({required this.schedules});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 70,
            child: Text('DN / OD',
                style: TextStyle(
                    color: _kMuted, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          ...schedules.map((s) => Expanded(
                child: Text(s,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _kOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4)),
              )),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final PipeRow row;
  final List<String> schedules;
  final ScheduleView view;
  final bool stainless;
  const _Row({
    required this.row,
    required this.schedules,
    required this.view,
    required this.stainless,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            // Long-press the DN/OD cell to copy the whole row as one line.
            child: CopyOnLongPress(
              value: _rowSummary(row,
                  schedules: schedules, view: view, stainless: stainless),
              label: 'DN${row.dn}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DN${row.dn}',
                      style: const TextStyle(
                          color: Color(0xFFE7ECF3),
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  Text('Ø ${row.od.toStringAsFixed(1)}',
                      style: const TextStyle(color: _kMuted, fontSize: 10)),
                ],
              ),
            ),
          ),
          ...schedules.map((s) {
            final txt = _cellText(row, s, view, stainless);
            if (txt == null) {
              return const Expanded(
                child: Text('—',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _kMuted, fontSize: 12)),
              );
            }
            return Expanded(
              child: CopyOnLongPress(
                value: txt,
                label: 'DN${row.dn} Sch $s',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(txt,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _kBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
