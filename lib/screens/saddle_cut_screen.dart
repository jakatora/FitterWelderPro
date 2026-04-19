import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

class SaddleCutScreen extends StatefulWidget {
  const SaddleCutScreen({super.key});

  @override
  State<SaddleCutScreen> createState() => _SaddleCutScreenState();
}

class _SaddleCutScreenState extends State<SaddleCutScreen> {
  final _headerOdController = TextEditingController();
  final _branchOdController = TextEditingController();

  double? _hMax;
  List<_SaddlePoint>? _profile;

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  // Saddle cut (fish-mouth cut) for a 90° branch-to-header intersection.
  //
  // The branch pipe is parameterised by angle α around its circumference,
  // where α=0° is the side of the branch (max cut depth) and α=90° is
  // the top/bottom of the branch (depth = 0, touches header apex).
  //
  // Depth at angle α:
  //   d(α) = R_header − √(R_header² − (r_branch × sin(α))²)
  //
  // Maximum depth (at α = 0°, i.e., the sides):
  //   h_max = R_header − √(R_header² − r_branch²)
  //
  // Verification (Header OD=219.1mm, Branch OD=114.3mm):
  //   R=109.55, r=57.15
  //   h_max = 109.55 − √(109.55²−57.15²)
  //         = 109.55 − √(11001.3−3266.1)
  //         = 109.55 − √7735.2
  //         = 109.55 − 87.95
  //         ≈ 21.6mm  ✓
  void _calculate() {
    final headerOd = _parse(_headerOdController.text);
    final branchOd = _parse(_branchOdController.text);

    if (headerOd <= 0 || branchOd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(pl: 'Wpisz OD nagłówka i odgałęzienia > 0', en: 'Enter header and branch OD > 0')),
      ));
      return;
    }
    if (branchOd >= headerOd) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'OD odgałęzienia musi być mniejsze od OD nagłówka',
          en: 'Branch OD must be smaller than header OD',
        )),
      ));
      return;
    }

    final R = headerOd / 2.0;
    final r = branchOd / 2.0;

    final hMax = R - math.sqrt(R * R - r * r);

    // Profile at every 15° (0°=side, 90°=top)
    final profile = <_SaddlePoint>[];
    for (int deg = 0; deg <= 90; deg += 15) {
      final rad   = deg * math.pi / 180.0;
      final sinA  = math.sin(rad);
      final depth = R - math.sqrt(R * R - (r * sinA) * (r * sinA));
      profile.add(_SaddlePoint(angle: deg, depth: depth));
    }

    setState(() {
      _hMax    = hMax;
      _profile = profile;
    });
  }

  @override
  void dispose() {
    _headerOdController.dispose();
    _branchOdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Saddle Cut – wycięcie siodłowe', en: 'Saddle Cut – fish-mouth cut')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context.tr(pl: 'DANE WEJŚCIOWE', en: 'INPUT DATA')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(
                _headerOdController,
                label: context.tr(pl: 'OD nagłówka (Header)', en: 'Header OD'),
                suffix: 'mm',
              )),
              const SizedBox(width: 12),
              Expanded(child: _field(
                _branchOdController,
                label: context.tr(pl: 'OD odgałęzienia (Branch)', en: 'Branch OD'),
                suffix: 'mm',
              )),
            ]),
            const SizedBox(height: 8),
            Text(
              context.tr(
                pl: 'Użyj zewnętrznej średnicy (OD). Np. DN200=219.1mm, DN100=114.3mm.',
                en: 'Use outside diameter (OD). E.g. DN200=219.1mm, DN100=114.3mm.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: Text(context.tr(pl: 'OBLICZ', en: 'CALCULATE')),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),

            if (_hMax != null) ...[
              const SizedBox(height: 24),
              _sectionLabel(context.tr(pl: 'WYNIKI', en: 'RESULTS')),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.content_cut, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(pl: 'Maks. głębokość cięcia (h_max)', en: 'Max. cut depth (h_max)'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_hMax!.toStringAsFixed(1)} mm',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        context.tr(pl: 'Wzór: R − √(R²−r²)', en: 'Formula: R − √(R²−r²)'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  )),
                ]),
              ),

              const SizedBox(height: 20),
              _sectionLabel(context.tr(pl: 'PROFIL CIĘCIA (α=0°: bok, α=90°: góra/dół)', en: 'CUT PROFILE (α=0°: side, α=90°: top/bottom)')),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'Głębokość na każdy kąt α wokół rury odgałęzienia:\nd(α) = R − √(R² − (r×sin α)²)',
                  en: 'Depth at each angle α around the branch pipe:\nd(α) = R − √(R² − (r×sin α)²)',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _profileTable(),

              const SizedBox(height: 16),
              Text(
                context.tr(
                  pl: 'Jak użyć: zaznacz głębokość na każdym zaznaczonym kącie dookoła rury odgałęzienia, połącz punkty krzywą i tnij.',
                  en: 'How to use: mark each depth at the corresponding angle around the branch pipe, connect the points with a smooth curve and cut.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profileTable() {
    final profile = _profile;
    if (profile == null) return const SizedBox();

    final cs = Theme.of(context).colorScheme;
    return Table(
      border: TableBorder.all(color: cs.outlineVariant, borderRadius: BorderRadius.circular(4)),
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(2),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: cs.surfaceContainerHigh),
          children: [
            _cell(context.tr(pl: 'Kąt α (°)', en: 'Angle α (°)'), bold: true),
            _cell(context.tr(pl: 'Głębokość (mm)', en: 'Depth (mm)'), bold: true),
          ],
        ),
        ...profile.map((p) => TableRow(children: [
          _cell('${p.angle}°'),
          _cell(p.depth.toStringAsFixed(1)),
        ])),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: Text(
        text,
        style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
  );

  Widget _field(TextEditingController ctrl,
      {required String label, String? suffix}) {
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

class _SaddlePoint {
  final int    angle;
  final double depth;
  const _SaddlePoint({required this.angle, required this.depth});
}
