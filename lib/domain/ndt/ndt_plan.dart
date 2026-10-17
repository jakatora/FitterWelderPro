/// Plan badań NDT z dziennika spoin: ile spoin trzeba zbadać (losowy % na
/// spawacza i linię), które zlecić i czy linia jest gotowa do próby
/// ciśnieniowej.
///
/// ## Wymagania
/// Zestaw reguł ([NdtRule]) wpisuje użytkownik albo wybiera preset. Reguła:
/// metoda (VT/PT/MT/RT/UT), procent 0–100, zakres (rodzaj spoiny BW / FW /
/// SW / BR, opcjonalnie materiał — „zawiera", bez wielkości liter i spacji)
/// i podział: osobno na każdego spawacza i/lub osobno na każdą linię. Bez
/// podziału na linię partią jest projekt. Projekty nigdy się nie łączą.
///
/// ASME B31.3 §341.4.1 (Normal Fluid Service) to minimum kodu, sprawdzone w
/// tekście wydań 2014, 2020 i 2024: (b)(1) co najmniej 5 % spoin obwodowych
/// doczołowych i „miter" w każdej wyznaczonej partii badanych w całości
/// losowo RT (§344.5) albo UT (§344.6), a w próbce praca każdego spawacza,
/// którego spoiny są w partii; (a) oględziny — w wydaniach 2020 i 2024
/// 100 % ukończonych spoin ((a)(3), poza elementami wg norm z listy) i 5 %
/// wykonania ((a)(2)); w starszych (2014) 5 % wykonania z pracą każdego
/// spawacza i 100 % spoin wzdłużnych. Specyfikacja projektu zwykle wymaga
/// więcej (10 / 20 / 100 % RT, PT/MT dla spoin pachwinowych i mufowych);
/// kategoria M — 20 % (M341.4). Aplikacja niczego nie zakłada ponad to, co
/// wpisano w regułach.
///
/// ## Grupa = reguła × projekt × [linia] × [spawacz]
/// * spoiny — nieusunięte wpisy, do których reguła się stosuje;
/// * wymagane = ⌈n · p⌉ w liczbach całkowitych, zawsze W GÓRĘ (5 % z 1
///   spoiny = 1, z 20 = 1, z 21 = 2);
/// * zbadane — spoiny z wynikiem (OK albo NOK) tą metodą. Badania dodatkowe
///   §341.3.4 (zakres „dod.") NIE liczą się do podstawowego % — chyba że
///   reguła wymaga 100 %;
/// * zlecone — zakres ustawiony, wyniku brak (także naprawiona spoina, która
///   czeka na ponowne badanie: naprawa zostawia zakres i czyści wynik);
/// * dodatkowe (§341.3.4) — z weld_stats ([computeWeldJournalStats],
///   [WeldGroupStats.toExamineBy]) na partii spawacza: wszystkie jego spoiny
///   w projekcie (gdy któraś reguła tej metody nie dzieli na linie) albo na
///   linii — wszystkie rodzaje spoin, bo odrzucenie poza zakresem reguły też
///   wymaga dobadania. Które spoiny wziąć — decyduje inspektor (jak w
///   weld_stats nic nie jest wybierane automatycznie);
/// * spoina z dwoma spawaczami (grań / lico) jest w grupie KAŻDEGO z nich i
///   jej badanie liczy się obu — tak jak w weld_stats (radiogram pokazuje
///   pracę obu), a odrzucenie daje §341.3.4 obu.
///
/// ## Gotowość linii do próby ciśnieniowej
/// „Gotowa" tylko wtedy, gdy nic nie blokuje ([NdtBlocker]): reguły są i są
/// nieuszkodzone, każda spoina linii ma spawacza, rodzaj (gdy reguła go
/// rozróżnia) i materiał (gdy reguła go rozróżnia), linia ma nazwę, nie ma
/// odrzuconych spoin bez naprawy ani napraw czekających na badanie, żadne
/// zlecone badanie nie czeka na wynik, każda grupa obejmująca spoiny linii
/// jest kompletna i nie ma zaległych badań dodatkowych §341.3.4. Brak danych
/// nigdy nie jest „OK".
///
/// ## Propozycja spoin do badania losowego
/// Deterministyczna i powtarzalna: kolejność kandydatów to skrót FNV-1a z
/// (projekt, linia, spawacz, metoda, runda) i id spoiny — te same dane dają
/// tę samą listę, nowa spoina nie przetasowuje pozostałych, „losuj ponownie"
/// zmienia rundę. Najpierw spoiny bez żadnego badania innymi metodami
/// (poza VT), potem pozostałe, na końcu spoiny odrzucone. Spoina wybrana
/// dla jednego spawacza, a wspólna z drugim, liczy się też drugiemu.
///
/// Czysty Dart: bez Fluttera i I/O.
library;

import 'dart:convert';

import '../progress/progress_report.dart' show weldsCount;
import '../weld_journal/weld_dates.dart' show isoDate;
import '../weld_journal/weld_entry.dart';
import '../weld_journal/weld_ndt.dart';
import '../weld_journal/weld_numbering.dart' show compareWeldNos;
import '../weld_journal/weld_stats.dart';

/// 100 % w setnych częściach procenta.
const int kNdtFullBp = 10000;

/// Wersja zapisu reguł (JSON).
const int kNdtRulesVersion = 1;

/// Wymagana liczba badań z [welds] spoin przy [bp] (setne części %),
/// zawsze w górę: ⌈welds · bp / 10000⌉, w liczbach całkowitych — bez błędów
/// zaokrągleń liczb zmiennoprzecinkowych.
int ndtRequiredCount(int welds, int bp) {
  if (welds <= 0 || bp <= 0) return 0;
  final b = bp > kNdtFullBp ? kNdtFullBp : bp;
  return (welds * b + kNdtFullBp - 1) ~/ kNdtFullBp;
}

/// Procent (0–100) na setne części procenta; null dla pustego, NaN,
/// nieskończoności i wartości spoza 0–100 — reguła z takim procentem nie
/// może istnieć.
int? ndtBpFromPct(double? pct) {
  if (pct == null || !pct.isFinite || pct < 0 || pct > 100) return null;
  return (pct * 100).round();
}

/// Rodzaj spoiny z dziennika jako kod [WeldJointType] albo null, gdy pusty
/// lub nieznany.
String? ndtJointOf(WeldEntry e) {
  final j = e.jointType.trim().toUpperCase();
  return WeldJointType.values.contains(j) ? j : null;
}

/// Rodzaje w kolejności [WeldJointType.values], bez powtórzeń i nieznanych.
List<String> ndtJoints(Iterable<String> joints) {
  final set = {for (final j in joints) j.trim().toUpperCase()};
  return [
    for (final j in WeldJointType.values)
      if (set.contains(j)) j
  ];
}

String _norm(String s) => s.replaceAll(RegExp(r'\s'), '').toLowerCase();
String _key(String s) => s.trim().toLowerCase();

// ─── Reguły ───────────────────────────────────────────────────────────────

class NdtRule {
  final String id;
  final NdtMethod method;

  /// Procent w setnych częściach (5 % = 500, 100 % = [kNdtFullBp]).
  final int bp;

  /// Kody [WeldJointType], do których reguła się stosuje.
  final List<String> joints;

