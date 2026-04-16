import 'package:flutter/material.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../models/segment.dart';
import '../services/bar_nesting.dart';
import '../services/pdf_export_service.dart';

const _kOrange = Color(0xFFF5A623);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kBlue   = Color(0xFF4A9EFF);
const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kMuted  = Color(0xFF55607A);

class CutListSummaryScreen extends StatefulWidget {
  final String projectId;
  const CutListSummaryScreen({super.key, required this.projectId});

  @override
  State<CutListSummaryScreen> createState() => _CutListSummaryScreenState();
}

class _CutListSummaryScreenState extends State<CutListSummaryScreen> {
  final _projectDao = ProjectDao();
  final _segmentDao = SegmentDao();
  Project? _project;
  List<Segment> _segments = [];
  Map<String, List<double>> _groups = {};
  bool _loading = true;
  bool _exporting = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final p    = await _projectDao.getById(widget.projectId);
    final segs = await _segmentDao.listForProject(widget.projectId);

    final groups = <String, List<double>>{};
    for (final s in segs) {
      final key = '${s.diameterMm}|${s.wallThicknessMm}';
      groups.putIfAbsent(key, () => []).add(s.cutMm);
    }

    setState(() {
      _project  = p;
      _segments = segs;
      _groups   = groups;
      _loading  = false;
    });
  }

  Future<void> _exportPdf() async {
    final p = _project;
    if (p == null || _segments.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await PdfExportService.exportCutList(project: p, segments: _segments);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF błąd: $e'), backgroundColor: const Color(0xFFE74C3C)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CUT LIST'),
        actions: [
          if (p != null) ...[
            // Eksport PDF
            if (_exporting)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange))),
              )
            else
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: context.tr(pl: 'Eksportuj PDF', en: 'Export PDF'),
                onPressed: _exportPdf,
              ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: context.tr(pl: 'Udostępnij tekst', en: 'Share text'),
              onPressed: () => _share(context, p),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : p == null
              ? Center(child: Text(context.tr(pl: 'Nie znaleziono projektu', en: 'Project not found')))
              : ListView(
                  padding: EdgeInsets.fromLTRB(14, 14, 14, 24 + MediaQuery.viewPaddingOf(context).bottom),
                  children: [
                    // ── NAGŁÓWEK PROJEKTU ─────────────────────────────────
                    _ProjectHeader(project: p),
                    const SizedBox(height: 16),

                    if (_groups.isEmpty)
                      Center(child: Text(context.tr(pl: 'Brak segmentów.', en: 'No segments.')))
                    else ...[
                      // ── PODSUMOWANIE ZBIORCZE ─────────────────────────
                      _GlobalSummary(groups: _groups, project: p),
                      const SizedBox(height: 20),

                      // ── GRUPY RURY ────────────────────────────────────
                      ..._groups.entries.map((e) {
                        final parts = e.key.split('|');
                        final d = double.parse(parts[0]);
                        final w = double.parse(parts[1]);
                        final cuts = List<double>.from(e.value)..sort((a, b) => b.compareTo(a));
                        final plans = nestCutsToBars(
                          cutsMm: cuts,
                          stockLengthMm: p.stockLengthMm,
                          sawKerfMm: p.sawKerfMm,
                        );
                        return _PipeGroup(
                          diameterMm: d,
                          wallMm: w,
                          cuts: cuts,
                          plans: plans,
                          stockLengthMm: p.stockLengthMm,
                          sawKerfMm: p.sawKerfMm,
                        );
                      }),
                    ],
                  ],
                ),
    );
  }

  void _share(BuildContext context, Project p) {
    final buf = StringBuffer();
    buf.writeln('CUT LIST — ${p.name ?? p.id.substring(0, 8)}');
    buf.writeln('Material: ${p.materialGroup}  Stock: ${p.stockLengthMm.toStringAsFixed(0)} mm  Kerf: ${p.sawKerfMm.toStringAsFixed(1)} mm');
    buf.writeln();
    for (final e in _groups.entries) {
      final parts = e.key.split('|');
      final d = double.parse(parts[0]);
      final w = double.parse(parts[1]);
      final cuts = List<double>.from(e.value)..sort((a, b) => b.compareTo(a));
      buf.writeln('Ø${d.toStringAsFixed(1)} x ${w.toStringAsFixed(1)}:');
      final plans = nestCutsToBars(cutsMm: cuts, stockLengthMm: p.stockLengthMm, sawKerfMm: p.sawKerfMm);
      for (var i = 0; i < plans.length; i++) {
        final b = plans[i];
        buf.writeln('  Bar ${i + 1}: ${b.piecesMm.map((x) => x.toStringAsFixed(0)).join(' + ')}  (rem: ${b.remainingMm.toStringAsFixed(0)} mm)');
      }
      buf.writeln();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr(pl: 'Skopiowano do schowka', en: 'Copied to clipboard')),
        backgroundColor: _kGreen,
      ),
    );
  }
}

