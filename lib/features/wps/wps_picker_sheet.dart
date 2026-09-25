/// Wybór WPS z Biblioteki WPS — wspólny dla dziennika spoin (pole WPS
/// spoiny) i ekranu energii liniowej (zakres min–max i konwencja z WPS).
///
/// Pusta biblioteka nie jest błędem: arkusz mówi, skąd wziąć WPS, i otwiera
/// bibliotekę; po powrocie lista się odświeża.
library;

import 'package:flutter/material.dart';

import '../../database/wps_dao.dart';
import '../../domain/welding/heat_input.dart';
import '../../domain/wps/wps_record.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import 'wps_library_page.dart';

/// Źródło listy WPS (w testach — lista w pamięci).
typedef WpsLoader = Future<List<WpsRecord>> Function();

Future<WpsRecord?> showWpsPickerSheet(
  BuildContext context, {
  String? currentId,
  WpsLoader? load,
}) =>
    showModalBottomSheet<WpsRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: WpsPickerList(
            currentId: currentId,
            load: load ?? () => WpsDao().listAll(),
          ),
        ),
      ),
    );

String _num(double v) {
  final s = v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

String _range(double? min, double? max) {
  if (min != null && max != null) return '${_num(min)}–${_num(max)}';
  if (min != null) return '≥ ${_num(min)}';
  if (max != null) return '≤ ${_num(max)}';
  return '';
}

/// Jedna linia opisu WPS na liście: procesy, grupa, t, D, pozycje, energia.
String wpsSummaryLine(WpsRecord w, {required bool en}) {
  final t = _range(w.thicknessMinMm, w.thicknessMaxMm);
  final d = _range(w.diameterMinMm, w.diameterMaxMm);
  final hi = _range(w.heatInputMinKjMm, w.heatInputMaxKjMm);
  final method = switch (w.heatInputMethod) {
    HeatInputStandard.en1011 => 'EN',
    HeatInputStandard.asmeIx => 'ASME',
  };
  return [
    if (w.processes.trim().isNotEmpty) w.processes.trim(),
    if (w.materialGroup.trim().isNotEmpty)
      '${en ? 'gr.' : 'gr.'} ${w.materialGroup.trim()}',
    if (t.isNotEmpty) 't $t mm',
    if (d.isNotEmpty) 'D $d mm',
    if (w.positions.trim().isNotEmpty) w.positions.trim(),
    if (hi.isNotEmpty) '$hi kJ/mm $method',
  ].join(' · ');
}

class WpsPickerList extends StatefulWidget {
  final String? currentId;
  final WpsLoader load;

  const WpsPickerList({super.key, this.currentId, required this.load});

  @override
  State<WpsPickerList> createState() => _WpsPickerListState();
}

class _WpsPickerListState extends State<WpsPickerList> {
  late Future<List<WpsRecord>> _future = widget.load();

  Future<void> _openLibrary() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const WpsLibraryPage()),
    );
    if (mounted) setState(() => _future = widget.load());
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(pl: 'WPS z Biblioteki WPS', en: 'WPS from the library'),
            style: const TextStyle(
                color: kArc, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: FutureBuilder<List<WpsRecord>>(
              future: _future,
              builder: (_, snap) {
                if (snap.hasError) {
                  return Text(
                      context.tr(
                          pl: 'Nie udało się wczytać Biblioteki WPS.',
                          en: 'Failed to load the WPS library.'),
                      style: const TextStyle(color: kFail));
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child:
                        Center(child: CircularProgressIndicator(color: kArc)),
                  );
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return Text(
                    context.tr(
                      pl: 'Biblioteka WPS jest pusta. Dodaj WPS (ręcznie albo '
                          'z pliku od koordynatora) — potem wybierzesz ją '
                          'tutaj. Numer możesz też wpisać ręcznie.',
                      en: 'The WPS library is empty. Add a WPS (by hand or '
                          'from a file from your coordinator) — then pick it '
                          'here. You can also type the number by hand.',
                    ),
                    style: const TextStyle(color: kTextMut),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final w = list[i];
                    final selected = w.id == widget.currentId;
                    final summary = wpsSummaryLine(w, en: en);
                    return InkWell(
                      onTap: () => Navigator.pop(context, w),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        constraints:
                            const BoxConstraints(minHeight: kMinTapTarget),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? kArc.withValues(alpha: 0.12) : kBg,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: selected ? kArc : kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.displayName,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: kText)),
                            if (summary.isNotEmpty)
                              Text(summary,
                                  style: const TextStyle(
                                      fontSize: 12, color: kTextSec)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                  onPressed: _openLibrary,
                  icon: const Icon(Icons.library_books_outlined, size: 20),
                  label: Text(context.tr(
                      pl: 'Biblioteka WPS', en: 'WPS library')),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