  /// Materiał — spoina musi go zawierać („316" ⊂ „316L"); pusty = każdy.
  final String material;

  /// Każdy spawacz osobno (praca każdego spawacza reprezentowana).
  final bool perWelder;

  /// Każda linia osobno; inaczej partią jest projekt.
  final bool perLine;

  const NdtRule({
    required this.id,
    required this.method,
    required this.bp,
    required this.joints,
    this.material = '',
    this.perWelder = true,
    this.perLine = true,
  });

  double get pct => bp / 100;
  bool get isFull => bp >= kNdtFullBp;
  bool get coversAllJoints => WeldJointType.values.every(joints.contains);
  bool get hasMaterial => material.trim().isNotEmpty;

  /// Reguła, z której da się liczyć: procent 0–100, co najmniej jeden znany
  /// rodzaj spoiny, id.
  bool get isValid =>
      id.trim().isNotEmpty &&
      bp >= 0 &&
      bp <= kNdtFullBp &&
      joints.isNotEmpty &&
      joints.every(WeldJointType.values.contains);

  int requiredFor(int welds) => ndtRequiredCount(welds, bp);

  NdtRule copyWith({
    String? id,
    NdtMethod? method,
    int? bp,
    List<String>? joints,
    String? material,
    bool? perWelder,
    bool? perLine,
  }) =>
      NdtRule(
        id: id ?? this.id,
        method: method ?? this.method,
        bp: bp ?? this.bp,
        joints: joints ?? this.joints,
        material: material ?? this.material,
        perWelder: perWelder ?? this.perWelder,
        perLine: perLine ?? this.perLine,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'method': method.code,
        'pct': bp / 100,
        'joints': joints,
        if (hasMaterial) 'material': material.trim(),
        'perWelder': perWelder,
        'perLine': perLine,
      };

  /// Reguła z JSON albo null, gdy którekolwiek pole jest złego typu albo
  /// spoza zakresu. Brak flag podziału = podział (więcej grup, więcej badań —
  /// bezpieczniej niż mniej).
  static NdtRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final m = json['method'];
    final pct = json['pct'];
    final joints = json['joints'];
    final material = json['material'];
    final perWelder = json['perWelder'];
    final perLine = json['perLine'];
    if (id is! String || id.trim().isEmpty) return null;
    if (m is! String) return null;
    final method = NdtMethod.values
        .where((x) => x.code == m.trim().toUpperCase())
        .firstOrNull;
    if (method == null) return null;
    if (pct is! num) return null;
    final bp = ndtBpFromPct(pct.toDouble());
    if (bp == null) return null;
    if (joints is! List || joints.isEmpty) return null;
    if (joints.any(
        (j) => j is! String || !WeldJointType.values.contains(j))) {
      return null;
    }
    if (material != null && material is! String) return null;
    if (perWelder != null && perWelder is! bool) return null;
    if (perLine != null && perLine is! bool) return null;
    return NdtRule(
      id: id.trim(),
      method: method,
      bp: bp,
      joints: ndtJoints(joints.cast<String>()),
      material: (material as String?)?.trim() ?? '',
      perWelder: (perWelder as bool?) ?? true,
      perLine: (perLine as bool?) ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NdtRule &&
      other.id == id &&
      other.method == method &&
      other.bp == bp &&
      other.joints.join(',') == joints.join(',') &&
      other.material == material &&
      other.perWelder == perWelder &&
      other.perLine == perLine;

  @override
  int get hashCode => Object.hash(
      id, method, bp, joints.join(','), material, perWelder, perLine);

  @override
  String toString() => 'NdtRule(${ndtRuleText(this, en: true)})';
}

/// Gotowe zestawy reguł.
abstract final class NdtPreset {
  /// ASME B31.3 Normal Fluid Service — minimum kodu.
  static const String b313 = 'b31.3-nfs';
  static const String rt100 = 'rt-100';
  static const String rt10vt100 = 'rt-10-vt-100';

  /// Reguły wpisane przez użytkownika.
  static const String custom = 'custom';

  static const List<String> values = [b313, rt100, rt10vt100, custom];
}

/// Reguły presetu (pusta lista dla „własny").
List<NdtRule> ndtPresetRules(String preset) => switch (preset) {
      NdtPreset.b313 => const [
          NdtRule(
            id: 'b313-rt',
            method: NdtMethod.rt,
            bp: 500,
            joints: [WeldJointType.butt],
            perWelder: true,
            perLine: false,
          ),
          // §341.4.1(a)(3) wydań 2020 i 2024: oględziny 100 % ukończonych
          // spoin (starsze wydania: 5 % — 100 % jest bezpieczniejsze).
          NdtRule(
            id: 'b313-vt',
            method: NdtMethod.vt,
            bp: kNdtFullBp,
            joints: WeldJointType.values,
            perWelder: false,
            perLine: true,
          ),
        ],
      NdtPreset.rt100 => const [
          NdtRule(
            id: 'rt100-rt',
            method: NdtMethod.rt,
            bp: kNdtFullBp,
            joints: [WeldJointType.butt],
            perWelder: false,
            perLine: true,
          ),
        ],
      NdtPreset.rt10vt100 => const [
          NdtRule(
            id: 'rt10-rt',
            method: NdtMethod.rt,
            bp: 1000,
            joints: [WeldJointType.butt],
            perWelder: true,
            perLine: true,
          ),
          NdtRule(
            id: 'rt10-vt',
            method: NdtMethod.vt,
            bp: kNdtFullBp,
            joints: WeldJointType.values,
            perWelder: false,
            perLine: true,
          ),
        ],
      _ => const [],
    };

/// Krótka etykieta presetu na chipie (jedna linia na wąskim telefonie).
String ndtPresetChip(String preset, {required bool en}) => switch (preset) {
      NdtPreset.b313 => 'B31.3 NFS · RT 5$_nb%',
      NdtPreset.rt100 => '100$_nb% RT',
      NdtPreset.rt10vt100 => '10$_nb% RT + 100$_nb% VT',
      _ => en ? 'Custom' : 'Własny',
    };

/// Pełna nazwa presetu.
String ndtPresetLabel(String preset, {required bool en}) => switch (preset) {
      NdtPreset.b313 => en
          ? 'ASME B31.3 normal fluid service — RT 5 % random, each welder + VT 100 %'
          : 'ASME B31.3 normal fluid service — RT 5 % losowo, każdy spawacz + VT 100 %',
      NdtPreset.rt100 => '100 % RT',
      NdtPreset.rt10vt100 => '10 % RT + 100 % VT',
      _ => en ? 'Custom' : 'Własny',
    };

/// Opis presetu: skąd liczby i czego preset NIE wie.
String ndtPresetNote(String preset, {required bool en}) => switch (preset) {
      NdtPreset.b313 => en
          ? 'ASME B31.3 §341.4.1, Normal Fluid Service — the code minimum: at '
              'least 5 % of circumferential butt (and miter) welds of each '
              'designated lot fully examined by random RT (or UT, §344.5 / '
              '§344.6), the sample including the work of each welder in the '
              'lot (§341.4.1(b)(1)); visual examination of 100 % of completed '
              'welds (§341.4.1(a)(3) in the 2020 and 2024 editions; older '
              'editions: 5 % of fabrication, each welder represented). Here the '
              'lot is the project — the inspector may designate smaller lots '
              '(then "each line"). A rejected sample = 2 more of the same welder '
              'by the same method (§341.3.4). Do not show the list to the '
              'welders before the examination. The project specification often '
              'requires more (10 / 20 / 100 % RT, PT/MT for fillet and socket '
              'welds); Category M — 20 % (M341.4). Check the specification and '
              'the code edition.'
          : 'ASME B31.3 §341.4.1, Normal Fluid Service — minimum kodu: co '
              'najmniej 5 % spoin obwodowych doczołowych (i „miter") każdej '
              'wyznaczonej partii badanych w całości losowo RT (albo UT, '
              '§344.5 / §344.6), w próbce praca każdego spawacza z partii '
              '(§341.4.1(b)(1)); oględziny 100 % ukończonych spoin '
              '(§341.4.1(a)(3) w wydaniach 2020 i 2024; starsze wydania: 5 % '
              'wykonania z pracą każdego spawacza). Partią jest tu projekt — '
              'inspektor może wyznaczyć mniejsze partie (wtedy „każda linia"). '
              'Odrzucona próbka = 2 kolejne tego spawacza tą samą metodą '
              '(§341.3.4). Nie pokazuj listy spawaczom przed badaniem. '
              'Specyfikacja projektu często wymaga więcej (10 / 20 / 100 % RT, '
              'PT/MT dla spoin pachwinowych i mufowych); kategoria M — 20 % '
              '(M341.4). Sprawdź specyfikację i wydanie normy.',
      NdtPreset.rt100 => en
          ? 'Every butt weld radiographed (e.g. a specification for severe '
              'service). Add VT and PT/MT rules if the specification requires '
              'them.'
          : 'Każda spoina doczołowa prześwietlona (np. specyfikacja dla cięższej '
              'usługi). Dodaj reguły VT i PT/MT, jeśli wymaga ich specyfikacja.',
      NdtPreset.rt10vt100 => en
          ? 'A common project specification: RT 10 % of the butt welds of each '
              'welder on each line, VT of every weld.'
          : 'Częsta specyfikacja projektu: RT 10 % spoin doczołowych każdego '
              'spawacza na każdej linii, VT każdej spoiny.',
      _ => en
          ? 'Your own rules — as in the project specification.'
          : 'Własne reguły — tak jak w specyfikacji projektu.',
    };

class NdtRuleSet {
  final String preset;
  final List<NdtRule> rules;

