import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tungsten.dart';
import '../i18n/app_language.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kGreen  = Color(0xFF2ECC71);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

/// Tungsten electrode picker — enter the welding current, get the electrode
/// diameter, plus a reference of electrode types for stainless DC TIG.
class TungstenScreen extends StatefulWidget {
  const TungstenScreen({super.key});

  @override
  State<TungstenScreen> createState() => _TungstenScreenState();
}

class _TungstenScreenState extends State<TungstenScreen> {
  final _amps = TextEditingController();

  @override
  void dispose() {
    _amps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    final a = double.tryParse(_amps.text.replaceAll(',', '.'));
    final pick = (a != null && a > 0) ? sizeForCurrent(a) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Elektroda wolframowa', en: 'Tungsten electrode')),
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
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

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
          const SizedBox(height: 8),
          ...kTungstenSizes.map((s) {
            final hit = pick != null && pick.diaMm == s.diaMm;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: hit ? _kOrange.withValues(alpha: 0.12) : _kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: hit ? _kOrange : _kBorder,
                    width: hit ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  if (hit)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check_circle, color: _kOrange, size: 18),
                    ),
                  Text('Ø ${s.diaMm.toStringAsFixed(1)} mm',
                      style: TextStyle(
                          color: hit ? _kOrange : const Color(0xFFE8ECF0),
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Text('(${s.diaImp})',
                      style: const TextStyle(color: _kMuted, fontSize: 12)),
                  const Spacer(),
                  Text('${s.minA}–${s.maxA} A',
                      style: TextStyle(
                          color: hit ? _kOrange : _kSec,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
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
