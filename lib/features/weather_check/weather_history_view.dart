// Historia pomiarów „Warunki do spawania”: lista (najnowsze na górze),
// podgląd raportu, udostępnienie tekstem / PDF, usunięcie wpisu.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/welding/weather_conditions.dart';
import '../../i18n/app_language.dart';
import '../../services/weather_check_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/local_record_scope.dart';
import '../quotes/quote_widgets.dart';
import 'weather_check_store.dart';

class WeatherHistoryView extends StatefulWidget {
  const WeatherHistoryView({
    super.key,
    required this.session,
    required this.store,
    required this.shareText,
    required this.sharePdf,
  });

  final LocalRecordSession session;
  final WeatherCheckStore store;
  final Future<void> Function(String text, String subject) shareText;
  final Future<void> Function(WeatherCheckRecord record, bool english) sharePdf;

  @override
  State<WeatherHistoryView> createState() => _WeatherHistoryViewState();
}

class _WeatherHistoryViewState extends State<WeatherHistoryView> {
  List<WeatherCheckRecord>? _records;

  /// Pominięte uszkodzone wpisy; -1 — cały zapis nieczytelny.
  int _skipped = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<WeatherCheckRecord> list;
    var skipped = 0;
    try {
      final h = await widget.store.loadHistoryDetailed();
      list = h.records;
      skipped = h.unreadable ? -1 : h.skipped;
    } catch (_) {
      list = const [];
      skipped = -1;
    }
    if (mounted && widget.session.isCurrent) {
      setState(() {
        _records = list;
        _skipped = skipped;
      });
    }
  }

  bool get _en => context.language == AppLanguage.en;

  (Color, IconData) _look(WeatherVerdict v) => switch (v) {
        WeatherVerdict.go => (kPass, Icons.check_circle_outline),
        WeatherVerdict.conditional => (kWarn, Icons.rule),
        WeatherVerdict.noGo => (kFail, Icons.block),
      };

  String _summary(WeatherCheckRecord r) {
    final i = r.input;
    String n(double v) => weatherNumAuto(v, english: _en);
    return '${n(i.ambientC)} °C · RH ${n(i.rhPct)} % · '
        '${weatherNumAuto(ceilTo(i.windMs, 2), english: _en)} m/s · '
        '${i.process.label(_en)}';
  }

  Future<void> _delete(WeatherCheckRecord r) async {
    if (!widget.session.isCurrent) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => LocalRecordScope(
        originSession: widget.session,
        restartOnAccountChange: false,
        builder: (_, __) => AlertDialog(
          title:
              Text(context.tr(pl: 'Usunąć pomiar?', en: 'Delete this check?')),
          content: Text(
              '${weatherStamp(r.takenAt)}${r.place.isEmpty ? '' : ' · ${r.place}'}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
            ),
            TextButton(
              key: const ValueKey('wx-rec-delete-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.tr(pl: 'Usuń', en: 'Delete'),
                  style: const TextStyle(color: kFail)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !widget.session.isCurrent) return;
    unawaited(Haptic.tap());
    try {
      final list = await widget.store.remove(r.id);
      if (mounted && widget.session.isCurrent) {
        setState(() {
          _records = list;
          // Uszkodzony zapis skopiowano (…_corrupt) i nadpisano.
          _skipped = 0;
        });
      }
    } catch (e) {
      debugPrint('[weather] delete failed: $e');
    }
  }

  Future<void> _open(WeatherCheckRecord r) async {
    if (!widget.session.isCurrent) return;
    final en = _en;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => LocalRecordScope(
        originSession: widget.session,
        restartOnAccountChange: false,
        builder: (_, __) => SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
            child: ListView(
              key: const ValueKey('wx-rec-sheet'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shrinkWrap: true,
              children: [
                SelectableText(
                  weatherCheckText(r, english: en),
                  style:
                      const TextStyle(fontSize: 13, color: kText, height: 1.4),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('wx-rec-share-text'),
                      onPressed: () {
                        if (!widget.session.isCurrent) return;
                        widget.shareText(weatherCheckText(r, english: en),
                            weatherCheckSubject(english: en));
                      },
                      icon: const Icon(Icons.ios_share),
                      label: Text(context.tr(pl: 'Tekst', en: 'Text')),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('wx-rec-share-pdf'),
                      onPressed: () async {
                        if (!widget.session.isCurrent) return;
                        try {
                          await widget.sharePdf(r, en);
                        } catch (e) {
                          debugPrint('[weather] pdf export failed: $e');
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('wx-rec-delete'),
                      style: TextButton.styleFrom(
                          foregroundColor: kFail,
                          minimumSize: const Size(0, kMinTapTarget)),
                      onPressed: () {
                        if (!widget.session.isCurrent) return;
                        Navigator.of(ctx).pop();
                        unawaited(_delete(r));
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text(context.tr(pl: 'Usuń', en: 'Delete')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Historia pomiarów', en: 'Check history')),
      ),
      body: records == null
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : ListView(
              key: const ValueKey('wx-history-list'),
              padding: EdgeInsets.fromLTRB(
                  12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
              children: [
                if (_skipped != 0)
                  QuoteNotice(
                    key: const ValueKey('wx-history-skipped'),
                    color: kFail,
                    icon: Icons.report_problem_outlined,
                    text: _skipped < 0
                        ? context.tr(
                            pl: 'Zapis historii jest nieczytelny. Przy '
                                'następnym zapisie jego kopia trafi pod '
                                '„${WeatherCheckStore.corruptHistoryKey}”.',
                            en: 'The saved history is unreadable. On the next '
                                'save a copy is kept under '
                                '“${WeatherCheckStore.corruptHistoryKey}”.')
                        : context.tr(
                            pl: '$_skipped wpisów pominięto (uszkodzone). '
                                'Przy następnym zapisie kopia całego zapisu '
                                'trafi pod „${WeatherCheckStore.corruptHistoryKey}”.',
                            en: '$_skipped entries skipped (damaged). On the '
                                'next save a copy of the whole record is kept '
                                'under “${WeatherCheckStore.corruptHistoryKey}”.'),
                  ),
                if (records.length >= WeatherCheckStore.warnRecords)
                  QuoteNotice(
                    key: const ValueKey('wx-history-limit'),
                    text: context.tr(
                        pl: 'Historia: ${records.length} z '
                            '${WeatherCheckStore.maxRecords} wpisów. Po '
                            'przekroczeniu limitu najstarsze są usuwane — '
                            'udostępnij (PDF/tekst) te, które trzeba zachować.',
                        en: 'History: ${records.length} of '
                            '${WeatherCheckStore.maxRecords} entries. Beyond '
                            'the limit the oldest are removed — share (PDF/'
                            'text) the ones you must keep.'),
                  ),
                if (records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.tr(
                          pl: 'Brak zapisanych pomiarów. Zapisz pomiar na '
                              'ekranie „Warunki do spawania”.',
                          en: 'No saved checks yet. Save one on the '
                              '“Welding conditions” screen.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kTextSec),
                    ),
                  ),
                for (final r in records) _tile(r),
              ],
            ),
    );
  }

  Widget _tile(WeatherCheckRecord r) {
    final (color, icon) = _look(r.verdict);
    final mismatch = r.rulesMismatch;
    return Card(
      key: ValueKey('wx-record-${r.id}'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: 10,
        leading: Icon(icon, color: color),
        title: Text(
          '${weatherStamp(r.takenAt)}'
          '${r.place.isEmpty ? '' : ' · ${r.place}'}',
          style: const TextStyle(color: kText, fontWeight: FontWeight.w600),
        ),
        subtitle: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '${weatherVerdictText(r.verdict, english: _en)}\n'
                    '${_summary(r)}'),
            if (mismatch)
              TextSpan(
                text: context.tr(
                    pl: '\nOdtworzone inną wersją reguł — wiąże zapisany '
                        'werdykt',
                    en: '\nRebuilt with a different rules version — the saved '
                        'verdict governs'),
                style: const TextStyle(color: kWarn),
              ),
          ]),
          key: mismatch ? ValueKey('wx-record-mismatch-${r.id}') : null,
          style: const TextStyle(color: kTextSec, height: 1.35),
        ),
        isThreeLine: true,
        onTap: () => _open(r),
      ),
    );
  }
}