  const NdtRuleSet({this.preset = NdtPreset.custom, this.rules = const []});

  factory NdtRuleSet.fromPreset(String preset) =>
      NdtRuleSet(preset: preset, rules: ndtPresetRules(preset));

  bool get isEmpty => rules.isEmpty;

  String encode() => jsonEncode({
        'v': kNdtRulesVersion,
        'preset': preset,
        'rules': [for (final r in rules) r.toJson()],
      });

  @override
  bool operator ==(Object other) =>
      other is NdtRuleSet &&
      other.preset == preset &&
      other.rules.length == rules.length &&
      [for (var i = 0; i < rules.length; i++) other.rules[i] == rules[i]]
          .every((x) => x);

  @override
  int get hashCode => Object.hash(preset, Object.hashAll(rules));
}

/// Wynik odczytu zapisu reguł.
class NdtRuleSetDecode {
  final NdtRuleSet set;

  /// Zapis nienaruszony (albo go nie było).
  final bool intact;

  /// Zapis był (pusty zapis ≠ brak reguł do zastosowania presetu).
  final bool saved;

  /// Reguły odrzucone jako nieczytelne.
  final int dropped;

  const NdtRuleSetDecode(this.set,
      {this.intact = true, this.saved = true, this.dropped = 0});
}

/// Odczyt zapisu reguł. Nieczytelny JSON, zła wersja albo choć jedna
/// nieczytelna reguła → `intact == false` — wtedy plan NIE daje „gotowe"
/// (pominięta reguła mogłaby po cichu obniżyć wymagania).
NdtRuleSetDecode decodeNdtRuleSet(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const NdtRuleSetDecode(NdtRuleSet(), saved: false);
  }
  const damaged = NdtRuleSetDecode(NdtRuleSet(), intact: false);
  try {
    final d = jsonDecode(raw);
    if (d is! Map) return damaged;
    if (d['v'] != kNdtRulesVersion) return damaged;
    final list = d['rules'];
    if (list is! List) return damaged;
    final p = d['preset'];
    final preset =
        p is String && NdtPreset.values.contains(p) ? p : NdtPreset.custom;
    final rules = <NdtRule>[];
    final ids = <String>{};
    var dropped = 0;
    for (final x in list) {
      final r = NdtRule.fromJson(x);
      if (r == null || !r.isValid) {
        dropped++;
        continue;
      }
      // Powtórzone id (ręczna edycja) — reguła zostaje, id unikalne.
      var id = r.id;
      for (var i = 2; !ids.add(id); i++) {
        id = '${r.id}-$i';
      }
      rules.add(id == r.id ? r : r.copyWith(id: id));
    }
    return NdtRuleSetDecode(NdtRuleSet(preset: preset, rules: rules),
        intact: dropped == 0, dropped: dropped);
  } catch (_) {
    return damaged;
  }
}

/// Czy reguła stosuje się do spoiny.
enum NdtFit { applies, outside, unknownJoint, unknownMaterial }

/// Znane kryterium, które wyklucza spoinę → [NdtFit.outside]; brak danych do
/// rozstrzygnięcia → `unknown…` (spoina blokuje gotowość linii, nie znika).
NdtFit ndtRuleFit(NdtRule r, WeldEntry e) {
  var unknownJoint = false;
  var unknownMaterial = false;
  if (!r.coversAllJoints) {
    final j = ndtJointOf(e);
    if (j == null) {
      unknownJoint = true;
    } else if (!r.joints.contains(j)) {
      return NdtFit.outside;
    }
  }
  if (r.hasMaterial) {
    final wm = _norm(e.material);
    if (wm.isEmpty) {
      unknownMaterial = true;
    } else if (!wm.contains(_norm(r.material))) {
      return NdtFit.outside;
    }
  }
  if (unknownJoint) return NdtFit.unknownJoint;
  if (unknownMaterial) return NdtFit.unknownMaterial;
  return NdtFit.applies;
}

// ─── Stan spoiny ──────────────────────────────────────────────────────────

bool _statusNok(WeldEntry e) =>
    e.status.trim().toUpperCase() == WeldStatus.nok;

/// Spoina odrzucona i jeszcze nie naprawiona: status NOK albo wynik NOK
/// którąkolwiek metodą.
bool ndtOpenDefect(WeldEntry e) =>
    _statusNok(e) || e.ndt.values.any((n) => n.isRejected);

/// Naprawiona spoina bez ponownego badania: zlecone badanie bez wyniku albo
/// — gdy naprawa nie zostawiła żadnego zakresu badań — ani wyniku, ani
/// odbioru (status OK).
bool ndtRepairAwaiting(WeldEntry e) =>
    e.repairs.isNotEmpty &&
    !ndtOpenDefect(e) &&
    (e.ndt.values.any((n) => n.isAwaiting) ||
        (!e.ndt.values.any((n) => n.hasResult) &&
            e.status.trim().toUpperCase() != WeldStatus.ok));

