// Deterministyczny walidator propozycji asystenta (spec §2 pkt 3–5, §6).
//
// Każda propozycja — z parsera lokalnego i z modelu na serwerze — przechodzi
// przez TEN walidator, zanim użytkownik zobaczy podsumowanie. Model nie ma
// uchwytu do bazy: w najlepszym razie dostaje się tu mapa pól, a stąd wychodzi
// tylko szkic ([WeldParamDraft]) albo odmowa. Zapis robi dopiero ekran po
// jawnym „Zapisz".

import '../i18n/app_language.dart';
import '../models/weld_param.dart';
import 'assistant_intents.dart';

enum AssistantRejectReason {
  /// Intencji nie ma na liście [kAssistantIntents].
  unknownIntent,

  /// Pole spoza listy danej intencji (np. `sql`, `id`).
  extraField,

  /// Zły typ: tekst zamiast liczby, 0 zamiast true/false, NaN, nieskończoność.
  wrongType,

  /// Liczba poza [kAssistantRanges] albo puste / za długie zapytanie.
  outOfRange,

  /// Tekst spoza słownika (materiał, proces, pozycja, gaz, złącze).
  notAllowed,

  /// Wartości wzajemnie sprzeczne (MIG/MAG albo MMA „bez drutu").
  inconsistent,
}

sealed class AssistantCheck {
  const AssistantCheck();
}

/// Kompletny, poprawny zapis parametru — do pokazania w podsumowaniu.
class AssistantReadyToSave extends AssistantCheck {
  final WeldParamDraft draft;
  const AssistantReadyToSave(this.draft);
}

/// Poprawne polecenie otwarcia narzędzia (sama nawigacja, bez zapisu).
class AssistantReadyToOpen extends AssistantCheck {
  final String query;
  const AssistantReadyToOpen(this.query);
}

/// Brakuje istotnego pola — asystent zadaje o nie JEDNO pytanie.
/// Pytanie wiedzowe — do trybu „Odpowiedz" (nic nie zapisuje).
class AssistantReadyToAnswer extends AssistantCheck {
  final String text;
  const AssistantReadyToAnswer(this.text);
}

/// Odczyt „Moich parametrów" według kryteriów (offline, nic nie zapisuje).
class AssistantReadyToQuery extends AssistantCheck {
  /// Kryteria: pola z [kAssistantIntents] dla `query_my_params` (bez nulli).
  final Map<String, Object> criteria;
  const AssistantReadyToQuery(this.criteria);
}

/// Kompletny wpis do dziennika spoin — do pokazania w podsumowaniu.
class AssistantReadyToJournal extends AssistantCheck {
  final WeldJournalDraft draft;
  const AssistantReadyToJournal(this.draft);
}

class AssistantNeedsField extends AssistantCheck {
  final String intent;
  final String field;
  const AssistantNeedsField(this.intent, this.field);
}

class AssistantRejected extends AssistantCheck {
  final AssistantRejectReason reason;

  /// Pole, którego dotyczy odmowa (null dla nieznanej intencji).
  final String? field;
  const AssistantRejected(this.reason, [this.field]);
}

/// Sprawdza typy, słowniki, zakresy i spójność — bez wymogu kompletności.
/// `null` znaczy „nic do zarzucenia". Pola z wartością `null` traktuje jak brak.
AssistantRejected? findAssistantRejection(
    String intent, Map<String, Object?> fields) {
  final spec = kAssistantIntents[intent];
  if (spec == null) return const AssistantRejected(AssistantRejectReason.unknownIntent);
  final allowed = spec.allFields;
  for (final entry in fields.entries) {
    final key = entry.key;
    final value = entry.value;
    if (!allowed.contains(key)) {
      return AssistantRejected(AssistantRejectReason.extraField, key);
    }
    if (value == null) continue;
    final problem = _checkValue(key, value);
    if (problem != null) return AssistantRejected(problem, key);
  }
  if (intent == kIntentSaveWeldParameter) {
    final process = fields['process'];
    if ((process == 'MIG_MAG' || process == 'MMA') && fields['filler'] == false) {
      return const AssistantRejected(AssistantRejectReason.inconsistent, 'filler');
    }
  }
  return null;
}

