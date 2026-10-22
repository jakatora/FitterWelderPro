// Obróbka cieplna PWHT — plan cyklu.
//
// Monter / spawacz / brygadzista sprawdza, czy spoina wymaga PWHT, w jakiej
// temperaturze wytrzymania, jak długo, z jaką maks. szybkością nagrzewania
// i chłodzenia powyżej temperatury kontrolnej i ile trwa kontrolowana część
// cyklu — i wysyła plan firmie wyżarzającej (tekst albo PDF).
//
// MODUŁ BEZPIECZEŃSTWA-KRYTYCZNY: liczby pochodzą z tabel normy
// (lib/domain/pwht/pwht_tables.dart — każda ze źródłem). Wiążące parametry
// podaje WPS / procedura PWHT i specyfikacja projektu — ekran mówi to
// na górze, na dole i w każdym udostępnionym planie.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../assistant/core/tool_bridge.dart';
import '../../domain/pwht/pwht_plan.dart';
import '../../domain/pwht/pwht_plan_text.dart';
import '../../i18n/app_language.dart';
import '../../services/pwht_plan_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import 'pwht_cycle_chart.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef PwhtShareText = Future<void> Function(String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef PwhtSharePdf = Future<void> Function(PwhtPlan plan, bool english);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Future<void> _defaultSharePdf(PwhtPlan plan, bool english) =>
    PwhtPlanExport.sharePdf(plan, english: english);

class PwhtPlannerPage extends StatefulWidget {
  const PwhtPlannerPage({
    super.key,
    this.shareText = _defaultShareText,
    this.sharePdf = _defaultSharePdf,
  });

  final PwhtShareText shareText;
  final PwhtSharePdf sharePdf;

  @override
  State<PwhtPlannerPage> createState() => _PwhtPlannerPageState();
}

class _PwhtPlannerPageState extends State<PwhtPlannerPage>
    with ToolHandleHost<PwhtPlannerPage>
    implements InputToolHandle {
  PwhtCode _code = PwhtCode.values.first;
  PwhtMaterial _material = PwhtMaterial.p1;
  final _t = TextEditingController();
  final _od = TextEditingController();
  final _ww = TextEditingController();
  bool _busy = false;

  @override
  String get toolId => 'pwht_planner';
  @override
  Set<String> get supportedFields =>
      const {'code', 'material', 'thickness_mm', 'od_mm', 'weld_width_mm'};
  @override
  Map<String, Object?> get inputFields => Map.unmodifiable({
        'code': _code.name,
        'material': _material.name,
        'thickness_mm': parseDecimal(_t.text),
        'od_mm': parseDecimal(_od.text),
        'weld_width_mm': parseDecimal(_ww.text),
      });

  @override
  void initState() {
    super.initState();
    markReady();
  }

  /// Asystent: norma, grupa (tylko z tabeli tej normy), grubość, opcjonalnie
  /// OD i szerokość lica. Puste opcjonalne pola są czyszczone.
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted || fields.keys.any((k) => !supportedFields.contains(k))) {
      return fields.keys.toSet();
    }
    final code =
        PwhtCode.values.where((c) => c.name == fields['code']).firstOrNull;
    final material = PwhtMaterial.values
        .where((m) => m.name == fields['material'])
        .firstOrNull;
    bool positive(Object? v) => v is num && v.isFinite && v > 0;
    final rejected = <String>{
      if (code == null) 'code',
      if (material == null ||
          (code != null && !pwhtMaterialsFor(code).contains(material)))
        'material',
      if (!positive(fields['thickness_mm'])) 'thickness_mm',
      for (final key in const ['od_mm', 'weld_width_mm'])
        if (fields.containsKey(key) && !positive(fields[key])) key,
    };
    if (rejected.isNotEmpty) return rejected;
    String text(String key) =>
        fields[key] is num ? (fields[key] as num).toString() : '';
    setState(() {
      _code = code!;
      _material = material!;
      _t.text = text('thickness_mm');
      _od.text = text('od_mm');
      _ww.text = text('weld_width_mm');
    });
    return {};
  }

  @override
  void dispose() {
    _t.dispose();
    _od.dispose();
    _ww.dispose();
    super.dispose();
  }

  // ── Pola ────────────────────────────────────────────────────────────────

  /// Liczba dodatnia z pola albo null (puste / błędne / ≤ 0).
  static double? _positive(TextEditingController c) {
    final v = parseDecimal(c.text);
    if (v == null || !v.isFinite || v <= 0) return null;
    return v;
  }

  String? _fieldError(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    final v = parseDecimal(text);
    if (v == null || !v.isFinite) {
      return context.tr(pl: 'Nieprawidłowa liczba', en: 'Invalid number');
    }
    if (v <= 0) {
      return context.tr(pl: 'Wartość musi być > 0', en: 'Value must be > 0');
    }
    return null;
  }

  String? get _odError {
    final base = _fieldError(_od);
    if (base != null) return base;
    final od = _positive(_od);
    final t = _positive(_t);
    if (od != null && t != null && od <= 2 * t) {
      return context.tr(
          pl: 'Średnica musi być większa niż 2 × grubość',
          en: 'Diameter must be larger than 2 × thickness');
    }
    return null;
  }

  PwhtPlan? get _plan {
    final t = _positive(_t);
    if (t == null) return null;
    final odOk = _odError == null;
    return planPwht(PwhtInput(
      code: _code,
      material: _material,
      thicknessMm: t,
      outsideDiameterMm: odOk ? _positive(_od) : null,
      weldWidthMm: _positive(_ww),
    ));
  }

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _shareText(PwhtPlan plan) async {
    final en = context.language == AppLanguage.en;
    final subject = context.tr(pl: 'Plan PWHT', en: 'PWHT plan');
    unawaited(Haptic.tap());
    await widget.shareText(pwhtPlanText(plan, english: en), subject);
  }

  Future<void> _sharePdf(PwhtPlan plan) async {
    if (_busy) return;
    final en = context.language == AppLanguage.en;
    setState(() => _busy = true);
    try {
      await widget.sharePdf(plan, en);
    } catch (e) {
      debugPrint('[pwht] pdf export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się przygotować PDF.',
              en: 'Could not prepare the PDF.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Plan PWHT', en: 'PWHT plan')),
        actions: [
          IconButton(
            key: const ValueKey('pwht-appbar-share'),
            tooltip: context.tr(pl: 'Udostępnij plan', en: 'Share plan'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: plan == null ? null : () => _shareText(plan),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _Disclaimer(text: pwhtDisclaimer(english: en)),
          const SizedBox(height: 12),
          _Section(
            title: context.tr(pl: 'Norma', en: 'Code'),
            child: _codeChips(en),
          ),
          const SizedBox(height: 10),
          _Section(
            title: context.tr(pl: 'Grupa materiału', en: 'Material group'),
            child: _materialPicker(en),
          ),
          const SizedBox(height: 10),
          _Section(
            title: context.tr(pl: 'Złącze', en: 'Joint'),
            child: _inputs(),
          ),
          const SizedBox(height: 10),
          if (plan == null)
            _Hint(
              text: context.tr(
                  pl: 'Wpisz grubość, żeby zobaczyć plan PWHT.',
                  en: 'Enter the thickness to see the PWHT plan.'),
            )
          else
            ..._results(plan, en),
          const SizedBox(height: 12),
          _Disclaimer(text: pwhtDisclaimer(english: en)),
        ],
      ),
    );
  }

  Widget _codeChips(bool en) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in PwhtCode.values)
              ChoiceChip(
                key: ValueKey('pwht-code-${c.name}'),
                label: Text(c.label),
                selected: _code == c,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  unawaited(Haptic.tap());
                  setState(() {
                    _code = c;
                    if (!pwhtMaterialsFor(c).contains(_material)) {
                      _material = pwhtMaterialsFor(c).first;
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          en ? _code.scopeEn : _code.scopePl,
          style: const TextStyle(fontSize: 12, color: kTextMut, height: 1.4),
        ),
      ],
    );
  }

  Widget _materialPicker(bool en) {
    final info = pwhtMaterialInfo(_material);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in pwhtMaterialsFor(_code))
              ChoiceChip(
                key: ValueKey('pwht-material-${m.name}'),
                label: Text(pwhtMaterialInfo(m).pNo),
                selected: _material == m,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  unawaited(Haptic.tap());
                  setState(() => _material = m);
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${info.pNo} · ${en ? info.alloyEn : info.alloyPl}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: kText),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                    pl: 'Typowy odpowiednik EN ISO 15608: gr. ${info.isoGroup}',
                    en: 'Typical EN ISO 15608 equivalent: gr. ${info.isoGroup}'),
                style: const TextStyle(fontSize: 12, color: kTextSec),
              ),
              const SizedBox(height: 2),
              Text(
                info.grades,
                style:
                    const TextStyle(fontSize: 12, color: kTextSec, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                    pl: 'P-No i grupy ISO 15608 nie pokrywają się 1:1 — grupę '
                        'materiału bierz z WPS.',
                    en: 'P-Nos and ISO 15608 groups are not a 1:1 match — take '
                        'the material group from the WPS.'),
                style:
                    const TextStyle(fontSize: 11, color: kTextMut, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String helper,
    String? error,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: numberKeyboard(),
      inputFormatters: numberInputFormatters(),
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: kText),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'mm',
        helperText: helper,
        helperMaxLines: 3,
        errorText: error,
        errorMaxLines: 2,
      ),
    );
  }

  Widget _inputs() {
    return Column(
      children: [
        _numberField(
          key: const ValueKey('pwht-thickness'),
          controller: _t,
          label: context.tr(pl: 'Grubość kontrolna', en: 'Control thickness'),
          helper: context.tr(
              pl: 'Złącze doczołowe z pełnym przetopem: grubość grubszego '
                  'elementu w złączu (nominalna).',
              en: 'Full-penetration butt weld: nominal thickness of the '
                  'thicker part at the joint.'),
          error: _fieldError(_t),
        ),
        const SizedBox(height: 12),
        _numberField(
          key: const ValueKey('pwht-od'),
          controller: _od,
          label: context.tr(
              pl: 'Średnica zewnętrzna (opcjonalnie)',
              en: 'Outside diameter (optional)'),
          helper: context.tr(
              pl: 'Do liczby stref regulacji (AWS D10.10) i opisu planu.',
              en: 'For the number of control zones (AWS D10.10) and the '
                  'plan description.'),
          error: _odError,
        ),
        const SizedBox(height: 12),
        _numberField(
          key: const ValueKey('pwht-weld-width'),
          controller: _ww,
          label: context.tr(
              pl: 'Szerokość lica spoiny (opcjonalnie)',
              en: 'Weld cap width (optional)'),
          helper: context.tr(
              pl: 'Największa szerokość spoiny — do minimalnego pasma '
                  'wytrzymania.',
              en: 'Widest width of the weld — for the minimum soak band.'),
          error: _fieldError(_ww),
        ),
      ],
    );
  }

  List<Widget> _results(PwhtPlan plan, bool en) {
    final entry = plan.entry;
    final range = entry.holdRange;
    final rule = plan.rateRule;
    final cycle = plan.cycle;
    final holdRule = entry.holdTime;
    return [
      _VerdictBanner(plan: plan, english: en),
      if (plan.verdict == PwhtVerdict.exemptIfConditionsMet) ...[
        const SizedBox(height: 8),
        _ConditionsCard(plan: plan, english: en),
      ],
      if (plan.hasCycleData) ...[
        const SizedBox(height: 10),
        if (plan.verdict != PwhtVerdict.required)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.tr(
                  pl: 'Parametry, jeśli PWHT jest wykonywane (np. wymaga go '
                      'WPS lub specyfikacja):',
                  en: 'Parameters if PWHT is performed (e.g. the WPS or the '
                      'specification requires it):'),
              style:
                  const TextStyle(fontSize: 12, color: kTextSec, height: 1.4),
            ),
          ),
        _Section(
          title: context.tr(pl: 'Parametry z tabeli', en: 'Table values'),
          child: _ReadoutGrid(children: [
            Readout(
              key: const ValueKey('pwht-readout-temp'),
              label: context.tr(
                  pl: 'Temperatura wytrzymania', en: 'Holding temperature'),
              value: '${range!.minC}–${range.maxC}',
              unit: '°C · ${range.minF}–${range.maxF} °F',
              hot: true,
            ),
            Readout(
              key: const ValueKey('pwht-readout-hold'),
              label: context.tr(
                  pl: 'Min. czas wytrzymania', en: 'Min. holding time'),
              value: formatPwhtDuration(plan.holdMinutes! / 60.0),
              unit: en
                  ? holdRule!.segmentFor(plan.input.thicknessMm).en
                  : holdRule!.segmentFor(plan.input.thicknessMm).pl,
            ),
            if (rule != null && plan.heatingRateCPerH != null)
              Readout(
                key: const ValueKey('pwht-readout-heat'),
                label: context.tr(
                    pl: 'Maks. nagrzewanie > ${rule.controlTempC} °C',
                    en: 'Max heating > ${rule.controlTempC} °C'),
                value: plan.heatingRateCPerH!.toStringAsFixed(0),
                unit: '°C/h',
              ),
            if (rule != null && plan.coolingRateCPerH != null)
              Readout(
                key: const ValueKey('pwht-readout-cool'),
                label: context.tr(
                    pl: 'Maks. chłodzenie > ${rule.controlTempC} °C',
                    en: 'Max cooling > ${rule.controlTempC} °C'),
                value: plan.coolingRateCPerH!.toStringAsFixed(0),
                unit: '°C/h',
              ),
            if (cycle != null)
              Readout(
                key: const ValueKey('pwht-readout-cycle'),
                label: context.tr(
                    pl: 'Czas cyklu (część kontrolowana)',
                    en: 'Cycle time (controlled part)'),
                value: formatPwhtDuration(cycle.totalHours),
                unit: context.tr(
                    pl: 'przy maks. szybkościach', en: 'at the max rates'),
              ),
          ]),
        ),
        if (rule != null) ...[
          const SizedBox(height: 8),
          _Note(
            icon: Icons.speed,
            text: context.tr(
              pl: 'Szybkości: ${rule.source}. ${rule.notePl} Poniżej '
                  '${rule.controlTempC} °C: ${rule.belowControlPl}.',
              en: 'Rates: ${rule.source}. ${rule.noteEn} Below '
                  '${rule.controlTempC} °C: ${rule.belowControlEn}.',
            ),
          ),
        ],
        if (cycle != null) ...[
          const SizedBox(height: 10),
          _Section(
            title: context.tr(pl: 'Wykres cyklu', en: 'Cycle chart'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PwhtCycleChart(
                  key: const ValueKey('pwht-chart'),
                  cycle: cycle,
                  holdMinC: range.minC,
                  holdMaxC: range.maxC,
                  semanticLabel: _chartSemantics(cycle, en),
                ),
                const SizedBox(height: 8),
                _Legend(controlTempC: cycle.controlTempC),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    pl: 'Nagrzewanie ${formatPwhtDuration(cycle.rampUpHours)} '
                        '(${cycle.controlTempC}→${cycle.holdTempC} °C) · '
                        'wytrzymanie ${formatPwhtDuration(cycle.holdHours)} · '
                        'chłodzenie ${formatPwhtDuration(cycle.rampDownHours)} '
                        '(${cycle.holdTempC}→${cycle.controlTempC} °C). '
                        'Temperatura w planie = środek zakresu z tabeli. '
                        'Nagrzewanie do ${cycle.controlTempC} °C i chłodzenie '
                        'poniżej niej nie są wliczone.',
                    en: 'Heating ${formatPwhtDuration(cycle.rampUpHours)} '
                        '(${cycle.controlTempC}→${cycle.holdTempC} °C) · '
                        'hold ${formatPwhtDuration(cycle.holdHours)} · '
                        'cooling ${formatPwhtDuration(cycle.rampDownHours)} '
                        '(${cycle.holdTempC}→${cycle.controlTempC} °C). '
                        'Planned temperature = middle of the table range. '
                        'Heating up to ${cycle.controlTempC} °C and cooling '
                        'below it are not included.',
                  ),
                  style: const TextStyle(
                      fontSize: 12, color: kTextSec, height: 1.45),
                ),
              ],
            ),
          ),
        ],
        if (plan.soakBandMm != null) ...[
          const SizedBox(height: 10),
          _SoakBandCard(plan: plan, english: en),
        ],
        if (plan.controlZones != null) ...[
          const SizedBox(height: 10),
          _ZonesCard(zones: plan.controlZones!),
        ],
      ],
      if (entry.notes.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final n in entry.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _Note(icon: Icons.info_outline, text: en ? n.en : n.pl),
          ),
      ],
      const SizedBox(height: 8),
      _Note(
        icon: Icons.menu_book_outlined,
        text: context.tr(
            pl: 'Źródło: ${entry.source}', en: 'Source: ${entry.source}'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('pwht-share-text'),
              onPressed: () => _shareText(plan),
              icon: const Icon(Icons.ios_share, size: 18),
              label: Text(context.tr(pl: 'Udostępnij', en: 'Share')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('pwht-share-pdf'),
              onPressed: _busy ? null : () => _sharePdf(plan),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(context.tr(pl: 'PDF', en: 'PDF')),
            ),
          ),
        ],
      ),
    ];
  }

  String _chartSemantics(PwhtCycle c, bool en) => en
      ? 'PWHT cycle chart: heating from ${c.controlTempC} to ${c.holdTempC} °C '
          'in ${formatPwhtDuration(c.rampUpHours)}, hold '
          '${formatPwhtDuration(c.holdHours)}, cooling to ${c.controlTempC} °C '
          'in ${formatPwhtDuration(c.rampDownHours)}.'
      : 'Wykres cyklu PWHT: nagrzewanie od ${c.controlTempC} do '
          '${c.holdTempC} °C w ${formatPwhtDuration(c.rampUpHours)}, '
          'wytrzymanie ${formatPwhtDuration(c.holdHours)}, chłodzenie do '
          '${c.controlTempC} °C w ${formatPwhtDuration(c.rampDownHours)}.';
}