// ── Nagłówek projektu ──────────────────────────────────────────────────────
class _ProjectHeader extends StatelessWidget {
  final Project project;
  const _ProjectHeader({required this.project});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _kOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.checklist_rtl, size: 22, color: _kOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name?.isNotEmpty == true ? project.name! : 'CUT LIST',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0)),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr(
                    pl: '${project.materialGroup}  ·  Sztanga: ${project.stockLengthMm.toStringAsFixed(0)} mm  ·  Kerf: ${project.sawKerfMm.toStringAsFixed(1)} mm',
                    en: '${project.materialGroup}  ·  Stock: ${project.stockLengthMm.toStringAsFixed(0)} mm  ·  Kerf: ${project.sawKerfMm.toStringAsFixed(1)} mm',
                  ),
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Podsumowanie zbiorcze ──────────────────────────────────────────────────
class _GlobalSummary extends StatelessWidget {
  final Map<String, List<double>> groups;
  final Project project;
  const _GlobalSummary({required this.groups, required this.project});

  @override
  Widget build(BuildContext context) {
    int totalBars = 0;
    double totalCutMm = 0;
    double totalWasteMm = 0;

    for (final e in groups.entries) {
      final cuts = List<double>.from(e.value);
      final plans = nestCutsToBars(
        cutsMm: cuts,
        stockLengthMm: project.stockLengthMm,
        sawKerfMm: project.sawKerfMm,
      );
      totalBars += plans.length;
      for (final b in plans) {
        totalCutMm += b.piecesMm.fold(0, (s, v) => s + v);
        totalWasteMm += b.remainingMm;
      }
    }

    final totalMaterialMm = totalBars * project.stockLengthMm;
    final wastePct = totalMaterialMm > 0 ? (totalWasteMm / totalMaterialMm * 100) : 0.0;
    final wasteColor = wastePct < 10 ? _kGreen : (wastePct < 25 ? _kOrange : _kRed);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(pl: 'Podsumowanie', en: 'Summary'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SummaryStatBox(
                value: '$totalBars',
                label: context.tr(pl: 'Sztangi', en: 'Bars'),
                color: _kOrange,
                icon: Icons.horizontal_rule,
              ),
              const SizedBox(width: 10),
              _SummaryStatBox(
                value: '${(totalCutMm / 1000).toStringAsFixed(2)} m',
                label: context.tr(pl: 'Rura netto', en: 'Net pipe'),
                color: _kBlue,
                icon: Icons.straighten,
              ),
              const SizedBox(width: 10),
              _SummaryStatBox(
                value: '${wastePct.toStringAsFixed(1)}%',
                label: context.tr(pl: 'Odpad', en: 'Waste'),
                color: wasteColor,
                icon: Icons.recycling,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStatBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _SummaryStatBox({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: _kMuted)),
          ],
        ),
      ),
    );
  }
}

// ── Grupa rury (jedna średnica/ścianka) ────────────────────────────────────
class _PipeGroup extends StatelessWidget {
  final double diameterMm;
  final double wallMm;
  final List<double> cuts;
  final List<BarPlan> plans;
  final double stockLengthMm;
  final double sawKerfMm;

  const _PipeGroup({
    required this.diameterMm,
    required this.wallMm,
    required this.cuts,
    required this.plans,
    required this.stockLengthMm,
    required this.sawKerfMm,
  });

