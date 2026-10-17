// Wady spoin — spójność danych: identyfikatory, przyczyny dla każdego
// procesu (i materiału / pozycji), numery ISO 6520-1 zgodne z grupą, nazwy PL
// / EN zgodne z tabelą ISO 5817 i słownikiem, te same liczby w PL i EN,
// źródła, lista „przed następnym ściegiem” (3–6 punktów), bez emoji.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/weld_defects.dart';
import 'package:cut_list_app/data/welding_glossary.dart';
import 'package:cut_list_app/domain/defects/defect_advice.dart';
import 'package:cut_list_app/domain/glossary/glossary.dart';
import 'package:cut_list_app/domain/iso5817/iso5817_table.dart';

/// Wszystkie teksty dwujęzyczne danych z etykietą (do komunikatów testu).
Iterable<(String, Tx)> _allTx() sync* {
  for (final d in kWeldDefects) {
    yield ('${d.id}.title', d.title);
    yield ('${d.id}.looks', d.looks);
    yield ('${d.id}.cutOut', d.cutOut);
    for (final (i, s) in d.safety.indexed) {
      yield ('${d.id}.safety[$i]', s);
    }
    for (final c in d.causes) {
      yield ('${d.id}.${c.id}.cause', c.cause);
      yield ('${d.id}.${c.id}.check', c.check);
      yield ('${d.id}.${c.id}.fix', c.fix);
    }
    for (final s in [...d.repair, ...d.checklist]) {
      yield ('${d.id}.${s.id}', s.text);
    }
  }
}

final _number = RegExp(r'\d+(?:[.,]\d+)?');

List<String> _numbers(String s) =>
    [for (final m in _number.allMatches(s)) m.group(0)!.replaceAll(',', '.')]
      ..sort();

bool _hasEmoji(String s) => s.runes.any((r) =>
    (r >= 0x1F300 && r <= 0x1FAFF) ||
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x1F000 && r <= 0x1F2FF) ||
    r == 0xFE0F);

