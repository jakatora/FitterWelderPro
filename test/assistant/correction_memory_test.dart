import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/correction_memory.dart';
import 'package:cut_list_app/services/account_service.dart';

class HeldStorage extends FlutterSecureStorage {
  final started = Completer<void>();
  final release = Completer<void>();
  int writes = 0;

  @override
  Future<String?> read(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    started.complete();
    await release.future;
    return null;
  }

  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountService previous;
  late AccountService guest;
  late MockClient client;
  late CorrectionMemoryStore store;
  const entry = RememberedCorrection(
      question: 'Co to jest TIG?',
      correction: 'Chodzi mi o spawanie aluminium');

  setUp(() async {
    previous = AccountService.instance;
    FlutterSecureStorage.setMockInitialValues({});
    client = MockClient((_) async => http.Response('{}', 500));
    guest = AccountService.forTesting(client);
    AccountService.instance = guest;
    await guest.load();
    store = CorrectionMemoryStore();
  });
  tearDown(() {
    AccountService.instance = previous;
    guest.dispose();
    client.close();
  });

  test('persists, deduplicates and clears the current owner', () async {
    await store.remember(entry);
    await store.remember(entry);
    final loaded = await CorrectionMemoryStore().list();
    expect(loaded, hasLength(1));
    expect(loaded.single.question, entry.question);
    expect(loaded.single.correction, entry.correction);
    await store.clear();
    expect(await store.list(), isEmpty);
  });

  test('separate accounts cannot read or clear each others records', () async {
    await store.remember(entry);
    final signed = AccountService.forTesting(client);
    await signed.load();
    signed.account = {'id': 'account-b'};
    AccountService.instance = signed;
    expect(await store.list(), isEmpty);
    await store.remember(const RememberedCorrection(
        question: 'pytanie B', correction: 'korekta B'));
    await store.clear();
    AccountService.instance = guest;
    expect((await store.list()).single.correction, entry.correction);
    signed.dispose();
  });

  test('refuses credentials and oversized records', () async {
    expect(
        () => store.remember(const RememberedCorrection(
            question: 'pytanie', correction: 'hasło: sekret123')),
        throwsFormatException);
    expect(
        () => store.remember(
            RememberedCorrection(question: 'x' * 501, correction: 'korekta')),
        throwsFormatException);
    expect(await store.list(), isEmpty);
  });

  test('corrupt memory is not overwritten by new record', () async {
    final key =
        'assistant_corrections_v1_${sha256.convert(utf8.encode('guest'))}';
    const storage = FlutterSecureStorage();
    await storage.write(key: key, value: '{broken');
    await expectLater(store.remember(entry), throwsFormatException);
    expect(await storage.read(key: key), '{broken');
  });

  test('concurrent writes stay serialized and storage is bounded', () async {
    await Future.wait([
      for (var i = 0; i < 25; i++)
        store.remember(RememberedCorrection(
            question: 'Pytanie $i', correction: 'Korekta $i')),
    ]);
    final saved = await store.list();
    expect(saved, hasLength(CorrectionMemoryStore.maxRecords));
    expect(saved.first.question, 'Pytanie 24');
    expect(saved.last.question, 'Pytanie 5');
  });

  test('one correction can be forgotten without deleting others', () async {
    const other = RememberedCorrection(
        question: 'Inne pytanie', correction: 'Inna odpowiedź');
    await store.remember(entry);
    await store.remember(other);
    await store.forget(entry);
    final left = await store.list();
    expect(left, hasLength(1));
    expect(left.single.correction, other.correction);
  });

  test(
      'account change during read cannot write correction into another session',
      () async {
    final storage = HeldStorage();
    final guarded = CorrectionMemoryStore(storage: storage);
    final pending = guarded.remember(entry);
    final expectation = expectLater(pending, throwsA(isA<AccountException>()));
    await storage.started.future;
    final other = AccountService.forTesting(client);
    await other.load();
    other.account = {'id': 'other'};
    AccountService.instance = other;
    storage.release.complete();
    await expectation;
    expect(storage.writes, 0);
    other.dispose();
  });

