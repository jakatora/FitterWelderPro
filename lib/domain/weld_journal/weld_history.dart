/// Change history of the weld journal — who changed what, when, from what
/// to what.
///
/// ISO 3834-2 §14 and every client QA plan treat the weld log as a quality
/// record: an entry may be corrected, but the correction has to be
/// traceable. Before this, an edit overwrote the row in place and a delete
/// removed it for good. Now every write goes through the DAO, which stores
/// what [diffWeldEntries] reports, stamped with the welder identity of the
/// phone.
///
/// Pure Dart: no Flutter, no I/O.
library;

import 'weld_entry.dart';
import 'weld_ndt.dart';

/// Kinds of history rows.
abstract final class WeldHistoryAction {
  static const String create = 'CREATE';
  static const String update = 'UPDATE';

  /// Status changed through the explicit, confirmed status action.
  static const String status = 'STATUS';
  static const String delete = 'DELETE';
  static const String restore = 'RESTORE';
  static const String repair = 'REPAIR';
}

/// One field that differs between two versions of a weld.
class WeldChange {
  final String field;
  final String oldValue;
  final String newValue;
  const WeldChange(this.field, this.oldValue, this.newValue);

  @override
  String toString() => '$field: "$oldValue" → "$newValue"';
}

/// Fields of [after] that differ from [before], in [weldAuditFieldKeys]
/// order. Internal ids and the delete marker are not compared — see
/// [WeldEntry.auditFields].
List<WeldChange> diffWeldEntries(WeldEntry before, WeldEntry after) {
  final a = before.auditFields();
  final b = after.auditFields();
  return [
    for (final key in weldAuditFieldKeys)
      if ((a[key] ?? '') != (b[key] ?? ''))
        WeldChange(key, a[key] ?? '', b[key] ?? ''),
  ];
}

/// One row of `weld_journal_history`.
class WeldHistoryEntry {
  final String id;
  final String weldId;

  /// Epoch milliseconds.
  final int at;

  /// Welder stamp from the phone's welder identity; empty when none is set.
  final String byStamp;

  /// [WeldHistoryAction] value.
  final String action;

  /// Field key (column name) for field-level rows, empty for whole-record
  /// actions (create / delete / restore).
  final String field;
  final String oldValue;
  final String newValue;

