import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tungsten.dart';
import '../i18n/app_language.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kGreen  = Color(0xFF2ECC71);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

// SharedPreferences keys (P2-14 persistence)
const _kPrefOverrides = 'prefs_tungsten_overrides';
const _kPrefInStock   = 'prefs_tungsten_in_stock';

// ── P2-14: per-diameter cup / argon flow / tip-angle reference ──────────────
// Local catalogue (not in lib/data/tungsten.dart per single-file edit scope).
// Cup numbers are #-sizing (each # = 1/16" ID); argon flow in l/min for DC-
// stainless TIG; tip-angle ranges in degrees (sharp → blunt) per diameter.
class _TungstenExtras {
  final String cup;          // e.g. '#5 (8 mm)'
  final String argonFlow;    // e.g. '8–10 l/min'
  final String tipAngle;     // e.g. '20–30°'
  const _TungstenExtras({
    required this.cup,
    required this.argonFlow,
    required this.tipAngle,
  });
}

// Dart `const Map<double, _>` is illegal because `double` does not have
// primitive equality. Key by the diameter's printed mm representation
// instead and look up via `_extrasFor(diaMm)` so callers stay readable.
const Map<String, _TungstenExtras> _kExtrasByDia = {
  '1.0': _TungstenExtras(cup: '#4–#5 (6–8 mm)',  argonFlow: '6–8 l/min',   tipAngle: '15–25°'),
  '1.6': _TungstenExtras(cup: '#5–#6 (8–10 mm)', argonFlow: '8–10 l/min',  tipAngle: '20–30°'),
  '2.4': _TungstenExtras(cup: '#6–#7 (10–11 mm)', argonFlow: '10–12 l/min', tipAngle: '30–45°'),
  '3.2': _TungstenExtras(cup: '#7–#8 (11–13 mm)', argonFlow: '12–15 l/min', tipAngle: '45–60°'),
};

_TungstenExtras? _extrasFor(double diaMm) {
  return _kExtrasByDia[diaMm.toStringAsFixed(1)];
}

/// In-memory override record for a single user pick decision.
/// Persisted as JSON in `prefs_tungsten_overrides` (capped list, newest first).
class TungstenOverride {
  final double suggestedDiaMm;   // what sizeForCurrent() proposed
  final double usedDiaMm;        // what the welder actually picked
  final String reason;           // free-text (length-capped)
  final int amps;                // current at decision time
  final int ts;                  // ms since epoch

  const TungstenOverride({
    required this.suggestedDiaMm,
    required this.usedDiaMm,
    required this.reason,
    required this.amps,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'suggested': suggestedDiaMm,
        'used': usedDiaMm,
        'reason': reason,
        'amps': amps,
        'ts': ts,
      };

  static TungstenOverride? fromJson(Map<String, dynamic> j) {
    final s = (j['suggested'] as num?)?.toDouble();
    final u = (j['used'] as num?)?.toDouble();
    final r = j['reason'] as String?;
    final a = (j['amps'] as num?)?.toInt();
    final t = (j['ts'] as num?)?.toInt();
    if (s == null || u == null || r == null || a == null || t == null) {
      return null;
    }
    return TungstenOverride(
        suggestedDiaMm: s, usedDiaMm: u, reason: r, amps: a, ts: t);
  }
}

// Local help content — global kHelp* lives in lib/data/help_entries.dart;
// added inline because tungsten was not in the original catalog.
final _kHelpTungsten = ScreenHelp(
  titlePl: 'Elektroda wolframowa (DC-)',
  titleEn: 'Tungsten electrode (DC-)',
  bodyPl:
      'Wpisz prąd spawania, aby dobrać średnicę elektrody wolframowej dla DC- TIG '
      'stali nierdzewnej. Tabela podświetla zalecaną średnicę; pomarańczowa karta '
      '"POZA ZAKRESEM" oznacza wartość spoza tabeli (sprawdź ustawienia).',
  bodyEn:
      'Enter the welding current to pick the tungsten electrode diameter for DC- TIG '
      'on stainless steel. The table highlights the recommended diameter; the orange '
      '"OUT OF RANGE" tile means the value sits outside the table (re-check settings).',
  stepsPl: [
    HelpStep('🔢', 'Wpisz prąd spawania (A) dla DC-.'),
    HelpStep('🟠', 'Tabela podświetli zalecaną średnicę.'),
    HelpStep('👆', 'Dotknij wiersza aby nadpisać wybór i podać powód.'),
    HelpStep('📦', 'Przytrzymaj wiersz aby oznaczyć "W magazynie".'),
    HelpStep('🪪', 'Opcjonalnie wpisz nr złącza i stempel spawacza (do notatek).'),
  ],
  stepsEn: [
    HelpStep('🔢', 'Enter the welding current (A) for DC-.'),
    HelpStep('🟠', 'The table highlights the recommended diameter.'),
    HelpStep('👆', 'Tap a row to override the pick and add a reason.'),
    HelpStep('📦', 'Long-press a row to flag it "In stock".'),
    HelpStep('🪪', 'Optionally enter joint ID and welder stamp (for notes).'),
  ],
);

/// Tungsten electrode picker — enter the welding current, get the electrode
/// diameter, plus a reference of electrode types for stainless DC TIG.
class TungstenScreen extends StatefulWidget {
  const TungstenScreen({super.key});

