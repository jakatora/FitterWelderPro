// Twardość: przelicznik HV ↔ HB ↔ HRC ↔ HRB (i Rm orientacyjnie) wg
// ISO 18265 tab. A.1 oraz ocena serii pomiarów (lico, grań, SWC, materiał
// rodzimy) względem limitu z presetu (NACE MR0175/ISO 15156-2, EN ISO
// 15614-1, ASME B31.3) albo własnego. Udostępnianie: tekst i PDF.
//
// Logika, tablica i źródła: lib/domain/welding/hardness.dart. Historii brak —
// seria żyje w pamięci ekranu; zapamiętywany jest tylko ostatni limit.

import 'dart:async';
import '../../assistant/core/tool_bridge.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/welding/hardness.dart';
import '../../i18n/app_language.dart';
import '../../services/hardness_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';

/// Zapamiętany limit: wybrany preset i — NIEZALEŻNIE od niego — ostatni
/// prawidłowy własny limit (wybór presetu go nie kasuje).
class HardnessSavedLimit {
  /// Id presetu albo [kHardnessCustomLimitId]; `null` — nic nie zapisano.
  final String? presetId;
  final HardnessScale? customScale;
  final String? customValue;

  const HardnessSavedLimit({this.presetId, this.customScale, this.customValue});
}

/// Ostatni limit w SharedPreferences. Nigdy nie rzuca — przy błędzie ekran
/// startuje z domyślnym limitem.
class HardnessLimitStore {
  static const String presetKey = 'hardness_limit_preset_v1';
  static const String customKey = 'hardness_limit_custom_v1';

  /// Zapis pierwszej wersji modułu („id|skala|wartość”, jeden klucz) —
  /// tylko do odczytu, gdy nowych kluczy jeszcze nie ma.
  static const String legacyKey = 'hardness_limit_v1';

  const HardnessLimitStore();

  static HardnessScale? _scale(String name) =>
      HardnessScale.values.where((s) => s.name == name).firstOrNull;

  /// Własny limit „skala|wartość” — tylko prawidłowy (inaczej `null`).
  static (HardnessScale, String)? _custom(String scaleName, String value) {
    final scale = _scale(scaleName);
    final v = parseDecimal(value);
    if (scale == null || v == null || !HardnessLimit(scale, v).isValid) {
      return null;
    }
    return (scale, value.trim());
  }

  Future<HardnessSavedLimit?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      var presetId = prefs.getString(presetKey);
      (HardnessScale, String)? custom;
      final rawCustom = prefs.getString(customKey);
      if (rawCustom != null) {
        final parts = rawCustom.split('|');
        if (parts.length == 2) custom = _custom(parts[0], parts[1]);
      }
      final legacy = prefs.getString(legacyKey);
      if (presetId == null && rawCustom == null && legacy != null) {
        final parts = legacy.split('|');
        if (parts.length == 3) {
          presetId = parts[0];
          custom = _custom(parts[1], parts[2]);
        }
      }
      if (presetId == null && custom == null) return null;
      return HardnessSavedLimit(
          presetId: presetId, customScale: custom?.$1, customValue: custom?.$2);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePreset(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(presetKey, id);
    } catch (_) {
      // Wybór działa w tej sesji.
    }
  }

  /// Zapisuje własny limit TYLKO, gdy jest prawidłowy — pusty albo błędny
  /// tekst w trakcie pisania nie nadpisuje ostatniego dobrego limitu.
  Future<void> saveCustom(HardnessScale scale, String value) async {
    final c = _custom(scale.name, value.replaceAll('|', ''));
    if (c == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(customKey, '${c.$1.name}|${c.$2}');
    } catch (_) {
      // Wybór działa w tej sesji.
    }
  }
}

class HardnessPage extends StatefulWidget {
  /// Udostępnianie oceny — test podmienia, żeby nie wołać platformy.
  final HardnessShareFn share;
  final HardnessLimitStore store;

  const HardnessPage({
    super.key,
    this.share = shareHardness,
    this.store = const HardnessLimitStore(),
  });

  @override
  State<HardnessPage> createState() => _HardnessPageState();
}

/// Wiersz serii pomiarów (stałe [id] — klucze widżetów przeżywają usuwanie).
class _Row {
  final int id;
  final TextEditingController location;
  final TextEditingController value = TextEditingController();
  HardnessScale scale;

