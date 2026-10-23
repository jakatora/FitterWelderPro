// Rejestr przyrządów i kalibracji: po terminie na górze, „skalibrowane
// dziś” jednym dotknięciem, eksport CSV/PDF, przypomnienia 30 i 7 dni przed
// terminem.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../database/instrument_dao.dart';
import '../../domain/instruments/instrument.dart';
import '../../domain/qualification/qualification_dates.dart';
import '../../i18n/app_language.dart';
import '../../services/instrument_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import 'instrument_edit_page.dart';
import '../../widgets/local_record_scope.dart';

Color _statusColor(InstrumentStatus s) => switch (s) {
      InstrumentStatus.ok => kPass,
      InstrumentStatus.dueSoon => kWarn,
      InstrumentStatus.overdue => kFail,
      InstrumentStatus.unknown => kTextMut,
    };

/// v34: rejestr należy do konta — po zmianie konta lista startuje od nowa.
class InstrumentRegisterPage extends StatelessWidget {
  final InstrumentDao? dao;

  /// Do testów — „dziś”.
  final DateTime Function()? clock;

  const InstrumentRegisterPage({super.key, this.dao, this.clock});

  @override
  Widget build(BuildContext context) => LocalRecordScope(
      builder: (_, session) => _InstrumentRegister(
          dao: dao ?? InstrumentDao(captureOwner: session.captureOwner),
          clock: clock));
}

class _InstrumentRegister extends StatefulWidget {
  final InstrumentDao dao;
  final DateTime Function()? clock;

  const _InstrumentRegister({required this.dao, this.clock});

  @override
  State<_InstrumentRegister> createState() => _InstrumentRegisterPageState();
}

class _InstrumentRegisterPageState extends State<_InstrumentRegister> {
  late final InstrumentDao _dao = widget.dao;
  List<Instrument> _all = const [];
  bool _loading = true;
  bool _failed = false;
  bool _onlyDue = false;
  bool _remindersOn = false;