  test('only related questions receive stored user statements', () async {
    await store.remember(entry);
    final relevant = await store.capture('Jak działa TIG przy spawaniu?');
    expect(relevant.records, hasLength(1));
    final unrelated = await store.capture('Jak obliczyć ciężar kołnierza?');
    expect(unrelated.records, isEmpty);
    await store.remember(const RememberedCorrection(
        question: 'Jak obliczyć wymiary kolana?', correction: 'Chodzi o DN50'));
    expect((await store.capture('Jak obliczyć ciężar kołnierza?')).records,
        isEmpty);
    await store.clear();
    expect(relevant.requireCurrent, throwsA(isA<CorrectionMemoryChanged>()));
  });

  test('finds technical topics in a correction including Polish forms', () {
    const record = RememberedCorrection(
        question: 'Co to jest TIG?',
        correction: 'Chodzi o spawanie aluminium i rury DN 50');
    expect(
        relevantCorrections('Jak spawać aluminiową rurę?', [record]), [record]);
    expect(relevantCorrections('Jak dobrać DN50?', [record]), [record]);
    expect(relevantCorrections('Jak spawać nierdzewkę?', [record]), isEmpty);
  });

  test('technical questions match natural inflections in later questions', () {
    for (final (original, followUp) in [
      ('Jaki gaz osłonowy wybrać?', 'Jaki przepływ gazu osłonowego?'),
      ('Jak ustawić przepływ?', 'Czy przepływu jest za dużo?'),
      ('Jaka temperatura międzyściegowa?', 'Jak zmierzyć temperaturę?'),
      ('Jak dobrać podgrzewanie?', 'Czy preheat jest konieczny?'),
      ('Jaka średnica rury?', 'Jak zmierzyć średnicę?'),
      ('Jaka długość odcinka?', 'Jak sprawdzić długości?'),
      ('What shielding gas should I use?', 'Jaki gaz osłonowy wybrać?'),
    ]) {
      final record = RememberedCorrection(question: original, correction: 'Mój kontekst');
      expect(relevantCorrections(followUp, [record]), [record],
          reason: '$original → $followUp');
    }
  });

  test('correction keywords match inflections without matching arbitrary prefixes', () {
    const record = RememberedCorrection(question: 'Inny temat', correction: 'Chodzi o hel');
    expect(relevantCorrections('Ile helu potrzeba?', [record]), [record]);
    const gas = RememberedCorrection(question: 'Inny temat', correction: 'Chodzi o gaz');
    expect(relevantCorrections('Co napisała gazeta?', [gas]), isEmpty);
    const length = RememberedCorrection(question: 'Inny temat', correction: 'Długość dwa metry');
    expect(relevantCorrections('Jaka długość rury?', [length]), isEmpty);
  });

  test('a name in a correction alone is not a topic match', () {
    const record = RememberedCorrection(
        question: 'Co to TIG?', correction: 'Chodzi o projekt Kowalski');
    expect(relevantCorrections('Co zamówił Kowalski?', [record]), isEmpty);
  });

  test('generic words for method or type do not relate different topics', () {
    const tig = RememberedCorrection(
        question: 'Jaka metoda do TIG?', correction: 'Chodzi o aluminium');
    expect(relevantCorrections('Jaką metodę stosować przy MIG?', [tig]), isEmpty);
    expect(relevantCorrections('Jaka metoda TIG do rur?', [tig]), [tig]);
    const pipe = RememberedCorrection(
        question: 'Jaki rodzaj kołnierza?', correction: 'Chodzi o DN50');
    expect(relevantCorrections('Jaki rodzaj elektrody?', [pipe]), isEmpty);
    const english = RememberedCorrection(
        question: 'What method for TIG?', correction: 'Aluminium');
    expect(relevantCorrections('Which method for MIG?', [english]), isEmpty);
  });

