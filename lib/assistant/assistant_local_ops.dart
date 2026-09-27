// Operacje lokalne asystenta — czyste funkcje, bez bazy i bez sieci:
//   • `query_my_params`: filtrowanie „Moich parametrów" (tabela weld_params)
//     według kryteriów z polecenia — tylko odczyt;
//   • `add_weld_journal_entry`: szkic wpisu do dziennika spoin → [WeldEntry]
//     (zapis robi ekran przez WeldJournalDao dopiero po „Zapisz").

import '../domain/weld_journal/weld_dates.dart';
import '../domain/weld_journal/weld_entry.dart';
import '../i18n/app_language.dart';
import '../models/weld_param.dart';
import 'assistant_validator.dart';

// ── Moje parametry ──────────────────────────────────────────────────────────

/// Tolerancje porównania: ścianka ±0,05 mm, średnica ±0,5 mm, elektroda
/// ±0,05 mm (ułamki z rozpoznawania mowy i zaokrąglenia z formularza).
const double _wallTol = 0.05;
const double _diameterTol = 0.5;
const double _electrodeTol = 0.05;

/// Metody z tabeli weld_params pasujące do procesu z polecenia.
Set<String> _methodsFor(String process, bool? filler) => switch (process) {
      'TIG' => filler == null
          ? const {'TIG_WIRE', 'TIG_AUTOGEN'}
          : (filler ? const {'TIG_WIRE'} : const {'TIG_AUTOGEN'}),
      'MIG_MAG' => const {'MAG', 'MIG', 'MIG_MAG'},
      'MMA' => const {'MMA'},
      _ => const {'OTHER'},
    };

/// Zapisane parametry pasujące do [criteria] (materiał, proces, drut,
/// ścianka, średnica, elektroda), najnowsze pierwsze, najwyżej [limit].
List<WeldParam> findMyWeldParams(
  List<WeldParam> all,
  Map<String, Object> criteria, {
  int limit = 20,
}) {
  final material = criteria['material'] as String?;
  final process = criteria['process'] as String?;
  final filler = criteria['filler'] as bool?;
  final wall = (criteria['wall_mm'] as num?)?.toDouble();
  final diameter = (criteria['diameter_mm'] as num?)?.toDouble();
  final electrode = (criteria['electrode_mm'] as num?)?.toDouble();
  final methods = process == null ? null : _methodsFor(process, filler);

  final out = all.where((p) {
    if (material != null && p.baseMaterial != material) return false;
    if (methods != null && !methods.contains(p.method)) return false;
    if (process == null && filler != null) {
      // „z drutem" bez metody: TIG z drutem, MAG, MMA; „bez drutu": TIG bez.
      final hasFiller = p.method != 'TIG_AUTOGEN';
      if (hasFiller != filler) return false;
    }
    if (wall != null && (p.wallThicknessMm - wall).abs() > _wallTol) {
      return false;
    }
    if (diameter != null && (p.diameterMm - diameter).abs() > _diameterTol) {
      return false;
    }
    if (electrode != null && (p.electrodeMm - electrode).abs() > _electrodeTol) {
      return false;
    }
    return true;
  }).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return out.length <= limit ? out : out.sublist(0, limit);
}

String _methodLabel(String method, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  return switch (method) {
    'TIG_WIRE' => en ? 'TIG with filler' : 'TIG z drutem',
    'TIG_AUTOGEN' => en ? 'TIG no filler' : 'TIG bez drutu',
    'MAG' || 'MIG' || 'MIG_MAG' => 'MIG/MAG',
    'MMA' => 'MMA',
    _ => method,
  };
}

