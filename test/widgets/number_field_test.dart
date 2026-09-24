// Numeric input for gloved hands on iOS and Android.
//
// `TextInputType.number` opens the iOS number pad, which has NO decimal key
// and NO comma — 60,3 / 114,3 / 76,2 could not be typed at all (audit
// 2026-08-29: ~67 such fields). This file guards the shared fix in
// `lib/widgets/number_field.dart` + `lib/utils/decimal_parse.dart`:
//
//   * parseDecimal — the one parser (comma == dot, white space ignored);
//   * NumberInputFormatter — digits , . (and - when signed), everything else
//     refused as a whole edit instead of silently cut out;
//   * a source-level sweep of lib/: no numeric field may use the bare keypad,
//     every numeric keyboard comes from the helper, every field with it has a
//     formatter, and nobody re-rolls `double.tryParse(x.replaceAll(',', '.'))`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/widgets/number_field.dart';

/// Files the sweep does not police, each with the reason. Files marked
/// "NIE ruszaj" belong to branches worked on in parallel (weld journal,
/// welder identity / WPQR / new WPS & qualification screens, chat, profile,
/// premium, AI chat, API client, legal texts, db.dart) — they were left
/// untouched on purpose. AFTER MERGING those branches, switch their numeric
/// fields to numberKeyboard()/numberInputFormatters()/parseDecimal and
/// delete the entry here.
const Map<String, String> _exempt = {
  'lib/widgets/number_field.dart':
      'the one place allowed to build the numeric keyboard',
  // NIE ruszaj — OD / t fields at weld_journal_screen.dart ~1142 / ~1149 use
  // TextInputType.numberWithOptions(decimal: true) + their own [0-9.,]
  // filter, and weldJournal parses with its own replaceAll(',', '.').
  'lib/screens/weld_journal_screen.dart':
      'NIE ruszaj (dziennik spoin) — 2 pola OD/t do przepięcia po scaleniu',
  'lib/screens/coupon_log_screen.dart': 'NIE ruszaj (dziennik spoin)',
  'lib/services/weld_journal_export.dart': 'NIE ruszaj (dziennik spoin)',
  'lib/widgets/wpqr_chip.dart': 'NIE ruszaj (uprawnienia / WPQR)',
  'lib/screens/profile_screen.dart': 'NIE ruszaj (profil)',
  'lib/services/api_client.dart': 'NIE ruszaj',
  'lib/legal/legal_texts.dart': 'NIE ruszaj',
  'lib/database/db.dart': 'NIE ruszaj',
};

/// Name fragments of the other "NIE ruszaj" files (welder_identity*,
/// chat_*, premium_*, ai_chat_*). New WPS / qualification screens from the
/// parallel branch are NOT listed: when they arrive with a bare keypad this
/// test fails after the merge — which is exactly the reminder intended.
const Map<String, String> _exemptFragments = {
  'welder_identity': 'NIE ruszaj (tożsamość spawacza)',
  'chat_': 'NIE ruszaj (czat)',
  'premium_': 'NIE ruszaj (premium)',
  'ai_chat_': 'NIE ruszaj (czat AI)',
};

bool _isExempt(String path) =>
    _exempt.containsKey(path) ||
    _exemptFragments.keys.any((f) => path.split('/').last.contains(f));

/// Every Dart source under lib/, path normalised to forward slashes.
Map<String, String> _sources() {
  final out = <String, String>{};
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) {
      out[e.path.replaceAll(r'\', '/')] = e.readAsStringSync();
    }
  }
  return out;
}

// ── A tiny Dart lexer: enough to skip strings / comments and find the
//    closing paren of a call, so a check can look at ONE TextField's
//    arguments and not at its neighbours'. ─────────────────────────────────

int _skipString(String s, int i) {
  final raw = i > 0 && s[i - 1] == 'r';
  final q = s[i];
  final triple = s.startsWith(q * 3, i);
  final quote = triple ? q * 3 : q;
  var j = i + quote.length;
  while (j < s.length) {
    if (!raw && s[j] == r'\') {
      j += 2;
      continue;
    }
    if (!raw && s.startsWith(r'${', j)) {
      j = _scanBalanced(s, j + 2);
      continue;
    }
    if (s.startsWith(quote, j)) return j + quote.length;
    j++;
  }
  return j;
}

/// Index just past the bracket closing the one open before [j].
int _scanBalanced(String s, int j) {
  var depth = 0;
  while (j < s.length) {
    if (s.startsWith('//', j)) {
      final nl = s.indexOf('\n', j);
      if (nl < 0) return s.length;
      j = nl;
      continue;
    }
    if (s.startsWith('/*', j)) {
      j = s.indexOf('*/', j) + 2;
      continue;
    }
    final c = s[j];
    if (c == "'" || c == '"') {
      j = _skipString(s, j);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return j + 1;
      depth--;
    }
    j++;
  }
  return j;
}