// ════════════════════════════════════════════════════════════════════════════
// Klocki ekranu
// ════════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kTextSec,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ReadoutGrid extends StatelessWidget {
  const _ReadoutGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final two = c.maxWidth >= 480;
      final w = two ? (c.maxWidth - 16) / 2 : c.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: w, child: child),
        ],
      );
    });
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kWarn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kWarn.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_outlined, color: kWarn, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: kText, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 13, color: kTextMut, height: 1.4)),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: kTextMut),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: kTextSec, height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.plan, required this.english});
  final PwhtPlan plan;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (plan.verdict) {
      PwhtVerdict.required => (kFail, Icons.local_fire_department_outlined),
      PwhtVerdict.exemptIfConditionsMet => (kWarn, Icons.rule),
      PwhtVerdict.exempt => (kPass, Icons.check_circle_outline),
      PwhtVerdict.notRequiredByTable => (kPass, Icons.check_circle_outline),
    };
    return Container(
      key: const ValueKey('pwht-verdict'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pwhtVerdictText(plan, english: english),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionsCard extends StatelessWidget {
  const _ConditionsCard({required this.plan, required this.english});
  final PwhtPlan plan;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final ex = plan.entry.exemption!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kWarn.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                pl: 'Zwolnienie z PWHT — wszystkie warunki muszą być spełnione:',
                en: 'PWHT exemption — every condition must be met:'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: kText),
          ),
          const SizedBox(height: 6),
          for (final c in ex.conditionsFor(plan.input.thicknessMm))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ',
                      style: TextStyle(fontSize: 13, color: kWarn)),
                  Expanded(
                    child: Text(
                      english ? c.text.en : c.text.pl,
                      style: const TextStyle(
                          fontSize: 13, color: kTextSec, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            ex.source,
            style: const TextStyle(fontSize: 11, color: kTextMut),
          ),
        ],
      ),
    );
  }
}