  DateTime get _today => dateOnly((widget.clock ?? DateTime.now)());

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var failed = false;
    List<Instrument> all = const [];
    var reminders = false;
    try {
      all = await _dao.listAll();
      reminders = await instrumentReminders.isEnabled();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _all = all;
      _failed = failed;
      _remindersOn = reminders;
      _loading = false;
    });
  }

  Future<void> _afterChange() async {
    await _load();
    if (!mounted) return;
    unawaited(rescheduleInstrumentReminders(_all,
        english: context.language == AppLanguage.en));
  }

  Future<void> _edit([Instrument? i]) async {
    final saved = await Navigator.of(context).push<Instrument>(
        MaterialPageRoute(builder: (_) => InstrumentEditPage(instrument: i)));
    if (saved == null) return;
    await _dao.save(saved);
    await _afterChange();
  }

  Future<void> _calibratedToday(Instrument i) async {
    await _dao.save(i.calibratedOn(_today));
    Haptic.saved();
    await _afterChange();
    if (!mounted) return;
    final due = i.calibratedOn(_today).dueDate;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(
          pl: 'Zapisano kalibrację z dziś. Następna: ${due == null ? '—' : formatIsoDate(due)}.',
          en: 'Calibration saved for today. Next: ${due == null ? '—' : formatIsoDate(due)}.')),
    ));
  }

  Future<void> _delete(Instrument i) async {
    await _dao.softDelete(i.id);
    await _afterChange();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
            context.tr(pl: 'Usunięto przyrząd.', en: 'Instrument removed.')),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () async {
            await _dao.restore(i.id);
            await _afterChange();
          },
        ),
      ));
  }

  Future<void> _toggleReminders(bool on) async {
    final en = context.language == AppLanguage.en;
    if (on) {
      final ok = await instrumentReminders.enable(
          planInstrumentReminders(_all, now: DateTime.now(), english: en));
      if (!mounted) return;
      setState(() => _remindersOn = ok);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.tr(
                pl: 'Bez zgody na powiadomienia przypomnienia nie zadziałają.',
                en: 'Reminders need notification permission.'))));
      }
    } else {
      await instrumentReminders.disable();
      if (mounted) setState(() => _remindersOn = false);
    }
  }

  Future<void> _export(String kind) async {
    try {
      if (kind == 'csv') {
        await InstrumentExport.shareCsv(_all);
      } else {
        await InstrumentExport.sharePdf(_all);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się wyeksportować.', en: 'Export failed.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final today = _today;
    final sorted = sortForRegister(_all, today);
    final overdue = sorted
        .where((i) => i.statusOn(today) == InstrumentStatus.overdue)
        .length;
    final soon = sorted
        .where((i) => i.statusOn(today) == InstrumentStatus.dueSoon)
        .length;
    final visible = _onlyDue
        ? sorted
            .where((i) =>
                i.statusOn(today) == InstrumentStatus.overdue ||
                i.statusOn(today) == InstrumentStatus.dueSoon)
            .toList()
        : sorted;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Przyrządy i kalibracja', en: 'Instruments & calibration')),
        actions: [
          PopupMenuButton<String>(
            tooltip: context.tr(pl: 'Eksport', en: 'Export'),
            icon: const Icon(Icons.ios_share),
            onSelected: _export,
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'csv',
                  child:
                      Text(context.tr(pl: 'CSV (Excel)', en: 'CSV (Excel)'))),
              PopupMenuItem(
                  value: 'pdf',
                  child:
                      Text(context.tr(pl: 'PDF rejestru', en: 'Register PDF'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('instrument-add'),
        backgroundColor: kArc,
        foregroundColor: kOnArc,
        onPressed: _loading || _failed ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(context.tr(pl: 'Dodaj przyrząd', en: 'Add instrument'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (_failed)
                  Text(
                      context.tr(
                          pl: 'Nie udało się odczytać rejestru.',
                          en: 'Could not read the register.'),
                      style: const TextStyle(color: kFail)),
                Text(
                  context.tr(
                    pl: 'Spawarki (walidacja), manometry do prób, termometry, '
                        'mierniki, analizatory O₂, klucze dynamometryczne — '
                        'z terminami kalibracji. ISO 3834 wymaga, żeby były pod kontrolą.',
                    en: 'Welders (validation), test gauges, thermometers, meters, '
                        'O₂ analysers, torque wrenches — with calibration due dates. '
                        'ISO 3834 requires them to be under control.',
                  ),
                  style: const TextStyle(
                      fontSize: 12.5, color: kTextSec, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (_all.isNotEmpty)
                  Row(
                    children: [
                      _Count(
                          color: kFail,
                          value: overdue,
                          label: context.tr(pl: 'po terminie', en: 'overdue')),
                      const SizedBox(width: 8),
                      _Count(
                          color: kWarn,
                          value: soon,
                          label: context.tr(pl: '≤ 30 dni', en: '≤ 30 days')),
                      const Spacer(),
                      FilterChip(
                        key: const ValueKey('instrument-only-due'),
                        label: Text(
                            context.tr(pl: 'Tylko pilne', en: 'Urgent only')),
                        selected: _onlyDue,
                        onSelected: (v) => setState(() => _onlyDue = v),
                      ),
                    ],
                  ),
                if (instrumentReminders.supported && _all.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _remindersOn,
                    onChanged: (v) => unawaited(_toggleReminders(v)),
                    title: Text(context.tr(
                        pl: 'Przypomnienia 30 i 7 dni przed terminem',
                        en: 'Reminders 30 and 7 days before due')),
                  )
                else if (!kIsWeb &&
                    !instrumentReminders.supported &&
                    _all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        context.tr(
                            pl: 'Przypomnienia działają na telefonie (Android/iOS).',
                            en: 'Reminders work on the phone (Android/iOS).'),
                        style: const TextStyle(fontSize: 12, color: kTextMut)),
                  ),
                const SizedBox(height: 8),
                if (_all.isEmpty && !_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      context.tr(
                          pl: 'Rejestr jest pusty. Dodaj pierwszy przyrząd — np. manometr do prób ciśnieniowych.',
                          en: 'The register is empty. Add your first instrument — e.g. a pressure-test gauge.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kTextSec),
                    ),
                  ),
                for (final i in visible)
                  _InstrumentCard(
                    key: ValueKey('instrument-${i.id}'),
                    instrument: i,
                    today: today,
                    en: en,
                    onEdit: () => _edit(i),
                    onCalibrated: () => _calibratedToday(i),
                    onDelete: () => _delete(i),
                  ),
              ],
            ),
    );
  }
}

class _Count extends StatelessWidget {
  final Color color;
  final int value;
  final String label;
  const _Count({required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: value > 0 ? 0.15 : 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$value $label',
            style: TextStyle(
                color: value > 0 ? color : kTextMut,
                fontWeight: FontWeight.w800,
                fontSize: 12.5)),
      );
}

class _InstrumentCard extends StatelessWidget {
  final Instrument instrument;
  final DateTime today;
  final bool en;
  final VoidCallback onEdit;
  final VoidCallback onCalibrated;
  final VoidCallback onDelete;

  const _InstrumentCard({
    super.key,
    required this.instrument,
    required this.today,
    required this.en,
    required this.onEdit,
    required this.onCalibrated,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final i = instrument;
    final status = i.statusOn(today);
    final color = _statusColor(status);
    final due = i.dueDate;
    final days = i.daysLeft(today) ?? 0;
    final dueText = due == null
        ? context.tr(pl: 'brak terminu', en: 'no due date')
        : switch (status) {
            InstrumentStatus.overdue => context.tr(
                pl: 'po terminie ${-days} dni (${formatIsoDate(due)})',
                en: 'overdue by ${-days} days (${formatIsoDate(due)})'),
            _ => context.tr(
                pl: 'termin ${formatIsoDate(due)} · za $days dni',
                en: 'due ${formatIsoDate(due)} · in $days days'),
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: status == InstrumentStatus.overdue
                  ? kFail.withValues(alpha: 0.6)
                  : kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 44,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.displayName(en: en),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                        [
                          en ? i.kind.labelEn : i.kind.labelPl,
                          if (i.location.trim().isNotEmpty) i.location.trim(),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: kTextSec),
                      ),
                      const SizedBox(height: 2),
                      Text(dueText,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: color,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: context.tr(pl: 'Więcej', en: 'More'),
                  onSelected: (v) => switch (v) {
                    'cal' => onCalibrated(),
                    'del' => onDelete(),
                    _ => onEdit(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'cal',
                        child: Text(context.tr(
                            pl: 'Skalibrowane dziś', en: 'Calibrated today'))),
                    PopupMenuItem(
                        value: 'edit',
                        child: Text(context.tr(pl: 'Edytuj', en: 'Edit'))),
                    PopupMenuItem(
                        value: 'del',
                        child: Text(context.tr(pl: 'Usuń', en: 'Delete'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
