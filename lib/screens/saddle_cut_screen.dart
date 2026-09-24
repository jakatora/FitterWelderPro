import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/saddle_geometry.dart';
import '../utils/clipboard_helper.dart';
import '../widgets/calculation_guide.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

class SaddleCutScreen extends StatefulWidget {
  const SaddleCutScreen({super.key});

  @override
  State<SaddleCutScreen> createState() => _SaddleCutScreenState();
}

class _SaddleCutScreenState extends State<SaddleCutScreen> {
  final _headerOdController = TextEditingController();
  final _branchOdController = TextEditingController();
  _SaddleResult? _result;
  bool _submitted = false;
  String _lastHeaderText = '';
  String _lastBranchText = '';

  @override
  void initState() {
    super.initState();
    _headerOdController.addListener(_inputChanged);
    _branchOdController.addListener(_inputChanged);
  }

  void _inputChanged() {
    // Moving the cursor does not invalidate an otherwise current calculation.
    if (_lastHeaderText == _headerOdController.text &&
        _lastBranchText == _branchOdController.text) {
      return;
    }
    _lastHeaderText = _headerOdController.text;
    _lastBranchText = _branchOdController.text;
    setState(() => _result = null);
  }

  double? _parse(String text) =>
      parseDecimal(text);

  String? _odError(String text) {
    if (text.trim().isEmpty) {
      return context.tr(
          pl: 'Wpisz średnicę w mm', en: 'Enter a diameter in mm');
    }
    final value = _parse(text);
    if (value == null || !value.isFinite) {
      return context.tr(
          pl: 'Wpisz poprawną, skończoną liczbę',
          en: 'Enter a valid, finite number');
    }
    if (value <= 0 || value > 2000) {
      return context.tr(
          pl: 'Zakres: powyżej 0 do 2000 mm',
          en: 'Range: above 0 up to 2000 mm');
    }
    return null;
  }

  String? get _branchError {
    final error = _odError(_branchOdController.text);
    if (error != null) return error;
    if (_odError(_headerOdController.text) == null &&
        _parse(_branchOdController.text)! > _parse(_headerOdController.text)!) {
      return context.tr(
        pl: 'OD odgałęzienia nie może być większe od OD rury głównej',
        en: 'Branch OD cannot exceed header OD',
      );
    }
    return null;
  }

