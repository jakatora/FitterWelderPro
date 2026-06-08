import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/material_catalog.dart';
import '../utils/haptic.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kGreen  = Color(0xFF2ECC71);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

class _Check {
  final String pl;
  final String en;
  const _Check(this.pl, this.en);
}

/// Pre-weld checklist for hygienic stainless tube — the run-through a welder
/// does before every joint. State is in-memory only: it is a live check, not
/// a record, and resets for the next weld.
/// Material-specific extra checks. Pulled in when the welder picks a grade
/// from the catalog. Keeps the universal list short and adds only the items
/// that matter for the actual joint in front of them (P91 needs PWHT setup,
/// Duplex needs ferrite check, etc.).
const Map<int, List<_Check>> _pNumberExtras = {
  // P-No 1 — C-Mn steel
  1: [
    _Check('Elektroda E7018 / drut ER70S-2 w zamkniętym piecu (low-H)',
           'E7018 / ER70S-2 from sealed oven (low-H)'),
    _Check('Bevel 30° czysty, brak rdzy, kupon poradiowany jeśli >25 mm',
           'Bevel 30° clean, no rust, radiograph if >25 mm'),
  ],
  // P-No 4 — 1¼Cr-½Mo
  4: [
    _Check('Preheat 150-200°C zmierzony pirometrem przed pierwszą ściegą',
           'Preheat 150-200°C verified with pyrometer before first pass'),
    _Check('Drut/elektroda zgodna z B-grade (ER80S-B2 / E8018-B2)',
           'Filler matches B-grade (ER80S-B2 / E8018-B2)'),
    _Check('PWHT zaplanowany — termin i piec zarezerwowane',
           'PWHT scheduled — slot and furnace booked'),
  ],
  // P-No 5 (P22 / P91 grouped)
  5: [
    _Check('PREHEAT KRYTYCZNY 200-250°C, interpass max 300°C',
           'CRITICAL preheat 200-250°C, interpass max 300°C'),
    _Check('Elektroda E9015-B9 (P91) / E9018-B3 (P22) z certyfikatu HEAT',
           'E9015-B9 (P91) / E9018-B3 (P22) with HEAT certificate'),
    _Check('PWHT 750-770°C / 1 h-cal OBOWIĄZKOWE — slot zarezerwowany',
           'PWHT 750-770°C / 1 h-per-inch MANDATORY — slot booked'),
    _Check('Brak kontaktu CS↔CrMo (uziemnienie, narzędzia)',
           'No CS↔CrMo cross-contact (ground clamp, tools)'),
  ],
  // P-No 8 — Austenitic SS
  8: [
    _Check('Interpass <175°C — pirometr przed kolejną ściegą',
           'Interpass <175°C — pyrometer before next bead'),
    _Check('Drut L-grade (ER308L/ER316L) — niski C zapobiega sensitization',
           'L-grade filler (ER308L/ER316L) — low C prevents sensitization'),
    _Check('Argon czysty, brak N₂ w gazie formującym',
           'Argon pure, no N₂ in backing gas'),
    _Check('Pasywacja po spawaniu zaplanowana (kwas azotowy)',
           'Post-weld passivation scheduled (nitric acid)'),
  ],
  // P-No 10 — Duplex
  10: [
    _Check('Interpass MAX 150°C (2205) / 100°C (2507) — pirometr CO 2 ściegi',
           'Interpass MAX 150°C (2205) / 100°C (2507) — pyrometer every 2 passes'),
    _Check('Gaz formujący Ar + 2% N₂ (utrzymanie austenitu)',
           'Backing gas Ar + 2% N₂ (austenite balance)'),
    _Check('HI w oknie 0.5-2.5 kJ/mm — wyższy → σ-phase',
           'HI in 0.5-2.5 kJ/mm window — higher → σ-phase'),
    _Check('Ferrite check po cooldown (target 30-60 FN)',
           'Ferrite check after cooldown (target 30-60 FN)'),
  ],
  // P-No 41-45 — Ni alloys
  43: [
    _Check('Niski HI <1.5 kJ/mm — narrow string beads',
           'Low HI <1.5 kJ/mm — narrow string beads'),
    _Check('Argon czysty (>99.99%), brak Helium na nierdzewce',
           'Pure argon (>99.99%), no Helium on SS'),
    _Check('Drut ERNiCrMo-3 (625) z certyfikatu',
           'ERNiCrMo-3 (625) wire with cert'),
  ],
};

