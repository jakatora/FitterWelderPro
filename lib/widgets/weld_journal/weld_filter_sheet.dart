/// Filters of the weld journal beyond the status chips: project, line / ISO,
/// welder, date range, NDT state and the deleted-entries view. Whatever is
/// set here is exactly what the CSV/PDF export gets.
library;

import 'package:flutter/material.dart';
import 'journal_session_view.dart';

import '../../domain/weld_journal/weld_dates.dart';
import '../../domain/weld_journal/weld_filter.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import 'wj_ui.dart';

Future<WeldJournalFilter?> showWeldFilterSheet(
  BuildContext context, {
  required WeldJournalFilter filter,
  required List<String> projects,
  required List<String> welders,
}) =>
    showJournalModalBottomSheet<WeldJournalFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WeldFilterSheet(
          filter: filter, projects: projects, welders: welders),
    );

class _WeldFilterSheet extends StatefulWidget {
  final WeldJournalFilter filter;
  final List<String> projects;
  final List<String> welders;
  const _WeldFilterSheet({
    required this.filter,
    required this.projects,
    required this.welders,
  });

  @override
  State<_WeldFilterSheet> createState() => _WeldFilterSheetState();
}

class _WeldFilterSheetState extends State<_WeldFilterSheet> {
  late String _project = widget.filter.project;
  late String _welder = widget.filter.welder;
  late String _from = widget.filter.dateFrom;
  late String _to = widget.filter.dateTo;
  late WeldNdtFilter _ndt = widget.filter.ndt;
  late bool _deleted = widget.filter.deleted;
  late final TextEditingController _line =
      TextEditingController(text: widget.filter.line);

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final current = DateTime.tryParse(from ? _from : _to);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() => from ? _from = isoDate(picked) : _to = isoDate(picked));
  }

  WeldJournalFilter _result() => widget.filter.copyWith(
        project: _project,
        line: _line.text.trim(),
        welder: _welder,
        dateFrom: _from,
        dateTo: _to,
        ndt: _ndt,
        deleted: _deleted,
      );

  @override
  Widget build(BuildContext context) {
    final en = AppLanguageController.isEnglish;
    final any = context.tr(pl: 'dowolny', en: 'any');
    final projects = {
      ...widget.projects,
      if (_project.isNotEmpty) _project,
    }.toList();
    final welders = {
      ...widget.welders,
      if (_welder.isNotEmpty) _welder,
    }.toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(pl: 'Filtry dziennika', en: 'Journal filters'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: kText),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  pl: 'Eksport CSV/PDF obejmuje dokładnie spoiny widoczne po '
                      'filtrowaniu.',
                  en: 'The CSV/PDF export contains exactly the welds shown '
                      'after filtering.',
                ),
                style: const TextStyle(fontSize: 12, color: kTextMut),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _project,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: context.tr(pl: 'Projekt', en: 'Project')),
                items: [
                  DropdownMenuItem(value: '', child: Text(any)),
                  for (final p in projects)
                    DropdownMenuItem(
                        value: p,
                        child: Text(p, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _project = v ?? ''),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _line,
                decoration: InputDecoration(
                  labelText:
                      context.tr(pl: 'Linia / nr ISO', en: 'Line / ISO no.'),
                  hintText: context.tr(
                      pl: 'fragment, np. L-12 albo 0042',
                      en: 'part of it, e.g. L-12 or 0042'),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _welder,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Spawacz (stempel)', en: 'Welder (stamp)')),
                items: [
                  DropdownMenuItem(value: '', child: Text(any)),
                  for (final w in welders)
                    DropdownMenuItem(value: w, child: Text(w)),
                ],
                onChanged: (v) => setState(() => _welder = v ?? ''),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _DateButton(
                    label: context.tr(pl: 'Od', en: 'From'),
                    value: _from,
                    onPick: () => _pickDate(true),
                    onClear: () => setState(() => _from = ''),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateButton(
                    label: context.tr(pl: 'Do', en: 'To'),
                    value: _to,
                    onPick: () => _pickDate(false),
                    onClear: () => setState(() => _to = ''),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<WeldNdtFilter>(
                initialValue: _ndt,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'NDT'),
                items: [
                  for (final f in WeldNdtFilter.values)
                    DropdownMenuItem(
                        value: f, child: Text(weldNdtFilterLabel(f, en: en))),
                ],
                onChanged: (v) =>
                    setState(() => _ndt = v ?? WeldNdtFilter.all),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _deleted,
                onChanged: (v) => setState(() => _deleted = v),
                title: Text(context.tr(
                    pl: 'Pokaż usunięte wpisy',
                    en: 'Show deleted entries')),
                subtitle: Text(
                  context.tr(
                      pl: 'Usunięte spoiny zostają w dzienniku — tu można je '
                          'przywrócić.',
                      en: 'Deleted welds stay in the journal — restore them '
                          'here.'),
                  style: const TextStyle(fontSize: 12, color: kTextMut),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(kMinTapTarget)),
                    onPressed: () => Navigator.pop(
                        context, WeldJournalFilter(status: widget.filter.status)),
                    child: Text(context.tr(pl: 'Wyczyść', en: 'Clear')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(kMinTapTarget)),
                    onPressed: () => Navigator.pop(context, _result()),
                    child: Text(context.tr(pl: 'Pokaż', en: 'Apply')),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: WjChoiceChip(
              label: value.isEmpty ? label : '$label: $value',
              selected: value.isNotEmpty,
              icon: Icons.calendar_month_outlined,
              onTap: onPick,
            ),
          ),
          if (value.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: context.tr(pl: 'Wyczyść datę', en: 'Clear date'),
              onPressed: onClear,
            ),
        ],
      );
}
