import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
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

class PreWeldChecklistScreen extends StatefulWidget {
  const PreWeldChecklistScreen({super.key});

  @override
  State<PreWeldChecklistScreen> createState() => _PreWeldChecklistScreenState();
}

class _PreWeldChecklistScreenState extends State<PreWeldChecklistScreen> {
  final _done = <int>{};

  void _toggle(int i) {
    setState(() {
      if (_done.contains(i)) {
        _done.remove(i);
      } else {
        _done.add(i);
        Haptic.tap();
      }
    });
    if (_done.length == _checks.length) Haptic.saved();
  }

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    final all = _done.length == _checks.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Checklista przed spawaniem',
            en: 'Pre-weld checklist')),
        actions: [
          TextButton(
            onPressed: _done.isEmpty ? null : () => setState(_done.clear),
            child: Text(context.tr(pl: 'Reset', en: 'Reset')),
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
                Text('${_done.length}/${_checks.length}',
                    style: TextStyle(
                        color: all ? _kGreen : _kOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _checks.length,
              itemBuilder: (_, i) {
                final done = _done.contains(i);
                final c = _checks[i];
                return GestureDetector(
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
                          child: Text(
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
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