/// Source with `//` line comments blanked out (strings are left alone, a
/// `//` inside one is rare in this code base and only makes the check
/// stricter). Doc comments mention `TextInputType.number` on purpose.
String _withoutLineComments(String s) =>
    s.split('\n').map((l) {
      final i = l.indexOf('//');
      if (i < 0) return l;
      // Keep `//` that sits inside a string literal on this line.
      final before = l.substring(0, i);
      final quotes = "'".allMatches(before).length;
      return quotes.isOdd ? l : before;
    }).join('\n');

int _line(String s, int offset) => '\n'.allMatches(s.substring(0, offset)).length + 1;

void main() {
  group('parseDecimal', () {
    test('comma and dot are the same decimal separator', () {
      expect(parseDecimal('60,3'), 60.3);
      expect(parseDecimal('60.3'), 60.3);
      expect(parseDecimal('114,3'), 114.3);
      expect(parseDecimal('114.30'), 114.3);
      expect(parseDecimal('76,2'), 76.2);
    });

    test('white space anywhere is ignored, incl. non-breaking spaces', () {
      expect(parseDecimal(' 114,3 '), 114.3);
      expect(parseDecimal('1 234,5'), 1234.5);
      expect(parseDecimal('\u00A0114,3\u202F'), 114.3);
      expect(parseDecimal('\t2,77\n'), 2.77);
    });

    test('signs, including the Unicode minus', () {
      expect(parseDecimal('-5'), -5);
      expect(parseDecimal('\u22125,5'), -5.5);
      expect(parseDecimal('+7'), 7);
    });

    test('garbage, empty and non-finite give null — never a silent 0', () {
      for (final bad in [
        null,
        '',
        '   ',
        'abc',
        '1,2,3',
        '12..3',
        '60,3 mm',
        'NaN',
        'Infinity',
        '-Infinity',
        '1e309',
        '9' * 400,
      ]) {
        expect(parseDecimal(bad), isNull, reason: 'input: $bad');
      }
    });

    test('the one parser replaces every hand-rolled copy', () {
      // Same answers the old `double.tryParse(x.replaceAll(',', '.'))`
      // gave for everything a numeric keypad can produce.
      for (final s in ['0', '0,5', '12', '12.75', ',5', '5,', '1000,0']) {
        expect(parseDecimal(s), double.tryParse(s.replaceAll(',', '.')),
            reason: s);
      }
    });
  });

  group('numberKeyboard', () {
    test('decimal pad by default — never the bare number pad', () {
      expect(numberKeyboard(),
          const TextInputType.numberWithOptions(decimal: true));
      expect(numberKeyboard(), isNot(TextInputType.number));
      expect(numberKeyboard().decimal, isTrue);
      expect(numberKeyboard().signed, isFalse);
    });

    test('signed only on request; counts get a pad without decimals', () {
      expect(numberKeyboard(signed: true).signed, isTrue);
      expect(numberKeyboard(signed: true).decimal, isTrue);
      expect(numberKeyboard(decimal: false),
          const TextInputType.numberWithOptions(decimal: false));
    });
  });

  group('NumberInputFormatter', () {
    TextEditingValue v(String text) => TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));

    String edit(TextInputFormatter f, String from, String to) =>
        f.formatEditUpdate(v(from), v(to)).text;

    test('decimal: digits, comma and dot pass', () {
      final f = numberInputFormatters().single;
      expect(edit(f, '', '60,3'), '60,3');
      expect(edit(f, '', '114.3'), '114.3');
      expect(edit(f, '60', '60,'), '60,');
    });

    test('anything else refuses the whole edit instead of trimming it', () {
      final f = numberInputFormatters().single;
      expect(edit(f, '', 'abc'), '');
      expect(edit(f, '12', '12a'), '12', reason: 'a typed letter is ignored');
      expect(edit(f, '', '1e5'), '', reason: 'trimming would give 15');
      expect(edit(f, '', '2 1/2'), '', reason: 'trimming would give 212');
      expect(edit(f, '7', '-10'), '7',
          reason: 'an unsigned field must not turn -10 into 10');
    });

    test('white space from a paste is dropped, cursor kept in place', () {
      final f = numberInputFormatters().single;
      final out = f.formatEditUpdate(
        v(''),
        const TextEditingValue(
          text: ' 114,3 ',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(out.text, '114,3');
      expect(out.selection.baseOffset, 5);
    });

    test('signed fields take - and read the Unicode minus as -', () {
      final f = numberInputFormatters(signed: true).single;
      expect(edit(f, '', '-10'), '-10');
      expect(edit(f, '', '\u221215,5'), '-15,5');
    });

    test('integer fields take digits only', () {
      final f = numberInputFormatters(decimal: false).single;
      expect(edit(f, '', '12'), '12');
      expect(edit(f, '12', '12,5'), '12');
      expect(edit(f, '12', '12.'), '12');
    });

    test('an odd programmatic value can still be corrected', () {
      final f = numberInputFormatters().single;
      // Nothing forbidden is ADDED by deleting — the edit goes through.
      expect(edit(f, '1e-7', '1e-'), '1e-');
      expect(edit(f, '1e-', '1e'), '1e');
      expect(edit(f, '1e', '1'), '1');
      // …but the odd value cannot grow.
      expect(edit(f, '1e', '1ex'), '1e');
    });

    testWidgets('a real TextField keeps the comma the Polish pad types',
        (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: ctrl,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), '60,3');
      expect(ctrl.text, '60,3');
      expect(parseDecimal(ctrl.text), 60.3);

      await tester.enterText(find.byType(TextField), '1e5');
      expect(ctrl.text, '60,3', reason: 'the paste is refused, not trimmed');
    });
  });

  group('source sweep of lib/ (every numeric field)', () {
    final sources = _sources();

    test('lib/ is where the test expects it', () {
      expect(sources.keys, contains('lib/widgets/number_field.dart'));
      expect(sources.length, greaterThan(50));
    });

    test('no field uses the bare TextInputType.number keypad', () {
      final bare = RegExp(r'TextInputType\.number(?!WithOptions)');
      final offenders = <String>[];
      sources.forEach((path, src) {
        if (_isExempt(path)) return;
        final code = _withoutLineComments(src);
        for (final m in bare.allMatches(code)) {
          offenders.add('$path:${_line(code, m.start)}');
        }
      });
      expect(offenders, isEmpty,
          reason: 'TextInputType.number has no decimal key and no comma on '
              'iOS — 60,3 cannot be typed. Use numberKeyboard() '
              '(or numberKeyboard(decimal: false) for counts).');
    });

    test('every numeric keyboard comes from numberKeyboard()', () {
      final direct = RegExp(r'TextInputType\s*\.\s*numberWithOptions');
      final offenders = <String>[];
      sources.forEach((path, src) {
        if (_isExempt(path)) return;
        final code = _withoutLineComments(src);
        for (final m in direct.allMatches(code)) {
          offenders.add('$path:${_line(code, m.start)}');
        }
      });
      expect(offenders, isEmpty,
          reason: 'build numeric keyboards with numberKeyboard() from '
              'widgets/number_field.dart so the keyboard, the filter and the '
              'parser stay one rule');
    });

    test('every field with a numeric keyboard also has an input filter', () {
      final start = RegExp(r'\b(TextField|TextFormField)\(');
      final offenders = <String>[];
      var checked = 0;
      sources.forEach((path, src) {
        if (_isExempt(path)) return;
        for (final m in start.allMatches(src)) {
          // A `TextField(` mentioned in a comment is not a call.
          final lineStart = src.lastIndexOf('\n', m.start) + 1;
          if (src.substring(lineStart, m.start).contains('//')) continue;
          final end = _scanBalanced(src, m.end);
          final args = src.substring(m.end, end - 1);
          if (!args.contains('numberKeyboard(')) continue;
          checked++;
          if (!args.contains('inputFormatters:')) {
            offenders.add('$path:${_line(src, m.start)}');
          }
        }
      });
      expect(checked, greaterThan(60),
          reason: 'the sweep must actually see the ~70 numeric fields');
      expect(offenders, isEmpty,
          reason: 'pair numberKeyboard() with numberInputFormatters() (or '
              'isoExpressionInputFormatters() for an ISO expression)');
    });

    test('nobody re-rolls the comma parser', () {
      final handRolled = RegExp(
          r"double\.(?:try)?[pP]arse\([^;]*?replaceAll\(\s*','\s*,\s*'\.'\s*\)");
      final offenders = <String>[];
      sources.forEach((path, src) {
        if (_isExempt(path) || path == 'lib/utils/decimal_parse.dart') return;
        final code = _withoutLineComments(src);
        for (final m in handRolled.allMatches(code)) {
          offenders.add('$path:${_line(code, m.start)}');
        }
      });
      expect(offenders, isEmpty,
          reason: 'use parseDecimal() — one rule for comma, dot and spaces');
    });

    test('the exemption list names real files', () {
      for (final path in _exempt.keys) {
        expect(File(path).existsSync(), isTrue,
            reason: '$path is exempt but does not exist — drop the entry');
      }
    });
  });
}