/// Zlecone badanie bez wyniku na spoinie bez napraw i odrzuceń.
bool ndtAwaitingResult(WeldEntry e) =>
    !ndtOpenDefect(e) &&
    !ndtRepairAwaiting(e) &&
    e.ndt.values.any((n) => n.isAwaiting);

// ─── Skrót do wyboru deterministycznego ──────────────────────────────────

/// FNV-1a 32 bit po jednostkach UTF-16. Tylko dodawanie, mnożenie przez małe
/// liczby i reszta z dzielenia — wynik dokładny także w JavaScripcie (web),
/// bez zależności od `String.hashCode`.
int ndtSeedHash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    // h · 16777619 mod 2^32, gdzie 16777619 = 2^24 + 403.
    h = (h * 403 + (h % 256) * 16777216) % 4294967296;
  }
  return h;
}

// ─── Plan ─────────────────────────────────────────────────────────────────

enum NdtGroupStatus { complete, missing, awaiting, repairsOpen, unassigned }

class NdtGroup {
  /// Pozycja reguły w zestawie.
  final int ruleIndex;
  final NdtRule rule;

  /// Projekt w pisowni z dziennika ('' = bez projektu).
  final String project;

  /// Linia ('' = bez linii i ISO) albo null — partią jest projekt.
  final String? line;

  /// Stempel ('' = spoiny bez spawacza) albo null — wszyscy spawacze razem.
  final String? welder;

  final List<WeldEntry> welds;
  final int required;
  final int examined;

  /// Zlecone (zakres ustawiony), bez wyniku — liczą się do podstawy.
  final List<WeldEntry> ordered;

  /// Badania dodatkowe §341.3.4 zlecone, bez wyniku.
  final int awaitingExtra;

  /// Badania dodatkowe §341.3.4 jeszcze do wykonania (weld_stats).
  final int progressive;

  /// Spoiny z odrzuceniem tą metodą (albo statusem NOK) bez naprawy i
  /// naprawione, czekające na badanie tą metodą.
  final int openRepairs;

  /// Propozycja do zlecenia teraz (nowe spoiny + wybrane już dla innej grupy).
  final List<WeldEntry> proposal;

  const NdtGroup({
    required this.ruleIndex,
    required this.rule,
    required this.project,
    required this.line,
    required this.welder,
    required this.welds,
    required this.required,
    required this.examined,
    required this.ordered,
    required this.awaitingExtra,
    required this.progressive,
    required this.openRepairs,
    required this.proposal,
  });

  NdtMethod get method => rule.method;
  int get missing => required > examined ? required - examined : 0;
  int get awaiting => ordered.length;

  /// Ile nowych spoin trzeba zlecić (brakujące minus już zlecone).
  int get toOrder => missing > awaiting ? missing - awaiting : 0;

  /// Reguła dzieli na spawaczy, a spoiny nie mają stempla.
  bool get unassigned => welder != null && welder!.isEmpty;

  NdtGroupStatus get status {
    if (unassigned) return NdtGroupStatus.unassigned;
    if (openRepairs > 0) return NdtGroupStatus.repairsOpen;
    if (missing > 0 || progressive > 0) return NdtGroupStatus.missing;
    if (awaiting > 0 || awaitingExtra > 0) return NdtGroupStatus.awaiting;
    return NdtGroupStatus.complete;
  }

  bool get isComplete => status == NdtGroupStatus.complete;

  /// Stały klucz grupy (testy, klucze widżetów).
  String get key => [
        ruleIndex,
        _key(project),
        line == null ? '*' : _key(line!),
        welder == null ? '*' : _key(welder!),
      ].join('|');
}

/// Co blokuje gotowość linii. Kolejność = kolejność na ekranie.
enum NdtBlocker {
  rulesDamaged,
  noRules,
  noLine,
  unassigned,
  noJointType,
  noMaterial,
  openDefects,
  repairsAwaiting,
  awaitingResults,
  incompleteGroups,
  missing,
  progressive,
}

class NdtLine {
  final String project;

  /// Linia (pole „Rura / linia", inaczej numer ISO); '' = bez obu.
  final String line;
  final List<WeldEntry> welds;

  /// Grupy, które obejmują choć jedną spoinę tej linii.
  final List<NdtGroup> groups;

  /// Co blokuje — tylko pozycje z liczbą > 0.
  final Map<NdtBlocker, int> blockers;

  /// Spoiny, do których nie stosuje się żadna reguła (informacja).
  final int uncovered;

  /// Odrzucenia bez zakresu badania (weld_stats) — nie wiadomo, czy były
  /// losowe; nie liczą się do §341.3.4 (informacja dla inspektora).
  final int rejectsNoScope;

  /// Dodatkowe §341.3.4 do wykonania per metoda (partia spawaczy linii).
  final Map<NdtMethod, int> progressiveByMethod;

  const NdtLine({
    required this.project,
    required this.line,
    required this.welds,
    required this.groups,
    required this.blockers,
    required this.uncovered,
    required this.rejectsNoScope,
    required this.progressiveByMethod,
  });

  bool get ready => blockers.isEmpty;
  int get completeGroups => groups.where((g) => g.isComplete).length;
  int get missing => blockers[NdtBlocker.missing] ?? 0;
  int get progressive => blockers[NdtBlocker.progressive] ?? 0;
  String get key => '${_key(project)}|${_key(line)}';
}

/// Brak danych na spoinie.
enum NdtWeldIssue { noWelder, noJointType, noMaterial, noLine }

class NdtIssueWeld {
  final WeldEntry weld;
  final List<NdtWeldIssue> issues;
  const NdtIssueWeld(this.weld, this.issues);
}

/// Spoina do zlecenia (albo już zlecona) i grupa, z której wynika.
class NdtOrderItem {
  final NdtMethod method;
  final WeldEntry weld;
  final NdtGroup group;
  const NdtOrderItem(this.method, this.weld, this.group);
}

class NdtPlan {
  /// Reguły, z których liczono (tylko poprawne).
  final List<NdtRule> rules;
  final bool rulesIntact;
  final List<NdtGroup> groups;
  final List<NdtLine> lines;
  final List<NdtIssueWeld> issues;
  final int round;

  const NdtPlan({
    required this.rules,
    required this.rulesIntact,
    required this.groups,
    required this.lines,
    required this.issues,
    required this.round,
  });

  int get welds => lines.fold(0, (s, l) => s + l.welds.length);
  int get readyLines => lines.where((l) => l.ready).length;

  /// Nowe spoiny do zlecenia, metoda po metodzie (każda spoina raz).
  Map<NdtMethod, List<NdtOrderItem>> get toOrder =>
      _byMethod((g) => g.proposal);

  /// Zlecone wcześniej, bez wyniku (każda spoina raz na metodę).
  Map<NdtMethod, List<NdtOrderItem>> get ordered =>
      _byMethod((g) => g.ordered);

  int get toOrderCount =>
      toOrder.values.fold(0, (s, list) => s + list.length);

  /// Dodatkowe §341.3.4 do wykonania: grupa → liczba (grupy z > 0).
  List<NdtGroup> get progressiveGroups =>
      [for (final g in groups) if (g.progressive > 0) g];