const List<_Check> _checks = [
  _Check('Szczelina fit-up ≈ 0, rury współosiowe (brak przesunięcia lic)',
         'Fit-up gap ≈ 0, tubes aligned (no land mismatch)'),
  _Check('Końce rur czyste — odtłuszczone, bez śladów markera',
         'Tube ends clean — degreased, no marker ink'),
  _Check('Gaz formujący podłączony, tamy/korki purge założone',
         'Backing gas connected, purge dams/plugs fitted'),
  _Check('Przepływ gazu osłonowego i formującego ustawiony',
         'Shielding and backing gas flow set'),
  _Check('O₂ w gazie formującym poniżej limitu (miernik)',
         'Backing-gas O₂ below the limit (meter checked)'),
  _Check('Pre-purge odczekany — powietrze wypłukane',
         'Pre-purge time elapsed — air flushed out'),
  _Check('Elektroda wolframowa zaostrzona, czysta, właściwa średnica',
         'Tungsten electrode sharp, clean, correct diameter'),
  _Check('Parametry maszyny zgodne z WPS / programem',
         'Machine parameters match the WPS / program'),
  _Check('Kupon próbny dnia wykonany i zaakceptowany',
         "Today's test coupon welded and accepted"),
  _Check('Numer spoiny naniesiony, weld map zaktualizowana',
         'Weld number marked, weld map updated'),
  _Check('Narzędzia dedykowane do nierdzewki (brak kontaktu z żelazem)',
         'Stainless-only tools used (no iron cross-contamination)'),
];

/// Scans a preheatNote like "200–250 °C, interpass 250–300 °C" for °C numbers
/// and appends a "  (~390–480 °F)" tail. Best-effort — if no °C number is
/// found (notes like "Bez preheat.") returns an empty string so the tooltip
/// stays clean.
String _preheatFahrenheit(String note) {
  final matches = RegExp(r'(\d+)\s*°?\s*C').allMatches(note).toList();
  if (matches.isEmpty) return '';
  final fs = matches
      .map((m) => (int.parse(m.group(1)!) * 9 / 5 + 32).round())
      .toList();
  final tail = fs.length == 1
      ? '${fs.first} °F'
      : '${fs.reduce((a, b) => a < b ? a : b)}–${fs.reduce((a, b) => a > b ? a : b)} °F';
  return '  (~$tail)';
}

class PreWeldChecklistScreen extends StatefulWidget {
  const PreWeldChecklistScreen({super.key});

  @override
  State<PreWeldChecklistScreen> createState() => _PreWeldChecklistScreenState();
}

class _PreWeldChecklistScreenState extends State<PreWeldChecklistScreen> {
  final _done = <int>{};
  MaterialSpec? _material;

  /// Combined check list = universal items + extras for the picked grade's
  /// P-Number. Index 0..len-1 stays consistent across builds because we never
  /// re-order (extras are always appended).
  List<_Check> get _all {
    final list = <_Check>[..._checks];
    if (_material != null) {
      final extras = _pNumberExtras[_material!.pNumber];
      if (extras != null) list.addAll(extras);
    }
    return list;
  }

  void _toggle(int i) {
    setState(() {
      if (_done.contains(i)) {
        _done.remove(i);
      } else {
        _done.add(i);
        Haptic.tap();
      }
    });
    if (_done.length == _all.length) Haptic.saved();
  }

