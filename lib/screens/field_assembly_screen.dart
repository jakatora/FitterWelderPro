// ignore_for_file: prefer_const_constructors
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/nps_dn_od_r.dart';
import '../database/component_library_dao.dart';
import '../i18n/app_language.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Kolory
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kGreen  = Color(0xFF2ECC71);
const _kRed    = Color(0xFFE74C3C);
const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kMuted  = Color(0xFF55607A);
const _kSec    = Color(0xFF9BA3C7);

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Ekran gÅ‚Ã³wny moduÅ‚u
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class FieldAssemblyScreen extends StatelessWidget {
  const FieldAssemblyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(pl: 'MontaÅ¼ w terenie', en: 'Field assembly')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.tr(pl: 'EtaÅ¼', en: 'Offset')),
              Tab(text: context.tr(pl: 'Prosta wstawka', en: 'Straight run')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _EtazTab(),
            _ProstaTab(),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  WspÃ³lne widgety pomocnicze
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: _kBlue.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: _kSec, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _kMuted,
              letterSpacing: 1.2)),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? unit;
  final String? helperText;
  final VoidCallback? onChanged;

  const _NumField({
    required this.controller,
    required this.label,
    this.hint,
    this.unit,
    this.helperText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: unit,
        helperText: helperText,
      ),
      onChanged: (_) => onChanged?.call(),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final List<Widget> children;
  const _ResultCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kOrange.withValues(alpha: 0.12), _kOrange.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kOrange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool primary;
  final bool dimmed;
  const _ResultRow(
      {required this.label,
      required this.value,
      this.primary = false,
      this.dimmed = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: dimmed ? _kMuted : _kSec))),
          Text(value,
              style: TextStyle(
                  fontSize: primary ? 22 : 14,
                  fontWeight:
                      primary ? FontWeight.w800 : FontWeight.w600,
                  color: primary
                      ? _kOrange
                      : (dimmed ? _kMuted : const Color(0xFFE8ECF0)),
                  letterSpacing: primary ? -0.4 : 0)),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_outlined, size: 16, color: _kRed.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, color: _kRed.shade300))),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  TAB 1: ETAÅ»
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _EtazTab extends StatefulWidget {
  const _EtazTab();
  @override
  State<_EtazTab> createState() => _EtazTabState();
}

class _EtazTabState extends State<_EtazTab> {
  // â”€â”€ Tryb podania offsetu â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // DIRECT: user wpisuje offset bezpoÅ›rednio
  // D1D2_SUM: user wpisuje D1 i D2 mierzone od swoich Å›cian (offset = D1+D2)
  // D1D2_DIFF: user wpisuje D1 i D2 od wspÃ³lnej ref (offset = |D2-D1|)
  String _offsetMode = 'DIRECT';

  // Pola wejÅ›ciowe
  final _offsetCtrl = TextEditingController();
  final _d1Ctrl     = TextEditingController();
  final _d2Ctrl     = TextEditingController();
  final _axisCtrl   = TextEditingController();
  final _gapCtrl    = TextEditingController(text: '0');
  final _odCtrl     = TextEditingController();

  String _elbowAngle = '90';

  // Wyniki
  double? _offset;
  double? _axisMm;
  double? _travel;
  double? _cutMm;
  String? _error;

  // Historia axisMm (per OD) â€” proste zapamiÄ™tywanie w sesji
  final _axisHistory = <String, double>{};

