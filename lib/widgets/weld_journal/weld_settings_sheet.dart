/// Journal settings of one project: the PDF header (company, client, project
/// title, document number, revision) and the RT/UT target % from the project
/// specification (empty by default — the app never assumes one).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/weld_journal_dao.dart';
import '../../domain/weld_journal/weld_journal_settings.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

/// Opens the settings of [projectName]; returns true when saved.
Future<bool?> showWeldProjectSettingsSheet(
  BuildContext context, {
  required String projectName,
  WeldJournalSettingsDao? dao,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettingsSheet(
        projectName: projectName,
        dao: dao ?? WeldJournalSettingsDao(),
      ),
    );

class _SettingsSheet extends StatefulWidget {
  final String projectName;
  final WeldJournalSettingsDao dao;
  const _SettingsSheet({required this.projectName, required this.dao});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  final _company = TextEditingController();
  final _client = TextEditingController();
  final _title = TextEditingController();
  final _docNo = TextEditingController();
  final _rev = TextEditingController();
  final _target = TextEditingController();
  WeldJournalProjectSettings? _loaded;
  bool _loading = true;
  bool _saving = false;
  String? _targetError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    WeldJournalProjectSettings? s;
    try {
      s = await widget.dao.forProject(widget.projectName);
    } catch (e) {
      debugPrint('[weld_journal] settings load failed: $e');
    }
    if (!mounted) return;
    final v = s ?? WeldJournalProjectSettings.empty(widget.projectName);
    setState(() {
      _loaded = v;
      _company.text = v.company;
      _client.text = v.client;
      _title.text = v.projectTitle;
      _docNo.text = v.documentNo;
      _rev.text = v.revision;
      final t = v.volumetricTargetPct;
      _target.text = t == null
          ? ''
          : (t == t.roundToDouble() ? t.toStringAsFixed(0) : '$t');
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_company, _client, _title, _docNo, _rev, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _target.text.trim();
    final target = parseTargetPct(raw);
    if (raw.isNotEmpty && target == null) {
      setState(() => _targetError =
          context.tr(pl: 'Liczba 0–100', en: 'A number 0–100'));
      return;
    }
    setState(() {
      _targetError = null;
      _saving = true;
    });
    final s = (_loaded ?? WeldJournalProjectSettings.empty(widget.projectName))
        .copyWith(
      company: _company.text.trim(),
      client: _client.text.trim(),
      projectTitle: _title.text.trim(),
      documentNo: _docNo.text.trim(),
      revision: _rev.text.trim(),
      volumetricTargetPct: target,
    );
    try {
      await widget.dao.save(s);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[weld_journal] settings save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie udało się zapisać ustawień.',
            en: 'Failed to save the settings.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: kArc)),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr(
                          pl: 'Ustawienia dziennika — ${widget.projectName}',
                          en: 'Journal settings — ${widget.projectName}'),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                          pl: 'Trafiają do nagłówka PDF dziennika tego projektu.',
                          en: 'Printed in the header of this project\'s '
                              'journal PDF.'),
                      style: const TextStyle(fontSize: 12, color: kTextMut),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _company,
                      decoration: InputDecoration(
                          labelText: context.tr(
                              pl: 'Firma (wykonawca)',
                              en: 'Company (contractor)')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _client,
                      decoration: InputDecoration(
                          labelText: context.tr(pl: 'Klient', en: 'Client')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _title,
                      decoration: InputDecoration(
                        labelText: context.tr(
                            pl: 'Projekt (pełna nazwa)',
                            en: 'Project (full title)'),
                        hintText: widget.projectName,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _docNo,
                          decoration: InputDecoration(
                              labelText: context.tr(
                                  pl: 'Nr dokumentu', en: 'Document no.')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _rev,
                          decoration: InputDecoration(
                              labelText:
                                  context.tr(pl: 'Rewizja', en: 'Revision')),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _target,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,%]')),
                      ],
                      decoration: InputDecoration(
                        labelText: context.tr(
                            pl: 'Docelowy % badań RT/UT',
                            en: 'Target % of RT/UT examination'),
                        helperText: context.tr(
                            pl: 'Ze specyfikacji projektu. Puste = brak celu.',
                            en: 'From the project specification. Empty = no '
                                'target.'),
                        errorText: _targetError,
                        suffixText: '%',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(kMinTapTarget)),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(context.tr(pl: 'Zapisz', en: 'Save')),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