/// Jedna linia wyniku: „TIG bez drutu · SS · t 2 mm · Ø 60,3 · 60 A".
String myWeldParamLine(WeldParam p, AppLanguage lang) {
  String n(double v) => assistantNumber(v, lang);
  return [
    _methodLabel(p.method, lang),
    p.baseMaterial,
    't ${n(p.wallThicknessMm)} mm',
    if (p.diameterMm > 0) 'Ø ${n(p.diameterMm)}',
    '${n(p.amps)} A',
    if (p.torchGasLpm > 0) '${n(p.torchGasLpm)} l/min',
    if (p.purgeLpm > 0)
      '${lang == AppLanguage.en ? 'purge' : 'formowanie'} ${n(p.purgeLpm)} l/min',
  ].join(' · ');
}

/// Opis kryteriów do nagłówka wyniku: „SS · TIG · z drutem · t 2 mm".
String describeMyParamsQuery(Map<String, Object> c, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  String n(Object v) => assistantNumber((v as num).toDouble(), lang);
  final parts = <String>[
    if (c['material'] != null) c['material'] as String,
    if (c['process'] != null)
      (c['process'] == 'MIG_MAG' ? 'MIG/MAG' : c['process'] as String),
    if (c['filler'] == true) en ? 'with filler' : 'z drutem',
    if (c['filler'] == false) en ? 'no filler' : 'bez drutu',
    if (c['wall_mm'] != null) 't ${n(c['wall_mm']!)} mm',
    if (c['diameter_mm'] != null) 'Ø ${n(c['diameter_mm']!)}',
    if (c['electrode_mm'] != null)
      '${en ? 'electrode' : 'elektroda'} ${n(c['electrode_mm']!)} mm',
  ];
  return parts.isEmpty ? (en ? 'all' : 'wszystkie') : parts.join(' · ');
}

// ── Dziennik spoin ──────────────────────────────────────────────────────────

/// Czy numer [weldNo] jest już zajęty w projekcie [project] (także przez
/// wpis usunięty — jak w dzienniku: numer w projekcie jest jeden).
bool isWeldNoTaken(Iterable<WeldEntry> journal,
    {required String project, required String weldNo}) {
  final p = project.trim().toLowerCase();
  final n = weldNo.trim().toUpperCase();
  return journal.any((e) =>
      e.projectName.trim().toLowerCase() == p &&
      e.weldNo.trim().toUpperCase() == n);
}

/// Nazwa projektu z dziennika o tej samej nazwie (inna wielkość liter) —
/// żeby „blok 4" nie rozszczepił projektu „Blok 4" na dwa.
String canonicalJournalProject(Iterable<WeldEntry> journal, String project) {
  final p = project.trim();
  for (final e in journal) {
    if (e.projectName.trim().toLowerCase() == p.toLowerCase()) {
      return e.projectName.trim();
    }
  }
  return p;
}

/// Notatka źródłowa wpisu: „Asystent (głosowo), 2026-09-25 14:03".
String journalSourceNote(
    {required DateTime at, required bool byVoice, required AppLanguage lang}) {
  final en = lang == AppLanguage.en;
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${isoDate(at)} ${two(at.hour)}:${two(at.minute)}';
  final source = byVoice
      ? (en ? 'Assistant (by voice)' : 'Asystent (głosowo)')
      : (en ? 'Assistant (text)' : 'Asystent (tekst)');
  return '$source, $stamp';
}

/// Rekord dziennika ze szkicu. Spawacz = stempel z tożsamości spawacza w
/// telefonie (nie z polecenia), status „do badania" (PENDING), data dzisiaj.
/// Pozostałe pola puste — nic nie jest zgadywane.
WeldEntry buildAssistantWeldEntry(
  WeldJournalDraft draft, {
  required String id,
  required String stamp,
  required DateTime at,
  required bool byVoice,
  required AppLanguage lang,
  String? projectId,
}) {
  return WeldEntry(
    id: id,
    weldNo: draft.weldNo,
    projectName: draft.project,
    projectId: projectId,
    pipeName: '',
    material: '',
    od: '',
    t: '',
    method: '',
    welder: stamp.trim(),
    date: isoDate(at),
    notes: journalSourceNote(at: at, byVoice: byVoice, lang: lang),
    status: WeldStatus.pending,
    wpsRef: draft.wps ?? '',
  );
}