  @override
  Widget build(BuildContext context) {
    final totalWaste = plans.fold<double>(0, (s, b) => s + b.remainingMm);
    final totalNet   = cuts.fold<double>(0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nagłówek grupy
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.oil_barrel_outlined, size: 18, color: _kOrange),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr(
                  pl: 'Rura  Ø${diameterMm.toStringAsFixed(1)} × ${wallMm.toStringAsFixed(1)} mm',
                  en: 'Pipe  Ø${diameterMm.toStringAsFixed(1)} × ${wallMm.toStringAsFixed(1)} mm',
                ),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE8ECF0)),
              ),
            ),
            Text(
              '${plans.length} ${context.tr(pl: 'szt.', en: 'bars')}',
              style: const TextStyle(fontSize: 12, color: _kOrange, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Lista odcinków do cięcia
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(pl: 'Odcinki (${cuts.length} szt.)', en: 'Pieces (${cuts.length})'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: cuts.map((c) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22263A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Text('${c.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 12, color: Color(0xFFE8ECF0))),
                )).toList(),
              ),
              const Divider(height: 20, color: _kBorder),
              Text(
                context.tr(
                  pl: 'Netto: ${(totalNet / 1000).toStringAsFixed(3)} m  ·  Odpad: ${totalWaste.toStringAsFixed(0)} mm',
                  en: 'Net: ${(totalNet / 1000).toStringAsFixed(3)} m  ·  Waste: ${totalWaste.toStringAsFixed(0)} mm',
                ),
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Sztangi
        ...List.generate(plans.length, (i) => _BarCard(
          index: i,
          plan: plans[i],
          stockLengthMm: stockLengthMm,
          sawKerfMm: sawKerfMm,
        )),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Karta sztangi z wizualizacją paskową ───────────────────────────────────
class _BarCard extends StatelessWidget {
  final int index;
  final BarPlan plan;
  final double stockLengthMm;
  final double sawKerfMm;

  const _BarCard({
    required this.index,
    required this.plan,
    required this.stockLengthMm,
    required this.sawKerfMm,
  });

  @override
  Widget build(BuildContext context) {
    final usedMm = plan.piecesMm.fold<double>(0, (s, v) => s + v) + plan.cutsCount * sawKerfMm;
    final wastePct = stockLengthMm > 0 ? plan.remainingMm / stockLengthMm : 0.0;
    final wasteColor = wastePct < 0.10 ? _kGreen : (wastePct < 0.25 ? _kOrange : _kRed);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr(pl: 'Sztanga ${index + 1}', en: 'Bar ${index + 1}'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kOrange),
              ),
              const Spacer(),
              Text(
                '${usedMm.toStringAsFixed(0)} / ${stockLengthMm.toStringAsFixed(0)} mm',
                style: const TextStyle(fontSize: 11, color: _kMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Pasek wizualny sztangi
          _BarVisual(plan: plan, stockLengthMm: stockLengthMm, sawKerfMm: sawKerfMm),
          const SizedBox(height: 8),

          // Odcinki
          Text(
            plan.piecesMm.map((x) => x.toStringAsFixed(0)).join('  +  '),
            style: const TextStyle(fontSize: 13, color: Color(0xFFE8ECF0), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                context.tr(
                  pl: 'Cięcia: ${plan.cutsCount}  ·  Zostaje: ${plan.remainingMm.toStringAsFixed(0)} mm',
                  en: 'Cuts: ${plan.cutsCount}  ·  Remaining: ${plan.remainingMm.toStringAsFixed(0)} mm',
                ),
                style: TextStyle(fontSize: 11, color: wasteColor),
              ),
              if (plan.remainingMm > 200) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _kGreen.withOpacity(0.3)),
                  ),
                  child: Text(
                    context.tr(pl: 'nadaje się na spady', en: 'usable offcut'),
                    style: const TextStyle(fontSize: 10, color: _kGreen),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Wizualizacja paskowa sztangi ───────────────────────────────────────────
class _BarVisual extends StatelessWidget {
  final BarPlan plan;
  final double stockLengthMm;
  final double sawKerfMm;

  const _BarVisual({
    required this.plan,
    required this.stockLengthMm,
    required this.sawKerfMm,
  });

  @override
  Widget build(BuildContext context) {
    // Kolory dla kolejnych odcinków
    const pieceColors = [
      Color(0xFFF5A623),
      Color(0xFF4A9EFF),
      Color(0xFF2ECC71),
      Color(0xFFAB47BC),
      Color(0xFFE74C3C),
      Color(0xFF26C6DA),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth;

      return SizedBox(
        height: 24,
        child: Row(
          children: [
            ...List.generate(plan.piecesMm.length, (i) {
              final piecePct = plan.piecesMm[i] / stockLengthMm;
              final kerfPct  = sawKerfMm / stockLengthMm;
              final color = pieceColors[i % pieceColors.length];

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Odcinek
                  Container(
                    width: (totalWidth * piecePct).clamp(4.0, totalWidth),
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Kerf (cięcie piłą)
                  if (i < plan.piecesMm.length - 1 || plan.remainingMm > 0)
                    Container(
                      width: (totalWidth * kerfPct).clamp(2.0, 6.0),
                      height: 24,
                      color: const Color(0xFF0F1117),
                    ),
                ],
              );
            }),
            // Odpad
            if (plan.remainingMm > 0)
              Expanded(
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C3354),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: plan.remainingMm > 300
                      ? Center(
                          child: Text(
                            '${plan.remainingMm.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 9, color: _kMuted),
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ),
      );
    });
  }
}
