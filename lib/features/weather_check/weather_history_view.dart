// Historia pomiarów „Warunki do spawania”: lista (najnowsze na górze),
// podgląd raportu, udostępnienie tekstem / PDF, usunięcie wpisu.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/welding/weather_conditions.dart';
import '../../i18n/app_language.dart';
import '../../services/weather_check_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import 'weather_check_store.dart';

class WeatherHistoryView extends StatefulWidget {
  const WeatherHistoryView({
    super.key,
    required this.store,
    required this.shareText,
    required this.sharePdf,
  });

  final WeatherCheckStore store;
  final Future<void> Function(String text, String subject) shareText;
  final Future<void> Function(WeatherCheckRecord record, bool english) sharePdf;

  @override
  State<WeatherHistoryView> createState() => _WeatherHistoryViewState();
}

class _WeatherHistoryViewState extends State<WeatherHistoryView> {
  List<WeatherCheckRecord>? _records;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<WeatherCheckRecord> list;
    try {
      list = await widget.store.loadHistory();
    } catch (_) {
      list = const [];
    }
    if (mounted) setState(() => _records = list);
  }

  bool get _en => context.language == AppLanguage.en;

  (Color, IconData) _look(WeatherVerdict v) => switch (v) {
        WeatherVerdict.go => (kPass, Icons.check_circle_outline),
        WeatherVerdict.conditional => (kWarn, Icons.rule),
        WeatherVerdict.noGo => (kFail, Icons.block),
      };

  String _summary(WeatherCheckRecord r) {
    final i = r.input;
    String n(double v, [int d = 1]) => weatherNum(v, decimals: d, english: _en);
    return '${n(i.ambientC)} °C · RH ${n(i.rhPct, 0)} % · '
        '${n(i.windMs)} m/s · ${i.process.label(_en)}';
  }

  Future<void> _delete(WeatherCheckRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(pl: 'Usunąć pomiar?', en: 'Delete this check?')),
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
    );
    if (ok != true) return;
    unawaited(Haptic.tap());
    try {
      final list = await widget.store.remove(r.id);
      if (mounted) setState(() => _records = list);
    } catch (e) {
      debugPrint('[weather] delete failed: $e');
    }
  }

  Future<void> _open(WeatherCheckRecord r) async {
    final en = _en;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
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
                style: const TextStyle(fontSize: 13, color: kText, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('wx-rec-share-text'),
                    onPressed: () => widget.shareText(
                        weatherCheckText(r, english: en),
                        weatherCheckSubject(english: en)),
                    icon: const Icon(Icons.ios_share),
                    label: Text(context.tr(pl: 'Tekst', en: 'Text')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('wx-rec-share-pdf'),
                    onPressed: () async {
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
          : records.isEmpty
              ? Center(
                  child: Padding(
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
                )
              : ListView.builder(
                  key: const ValueKey('wx-history-list'),
                  padding: EdgeInsets.fromLTRB(12, 12, 12,
                      24 + MediaQuery.viewPaddingOf(context).bottom),
                  itemCount: records.length,
                  itemBuilder: (_, i) {
                    final r = records[i];
                    final (color, icon) = _look(r.verdict);
                    return Card(
                      key: ValueKey('wx-record-${r.id}'),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        minVerticalPadding: 10,
                        leading: Icon(icon, color: color),
                        title: Text(
                          '${weatherStamp(r.takenAt)}'
                          '${r.place.isEmpty ? '' : ' · ${r.place}'}',
                          style: const TextStyle(
                              color: kText, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${weatherVerdictText(r.verdict, english: _en)}\n'
                          '${_summary(r)}',
                          style: const TextStyle(color: kTextSec, height: 1.35),
                        ),
                        isThreeLine: true,
                        onTap: () => _open(r),
                      ),
                    );
                  },
                ),
    );
  }
}