  Map<NdtMethod, List<NdtOrderItem>> _byMethod(
      List<WeldEntry> Function(NdtGroup g) pick) {
    final out = <NdtMethod, List<NdtOrderItem>>{};
    final seen = <NdtMethod, Set<String>>{};
    for (final m in NdtMethod.values) {
      for (final g in groups) {
        if (g.method != m) continue;
        for (final w in pick(g)) {
          if (!(seen[m] ??= {}).add(w.id)) continue;
          (out[m] ??= []).add(NdtOrderItem(m, w, g));
        }
      }
    }
    return out;
  }
}

class _Acc {
  final int ruleIndex;
  final NdtRule rule;
  final String projectKey;
  final String project;
  final String? lineKey;
  final String? line;
  final String? welderKey;
  final String? welder;
  final List<WeldEntry> welds = [];
  _Acc(this.ruleIndex, this.rule, this.projectKey, this.project, this.lineKey,
      this.line, this.welderKey, this.welder);
}

/// Badanie [n] liczy się do podstawowego % reguły [r]: dodatkowe §341.3.4
/// nie, chyba że reguła wymaga 100 %.
bool _base(NdtRule r, WeldNdt n) =>
    n.scope != NdtScope.progressive || r.isFull;

/// Plan dla nieusuniętych spoin [entries] (opcjonalnie tylko projektu
/// [project] — porównanie bez wielkości liter) według [rules].
///
/// [rulesIntact] = false (uszkodzony zapis reguł) blokuje gotowość każdej
/// linii. [round] — „losuj ponownie".
NdtPlan computeNdtPlan(
  Iterable<WeldEntry> entries, {
  required List<NdtRule> rules,
  bool rulesIntact = true,
  String? project,
  int round = 0,
}) {
  final pk = project == null ? null : _key(project);
  final live = [
    for (final e in entries)
      if (!e.isDeleted && (pk == null || _key(e.projectName) == pk)) e
  ];
  final valid = [for (final r in rules) if (r.isValid) r];
  final intact = rulesIntact && valid.length == rules.length;

  // ── Dodatkowe §341.3.4 z weld_stats, na partii spawacza ──
  final lotPerLine = {
    for (final m in NdtMethod.values)
      m: valid.where((r) => r.method == m).every((r) => r.perLine),
  };
  final statsCache = <String, WeldJournalStats>{};
  WeldJournalStats lotStats(String projectKey, String? lineKey) =>
      statsCache.putIfAbsent(
        '$projectKey\u0000${lineKey ?? '\u0001'}',
        () => computeWeldJournalStats(live.where((e) =>
            _key(e.projectName) == projectKey &&
            (lineKey == null || _key(weldLineKey(e)) == lineKey))),
      );
  int progressiveFor(
      NdtMethod m, String projectKey, String? lineKey, String welderKey) {
    final stats = lotStats(projectKey, lotPerLine[m]! ? (lineKey ?? '') : null);
    final label = welderKey.isEmpty ? '—' : welderKey;
    for (final g in stats.byWelder) {
      if (g.key.toLowerCase() == label) return g.toExamineBy(m);
    }
    return 0;
  }

  List<String> welderKeys(Iterable<WeldEntry> welds) {
    final out = <String>{};
    for (final e in welds) {
      if (e.stamps.isEmpty) {
        out.add('');
      } else {
        out.addAll(e.stamps.map((s) => s.toLowerCase()));
      }
    }
    return out.toList();
  }

  // ── Grupy ──
  const any = '\u0001';
  final accs = <String, _Acc>{};
  for (var i = 0; i < valid.length; i++) {
    final r = valid[i];
    for (final e in live) {
      if (ndtRuleFit(r, e) != NdtFit.applies) continue;
      final pKey = _key(e.projectName);
      final lineName = weldLineKey(e).trim();
      final lKey = r.perLine ? _key(lineName) : null;
      final stamps = r.perWelder
          ? (e.stamps.isEmpty ? const [''] : e.stamps)
          : const <String?>[null];
      for (final w in stamps) {
        final wKey = w?.toLowerCase();
        final k = '$i|$pKey|${lKey ?? any}|${wKey ?? any}';
        accs
            .putIfAbsent(
                k,
                () => _Acc(i, r, pKey, e.projectName.trim(), lKey,
                    lKey == null ? null : lineName, wKey, w))
            .welds
            .add(e);
      }
    }
  }

  int cmpNullable(String? a, String? b, {bool emptyLast = false}) {
    if (a == b) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (emptyLast && a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
    return compareWeldNos(a, b);
  }

  final sorted = accs.values.toList()
    ..sort((a, b) {
      final p = compareWeldNos(a.project, b.project);
      if (p != 0) return p;
      final l = cmpNullable(a.line, b.line, emptyLast: true);
      if (l != 0) return l;
      final w = cmpNullable(a.welder, b.welder, emptyLast: true);
      if (w != 0) return w;
      return a.ruleIndex.compareTo(b.ruleIndex);
    });

  // ── Liczenie grup i propozycja (deterministyczna) ──
  final proposed = <NdtMethod, Set<String>>{};
  final groups = <NdtGroup>[];
  for (final a in sorted) {
    final r = a.rule;
    final m = r.method;
    final welds = [...a.welds]
      ..sort((x, y) => compareWeldNos(x.weldNo, y.weldNo));
    var examined = 0;
    var awaitingExtra = 0;
    var open = 0;
    final ordered = <WeldEntry>[];
    for (final e in welds) {
      final n = e.ndtOf(m);
      if (n.hasResult && _base(r, n)) examined++;
      if (n.isAwaiting) {
        if (_base(r, n)) {
          ordered.add(e);
        } else {
          awaitingExtra++;
        }
      }
      if (_statusNok(e) ||
          n.isRejected ||
          (e.repairs.isNotEmpty && n.isAwaiting)) {
        open++;
      }
    }
    final required = r.requiredFor(welds.length);
    final progressive = a.welderKey != null
        ? progressiveFor(m, a.projectKey, a.lineKey, a.welderKey!)
        : welderKeys(welds).fold<int>(
            0, (s, w) => s + progressiveFor(m, a.projectKey, a.lineKey, w));

    // Propozycja: brakujące minus już zlecone, z preferencją spoin nie
    // badanych innymi metodami. Spoiny bez spawacza (reguła na spawacza)
    // nie dostają propozycji — najpierw trzeba je przypisać.
    final missing = required > examined ? required - examined : 0;
    final toOrder = missing > ordered.length ? missing - ordered.length : 0;
    final unassigned = a.welderKey != null && a.welderKey!.isEmpty;
    final proposal = <WeldEntry>[];
    if (toOrder > 0 && !unassigned) {
      final taken = proposed[m] ??= <String>{};
      final covered = [
        for (final e in welds)
          if (taken.contains(e.id)) e
      ];
      proposal.addAll(covered);
      final need = toOrder - covered.length;
      if (need > 0) {
        final seed = '${a.projectKey}|${a.lineKey ?? any}|'
            '${a.welderKey ?? any}|${m.code}|$round';
        int tier(WeldEntry e) {
          if (ndtOpenDefect(e)) return 2;
          final other = e.ndt.entries.any((x) =>
              x.key != NdtMethod.vt && x.key != m && x.value.hasResult);
          return other ? 1 : 0;
        }

        final candidates = [
          for (final e in welds)
            if (!taken.contains(e.id) && e.ndtOf(m).isEmpty) e
        ]..sort((x, y) {
            final t = tier(x).compareTo(tier(y));
            if (t != 0) return t;
            final h = ndtSeedHash('$seed|${x.id}')
                .compareTo(ndtSeedHash('$seed|${y.id}'));
            if (h != 0) return h;
            return x.id.compareTo(y.id);
          });
        final picks = candidates.take(need).toList();
        taken.addAll(picks.map((e) => e.id));
        proposal.addAll(picks);
      }
    }

    groups.add(NdtGroup(
      ruleIndex: a.ruleIndex,
      rule: r,
      project: a.project,
      line: a.line,
      welder: a.welder,
      welds: List.unmodifiable(welds),
      required: required,
      examined: examined,
      ordered: List.unmodifiable(ordered),
      awaitingExtra: awaitingExtra,
      progressive: progressive,
      openRepairs: open,
      proposal: List.unmodifiable(proposal),
    ));
  }

  // ── Linie ──
  final lineWelds = <String, List<WeldEntry>>{};
  final lineNames = <String, (String, String)>{};
  for (final e in live) {
    final lineName = weldLineKey(e).trim();
    final k = '${_key(e.projectName)}\u0000${_key(lineName)}';
    (lineWelds[k] ??= []).add(e);
    lineNames.putIfAbsent(k, () => (e.projectName.trim(), lineName));
  }

  final issues = <NdtIssueWeld>[];
  final lines = <NdtLine>[];
  for (final entry in lineWelds.entries) {
    final (projectName, lineName) = lineNames[entry.key]!;
    final pKey = _key(projectName);
    final lKey = _key(lineName);
    final welds = [...entry.value]
      ..sort((x, y) => compareWeldNos(x.weldNo, y.weldNo));
    final ids = {for (final e in welds) e.id};
    final touching = [
      for (final g in groups)
        if (_key(g.project) == pKey && g.welds.any((e) => ids.contains(e.id)))
          g
    ];

    var unassigned = 0, noJoint = 0, noMaterial = 0, uncovered = 0;
    var openDefects = 0, repairsAwaiting = 0, awaitingResults = 0;
    for (final e in welds) {
      final fits = [for (final r in valid) ndtRuleFit(r, e)];
      final weldIssues = <NdtWeldIssue>[
        if (e.stamps.isEmpty) NdtWeldIssue.noWelder,
        if (fits.contains(NdtFit.unknownJoint)) NdtWeldIssue.noJointType,
        if (fits.contains(NdtFit.unknownMaterial)) NdtWeldIssue.noMaterial,
        if (lKey.isEmpty) NdtWeldIssue.noLine,
      ];
      if (weldIssues.isNotEmpty) issues.add(NdtIssueWeld(e, weldIssues));
      if (e.stamps.isEmpty) unassigned++;
      if (fits.contains(NdtFit.unknownJoint)) noJoint++;
      if (fits.contains(NdtFit.unknownMaterial)) noMaterial++;
      if (fits.isNotEmpty && fits.every((f) => f == NdtFit.outside)) {
        uncovered++;
      }
      if (ndtOpenDefect(e)) {
        openDefects++;
      } else if (ndtRepairAwaiting(e)) {
        repairsAwaiting++;
      } else if (ndtAwaitingResult(e)) {
        awaitingResults++;
      }
    }

    // §341.3.4: spawacze linii (każda metoda) i spawacze grup obejmujących
    // linię (metoda grupy) — każda para (metoda, partia, spawacz) raz.
    final progByMethod = <NdtMethod, int>{};
    final seenPairs = <String>{};
    void addProg(NdtMethod m, String welderKey) {
      final lot = lotPerLine[m]! ? lKey : any;
      if (!seenPairs.add('${m.code}|$lot|$welderKey')) return;
      final n = progressiveFor(m, pKey, lKey, welderKey);
      if (n > 0) progByMethod[m] = (progByMethod[m] ?? 0) + n;
    }

    for (final w in welderKeys(welds)) {
      for (final m in NdtMethod.values) {
        addProg(m, w);
      }
    }
    for (final g in touching) {
      final keys = g.welder != null
          ? [g.welder!.toLowerCase()]
          : welderKeys(g.welds);
      for (final w in keys) {
        addProg(g.method, w);
      }
    }
    final progressive = progByMethod.values.fold(0, (s, n) => s + n);

    final blockers = <NdtBlocker, int>{};
    void add(NdtBlocker b, int n) {
      if (n > 0) blockers[b] = n;
    }

    add(NdtBlocker.rulesDamaged, intact ? 0 : 1);
    add(NdtBlocker.noRules, valid.isEmpty ? 1 : 0);
    add(NdtBlocker.noLine, lKey.isEmpty ? welds.length : 0);
    add(NdtBlocker.unassigned, unassigned);
    add(NdtBlocker.noJointType, noJoint);
    add(NdtBlocker.noMaterial, noMaterial);
    add(NdtBlocker.openDefects, openDefects);
    add(NdtBlocker.repairsAwaiting, repairsAwaiting);
    add(NdtBlocker.awaitingResults, awaitingResults);
    add(NdtBlocker.incompleteGroups,
        touching.where((g) => !g.isComplete).length);
    add(NdtBlocker.missing, touching.fold(0, (s, g) => s + g.missing));
    add(NdtBlocker.progressive, progressive);

    lines.add(NdtLine(
      project: projectName,
      line: lineName,
      welds: List.unmodifiable(welds),
      groups: List.unmodifiable(touching),
      blockers: Map.unmodifiable(blockers),
      uncovered: uncovered,
      rejectsNoScope: lotStats(pKey, lKey).total.rejectsNoScope,
      progressiveByMethod: Map.unmodifiable(progByMethod),
    ));
  }

  lines.sort((a, b) {
    final p = compareWeldNos(a.project, b.project);
    if (p != 0) return p;
    if (a.line.isEmpty != b.line.isEmpty) return a.line.isEmpty ? 1 : -1;
    return compareWeldNos(a.line, b.line);
  });

  return NdtPlan(
    rules: List.unmodifiable(valid),
    rulesIntact: intact,
    groups: List.unmodifiable(groups),
    lines: List.unmodifiable(lines),
    issues: List.unmodifiable(issues),
    round: round,
  );
}

/// Projekty z dziennika (nieusunięte wpisy): pierwsza pisownia,
/// alfabetycznie; '' (spoiny bez projektu) na końcu.
List<String> ndtProjects(Iterable<WeldEntry> entries) {
  final seen = <String, String>{};
  for (final e in entries) {
    if (e.isDeleted) continue;
    final t = e.projectName.trim();
    seen.putIfAbsent(t.toLowerCase(), () => t);
  }
  final out = seen.values.toList()
    ..sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return compareWeldNos(a, b);
    });
  return out;
}