  final _libDao = ComponentLibraryDao();

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _offsetCtrl.dispose();
    _d1Ctrl.dispose();
    _d2Ctrl.dispose();
    _axisCtrl.dispose();
    _gapCtrl.dispose();
    _odCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Auto-uzupeÅ‚nienie axisMm z biblioteki lub tabeli NPS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _lookupAxis() async {
    final odText = _odCtrl.text.replaceAll(',', '.');
    final od = double.tryParse(odText);
    if (od == null || od <= 0) return;

    // 1. SprawdÅº historiÄ™
    if (_axisHistory.containsKey(odText)) {
      _axisCtrl.text = _axisHistory[odText]!.toStringAsFixed(1);
      _calc();
      return;
    }

    // 2. Szukaj w bibliotece komponentÃ³w (ELB90)
    try {
      final all = await _libDao.listFor(
        materialGroup: 'SS',
        currentDiameter: od,
        wallThickness: 0,
      );
      final elb = all.where((c) => c.type == 'ELB90' && c.axisMm != null).toList();
      if (elb.isNotEmpty) {
        final axis = elb.first.axisMm!;
        _axisCtrl.text = axis.toStringAsFixed(1);
        _axisHistory[odText] = axis;
        _calc();
        return;
      }
    } catch (_) {}

    // 3. Szukaj w tabeli NPS
    NpsRow? best;
    double bestDiff = double.infinity;
    for (final row in kNpsTable) {
      final diff = (row.odMm - od).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = row;
      }
    }
    if (best != null && bestDiff < 5) {
      // axisMm dla 90Â° = rMm (centrum do czoÅ‚a = R dla kolan 90Â°)
      _axisCtrl.text = best.rMm.toStringAsFixed(1);
      _axisHistory[odText] = best.rMm;
      _calc();
    }
  }

  // â”€â”€ Obliczenia â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _calc() {
    setState(() {
      _error   = null;
      _offset  = null;
      _axisMm  = null;
      _travel  = null;
      _cutMm   = null;

      // Wylicz offset
      double? off;
      if (_offsetMode == 'DIRECT') {
        off = double.tryParse(_offsetCtrl.text.replaceAll(',', '.'));
        if (off == null || off <= 0) {
          _error = _tr('Podaj odlegÅ‚oÅ›Ä‡ miÄ™dzy osiami rur (mm)',
              'Enter the distance between pipe axes (mm)');
          return;
        }
      } else {
        final d1 = double.tryParse(_d1Ctrl.text.replaceAll(',', '.'));
        final d2 = double.tryParse(_d2Ctrl.text.replaceAll(',', '.'));
        if (d1 == null || d1 <= 0 || d2 == null || d2 <= 0) {
          _error = _tr('Podaj oba wymiary D1 i D2', 'Enter both D1 and D2');
          return;
        }
        off = _offsetMode == 'D1D2_SUM' ? (d1 + d2) : (d1 - d2).abs();
      }
      _offset = off;

      // Wymiar do osi kolanka
      final axis = double.tryParse(_axisCtrl.text.replaceAll(',', '.'));
      if (axis == null || axis <= 0) {
        _error = _tr('Podaj wymiar kolanka do osi (mm)',
            'Enter elbow axis dimension (mm)');
        return;
      }
      _axisMm = axis;

      // Gap
      final gap = double.tryParse(_gapCtrl.text.replaceAll(',', '.')) ?? 0.0;

      // KÄ…t
      final angle = double.parse(_elbowAngle);
      final angleRad = angle * math.pi / 180.0;

      // Travel = odlegÅ‚oÅ›Ä‡ miÄ™dzy czoÅ‚ami kolan (po osi Å‚Ä…czÄ…cej)
      final travel = off / math.sin(angleRad);
      _travel = travel;

      // CUT = travel - axisMm Ã— 2 - gap Ã— 2
      final cut = travel - 2.0 * axis - 2.0 * gap;
      _cutMm = cut;

      if (cut < 0) {
        _error = _tr(
          'Ujemna dÅ‚ugoÅ›Ä‡ rury! OdejÅ›cie za maÅ‚e dla tych kolan. '
          'ZwiÄ™ksz offset lub uÅ¼yj mniejszych kolan.',
          'Negative pipe length! Offset too small for these elbows. '
          'Increase offset or use smaller elbows.',
        );
      }
    });
  }

  // â”€â”€ BUDOWANIE UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        // Schemat
        _EtazDiagram(
          angle: _elbowAngle,
          offset: _offset,
          axisMm: _axisMm,
          cutMm: _cutMm,
        ),
        const SizedBox(height: 16),

        // Typ kolan
        _SectionLabel(_tr('Kolana', 'Elbows')),
        DropdownButtonFormField<String>(
          initialValue: _elbowAngle,
          decoration: InputDecoration(labelText: _tr('KÄ…t kolan', 'Elbow angle')),
          items: const [
            DropdownMenuItem(value: '90', child: Text('90Â°')),
            DropdownMenuItem(value: '45', child: Text('45Â°')),
          ],
          onChanged: (v) {
            setState(() => _elbowAngle = v ?? '90');
            _calc();
          },
        ),
        const SizedBox(height: 10),

        // Wymiar do osi kolanka
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _NumField(
                controller: _axisCtrl,
                label: _tr('Wymiar kolanka do osi (mm)', 'Elbow axis dim (mm)'),
                hint: 'np. 76.2',
                unit: 'mm',
                helperText: _tr(
                  'Twarz kolanka â†’ oÅ›. Dla 90Â° LR: â‰ˆ1.5Ã—OD',
                  'Elbow face â†’ axis. For 90Â° LR: â‰ˆ1.5Ã—OD',
                ),
                onChanged: _calc,
              ),
            ),
            const SizedBox(width: 8),
            // Auto-wyszukaj po OD
            SizedBox(
              width: 90,
              child: _NumField(
                controller: _odCtrl,
                label: 'OD (mm)',
                hint: '60.3',
                onChanged: null,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: IconButton(
                icon: const Icon(Icons.search, color: _kOrange),
                tooltip: _tr('Szukaj w bibliotece', 'Search in library'),
                onPressed: _lookupAxis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Gap
        _NumField(
          controller: _gapCtrl,
          label: _tr('Gap na spoinÄ™ (mm)', 'Weld gap (mm)'),
          hint: '2',
          unit: 'mm',
          onChanged: _calc,
        ),
        const SizedBox(height: 16),
        const Divider(color: _kBorder),
        const SizedBox(height: 12),

        // Tryb podania offsetu
        _SectionLabel(_tr('Jak podajesz odlegÅ‚oÅ›Ä‡?', 'How do you enter the distance?')),
        _OffsetModeSelector(
          mode: _offsetMode,
          onChanged: (m) => setState(() {
            _offsetMode = m;
            _calc();
          }),
        ),
        const SizedBox(height: 12),

        // Pola offsetu
        if (_offsetMode == 'DIRECT') ...[
          _InfoBox(_tr(
            'Wpisz odlegÅ‚oÅ›Ä‡ miÄ™dzy osiami rur A i B '
            '(np. zmierzonÄ… taÅ›mÄ… miÄ™dzy Å›rodkami rur).',
            'Enter the distance between pipe A and B axes '
            '(e.g. measured with a tape between pipe centres).',
          )),
          _NumField(
            controller: _offsetCtrl,
            label: _tr('OdlegÅ‚oÅ›Ä‡ miÄ™dzy osiami â€” OFFSET (mm)', 'Distance between axes â€” OFFSET (mm)'),
            hint: 'np. 200',
            unit: 'mm',
            onChanged: _calc,
          ),
        ] else if (_offsetMode == 'D1D2_SUM') ...[
          _InfoBox(_tr(
            'ZmierzyÅ‚eÅ› od kaÅ¼dej Å›ciany/punktu do swojej rury.\n'
            'OFFSET = D1 + D2  (rury wychodzÄ… z przeciwnych Å›cian).',
            'You measured from each wall to its pipe.\n'
            'OFFSET = D1 + D2  (pipes emerge from opposite walls).',
          )),
          Row(children: [
            Expanded(
                child: _NumField(
                    controller: _d1Ctrl,
                    label: _tr('D1 â€” od Å›ciany 1 do osi rury A', 'D1 â€” wall 1 to pipe A'),
                    hint: 'mm',
                    unit: 'mm',
                    onChanged: _calc)),
            const SizedBox(width: 10),
            Expanded(
                child: _NumField(
                    controller: _d2Ctrl,
                    label: _tr('D2 â€” od Å›ciany 2 do osi rury B', 'D2 â€” wall 2 to pipe B'),
                    hint: 'mm',
                    unit: 'mm',
                    onChanged: _calc)),
          ]),
        ] else ...[
          _InfoBox(_tr(
            'ZmierzyÅ‚eÅ› oba wymiary od TEGO SAMEGO punktu referencyjnego.\n'
            'OFFSET = |D2 âˆ’ D1|  (rury sÄ… po tej samej stronie).',
            'Both measurements from the SAME reference point.\n'
            'OFFSET = |D2 âˆ’ D1|.',
          )),
          Row(children: [
            Expanded(
                child: _NumField(
                    controller: _d1Ctrl,
                    label: _tr('D1 â€” oÅ› rury A od ref.', 'D1 â€” pipe A from ref.'),
                    hint: 'mm',
                    unit: 'mm',
                    onChanged: _calc)),
            const SizedBox(width: 10),
            Expanded(
                child: _NumField(
                    controller: _d2Ctrl,
                    label: _tr('D2 â€” oÅ› rury B od ref.', 'D2 â€” pipe B from ref.'),
                    hint: 'mm',
                    unit: 'mm',
                    onChanged: _calc)),
          ]),
        ],

        const SizedBox(height: 16),

        // Wyniki
        if (_offset != null && _axisMm != null && _travel != null && _cutMm != null)
          _ResultCard(children: [
            _ResultRow(
              label: _tr('Offset (odl. miÄ™dzy osiami)', 'Offset (between axes)'),
              value: '${_offset!.toStringAsFixed(1)} mm',
            ),
            if (_elbowAngle != '90')
              _ResultRow(
                label: _tr('Travel (oÅ› Å‚Ä…czÄ…ca kolan)', 'Travel (elbow-to-elbow axis)'),
                value: '${_travel!.toStringAsFixed(1)} mm',
                dimmed: true,
              ),
            _ResultRow(
              label: 'âˆ’ 2 Ã— axisMm',
              value: 'âˆ’ ${(2 * _axisMm!).toStringAsFixed(1)} mm',
              dimmed: true,
            ),
            if ((double.tryParse(_gapCtrl.text.replaceAll(',', '.')) ?? 0) > 0)
              _ResultRow(
                label: 'âˆ’ 2 Ã— gap',
                value: 'âˆ’ ${(2 * (double.tryParse(_gapCtrl.text.replaceAll(',', '.')) ?? 0)).toStringAsFixed(1)} mm',
                dimmed: true,
              ),
            const Divider(height: 16, color: _kBorder),
            _ResultRow(
              label: _tr('Rura Å‚Ä…czÄ…ca â€” CUT', 'Connecting pipe â€” CUT'),
              value: '${_cutMm!.toStringAsFixed(1)} mm',
              primary: _cutMm! > 0,
            ),
            if (_cutMm! > 0) ...[
              const SizedBox(height: 10),
              Text(
                _tr(
                  'Zaznacz kolanko:\n'
                  '  â€¢ DÅ‚ugi bok (extrados): ${(_axisMm! * math.pi / 2).toStringAsFixed(1)} mm od czoÅ‚a\n'
                  '  â€¢ KrÃ³tki bok (intrados): ${(_axisMm! * math.pi / 2 - (_axisMm!)).toStringAsFixed(1)} mm od czoÅ‚a',
                  'Mark the elbow:\n'
                  '  â€¢ Long side (extrados): ${(_axisMm! * math.pi / 2).toStringAsFixed(1)} mm from face\n'
                  '  â€¢ Short side (intrados): ${(_axisMm! * math.pi / 2 - (_axisMm!)).toStringAsFixed(1)} mm from face',
                ),
                style: const TextStyle(fontSize: 11, color: _kSec, height: 1.6),
              ),
            ],
          ]),

        if (_error != null) _ErrorBox(_error!),

        // Zapis axisMm do historii
        if (_axisMm != null && _odCtrl.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton.icon(
              icon: const Icon(Icons.save_alt, size: 16),
              label: Text(_tr(
                  'ZapamiÄ™taj wymiar kolanka OD ${_odCtrl.text} = ${_axisMm!.toStringAsFixed(1)} mm',
                  'Remember elbow dim OD ${_odCtrl.text} = ${_axisMm!.toStringAsFixed(1)} mm')),
              onPressed: () {
                _axisHistory[_odCtrl.text.replaceAll(',', '.')] = _axisMm!;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_tr('ZapamiÄ™tano', 'Saved')),
                  backgroundColor: _kGreen,
                ));
              },
            ),
          ),
      ],
    );
  }
}