  _Row(this.id, String loc, this.scale)
      : location = TextEditingController(text: loc);

  void dispose() {
    location.dispose();
    value.dispose();
  }
}

/// Szybkie dodawanie pomiaru z nazwą miejsca.
enum _Spot { cap, root, hazA, hazB, base, other }

class _HardnessPageState extends State<HardnessPage>
    with ToolHandleHost<HardnessPage> {
  @override
  String get toolId => 'hardness';
  @override
  Set<String> get supportedFields => const {'value', 'scale', 'material'};
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted ||
        fields.length != 3 ||
        !supportedFields.containsAll(fields.keys)) {
      return fields.keys.toSet();
    }
    final value = fields['value'];
    final scale = HardnessScale.values
        .where((s) => s.name == fields['scale'])
        .firstOrNull;
    final material = HardnessMaterial.values
        .where((s) => s.name == fields['material'])
        .firstOrNull;
    if (value is! num ||
        !value.toDouble().isFinite ||
        scale == null ||
        material == null ||
        value <= 0 ||
        value > scale.maxPlausible) {
      return fields.keys.toSet();
    }
    if (material != _material &&
        _rows.any((r) => r.value.text.trim().isNotEmpty)) {
      return fields.keys.toSet();
    }
    setState(() {
      _convValue.text = value.toString();
      _convScale = scale;
      _material = material;
    });
    return {};
  }

  static const String _defaultPresetId = 'iso15156_weld';

  HardnessMaterial _material = HardnessMaterial.carbonLowAlloy;

  final _convValue = TextEditingController(text: '250');
  HardnessScale _convScale = HardnessScale.hv;

  String _presetId = _defaultPresetId;
  final _customValue = TextEditingController();
  HardnessScale _customScale = HardnessScale.hv;

  /// Monter już zmienił preset / własny limit — zapis odczytany później go
  /// nie nadpisze.
  bool _presetTouched = false;
  bool _customTouched = false;

  final List<_Row> _rows = [];
  int _seq = 0;
  bool _sharing = false;

  bool get _en => context.language == AppLanguage.en;

  @override
  void initState() {
    super.initState();
    // Kontekstu jeszcze nie ma — język z kontrolera (ustawiany przed runApp).
    _rows.add(_Row(_seq++, AppLanguageController.isEnglish ? 'Cap' : 'Lico',
        HardnessScale.hv));
    markReady();
    unawaited(_restoreLimit());
  }

  /// Własny limit odtwarzany ZAWSZE (także gdy wybrany jest preset), preset
  /// osobno — przełączenie na preset i restart nie gubią własnego limitu.
  Future<void> _restoreLimit() async {
    final saved = await widget.store.load();
    if (!mounted || saved == null) return;
    setState(() {
      final scale = saved.customScale;
      final value = saved.customValue;
      if (!_customTouched && scale != null && value != null) {
        _customScale = scale;
        _customValue.text = value;
      }
      final id = saved.presetId;
      if (!_presetTouched &&
          id != null &&
          (id == kHardnessCustomLimitId || hardnessPresetById(id) != null)) {
        _presetId = id;
      }
    });
  }

  void _savePreset() {
    _presetTouched = true;
    unawaited(widget.store.savePreset(_presetId));
  }

  void _saveCustom() {
    _customTouched = true;
    unawaited(widget.store.saveCustom(_customScale, _customValue.text));
  }

  @override
  void dispose() {
    _convValue.dispose();
    _customValue.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // ── Model ─────────────────────────────────────────────────────────────────

  HardnessLimitPreset? get _preset => hardnessPresetById(_presetId);

  HardnessLimit get _limit {
    final p = _preset;
    if (p != null) return p.limit;
    final t = _customValue.text.trim();
    // Puste albo nieczytelne → NaN → limit nieprawidłowy (nigdy fałszywe OK).
    final v = t.isEmpty ? double.nan : (parseDecimal(t) ?? double.nan);
    return HardnessLimit(_customScale, v);
  }

  HardnessReading _reading(_Row r) {
    final t = r.value.text.trim();
    return HardnessReading(
      location: r.location.text,
      value: t.isEmpty ? null : parseDecimal(t),
      scale: r.scale,
      blank: t.isEmpty,
    );
  }

  HardnessReport get _report => HardnessReport(
        material: _material,
        preset: _preset,
        limit: _limit,
        readings: [for (final r in _rows) _reading(r)],
      );

  String _n(double v, [int decimals = 1]) =>
      formatHardnessNumber(v, decimals: decimals, en: _en);

  String _spotLabel(_Spot s) => switch (s) {
        _Spot.cap => context.tr(pl: 'Lico', en: 'Cap'),
        _Spot.root => context.tr(pl: 'Grań', en: 'Root'),
        _Spot.hazA => context.tr(pl: 'SWC strona A', en: 'HAZ side A'),
        _Spot.hazB => context.tr(pl: 'SWC strona B', en: 'HAZ side B'),
        _Spot.base => context.tr(pl: 'Materiał rodzimy', en: 'Base metal'),
        _Spot.other => context.tr(pl: 'Inny punkt', en: 'Other point'),
      };

  void _addRow(_Spot s) {
    setState(() {
      final scale = _rows.isEmpty ? HardnessScale.hv : _rows.last.scale;
      _rows.add(_Row(_seq++, s == _Spot.other ? '' : _spotLabel(s), scale));
    });
  }

  void _removeRow(_Row r) {
    setState(() {
      _rows.remove(r);
      r.dispose();
    });
  }

  // ── Widżety pomocnicze ───────────────────────────────────────────────────

  Widget _caption(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _kv(String k, String v, {Key? key}) => CopyOnLongPress(
        key: key,
        value: v,
        label: k,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(k,
                      style: const TextStyle(fontSize: 13.5, color: kTextSec))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kText,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );

  Widget _scaleChips(
    HardnessScale selected,
    ValueChanged<HardnessScale> onSelected, {
    required String keyPrefix,
  }) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in HardnessScale.values)
            ChoiceChip(
              key: ValueKey('$keyPrefix-${s.name}'),
              label: Text(s.label),
              // Bez znacznika — cztery skale mieszczą się w jednym wierszu
              // na wąskim telefonie; zaznaczenie widać po kolorze.
              showCheckmark: false,
              selected: selected == s,
              onSelected: (_) => onSelected(s),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final result = report.result;
    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Twardość: przelicznik i limity',
              en: 'Hardness: converter and limits'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _materialSection(),
          _converterSection(),
          _limitSection(),
          _readingsSection(result),
          _resultSection(report, result),
          _disclaimer(),
        ],
      ),
    );
  }

  // ── Materiał ─────────────────────────────────────────────────────────────

  Widget _materialSection() {
    return QuoteSection(
      title: context.tr(pl: 'Materiał', en: 'Material'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in HardnessMaterial.values)
              ChoiceChip(
                key: ValueKey('hard-mat-${m.name}'),
                label: Text(hardnessMaterialLabel(m, en: _en)),
                selected: _material == m,
                onSelected: (_) => setState(() => _material = m),
              ),
          ],
        ),
        if (_material == HardnessMaterial.stainless) ...[
          const SizedBox(height: 10),
          QuoteNotice(
            key: const ValueKey('hard-stainless-notice'),
            icon: Icons.block,
            text: context.tr(
                pl: 'Dla stali nierdzewnych i austenitycznych tablica '
                    'ISO 18265 A.1 nie obowiązuje — nie przeliczaj skal. Mierz '
                    'w skali, którą podaje specyfikacja; pomiar w innej skali '
                    'niż limit nie zostanie oceniony.',
                en: 'ISO 18265 Table A.1 does not apply to stainless and '
                    'austenitic steels — do not convert scales. Measure in the '
                    'scale given by the specification; a reading in another '
                    'scale than the limit will not be rated.'),
          ),
        ],
      ],
    );
  }

  // ── Przelicznik ──────────────────────────────────────────────────────────

  String _rangeText(HardnessScale s) {
    final r = hardnessTableRange(s);
    final d = s == HardnessScale.hv || s == HardnessScale.hb ? 0 : 1;
    return '${s.label} ${_n(r.min, d)}–${_n(r.max, d)}';
  }

  Widget _converterSection() {
    final t = _convValue.text.trim();
    final v = t.isEmpty ? null : parseDecimal(t);
    final stainless = _material == HardnessMaterial.stainless;
    final outOfOwnRange =
        v != null && v > 0 && !isInHardnessTable(v, _convScale);

    String out(HardnessScale to) {
      if (v == null || v <= 0) return '—';
      final x = convertHardness(v, from: _convScale, to: to);
      if (x == null) {
        return context.tr(pl: 'poza zakresem tablicy', en: 'outside the table');
      }
      return '≈ ${_n(x)} ${to.label}';
    }

    final rm =
        v == null || v <= 0 ? null : estimateTensileStrengthMpa(v, _convScale);

    return QuoteSection(
      title: context.tr(pl: 'Przelicznik', en: 'Converter'),
      subtitle: context.tr(
          pl: 'ISO 18265:2013 tab. A.1 — stale niestopowe i niskostopowe. '
              'Interpolacja liniowa, bez ekstrapolacji. Wynik przybliżony.',
          en: 'ISO 18265:2013 Table A.1 — unalloyed and low-alloy steels. '
              'Linear interpolation, no extrapolation. Approximate result.'),
      children: [
        TextField(
          key: const ValueKey('hard-conv-value'),
          controller: _convValue,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: context.tr(pl: 'Twardość', en: 'Hardness'),
            suffixText: _convScale.label,
            errorText: t.isNotEmpty && (v == null || v <= 0)
                ? context.tr(pl: 'Wpisz liczbę > 0', en: 'Enter a number > 0')
                : null,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        _scaleChips(_convScale, (s) => setState(() => _convScale = s),
            keyPrefix: 'hard-conv-scale'),
        const SizedBox(height: 8),
        if (stainless)
          QuoteNotice(
            color: kTextSec,
            icon: Icons.block,
            text: context.tr(
                pl: 'Stal nierdzewna / austenityczna — przeliczeń nie '
                    'pokazujemy (tablica ich nie obejmuje).',
                en: 'Stainless / austenitic steel — no conversions shown (the '
                    'table does not cover it).'),
          )
        else ...[
          for (final s in HardnessScale.values)
            if (s != _convScale)
              _kv(s.label, out(s), key: ValueKey('hard-conv-out-${s.name}')),
          _kv(
            context.tr(pl: 'Rm (orientacyjnie)', en: 'Rm (indicative)'),
            rm == null
                ? (v == null || v <= 0
                    ? '—'
                    : context.tr(
                        pl: 'poza zakresem tablicy', en: 'outside the table'))
                : '≈ ${_n(rm, 0)} MPa',
            key: const ValueKey('hard-conv-out-rm'),
          ),
          if (outOfOwnRange)
            _caption(context.tr(
                pl: 'Wartość poza zakresem tablicy dla ${_convScale.label} — '
                    'nie ekstrapolujemy.',
                en: 'Value outside the table range for ${_convScale.label} — '
                    'no extrapolation.')),
          _caption(context.tr(
              pl: 'Zakres tablicy: ${HardnessScale.values.map(_rangeText).join(' · ')}. '
                  'HRB i HRC mają wartości tylko w części zakresu HV.',
              en: 'Table range: ${HardnessScale.values.map(_rangeText).join(' · ')}. '
                  'HRB and HRC cover only part of the HV range.')),
        ],
        _caption(context.tr(
            pl: 'Twardościomierz przenośny (Leeb HL, UCI) sam przelicza na '
                'HV/HB/HRC wg własnych krzywych — wpisz wartość i skalę '
                'z wyświetlacza; to przeliczenie też jest przybliżone.',
            en: 'A portable tester (Leeb HL, UCI) converts to HV/HB/HRC with '
                'its own curves — enter the value and scale it displays; that '
                'conversion is approximate too.')),
      ],
    );
  }

  // ── Limit ────────────────────────────────────────────────────────────────

  String _standardTitle(HardnessStandard s) => switch (s) {
        HardnessStandard.iso15156 => context.tr(
            pl: 'NACE MR0175 / ISO 15156-2 — środowisko H2S',
            en: 'NACE MR0175 / ISO 15156-2 — sour service'),
        HardnessStandard.iso15614 => context.tr(
            pl: 'EN ISO 15614-1 — kwalifikacja technologii (WPQR)',
            en: 'EN ISO 15614-1 — procedure qualification (WPQR)'),
        HardnessStandard.asmeB313 =>
          context.tr(pl: 'ASME B31.3 — po PWHT', en: 'ASME B31.3 — after PWHT'),
      };

  Future<void> _pickLimit() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        Widget tile(String id, String title, String subtitle) => ListTile(
              key: ValueKey('hard-preset-$id'),
              selected: id == _presetId,
              selectedColor: kArc,
              minVerticalPadding: 10,
              title: Text(title),
              subtitle: Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: kTextMut)),
              onTap: () => Navigator.of(ctx).pop(id),
            );
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                      context.tr(
                          pl: 'Wybierz limit (max)', en: 'Pick a limit (max)'),
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
                for (final std in HardnessStandard.values) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                    child: Text(_standardTitle(std).toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: kTextSec)),
                  ),
                  for (final p in kHardnessLimitPresets)
                    if (p.standard == std)
                      tile(
                        p.id,
                        '${hardnessLimitText(p.limit, en: _en)} — '
                        '${_en ? p.titleEn : p.titlePl}',
                        _en ? p.sourceEn : p.sourcePl,
                      ),
                ],
                const Divider(height: 24),
                tile(
                  kHardnessCustomLimitId,
                  context.tr(pl: 'Własny limit', en: 'Custom limit'),
                  context.tr(
                      pl: 'Wartość i skala ze specyfikacji projektu / WPS',
                      en: 'Value and scale from the project spec / WPS'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _presetId = picked);
    _savePreset();
  }

  Widget _limitSection() {
    final p = _preset;
    final limit = _limit;
    final customText = _customValue.text.trim();
    final customError = p == null && !limit.isValid
        ? (customText.isEmpty
            ? context.tr(pl: 'Wpisz limit', en: 'Enter the limit')
            : context.tr(
                pl: 'Liczba > 0, najwyżej ${formatHardnessExact(_customScale.maxPlausible, en: _en)} ${_customScale.label}',
                en: 'A number > 0, at most ${formatHardnessExact(_customScale.maxPlausible, en: true)} ${_customScale.label}'))
        : null;
    final note = p == null ? '' : (_en ? p.noteEn : p.notePl);
    final mismatch = hardnessPresetMismatchReason(p, _material, en: _en);

    return QuoteSection(
      title:
          context.tr(pl: 'Limit (wartość maksymalna)', en: 'Limit (maximum)'),
      children: [
        Material(
          color: kBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: kBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('hard-limit-picker'),
            onTap: _pickLimit,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p == null
                                ? context.tr(
                                    pl: 'Własny limit', en: 'Custom limit')
                                : (_en ? p.titleEn : p.titlePl),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: kText),
                          ),
                          if (limit.isValid)
                            Text(hardnessLimitText(limit, en: _en),
                                key: const ValueKey('hard-limit-value-text'),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: kArc)),
                          if (p != null)
                            Text(_en ? p.sourceEn : p.sourcePl,
                                style: const TextStyle(
                                    fontSize: 12, color: kTextMut)),
                        ],
                      ),
                    ),
                    const Icon(Icons.expand_more, color: kTextSec),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (note.isNotEmpty) _caption(note),
        if (p == null) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('hard-limit-value'),
            controller: _customValue,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
            onChanged: (_) {
              setState(() {});
              _saveCustom();
            },
            decoration: InputDecoration(
              labelText: context.tr(pl: 'Limit max', en: 'Limit max'),
              suffixText: _customScale.label,
              errorText: customError,
              errorMaxLines: 2,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          _scaleChips(_customScale, (s) {
            setState(() => _customScale = s);
            _saveCustom();
          }, keyPrefix: 'hard-limit-scale'),
        ],
        if (mismatch != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: QuoteNotice(
              key: const ValueKey('hard-limit-material-mismatch'),
              color: kWarn,
              icon: Icons.warning_amber_outlined,
              text: mismatch,
            ),
          ),
      ],
    );
  }

  // ── Pomiary ──────────────────────────────────────────────────────────────

  (Color, IconData) _statusLook(ReadingStatus s) => switch (s) {
        ReadingStatus.ok => (kPass, Icons.check_circle_outline),
        ReadingStatus.exceeded => (kFail, Icons.cancel_outlined),
        ReadingStatus.noLimit => (kTextSec, Icons.info_outline),
        _ => (kWarn, Icons.help_outline),
      };

  Widget _rowCard(_Row row, ReadingCheck check, HardnessLimit limit) {
    final (color, icon) = _statusLook(check.status);
    final t = row.value.text.trim();
    final unreadable = t.isNotEmpty && parseDecimal(t) == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('hard-row-${row.id}-loc'),
                      controller: row.location,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText:
                            context.tr(pl: 'Miejsce pomiaru', en: 'Location'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('hard-row-${row.id}-del'),
                    tooltip:
                        context.tr(pl: 'Usuń pomiar', en: 'Remove reading'),
                    icon: const Icon(Icons.delete_outline),
                    color: kTextSec,
                    onPressed: () => _removeRow(row),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextField(
                  key: ValueKey('hard-row-${row.id}-value'),
                  controller: row.value,
                  keyboardType: numberKeyboard(),
                  inputFormatters: numberInputFormatters(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr(pl: 'Twardość', en: 'Hardness'),
                    suffixText: row.scale.label,
                    errorText: unreadable
                        ? context.tr(
                            pl: 'Nieczytelna liczba', en: 'Unreadable number')
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _scaleChips(row.scale, (s) => setState(() => row.scale = s),
                  keyPrefix: 'hard-row-${row.id}-scale'),
              const SizedBox(height: 8),
              KeyedSubtree(
                key: ValueKey('hard-row-${row.id}-status-${check.status.name}'),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: color, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text:
                                    hardnessStatusLabel(check.status, en: _en),
                                style: TextStyle(
                                    color: color, fontWeight: FontWeight.w800)),
                            TextSpan(
                                text:
                                    ' · ${hardnessCheckDetail(check, limit, en: _en)}'),
                          ]),
                          key: ValueKey('hard-row-${row.id}-detail'),
                          style: const TextStyle(
                              fontSize: 13, color: kText, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readingsSection(HardnessSeriesResult result) {
    return QuoteSection(
      title: context.tr(pl: 'Pomiary', en: 'Readings'),
      subtitle: context.tr(
          pl: 'Każdy pomiar w swojej skali — przeliczenie do skali limitu '
              'i ocena osobno.',
          en: 'Each reading in its own scale — converted to the limit scale '
              'and judged on its own.'),
      children: [
        for (final (i, row) in _rows.indexed)
          _rowCard(row, result.checks[i], result.limit),
        if (_rows.isEmpty)
          _caption(context.tr(
              pl: 'Brak pomiarów — dodaj poniżej.',
              en: 'No readings — add one below.')),
        const SizedBox(height: 4),
        Text(context.tr(pl: 'Dodaj pomiar', en: 'Add reading'),
            style: const TextStyle(color: kTextSec, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in _Spot.values)
              ActionChip(
                key: ValueKey('hard-add-${s.name}'),
                avatar: const Icon(Icons.add, size: 18),
                label: Text(_spotLabel(s)),
                onPressed: () => _addRow(s),
              ),
          ],
        ),
      ],
    );
  }

  // ── Wynik ────────────────────────────────────────────────────────────────

  Widget _resultSection(HardnessReport report, HardnessSeriesResult r) {
    final total = r.checks.length;
    final limitText = hardnessLimitText(r.limit, en: _en);
    final (Color color, IconData icon, String detail) = switch (r.verdict) {
      SeriesVerdict.pass => (
          kPass,
          Icons.check_circle_outline,
          context.tr(
              pl: 'Wszystkie pomiary ($total) ≤ $limitText.'
                  '${r.convertedCount > 0 ? ' Przeliczono skalę: ${r.convertedCount} — wynik przybliżony; przy granicy zmierz w skali limitu.' : ''}',
              en: 'All readings ($total) ≤ $limitText.'
                  '${r.convertedCount > 0 ? ' Scale converted: ${r.convertedCount} — approximate; near the limit measure in the limit scale.' : ''}'),
        ),
      SeriesVerdict.fail => (
          kFail,
          Icons.error_outline,
          context.tr(
              pl: 'Przekroczenia: ${r.exceededCount} z $total ($limitText).',
              en: 'Exceeded: ${r.exceededCount} of $total ($limitText).'),
        ),
      SeriesVerdict.incomplete => (
          kWarn,
          Icons.warning_amber_outlined,
          r.limitNotForMaterial
              ? '${context.tr(pl: 'Powód', en: 'Reason')}: '
                  '${hardnessPresetMismatchReason(report.preset, report.material, en: _en)}'
              : context.tr(
                  pl: 'Bez oceny: ${r.unratedCount} z $total (puste, błędne, '
                      'poza tablicą albo bez przeliczenia). Zielony werdykt '
                      'tylko, gdy każdy pomiar jest oceniony.',
                  en: 'Not rated: ${r.unratedCount} of $total (empty, '
                      'invalid, outside the table or not convertible). Green '
                      'only when every reading is rated.'),
        ),
      SeriesVerdict.empty => (
          kTextSec,
          Icons.info_outline,
          context.tr(
              pl: 'Wpisz co najmniej jeden pomiar.',
              en: 'Enter at least one reading.'),
        ),
      SeriesVerdict.invalidLimit => (
          kFail,
          Icons.error_outline,
          context.tr(
              pl: 'Wpisz limit: liczba > 0 w zakresie skali.',
              en: 'Enter the limit: a number > 0 within the scale.'),
        ),
    };
    final max = hardnessMaxText(r, en: _en);
    final mean = hardnessMeanText(r, en: _en);
    final canShare = r.verdict != SeriesVerdict.empty &&
        r.verdict != SeriesVerdict.invalidLimit &&
        !_sharing;

    return QuoteSection(
      title: context.tr(pl: 'Wynik', en: 'Result'),
      children: [
        KeyedSubtree(
          key: ValueKey('hard-verdict-${r.verdict.name}'),
          child: QuoteNotice(
            color: color,
            icon: icon,
            text: '${hardnessVerdictTitle(r.verdict, en: _en)}\n$detail',
          ),
        ),
        if (max != null) ...[
          Readout(
            key: const ValueKey('hard-max'),
            label: context.tr(
                pl: 'Max w skali limitu', en: 'Max in the limit scale'),
            value: max,
            unit: context.tr(pl: 'limit: $limitText', en: 'limit: $limitText'),
            hot: true,
          ),
          const SizedBox(height: 8),
          if (mean != null)
            _kv(context.tr(pl: 'Średnia', en: 'Mean'), mean,
                key: const ValueKey('hard-mean')),
          _caption(context.tr(
              pl: 'Max i średnia z ${r.statsCount} z $total pomiarów '
                  'wyrażonych w skali limitu; liczby zaokrąglone w stronę '
                  'werdyktu.',
              en: 'Max and mean from ${r.statsCount} of $total readings '
                  'expressed in the limit scale; rounded towards the '
                  'verdict.')),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('hard-share-text'),
              onPressed: canShare
                  ? () => _share(report, HardnessShareFormat.text)
                  : null,
              icon: const Icon(Icons.share_outlined),
              label: Text(context.tr(pl: 'Udostępnij tekst', en: 'Share text')),
            ),
            OutlinedButton.icon(
              key: const ValueKey('hard-share-pdf'),
              onPressed: canShare
                  ? () => _share(report, HardnessShareFormat.pdf)
                  : null,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(context.tr(pl: 'PDF', en: 'PDF')),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _share(HardnessReport report, HardnessShareFormat f) async {
    final en = _en;
    setState(() => _sharing = true);
    try {
      await widget.share(report, f, en);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.tr(
                pl: 'Nie udało się udostępnić: $e',
                en: 'Sharing failed: $e'))));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Zastrzeżenie ─────────────────────────────────────────────────────────

  Widget _disclaimer() {
    return QuoteNotice(
      key: const ValueKey('hard-disclaimer'),
      text: context.tr(
          pl: 'Przeliczenia twardości są PRZYBLIŻONE (ISO 18265 tab. A.1 — '
              'stale niestopowe i niskostopowe, staliwo) i NIE obowiązują dla '
              'stali nierdzewnych i austenitycznych. Wiąże pomiar w skali '
              'wymaganej przez specyfikację / WPS i wydanie normy przywołane '
              'w projekcie. ASTM E140 daje nieco inne liczby (np. 22 HRC ≈ '
              '248 HV wg E140, ≈ 248,9 HV wg ISO 18265).',
          en: 'Hardness conversions are APPROXIMATE (ISO 18265 Table A.1 — '
              'unalloyed and low-alloy steels, cast steel) and do NOT apply to '
              'stainless and austenitic steels. The reading in the scale '
              'required by the specification / WPS and the code edition '
              'invoked by the project governs. ASTM E140 gives slightly '
              'different numbers (e.g. 22 HRC ≈ 248 HV per E140, ≈ 248.9 HV '
              'per ISO 18265).'),
    );
  }
}