// ─── Teksty ───────────────────────────────────────────────────────────────

const String _nb = ' ';

/// „5 %", „12,5 %" (EN „12.5 %").
String ndtPctText(int bp, {required bool en}) {
  final whole = bp ~/ 100;
  final frac = bp % 100;
  var s = '$whole';
  if (frac != 0) {
    var f = frac.toString().padLeft(2, '0');
    if (f.endsWith('0')) f = f.substring(0, 1);
    s = '$whole${en ? '.' : ','}$f';
  }
  return '$s$_nb%';
}

/// „RT 10 % BW" — metoda, procent, rodzaje (gdy nie wszystkie), materiał.
String ndtRuleShort(NdtRule r, {required bool en}) => [
      '${r.method.code} ${ndtPctText(r.bp, en: en)}'
          '${r.coversAllJoints ? '' : ' ${r.joints.join('/')}'}',
      if (r.hasMaterial) r.material.trim(),
    ].join(' · ');

/// Pełny opis reguły.
String ndtRuleText(NdtRule r, {required bool en}) => [
      '${r.method.code} ${ndtPctText(r.bp, en: en)}',
      r.coversAllJoints
          ? (en ? 'all welds (BW/FW/SW/BR)' : 'wszystkie spoiny (BW/FW/SW/BR)')
          : r.joints.join('/'),
      if (r.hasMaterial)
        '${en ? 'material' : 'materiał'}: ${r.material.trim()}',
      r.perWelder
          ? (en ? 'each welder' : 'każdy spawacz osobno')
          : (en ? 'welders together' : 'spawacze razem'),
      r.perLine
          ? (en ? 'each line' : 'każda linia osobno')
          : (en ? 'lot = project' : 'partia = projekt'),
    ].join(' · ');

