import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/widgets/account_session_popup.dart';

void main() {
  for (final sheet in [false, true]) {
    testWidgets(
        'private ${sheet ? 'sheet' : 'dialog'} closes on session change without closing login route above it',
        (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      final account = AccountService.forTesting(MockClient((r) async {
        final id = jsonDecode(r.body)['email'];
        return http.Response(
            jsonEncode({
              'token': 'fixture-$id',
              'account': {'id': id}
            }),
            200);
      }));
      AccountService.instance = account;
      await t.runAsync(() => account.signIn('A', 'fixture-password'));
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
          navigatorKey: nav,
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () {
                        Widget builder(BuildContext context) =>
                            const AlertDialog(content: Text('Private A title'));
                        if (sheet) {
                          unawaited(showOwnerBoundBottomSheet<void>(
                              context: context, builder: builder));
                        } else {
                          unawaited(showOwnerBoundDialog<void>(
                              context: context, builder: builder));
                        }
                      },
                      child: const Text('Open'))))));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(find.text('Private A title'), findsOneWidget);
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Account page')))));
      await t.pumpAndSettle();
      await t.runAsync(() => account.signIn('B', 'fixture-password'));
      await t.pump();
      await t.pumpAndSettle();
      expect(find.text('Account page'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('Private A title'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