  /// P0-14: Wipe behind a confirm dialog + Undo snackbar. Without this a
  /// phantom thumb tap during scroll was silently erasing 60-90 s of careful
  /// pre-weld inspection — welder could strike arc believing the checklist
  /// was completed when it had been blanked by the same gesture used to
  /// scroll. Safety-critical.
  Future<void> _confirmReset() async {
    final tickedCount = _done.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(context.tr(
          pl: 'Wyzerować checklistę?',
          en: 'Reset checklist?',
        )),
        content: Text(context.tr(
          pl: '$tickedCount pozycji jest zaznaczonych. '
              'Tej operacji nie można cofnąć po zamknięciu pasków.',
          en: '$tickedCount items are ticked. '
              'This cannot be undone once the SnackBar disappears.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade400,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(context.tr(pl: 'Wyczyść', en: 'Reset')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final snapshot = Set<int>.from(_done);
    setState(_done.clear);
    Haptic.error();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(
        pl: 'Checklistę wyczyszczono ($tickedCount pozycji).',
        en: 'Checklist reset ($tickedCount items).',
      )),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: context.tr(pl: 'Cofnij', en: 'Undo'),
        onPressed: () {
          if (!mounted) return;
          setState(() {
            _done
              ..clear()
              ..addAll(snapshot);
          });
        },
      ),
    ));
  }

  void _setMaterial(MaterialSpec? m) {
    setState(() {
      _material = m;
      // Drop ticked indices that point past the new list (shorter list after
      // deselecting a material with extras).
      _done.removeWhere((i) => i >= _all.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    final list = _all;
    final all = _done.length == list.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Checklista przed spawaniem',
            en: 'Pre-weld checklist')),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: context.tr(pl: 'Wyczyść', en: 'Reset'),
            onPressed: _done.isEmpty ? null : _confirmReset,
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress strip
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: all
                  ? _kGreen.withValues(alpha: 0.12)
                  : _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: all ? _kGreen.withValues(alpha: 0.5) : _kBorder),
            ),
            child: Row(
              children: [
                Icon(all ? Icons.check_circle : Icons.checklist_rtl,
                    color: all ? _kGreen : _kOrange, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    all
                        ? context.tr(
                            pl: 'Gotowe — możesz zajarzać łuk.',
                            en: 'All set — you can strike the arc.')
                        : context.tr(
                            pl: 'Sprawdź wszystkie punkty przed spoiną.',
                            en: 'Tick every item before welding.'),
                    style: TextStyle(
                        color: all ? _kGreen : _kSec,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${_done.length}/${list.length}',
                    style: TextStyle(
                        color: all ? _kGreen : _kOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          // Material picker — adds grade-specific checks (P91 needs PWHT slot,
          // Duplex needs ferrite check, etc.) on top of the universal list.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              // Glove-friendly: 48dp min strip so material picker chips meet
              // the WCAG/MD3 touch target — these chips gate grade-specific
              // safety checks (P91 PWHT, Duplex ferrite) and must be tappable
              // through a thick welding glove without hunting.
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: Text(context.tr(pl: 'wszystkie', en: 'generic'),
                        style: const TextStyle(fontSize: 11)),
                    selected: _material == null,
                    onSelected: (_) => _setMaterial(null),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  const SizedBox(width: 6),
                  for (final m in MaterialCatalog.all) ...[
                    // Long-press hint surfaces preheat range in both °C and °F
                    // for welders cross-reading EU WPS against US ASME spec sheets
                    // without retyping into a converter.
                    Tooltip(
                      message: '${m.key}: ${m.preheatNote}'
                          '${_preheatFahrenheit(m.preheatNote)}',
                      child: ChoiceChip(
                        label: Text(m.key, style: const TextStyle(fontSize: 11)),
                        selected: _material?.key == m.key,
                        onSelected: (_) => _setMaterial(m),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final done = _done.contains(i);
                final c = list[i];
                final isExtra = i >= _checks.length;
                // Group divider before the first material-specific extra so the
                // jump from universal → grade-specific is visible at a glance.
                final showDivider = isExtra && i == _checks.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDivider && _material != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                        child: Row(
                          children: [
                            Expanded(child: Container(height: 1, color: _kBorder)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                context.tr(
                                    pl: 'Specyficzne · ${_material!.key}',
                                    en: 'Specific to ${_material!.key}'),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: _kOrange,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            Expanded(child: Container(height: 1, color: _kBorder)),
                          ],
                        ),
                      ),
                    GestureDetector(
                      onTap: () => _toggle(i),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: done
                              ? _kGreen.withValues(alpha: 0.5)
                              : _kBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          done
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: done ? _kGreen : _kMuted,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isExtra && _material != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    '${_material!.key} · P${_material!.pNumber}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: _kOrange,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              Text(
                                isPl ? c.pl : c.en,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: done
                                      ? _kMuted
                                      : const Color(0xFFE8ECF0),
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
