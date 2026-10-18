// Lista kontrolna stanowiska: kompletna, trwałe identyfikatory, każdy punkt
// ma źródło; niezaznaczony ≠ OK; „n/d” tylko tam, gdzie wolno; punkt
// odsyłający do „Przestrzeni zamkniętej”.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fume/fume_checklist.dart';
import 'package:cut_list_app/domain/fume/fume_hazards.dart';

void main() {
  test('identyfikatory unikalne, teksty PL/EN i źródła niepuste', () {
    final ids = kFumeChecks.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final c in kFumeChecks) {
      expect(c.id, matches(RegExp(r'^[a-z]+-[a-z0-9-]+$')), reason: c.id);
      expect(c.pl.trim(), isNotEmpty, reason: c.id);
      expect(c.en.trim(), isNotEmpty, reason: c.id);
      expect(c.source.trim(), isNotEmpty, reason: c.id);
      expect(fumeCheckById(c.id), same(c));
      if (c.naAllowed) {
        expect(c.naHint(en: false), isNotNull, reason: c.id);
        expect(c.naHint(en: true), isNotNull, reason: c.id);
      }
    }
  });

  test('każda grupa ma punkty; kluczowe punkty z briefu są na liście', () {
    for (final g in FumeCheckGroup.values) {
      expect(fumeChecksIn(g), isNotEmpty, reason: g.name);
    }
    for (final id in [
      'lev-close', // odciąg włączony i blisko
      'lev-filter', // filtr wymieniany
      'lev-recirc', // recyrkulacja tylko W3
      'mat-coatings', // powłoki usunięte
      kFumeCheckConfinedId, // odsyłacz: przestrzeń zamknięta
      kFumeCheckGasId, // gazy: filtr P3 nie chroni
      'room-airing', // przewietrzanie
    ]) {
      expect(fumeCheckById(id), isNotNull, reason: id);
    }
    expect(fumeCheckById('lev-recirc')!.pl, contains('W3'));
    expect(fumeCheckById(kFumeCheckConfinedId)!.pl,
        contains('Przestrzeń zamknięta'));
  });

  test('niezaznaczony punkt to otwarty, nie OK', () {
    expect(fumeOpenChecks(const {}).length, kFumeChecks.length);
    final c = kFumeChecks.first;
    expect(fumeCheckState(c, const {}), FumeCheckState.open);
    expect(fumeCheckState(c, {c.id: FumeCheckState.done}), FumeCheckState.done);
  });

  test('„n/d” przy punkcie bez tej opcji liczy się jako otwarty', () {
    final strict = kFumeChecks.firstWhere((c) => !c.naAllowed);
    expect(strict.id, 'lev-close');
    expect(fumeCheckState(strict, {strict.id: FumeCheckState.notApplicable}),
        FumeCheckState.open);
    final loose = kFumeChecks.firstWhere((c) => c.naAllowed);
    expect(fumeCheckState(loose, {loose.id: FumeCheckState.notApplicable}),
        FumeCheckState.notApplicable);
  });

  test('podstawowe punkty bez „n/d”: odciąg blisko, skład, przegląd, ŚOI', () {
    for (final id in [
      'lev-close',
      'lev-plume',
      'lev-exam',
      'mat-sds',
      'rpe-maint'
    ]) {
      expect(fumeCheckById(id)!.naAllowed, isFalse, reason: id);
    }
  });

  test('„nie dotyczy” zablokowane, gdy przeczy wyborom: powłoki, maska, gazy',
      () {
    final coatings = fumeCheckById(kFumeCheckCoatingsId)!;
    for (final m in [
      FumeMaterial.coated,
      FumeMaterial.galvanised,
      FumeMaterial.other,
    ]) {
      final ctx = FumeCheckContext(material: m);
      expect(fumeNaBlock(coatings, ctx), FumeNaBlock.coatedMaterial,
          reason: m.name);
      expect(
          fumeCheckState(
              coatings, {coatings.id: FumeCheckState.notApplicable}, ctx),
          FumeCheckState.open,
          reason: m.name);
    }
    expect(
        fumeNaBlock(coatings,
            const FumeCheckContext(material: FumeMaterial.carbonSteel)),
        isNull);

    final fit = fumeCheckById(kFumeCheckFitId)!;
    for (final r in [FumeRpe.none, FumeRpe.p2, FumeRpe.p3]) {
      expect(fumeNaBlock(fit, FumeCheckContext(rpe: r)), FumeNaBlock.notPowered,
          reason: r.name);
    }
    for (final r in [FumeRpe.th1, FumeRpe.th2, FumeRpe.th3]) {
      expect(fumeNaBlock(fit, FumeCheckContext(rpe: r)), isNull,
          reason: r.name);
    }

    final gas = fumeCheckById(kFumeCheckGasId)!;
    expect(gas.naAllowed, isTrue);
    expect(gas.pl, contains('P3'));
    expect(
        fumeNaBlock(
            gas,
            const FumeCheckContext(
                material: FumeMaterial.aluminium, process: FumeProcess.tig)),
        FumeNaBlock.gasHazard);
    expect(
        fumeNaBlock(
            gas,
            const FumeCheckContext(
                material: FumeMaterial.carbonSteel, process: FumeProcess.mma)),
        isNull);
  });
}
