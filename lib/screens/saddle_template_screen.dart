// ignore_for_file: prefer_const_constructors

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/saddle_template.dart';

// Saddle / coping template screen — inputs header + branch OD + angle,
// shows live preview of the cut profile, and exports a printable PDF
// template (offset table + scaled preview + 1:1 strip pages).
//
// Premium-tagged (PRO badge in title). Free while the global gate flag
// stays off; will be paywalled when `kPremiumGateEnforced` flips to true.

const _kBg = Color(0xFF0F1117);
const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kAccent = Color(0xFF26A69A);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);
const _kGold = Color(0xFFE8C14B);
const _kAccentDim = Color(0x3326A69A);

class SaddleTemplateScreen extends StatefulWidget {
  const SaddleTemplateScreen({super.key});

  @override
  State<SaddleTemplateScreen> createState() => _SaddleTemplateScreenState();
}

class _SaddleTemplateScreenState extends State<SaddleTemplateScreen> {
  final _headerCtrl = TextEditingController(text: '114.3');
  final _branchCtrl = TextEditingController(text: '60.3');
  final _projectCtrl = TextEditingController();
  double _angleDeg = 90;

  SaddleTemplate? _template;
  String? _errorMessage;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _branchCtrl.dispose();
    _projectCtrl.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  void _recompute() {
    final h = _parse(_headerCtrl);
    final b = _parse(_branchCtrl);
    try {
      setState(() {
        _template = SaddleTemplate(
          headerOdMm: h,
          branchOdMm: b,
          angleDeg: _angleDeg,
        );
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _template = null;
        _errorMessage = _localizeError(e);
      });
    }
  }

  // Service throws English-only ArgumentErrors; remap the known cases to
  // bilingual messages so the _ErrorBox isn't English-only for PL users.
  // Uses the static current language because _recompute may run from
  // initState where InheritedWidget lookups are not allowed.
  String _localizeError(Object e) {
    final raw = e is ArgumentError ? e.message.toString() : e.toString();
    final isEn = AppLanguageController.isEnglish;
    final h = _headerCtrl.text.trim();
    final b = _branchCtrl.text.trim();
    if (raw.contains('Branch OD') && raw.contains('header OD')) {
      return isEn
          ? 'Branch OD ($b) must be ≤ header OD ($h)'
          : 'OD rury bocznej ($b) musi być ≤ OD rury głównej ($h)';
    }
    if (raw.contains('Angle must be')) {
      final a = _angleDeg.toStringAsFixed(0);
      return isEn
          ? 'Angle must be in [15°, 90°], got $a°'
          : 'Kąt musi być w zakresie [15°, 90°], wpisano $a°';
    }
    return raw;
  }