AssistantRejectReason? _checkValue(String key, Object value) {
  switch (key) {
    case 'query':
      if (value is! String) return AssistantRejectReason.wrongType;
      final q = value.trim();
      if (q.isEmpty || q.length > kAssistantMaxQueryLength) {
        return AssistantRejectReason.outOfRange;
      }
      return null;
    case 'weld_no':
    case 'project':
    case 'wps':
    case 'text':
      if (value is! String) return AssistantRejectReason.wrongType;
      final t = value.trim();
      if (t.isEmpty ||
          t.length > kAssistantTextLimits[key]! ||
          RegExp('[\u0000-\u001f\u007f-\u009f\u2028\u2029]').hasMatch(t)) {
        return AssistantRejectReason.outOfRange;
      }
      return null;
    case 'filler':
      return value is bool ? null : AssistantRejectReason.wrongType;
    case 'material':
      return _checkEnum(value, kAssistantMaterials);
    case 'process':
      return _checkEnum(value, kAssistantProcesses);
    case 'position':
      return _checkEnum(value, kAssistantPositions);
    case 'gas':
      return _checkEnum(value, kAssistantGases);
    case 'joint':
      return _checkEnum(value, kAssistantJoints);
  }
  final range = kAssistantRanges[key];
  if (range != null) {
    if (value is! num || !value.isFinite) return AssistantRejectReason.wrongType;
    return range.contains(value.toDouble())
        ? null
        : AssistantRejectReason.outOfRange;
  }
  // Pole jest na liście intencji, ale walidator go nie zna — to błąd
  // programisty; bezpieczniej odrzucić niż przepuścić.
  return AssistantRejectReason.extraField;
}

AssistantRejectReason? _checkEnum(Object value, Set<String> allowed) {
  if (value is! String) return AssistantRejectReason.wrongType;
  return allowed.contains(value) ? null : AssistantRejectReason.notAllowed;
}

/// Pełna walidacja: odrzucenie, brakujące pole albo gotowy szkic.
AssistantCheck validateAssistantProposal(
    String intent, Map<String, Object?> fields) {
  final rejection = findAssistantRejection(intent, fields);
  if (rejection != null) return rejection;

  final present = <String, Object>{
    for (final e in fields.entries)
      if (e.value != null) e.key: e.value!,
  };

  if (intent == kIntentOpenTool) {
    final q = present['query'];
    if (q == null) return const AssistantNeedsField(kIntentOpenTool, 'query');
    return AssistantReadyToOpen((q as String).trim());
  }

  if (intent == kIntentAnswerQuestion) {
    final t = present['text'];
    if (t == null) return const AssistantNeedsField(kIntentAnswerQuestion, 'text');
    return AssistantReadyToAnswer((t as String).trim());
  }

  if (intent == kIntentQueryMyParams) {
    return AssistantReadyToQuery(Map.unmodifiable(present));
  }

  if (intent == kIntentAddWeldJournalEntry) {
    for (final field in kJournalRequiredOrder) {
      if (!present.containsKey(field)) {
        return AssistantNeedsField(kIntentAddWeldJournalEntry, field);
      }
    }
    return AssistantReadyToJournal(WeldJournalDraft(
      weldNo: (present['weld_no'] as String).trim(),
      project: (present['project'] as String).trim(),
      wps: (present['wps'] as String?)?.trim(),
    ));
  }

  // save_weld_parameter
  final process = present['process'];
  if ((process == 'MIG_MAG' || process == 'MMA') && !present.containsKey('filler')) {
    // Drut (MIG/MAG) i elektroda (MMA) SĄ spoiwem — nie ma czego dopytywać.
    present['filler'] = true;
  }
  for (final field in kSaveWeldRequiredOrder) {
    if (!present.containsKey(field)) {
      return AssistantNeedsField(kIntentSaveWeldParameter, field);
    }
  }
  double? d(String k) => (present[k] as num?)?.toDouble();
  return AssistantReadyToSave(WeldParamDraft(
    material: present['material'] as String,
    process: present['process'] as String,
    filler: present['filler'] as bool,
    wallMm: d('wall_mm')!,
    currentA: d('current_a')!,
    diameterMm: d('diameter_mm'),
    position: present['position'] as String?,
    gas: present['gas'] as String?,
    flowLpm: d('flow_lpm'),
    electrodeMm: d('electrode_mm'),
    joint: present['joint'] as String?,
    purgeLpm: d('purge_lpm'),
  ));
}

