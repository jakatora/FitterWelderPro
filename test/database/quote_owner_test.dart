// Wyceny należą do właściciela danych (schema34): dawne wiersze zostają
// gościowi, konto nie widzi, nie nadpisuje i nie usuwa cudzych ofert, a
// numeracja liczy się we własnych wycenach.

import 'dart:convert';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_account.dart';
import '../support/test_database.dart';

Future<void> signIn(String id) async {
  FlutterSecureStorage.setMockInitialValues({});
  AccountService.instance =
      AccountService.forTesting(MockClient((_) async => http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'}
          }),
          200)));
  await AccountService.instance.signIn('$id@example.test', 'test-password');
}

WeldQuote quote(String id, {String client = 'Klient'}) => WeldQuote(
    id: id, client: client, createdAt: 1, updatedAt: 1);

void main() {
  useTestDatabase();
  setUp(() async {
    await seedGuestAccount();
    final db = await AppDatabase.get();
    await db.delete('weld_quotes');
  });

  test('legacy rows belong to the guest; an account starts empty', () async {
    final db = await AppDatabase.get();
    // Wiersz sprzed v34 (bez właściciela w zapisie) — domyślnie gość.
    await db.insert('weld_quotes', {
      ...quote('legacy').toRow(netGrosze: 0, grossGrosze: 0),
    });
    expect((await WeldQuoteDao().listAll()).map((q) => q.id), ['legacy']);
    await signIn('a');
    expect(await WeldQuoteDao().listAll(), isEmpty);
    expect(await WeldQuoteDao().byId('legacy'), isNull);
  });

  test('accounts see only their own offers and cannot overwrite others',
      () async {
    await signIn('a');
    await WeldQuoteDao().save(quote('q1', client: 'A-client'));
    await signIn('b');
    expect(await WeldQuoteDao().listAll(), isEmpty);
    await expectLater(WeldQuoteDao().save(quote('q1', client: 'B-steal')),
        throwsA(isA<AccountException>()));
    await WeldQuoteDao().softDelete('q1');
    await signIn('a');
    final mine = await WeldQuoteDao().listAll();
    expect(mine.single.client, 'A-client',
        reason: 'B nie nadpisał ani nie usunął oferty A');
  });

  test('numbering counts only the owner offers', () async {
    await signIn('a');
    final a1 = await WeldQuoteDao().insertNewDraft(quote('a1'));
    final a2 = await WeldQuoteDao().insertNewDraft(quote('a2'));
    await signIn('b');
    final b1 = await WeldQuoteDao().insertNewDraft(quote('b1'));
    expect(a1.number, isNot(a2.number));
    expect(b1.number, a1.number, reason: 'B zaczyna własną numerację');
  });

  test('undo of an assistant draft works for the owner only', () async {
    await signIn('a');
    final saved = await WeldQuoteDao().insertNewDraft(quote('d1'));
    await signIn('b');
    expect(await WeldQuoteDao().softDeleteIfUnchanged(saved), isFalse);
    await signIn('a');
    expect(await WeldQuoteDao().softDeleteIfUnchanged(saved), isTrue);
    expect(await WeldQuoteDao().listAll(), isEmpty);
  });
}