  // Welder/fitter usually inherits a "fish-mouth" tool with no explanation —
  // a tap on (i) shows the actual math so they trust the output and can
  // sanity-check edge cases (e.g. equal OD, shallow angles).
  void _showFormulaHelp() {
    final isEn = AppLanguageController.isEnglish;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.functions, color: _kAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              isEn ? 'How is it calculated?' : 'Jak to się liczy?',
              style: const TextStyle(color: Color(0xFFE8ECF0), fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEn
                    ? 'Branch (R_b) crosses header (R_h). For a point at angle φ around the branch:'
                    : 'Rura boczna (R_b) przebija rurę główną (R_h). Dla punktu pod kątem φ wokół rury bocznej:',
                style: const TextStyle(color: _kTextSec, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Text(
                  'd(φ) = R_h − √(R_h² − R_b²·sin²φ)\n'
                  'wrap = 2π·R_b\n'
                  'tilt: d/sin(α) + R_b·cos(α)·cosφ',
                  style: const TextStyle(
                    color: _kAccent,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isEn
                    ? 'd = cut depth, α = branch angle. Profile is sampled every 5° (72 points) — exported PDF table prints offsets every 15°.'
                    : 'd = głębokość cięcia, α = kąt rury bocznej. Profil próbkowany co 5° (72 pkt) — tabela w PDF wypisuje offsety co 15°.',
                style: const TextStyle(color: _kTextSec, fontSize: 11, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                isEn
                    ? 'Reference: standard saddle / fish-mouth geometry, e.g. Pipe Fitter\'s Blue Book (Hawkins).'
                    : 'Źródło: standardowa geometria fish-mouth, np. Pipe Fitter\'s Blue Book (Hawkins).',
                style: const TextStyle(color: _kTextMut, fontSize: 10, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'OK',
              style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    final tpl = _template;
    if (tpl == null) return;
    setState(() => _exporting = true);
    try {
      await tpl.exportPdf(
        projectName: _projectCtrl.text.trim().isEmpty
            ? null
            : _projectCtrl.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              pl: 'Błąd eksportu PDF: $e',
              en: 'PDF export error: $e',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Row(
          children: [
            Text(context.tr(pl: 'Saddle / Coping', en: 'Saddle / Coping')),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kGold.withValues(alpha: 0.3)),
              ),
              child: Text(
                'PRO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _kGold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.tr(pl: 'Wzór i jak liczymy', en: 'Formula & how it works'),
            icon: Icon(Icons.help_outline, color: _kTextSec),
            onPressed: _showFormulaHelp,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionCard(
            title: context.tr(pl: 'Wymiary rur', en: 'Pipe dimensions'),
            child: Column(
              children: [
                _NumField(
                  label: context.tr(pl: 'OD rury głównej (header)', en: 'Header pipe OD'),
                  ctrl: _headerCtrl,
                  suffix: 'mm',
                  onChanged: _recompute,
                ),
                const SizedBox(height: 10),
                _NumField(
                  label: context.tr(pl: 'OD rury bocznej (branch)', en: 'Branch pipe OD'),
                  ctrl: _branchCtrl,
                  suffix: 'mm',
                  onChanged: _recompute,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(pl: 'Kąt przyłączenia', en: 'Connection angle'),
                        style: const TextStyle(color: _kTextSec, fontSize: 13),
                      ),
                    ),
                    Text(
                      '${_angleDeg.toStringAsFixed(0)}°',
                      style: const TextStyle(
                        color: _kAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _angleDeg,
                  min: 15,
                  max: 90,
                  divisions: 15,
                  activeColor: _kAccent,
                  inactiveColor: _kBorder,
                  onChanged: (v) {
                    setState(() => _angleDeg = v);
                    _recompute();
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final preset in [30.0, 45.0, 60.0, 75.0, 90.0])
                      _AngleChip(
                        label: '${preset.toStringAsFixed(0)}°',
                        active: (_angleDeg - preset).abs() < 0.5,
                        onTap: () {
                          setState(() => _angleDeg = preset);
                          _recompute();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: context.tr(pl: 'Opis (opcjonalnie)', en: 'Description (optional)'),
            child: TextField(
              controller: _projectCtrl,
              style: const TextStyle(color: Color(0xFFE8ECF0)),
              decoration: InputDecoration(
                hintText: context.tr(
                  pl: 'np. "Linia 12-WP-3045  /  TIE-IN B"',
                  en: 'e.g. "Line 12-WP-3045  /  TIE-IN B"',
                ),
                hintStyle: const TextStyle(color: _kTextMut, fontSize: 13),
                helperText: context.tr(
                  pl: 'Pojawi się na pierwszej stronie PDF — pomocne przy archiwizacji szablonu na linii',
                  en: 'Prints on PDF page 1 — handy when filing the template on the line',
                ),
                helperStyle: const TextStyle(color: _kTextMut, fontSize: 10),
                helperMaxLines: 2,
                filled: true,
                fillColor: _kBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _kAccent, width: 1.2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_errorMessage != null)
            _ErrorBox(message: _errorMessage!)
          else if (_template != null) ...[
            _PreviewCard(template: _template!),
            const SizedBox(height: 12),
            _MetricsRow(template: _template!),
            const SizedBox(height: 8),
            // Marking step hint — arc spacing between adjacent offset rows
            // (every 5° around the branch). Fitter wraps the paper strip and
            // can verify mark positions with a tape: "co X mm = 1 offset".
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Builder(
                builder: (ctx) {
                  final tpl = _template!;
                  final stepMm = tpl.points.length > 1
                      ? tpl.stripLengthMm / (tpl.points.length - 1)
                      : 0.0;
                  final stepDeg = tpl.points.length > 1
                      ? 360.0 / (tpl.points.length - 1)
                      : 0.0;
                  return Row(
                    children: [
                      Icon(Icons.straighten, size: 13, color: _kTextMut),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ctx.tr(
                            pl: 'Znacznik co ${stepMm.toStringAsFixed(1)} mm '
                                '(krok ${stepDeg.toStringAsFixed(0)}°) wokół rury bocznej',
                            en: 'Mark every ${stepMm.toStringAsFixed(1)} mm '
                                '(${stepDeg.toStringAsFixed(0)}° step) around branch',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kTextSec,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _exporting ? null : _exportPdf,
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _exporting
                      ? context.tr(pl: 'Generowanie PDF…', en: 'Generating PDF…')
                      : context.tr(pl: 'Eksportuj szablon PDF', en: 'Export PDF template'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
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
                Icon(Icons.info_outline, size: 16, color: _kAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Szablon to "fish-mouth" — rozwinięty profil cięcia owijany na rurze bocznej. '
                          'PDF zawiera tabelę offsetów co 15° + preview + strony 1:1 do druku.',
                      en: 'Template is a "fish-mouth" — unrolled cut profile wrapped around the branch pipe. '
                          'PDF contains 15°-step offset table + scaled preview + 1:1 print pages.',
                    ),
                    style: const TextStyle(fontSize: 11, color: _kTextSec, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _kTextMut,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? suffix;
  final VoidCallback onChanged;
  const _NumField({
    required this.label,
    required this.ctrl,
    this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onChanged(),
      style: const TextStyle(color: Color(0xFFE8ECF0)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSec, fontSize: 12),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: _kTextMut, fontSize: 11),
        filled: true,
        fillColor: _kBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kAccent, width: 1.2),
        ),
      ),
    );
  }
}

class _AngleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _AngleChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Wrap in a 48px-tall SizedBox so the tap target meets glove-on-fingertip
    // minimums; visual chip stays compact via the inner Container.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 48,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active ? _kAccent.withValues(alpha: 0.18) : _kBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? _kAccent : _kBorder,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: active ? _kAccent : _kTextSec,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE57373).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE57373).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: const Color(0xFFE57373), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Color(0xFFE57373)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  final SaddleTemplate template;
  const _MetricsRow({required this.template});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Metric(
            label: context.tr(pl: 'Max głębokość', en: 'Max depth'),
            value: '${template.maxDepthMm.toStringAsFixed(1)} mm',
            altValue: _mmAsInches(template.maxDepthMm),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Metric(
            label: context.tr(pl: 'Owijka (obwód)', en: 'Wrap length'),
            value: '${template.stripLengthMm.toStringAsFixed(1)} mm',
            altValue: _mmAsFeetInches(template.stripLengthMm),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Metric(
            label: context.tr(pl: 'Punktów', en: 'Points'),
            value: '${template.points.length}',
          ),
        ),
      ],
    );
  }

  // Imperial hint for shops that still measure in inches. Welder sees
  // mm primarily (app base unit) and the inch reading right under it,
  // no toggle needed — glove-friendly.
  static String _mmAsInches(double mm) {
    final inches = mm / 25.4;
    return '${inches.toStringAsFixed(2)}"';
  }

  static String _mmAsFeetInches(double mm) {
    final totalInches = mm / 25.4;
    if (totalInches < 12) return '${totalInches.toStringAsFixed(1)}"';
    final feet = totalInches ~/ 12;
    final rem = totalInches - feet * 12;
    return '$feet\' ${rem.toStringAsFixed(1)}"';
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String? altValue;
  const _Metric({required this.label, required this.value, this.altValue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _kTextMut)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _kAccent,
            ),
          ),
          if (altValue != null)
            Text(
              altValue!,
              style: const TextStyle(fontSize: 10, color: _kTextMut),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Preview canvas — renders the cut profile using a CustomPainter.
// ═══════════════════════════════════════════════════════════════════════════
class _PreviewCard extends StatelessWidget {
  final SaddleTemplate template;
  const _PreviewCard({required this.template});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            context.tr(pl: 'PODGLĄD CIĘCIA', en: 'CUT PREVIEW'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _kTextMut,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 2.5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _CutProfilePainter(template),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              pl: 'Owijka od 0° do 360° wokół rury bocznej. Pionowo — głębokość cięcia.',
              en: 'Wrap from 0° to 360° around branch pipe. Vertical = cut depth.',
            ),
            style: const TextStyle(fontSize: 10, color: _kTextMut),
          ),
        ],
      ),
    );
  }
}

class _CutProfilePainter extends CustomPainter {
  final SaddleTemplate template;
  _CutProfilePainter(this.template);

  @override
  void paint(Canvas canvas, Size size) {
    // Background grid
    final bgPaint = Paint()..color = _kBg;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = _kBorder.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final pad = 14.0;
    final dw = size.width - pad * 2;
    final dh = size.height - pad * 2;
    if (dw <= 0 || dh <= 0 || template.points.isEmpty) return;

    final sx = dw / template.stripLengthMm;
    final maxD = math.max(template.maxDepthMm, 0.5);
    final sy = (dh * 0.85) / maxD;

    final baselineY = size.height - pad;

    // Fill
    final fillPath = Path();
    fillPath.moveTo(pad, baselineY);
    for (final p in template.points) {
      final x = pad + p.xMm * sx;
      final y = baselineY - p.depthMm * sy;
      fillPath.lineTo(x, y);
    }
    fillPath.lineTo(pad + template.stripLengthMm * sx, baselineY);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = _kAccentDim);

    // Stroke
    final strokePath = Path();
    bool first = true;
    for (final p in template.points) {
      final x = pad + p.xMm * sx;
      final y = baselineY - p.depthMm * sy;
      if (first) {
        strokePath.moveTo(x, y);
        first = false;
      } else {
        strokePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      strokePath,
      Paint()
        ..color = _kAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Baseline
    canvas.drawLine(
      Offset(pad, baselineY),
      Offset(pad + template.stripLengthMm * sx, baselineY),
      Paint()
        ..color = const Color(0xFFE8ECF0)
        ..strokeWidth = 1,
    );

    // 0°, 90°, 180°, 270°, 360° vertical guides
    for (final phi in [0, 90, 180, 270, 360]) {
      final phiRad = phi * math.pi / 180;
      final x = pad + (phiRad * template.branchOdMm / 2) * sx;
      canvas.drawLine(
        Offset(x, pad),
        Offset(x, baselineY),
        Paint()
          ..color = _kTextMut.withValues(alpha: 0.5)
          ..strokeWidth = 0.5,
      );
      _drawText(canvas, '$phi°', Offset(x - 8, pad - 2), 9, _kTextMut);
    }
  }

  void _drawText(Canvas canvas, String text, Offset pos, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_CutProfilePainter old) =>
      old.template.headerOdMm != template.headerOdMm ||
      old.template.branchOdMm != template.branchOdMm ||
      old.template.angleDeg != template.angleDeg;
}