// â”€â”€ Selektor trybu offsetu â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _OffsetModeSelector extends StatelessWidget {
  final String mode;
  final void Function(String) onChanged;
  const _OffsetModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      ('DIRECT',   context.tr(pl: 'WpisujÄ™ offset', en: 'Enter offset')),
      ('D1D2_SUM', context.tr(pl: 'D1 + D2', en: 'D1 + D2')),
      ('D1D2_DIFF',context.tr(pl: '|D2 âˆ’ D1|', en: '|D2 âˆ’ D1|')),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final selected = mode == opt.$1;
        return GestureDetector(
          onTap: () => onChanged(opt.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? _kOrange.withValues(alpha: 0.12) : _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? _kOrange : _kBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              opt.$2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? _kOrange : _kSec,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// â”€â”€ Diagram etaÅ¼u â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _EtazDiagram extends StatelessWidget {
  final String angle;
  final double? offset;
  final double? axisMm;
  final double? cutMm;

  const _EtazDiagram({
    required this.angle,
    required this.offset,
    required this.axisMm,
    required this.cutMm,
  });

  @override
  Widget build(BuildContext context) {
    final is90 = angle == '90';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                pl: 'Schemat etaÅ¼u $angleÂ°', en: '$angleÂ° offset diagram'),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: _kMuted),
          ),
          const SizedBox(height: 10),
          // Prosty diagram ASCII w widgecie
          CustomPaint(
            size: const Size(double.infinity, 100),
            painter: _EtazPainter(
              is90: is90,
              offset: offset,
              axisMm: axisMm,
              cutMm: cutMm,
            ),
          ),
          if (offset != null && axisMm != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DiagLabel('axisMm = ${axisMm!.toStringAsFixed(1)} mm', _kSec),
                _DiagLabel('OFFSET = ${offset!.toStringAsFixed(1)} mm', _kBlue),
                if (cutMm != null)
                  _DiagLabel(
                    'CUT = ${cutMm!.toStringAsFixed(1)} mm',
                    cutMm! > 0 ? _kOrange : _kRed,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _DiagLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600));
}

