/// Bottom sheet offering the projects a weld can be filed under.
///
/// Two sources, merged and de-duplicated:
///   * [ProjectDao] — projects created on the cut-list side of the app
///     (picking one also links the weld by `project_id`);
///   * the names already used in this journal — a welder is often documenting
///     a job that exists only on the drawing, and once he has typed it on the
///     first joint the other twenty-nine should come from a list.
///
/// It never offers a "new project" action: creating a project belongs to the
/// project screen, and typing a fresh name straight into the field behind this
/// sheet already works.
library;

import 'package:flutter/material.dart';
import 'journal_session_view.dart';

import '../../database/project_dao.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

/// A picked project: its name and, for a project from the app, its id.
class WeldProjectPick {
  final String name;
  final String? id;
  const WeldProjectPick(this.name, this.id);
}

Future<WeldProjectPick?> showWeldProjectPicker(
  BuildContext context, {
  required List<String> journalProjects,
  required String current,
}) =>
    showJournalModalBottomSheet<WeldProjectPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProjectPickerSheet(
        journalProjects: journalProjects,
        current: current,
      ),
    );

class _ProjectPickerSheet extends StatefulWidget {
  final List<String> journalProjects;
  final String current;

  const _ProjectPickerSheet({
    required this.journalProjects,
    required this.current,
  });

  @override
  State<_ProjectPickerSheet> createState() => _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends State<_ProjectPickerSheet> {
  List<({String name, String id})> _appProjects = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await ProjectDao().listAll();
      if (!mounted) return;
      setState(() {
        _appProjects = [
          for (final p in projects)
            if ((p.name ?? '').trim().isNotEmpty)
              (name: p.name!.trim(), id: p.id),
        ];
        _loading = false;
      });
    } catch (e) {
      // Degrade, don't empty: the journal half of the list needs no database
      // and is the half a welder reaches for most.
      debugPrint('[weld_journal] project list failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Merged list, de-duplicated case-insensitively and sorted by name. App
  /// projects are added first so they win a duplicate — and bring their id.
  List<({String name, String? id})> get _entries {
    final seen = <String>{};
    final out = <({String name, String? id})>[];
    for (final p in _appProjects) {
      if (seen.add(p.name.toLowerCase())) out.add((name: p.name, id: p.id));
    }
    for (final n in widget.journalProjects) {
      if (seen.add(n.toLowerCase())) out.add((name: n, id: null));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(pl: 'Wybierz projekt', en: 'Pick a project'),
              style: const TextStyle(
                  color: kArc, fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                pl: 'Projekty z aplikacji i nazwy już użyte w dzienniku. Nazwę '
                    'spoza listy nadal wpiszesz ręcznie w polu "Projekt".',
                en: 'Projects from the app plus names already used in the '
                    'journal. A name that is not here can still be typed into '
                    'the "Project" field by hand.',
              ),
              style:
                  const TextStyle(color: kTextMut, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator(color: kArc)),
              )
            else if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  context.tr(
                    pl: 'Brak projektów. Wpisz nazwę w polu "Projekt" — '
                        'pojawi się tu przy następnej spoinie.',
                    en: 'No projects yet. Type a name into the "Project" '
                        'field — it will show up here on the next weld.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kTextMut, fontSize: 13),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final it = entries[i];
                    final selected =
                        it.name.toLowerCase() == widget.current.toLowerCase();
                    return InkWell(
                      onTap: () => Navigator.pop(
                          context, WeldProjectPick(it.name, it.id)),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        constraints:
                            const BoxConstraints(minHeight: kMinTapTarget),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? kArc.withValues(alpha: 0.12) : kBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: selected ? kArc : kBorder,
                              width: selected ? 1.5 : 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              it.id != null
                                  ? Icons.folder_outlined
                                  : Icons.history,
                              size: 18,
                              color: selected ? kArc : kTextMut,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    it.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: selected ? kArc : kText,
                                    ),
                                  ),
                                  Text(
                                    it.id != null
                                        ? context.tr(
                                            pl: 'projekt w aplikacji',
                                            en: 'project in the app')
                                        : context.tr(
                                            pl: 'użyty w dzienniku',
                                            en: 'used in the journal'),
                                    style: const TextStyle(
                                        fontSize: 11, color: kTextMut),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check, size: 18, color: kArc),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'),
                  style: const TextStyle(color: kTextSec)),
            ),
          ],
        ),
      ),
    );
  }
}