String ndtLineName(String line, {required bool en}) => line.isEmpty
    ? (en ? 'no line / ISO' : 'bez linii i ISO')
    : line;

String ndtProjectName(String project, {required bool en}) =>
    project.isEmpty ? (en ? 'no project' : 'bez projektu') : project;

/// „RT 10 % BW · L-12 · JK-12".
String ndtGroupTitle(NdtGroup g, {required bool en}) => [
      ndtRuleShort(g.rule, en: en),
      g.line == null
          ? (en ? 'whole project' : 'cały projekt')
          : ndtLineName(g.line!, en: en),
      g.welder == null
          ? (en ? 'all welders' : 'wszyscy spawacze')
          : (g.welder!.isEmpty
              ? (en ? 'no welder' : 'bez spawacza')
              : g.welder!),
    ].join(' · ');

/// „12 spoin · wymagane 2 · zbadane 1 · brakuje 1 · zlecone 1 · dodatkowe
/// §341.3.4: 2".
String ndtGroupNumbers(NdtGroup g, {required bool en}) => [
      weldsCount(g.welds.length, en: en),
      '${en ? 'required' : 'wymagane'} ${g.required}',
      '${en ? 'examined' : 'zbadane'} ${g.examined}',
      '${en ? 'missing' : 'brakuje'} ${g.missing}',
      if (g.awaiting > 0) '${en ? 'ordered' : 'zlecone'} ${g.awaiting}',
      if (g.progressive > 0)
        '${en ? 'additional' : 'dodatkowe'} §341.3.4: ${g.progressive}',
    ].join(' · ');

String ndtGroupStatusText(NdtGroup g, {required bool en}) =>
    switch (g.status) {
      NdtGroupStatus.complete => en ? 'complete' : 'kompletne',
      NdtGroupStatus.missing => [
          if (g.missing > 0) en ? '${g.missing} missing' : 'brakuje ${g.missing}',
          if (g.progressive > 0)
            en
                ? '${g.progressive} additional (§341.3.4)'
                : 'dodatkowe ${g.progressive} (§341.3.4)',
        ].join(' + '),
      NdtGroupStatus.awaiting => en
          ? 'awaiting results (${g.awaiting + g.awaitingExtra})'
          : 'czeka na wynik (${g.awaiting + g.awaitingExtra})',
      NdtGroupStatus.repairsOpen => en
          ? 'open repairs (${g.openRepairs})'
          : 'naprawy otwarte (${g.openRepairs})',
      NdtGroupStatus.unassigned => en
          ? 'unassigned — no welder'
          : 'nieprzypisane — brak spawacza',
    };

String ndtVerdictText(NdtLine l, {required bool en}) => l.ready
    ? (en ? 'Ready for the pressure test' : 'Gotowa do próby ciśnieniowej')
    : (en ? 'Not ready for the pressure test' : 'Niegotowa do próby ciśnieniowej');

/// „12 spoin · grupy kompletne 3/4 · brakuje 1".
String ndtLineNumbers(NdtLine l, {required bool en}) => [
      weldsCount(l.welds.length, en: en),
      '${en ? 'groups complete' : 'grupy kompletne'} '
          '${l.completeGroups}/${l.groups.length}',
      '${en ? 'missing' : 'brakuje'} ${l.missing}',
      if (l.progressive > 0)
        '${en ? 'additional' : 'dodatkowe'} §341.3.4: ${l.progressive}',
    ].join(' · ');

String ndtBlockerText(NdtBlocker b, NdtLine l, {required bool en}) {
  final n = l.blockers[b] ?? 0;
  return switch (b) {
    NdtBlocker.rulesDamaged => en
        ? 'The saved rules were damaged — check and confirm the rules'
        : 'Zapisane reguły były uszkodzone — sprawdź i potwierdź reguły',
    NdtBlocker.noRules => en
        ? 'No examination rules — pick a preset or add a rule'
        : 'Brak reguł badań — wybierz preset albo dodaj regułę',
    NdtBlocker.noLine => en
        ? 'Welds with no line and no ISO: $n'
        : 'Spoiny bez linii i bez ISO: $n',
    NdtBlocker.unassigned => en
        ? 'Welds with no welder (unassigned): $n'
        : 'Spoiny bez spawacza (nieprzypisane): $n',
    NdtBlocker.noJointType => en
        ? 'Welds with no joint type (BW/FW/SW/BR): $n'
        : 'Spoiny bez rodzaju (BW/FW/SW/BR): $n',
    NdtBlocker.noMaterial => en
        ? 'Welds with no material (a rule depends on it): $n'
        : 'Spoiny bez materiału (reguła od niego zależy): $n',
    NdtBlocker.openDefects => en
        ? 'Rejected welds not repaired yet (NOK): $n'
        : 'Spoiny odrzucone, jeszcze bez naprawy (NOK): $n',
    NdtBlocker.repairsAwaiting => en
        ? 'Repairs awaiting re-examination: $n'
        : 'Naprawy czekają na ponowne badanie: $n',
    NdtBlocker.awaitingResults => en
        ? 'Ordered examinations with no result: $n'
        : 'Zlecone badania bez wyniku: $n',
    NdtBlocker.incompleteGroups => en
        ? 'Incomplete groups: $n of ${l.groups.length}'
        : 'Grupy niekompletne: $n z ${l.groups.length}',
    NdtBlocker.missing => en
        ? 'Examinations missing: $n'
        : 'Brakuje badań: $n',
    NdtBlocker.progressive => en
        ? 'Additional examinations due (B31.3 §341.3.4): $n'
        : 'Dodatkowe badania do wykonania (B31.3 §341.3.4): $n',
  };
}

String ndtIssueText(NdtWeldIssue i, {required bool en}) => switch (i) {
      NdtWeldIssue.noWelder => en ? 'no welder' : 'bez spawacza',
      NdtWeldIssue.noJointType => en ? 'no joint type' : 'bez rodzaju spoiny',
      NdtWeldIssue.noMaterial => en ? 'no material' : 'bez materiału',
      NdtWeldIssue.noLine => en ? 'no line / ISO' : 'bez linii i ISO',
    };