/// Jedno krótkie pytanie o brakujące pole.
String assistantQuestionFor(String field, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  switch (field) {
    case 'material':
      return en
          ? 'What material: stainless, carbon steel, duplex or aluminium?'
          : 'Jaki materiał: nierdzewka, stal czarna, duplex czy aluminium?';
    case 'process':
      return en ? 'Which process: TIG, MIG/MAG or stick?' : 'Jaka metoda: TIG, MIG/MAG czy elektroda?';
    case 'filler':
      return en ? 'With filler or without?' : 'Z drutem czy bez drutu?';
    case 'wall_mm':
      return en ? 'What wall thickness, in mm?' : 'Jaka grubość ścianki w mm?';
    case 'current_a':
      return en ? 'What current, in amps?' : 'Jaki prąd w amperach?';
    case 'query':
      return en ? 'Which tool should I open?' : 'Które narzędzie otworzyć?';
    case 'weld_no':
      return en ? 'What is the weld number?' : 'Jaki numer spoiny?';
    case 'project':
      return en ? 'Which project?' : 'Do którego projektu?';
    case 'wps':
      return en ? 'Which WPS?' : 'Jaki WPS?';
  }
  return en ? 'What is the $field?' : 'Podaj: $field?';
}

// ── Szkic zapisu ─────────────────────────────────────────────────────────────

/// Zwalidowany parametr spawania — jeszcze NIE zapisany. Ekran podsumowania
/// pokazuje dokładnie te wartości, a [toWeldParam] robi z nich rekord dopiero
/// po „Zapisz".
class WeldParamDraft {
  final String material;
  final String process;
  final bool filler;
  final double wallMm;
  final double currentA;
  final double? diameterMm;
  final String? position;
  final String? gas;
  final double? flowLpm;
  final double? electrodeMm;
  final String? joint;

  /// Przepływ gazu formującego (l/min) — kolumna `purge_lpm`.
  final double? purgeLpm;

  const WeldParamDraft({
    required this.material,
    required this.process,
    required this.filler,
    required this.wallMm,
    required this.currentA,
    this.diameterMm,
    this.position,
    this.gas,
    this.flowLpm,
    this.electrodeMm,
    this.joint,
    this.purgeLpm,
  });

  WeldParamDraft copyWith({String? process, bool? filler, String? material}) =>
      WeldParamDraft(
        material: material ?? this.material,
        process: process ?? this.process,
        filler: filler ?? this.filler,
        wallMm: wallMm,
        currentA: currentA,
        diameterMm: diameterMm,
        position: position,
        gas: gas,
        flowLpm: flowLpm,
        electrodeMm: electrodeMm,
        joint: joint,
        purgeLpm: purgeLpm,
      );

  /// Wartość `method` w tabeli `weld_params` (ta sama, której używa zakładka
  /// „Moje" w „Parametry — rury": TIG_WIRE / TIG_AUTOGEN / MAG).
  String get dbMethod => switch (process) {
        'TIG' => filler ? 'TIG_WIRE' : 'TIG_AUTOGEN',
        'MIG_MAG' => 'MAG',
        'MMA' => 'MMA',
        _ => 'OTHER',
      };

