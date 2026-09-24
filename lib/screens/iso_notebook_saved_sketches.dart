part of 'iso_notebook_screen.dart';

// ─── "Zapisane szkice" — list / open / delete stored ISO sketches ────────────
//
// Every sketch the notebook autosaves is a row in `iso_drawings`. "Nowy
// szkic" keeps the previous one there, so the fitter needs a way back to it —
// and a way to throw away the ones they no longer want, deliberately and
// with a confirmation (autosave itself never deletes anything with content).

/// `2026-09-24 14:05`, local time.
String _formatSketchTime(int millis) {
  String two(int v) => v.toString().padLeft(2, '0');
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

class _SavedSketchesSheet extends StatefulWidget {
  final List<IsoDrawingSummary> entries;
  final String currentId;
  final String Function(String pl, String en) tr;

  /// Deletes the stored sketch; the sheet removes it from its list once the
  /// future completes.
  final Future<void> Function(String id) onDelete;

  const _SavedSketchesSheet({
    required this.entries,
    required this.currentId,
    required this.tr,
    required this.onDelete,
  });

  @override
  State<_SavedSketchesSheet> createState() => _SavedSketchesSheetState();
}

class _SavedSketchesSheetState extends State<_SavedSketchesSheet> {
  late final List<IsoDrawingSummary> _entries = List.of(widget.entries);

  Future<void> _delete(IsoDrawingSummary e) async {
    final tr = widget.tr;
    final label = e.name.isEmpty ? tr('bez nazwy', 'untitled') : e.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr('Usunąć szkic?', 'Delete sketch?')),
        content: Text(tr(
          'Szkic „$label” zostanie usunięty z telefonu. Tego nie da się cofnąć.',
          'Sketch “$label” will be deleted from the phone. This cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(tr('Anuluj', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(
              tr('Usuń', 'Delete'),
              style: TextStyle(color: Theme.of(dctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.onDelete(e.id);
    } catch (err) {
      debugPrint('ISO notebook: deleting sketch ${e.id} failed: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Nie udało się usunąć szkicu.',
            'Could not delete the sketch.')),
      ));
      return;
    }
    if (!mounted) return;
    setState(() => _entries.removeWhere((x) => x.id == e.id));
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr('Zapisane szkice', 'Saved sketches'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  tr('Nie ma jeszcze zapisanych szkiców.',
                      'No saved sketches yet.'),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    final current = e.id == widget.currentId;
                    final when = _formatSketchTime(e.updatedAt);
                    return ListTile(
                      leading: Icon(
                        current ? Icons.edit_note : Icons.description_outlined,
                        color: current ? cs.primary : cs.onSurfaceVariant,
                      ),
                      title: Text(
                        e.name.isEmpty ? tr('Bez nazwy', 'Untitled') : e.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(current
                          ? tr('$when · otwarty teraz', '$when · open now')
                          : when),
                      trailing: IconButton(
                        tooltip: tr('Usuń szkic', 'Delete sketch'),
                        icon: Icon(Icons.delete_outline, color: cs.error),
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: () => _delete(e),
                      ),
                      onTap: () => Navigator.pop(context, e.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