/// „W-3 · L-12 · ISO-1201 · JK-12/AB-03 · BW".
String ndtWeldLabel(WeldEntry e, {required bool en}) {
  final line = weldLineKey(e).trim();
  final iso = e.isoDrawing.trim();
  return [
    e.weldNo.trim().isEmpty ? '?' : e.weldNo.trim(),
    ndtLineName(line, en: en),
    if (iso.isNotEmpty && iso.toLowerCase() != line.toLowerCase()) iso,
    e.stamps.isEmpty ? (en ? 'no welder' : 'bez spawacza') : e.stamps.join('/'),
    if (ndtJointOf(e) != null) ndtJointOf(e)!,
  ].join(' · ');
}

/// Powód zlecenia: „losowo 10 % · JK-12 · L-12" albo „100 % · L-12".
String ndtOrderReason(NdtOrderItem i, {required bool en}) {
  final g = i.group;
  final kind = g.rule.isFull
      ? ndtPctText(g.rule.bp, en: en)
      : '${en ? 'random' : 'losowo'} ${ndtPctText(g.rule.bp, en: en)}';
  return [
    kind,
    if (g.welder != null && g.welder!.isNotEmpty) g.welder!,
    g.line == null
        ? (en ? 'whole project' : 'cały projekt')
        : ndtLineName(g.line!, en: en),
  ].join(' · ');
}

/// Definicje pod planem (ekran, tekst, PDF).
List<String> ndtDefinitions({required bool en}) => en
    ? const [
        'Required = welds × %, always rounded up (5 % of 1 weld = 1, of 21 = 2).',
        'Examined = a result (OK or NOK) by the method. Additional §341.3.4 '
            'samples do not count towards the base % (unless the rule is 100 %).',
        'A weld with two welders (root / cap) is in the group of each, and its '
            'examination counts for both — as in the journal\'s NDT summary.',
        'Additional (§341.3.4): 2 per rejected random sample of the same '
            'welder by the same method, minus samples marked "additional"; the '
            'inspector picks them.',
        '"Ready" only with complete data: every weld has a welder, joint type '
            'and line, no open repairs, no result pending, every group complete.',
      ]
    : const [
        'Wymagane = spoiny × %, zawsze w górę (5 % z 1 spoiny = 1, z 21 = 2).',
        'Zbadane = wynik (OK albo NOK) tą metodą. Badania dodatkowe §341.3.4 '
            'nie liczą się do podstawowego % (chyba że reguła to 100 %).',
        'Spoina z dwoma spawaczami (grań / lico) jest w grupie każdego z nich, '
            'a jej badanie liczy się obu — jak w podsumowaniu NDT dziennika.',
        'Dodatkowe (§341.3.4): 2 za każdą odrzuconą próbkę losową tego samego '
            'spawacza tą samą metodą, minus oznaczone jako „dod."; wybiera '
            'inspektor.',
        '„Gotowa" tylko przy komplecie danych: każda spoina ma spawacza, rodzaj '
            'i linię, brak otwartych napraw i badań bez wyniku, wszystkie grupy '
            'kompletne.',
      ];

// ─── Zlecenie badań (tekst i PDF) ────────────────────────────────────────

class NdtOrderReport {
  /// Projekt w pisowni z dziennika ('' = bez projektu).
  final String project;
  final NdtPlan plan;
  final DateTime generatedAt;

  const NdtOrderReport({
    required this.project,
    required this.plan,
    required this.generatedAt,
  });

  String title({required bool en}) =>
      en ? 'NDT examination order' : 'Zlecenie badań NDT';

  String subject({required bool en}) =>
      '${title(en: en)} — ${ndtProjectName(project, en: en)} — '
      '${isoDate(generatedAt)}';

  String fileName({required bool en}) {
    final safe = project
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final p = safe.isEmpty ? '' : '-$safe';
    return '${en ? 'ndt-order' : 'zlecenie-ndt'}$p-${isoDate(generatedAt)}.pdf';
  }
}

/// Zlecenie badań tekstem (SMS, WhatsApp, e-mail).
String buildNdtOrderText(NdtOrderReport r, {required bool en}) {
  final plan = r.plan;
  final b = StringBuffer()
    ..writeln('${r.title(en: en).toUpperCase()} — '
        '${ndtProjectName(r.project, en: en)}')
    ..writeln(isoDate(r.generatedAt));
  if (plan.rules.isEmpty) {
    b.writeln(en ? 'Requirements: none set.' : 'Wymagania: brak reguł.');
  } else {
    b.writeln(en ? 'Requirements:' : 'Wymagania:');
    for (final x in plan.rules) {
      b.writeln('• ${ndtRuleText(x, en: en)}');
    }
  }
  if (!plan.rulesIntact) {
    b.writeln(en
        ? '! The saved rules were damaged — the plan is not final.'
        : '! Zapisane reguły były uszkodzone — plan nie jest ostateczny.');
  }

  final toOrder = plan.toOrder;
  for (final m in NdtMethod.values) {
    final list = toOrder[m];
    if (list == null || list.isEmpty) continue;
    b
      ..writeln()
      ..writeln('${m.code} — ${en ? 'to order' : 'do zlecenia'}: '
          '${weldsCount(list.length, en: en)}');
    for (final i in list) {
      b.writeln('• ${ndtWeldLabel(i.weld, en: en)} '
          '(${ndtOrderReason(i, en: en)})');
    }
  }
  if (toOrder.isEmpty) {
    b
      ..writeln()
      ..writeln(en
          ? 'Nothing new to order.'
          : 'Nic nowego do zlecenia.');
  }

  final ordered = plan.ordered;
  if (ordered.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en
          ? 'Ordered earlier, no result yet:'
          : 'Zlecone wcześniej, bez wyniku:');
    for (final m in NdtMethod.values) {
      for (final i in ordered[m] ?? const <NdtOrderItem>[]) {
        b.writeln('• ${m.code}: ${ndtWeldLabel(i.weld, en: en)}');
      }
    }
  }

  final prog = plan.progressiveGroups;
  if (prog.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en
          ? 'Additional examinations (B31.3 §341.3.4) — picked by the '
              'inspector, same welder, same method:'
          : 'Badania dodatkowe (B31.3 §341.3.4) — wybiera inspektor, ten sam '
              'spawacz, ta sama metoda:');
    for (final g in prog) {
      b.writeln('• ${ndtGroupTitle(g, en: en)}: ${g.progressive}');
    }
  }

  if (plan.lines.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en
          ? 'Ready for the pressure test: ${plan.readyLines} of '
              '${plan.lines.length} lines'
          : 'Gotowe do próby ciśnieniowej: ${plan.readyLines} z '
              '${plan.lines.length} linii');
    for (final l in plan.lines) {
      final why = l.ready
          ? ''
          : ' — ${[
              for (final k in l.blockers.keys) ndtBlockerText(k, l, en: en)
            ].join('; ')}';
      b.writeln('• ${ndtLineName(l.line, en: en)}: '
          '${ndtVerdictText(l, en: en)}$why');
    }
  }
  b
    ..writeln()
    ..write(en
        ? 'Fitter Welder Pro — from the weld journal'
        : 'Fitter Welder Pro — z dziennika spoin');
  return b.toString();
}
