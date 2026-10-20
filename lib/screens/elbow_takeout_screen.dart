import 'package:flutter/material.dart';
import '../assistant/core/tool_bridge.dart';

import '../data/elbow_takeouts.dart';
import '../domain/fitter/size_query.dart';
import '../i18n/app_language.dart';
import '../utils/clipboard_helper.dart';
import '../theme/app_theme.dart' show kTextMut;

const _kCard = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kSec = Color(0xFF9BA3C7);
const _kMuted = kTextMut;
const _kAccent = Color(0xFF4A9EFF);

/// Quick reference: centre-to-face dimensions for butt-weld elbows.
/// Long-press any number to copy it.
class ElbowTakeoutScreen extends StatefulWidget {
  const ElbowTakeoutScreen({super.key});

  @override
  State<ElbowTakeoutScreen> createState() => _ElbowTakeoutScreenState();
}

class _ElbowTakeoutScreenState extends State<ElbowTakeoutScreen>
    with ToolHandleHost<ElbowTakeoutScreen> {
  @override
  String get toolId => 'elbow_takeouts';
  @override
  Set<String> get supportedFields => const {'dn'};
  @override
  void initState() {
    super.initState();
    markReady();
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final dn = fields['dn'];
    if (fields.keys.any((k) => !supportedFields.contains(k))) {
      return fields.keys.toSet();
    }
    if (dn is! int || !kElbowTakeouts.any((r) => r.dn == dn)) return {'dn'};
    if (!mounted) return {'dn'};
    setState(() {
      _q = 'DN$dn';
      _filter.text = _q;
    });
    return {};
  }

  final _filter = TextEditingController();
  String _q = '';
  // Cache filtered rows so we don't walk the full list on every rebuild
  // (e.g. keyboard show/hide, theme changes). Recomputed only when _q changes.
  List<ElbowTakeout> _cachedRows = kElbowTakeouts;
  String _cachedQ = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<ElbowTakeout> get _rows {
    if (_cachedQ == _q) return _cachedRows;
    _cachedQ = _q;
    // `2"`, `2 cale`, `1 1/2"`, `DN 50` — lib/domain/fitter/size_query.dart.
    _cachedRows = kElbowTakeouts
        .where((e) => sizeQueryMatches(_q, dn: e.dn, nps: e.nps))
        .toList();
    return _cachedRows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Wymiary kolan (centre–face)',
            en: 'Elbow takeouts (centre-to-face)')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _filter,
              // Longest sensible token is e.g. "DN1200" / "24" — 16 chars is
              // already 2x headroom. Caps pathological pastes silently.
              maxLength: 16,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: context.tr(
                    pl: 'Szukaj: DN50, 2", 100…', en: 'Search: DN50, 2", 100…'),
                isDense: true,
                counterText: '',
              ),
              textInputAction: TextInputAction.search,
              // Trim at the source so trailing whitespace from autocorrect /
              // paste doesn't bust the filter cache or break substring match.
              onChanged: (v) {
                final t = v.trim();
                if (t == _q) return;
                setState(() => _q = t);
              },
            ),
          ),
          const _LegendBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
            child: Text(
              context.tr(
                pl: 'ASME B16.9-2018 · SR 90° dopiero od DN25 (NPS 1) · norma nie ma kolan SR 45°',
                en: 'ASME B16.9-2018 · SR 90° only from DN25 (NPS 1) · the standard has no SR 45° elbows',
              ),
              style: const TextStyle(color: _kMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: _rows.isEmpty
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
                                pl: 'Brak wyników dla "$_q"',
                                en: 'No results for "$_q"'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFE7ECF3),
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr(
                                pl: 'Spróbuj: DN50, 2", 1 1/2", 100',
                                en: 'Try: DN50, 2", 1 1/2", 100'),
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: _kMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) => _Row(e: _rows[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LegendBar extends StatelessWidget {
  const _LegendBar();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: const [
          _LegendChip(label: 'DN / NPS', color: _kMuted),
          _LegendChip(label: 'LR 90°', color: _kOrange),
          _LegendChip(label: 'SR 90°', color: _kAccent),
          _LegendChip(label: 'LR 45°', color: _kSec),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final ElbowTakeout e;
  const _Row({required this.e});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // DN + actual elbow size (NPS) on one prominent line so the
                // fitter sees the pipe size at a glance without scanning
                // a second muted row.
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: Color(0xFFE7ECF3),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      TextSpan(text: 'DN${e.dn}'),
                      TextSpan(
                        text: '  · ${e.nps}"',
                        style: const TextStyle(
                          color: _kOrange,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  context.tr(pl: 'rozmiar kolanka', en: 'elbow size'),
                  style: const TextStyle(color: _kMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          _Cell(value: '${e.lr90}', unit: 'mm', color: _kOrange),
          // B16.9 has no short radius elbow below NPS 1 (DN25) — show a dash,
          // never a made-up number.
          if (e.sr90 == null)
            _Cell(
              value: '—',
              unit: context.tr(pl: 'brak', en: 'n/a'),
              color: _kMuted,
              copyable: false,
            )
          else
            _Cell(value: '${e.sr90}', unit: 'mm', color: _kAccent),
          _Cell(value: '${e.lr45}', unit: 'mm', color: _kSec),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final String unit;
  final Color color;
  final bool copyable;
  const _Cell({
    required this.value,
    required this.unit,
    required this.color,
    this.copyable = true,
  });
  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(unit,
              style: const TextStyle(color: _kMuted, fontSize: 10, height: 1)),
        ],
      ),
    );
    return Expanded(
      child: copyable
          ? CopyOnLongPress(value: value, label: 'centre–face', child: body)
          : body,
    );
  }
}
