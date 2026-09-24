// open_tool: zapytanie z polecenia → wpis rejestru narzędzi.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/assistant_parser.dart';
import 'package:cut_list_app/assistant/assistant_tools.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';

String? _open(String sentence, [AppLanguage lang = AppLanguage.pl]) {
  final p = parseAssistantCommand(sentence);
  final q = p.fields['query'] as String?;
  if (q == null) return null;
  return resolveToolQuery(q, lang)?.id;
}

void main() {
  test('polecenia PL trafiają w narzędzia', () {
    expect(_open('Otwórz kalkulator heat input'), 'heat_input');
    expect(_open('Pokaż szablon siodła'), 'saddle_template');
    expect(_open('Otwórz dziennik spoin'), 'weld_journal');
    expect(_open('Proszę, włącz mi konwerter jednostek'), 'unit_converter');
    expect(_open('Otwórz moment śrub'), 'bolt_torque');
  });

  test('polecenia EN trafiają w narzędzia', () {
    expect(_open('Open heat input', AppLanguage.en), 'heat_input');
    expect(_open('Show me the bolt torque calculator', AppLanguage.en),
        'bolt_torque');
  });

  test('asystent nie otwiera sam siebie, bełkot → nic', () {
    expect(resolveToolQuery('asystent', AppLanguage.pl), isNull);
    expect(resolveToolQuery('xyzqq', AppLanguage.pl), isNull);
  });

  test('asystent ma wpis w rejestrze bez bramki konta', () {
    final t = toolById(kAssistantToolId);
    expect(t, isNotNull);
    expect(t!.needsAccount, isFalse,
        reason: 'tryb „Wykonaj" działa offline i bez zgody');
    expect(searchTools('asystent', AppLanguage.pl).first.tool.id,
        kAssistantToolId);
  });
}