void main() {
  test('identyfikatory wad, przyczyn i kroków są unikalne', () {
    final ids = [for (final d in kWeldDefects) d.id];
    expect(ids.toSet().length, ids.length);
    for (final d in kWeldDefects) {
      final causes = [for (final c in d.causes) c.id];
      expect(causes.toSet().length, causes.length, reason: d.id);
      final steps = [for (final s in d.repair) s.id];
      expect(steps.toSet().length, steps.length, reason: '${d.id} repair');
      final checks = [for (final s in d.checklist) s.id];
      expect(checks.toSet().length, checks.length, reason: '${d.id} checklist');
      expect(d.id.trim(), isNotEmpty);
    }
  });

  test('każda wada ma ≥ 1 przyczynę dla każdego swojego procesu, materiału '
      'i pozycji', () {
    for (final d in kWeldDefects) {
      expect(d.processes, isNotEmpty, reason: d.id);
      for (final p in d.processes) {
        final mats = d.materialsFor(p);
        expect(mats, isNotEmpty, reason: '${d.id}/${p.name}: brak materiału');
        for (final m in <DefectMaterial?>[null, ...mats]) {
          for (final pos in <DefectPosition?>[null, ...DefectPosition.values]) {
            final a = defectAdvice(d, p, material: m, position: pos)!;
            expect(a.causes, isNotEmpty,
                reason: '${d.id}/${p.name}/${m?.name}/${pos?.name}');
            expect(a.repair, isNotEmpty, reason: '${d.id}/${p.name} naprawa');
          }
        }
      }
    }
  });

  test('przyczyny i kroki odnoszą się tylko do procesów / materiałów wady', () {
    for (final d in kWeldDefects) {
      for (final c in d.causes) {
        expect(c.processes, isNotEmpty, reason: '${d.id}/${c.id}');
        expect(d.processes.containsAll(c.processes), isTrue,
            reason: '${d.id}/${c.id}: proces spoza wady');
        expect(c.rank, inInclusiveRange(1, 4), reason: '${d.id}/${c.id}');
        if (d.materials.isNotEmpty && c.materials.isNotEmpty) {
          expect(d.materials.containsAll(c.materials), isTrue,
              reason: '${d.id}/${c.id}: materiał spoza wady');
        }
        // Przyczyna musi być osiągalna: jakiś proces przyczyny spawa jej
        // materiał.
        if (c.materials.isNotEmpty) {
          expect(
              c.processes.any(
                  (p) => d.materialsFor(p).any(c.materials.contains)),
              isTrue,
              reason: '${d.id}/${c.id}: nieosiągalna');
        }
      }
      // Krok ograniczony do procesów musi dotyczyć choć jednego procesu wady
      // (wspólne kroki naprawy, np. żłobienie, mają szerszy zakres).
      for (final s in [...d.repair, ...d.checklist]) {
        expect(s.processes.isEmpty || s.processes.any(d.processes.contains),
            isTrue,
            reason: '${d.id}/${s.id}');
      }
      for (final s in d.checklist) {
        expect(d.processes.containsAll(s.processes), isTrue,
            reason: '${d.id}/${s.id}');
      }
    }
  });

  test('„przed następnym ściegiem”: 3–6 punktów dla każdego procesu '
      'i materiału', () {
    for (final d in kWeldDefects) {
      for (final p in d.processes) {
        for (final m in <DefectMaterial?>[null, ...d.materialsFor(p)]) {
          final n = defectAdvice(d, p, material: m)!.checklist.length;
          expect(n, inInclusiveRange(3, 6),
              reason: '${d.id}/${p.name}/${m?.name}: $n');
        }
      }
    }
  });

  test('numery ISO 6520-1 zgodne z grupą 1xx–6xx', () {
    for (final d in kWeldDefects) {
      expect(d.refs, isNotEmpty, reason: d.id);
      expect(d.group.digit, inInclusiveRange(1, 6));
      final codes = d.codes;
      expect(codes.toSet().length, codes.length, reason: d.id);
      for (final r in d.refs) {
        expect(r.code, greaterThanOrEqualTo(100), reason: '${d.id}/${r.code}');
        expect(r.code, lessThan(10000), reason: '${d.id}/${r.code}');
        expect(r.groupDigit, d.group.digit, reason: '${d.id}/${r.code}');
        // Podgrupy (np. 5011) zaczynają się od numeru 3-cyfrowego.
        if (r.code >= 1000) {
          expect('${r.code}'.substring(0, 1), '${d.group.digit}');
        }
        expect(r.pl.trim(), isNotEmpty);
        expect(r.en.trim(), isNotEmpty);
      }
    }
    // Kolejność listy: grupy rosnąco.
    final digits = [for (final d in kWeldDefects) d.group.digit];
    expect(digits, [...digits]..sort());
  });

  test('nazwy PL / EN wspólnych numerów zgodne z tabelą ISO 5817 '
      'i słownikiem', () {
    // Pozycje tablicy 1 z jednym numerem — nazwa pozycji = nazwa numeru.
    final tablePl = <int, Set<String>>{};
    final tableEn = <int, Set<String>>{};
    for (final i in kIso5817Items) {
      if (i.codes.length != 1) continue;
      tablePl.putIfAbsent(i.codes.single, () => {}).add(i.namePl);
      tableEn.putIfAbsent(i.codes.single, () => {}).add(i.nameEn);
    }
    final glossPl = <int, Set<String>>{};
    final glossEn = <int, Set<String>>{};
    for (final t in kWeldingGlossary) {
      final code = int.tryParse(t.iso6520 ?? '');
      if (code == null) continue;
      glossPl.putIfAbsent(code, () => {})
        ..add(t.pl)
        ..addAll(t.synonyms[GlossaryLang.pl] ?? const []);
      glossEn.putIfAbsent(code, () => {})
        ..add(t.en)
        ..addAll(t.synonyms[GlossaryLang.en] ?? const []);
    }
    var checked = 0;
    for (final d in kWeldDefects) {
      for (final r in d.refs) {
        final pl = {...?tablePl[r.code], ...?glossPl[r.code]};
        final en = {...?tableEn[r.code], ...?glossEn[r.code]};
        if (pl.isNotEmpty) {
          checked++;
          expect(pl, contains(r.pl), reason: '${d.id}/${r.code} PL');
        }
        if (en.isNotEmpty) {
          expect(en, contains(r.en), reason: '${d.id}/${r.code} EN');
        }
      }
    }
    expect(checked, greaterThanOrEqualTo(20),
        reason: 'większość numerów jest w tabeli lub słowniku');
    // Ten sam numer w dwóch wadach — ta sama nazwa.
    final names = <int, String>{};
    for (final d in kWeldDefects) {
      for (final r in d.refs) {
        final prev = names[r.code];
        if (prev != null) expect(r.pl, prev, reason: '${r.code}');
        names[r.code] = r.pl;
      }
    }
    // Po poprawce nazw: 509 = „Zwis”.
    expect(names[509], 'Zwis');
  });

  test('wymagane wady z zakresu modułu są w danych', () {
    final codes = {for (final d in kWeldDefects) ...d.codes};
    for (final c in [
      100, 104, 2011, 2012, 2013, 2014, 2017, 202, 2025, 301, 303, 3041, //
      401, 402, 4021, 5011, 5012, 5013, 502, 503, 504, 506, 507, 509, 510,
      511, 512, 515, 516, 5213, 5214, 601, 602, 610,
    ]) {
      expect(codes, contains(c), reason: '$c');
    }
    for (final id in [
      'crack_cold',
      'crack_hot',
      'crack_crater',
      'root_oxidation',
      'temper_colour',
      'fillet_shape',
    ]) {
      expect(weldDefectById(id), isNotNull, reason: id);
    }
    // Procesy z zakresu: każdy ma co najmniej kilka wad.
    for (final p in DefectProcess.values) {
      expect(defectsForProcess(p).length, greaterThanOrEqualTo(10),
          reason: p.name);
    }
  });

  test('te same liczby w PL i EN', () {
    for (final (label, tx) in _allTx()) {
      expect(_numbers(tx.en), _numbers(tx.pl), reason: label);
    }
    for (final d in kWeldDefects) {
      for (final r in d.refs) {
        expect(_numbers(r.en), _numbers(r.pl), reason: '${d.id}/${r.code}');
      }
    }
  });

  test('teksty niepuste, bez emoji, bez podwójnych spacji', () {
    for (final (label, tx) in _allTx()) {
      for (final s in [tx.pl, tx.en]) {
        expect(s.trim(), isNotEmpty, reason: label);
        expect(_hasEmoji(s), isFalse, reason: label);
        expect(s.contains('  '), isFalse, reason: '$label: „$s”');
        expect(s, s.trim(), reason: label);
      }
    }
    for (final d in kWeldDefects) {
      for (final k in d.keywords) {
        expect(k, k.toLowerCase(), reason: '${d.id}: $k');
        expect(normalizeGlossary(k), k, reason: '${d.id}: $k bez znaków PL');
      }
    }
  });

  test('źródła: każda przyczyna ma źródło, klucze istnieją, adresy https', () {
    for (final s in kDefectSources.values) {
      expect(s.url, startsWith('https://'), reason: s.title);
      expect(s.url.contains(' '), isFalse, reason: s.url);
      expect(s.short.trim(), isNotEmpty);
    }
    final used = <String>{};
    for (final d in kWeldDefects) {
      expect(d.repairSources, isNotEmpty, reason: d.id);
      for (final k in d.repairSources) {
        expect(kDefectSources.containsKey(k), isTrue, reason: '${d.id}: $k');
        used.add(k);
      }
      for (final c in d.causes) {
        expect(c.sources, isNotEmpty, reason: '${d.id}/${c.id}');
        for (final k in c.sources) {
          expect(kDefectSources.containsKey(k), isTrue,
              reason: '${d.id}/${c.id}: $k');
          used.add(k);
        }
      }
    }
    // Żadne źródło nie wisi bez użycia.
    expect(kDefectSources.keys.toSet().difference(used), isEmpty);
    // Liczby w BHP mają źródło w części „Naprawa”.
    for (final d in kWeldDefects) {
      for (final s in d.safety) {
        final need = <String>[
          if (s.pl.contains('SUG004')) 'lincoln-gouging',
          if (s.pl.contains('Penetrant')) 'magnaflux-sds',
          if (s.pl.contains('Argon')) 'hse-argon',
          if (s.pl.contains('HNO')) 'hse-pickling',
        ];
        for (final k in need) {
          expect(d.repairSources, contains(k), reason: '${d.id}: $k');
        }
      }
    }
  });

  test('naprawa: kroki, „do wycięcia” i BHP dla każdej wady', () {
    for (final d in kWeldDefects) {
      expect(d.repair, isNotEmpty, reason: d.id);
      expect(d.safety, isNotEmpty, reason: d.id);
      expect(d.cutOut.pl.trim(), isNotEmpty, reason: d.id);
    }
    // Pęknięcia: limit napraw i wycięcie.
    final crack = weldDefectById('crack_cold')!;
    expect(crack.repair.map((s) => s.id), contains('limit'));
    expect(crack.cutOut.pl, contains('API 1104'));
  });

  test('przyczyny „przepływu gazu” tylko dla procesów z gazem z butli', () {
    for (final d in kWeldDefects) {
      for (final c in d.causes) {
        if (!c.id.contains('gas-flow')) continue;
        for (final p in c.processes) {
          expect(p.usesShieldingGas, isTrue, reason: '${d.id}/${c.id}');
        }
      }
    }
  });
}