  /// Notatka źródłowa: skąd rekord i kiedy, plus pola, dla których tabela
  /// nie ma kolumn (pozycja, gaz, złącze).
  String sourceNote({
    required DateTime at,
    required bool byVoice,
    required AppLanguage lang,
  }) {
    final en = lang == AppLanguage.en;
    final stamp = '${at.year.toString().padLeft(4, '0')}-${_two(at.month)}-'
        '${_two(at.day)} ${_two(at.hour)}:${_two(at.minute)}';
    final source = byVoice
        ? (en ? 'By voice (assistant)' : 'Głosowo')
        : (en ? 'Assistant (text)' : 'Asystent (tekst)');
    final parts = <String>['$source, $stamp'];
    if (position != null) parts.add(en ? 'position $position' : 'pozycja $position');
    if (gas != null) parts.add('${en ? 'gas' : 'gaz'}: ${assistantGasLabel(gas!, lang)}');
    if (joint != null) {
      parts.add('${en ? 'joint' : 'złącze'}: ${assistantJointLabel(joint!, lang)}');
    }
    if (diameterMm == null) {
      parts.add(en ? 'diameter not given' : 'średnica nie podana');
    }
    return parts.join('; ');
  }

  /// Rekord do `WeldParamDao.insert`. Kolumny NOT NULL bez wartości z
  /// polecenia dostają 0 (= „nie podano"), jak w ręcznym formularzu po
  /// wyczyszczeniu pola.
  WeldParam toWeldParam({
    required String id,
    required DateTime at,
    required bool byVoice,
    required AppLanguage lang,
  }) {
    final ms = at.millisecondsSinceEpoch;
    return WeldParam(
      id: id,
      method: dbMethod,
      baseMaterial: material,
      welderModel: null,
      diameterMm: diameterMm ?? 0,
      wallThicknessMm: wallMm,
      electrodeMm: electrodeMm ?? 0,
      torchGasLpm: flowLpm ?? 0,
      nozzleType: null,
      nozzleSize: null,
      purgeLpm: purgeLpm ?? 0,
      amps: currentA,
      outletHoles: null,
      tempo: null,
      note: sourceNote(at: at, byVoice: byVoice, lang: lang),
      createdAt: ms,
      updatedAt: ms,
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Zwalidowany wpis do dziennika spoin — jeszcze NIE zapisany. Spawacz
/// (stempel) i data nie pochodzą z polecenia: dokłada je ekran z tożsamości
/// spawacza w telefonie i zegara.
class WeldJournalDraft {
  final String weldNo;
  final String project;
  final String? wps;

  const WeldJournalDraft({
    required this.weldNo,
    required this.project,
    this.wps,
  });
}

// ── Etykiety do podsumowania ────────────────────────────────────────────────

String assistantMaterialLabel(String code, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  return switch (code) {
    'SS' => en ? 'Stainless steel (SS)' : 'Stal nierdzewna (SS)',
    'CS' => en ? 'Carbon steel (CS)' : 'Stal czarna / węglowa (CS)',
    'DUPLEX' => 'Duplex',
    'AL' => en ? 'Aluminium' : 'Aluminium',
    _ => en ? 'Other' : 'Inny',
  };
}

String assistantProcessLabel(String code, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  return switch (code) {
    'TIG' => 'TIG (141)',
    'MIG_MAG' => 'MIG/MAG (13x)',
    'MMA' => en ? 'Stick / MMA (111)' : 'Elektroda otulona (111)',
    _ => en ? 'Other' : 'Inna',
  };
}

String assistantGasLabel(String code, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  return switch (code) {
    'AR' => 'argon',
    'M21' => 'M21 (Ar + CO₂)',
    'CO2' => 'CO₂',
    'AR_HE' => en ? 'argon + helium' : 'argon + hel',
    'AR_H2' => en ? 'argon + hydrogen' : 'argon + wodór',
    'N2' => en ? 'nitrogen' : 'azot',
    _ => en ? 'other' : 'inny',
  };
}

String assistantJointLabel(String code, AppLanguage lang) {
  final en = lang == AppLanguage.en;
  return switch (code) {
    'BUTT' => en ? 'butt' : 'doczołowe',
    'FILLET' => en ? 'fillet' : 'pachwinowe',
    'SOCKET' => en ? 'socket' : 'kielichowe (mufa)',
    'BRANCH' => en ? 'branch' : 'odgałęzienie',
    _ => en ? 'other' : 'inne',
  };
}

/// Liczba bez zbędnych zer, z przecinkiem po polsku: 2 → „2", 2.5 → „2,5".
String assistantNumber(double v, AppLanguage lang) {
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return lang == AppLanguage.en ? s : s.replaceAll('.', ',');
}