  test('gas corrections follow explicit replacement and mixtures', () {
    const helium = RememberedCorrection(
        question: 'Jaki gaz osłonowy do TIG?',
        correction: 'Nie argon, tylko hel');
    expect(relevantCorrections('Jaki przepływ argonu do TIG?', [helium]), isEmpty);
    expect(relevantCorrections('Jaki przepływ helu do TIG?', [helium]), [helium]);
    expect(relevantCorrections('Jaki gaz do TIG?', [helium]), [helium]);
    const argon = RememberedCorrection(
        question: 'Jaki gaz osłonowy do TIG?',
        correction: 'Nie helu, tylko argonu');
    expect(relevantCorrections('Jaki przepływ helu do TIG?', [argon]), isEmpty);
    expect(relevantCorrections('Jaki przepływ argonu do TIG?', [argon]), [argon]);
    const mixture = RememberedCorrection(
        question: 'Jaki gaz osłonowy do TIG?',
        correction: 'Chodzi o mieszankę argonu i helu');
    expect(relevantCorrections('Jaki przepływ argonu i helu do TIG?', [mixture]), [mixture]);
    expect(relevantCorrections('Jaki przepływ argonu do TIG?', [mixture]), [mixture]);
    const english = RememberedCorrection(
        question: 'What shielding gas for TIG?', correction: 'Not helium but argon');
    expect(relevantCorrections('What helium flow for TIG?', [english]), isEmpty);
    expect(relevantCorrections('What argon flow for TIG?', [english]), [english]);
  });

  test('shared gas topic does not transfer corrections between explicit processes', () {
    const record = RememberedCorrection(
        question: 'Jaki gaz osłonowy do TIG?', correction: 'Chodzi o argon');
    expect(relevantCorrections('Jaki gaz osłonowy do MAG?', [record]), isEmpty);
    expect(relevantCorrections('Jaki gaz osłonowy do TIG?', [record]), [record]);
    expect(relevantCorrections('Jaki przepływ gazu osłonowego?', [record]), [record]);
  });

  test('explicit material from correction takes precedence over original question', () {
    const record = RememberedCorrection(
        question: 'Jaki gaz do aluminium?', correction: 'Nie, chodzi o nierdzewną');
    expect(relevantCorrections('Jaki gaz do aluminium?', [record]), isEmpty);
    expect(relevantCorrections('Jaki gaz do stali nierdzewnej?', [record]), [record]);
    expect(relevantCorrections('Jaki gaz osłonowy?', [record]), [record]);
  });

  test('explicit not X but Y corrections attach to Y rather than X', () {
    for (final (original, correction, rejected, accepted) in [
      ('Jaki gaz do TIG?', 'Nie TIG, tylko MAG', 'Jaki gaz do TIG?', 'Jaki gaz do MAG?'),
      ('Jaki gaz do aluminium?', 'Nie aluminium, tylko stal nierdzewna',
        'Jaki gaz do aluminium?', 'Jaki gaz do stali nierdzewnej?'),
      ('Which gas for TIG?', 'Not TIG but MIG', 'Which gas for TIG?', 'Which gas for MIG?'),
    ]) {
      final record = RememberedCorrection(question: original, correction: correction);
      expect(relevantCorrections(rejected, [record]), isEmpty, reason: correction);
      expect(relevantCorrections(accepted, [record]), [record], reason: correction);
    }
  });

  test('not only TIG but also MAG is not interpreted as rejecting TIG', () {
    const record = RememberedCorrection(
        question: 'Jaki gaz do TIG?', correction: 'Nie tylko TIG, ale także MAG');
    expect(relevantCorrections('Jaki gaz do TIG?', [record]), [record]);
    expect(relevantCorrections('Jaki gaz do MAG?', [record]), [record]);
  });

  test(
      'stronger original question matches are selected before correction-only matches',
      () {
    final records = [
      for (var i = 0; i < 3; i++)
        RememberedCorrection(
            question: 'Inne zagadnienie $i', correction: 'Chodzi o aluminium'),
      const RememberedCorrection(
          question: 'Jak spawać aluminium?', correction: 'Metodą TIG'),
    ];
    final matches = relevantCorrections('Jak spawać aluminium?', records);
    expect(matches, hasLength(3));
    expect(matches.first, same(records.last));
  });

  test('queued deletion invalidates a memory snapshot before it is captured',
      () async {
    final storage = HeldStorage();
    final guarded = CorrectionMemoryStore(storage: storage);
    final pendingCapture = guarded.capture('Co to TIG?');
    final expectation =
        expectLater(pendingCapture, throwsA(isA<CorrectionMemoryChanged>()));
    await storage.started.future;
    final pendingDeletion = guarded.clear();
    storage.release.complete();
    await expectation;
    await pendingDeletion;
  });
}
