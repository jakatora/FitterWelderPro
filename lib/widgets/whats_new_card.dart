// „Nowe w aplikacji” — karta na ekranie głównym po aktualizacji: poziomy
// pasek kafli prowadzących prosto do nowych narzędzi. Zamknięta raz — nie
// wraca (klucz w SharedPreferences z numerem fali nowości). Wpisy żyją
// w rejestrze narzędzi; nieznane / ukryte flagą są pomijane.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_language.dart';
import '../theme/app_theme.dart';
import 'tool_registry.dart';

/// Klucz zamknięcia karty — nowa fala nowości = nowy klucz.
const String kWhatsNewSeenKey = 'whats_new_seen_2026_10';

/// Narzędzia z tej fali, w kolejności pokazywania.
const List<String> kWhatsNewToolIds = [
  'weld_quotes',
  'hourly_rate',
  'piecework',
  'filler_selector',
  'pwht_planner',
  'cooling_time',
  'fillet_strength',
  'distortion',
  'iso5817',
  'weld_symbols',
  'work_progress',
  'ndt_plan',
  'qualification_range',
  'weather_check',
  'hot_work',
  'electrode_exposure',
  'hardness',
  'instruments',
  'flange_check',
  'bolt_kit',
  'mitre_bend',
  'tube_bending',
  'cone_layout',
  'glossary',
  'steel_weight',
];

class WhatsNewCard extends StatefulWidget {
  const WhatsNewCard({super.key});

  @override
  State<WhatsNewCard> createState() => _WhatsNewCardState();
}

class _WhatsNewCardState extends State<WhatsNewCard> {
  /// `null` = jeszcze nie wiemy (nic nie rysujemy, żeby nie mignęło).
  bool? _seen;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var seen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(kWhatsNewSeenKey) ?? false;
    } catch (_) {
      seen = false;
    }
    if (mounted) setState(() => _seen = seen);
  }

  Future<void> _dismiss() async {
    setState(() => _seen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kWhatsNewSeenKey, true);
    } catch (_) {
      // Najwyżej pokaże się jeszcze raz po restarcie.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_seen != false) return const SizedBox.shrink();
    final tools = resolveTools(kWhatsNewToolIds);
    if (tools.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        key: const ValueKey('whats-new'),
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: kArc.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: kArc, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr(
                          pl: 'NOWE W APLIKACJI', en: 'NEW IN THE APP'),
                      style: const TextStyle(
                        color: kArc,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('whats-new-close'),
                    tooltip: context.tr(pl: 'Zamknij', en: 'Close'),
                    icon: const Icon(Icons.close, size: 20, color: kTextMut),
                    onPressed: _dismiss,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  context.tr(
                    pl: 'Wyceny z ofertą PDF, dobór spoiwa, plan PWHT, odbiór '
                        'wg ISO 5817, symbole spawalnicze, postęp robót i więcej.',
                    en: 'Quotes with a PDF offer, filler selector, PWHT plan, '
                        'ISO 5817 acceptance, welding symbols, work progress '
                        'and more.',
                  ),
                  style: const TextStyle(
                      fontSize: 12.5, color: kTextSec, height: 1.35),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 10),
                  itemCount: tools.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final t = tools[i];
                    return Material(
                      color: kBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: kBorder),
                      ),
                      child: InkWell(
                        key: ValueKey('whats-new-${t.id}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => openTool(context, t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.icon, color: t.color, size: 22),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 150),
                                child: Text(
                                  t.title(context),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
