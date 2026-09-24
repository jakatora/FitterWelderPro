/// Change history of one weld — shown on the weld card (editor) and in its
/// own sheet from the list.
library;

import 'package:flutter/material.dart';

import '../../database/weld_journal_dao.dart';
import '../../domain/weld_journal/weld_history.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

/// Plain list of [entries], newest first as the DAO returns them.
class WeldHistoryList extends StatelessWidget {
  final List<WeldHistoryEntry> entries;
  const WeldHistoryList({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final en = AppLanguageController.isEnglish;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          context.tr(
            pl: 'Brak zapisanych zmian. Wpisy sprzed tej wersji aplikacji '
                'nie mają historii.',
            en: 'No recorded changes. Entries made before this app version '
                'have no history.',
          ),
          style: const TextStyle(fontSize: 12, color: kTextMut),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in entries)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatHistoryTime(h.at)} · '
                  '${h.byStamp.isEmpty ? '—' : h.byStamp} · '
                  '${weldHistoryActionLabel(h.action, en: en)}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kTextSec),
                ),
                const SizedBox(height: 2),
                Text(
                  _body(h, en),
                  style: const TextStyle(fontSize: 12, color: kText),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _body(WeldHistoryEntry h, bool en) {
    if (h.field.isEmpty) {
      final v = h.newValue.isNotEmpty ? h.newValue : h.oldValue;
      return v.isEmpty ? '' : v;
    }
    if (h.field == 'repair') return h.newValue;
    final label = weldFieldLabel(h.field, en: en);
    final from = weldFieldDisplayValue(h.field, h.oldValue, en: en);
    final to = weldFieldDisplayValue(h.field, h.newValue, en: en);
    return '$label: $from → $to';
  }
}

/// Bottom sheet with the history of weld [weldId].
Future<void> showWeldHistorySheet(
  BuildContext context, {
  required String weldId,
  required String weldNo,
  WeldJournalDao? dao,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ctx.tr(
                      pl: 'Historia zmian — $weldNo',
                      en: 'Change history — $weldNo'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kText),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: FutureBuilder<List<WeldHistoryEntry>>(
                    future: (dao ?? WeldJournalDao()).history(weldId),
                    builder: (_, snap) {
                      if (snap.hasError) {
                        return Text(
                          ctx.tr(
                              pl: 'Nie udało się wczytać historii.',
                              en: 'Failed to load the history.'),
                          style: const TextStyle(color: kFail),
                        );
                      }
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: CircularProgressIndicator(color: kArc)),
                        );
                      }
                      return SingleChildScrollView(
                        child: WeldHistoryList(entries: snap.data!),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ctx.tr(pl: 'Zamknij', en: 'Close')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