  // Centred 90-degree intersection, outside surfaces only.
  // Main axis x, branch axis z, branch body towards +z; y = r sin α.
  // The header surface gives z(α) = sqrt(R² - (r sin α)²).
  // Longest tips are at the smallest z: α=90/270, z_min=sqrt(R²-r²).
  // Axial CUTBACK from that plane towards the body is z(α)-z_min.
  // α=0/180 lies in the common plane of the pipe axes: maximum cutback.
  // Independent reference: R=50, r=30 -> h_max = 50 - sqrt(1600) = 10 mm.
  void _calculate() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitted = true;
      _result = null;
    });
    if (_odError(_headerOdController.text) != null || _branchError != null) {
      return;
    }

    final headerOd = _parse(_headerOdController.text)!;
    final branchOd = _parse(_branchOdController.text)!;
    final geometry = SaddleGeometry(
        headerOdMm: headerOd, branchOdMm: branchOd, angleDeg: 90);
    final hMax = geometry.maxDepthMm;
    final profile = <_SaddlePoint>[];
    for (var deg = 0; deg <= 360; deg += 15) {
      final point = geometry.pointAt(deg.toDouble());
      profile.add(_SaddlePoint(
        angle: deg,
        arc: point.xMm,
        depth: point.depthMm,
      ));
    }
    if (!hMax.isFinite ||
        profile.any((p) => !p.depth.isFinite || !p.arc.isFinite)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
        context.tr(
            pl: 'Nie można obliczyć profilu. Sprawdź średnice.',
            en: 'Cannot calculate the profile. Check the diameters.'),
      )));
      return;
    }
    setState(() => _result = _SaddleResult(
          headerOd: headerOd,
          branchOd: branchOd,
          hMax: hMax,
          profile: profile,
        ));
  }

  String get _limits => context.tr(
        pl: 'Bez uwzględnienia grubości ścianki, ukosowania, szczeliny i naddatków. '
            'Nie stosuj do odgałęzień ukośnych ani mimośrodowych. '
            'Przed cięciem sprawdź profil na materiale i wymagania dokumentacji.',
        en: 'Wall thickness, bevel, gap and allowances are not included. '
            'Do not use for angled or offset branches. '
            'Check the profile on the material and the project requirements before cutting.',
      );

  String get _orientation => context.tr(
        pl: '0° i 180°: punkty w płaszczyźnie obu osi — najgłębsze wycięcie. '
            '90° i 270°: najdłuższe końce rury — głębokość 0 mm.',
        en: '0° and 180°: points in the plane of both axes — deepest cut. '
            '90° and 270°: the longest pipe-end points — depth 0 mm.',
      );

  Future<void> _copyProfile() async {
    final result = _result;
    if (result == null) return;
    // Export only the input snapshot that produced this exact profile.
    final buffer = StringBuffer()
      ..writeln(context.tr(
          pl: 'Wycięcie siodłowe — centralne połączenie 90°',
          en: 'Saddle cut — centred 90° junction'))
      ..writeln(
          '${context.tr(pl: 'OD rury głównej', en: 'Header OD')}: ${guideNumber(result.headerOd)} mm')
      ..writeln(
          '${context.tr(pl: 'OD odgałęzienia', en: 'Branch OD')}: ${guideNumber(result.branchOd)} mm')
      ..writeln('h_max: ${result.hMax.toStringAsFixed(1)} mm')
      ..writeln(_orientation)
      ..writeln(context.tr(
          pl: 'Obwód: odległość po łuku od 0°. Głębokość: wzdłuż osi, od płaszczyzny prostopadłej do osi przechodzącej przez najdłuższe punkty, w stronę korpusu rury.',
          en: 'Circumference: arc distance from 0°. Depth: along the axis, from the plane perpendicular to the axis through the longest points, towards the pipe body.'))
      ..writeln(context.tr(
          pl: 'Kąt α\tNa obwodzie (mm)\tGłębokość (mm)',
          en: 'Angle α\tAlong circumference (mm)\tDepth (mm)'));
    for (final point in result.profile) {
      buffer.writeln(
          '${point.angle}°\t${point.arc.toStringAsFixed(1)}\t${point.depth.toStringAsFixed(1)}');
    }
    buffer
      ..writeln(context.tr(
          pl: '360° zamyka obwód w punkcie 0°. Wartości zaokrąglone do 0.1 mm.',
          en: '360° closes the circumference at 0°. Values rounded to 0.1 mm.'))
      ..writeln(_limits);
    await copyToClipboard(context, buffer.toString(),
        label: context.tr(
            pl: 'Skopiowano profil siodła', en: 'Saddle profile copied'));
  }

  @override
  void dispose() {
    _headerOdController.dispose();
    _branchOdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Wycięcie siodłowe', en: 'Saddle cut')),
        actions: [
          HelpButton(help: kHelpSaddleCut),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: context.tr(pl: 'Kopiuj profil', en: 'Copy profile'),
            onPressed: result == null ? null : _copyProfile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    context.tr(
                        pl: 'Centralne połączenie T • 90°',
                        en: 'Centred T-junction • 90°'),
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final fields = [
                    _field(_headerOdController,
                        label:
                            context.tr(pl: 'OD rury głównej', en: 'Header OD')),
                    _field(_branchOdController,
                        label:
                            context.tr(pl: 'OD odgałęzienia', en: 'Branch OD'),
                        branch: true),
                  ];
                  if (constraints.maxWidth < 520 ||
                      MediaQuery.textScalerOf(context).scale(16) > 22) {
                    return Column(children: [
                      fields[0],
                      const SizedBox(height: 16),
                      fields[1]
                    ]);
                  }
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 16),
                        Expanded(child: fields[1]),
                      ]);
                }),
                const SizedBox(height: 8),
                Text(
                    context.tr(
                        pl: 'OD to średnica zewnętrzna, nie DN. Odczytaj ją z dokumentacji rury lub zmierz. Zakres: > 0 do 2000 mm.',
                        en: 'OD means outside diameter, not DN. Read it from the pipe documentation or measure it. Range: > 0 up to 2000 mm.'),
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _calculate,
                  icon: const Icon(Icons.calculate_outlined),
                  label: Text(
                      context.tr(pl: 'Oblicz profil', en: 'Calculate profile')),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16)),
                ),
                if (result != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12)),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                context.tr(
                                    pl: 'Maks. głębokość cięcia (h_max)',
                                    en: 'Max. cut depth (h_max)'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            CopyOnLongPress(
                                value: result.hMax.toStringAsFixed(1),
                                label: 'h_max',
                                child: Text(
                                    '${result.hMax.toStringAsFixed(1)} mm',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                            color: theme
                                                .colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold))),
                            const SizedBox(height: 8),
                            Text(context.tr(
                                pl: 'W punktach 0° i 180°',
                                en: 'At 0° and 180°')),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                      context.tr(
                          pl: 'Profil 0–90° • co 15°',
                          en: 'Profile 0–90° • every 15°'),
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_orientation),
                  const SizedBox(height: 12),
                  _profileTable(result.profile.take(7)),
                  const SizedBox(height: 12),
                  Card.outlined(
                    margin: EdgeInsets.zero,
                    child: ExpansionTile(
                      key: const ValueKey('saddle-full-profile'),
                      title: Text(context.tr(
                          pl: 'Pełny obwód 0–360°',
                          en: 'Full circumference 0–360°')),
                      subtitle: Text(context.tr(
                          pl: '25 punktów z zamknięciem obwodu',
                          en: '25 points including closure')),
                      childrenPadding: const EdgeInsets.all(12),
                      children: [_profileTable(result.profile)],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      context.tr(
                          pl: '„Na obwodzie” mierz taśmą po łuku od 0°, nie w linii prostej. '
                              'Głębokość odmierzaj wzdłuż osi rury od płaszczyzny prostopadłej do osi, '
                              'przechodzącej przez najdłuższe punkty, w stronę korpusu rury. '
                              '360° wraca do 0°. Wartości zaokrąglone do 0.1 mm.',
                          en: 'Measure “Along circumference” with a tape along the arc from 0°, not in a straight line. '
                              'Measure depth along the pipe axis from the plane perpendicular to the axis '
                              'through the longest points, towards the pipe body. '
                              '360° returns to 0°. Values rounded to 0.1 mm.'),
                      style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                _guide(),
                const SizedBox(height: 16),
                Text(_limits, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guide() {
    final result = _result;
    final header = result?.headerOd ?? 100.0;
    final branch = result?.branchOd ?? 60.0;
    final radius = header / 2;
    final branchRadius = branch / 2;
    final hMax = result?.hMax ?? 10.0;
    return CalculationGuide(
      key: const ValueKey('saddle-guide'),
      hasResult: result != null,
      inputs: context.tr(
          pl: 'Podaj OD rury głównej i odgałęzienia. Odgałęzienie może mieć mniejszą lub taką samą średnicę. '
              'Ich osie muszą się przecinać pod kątem 90°. To profil zewnętrznych powierzchni rur.',
          en: 'Enter the header and branch OD. The branch can have a smaller or equal diameter. '
              'Their axes must intersect at 90°. This is the profile of the outside pipe surfaces.'),
      steps: [
        context.tr(
            pl: 'Promienie to połowy średnic: R = ${guideNumber(header)} / 2 = ${guideNumber(radius)} mm; '
                'r = ${guideNumber(branch)} / 2 = ${guideNumber(branchRadius)} mm.',
            en: 'Radii are half the diameters: R = ${guideNumber(header)} / 2 = ${guideNumber(radius)} mm; '
                'r = ${guideNumber(branch)} / 2 = ${guideNumber(branchRadius)} mm.'),
        'h_max = R − √(R² − r²)\n'
            '${guideNumber(radius)} − √(${guideNumber(radius)}² − ${guideNumber(branchRadius)}²) = ${hMax.toStringAsFixed(1)} mm',
        context.tr(
            pl: 'Dla każdego kąta: d(α) = √(R² − (r × sin α)²) − √(R² − r²). '
                'Przy 0° głębokość wynosi ${hMax.toStringAsFixed(1)} mm, a przy 90° wynosi 0 mm.',
            en: 'At each angle: d(α) = √(R² − (r × sin α)²) − √(R² − r²). '
                'Depth is ${hMax.toStringAsFixed(1)} mm at 0° and 0 mm at 90°.'),
        context.tr(
            pl: 'Obwód = π × ${guideNumber(branch)} = ${(math.pi * branch).toStringAsFixed(1)} mm. '
                'Odległość po łuku do punktu α = obwód × α / 360°. '
                'Zaznacz punkty na obwodzie, odłóż ich głębokości osiowo i połącz płynną krzywą. '
                'Przed cięciem sprawdź orientację i dopasowanie.',
            en: 'Circumference = π × ${guideNumber(branch)} = ${(math.pi * branch).toStringAsFixed(1)} mm. '
                'Arc distance to α = circumference × α / 360°. '
                'Mark the points around the circumference, mark each depth axially and join with a smooth curve. '
                'Check the orientation and fit before cutting.'),
      ],
      caution: context.tr(
          pl: 'Nie wpisuj DN zamiast OD. Nie zamieniaj odległości po obwodzie z głębokością wzdłuż osi. '
              'Wzór nie wyznacza ukosowania ani szczeliny spawalniczej.',
          en: 'Do not enter DN instead of OD. Do not confuse circumference distance with axial depth. '
              'The formula does not determine the weld bevel or gap.'),
    );
  }

  Widget _profileTable(Iterable<_SaddlePoint> profile) {
    final theme = Theme.of(context);
    // Keep numbers and headings readable with large system text; allow panning.
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(
          constraints.maxWidth, MediaQuery.textScalerOf(context).scale(300));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (width > constraints.maxWidth)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  context.tr(
                      pl: 'Przesuń tabelę w bok, aby zobaczyć głębokość.',
                      en: 'Scroll the table sideways to see the depth.'),
                  style: theme.textTheme.bodySmall)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Table(
              border: TableBorder.all(color: theme.colorScheme.outlineVariant),
              columnWidths: const {
                0: FlexColumnWidth(.7),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.1)
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                    decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh),
                    children: [
                      _cell(context.tr(pl: 'Kąt α', en: 'Angle α'), bold: true),
                      _cell(
                          context.tr(
                              pl: 'Na obwodzie\nmm',
                              en: 'Along circumference\nmm'),
                          bold: true),
                      _cell(context.tr(pl: 'Głębokość\nmm', en: 'Depth\nmm'),
                          bold: true),
                    ]),
                for (final point in profile)
                  TableRow(children: [
                    _cell('${point.angle}°'),
                    _cell(point.arc.toStringAsFixed(1)),
                    _cell(point.depth.toStringAsFixed(1))
                  ]),
              ],
            ),
          ),
        ),
      ]);
    });
  }

  Widget _cell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Text(text,
            style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      );

  Widget _field(TextEditingController controller,
      {required String label, bool branch = false}) {
    final showError = _submitted || controller.text.trim().isNotEmpty;
    return TextField(
      controller: controller,
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'mm',
        border: const OutlineInputBorder(),
        errorText: showError
            ? (branch ? _branchError : _odError(controller.text))
            : null,
        errorMaxLines: 4,
      ),
    );
  }
}

class _SaddleResult {
  final double headerOd;
  final double branchOd;
  final double hMax;
  final List<_SaddlePoint> profile;

  _SaddleResult(
      {required this.headerOd,
      required this.branchOd,
      required this.hMax,
      required List<_SaddlePoint> profile})
      : profile = List.unmodifiable(profile);
}

class _SaddlePoint {
  final int angle;
  final double arc;
  final double depth;
  const _SaddlePoint(
      {required this.angle, required this.arc, required this.depth});
}
