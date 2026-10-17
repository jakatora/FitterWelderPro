// Linia ograniczeń z próby `[ISO9606 v1]` w uwagach certyfikatu: zapis,
// odczyt, brak linii, uszkodzenia, nieznane klucze, ręczna edycja notatki.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/iso9606_limits.dart';

void main() {
  const full = Iso9606Limits(
    root: {RootCondition.mb, RootCondition.bs},
    dip: false,
    plates: false,
    fm: {'FM2', 'FM1'},
    noFillerGroup: '1.1',
    proc2: ['111'],
    branch: 60,
    layers: {'sl'},
    direction: 'lw',
  );

  group('zapis', () {
    test('stała kolejność kluczy, listy posortowane', () {
      expect(
          full.encode(),
          '[ISO9606 v1] root=mb,bs; dip=0; plates=0; fm=FM1,FM2; '
          'nofiller=1.1; proc2=111; branch=60; layers=sl; dir=lw');
      expect(const Iso9606Limits().encode(), '[ISO9606 v1]');
      expect(const Iso9606Limits(dip: true, plates: true).encode(),
          '[ISO9606 v1] dip=1; plates=1');
    });

    test('zapis → odczyt daje to samo', () {
      final p = parseIso9606Limits('Uwagi\n${full.encode()}\nKoniec');
      expect(p.status, Iso9606LimitsStatus.ok);
      final l = p.limits!;
      expect(l.root, {RootCondition.mb, RootCondition.bs});
      expect(l.dip, isFalse);
      expect(l.plates, isFalse);
      expect(l.fm, {'FM1', 'FM2'});
      expect(l.noFillerGroup, '1.1');
      expect(l.proc2, ['111']);
      expect(l.branch, 60);
      expect(l.layers, {'sl'});
      expect(l.direction, 'lw');
      expect(l.encode(), full.encode());
    });
  });

  group('odczyt', () {
    test('brak linii → brak ograniczeń (certyfikat wpisany ręcznie)', () {
      for (final notes in [null, '', 'Certyfikat UDT, egzamin w Gliwicach',
          '[ISO 9606-1] notatka spawacza', 'ISO9606 v1 root=nb']) {
        final p = parseIso9606Limits(notes);
        expect(p.status, Iso9606LimitsStatus.absent, reason: '$notes');
        expect(p.limits, isNull);
      }
    });

    test('ręczna edycja: wielkość liter, spacje, kolejność, puste odcinki', () {
      final p = parseIso9606Limits(
          'OGRANICZENIA…\n  [iso9606  V1]  FM = fm 1 , FM2 ;; Root=SS NB, bs ;'
          ' plates=0;branch = 0  \r\nreszta notatki');
      expect(p.status, Iso9606LimitsStatus.ok);
      expect(p.limits!.fm, {'FM1', 'FM2'});
      expect(p.limits!.root, {RootCondition.nb, RootCondition.bs});
      expect(p.limits!.plates, isFalse);
      expect(p.limits!.branch, 0);
      // Klucze, których nie ma, to brak ograniczenia.
      expect(p.limits!.dip, isNull);
      expect(p.limits!.layers, isNull);
    });

    test('nieznane klucze są pomijane (nowsze dopiski)', () {
      final p = parseIso9606Limits(
          '[ISO9606 v1] fm=FM5; type=B; heat=low; root=nb,mb,bs');
      expect(p.status, Iso9606LimitsStatus.ok);
      expect(p.limits!.fm, {'FM5'});
      expect(p.limits!.root,
          {RootCondition.nb, RootCondition.mb, RootCondition.bs});
    });

    test('uszkodzona linia → „uszkodzona”, bez częściowego odczytu', () {
      const broken = [
        '[ISO9606 v1] fm=FM7', // spoza tab. 2
        '[ISO9606 v1] fm=', // pusta lista
        '[ISO9606 v1] root=nb,xx', // nieznany sposób grani
        '[ISO9606 v1] dip=tak', // nie 0/1
        '[ISO9606 v1] plates=2',
        '[ISO9606 v1] branch=45',
        '[ISO9606 v1] layers=sl,zz',
        '[ISO9606 v1] dir=up',
        '[ISO9606 v1] nofiller=stal',
        '[ISO9606 v1] proc2=MMA',
        '[ISO9606 v1] fm=FM1; fm=FM5', // powtórzony klucz
        '[ISO9606 v1] fm FM1', // bez „=”
        '[ISO9606 v1 fm=FM1', // brak „]”
        '[ISO9606] fm=FM1', // brak wersji
        '[ISO9606 v2] fm=FM1', // nowsza wersja
      ];
      for (final line in broken) {
        final p = parseIso9606Limits('Uwagi\n$line');
        expect(p.status, Iso9606LimitsStatus.damaged, reason: line);
        expect(p.limits, isNull, reason: line);
        expect(p.problem, isNotEmpty, reason: line);
      }
    });

    test('dwie linie ze znacznikiem (np. sklejone notatki) → uszkodzona', () {
      final p = parseIso9606Limits(
          '[ISO9606 v1] fm=FM1,FM2\n[ISO9606 v1] fm=FM5');
      expect(p.status, Iso9606LimitsStatus.damaged);
    });

    test('kody grani: ss nb / nb / SS-NB; etykiety jak na certyfikacie', () {
      expect(RootCondition.parse('ss nb'), RootCondition.nb);
      expect(RootCondition.parse('SS-NB'), RootCondition.nb);
      expect(RootCondition.parse('bs'), RootCondition.bs);
      expect(RootCondition.parse('xx'), isNull);
      expect(RootCondition.nb.label, 'ss nb');
      expect(RootCondition.ci.label, 'ci');
    });
  });
}
