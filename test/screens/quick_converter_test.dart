import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/quick_converter_screen.dart';
import 'package:cut_list_app/utils/clipboard_helper.dart';

Widget _app(
        {AppLanguage language = AppLanguage.pl,
        double scale = 1,
        Brightness brightness = Brightness.light}) =>
    AppLanguageScope(
      controller: AppLanguageController(language),
      child: MaterialApp(
        theme:
            ThemeData(colorSchemeSeed: Colors.orange, brightness: brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: child!),
        home: const QuickConverterScreen(),
      ),
    );

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  await _tap(tester, find.widgetWithText(Tab, label));
}

Future<void> _enter(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.pumpAndSettle();
}

Future<void> _unit(WidgetTester tester, String unit) async {
  await _tap(tester, find.byType(DropdownButtonFormField<String>));
  await tester.tap(find.text(unit).last);
  await tester.pumpAndSettle();
}

Finder _result(String unit) =>
    find.byWidgetPredicate((w) => w is CopyOnLongPress && w.label == unit);

String _value(WidgetTester tester, String unit) =>
    tester.widget<CopyOnLongPress>(_result(unit)).value;

void main() {
  testWidgets('landscape layout remains usable with enlarged text and validation', (tester) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(scale: 2));
    await _tab(tester, 'Temperatura');
    await _enter(tester, '-273.16');
    expect(tester.widget<TextField>(find.byType(TextField)).decoration!.errorText, isNotNull);
    await _tap(tester, find.text('Pokaż jak'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'millimetre to metre conversion preserves sub-millimetre precision',
      (tester) async {
    await tester.pumpWidget(_app());
    await _enter(tester, '25.4');
    expect(double.parse(_value(tester, 'm')), closeTo(.0254, 0.0000001));
  });
  for (final sample in [
    ('32', '0.000'),
    ('-40', '-40.000'),
    ('212', '100.000')
  ]) {
    testWidgets('${sample.$1} Fahrenheit converts to exact Celsius reference',
        (tester) async {
      await tester.pumpWidget(_app());
      await _tab(tester, 'Temperatura');
      await _unit(tester, '°F');
      await _enter(tester, sample.$1);
      expect(_value(tester, '°C'), sample.$2);
    });
  }

  testWidgets('each tab keeps its input and selected unit while switching',
      (tester) async {
    await tester.pumpWidget(_app());
    await _unit(tester, 'in');
    await _enter(tester, '2');
    await _tab(tester, 'Przepływ gazu');
    await _enter(tester, '10');
    await _tab(tester, 'Długość');
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '2');
    expect(_value(tester, 'mm'), '50.800');
  });

  for (final sample in [
    ('12000.25', '12000.250'),
    ('0.00001', '1.000000e-5')
  ]) {
    testWidgets('length preserves useful precision for ${sample.$1}',
        (tester) async {
      await tester.pumpWidget(_app());
      await _enter(tester, sample.$1);
      expect(_value(tester, 'mm'), sample.$2);
    });
  }

  testWidgets('25,4 mm converts to 1 inch and guide follows the current input',
      (tester) async {
    await tester.pumpWidget(_app());
    await _enter(tester, '25,4');
    expect(_value(tester, 'in (")'), '1.000');
    await _tap(tester, find.text('Pokaż jak'));
    expect(find.textContaining('25.4 / 25.4 = 1.000 in'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await _enter(tester, '50,8');
    expect(_value(tester, 'in (")'), '2.000');
    expect(find.textContaining('50.8 / 25.4 = 2.000 in'), findsOneWidget);
  });

  for (final tab in ['Długość', 'Ciśnienie', 'Przepływ gazu']) {
    testWidgets('$tab preserves a negative paste and blocks its results',
        (tester) async {
      await tester.pumpWidget(_app());
      await _tab(tester, tab);
      await _enter(tester, '-10');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '-10');
      expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .errorText,
          isNotNull);
      expect(find.byType(CopyOnLongPress), findsNothing);
    });
  }

  for (final tab in ['Długość', 'Temperatura', 'Ciśnienie', 'Przepływ gazu']) {
    for (final bad in ['12..3', '9' * 310]) {
      testWidgets(
          '$tab rejects ${bad.length > 20 ? 'overflow' : bad} with a field error',
          (tester) async {
        await tester.pumpWidget(_app());
        await _tab(tester, tab);
        await _enter(tester, bad);
        expect(find.byType(CopyOnLongPress), findsNothing);
        expect(
            tester
                .widget<TextField>(find.byType(TextField))
                .decoration!
                .errorText,
            isNotNull);
      });
    }
  }

  for (final sample in [('°C', '-273.16'), ('°F', '-459.68'), ('K', '-0.01')]) {
    testWidgets('temperature below absolute zero in ${sample.$1} is rejected',
        (tester) async {
      await tester.pumpWidget(_app());
      await _tab(tester, 'Temperatura');
      await _unit(tester, sample.$1);
      await _enter(tester, sample.$2);
      expect(find.byType(CopyOnLongPress), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .errorText,
          isNotNull);
    });
  }

  for (final sample in [('°C', '-273.15'), ('°F', '-459.67'), ('K', '0')]) {
    testWidgets('absolute zero is accepted in ${sample.$1}', (tester) async {
      await tester.pumpWidget(_app());
      await _tab(tester, 'Temperatura');
      await _unit(tester, sample.$1);
      await _enter(tester, sample.$2);
      expect(double.parse(_value(tester, 'K')), 0);
      expect(double.parse(_value(tester, '°C')), closeTo(-273.15, .06));
      expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .errorText,
          isNull);
    });
  }

  testWidgets('pressure MPa converts to bar and clear resets the visible unit',
      (tester) async {
    await tester.pumpWidget(_app());
    await _tab(tester, 'Ciśnienie');
    await _unit(tester, 'MPa');
    await _enter(tester, '2');
    expect(_value(tester, 'bar'), '20.000');
    await _tap(tester, find.byTooltip('Wyczyść'));
    final dropdown = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(dropdown.value, 'bar');
    expect(find.byType(CopyOnLongPress), findsNothing);
    await _enter(tester, '2');
    expect(_value(tester, 'MPa'), '0.200');
  });

  // NIST SP 811 App. B: 1 kgf/cm² = 98 066,5 Pa (dokładnie) = 0,980665 bar;
  // 1 bar = 1000 mbar. 10 kgf/cm² → 9,807 bar; 50 mbar → 0,050 bar.
  testWidgets('kgf/cm² (at) i mbar dla starych manometrów i prób gazowych',
      (tester) async {
    await tester.pumpWidget(_app());
    await _tab(tester, 'Ciśnienie');
    await _unit(tester, 'kgf/cm²');
    await _enter(tester, '10');
    expect(_value(tester, 'bar'), '9.807');
    await _unit(tester, 'mbar');
    await _enter(tester, '50');
    expect(_value(tester, 'bar'), '0.050');
    expect(_value(tester, 'kPa'), '5.000');
  });

  testWidgets('conversion overflow is not exposed as a copyable pressure',
      (tester) async {
    await tester.pumpWidget(_app());
    await _tab(tester, 'Ciśnienie');
    await _unit(tester, 'MPa');
    await _enter(tester, '1${'0' * 307}');
    expect(find.byType(CopyOnLongPress), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
        isNotNull);
  });

  testWidgets(
      'flow never silently equates actual and standard reference conditions',
      (tester) async {
    await tester.pumpWidget(_app());
    await _tab(tester, 'Przepływ gazu');
    await _unit(tester, 'cfh');
    await _enter(tester, '60');
    expect(_value(tester, 'l/min'), '28.317');
    expect(_result('slpm'), findsNothing);
    expect(_result('scfh'), findsNothing);
    await _unit(tester, 'scfh');
    expect(_value(tester, 'slpm'), '28.317');
    expect(_result('l/min'), findsNothing);
    expect(_result('cfh'), findsNothing);
  });

  testWidgets('result can be copied using an explicit accessible action',
      (tester) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(_app());
    await _enter(tester, '25.4');
    await _tap(tester, find.byTooltip('Kopiuj in (")'));
    expect(copied, ['1.000']);
  });

  for (final brightness in Brightness.values) {
    testWidgets('all four English tabs fit large text in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          _app(language: AppLanguage.en, scale: 2, brightness: brightness));
      for (final tab in ['Length', 'Temperature', 'Pressure', 'Gas flow']) {
        await _tab(tester, tab);
        await _enter(tester, '1234567.89');
        await _tap(tester, find.text('Show how'));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