  @override
  State<TungstenScreen> createState() => _TungstenScreenState();
}

class _TungstenScreenState extends State<TungstenScreen> {
  final _amps = TextEditingController();
  final _jointId = TextEditingController();
  final _jointStamp = TextEditingController();

  /// Diameter (mm) of electrodes flagged "in stock / preferred" by this user.
  /// Hydrated from `prefs_tungsten_in_stock` on initState.
  final Set<double> _inStock = <double>{};

  /// Newest-first override history (cap 20). Surfaces last reason inline on
  /// the matching row so the welder sees recent context next session.
  final List<TungstenOverride> _overrides = <TungstenOverride>[];

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _amps.dispose();
    _jointId.dispose();
    _jointStamp.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final stockRaw = prefs.getStringList(_kPrefInStock) ?? const <String>[];
      final overridesRaw = prefs.getString(_kPrefOverrides);
      final loadedStock = <double>{};
      for (final s in stockRaw) {
        final v = double.tryParse(s);
        if (v != null) loadedStock.add(v);
      }
      final loadedOverrides = <TungstenOverride>[];
      if (overridesRaw != null && overridesRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(overridesRaw);
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) {
                final ov =
                    TungstenOverride.fromJson(e.cast<String, dynamic>());
                if (ov != null) loadedOverrides.add(ov);
              }
            }
          }
        } catch (e) {
          debugPrint('tungsten: overrides decode failed: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _inStock
          ..clear()
          ..addAll(loadedStock);
        _overrides
          ..clear()
          ..addAll(loadedOverrides);
      });
    } catch (e) {
      debugPrint('tungsten: prefs hydrate failed: $e');
    }
  }

  Future<void> _persistInStock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kPrefInStock,
        _inStock.map((d) => d.toString()).toList(growable: false),
      );
    } catch (e) {
      debugPrint('tungsten: inStock persist failed: $e');
    }
  }

  Future<void> _persistOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cap to 20 newest entries before serialising.
      final capped = _overrides.take(20).toList(growable: false);
      await prefs.setString(
        _kPrefOverrides,
        jsonEncode(capped.map((o) => o.toJson()).toList(growable: false)),
      );
    } catch (e) {
      debugPrint('tungsten: overrides persist failed: $e');
    }
  }

  void _clearAll() {
    setState(() {
      _amps.clear();
      _jointId.clear();
      _jointStamp.clear();
    });
  }

  Future<void> _copyRow(TungstenSize s) async {
    final extras = _extrasFor(s.diaMm);
    final extraTrail = extras == null
        ? ''
        : ' · ${extras.cup} · ${extras.argonFlow}';
    final text = '${s.diaMm.toStringAsFixed(1)} mm (${s.diaImp}) '
        '${s.minA}-${s.maxA} A$extraTrail';
    await Clipboard.setData(ClipboardData(text: text));
    await Haptic.copied();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.tr(
              pl: 'Skopiowano: $text',
              en: 'Copied: $text')),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  /// Toggle "in stock / preferred" flag for the given diameter (long-press).
  /// Persists immediately to `prefs_tungsten_in_stock`.
  Future<void> _toggleInStock(TungstenSize s) async {
    await Haptic.tap();
    if (!mounted) return;
    final now = !_inStock.contains(s.diaMm);
    setState(() {
      if (now) {
        _inStock.add(s.diaMm);
      } else {
        _inStock.remove(s.diaMm);
      }
    });
    await _persistInStock();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            now
                ? context.tr(
                    pl: 'Ø ${s.diaMm.toStringAsFixed(1)} mm — w magazynie',
                    en: 'Ø ${s.diaMm.toStringAsFixed(1)} mm — in stock')
                : context.tr(
                    pl: 'Ø ${s.diaMm.toStringAsFixed(1)} mm — usunięto z magazynu',
                    en: 'Ø ${s.diaMm.toStringAsFixed(1)} mm — removed from stock'),
          ),
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  /// Open the override dialog (tap on a row). Captures a reason and records
  /// {suggested, used, reason} as a TungstenOverride.
  Future<void> _openOverrideDialog(TungstenSize tapped, TungstenSize? suggested) async {
    await Haptic.tap();
    if (!mounted) return;
    final ctrl = TextEditingController();
    // Suggested reasons (taps fill the field) — kept tight per P2-14 hints.
    final suggestPl = <String>[
      'stożek za zimny',
      'grubsza grań',
      'cienkościenna rura',
      'orbital — niski prąd',
      'tylko ta średnica w magazynie',
    ];
    final suggestEn = <String>[
      'cone too cold',
      'thicker root',
      'thin-wall tube',
      'orbital — low current',
      'only this size in stock',
    ];
    final isPl = context.language == AppLanguage.pl;
    final chips = isPl ? suggestPl : suggestEn;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(builder: (dCtx, setS) {
          return AlertDialog(
            backgroundColor: _kCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _kBorder),
            ),
            title: Text(
              context.tr(
                  pl: 'Nadpisać wybór? Powód:',
                  en: 'Override pick? Reason:'),
              style: const TextStyle(
                  color: Color(0xFFE8ECF0),
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (suggested != null)
                    Text(
                      context.tr(
                        pl: 'AI sugeruje Ø ${suggested.diaMm.toStringAsFixed(1)} mm — '
                            'wybierasz Ø ${tapped.diaMm.toStringAsFixed(1)} mm.',
                        en: 'AI suggests Ø ${suggested.diaMm.toStringAsFixed(1)} mm — '
                            'you are picking Ø ${tapped.diaMm.toStringAsFixed(1)} mm.',
                      ),
                      style: const TextStyle(
                          color: _kSec, fontSize: 12, height: 1.4),
                    )
                  else
                    Text(
                      context.tr(
                        pl: 'Brak sugestii (wpisz prąd, aby zobaczyć rekomendację). '
                            'Wybierasz Ø ${tapped.diaMm.toStringAsFixed(1)} mm.',
                        en: 'No suggestion yet (enter current to see a recommendation). '
                            'You are picking Ø ${tapped.diaMm.toStringAsFixed(1)} mm.',
                      ),
                      style: const TextStyle(
                          color: _kSec, fontSize: 12, height: 1.4),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                    ],
                    decoration: InputDecoration(
                      labelText: context.tr(pl: 'Powód', en: 'Reason'),
                      hintText: context.tr(
                          pl: 'np. stożek za zimny',
                          en: 'e.g. cone too cold'),
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in chips)
                        ActionChip(
                          label: Text(c,
                              style: const TextStyle(
                                  color: _kSec, fontSize: 12)),
                          backgroundColor: _kCard,
                          side: const BorderSide(color: _kBorder),
                          onPressed: () {
                            ctrl.text = c;
                            ctrl.selection = TextSelection.fromPosition(
                                TextPosition(offset: c.length));
                            setS(() {});
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actionsPadding:
                const EdgeInsets.fromLTRB(8, 0, 8, 8),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(
                  context.tr(pl: 'Anuluj', en: 'Cancel'),
                  style: const TextStyle(color: _kSec),
                ),
              ),
              FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(72, 44),
                ),
                child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
              ),
            ],
          );
        });
      },
    );

    ctrl.dispose();

    if (saved != true) return;
    if (!mounted) return;
    final reason = ctrl.text.trim();
    if (reason.isEmpty) return;
    final ampsParsed =
        double.tryParse(_amps.text.replaceAll(',', '.')) ?? 0;
    final record = TungstenOverride(
      suggestedDiaMm: suggested?.diaMm ?? tapped.diaMm,
      usedDiaMm: tapped.diaMm,
      reason: reason,
      amps: ampsParsed.round(),
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      // Newest-first, capped at 20 (persist enforces the same cap).
      _overrides.insert(0, record);
      if (_overrides.length > 20) {
        _overrides.removeRange(20, _overrides.length);
      }
    });
    await _persistOverrides();
    await Haptic.saved();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.tr(
            pl: 'Zapisano: Ø ${tapped.diaMm.toStringAsFixed(1)} mm — $reason',
            en: 'Saved: Ø ${tapped.diaMm.toStringAsFixed(1)} mm — $reason',
          )),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: context.tr(pl: 'Kopiuj', en: 'Copy'),
            onPressed: () => _copyRow(tapped),
          ),
        ),
      );
  }

  /// Most-recent override for the given diameter, or null if none.
  TungstenOverride? _lastOverrideFor(double diaMm) {
    for (final o in _overrides) {
      if (o.usedDiaMm == diaMm) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    final a = double.tryParse(_amps.text.replaceAll(',', '.'));
    final pick = (a != null && a > 0) ? sizeForCurrent(a) : null;
    // Out-of-range = entered current is outside the union of all electrode
    // bands (below kTungstenSizes.first.minA or above kTungstenSizes.last.maxA).
    final outOfBand = a != null &&
        a > 0 &&
        (a < kTungstenSizes.first.minA || a > kTungstenSizes.last.maxA);

    // P2-14: tip-angle helperText constrained to the currently-picked diameter.
    final pickDia = pick?.diaMm;
    final pickExtras = pickDia == null ? null : _extrasFor(pickDia);
    final ampsHelper = (pickExtras == null || pickDia == null)
        ? null
        : context.tr(
            pl: 'Kąt szlifu dla Ø ${pickDia.toStringAsFixed(1)} mm: '
                '${pickExtras.tipAngle}',
            en: 'Tip angle for Ø ${pickDia.toStringAsFixed(1)} mm: '
                '${pickExtras.tipAngle}',
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Elektroda wolframowa', en: 'Tungsten electrode')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
            onPressed: _clearAll,
          ),
          HelpButton(help: _kHelpTungsten),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          TextField(
            controller: _amps,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Prąd spawania (A, DC-)', en: 'Welding current (A, DC-)'),
              hintText: '90',
              helperText: ampsHelper,
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),

          // ── Optional joint identity (notes only, no backend wire) ─────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jointId,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Nr złącza (opcj.)',
                        en: 'Joint ID (optional)'),
                    hintText: 'W-001',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _jointStamp,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9\-]')),
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Stempel (opcj.)',
                        en: 'Stamp (optional)'),
                    hintText: 'JK-12',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Out-of-band warning tile ──────────────────────────────────────
          if (outOfBand) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kOrange, width: 1.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _kOrange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(
                              pl: 'POZA ZAKRESEM',
                              en: 'OUT OF RANGE'),
                          style: const TextStyle(
                            color: _kOrange,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            pl: 'Prąd ${a.toStringAsFixed(0)} A jest poza '
                                'zakresem tabeli '
                                '(${kTungstenSizes.first.minA}-'
                                '${kTungstenSizes.last.maxA} A). '
                                'Sprawdź wartość i biegunowość.',
                            en: 'Current ${a.toStringAsFixed(0)} A is outside '
                                'the table range '
                                '(${kTungstenSizes.first.minA}-'
                                '${kTungstenSizes.last.maxA} A). '
                                'Re-check value and polarity.',
                          ),
                          style: const TextStyle(
                            color: _kSec,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Diameter table, highlighting the pick ──────────────────────────
          Text(
            context.tr(
                pl: 'ŚREDNICA WG PRĄDU (DC-)', en: 'DIAMETER BY CURRENT (DC-)'),
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
                pl: 'Dotknij wiersza aby nadpisać · przytrzymaj aby oznaczyć w magazynie',
                en: 'Tap a row to override · long-press to flag in stock'),
            style: const TextStyle(
                color: _kMuted, fontSize: 11, height: 1.3),
          ),
          const SizedBox(height: 8),
          ...kTungstenSizes.map((s) {
            final hit = pick != null && pick.diaMm == s.diaMm;
            final inStock = _inStock.contains(s.diaMm);
            final extras = _extrasFor(s.diaMm);
            final lastOverride = _lastOverrideFor(s.diaMm);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openOverrideDialog(s, pick),
                  onLongPress: () => _toggleInStock(s),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: hit ? _kOrange.withValues(alpha: 0.12) : _kCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: hit ? _kOrange : _kBorder,
                          width: hit ? 1.5 : 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (hit)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.check_circle,
                                    color: _kOrange, size: 18),
                              ),
                            Text('Ø ${s.diaMm.toStringAsFixed(1)} mm',
                                style: TextStyle(
                                    color: hit
                                        ? _kOrange
                                        : const Color(0xFFE8ECF0),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text('(${s.diaImp})',
                                style: const TextStyle(
                                    color: _kMuted, fontSize: 12)),
                            const Spacer(),
                            if (inStock) ...[
                              Tooltip(
                                message: context.tr(
                                    pl: 'Oznaczone jako w magazynie',
                                    en: 'Flagged as in stock'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _kGreen.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.inventory_2_outlined,
                                          color: _kGreen, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        context.tr(
                                            pl: 'W MAG.',
                                            en: 'IN STOCK'),
                                        style: const TextStyle(
                                            color: _kGreen,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text('${s.minA}–${s.maxA} A',
                                style: TextStyle(
                                    color: hit ? _kOrange : _kSec,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        if (extras != null) ...[
                          const SizedBox(height: 6),
                          // ── recommendedCup + argonFlow on the row card ────
                          Row(
                            children: [
                              const Icon(Icons.adjust,
                                  color: _kMuted, size: 12),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  context.tr(
                                      pl: 'Dysza ${extras.cup}',
                                      en: 'Cup ${extras.cup}'),
                                  style: const TextStyle(
                                      color: _kSec,
                                      fontSize: 11,
                                      height: 1.3),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(Icons.air,
                                  color: _kMuted, size: 12),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  context.tr(
                                      pl: 'Argon ${extras.argonFlow}',
                                      en: 'Argon ${extras.argonFlow}'),
                                  style: const TextStyle(
                                      color: _kSec,
                                      fontSize: 11,
                                      height: 1.3),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.change_history,
                                  color: _kMuted, size: 12),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  context.tr(
                                      pl: 'Kąt szlifu ${extras.tipAngle}',
                                      en: 'Tip angle ${extras.tipAngle}'),
                                  style: const TextStyle(
                                      color: _kSec,
                                      fontSize: 11,
                                      height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (lastOverride != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kOrange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: _kOrange.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.history,
                                    color: _kOrange, size: 12),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    context.tr(
                                      pl: 'Ostatnio: ${lastOverride.reason}',
                                      en: 'Last: ${lastOverride.reason}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: _kOrange,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
          // ── Grind angle hint ───────────────────────────────────────────────
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
                const Icon(Icons.change_history, color: _kGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Kąt szlifu: ostry 20–30° dla niskich prądów i cienkiej '
                          'rury (skupiony łuk, orbital); tępy 45–60° dla wyższych '
                          'prądów. Szlifuj wzdłuż osi elektrody, dedykowaną tarczą.',
                      en: 'Grind angle: sharp 20–30° for low current and thin tube '
                          '(focused arc, orbital); blunt 45–60° for higher current. '
                          'Grind along the electrode axis with a dedicated wheel.',
                    ),
                    style: const TextStyle(color: _kSec, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                context.tr(
                    pl: 'TYP ELEKTRODY', en: 'ELECTRODE TYPE'),
                style: const TextStyle(
                    color: _kMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: context.tr(
                    pl: 'Kolorowa kropka = pasek na końcówce elektrody '
                        '(oznaczenie ISO 6848). Sprawdź kolor na swojej '
                        'elektrodzie aby zidentyfikować typ.',
                    en: 'Coloured dot = stripe on the electrode tip '
                        '(ISO 6848 marking). Check the colour on your '
                        'electrode to identify the type.'),
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 6),
                child: const Icon(Icons.info_outline,
                    color: _kMuted, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...kTungstenTypes.map((t) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: t.bestForSs
                          ? _kGreen.withValues(alpha: 0.4)
                          : _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 14, height: 14,
                          decoration: BoxDecoration(
                              color: t.colorDot,
                              shape: BoxShape.circle,
                              border: Border.all(color: _kBorder)),
                        ),
                        const SizedBox(width: 8),
                        Text(t.code,
                            style: const TextStyle(
                                color: Color(0xFFE8ECF0),
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isPl ? t.namePl : t.nameEn,
                            style: const TextStyle(color: _kSec, fontSize: 12),
                          ),
                        ),
                        if (t.bestForSs)
                          Tooltip(
                            message: context.tr(
                                pl: 'Zalecana do stali nierdzewnej (DC-)',
                                en: 'Recommended for stainless steel (DC-)'),
                            child: Semantics(
                              label: context.tr(
                                  pl: 'Zalecana do stali nierdzewnej',
                                  en: 'Recommended for stainless steel'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _kGreen.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('SS',
                                    style: TextStyle(
                                        color: _kGreen,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(isPl ? t.notePl : t.noteEn,
                        style: const TextStyle(
                            color: _kSec,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.4)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