class _EtazPainter extends CustomPainter {
  final bool is90;
  final double? offset;
  final double? axisMm;
  final double? cutMm;

  const _EtazPainter({
    required this.is90,
    required this.offset,
    required this.axisMm,
    required this.cutMm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pipeColor = const Color(0xFF2C3354);
    final elbColor  = const Color(0xFF4A9EFF);
    final cutColor  = (cutMm != null && cutMm! > 0)
        ? const Color(0xFFF5A623)
        : const Color(0xFFE74C3C);
    final stroke3 = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round;
    final stroke4 = Paint()..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;

    final W = size.width;
    final H = size.height;

    if (is90) {
      // Rura A (pozioma, lewa)
      canvas.drawLine(Offset(0, H * 0.25), Offset(W * 0.35, H * 0.25),
          stroke3..color = pipeColor);
      // Kolano 1
      canvas.drawLine(Offset(W * 0.35, H * 0.25), Offset(W * 0.35, H * 0.75),
          stroke4..color = elbColor);
      // Rura CUT (pionowa)
      if (cutMm != null && (H * 0.75 - H * 0.25) > 20) {
        canvas.drawLine(Offset(W * 0.5, H * 0.25 + 4), Offset(W * 0.5, H * 0.75 - 4),
            stroke4..color = cutColor);
      }
      // Kolano 2
      canvas.drawLine(Offset(W * 0.65, H * 0.25), Offset(W * 0.65, H * 0.75),
          stroke4..color = elbColor);
      // Rura B (pozioma, prawa)
      canvas.drawLine(Offset(W * 0.65, H * 0.75), Offset(W, H * 0.75),
          stroke3..color = pipeColor);
      // StrzaÅ‚ka offset
      final arrowPaint = Paint()
        ..color = const Color(0xFF55607A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawLine(Offset(W * 0.85, H * 0.28), Offset(W * 0.85, H * 0.72), arrowPaint);
      canvas.drawLine(Offset(W * 0.82, H * 0.32), Offset(W * 0.85, H * 0.28), arrowPaint);
      canvas.drawLine(Offset(W * 0.88, H * 0.32), Offset(W * 0.85, H * 0.28), arrowPaint);
      canvas.drawLine(Offset(W * 0.82, H * 0.68), Offset(W * 0.85, H * 0.72), arrowPaint);
      canvas.drawLine(Offset(W * 0.88, H * 0.68), Offset(W * 0.85, H * 0.72), arrowPaint);
    } else {
      // 45Â° â€” linie ukoÅ›ne
      canvas.drawLine(Offset(0, H * 0.2), Offset(W * 0.3, H * 0.2),
          stroke3..color = pipeColor);
      canvas.drawLine(Offset(W * 0.3, H * 0.2), Offset(W * 0.5, H * 0.8),
          stroke4..color = elbColor);
      if (cutMm != null && cutMm! > 0) {
        canvas.drawLine(Offset(W * 0.5, H * 0.8), Offset(W * 0.5, H * 0.8),
            stroke4..color = cutColor);
      }
      canvas.drawLine(Offset(W * 0.5, H * 0.8), Offset(W * 0.7, H * 0.2),
          stroke4..color = elbColor);
      canvas.drawLine(Offset(W * 0.7, H * 0.2), Offset(W, H * 0.2),
          stroke3..color = pipeColor);
    }
  }

  @override
  bool shouldRepaint(covariant _EtazPainter old) =>
      old.offset != offset || old.axisMm != axisMm || old.cutMm != cutMm;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  TAB 2: PROSTA WSTAWKA
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ProstaTab extends StatefulWidget {
  const _ProstaTab();
  @override
  State<_ProstaTab> createState() => _ProstaTabState();
}

class _ProstaTabState extends State<_ProstaTab> {
  final _spanCtrl  = TextEditingController();
  final _off1Ctrl  = TextEditingController();
  final _off2Ctrl  = TextEditingController();
  final _gapCtrl   = TextEditingController(text: '0');

  double? _cutMm;
  String? _error;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _spanCtrl.dispose();
    _off1Ctrl.dispose();
    _off2Ctrl.dispose();
    _gapCtrl.dispose();
    super.dispose();
  }

  void _calc() {
    setState(() {
      _error = null;
      _cutMm = null;

      final span = double.tryParse(_spanCtrl.text.replaceAll(',', '.'));
      if (span == null || span <= 0) {
        _error = _tr('Podaj wymiar caÅ‚kowity (mm)', 'Enter total dimension (mm)');
        return;
      }

      final off1 = double.tryParse(_off1Ctrl.text.replaceAll(',', '.')) ?? 0.0;
      final off2 = double.tryParse(_off2Ctrl.text.replaceAll(',', '.')) ?? 0.0;
      final gap  = double.tryParse(_gapCtrl.text.replaceAll(',', '.')) ?? 0.0;

      _cutMm = span - off1 - off2 - 2 * gap;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        _InfoBox(_tr(
          'Dwa punkty w jednej linii. Zmierz caÅ‚kowity wymiar SPAN '
          'miÄ™dzy dwoma punktami referencyjnymi, nastÄ™pnie podaj '
          'ile kaÅ¼dy element "zajmuje" z tego wymiaru.',
          'Two coaxial points. Measure the total SPAN between two '
          'reference points, then enter how much each fitting takes '
          'from that dimension.',
        )),

        // Diagram
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(pl: 'Schemat prostej wstawki', en: 'Straight run diagram'),
                style: const TextStyle(fontSize: 11, color: _kMuted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Komp 1
                  Container(
                    width: 60, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22263A),
                      border: Border.all(color: _kBorder),
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomLeft: Radius.circular(4)),
                    ),
                    child: const Center(
                        child: Text('KOMP\n1',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 9, color: _kSec))),
                  ),
                  // Rura CUT
                  Expanded(
                    child: Container(
                      height: 36,
                      color: _kOrange.withValues(alpha: 0.15),
                      child: Center(
                        child: Text(
                          _cutMm != null
                              ? 'CUT: ${_cutMm!.toStringAsFixed(1)} mm'
                              : _tr('Rura CUT', 'Pipe CUT'),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _kOrange),
                        ),
                      ),
                    ),
                  ),
                  // Komp 2
                  Container(
                    width: 60, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22263A),
                      border: Border.all(color: _kBorder),
                      borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(4),
                          bottomRight: Radius.circular(4)),
                    ),
                    child: const Center(
                        child: Text('KOMP\n2',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 9, color: _kSec))),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('â† off1 â†’', style: TextStyle(fontSize: 9, color: _kMuted)),
                  Text(
                    'â†â”€â”€â”€â”€â”€â”€ SPAN â”€â”€â”€â”€â”€â”€â†’',
                    style: const TextStyle(fontSize: 9, color: _kSec),
                  ),
                  const Text('â† off2 â†’', style: TextStyle(fontSize: 9, color: _kMuted)),
                ],
              ),
            ],
          ),
        ),

        // SPAN
        _SectionLabel(_tr('Wymiar caÅ‚kowity', 'Total dimension')),
        _NumField(
          controller: _spanCtrl,
          label: _tr('SPAN â€” wymiar z rysunku/pomiaru (mm)', 'SPAN â€” measured/drawing dimension (mm)'),
          hint: 'np. 1500',
          unit: 'mm',
          helperText: _tr(
            'CaÅ‚kowity wymiar od punktu ref. 1 do punktu ref. 2',
            'Total dimension from ref. point 1 to ref. point 2',
          ),
          onChanged: _calc,
        ),
        const SizedBox(height: 16),

        // Komponenty
        _SectionLabel(_tr('Komponenty', 'Fittings')),
        Row(children: [
          Expanded(
            child: _NumField(
              controller: _off1Ctrl,
              label: _tr('Offset komp. 1 (mm)', 'Fitting 1 offset (mm)'),
              hint: '0',
              unit: 'mm',
              helperText: _tr('0 = czoÅ‚o, axisMm = do osi', '0 = face, axisMm = to axis'),
              onChanged: _calc,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _NumField(
              controller: _off2Ctrl,
              label: _tr('Offset komp. 2 (mm)', 'Fitting 2 offset (mm)'),
              hint: '0',
              unit: 'mm',
              helperText: _tr('0 = czoÅ‚o, axisMm = do osi', '0 = face, axisMm = to axis'),
              onChanged: _calc,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _NumField(
          controller: _gapCtrl,
          label: _tr('Gap na spoinÄ™ (mm)', 'Weld gap (mm)'),
          hint: '2',
          unit: 'mm',
          onChanged: _calc,
        ),
        const SizedBox(height: 16),

        // Wyniki
        if (_cutMm != null)
          _ResultCard(children: [
            _ResultRow(label: 'SPAN', value: '${double.tryParse(_spanCtrl.text.replaceAll(",","."))?.toStringAsFixed(1) ?? "?"} mm'),
            if ((double.tryParse(_off1Ctrl.text.replaceAll(',', '.')) ?? 0) > 0)
              _ResultRow(
                  label: _tr('âˆ’ offset 1', 'âˆ’ offset 1'),
                  value: 'âˆ’ ${(double.tryParse(_off1Ctrl.text.replaceAll(',', '.')) ?? 0).toStringAsFixed(1)} mm',
                  dimmed: true),
            if ((double.tryParse(_off2Ctrl.text.replaceAll(',', '.')) ?? 0) > 0)
              _ResultRow(
                  label: _tr('âˆ’ offset 2', 'âˆ’ offset 2'),
                  value: 'âˆ’ ${(double.tryParse(_off2Ctrl.text.replaceAll(',', '.')) ?? 0).toStringAsFixed(1)} mm',
                  dimmed: true),
            if ((double.tryParse(_gapCtrl.text.replaceAll(',', '.')) ?? 0) > 0)
              _ResultRow(
                  label: _tr('âˆ’ 2 Ã— gap', 'âˆ’ 2 Ã— gap'),
                  value: 'âˆ’ ${(2 * (double.tryParse(_gapCtrl.text.replaceAll(',', '.')) ?? 0)).toStringAsFixed(1)} mm',
                  dimmed: true),
            const Divider(height: 16, color: _kBorder),
            _ResultRow(
              label: _tr('Rura â€” CUT', 'Pipe â€” CUT'),
              value: '${_cutMm!.toStringAsFixed(1)} mm',
              primary: _cutMm! > 0,
            ),
          ]),

        if (_error != null) _ErrorBox(_error!),
      ],
    );
  }
}

extension on Color {
  Color get shade300 => withValues(alpha: 0.85);
}
