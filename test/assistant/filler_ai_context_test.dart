import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/features/filler/filler_selector_page.dart';
import 'package:cut_list_app/services/premium_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show say, settle;

void main() {
  useGuestAccount();
  useTestDatabase();
  testWidgets('AI receives visible gas selection and its warning', (t) async {
    final requests=<Map>[];
    await http.runWithClient(() async {
      await mount(t, home:const FillerSelectorPage(),
          interpret: (_) async => throw StateError('Not a command'));
      PremiumService.instance.resetForTest();
      expect(await ToolBridge.instance.current!.apply(
          {'material_a':'ss316L','material_b':'ss316L','process':'tig'}),isEmpty);
      await settle(t);
      await say(t,'Dlaczego taki gaz osłonowy?');
      expect(requests,hasLength(1));
      final payload=requests.single['calculator_context'] as Map;
      expect(payload['tool_id'],'filler_selector');
      expect(payload['inputs'],{'material_a':'ss316L','material_b':'ss316L','process':'tig'});
      final results=payload['results'] as Map;
      expect(results['gas_status'],'available');
      expect(results['shielding_gases'],contains('I1'));
      expect(results['consumables'],contains('316'));
      expect(results['warnings'],contains('WPS'));
      expect(find.textContaining('Testowa odpowiedź o wybranym gazie'),findsWidgets);
      expect(t.takeException(),isNull);
    }, () => MockClient((r) async {
      if (!r.url.path.endsWith('/ai/chat')) throw StateError('Unexpected request');
      requests.add(jsonDecode(r.body) as Map);
      return http.Response(jsonEncode({'text':'Testowa odpowiedź o wybranym gazie',
        'calculator_context_used':true}),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });
  testWidgets('changing the selection while AI responds discards stale advice', (t) async {
    final pending=Completer<http.Response>();
    var requests=0;
    await http.runWithClient(() async {
      await mount(t,home:const FillerSelectorPage(),
          interpret: (_) async => throw StateError('Not a command'));
      PremiumService.instance.resetForTest();
      final input=find.byKey(const Key('assistant-command'));
      await t.enterText(input,'Dlaczego taki gaz osłonowy?');
      await t.tap(find.byKey(const Key('assistant-go')));
      for(var i=0;i<30 && requests==0;i++) { await t.pump(const Duration(milliseconds:100)); }
      expect(requests,1);
      expect(await ToolBridge.instance.current!.apply(
          {'material_a':'duplex2205','material_b':'duplex2205','process':'tig'}),isEmpty);
      await t.pump();
      pending.complete(http.Response(jsonEncode({'text':'Stara porada',
        'calculator_context_used':true}),200,headers:{'content-type':'application/json; charset=utf-8'}));
      await settle(t);
      expect(find.textContaining('Kalkulator lub dane zmieniły się'),findsWidgets);
      expect(find.textContaining('Stara porada'),findsNothing);
      expect(t.takeException(),isNull);
    }, () => MockClient((r) {
      if (!r.url.path.endsWith('/ai/chat')) throw StateError('Unexpected request');
      requests++;
      return pending.future;
    }));
  });
}