class _SoakBandCard extends StatelessWidget {
  const _SoakBandCard({required this.plan, required this.english});
  final PwhtPlan plan;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final rule = soakBandRuleFor(plan.input.code);
    final band = plan.soakBandMm!;
    final half = band / 2;
    final weld = plan.input.weldWidthMm;
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return _Section(
      title: context.tr(
          pl: 'Pasmo wytrzymania (grzanie miejscowe)',
          en: 'Soak band (local heating)'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Readout(
            key: const ValueKey('pwht-readout-soak'),
            label:
                context.tr(pl: 'Min. szerokość pasma', en: 'Min. band width'),
            value: fmt(band),
            unit: context.tr(
                pl: 'mm · ${fmt(half)} mm w każdą stronę od osi spoiny',
                en: 'mm · ${fmt(half)} mm each side of the weld centreline'),
          ),
          if (rule != null) ...[
            const SizedBox(height: 8),
            Text(
              '${english ? rule.formula.en : rule.formula.pl} · ${rule.source}',
              style:
                  const TextStyle(fontSize: 12, color: kTextSec, height: 1.4),
            ),
          ],
          if (weld != null && weld >= band) ...[
            const SizedBox(height: 8),
            Row(
              key: const ValueKey('pwht-soak-weld-warning'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: kWarn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(
                        pl: 'Lico spoiny (${fmt(weld)} mm) nie mieści się '
                            'w minimum normy — pasmo musi objąć całą spoinę; '
                            'przyjmij szersze pasmo wg procedury PWHT.',
                        en: 'The weld cap (${fmt(weld)} mm) does not fit in '
                            'the code minimum — the band must cover the whole '
                            'weld; use a wider band per the PWHT procedure.'),
                    style: const TextStyle(
                        fontSize: 12, color: kText, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ZonesCard extends StatelessWidget {
  const _ZonesCard({required this.zones});
  final PwhtControlZones zones;

  @override
  Widget build(BuildContext context) {
    final n = zones.zones;
    return _Section(
      title: context.tr(
          pl: 'Strefy regulacji (zalecenie)',
          en: 'Control zones (recommended)'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Readout(
            key: const ValueKey('pwht-readout-zones'),
            label: context.tr(
                pl: 'Strefy regulacji — rura pozioma',
                en: 'Control zones — horizontal pipe'),
            value: n == null ? '—' : '$n',
            unit: zones.npsRange,
          ),
          const SizedBox(height: 8),
          Text(
            n == null
                ? context.tr(
                    pl: 'Powyżej NPS 30 norma nie podaje jednej liczby — '
                        'wg rozstawu grzałek i procedury PWHT. '
                        '${zones.source}.',
                    en: 'Above NPS 30 no single number is given — per the '
                        'heater layout and the PWHT procedure. '
                        '${zones.source}.')
                : context.tr(
                    pl: 'Liczba i miejsca termopar (regulacyjnych '
                        'i kontrolnych) — wg rysunku normy; rura pionowa — '
                        'wg procedury. ${zones.source}.',
                    en: 'Number and locations of thermocouples (control and '
                        'monitoring) — per the figure; vertical pipe — per '
                        'the procedure. ${zones.source}.'),
            style: const TextStyle(fontSize: 12, color: kTextSec, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.controlTempC});
  final int controlTempC;

  @override
  Widget build(BuildContext context) {
    Widget item(Widget swatch, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  style: const TextStyle(fontSize: 11, color: kTextSec)),
            ),
          ],
        );
    Widget bar(Color c, {double h = 4}) =>
        Container(width: 18, height: h, color: c);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(bar(kArc.withValues(alpha: 0.35), h: 10),
            context.tr(pl: 'Zakres z tabeli', en: 'Table range')),
        item(bar(kArc), context.tr(pl: 'Wytrzymanie', en: 'Hold')),
        item(bar(kText, h: 2.5),
            context.tr(pl: 'Rampa kontrolowana', en: 'Controlled ramp')),
        item(
            bar(kTextMut, h: 1.5),
            context.tr(
                pl: 'Poniżej $controlTempC °C — poza skalą czasu',
                en: 'Below $controlTempC °C — not to time scale')),
      ],
    );
  }
}