  const WeldHistoryEntry({
    required this.id,
    required this.weldId,
    required this.at,
    required this.byStamp,
    required this.action,
    this.field = '',
    this.oldValue = '',
    this.newValue = '',
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'weld_id': weldId,
        'at': at,
        'by_stamp': byStamp,
        'action': action,
        'field': field,
        'old_value': oldValue,
        'new_value': newValue,
      };

  static WeldHistoryEntry fromRow(Map<String, Object?> r) => WeldHistoryEntry(
        id: r['id'] as String,
        weldId: (r['weld_id'] as String?) ?? '',
        at: (r['at'] as num?)?.toInt() ?? 0,
        byStamp: (r['by_stamp'] as String?) ?? '',
        action: (r['action'] as String?) ?? '',
        field: (r['field'] as String?) ?? '',
        oldValue: (r['old_value'] as String?) ?? '',
        newValue: (r['new_value'] as String?) ?? '',
      );
}

/// `2026-09-24 14:05` in local time, for the history list and the PDF.
String formatHistoryTime(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

const Map<String, (String, String)> _labels = {
  'weld_no': ('Numer spoiny', 'Weld number'),
  'project_name': ('Projekt', 'Project'),
  'pipe_name': ('Linia', 'Line'),
  'iso_drawing': ('Nr ISO / rysunku', 'ISO / drawing no.'),
  'iso_rev': ('Rewizja', 'Revision'),
  'spool': ('Spool', 'Spool'),
  'test_package': ('Pakiet testowy', 'Test package'),
  'joint_type': ('Typ złącza', 'Joint type'),
  'shop_field': ('Warsztat / montaż', 'Shop / field'),
  'position': ('Pozycja', 'Position'),
  'material': ('Materiał', 'Material'),
  'od': ('OD (mm)', 'OD (mm)'),
  't': ('t (mm)', 't (mm)'),
  'heat_no1': ('Nr wytopu 1', 'Heat no. 1'),
  'heat_no2': ('Nr wytopu 2', 'Heat no. 2'),
  'method': ('Proces', 'Process'),
  'weld_type': ('Typ spawania', 'Weld type'),
  'wps_ref': ('WPS', 'WPS'),
  'filler_class': ('Spoiwo — klasyfikacja', 'Filler classification'),
  'filler_batch': ('Spoiwo — partia', 'Filler batch'),
  'welder': ('Spawacz', 'Welder'),
  'root_welder': ('Stempel graniówki', 'Root welder stamp'),
  'cap_welder': ('Stempel lica', 'Cap welder stamp'),
  'fitter': ('Monter', 'Fitter'),
  'date': ('Data', 'Date'),
  'preheat_c': ('Podgrzanie (°C)', 'Preheat (°C)'),
  'interpass_c': ('Międzyściegowa (°C)', 'Interpass (°C)'),
  'heat_input': ('Energia liniowa (kJ/mm)', 'Heat input (kJ/mm)'),
  'coupon_ref': ('Kupon próbny', 'Test coupon'),
  'status': ('Status', 'Status'),
  'exam': ('Uwagi z badań', 'Examination remarks'),
  'pwht_required': ('PWHT wymagane', 'PWHT required'),
  'pwht_chart': ('PWHT — nr wykresu', 'PWHT chart no.'),
  'hardness': ('Twardość', 'Hardness'),
  'inspector': ('Odbiór — inspektor', 'Accepted by (inspector)'),
  'inspected_at': ('Odbiór — data', 'Acceptance date'),
  'notes': ('Uwagi', 'Notes'),
};

const Map<String, (String, String)> _ndtFieldLabels = {
  'scope': ('zakres', 'scope'),
  'result': ('wynik', 'result'),
  'report': ('nr raportu', 'report no.'),
  'date': ('data', 'date'),
};

/// Human label of a history field key.
String weldFieldLabel(String field, {required bool en}) {
  final fixed = _labels[field];
  if (fixed != null) return en ? fixed.$2 : fixed.$1;
  final m = RegExp(r'^ndt_([a-z]+)_([a-z]+)$').firstMatch(field);
  if (m != null) {
    final method = NdtMethod.values
        .where((x) => x.name == m.group(1))
        .map((x) => x.code)
        .firstOrNull;
    final part = _ndtFieldLabels[m.group(2)];
    if (method != null && part != null) {
      return '$method — ${en ? part.$2 : part.$1}';
    }
  }
  return field;
}

/// Stored value of [field] as shown in the history list.
String weldFieldDisplayValue(String field, String value, {required bool en}) {
  if (value.isEmpty) return '—';
  if (field == 'pwht_required') {
    return value == '1' ? (en ? 'yes' : 'tak') : (en ? 'no' : 'nie');
  }
  if (field.startsWith('ndt_') && field.endsWith('_scope')) {
    return switch (value) {
      NdtScope.required => en ? 'required' : 'wymagane',
      NdtScope.selected => en ? 'selected (random)' : 'wybrane (losowo)',
      NdtScope.progressive =>
        en ? 'additional §341.3.4' : 'dodatkowe §341.3.4',
      _ => value,
    };
  }
  return value;
}

/// Label of a history action.
String weldHistoryActionLabel(String action, {required bool en}) =>
    switch (action) {
      WeldHistoryAction.create => en ? 'Created' : 'Utworzono',
      WeldHistoryAction.update => en ? 'Edited' : 'Edycja',
      WeldHistoryAction.status => en ? 'Status change' : 'Zmiana statusu',
      WeldHistoryAction.delete => en ? 'Deleted' : 'Usunięto',
      WeldHistoryAction.restore => en ? 'Restored' : 'Przywrócono',
      WeldHistoryAction.repair => en ? 'Repair' : 'Naprawa',
      _ => action,
    };
