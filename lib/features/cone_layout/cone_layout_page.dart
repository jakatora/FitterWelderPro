// Rozwinięcie stożka i przejść — dla kotlarza, który wycina z blachy lej,
// stożek albo przejście kwadrat–koło: wymiary do trasowania (promienie,
// kąt, cięciwy, strzałki, linie prawdziwe triangulacji, współrzędne
// punktów), podgląd rozwinięcia, podział na części, rzędne od cięciwy
// (gdy cyrkiel za krótki) i szablon 1:1 do druku na kartkach A4/A3.
//
// Matematyka: lib/domain/fitter/cone_development.dart
// i lib/domain/fitter/transition_development.dart (czysty Dart, z testami).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../domain/fitter/cone_development.dart';
import '../../domain/fitter/cone_assistant_input.dart';
import '../../domain/fitter/eccentric_cone_assistant_input.dart';
import '../../domain/fitter/transition_assistant_input.dart';
import '../../assistant/core/tool_bridge.dart';
import '../../services/account_service.dart';
import '../../assistant/core/skill.dart' show AssistantText, ModuleActionResult;
import '../../domain/fitter/transition_development.dart';
import '../../domain/quotes/quote_calculator.dart' show formatQty;
import '../../i18n/app_language.dart';
import '../../services/wrap_template_pdf.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef ConeShareText = Future<void> Function(String text, String subject);

/// Zbudowanie i udostępnienie PDF szablonu — wstrzykiwane w testach.
typedef ConeSharePdf = Future<void> Function(
    FlatTemplateSpec spec, String fileName, bool english);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Future<void> _defaultSharePdf(
    FlatTemplateSpec spec, String fileName, bool english) async {
  final bytes = await buildFlatTemplatePdf(
    spec,
    font: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
    en: english,
    generatedAt: DateTime.now(),
  );
  if (kIsWeb) {
    await Share.shareXFiles([
      XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
    ]);
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
      subject: english ? 'Flat pattern template' : 'Szablon rozwinięcia');
}

/// Największy wymiar części, przy którym proponujemy wydruk 1:1, mm.
const double kConeMaxPrintMm = 2000;

enum ConeShape { concentric, eccentric, transition }

class ConeLayoutPage extends StatefulWidget {
  const ConeLayoutPage({
    super.key,
    this.shareText = _defaultShareText,
    this.sharePdf = _defaultSharePdf,
  });

  final ConeShareText shareText;
  final ConeSharePdf sharePdf;

  @override
  State<ConeLayoutPage> createState() => _ConeLayoutPageState();
}

class _ConeLayoutPageState extends State<ConeLayoutPage>
    with ToolHandleHost<ConeLayoutPage>
    implements InputToolHandle, ModuleActionHandle {
  @override
  String get toolId => 'cone_layout';
  @override
  Set<String> get supportedFields => {
        ...ConeAssistantInput.fields,
        ...EccentricConeAssistantInput.fields,
        ...TransitionAssistantInput.fields
      };
  @override
  Map<String, Object?> get inputFields => Map.unmodifiable({
        'shape': _shape.name,
        if (_shape == ConeShape.transition) ...{
          'side_a_mm': _mmOf(_a),
          'side_b_mm': _mmOf(_b),
          'diameter_mm': _mmOf(_dT),
          'height_mm': _mmOf(_hT),
          'offset_x_mm': _ex.text.trim().isEmpty ? 0 : _mmOf(_ex),
          'offset_y_mm': _ey.text.trim().isEmpty ? 0 : _mmOf(_ey),
          'thickness_mm': _mmOf(_t),
          'reference': _ref.name,
          'parts': _parts,
          'divisions': _div,
          'seam': _seam.name,
        },
        if (_shape == ConeShape.eccentric) ...{
          'mode': 'height',
          'large_dia_mm': _mmOf(_dL),
          'small_dia_mm': _mmOf(_dS),
          'height_mm': _mmOf(_h),
          'thickness_mm': _mmOf(_t),
          'reference': _ref.name,
          'parts': _parts,
          'divisions': _div,
          'vertical_side': _vertical,
          if (!_vertical) 'offset_mm': _mmOf(_e),
          'seam_on_short_side': _seamShort,
        },
        if (_shape == ConeShape.concentric) ...{
          'mode': _mode.name,
          'large_dia_mm': _mmOf(_dL),
          'small_dia_mm': _mmOf(_dS),
          'thickness_mm': _mmOf(_t),
          'reference': _ref.name,
          'parts': _coneParts,
          'allowance_mm': _mmOf(_allow),
          switch (_mode) {
            ConeSizeMode.height => 'height_mm',
            ConeSizeMode.halfAngle => 'half_angle_deg',
            ConeSizeMode.slant => 'slant_mm',
          }: switch (_mode) {
            ConeSizeMode.height => _mmOf(_h),
            ConeSizeMode.halfAngle => parseDecimal(_alpha.text),
            ConeSizeMode.slant => _mmOf(_slant),
          },
        },
      });
  @override
  void initState() {
    super.initState();
    markReady();
  }

  final _undoHistory = <(Map<String, Object?>, VoidCallback)>[];
  AccountService? _undoAccount;
  int _undoAccountRevision = -1;
  int _manualEditRevision = 0;

  void _syncUndoSession() {
    final account = AccountService.instance;
    if (!identical(account, _undoAccount) ||
        account.sessionRevision != _undoAccountRevision) {
      _undoHistory.clear();
      _undoAccount = account;
      _undoAccountRevision = account.sessionRevision;
    }
  }

  void _manualChange(VoidCallback change) {
    _undoHistory.clear();
    _manualEditRevision++;
    setState(change);
  }

  void _validateSnapshot(Map<String, Object?> fields) {
    switch (fields['shape']) {
      case 'concentric':
        ConeAssistantInput.fromFields(fields);
      case 'eccentric':
        EccentricConeAssistantInput.fromFields(fields);
      case 'transition':
        TransitionAssistantInput.fromFields(fields);
      default:
        throw const FormatException('unknown development');
    }
  }

  VoidCallback _captureGeometryRestore() {
    final controllers = [
      _dL,
      _dS,
      _h,
      _alpha,
      _slant,
      _t,
      _allow,
      _e,
      _a,
      _b,
      _dT,
      _hT,
      _ex,
      _ey
    ];
    final texts = controllers.map((c) => c.text).toList();
    final settings = (
      _shape,
      _mode,
      _ref,
      _coneParts,
      _parts,
      _div,
      _vertical,
      _seamShort,
      _seam,
      _viewPart
    );
    return () => setState(() {
          for (var i = 0; i < controllers.length; i++) {
            controllers[i].text = texts[i];
          }
          _shape = settings.$1;
          _mode = settings.$2;
          _ref = settings.$3;
          _coneParts = settings.$4;
          _parts = settings.$5;
          _div = settings.$6;
          _vertical = settings.$7;
          _seamShort = settings.$8;
          _seam = settings.$9;
          _viewPart = settings.$10;
        });
  }

  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    _syncUndoSession();
    final account = AccountService.instance, session = account.sessionRevision;
    final manual = _manualEditRevision;
    final before = Map<String, Object?>.of(inputFields);
    VoidCallback? restore;
    try {
      _validateSnapshot(before);
      restore = _captureGeometryRestore();
    } on FormatException {/* An invalid previous form is not an undo target. */}
    final rejected = await _applyFields(fields);
    if (rejected.isEmpty &&
        mounted &&
        restore != null &&
        manual == _manualEditRevision &&
        identical(account, AccountService.instance) &&
        session == account.sessionRevision) {
      final after = Map<String, Object?>.of(inputFields);
      if (!mapEquals(before, after)) {
        _undoHistory.add((after, restore));
        if (_undoHistory.length > 20) {
          _undoHistory.removeAt(0);
        }
      }
    }
    return rejected;
  }

  ModuleActionResult _undoDevelopment() {
    _syncUndoSession();
    if (_undoHistory.isEmpty) {
      return const ModuleActionResult(
          false,
          AssistantText('Brak zmiany asystenta do cofnięcia w tym rozwinięciu.',
              'There is no assistant change to undo in this development.'));
    }
    final last = _undoHistory.last;
    if (!mapEquals(last.$1, inputFields)) {
      _undoHistory.clear();
      return const ModuleActionResult(
          false,
          AssistantText(
              'Dane zostały zmienione ręcznie. Nie nadpiszę ich cofnięciem.',
              'Inputs were changed manually. Undo will not overwrite them.'));
    }
    _undoHistory.removeLast();
    last.$2();
    return const ModuleActionResult(
        true,
        AssistantText('Cofnięto ostatnią zmianę asystenta w rozwinięciu.',
            'Undid the last assistant change in the development.'));
  }

  Future<Set<String>> _applyFields(Map<String, Object?> fields) async {
    if (fields['shape'] == 'transition') return _applyTransition(fields);
    if (fields['shape'] == 'eccentric') return _applyEccentric(fields);
    ConeAssistantInput parsed;
    try {
      parsed = ConeAssistantInput.fromFields(fields);
    } on FormatException {
      return fields.keys.isEmpty ? {'shape'} : fields.keys.toSet();
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return fields.keys.toSet();
    }
    final i = parsed.input;
    // Preserve the selected display unit; canonical payload values are mm.
    String length(double mm) => (mm / _scale).toString();
    setState(() {
      _shape = ConeShape.concentric;
      _mode = i.mode;
      _ref = i.ref;
      _coneParts = i.parts;
      _dL.text = length(i.largeDiaMm);
      _dS.text = length(i.smallDiaMm);
      _t.text = length(i.thicknessMm);
      _allow.text = length(i.allowanceMm);
      switch (i.mode) {
        case ConeSizeMode.height:
          _h.text = length(i.heightMm);
        case ConeSizeMode.halfAngle:
          _alpha.text = i.halfAngleDeg.toString();
        case ConeSizeMode.slant:
          _slant.text = length(i.slantMm);
      }
    });
    return {};
  }

  Future<Set<String>> _applyEccentric(Map<String, Object?> fields) async {
    EccentricConeAssistantInput parsed;
    try {
      parsed = EccentricConeAssistantInput.fromFields(fields);
    } on FormatException {
      return fields.keys.toSet();
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return fields.keys.toSet();
    }
    final i = parsed.input;
    String length(double mm) => (mm / _scale).toString();
    setState(() {
      _shape = ConeShape.eccentric;
      _ref = i.ref;
      _parts = i.parts;
      _div = i.divisions;
      _vertical = i.verticalSide;
      _seamShort = i.seamOnShortSide;
      _dL.text = length(i.largeDiaMm);
      _dS.text = length(i.smallDiaMm);
      _h.text = length(i.heightMm);
      _t.text = length(i.thicknessMm);
      if (!i.verticalSide) _e.text = length(i.offsetMm);
    });
    return {};
  }

  Future<Set<String>> _applyTransition(Map<String, Object?> fields) async {
    TransitionAssistantInput parsed;
    try {
      parsed = TransitionAssistantInput.fromFields(fields);
    } on FormatException {
      return fields.keys.toSet();
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return fields.keys.toSet();
    }
    final i = parsed.input;
    String length(double mm) => (mm / _scale).toString();
    setState(() {
      _shape = ConeShape.transition;
      _ref = i.ref;
      _parts = i.parts;
      _div = i.divisions;
      _seam = i.seam;
      _a.text = length(i.sideAMm);
      _b.text = length(i.sideBMm);
      _dT.text = length(i.diameterMm);
      _hT.text = length(i.heightMm);
      _ex.text = length(i.offsetXMm);
      _ey.text = length(i.offsetYMm);
      _t.text = length(i.thicknessMm);
    });
    return {};
  }

  bool _printTooBig(_Outcome out) {
    final maxDim = out.partSizes
        .fold<double>(0, (m, size) => math.max(m, math.max(size.$1, size.$2)));
    return maxDim > kConeMaxPrintMm ||
        flatTemplateSheetCount(out.partSizes, _paper) > WrapTileLayout.maxTiles;
  }

  @override
  Future<ModuleActionResult> performAction(String action,
      {String? field}) async {
    const unavailable = ModuleActionResult(
        false,
        AssistantText(
            'Otwórz rozwinięcie i zamknij okno dialogowe przed przygotowaniem PDF.',
            'Open the development and close any dialog before preparing PDF.'));
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return unavailable;
    }
    if (!const {'export_pdf', 'undo'}.contains(action) || field != null) {
      return const ModuleActionResult(
          false,
          AssistantText('Ta czynność eksportu nie jest obsługiwana.',
              'This export action is unsupported.'));
    }
    if (_exporting) {
      return const ModuleActionResult(
          false,
          AssistantText('Przygotowanie PDF jest już w toku.',
              'PDF preparation is already in progress.'));
    }
    if (action == 'undo') return _undoDevelopment();
    final out = switch (_shape) {
      ConeShape.concentric => _concentric(),
      ConeShape.eccentric => _eccentric(),
      ConeShape.transition => _transition(),
    };
    if (out.problems.isNotEmpty || out.spec == null || _printTooBig(out)) {
      return const ModuleActionResult(
          false,
          AssistantText(
              'Nie można przygotować PDF: popraw wymiary lub zmniejsz rozmiar wydruku zgodnie z komunikatem kalkulatora.',
              'Cannot prepare PDF: correct dimensions or reduce print size according to the calculator message.'));
    }
    final before = Map<String, Object?>.of(inputFields);
    final settings = (
      _paper,
      _viewPart,
      _showOrdinates,
      _step,
      _sheetW.text,
      _sheetL.text,
      _en
    );
    final success = await _sharePdf(out.spec!(_paper), out.fileName);
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        !mapEquals(before, inputFields) ||
        settings !=
            (
              _paper,
              _viewPart,
              _showOrdinates,
              _step,
              _sheetW.text,
              _sheetL.text,
              _en
            )) {
      return const ModuleActionResult(
          false,
          AssistantText(
              'Ekran lub dane zmieniły się podczas przygotowania PDF. Dalsze kroki wstrzymano.',
              'The screen or inputs changed during PDF preparation. Further steps were stopped.'));
    }
    return success
        ? const ModuleActionResult(
            true,
            AssistantText(
                'Przygotowano PDF. Zapis, druk lub udostępnienie wybierasz w oknie systemowym.',
                'PDF prepared. Choose saving, printing or sharing in the system dialog.'))
        : const ModuleActionResult(
            false,
            AssistantText(
                'Nie udało się przygotować szablonu PDF. Spróbuj ponownie.',
                'Could not prepare the PDF template. Please retry.'));
  }

  ConeShape _shape = ConeShape.concentric;
  bool _inch = false;

  // Stożek (współosiowy i mimośrodowy).
  // Domyślnie typowy lej Ø600 / Ø200, H 400, blacha 4 mm.
  final _dL = TextEditingController(text: '600');
  final _dS = TextEditingController(text: '200');
  final _h = TextEditingController(text: '400');
  final _alpha = TextEditingController(text: '30');
  final _slant = TextEditingController(text: '450');
  ConeSizeMode _mode = ConeSizeMode.height;
  final _t = TextEditingController(text: '4');
  DiameterRef _ref = DiameterRef.outside;
  int _coneParts = 1;
  final _allow = TextEditingController(text: '0');

  // Mimośrodowy.
  bool _vertical = true;
  final _e = TextEditingController(text: '100');
  bool _seamShort = true;

  // Przejście.
  final _a = TextEditingController(text: '600');
  final _b = TextEditingController(text: '400');
  final _dT = TextEditingController(text: '300');
  final _hT = TextEditingController(text: '400');
  final _ex = TextEditingController(text: '0');
  final _ey = TextEditingController(text: '0');
  TransitionSeam _seam = TransitionSeam.sideB;

  // Wspólne dla triangulacji.
  int _div = 16;
  int _parts = 1;

  // Arkusz i wydruk.
  final _sheetW = TextEditingController(text: '1500');
  final _sheetL = TextEditingController(text: '3000');
  TemplatePaper _paper = TemplatePaper.a4;
  int _viewPart = 0;
  double _step = 100;
  bool _showOrdinates = false;
  bool _exporting = false;

  List<TextEditingController> get _lengthFields => [
        _dL,
        _dS,
        _h,
        _slant,
        _t,
        _allow,
        _e,
        _a,
        _b,
        _dT,
        _hT,
        _ex,
        _ey,
        _sheetW,
        _sheetL,
      ];

  @override
  void dispose() {
    for (final c in [..._lengthFields, _alpha]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Jednostki i formatowanie ─────────────────────────────────────────────

  bool get _en => context.language == AppLanguage.en;
  double get _scale => _inch ? 25.4 : 1;
  String get _u => _inch ? 'in' : 'mm';

  /// Wartość pola w mm (NaN, gdy puste / błędne).
  double _mmOf(TextEditingController c) =>
      (parseDecimal(c.text) ?? double.nan) * _scale;

  String _num(double v, int d) {
    final s = formatQty(v, decimals: d);
    return _en ? s.replaceAll(',', '.') : s;
  }

  /// Długość w bieżącej jednostce (bez jednostki).
  String _len(double mm, {int? d}) => _num(mm / _scale, d ?? (_inch ? 2 : 1));

  String _lenU(double mm, {int? d}) => '${_len(mm, d: d)} $_u';

  String _deg(double v, {int d = 2}) => '${_num(v, d)}°';

  void _setUnit(bool inch) {
    if (inch == _inch) return;
    _undoHistory.clear();
    _manualEditRevision++;
    final from = _scale;
    final to = inch ? 25.4 : 1.0;
    for (final c in _lengthFields) {
      final v = parseDecimal(c.text);
      if (v == null) continue;
      c.text = numText(v * from / to, decimals: inch ? 3 : 1);
    }
    setState(() {
      _inch = inch;
      _step = inch ? 4 * 25.4 : 100;
    });
  }

  // ── Wejścia → domena ─────────────────────────────────────────────────────

  ConeInput get _coneInput => ConeInput(
        largeDiaMm: _mmOf(_dL),
        smallDiaMm: _mmOf(_dS),
        mode: _mode,
        heightMm: _mmOf(_h),
        halfAngleDeg: parseDecimal(_alpha.text) ?? double.nan,
        slantMm: _mmOf(_slant),
        thicknessMm: _mmOf(_t),
        ref: _ref,
        parts: _coneParts,
        allowanceMm: _allow.text.trim().isEmpty ? 0 : _mmOf(_allow),
      );

  EccentricConeInput get _eccInput => EccentricConeInput(
        largeDiaMm: _mmOf(_dL),
        smallDiaMm: _mmOf(_dS),
        heightMm: _mmOf(_h),
        offsetMm: _mmOf(_e),
        verticalSide: _vertical,
        thicknessMm: _mmOf(_t),
        ref: _ref,
        divisions: _div,
        parts: _parts,
        seamOnShortSide: _seamShort,
      );

  TransitionInput get _trInput => TransitionInput(
        sideAMm: _mmOf(_a),
        sideBMm: _mmOf(_b),
        diameterMm: _mmOf(_dT),
        heightMm: _mmOf(_hT),
        offsetXMm: _ex.text.trim().isEmpty ? 0 : _mmOf(_ex),
        offsetYMm: _ey.text.trim().isEmpty ? 0 : _mmOf(_ey),
        thicknessMm: _mmOf(_t),
        ref: _ref,
        divisions: _div,
        parts: _parts,
        seam: _seam,
      );

  (double, double)? get _sheet {
    final w = _mmOf(_sheetW), l = _mmOf(_sheetL);
    if (!(w > 0) || !(l > 0)) return null;
    return (w, l);
  }

  // ── Komunikaty ───────────────────────────────────────────────────────────

  String _coneProblem(ConeProblem p) => switch (p) {
        ConeProblem.largeDia => context.tr(
            pl: 'Podaj średnicę dużą D (do 50 m).',
            en: 'Enter the large diameter D (up to 50 m).'),
        ConeProblem.smallDia => context.tr(
            pl: 'Podaj średnicę małą d (0 = stożek pełny, z wierzchołkiem).',
            en: 'Enter the small diameter d (0 = full cone with apex).'),
        ConeProblem.smallNotLess => context.tr(
            pl: 'Średnica mała musi być mniejsza od dużej (d < D). '
                'Przy d = D to walczak — zwija się z prostokąta π·D × H.',
            en: 'The small diameter must be less than the large one (d < D). '
                'With d = D it is a cylinder — roll a π·D × H rectangle.'),
        ConeProblem.height => context.tr(
            pl: 'Podaj wysokość H większą od zera.',
            en: 'Enter a height H greater than zero.'),
        ConeProblem.halfAngle => context.tr(
            pl: 'Kąt połówkowy α (od osi stożka) musi być między 0° a 90°.',
            en: 'The half-angle α (from the cone axis) must be between 0° and 90°.'),
        ConeProblem.slant => context.tr(
            pl: 'Podaj długość tworzącej L większą od zera.',
            en: 'Enter a slant length L greater than zero.'),
        ConeProblem.slantTooShort => context.tr(
            pl: 'Tworząca musi być dłuższa niż różnica promieni (Dm − dm)/2 — '
                'inaczej stożek nie istnieje.',
            en: 'The slant must be longer than the radius difference (Dm − dm)/2 — '
                'otherwise the cone does not exist.'),
        ConeProblem.thickness => context.tr(
            pl: 'Grubość blachy: od 0 do mniej niż połowy mniejszej średnicy.',
            en: 'Plate thickness: from 0 to less than half the smaller diameter.'),
        ConeProblem.parts => context.tr(
            pl: 'Liczba części: od 1 do 12.', en: 'Number of parts: 1 to 12.'),
        ConeProblem.allowance => context.tr(
            pl: 'Naddatek na zakład: od 0 do 200 mm.',
            en: 'Seam allowance: 0 to 200 mm.'),
      };

  String _eccProblem(EccentricProblem p) => switch (p) {
        EccentricProblem.largeDia => _coneProblem(ConeProblem.largeDia),
        EccentricProblem.smallDia => _coneProblem(ConeProblem.smallDia),
        EccentricProblem.smallNotLess => _coneProblem(ConeProblem.smallNotLess),
        EccentricProblem.height => _coneProblem(ConeProblem.height),
        EccentricProblem.offset => context.tr(
            pl: 'Przesunięcie osi e: liczba ≥ 0.',
            en: 'Axis offset e: a number ≥ 0.'),
        EccentricProblem.thickness => _coneProblem(ConeProblem.thickness),
        EccentricProblem.divisions => context.tr(
            pl: 'Podział obwodu: 12, 16, 24, 32 albo 48.',
            en: 'Divisions: 12, 16, 24, 32 or 48.'),
        EccentricProblem.parts =>
          context.tr(pl: 'Części: 1, 2 albo 4.', en: 'Parts: 1, 2 or 4.'),
      };

  String _trProblem(TransitionProblem p) => switch (p) {
        TransitionProblem.sideA => context.tr(
            pl: 'Podaj bok A prostokąta.', en: 'Enter rectangle side A.'),
        TransitionProblem.sideB => context.tr(
            pl: 'Podaj bok B prostokąta.', en: 'Enter rectangle side B.'),
        TransitionProblem.diameter => context.tr(
            pl: 'Podaj średnicę koła D.', en: 'Enter the circle diameter D.'),
        TransitionProblem.height => _coneProblem(ConeProblem.height),
        TransitionProblem.offset => context.tr(
            pl: 'Przesunięcie środka koła musi być liczbą.',
            en: 'The circle offset must be a number.'),
        TransitionProblem.thickness => context.tr(
            pl: 'Grubość: mniej niż połowa najmniejszego wymiaru (A, B, D).',
            en: 'Thickness: less than half the smallest size (A, B, D).'),
        TransitionProblem.divisions => _eccProblem(EccentricProblem.divisions),
        TransitionProblem.parts => _eccProblem(EccentricProblem.parts),
      };

  // ── Udostępnianie ────────────────────────────────────────────────────────

  Future<void> _shareText(String text) async {
    unawaited(Haptic.tap());
    await widget.shareText(
        text,
        context.tr(
            pl: 'Rozwinięcie blachy — wymiary',
            en: 'Flat pattern — dimensions'));
  }

  Future<bool> _sharePdf(FlatTemplateSpec spec, String fileName) async {
    if (_exporting) return false;
    final en = _en;
    setState(() => _exporting = true);
    try {
      await widget.sharePdf(spec, fileName, en);
      unawaited(Haptic.saved());
      return true;
    } catch (e) {
      debugPrint('[cone_layout] pdf failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.tr(
                pl: 'Nie udało się przygotować szablonu.',
                en: 'Could not prepare the template.'))));
      }
      return false;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Budowa ekranu ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final _Outcome out = switch (_shape) {
      ConeShape.concentric => _concentric(),
      ConeShape.eccentric => _eccentric(),
      ConeShape.transition => _transition(),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Rozwinięcie stożka i przejść',
            en: 'Cone & transition layout')),
        actions: [
          IconButton(
            key: const ValueKey('cone-appbar-share'),
            tooltip:
                context.tr(pl: 'Udostępnij wymiary', en: 'Share dimensions'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed:
                out.shareText == null ? null : () => _shareText(out.shareText!),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('cone-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _shapeSection(),
          ...out.inputs,
          if (out.problems.isNotEmpty)
            QuoteNotice(
              key: const ValueKey('cone-problem'),
              color: kFail,
              icon: Icons.error_outline,
              text: out.problems.join('\n'),
            )
          else ...[
            ...out.results,
            _printSection(out),
          ],
        ],
      ),
    );
  }

  Widget _shapeSection() {
    Widget chip(ConeShape s, String pl, String en) => ChoiceChip(
          key: ValueKey('cone-shape-${s.name}'),
          label: Text(context.tr(pl: pl, en: en)),
          selected: _shape == s,
          onSelected: (_) => _manualChange(() {
            _shape = s;
            _viewPart = 0;
          }),
        );
    return QuoteSection(
      title: context.tr(pl: 'Kształt', en: 'Shape'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(ConeShape.concentric, 'Stożek współosiowy', 'Concentric cone'),
            chip(ConeShape.eccentric, 'Stożek mimośrodowy', 'Eccentric cone'),
            chip(ConeShape.transition, 'Kwadrat → koło', 'Square to round'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(context.tr(pl: 'Jednostki:', en: 'Units:'),
                style: const TextStyle(color: kTextSec, fontSize: 13)),
            ChoiceChip(
              key: const ValueKey('cone-unit-mm'),
              label: const Text('mm'),
              selected: !_inch,
              onSelected: (_) => _setUnit(false),
            ),
            ChoiceChip(
              key: const ValueKey('cone-unit-in'),
              label: Text(context.tr(pl: 'cale', en: 'inches')),
              selected: _inch,
              onSelected: (_) => _setUnit(true),
            ),
          ],
        ),
      ],
    );
  }

  // ── Wspólne pola ─────────────────────────────────────────────────────────

  Widget _numField(TextEditingController c, String label,
          {required String key,
          String? unit,
          String? helper,
          bool signed = false}) =>
      TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: numberKeyboard(signed: signed),
        inputFormatters: numberInputFormatters(signed: signed),
        onChanged: (_) => _manualChange(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit ?? _u,
          helperText: helper,
          helperMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _caption(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child:
            Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _chips<T>(List<(T, String, String)> items, T selected,
          ValueChanged<T> onPick) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (value, key, label) in items)
            ChoiceChip(
              key: ValueKey(key),
              label: Text(label),
              selected: value == selected,
              onSelected: (_) => _manualChange(() => onPick(value)),
            ),
        ],
      );

  List<Widget> _thicknessBlock() => [
        const SizedBox(height: 12),
        _numField(
            _t, context.tr(pl: 'Grubość blachy t', en: 'Plate thickness t'),
            key: 'cone-t'),
        _caption(
            context.tr(pl: 'Wymiary podane jako', en: 'Dimensions given as')),
        _chips<DiameterRef>([
          (
            DiameterRef.outside,
            'cone-ref-outside',
            context.tr(pl: 'zewnętrzne', en: 'outside')
          ),
          (
            DiameterRef.inside,
            'cone-ref-inside',
            context.tr(pl: 'wewnętrzne', en: 'inside')
          ),
          (
            DiameterRef.mean,
            'cone-ref-mean',
            context.tr(pl: 'średnie', en: 'mean')
          ),
        ], _ref, (v) => _ref = v),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              key: const ValueKey('cone-neutral-hint'),
              switch (_shape) {
                ConeShape.concentric => context.tr(
                    pl: 'Rozwinięcie po osi obojętnej: zewn. − t/cos α, wewn. + t/cos α '
                        '(t prostopadle do ścianki, α — pochylenie ścianki od pionu).',
                    en: 'Developed on the neutral axis: outside − t/cos α, inside + t/cos α '
                        '(t square to the wall, α — wall slope from vertical).'),
                ConeShape.eccentric => context.tr(
                    pl: 'Rozwinięcie po osi obojętnej: zewn. − t·⟨1/cos β⟩, wewn. + t·⟨1/cos β⟩ '
                        '(β — pochylenie ścianki, uśrednione po obwodzie).',
                    en: 'Developed on the neutral axis: outside − t·⟨1/cos β⟩, inside + t·⟨1/cos β⟩ '
                        '(β — wall slope, averaged round the circumference).'),
                ConeShape.transition => context.tr(
                    pl: 'Rozwinięcie po osi obojętnej: zewn. − t, wewn. + t.',
                    en: 'Developed on the neutral axis: outside − t, inside + t.'),
              },
              style: const TextStyle(fontSize: 12, color: kTextMut)),
        ),
      ];

  List<Widget> _divisionsAndParts() => [
        _caption(context.tr(
            pl: 'Podział obwodu (punkty triangulacji)',
            en: 'Divisions (triangulation points)')),
        _chips<int>([
          for (final n in kConeDivisions) (n, 'cone-div-$n', '$n'),
        ], _div, (v) => _div = v),
        _caption(context.tr(pl: 'Części blachy', en: 'Plate parts')),
        _chips<int>([
          for (final n in const [1, 2, 4]) (n, 'cone-tparts-$n', '$n'),
        ], _parts, (v) {
          _parts = v;
          _viewPart = 0;
        }),
      ];

  Widget _kv(String k, String v, {Key? key}) => CopyOnLongPress(
        value: v,
        label: k,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(k,
                      style: const TextStyle(fontSize: 13.5, color: kTextSec))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(v,
                    key: key,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );

  /// Tabela z przewijaniem w poziomie (wąski ekran).
  Widget _grid(String key, List<String> headers, List<List<String>> rows,
      {String? copyLabel}) {
    final text =
        [headers.join('\t'), for (final r in rows) r.join('\t')].join('\n');
    return CopyOnLongPress(
      value: text,
      label: copyLabel,
      child: SingleChildScrollView(
        key: ValueKey(key),
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: const TableBorder(
              horizontalInside: BorderSide(color: kBorder, width: 0.6)),
          children: [
            TableRow(children: [
              for (final h in headers)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Text(h,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: kTextMut,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
            for (final r in rows)
              TableRow(children: [
                for (final (i, c) in r.indexed)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                    child: Text(c,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: i == 0 ? kArc : kText,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _partPicker(int count, String Function(int) label) => count < 2
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _chips<int>([
            for (var p = 0; p < count; p++)
              (p, 'cone-view-part-${p + 1}', label(p)),
          ], _viewPart.clamp(0, count - 1), (v) => _viewPart = v),
        );

  String _partName(int p) =>
      context.tr(pl: 'Część ${p + 1}', en: 'Part ${p + 1}');

  // ── Stożek współosiowy ───────────────────────────────────────────────────

  _Outcome _concentric() {
    final input = _coneInput;
    final inputs = [
      QuoteSection(
        title: context.tr(pl: 'Wymiary stożka', en: 'Cone dimensions'),
        children: [
          FieldPair(
            left: _numField(
                _dL, context.tr(pl: 'Średnica duża D', en: 'Large dia. D'),
                key: 'cone-D'),
            right: _numField(
                _dS, context.tr(pl: 'Średnica mała d', en: 'Small dia. d'),
                key: 'cone-d',
                helper:
                    context.tr(pl: '0 = stożek pełny', en: '0 = full cone')),
          ),
          _caption(context.tr(
              pl: 'Bok stożka podany jako', en: 'Cone side given as')),
          _chips<ConeSizeMode>([
            (
              ConeSizeMode.height,
              'cone-mode-height',
              context.tr(pl: 'wysokość H', en: 'height H')
            ),
            (
              ConeSizeMode.halfAngle,
              'cone-mode-angle',
              context.tr(pl: 'kąt α', en: 'angle α')
            ),
            (
              ConeSizeMode.slant,
              'cone-mode-slant',
              context.tr(pl: 'tworząca L', en: 'slant L')
            ),
          ], _mode, (v) => _mode = v),
          const SizedBox(height: 10),
          switch (_mode) {
            ConeSizeMode.height => _numField(
                _h, context.tr(pl: 'Wysokość H', en: 'Height H'),
                key: 'cone-H',
                helper: context.tr(
                    pl: 'Między płaszczyznami końców.',
                    en: 'Between the end planes.')),
            ConeSizeMode.halfAngle => _numField(
                _alpha, context.tr(pl: 'Kąt połówkowy α', en: 'Half-angle α'),
                key: 'cone-alpha',
                unit: '°',
                helper: context.tr(
                    pl: 'Od osi stożka do tworzącej (kąt wierzchołkowy = 2α).',
                    en: 'From the cone axis to the side (apex angle = 2α).')),
            ConeSizeMode.slant => _numField(
                _slant, context.tr(pl: 'Tworząca L', en: 'Slant length L'),
                key: 'cone-L',
                helper: context.tr(
                    pl: 'Długość boku stożka od końca do końca.',
                    en: 'Side length of the cone, end to end.')),
          },
          ..._thicknessBlock(),
        ],
      ),
    ];
    final problems = input.problems;
    final r = computeCone(input);
    if (problems.isNotEmpty || r == null) {
      return _Outcome(
          inputs: inputs, problems: problems.map(_coneProblem).toList());
    }
    final part = r.part;
    final whole = r.whole;
    final sheet = _sheet;
    final rec = sheet == null ? null : r.recommendedParts(sheet.$1, sheet.$2);
    final pattern = part.pattern();
    final showOrd = r.needsOrdinates || _showOrdinates;
    final results = <Widget>[
      QuoteSection(
        title: context.tr(pl: 'Rozwinięcie', en: 'Flat pattern'),
        children: [
          Readout(
            key: const ValueKey('cone-R'),
            label: context.tr(pl: 'Promień zewnętrzny R', en: 'Outer radius R'),
            value: _len(r.outerRadiusMm),
            unit: context.tr(
                pl: '$_u · od wierzchołka do dużej krawędzi',
                en: '$_u · apex to the large edge'),
            hot: true,
          ),
          const SizedBox(height: 12),
          _kv(
              context.tr(pl: 'Promień wewnętrzny r', en: 'Inner radius r'),
              r.isFull
                  ? context.tr(pl: '0 (wierzchołek)', en: '0 (apex)')
                  : _lenU(r.innerRadiusMm),
              key: const ValueKey('cone-r')),
          _kv(context.tr(pl: 'Kąt wycinka θ', en: 'Sector angle θ'),
              _deg(r.sectorAngleDeg),
              key: const ValueKey('cone-theta')),
          _kv(context.tr(pl: 'Tworząca L (R − r)', en: 'Slant L (R − r)'),
              _lenU(r.slantMm)),
          _kv(context.tr(pl: 'Wysokość H', en: 'Height H'), _lenU(r.heightMm)),
          _kv(
              context.tr(
                  pl: 'Kąt połówkowy α / wierzchołkowy 2α',
                  en: 'Half-angle α / apex angle 2α'),
              '${_deg(r.halfAngleDeg)} / ${_deg(2 * r.halfAngleDeg)}'),
          _kv(
              context.tr(
                  pl: 'Średnice obliczeniowe Dm / dm',
                  en: 'Neutral diameters Dm / dm'),
              '${_len(r.meanLargeMm)} / ${_len(r.meanSmallMm)} $_u'),
          _kv(
              context.tr(
                  pl: 'Łuk zewn. / wewn. (= π·Dm, π·dm)',
                  en: 'Outer / inner arc (= π·Dm, π·dm)'),
              '${_len(r.outerArcMm)} / ${_len(r.innerArcMm)} $_u'),
          _kv(
              context.tr(
                  pl: 'Cięciwa zewn. / wewn.', en: 'Outer / inner chord'),
              '${_len(whole.outerChordMm)} / ${_len(whole.innerChordMm)} $_u'),
          _kv(
              context.tr(
                  pl: 'Strzałka łuku zewn. / wewn.',
                  en: 'Outer / inner arc height'),
              '${_len(whole.outerSagittaMm)} / ${_len(whole.innerSagittaMm)} $_u'),
          _kv(
              context.tr(
                  pl: 'Przekątna kontrolna (róg zewn. → przeciwny róg wewn.)',
                  en: 'Check diagonal (outer corner → opposite inner corner)'),
              _lenU(whole.diagonalMm)),
          _kv(
              context.tr(
                  pl: 'Prostokąt blachy (całość)',
                  en: 'Plate rectangle (whole)'),
              '${_len(whole.widthMm)} × ${_len(whole.heightMm)} $_u',
              key: const ValueKey('cone-whole-rect')),
          if (input.thicknessMm > 0)
            _kv(
                context.tr(
                    pl: 'Masa blachy (stal 7850 kg/m³)',
                    en: 'Plate mass (steel 7850 kg/m³)'),
                '${_num(r.massKg(), 1)} kg'),
        ],
      ),
      if (r.nearlyFlat)
        QuoteNotice(
          key: const ValueKey('cone-flat-notice'),
          text: context.tr(
              pl: 'Wycinek prawie płaski (θ > 300°) — źle się zwija. Podziel na co najmniej 2 części albo prasuj segmentami.',
              en: 'Nearly flat sector (θ > 300°) — hard to roll. Split into at least 2 parts or press in segments.'),
        ),
      QuoteSection(
        title: context.tr(pl: 'Podgląd i podział', en: 'Preview and split'),
        subtitle: context.tr(
            pl: 'Linie przerywane — tworzące (prowadź wzdłuż walców przy zwijaniu).',
            en: 'Dashed lines — generators (keep them along the rolls).'),
        children: [
          _PatternView(part: pattern),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '${context.tr(pl: 'Prostokąt części', en: 'Part rectangle')}: '
                '${_len(part.widthMm)} × ${_len(part.heightMm)} $_u',
                key: const ValueKey('cone-part-rect'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSec, fontSize: 12.5)),
          ),
          _caption(context.tr(pl: 'Liczba części', en: 'Number of parts')),
          _chips<int>([
            for (final n in kConePartOptions) (n, 'cone-parts-$n', '$n'),
          ], _coneParts, (v) => _coneParts = v),
          const SizedBox(height: 10),
          _numField(
              _allow,
              context.tr(
                  pl: 'Naddatek na zakład / spoinę', en: 'Seam allowance'),
              key: 'cone-allow',
              helper: context.tr(
                  pl: 'Pas wzdłuż jednej krawędzi prostej każdej części (0 = bez).',
                  en: 'Strip along one straight edge of each part (0 = none).')),
          if (r.parts > 1) ...[
            const SizedBox(height: 10),
            _kv(
                context.tr(
                    pl: 'Część × ${r.parts}: kąt θ/${r.parts}',
                    en: 'Part × ${r.parts}: angle θ/${r.parts}'),
                _deg(part.angleDeg),
                key: const ValueKey('cone-part-angle')),
            _kv(
                context.tr(
                    pl: 'Łuk zewn. / wewn. części',
                    en: 'Part outer / inner arc'),
                '${_len(part.outerArcMm)} / ${_len(part.innerArcMm)} $_u'),
            _kv(
                context.tr(
                    pl: 'Cięciwa zewn. / wewn. części',
                    en: 'Part outer / inner chord'),
                '${_len(part.outerChordMm)} / ${_len(part.innerChordMm)} $_u'),
            _kv(
                context.tr(
                    pl: 'Strzałka zewn. / wewn. części',
                    en: 'Part outer / inner arc height'),
                '${_len(part.outerSagittaMm)} / ${_len(part.innerSagittaMm)} $_u'),
            _kv(
                context.tr(
                    pl: 'Przekątna kontrolna części',
                    en: 'Part check diagonal'),
                _lenU(part.diagonalMm)),
          ],
          if (sheet != null && !part.fitsSheet(sheet.$1, sheet.$2))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: QuoteNotice(
                key: const ValueKey('cone-fit-notice'),
                text: rec == null
                    ? context.tr(
                        pl:
                            'Część nie mieści się na arkuszu ${_len(sheet.$1)} × ${_len(sheet.$2)} $_u nawet przy 12 częściach.',
                        en:
                            'The part does not fit a ${_len(sheet.$1)} × ${_len(sheet.$2)} $_u sheet even in 12 parts.')
                    : context.tr(
                        pl: 'Część nie mieści się na arkuszu ${_len(sheet.$1)} × ${_len(sheet.$2)} $_u — zalecany podział: $rec cz.',
                        en: 'The part does not fit a ${_len(sheet.$1)} × ${_len(sheet.$2)} $_u sheet — suggested split: $rec parts.'),
              ),
            ),
        ],
      ),
      QuoteSection(
        title: context.tr(
            pl: 'Trasowanie bez cyrkla', en: 'Marking without trammels'),
        subtitle: context.tr(
            pl: 'Rzędne łuku od cięciwy — gdy promień R za duży na cyrkiel.',
            en: 'Arc offsets from the chord — when R is too long for trammels.'),
        children: [
          if (!showOrd)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('cone-show-ordinates'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                onPressed: () => setState(() => _showOrdinates = true),
                icon: const Icon(Icons.table_rows_outlined),
                label: Text(context.tr(
                    pl: 'Pokaż tabelę rzędnych', en: 'Show offset table')),
              ),
            )
          else if (!part.chordOffsetsPossible)
            QuoteNotice(
              key: const ValueKey('cone-ord-split'),
              text: context.tr(
                  pl: 'Część ma ponad 180° — od cięciwy się nie da. Podziel stożek na więcej części.',
                  en: 'The part spans over 180° — chord offsets will not work. Split the cone into more parts.'),
            )
          else
            ..._ordinates(r, part),
        ],
      ),
    ];

    final shapes = [
      _shapeOf(
          pattern,
          r.parts > 1
              ? context.tr(
                  pl: 'Część (× ${r.parts})', en: 'Part (× ${r.parts})')
              : context.tr(pl: 'Rozwinięcie', en: 'Flat pattern')),
    ];
    return _Outcome(
      inputs: inputs,
      problems: const [],
      results: results,
      shareText: _coneText(r, showOrd),
      shapes: shapes,
      partSizes: [(part.widthMm, part.heightMm)],
      fileName:
          'stozek_${_num(r.meanLargeMm, 0)}_${_num(r.meanSmallMm, 0)}.pdf',
      spec: (paper) => FlatTemplateSpec(
        title: context.tr(
            pl: 'Rozwinięcie stożka ściętego',
            en: 'Concentric cone flat pattern'),
        summaryLines: _coneSummary(r),
        tables: [
          if (part.chordOffsetsPossible) ..._ordinateTables(r, part),
        ],
        instructions: [
          context.tr(
              pl: 'Łuk zewnętrzny (dolny) to duża średnica. Linie przerywane — tworzące do prowadzenia zwijania.',
              en: 'The outer (lower) arc is the large diameter. Dashed lines — generators to guide rolling.'),
          if (input.allowanceMm > 0)
            context.tr(
                pl: 'Pas przerywany wzdłuż krawędzi — naddatek ${_lenU(input.allowanceMm)} na zakład.',
                en: 'Dashed strip along the edge — ${_lenU(input.allowanceMm)} seam allowance.'),
          if (_ordinatesSkipped(part) case final skipped?) skipped,
        ],
        note: _neutralNote(),
        shapes: shapes,
        paper: paper,
      ),
    );
  }

  List<Widget> _ordinates(ConeResult r, ConeSector part) {
    final outer = part.chordOffsets(outer: true, stepMm: _step);
    final inner = part.chordOffsets(outer: false, stepMm: _step);
    final steps =
        _inch ? const [1.0, 2.0, 4.0, 10.0] : const [50.0, 100.0, 200.0, 500.0];
    final tooMany = outer.length > 300;
    return [
      _chips<double>([
        for (final s in steps)
          (
            s * _scale,
            'cone-step-${_num(s, 0)}',
            '${context.tr(pl: 'co', en: 'every')} ${_num(s, 0)} $_u'
          ),
      ], _step, (v) => _step = v),
      const SizedBox(height: 8),
      Text(
        context.tr(
            pl: 'Narysuj cięciwę zewnętrzną ${_lenU(part.outerChordMm)}, przez jej środek prostopadłą. '
                'Cięciwa wewnętrzna ${_lenU(part.innerChordMm)} równolegle, ${_lenU(part.chordGapMm)} w stronę wierzchołka, środkiem na prostopadłej. '
                'Rzędne x od lewego końca, y od cięciwy na zewnątrz (w stronę wybrzuszenia łuku).',
            en: 'Draw the outer chord ${_lenU(part.outerChordMm)} and a square line through its middle. '
                'Inner chord ${_lenU(part.innerChordMm)} parallel, ${_lenU(part.chordGapMm)} towards the apex, centred on that line. '
                'Offsets: x from the left end, y outwards from the chord (towards the bulge).'),
        style: const TextStyle(fontSize: 12.5, color: kTextSec, height: 1.35),
      ),
      const SizedBox(height: 8),
      if (tooMany)
        QuoteNotice(
          key: const ValueKey('cone-ord-too-many'),
          text: context.tr(
              pl: 'Ponad 300 rzędnych — wybierz większy krok.',
              en: 'Over 300 offsets — pick a larger step.'),
        )
      else ...[
        Text(context.tr(pl: 'Łuk zewnętrzny (R)', en: 'Outer arc (R)'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        _grid(
            'cone-ord-outer',
            ['x $_u', 'y $_u'],
            [
              for (final o in outer) [_len(o.xMm), _len(o.yMm)]
            ],
            copyLabel:
                context.tr(pl: 'Rzędne łuku zewn.', en: 'Outer arc offsets')),
        if (inner.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(context.tr(pl: 'Łuk wewnętrzny (r)', en: 'Inner arc (r)'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          _grid(
              'cone-ord-inner',
              ['x $_u', 'y $_u'],
              [
                for (final o in inner) [_len(o.xMm), _len(o.yMm)]
              ],
              copyLabel:
                  context.tr(pl: 'Rzędne łuku wewn.', en: 'Inner arc offsets')),
        ],
      ],
    ];
  }

  List<FlatTemplateTable> _ordinateTables(ConeResult r, ConeSector part) {
    final outer = part.chordOffsets(outer: true, stepMm: _step);
    final inner = part.chordOffsets(outer: false, stepMm: _step);
    if (outer.length > 300) return const [];
    return [
      FlatTemplateTable(
          context.tr(
              pl: 'Rzędne łuku zewnętrznego od cięciwy ${_lenU(part.outerChordMm)}',
              en: 'Outer arc offsets from the ${_lenU(part.outerChordMm)} chord'),
          [
            'x ($_u)',
            'y ($_u)'
          ],
          [
            for (final o in outer) [_len(o.xMm), _len(o.yMm)]
          ]),
      if (inner.isNotEmpty)
        FlatTemplateTable(
            context.tr(
                pl: 'Rzędne łuku wewnętrznego od cięciwy ${_lenU(part.innerChordMm)} '
                    '(odstęp cięciw ${_lenU(part.chordGapMm)})',
                en: 'Inner arc offsets from the ${_lenU(part.innerChordMm)} chord '
                    '(chord gap ${_lenU(part.chordGapMm)})'),
            [
              'x ($_u)',
              'y ($_u)'
            ],
            [
              for (final o in inner) [_len(o.xMm), _len(o.yMm)]
            ]),
    ];
  }

  String _refText(DiameterRef ref) => switch (ref) {
        DiameterRef.outside => context.tr(pl: 'zewn.', en: 'outside'),
        DiameterRef.inside => context.tr(pl: 'wewn.', en: 'inside'),
        DiameterRef.mean => context.tr(pl: 'średnie', en: 'mean'),
      };

  String _neutralNote() {
    final rule = switch (_shape) {
      ConeShape.concentric => context.tr(
          pl: 'zewn. − t/cos α, wewn. + t/cos α',
          en: 'outside − t/cos α, inside + t/cos α'),
      ConeShape.eccentric => context.tr(
          pl: 'zewn. − t·⟨1/cos β⟩, wewn. + t·⟨1/cos β⟩, β uśrednione po obwodzie',
          en: 'outside − t·⟨1/cos β⟩, inside + t·⟨1/cos β⟩, β averaged round the circumference'),
      ConeShape.transition =>
        context.tr(pl: 'zewn. − t, wewn. + t', en: 'outside − t, inside + t'),
    };
    return context.tr(
        pl: 'Rozwinięcie po osi obojętnej (wymiar średni: $rule). '
            'Bez naddatku na ukosowanie i szczelinę spoiny, chyba że podano. '
            'Przed cięciem sprawdź przekątne i długości łuków taśmą.',
        en: 'Developed on the neutral axis (mean size: $rule). '
            'No bevel or root-gap allowance unless given. '
            'Check diagonals and arc lengths with a tape before cutting.');
  }

  /// Dlaczego w PDF / tekście nie ma tabeli rzędnych (null — jest).
  String? _ordinatesSkipped(ConeSector part) {
    if (!part.chordOffsetsPossible) {
      return context.tr(
          pl: 'Tabeli rzędnych od cięciwy brak: część ma ponad 180° — podziel stożek na więcej części.',
          en: 'No chord offset table: the part spans over 180° — split the cone into more parts.');
    }
    final n = part.chordOffsets(outer: true, stepMm: _step).length;
    if (n > 300) {
      return context.tr(
          pl: 'Tabela rzędnych pominięta: przy kroku ${_lenU(_step)} wyszłoby $n punktów (limit 300) — wybierz na ekranie większy krok.',
          en: 'Offset table left out: a ${_lenU(_step)} step would give $n points (limit 300) — pick a larger step on screen.');
    }
    return null;
  }

  List<String> _coneSummary(ConeResult r) {
    final i = r.input;
    final w = r.whole, p = r.part;
    return [
      'D ${_len(i.largeDiaMm)} / d ${_len(i.smallDiaMm)} $_u (${_refText(i.ref)}), '
          't ${_len(i.thicknessMm)} $_u · Dm ${_len(r.meanLargeMm)} / dm ${_len(r.meanSmallMm)} $_u',
      'H ${_len(r.heightMm)} $_u · L ${_len(r.slantMm)} $_u · α ${_deg(r.halfAngleDeg)}',
      'R ${_len(r.outerRadiusMm)} $_u · r ${_len(r.innerRadiusMm)} $_u · θ ${_deg(r.sectorAngleDeg)}',
      '${context.tr(pl: 'Łuki', en: 'Arcs')} ${_len(r.outerArcMm)} / ${_len(r.innerArcMm)} $_u · '
          '${context.tr(pl: 'cięciwy', en: 'chords')} ${_len(w.outerChordMm)} / ${_len(w.innerChordMm)} $_u · '
          '${context.tr(pl: 'strzałki', en: 'arc heights')} ${_len(w.outerSagittaMm)} / ${_len(w.innerSagittaMm)} $_u',
      '${context.tr(pl: 'Prostokąt blachy', en: 'Plate rectangle')} ${_len(w.widthMm)} × ${_len(w.heightMm)} $_u · '
          '${context.tr(pl: 'przekątna kontrolna', en: 'check diagonal')} ${_len(w.diagonalMm)} $_u',
      if (r.parts > 1)
        '${context.tr(pl: 'Części', en: 'Parts')}: ${r.parts} × θ ${_deg(p.angleDeg)} · '
            '${context.tr(pl: 'łuki', en: 'arcs')} ${_len(p.outerArcMm)} / ${_len(p.innerArcMm)} $_u · '
            '${context.tr(pl: 'cięciwy', en: 'chords')} ${_len(p.outerChordMm)} / ${_len(p.innerChordMm)} $_u · '
            '${context.tr(pl: 'prostokąt', en: 'rectangle')} ${_len(p.widthMm)} × ${_len(p.heightMm)} $_u',
      if (i.allowanceMm > 0)
        '${context.tr(pl: 'Naddatek na zakład', en: 'Seam allowance')} ${_len(i.allowanceMm)} $_u',
    ];
  }

  String _coneText(ConeResult r, bool withOrdinates) {
    final lines = <String>[
      '${context.tr(pl: 'Rozwinięcie stożka ściętego', en: 'Concentric cone flat pattern')} (Fitter Welder Pro)',
      ..._coneSummary(r),
    ];
    final part = r.part;
    if (withOrdinates) {
      final skipped = _ordinatesSkipped(part);
      if (skipped != null) {
        lines
          ..add('')
          ..add(skipped);
      } else {
        for (final t in _ordinateTables(r, part)) {
          lines
            ..add('')
            ..add(t.title)
            ..addAll([for (final row in t.rows) '  x ${row[0]} → y ${row[1]}']);
        }
      }
    }
    lines
      ..add('')
      ..add(_neutralNote());
    return lines.join('\n');
  }

  // ── Stożek mimośrodowy ───────────────────────────────────────────────────

  _Outcome _eccentric() {
    final input = _eccInput;
    final inputs = [
      QuoteSection(
        title: context.tr(
            pl: 'Wymiary stożka mimośrodowego',
            en: 'Eccentric cone dimensions'),
        children: [
          FieldPair(
            left: _numField(
                _dL, context.tr(pl: 'Średnica duża D', en: 'Large dia. D'),
                key: 'cone-D'),
            right: _numField(
                _dS, context.tr(pl: 'Średnica mała d', en: 'Small dia. d'),
                key: 'cone-d',
                helper:
                    context.tr(pl: '0 = stożek pełny', en: '0 = full cone')),
          ),
          const SizedBox(height: 10),
          _numField(_h, context.tr(pl: 'Wysokość H', en: 'Height H'),
              key: 'cone-H'),
          _caption(context.tr(pl: 'Przesunięcie osi', en: 'Axis offset')),
          _chips<bool>([
            (
              true,
              'cone-ecc-vertical',
              context.tr(pl: 'jedna tworząca pionowa', en: 'one vertical side')
            ),
            (
              false,
              'cone-ecc-custom',
              context.tr(pl: 'przesunięcie e', en: 'offset e')
            ),
          ], _vertical, (v) => _vertical = v),
          if (!_vertical) ...[
            const SizedBox(height: 10),
            _numField(
                _e,
                context.tr(
                    pl: 'Przesunięcie e (między środkami)',
                    en: 'Offset e (centre to centre)'),
                key: 'cone-e'),
          ],
          ..._thicknessBlock(),
          ..._divisionsAndParts(),
          _caption(context.tr(pl: 'Szew', en: 'Seam')),
          _chips<bool>([
            (
              true,
              'cone-seam-short',
              context.tr(pl: 'po krótkiej stronie', en: 'on the short side')
            ),
            (
              false,
              'cone-seam-long',
              context.tr(pl: 'po długiej stronie', en: 'on the long side')
            ),
          ], _seamShort, (v) => _seamShort = v),
        ],
      ),
    ];
    final problems = input.problems;
    final r = computeEccentricCone(input);
    if (problems.isNotEmpty || r == null) {
      return _Outcome(
          inputs: inputs, problems: problems.map(_eccProblem).toList());
    }
    final view = _viewPart.clamp(0, r.parts.length - 1);
    final part = r.parts[view];
    final n = input.divisions;
    final planShort = (r.meanLargeMm * math.pi) - n * r.planChordBottomMm;
    final rowsTable = [
      for (final row in r.rows)
        [
          '${row.index}',
          _deg(row.phiDeg, d: 1),
          _len(row.generatorMm),
          row.bottomChordMm == null ? '—' : _len(row.bottomChordMm!),
          row.topChordMm == null ? '—' : _len(row.topChordMm!),
          row.diagonalMm == null ? '—' : _len(row.diagonalMm!),
        ],
    ];
    final headers = [
      '#',
      'φ',
      context.tr(pl: "j–j' (tworząca)", en: "j–j' (generator)"),
      'j→j+1',
      "j'→(j+1)'",
      "j'→j+1",
    ];
    final coordRows = _coordRowsEcc(part, r.isFull);
    final coordHeaders = [
      context.tr(pl: 'Pkt', en: 'Pt'),
      'X',
      'Y',
      if (!r.isFull) ...["X'", "Y'"],
    ];
    final results = <Widget>[
      QuoteSection(
        title: context.tr(pl: 'Rozwinięcie', en: 'Flat pattern'),
        children: [
          Readout(
            key: const ValueKey('cone-ecc-rect'),
            label: context.tr(
                pl: 'Prostokąt blachy — ${_partName(view).toLowerCase()}',
                en: 'Plate rectangle — ${_partName(view).toLowerCase()}'),
            value: '${_len(part.widthMm)} × ${_len(part.heightMm)}',
            unit: _u,
            hot: true,
          ),
          const SizedBox(height: 12),
          _kv(
              context.tr(
                  pl: 'Średnice obliczeniowe Dm / dm',
                  en: 'Neutral diameters Dm / dm'),
              '${_len(r.meanLargeMm)} / ${_len(r.meanSmallMm)} $_u'),
          _kv(context.tr(pl: 'Przesunięcie osi e', en: 'Axis offset e'),
              _lenU(r.offsetMm),
              key: const ValueKey('cone-ecc-e')),
          _kv(
              context.tr(
                  pl: 'Tworząca najkrótsza / najdłuższa',
                  en: 'Shortest / longest side'),
              '${_len(r.shortestGeneratorMm)} / ${_len(r.longestGeneratorMm)} $_u',
              key: const ValueKey('cone-ecc-gen')),
          _kv(
              context.tr(
                  pl: 'Pochylenie boków od pionu',
                  en: 'Side slope from vertical'),
              '${_deg(r.shortSideAngleDeg, d: 1)} / ${_deg(r.longSideAngleDeg, d: 1)}'),
          _kv(
              context.tr(
                  pl: 'Krawędź dolna / górna na blasze',
                  en: 'Lower / upper edge on the plate'),
              '${_len(r.bottomEdgeMm)} / ${_len(r.topEdgeMm)} $_u'),
          _kv(
              context.tr(
                  pl: 'Kąt rozwinięcia wokół wierzchołka',
                  en: 'Developed angle at the apex'),
              _deg(r.developedAngleDeg)),
        ],
      ),
      QuoteSection(
        title: context.tr(pl: 'Podgląd', en: 'Preview'),
        subtitle: context.tr(
            pl: 'Linie ciągłe — tworzące, cienkie — przekątne triangulacji. Numery od szwu.',
            en: 'Solid lines — generators, thin — triangulation diagonals. Numbers from the seam.'),
        children: [
          _partPicker(r.parts.length, _partName),
          _PatternView(part: part),
        ],
      ),
      QuoteSection(
        title: context.tr(
            pl: 'Linie prawdziwe (triangulacja)',
            en: 'True lengths (triangulation)'),
        subtitle: context.tr(
            pl: "j — punkt dolny (duże koło), j' — górny. Cięciwy i przekątne NA BLASZE: "
                'trasuj trójkątami z tych długości. Cięciwa w rzucie (${_lenU(r.planChordBottomMm)}) '
                'skróciłaby obwód o ${_lenU(planShort)}.',
            en: "j — lower point (large circle), j' — upper. Chords and diagonals ON THE PLATE: "
                'mark triangles with these lengths. The plan chord (${_lenU(r.planChordBottomMm)}) '
                'would shorten the edge by ${_lenU(planShort)}.'),
        children: [
          _grid('cone-ecc-table', headers, rowsTable,
              copyLabel: context.tr(pl: 'Linie prawdziwe', en: 'True lengths')),
        ],
      ),
      QuoteSection(
        title: context.tr(
            pl: 'Współrzędne punktów — ${_partName(view).toLowerCase()}',
            en: 'Point coordinates — ${_partName(view).toLowerCase()}'),
        subtitle: context.tr(
            pl: 'X od lewej, Y od dołu prostokąta blachy ($_u).',
            en: 'X from the left, Y from the bottom of the plate rectangle ($_u).'),
        children: [
          _grid('cone-ecc-coords', coordHeaders, coordRows,
              copyLabel: context.tr(pl: 'Współrzędne', en: 'Coordinates')),
        ],
      ),
    ];
    final shapes = [
      for (final (p, pt) in r.parts.indexed)
        _shapeOf(
            pt,
            r.parts.length > 1
                ? _partName(p)
                : context.tr(pl: 'Rozwinięcie', en: 'Flat pattern')),
    ];
    final summary = [
      'D ${_len(input.largeDiaMm)} / d ${_len(input.smallDiaMm)} $_u (${_refText(input.ref)}), '
          't ${_len(input.thicknessMm)} $_u, H ${_len(input.heightMm)} $_u, e ${_len(r.offsetMm)} $_u',
      'Dm ${_len(r.meanLargeMm)} / dm ${_len(r.meanSmallMm)} $_u · '
          '${context.tr(pl: 'tworzące', en: 'sides')} ${_len(r.shortestGeneratorMm)}–${_len(r.longestGeneratorMm)} $_u · '
          '${context.tr(pl: 'podział', en: 'divisions')} $n · ${context.tr(pl: 'części', en: 'parts')} ${r.parts.length}',
      for (final (p, pt) in r.parts.indexed)
        '${_partName(p)}: ${_len(pt.widthMm)} × ${_len(pt.heightMm)} $_u',
    ];
    final tables = [
      FlatTemplateTable(
          context.tr(
              pl: 'Linie prawdziwe i długości na blasze',
              en: 'True lengths and plate lengths'),
          headers,
          rowsTable),
      for (final (p, pt) in r.parts.indexed)
        FlatTemplateTable(
            '${context.tr(pl: 'Współrzędne', en: 'Coordinates')} — ${_partName(p)} ($_u)',
            coordHeaders,
            _coordRowsEcc(pt, r.isFull)),
    ];
    return _Outcome(
      inputs: inputs,
      problems: const [],
      results: results,
      shareText: _tablesText(
          context.tr(
              pl: 'Stożek mimośrodowy — rozwinięcie',
              en: 'Eccentric cone — flat pattern'),
          summary,
          tables),
      shapes: shapes,
      partSizes: [for (final p in r.parts) (p.widthMm, p.heightMm)],
      fileName:
          'stozek_mimosrodowy_${_num(r.meanLargeMm, 0)}_${_num(r.meanSmallMm, 0)}.pdf',
      spec: (paper) => FlatTemplateSpec(
        title: context.tr(
            pl: 'Rozwinięcie stożka mimośrodowego',
            en: 'Eccentric cone flat pattern'),
        summaryLines: summary,
        tables: tables,
        instructions: [
          context.tr(
              pl: "Punkty j na dużej krawędzi, j' na małej. Tworzące j–j' przerywane — linie zwijania.",
              en: "Points j on the large edge, j' on the small one. Dashed generators j–j' — rolling lines."),
        ],
        note: _neutralNote(),
        shapes: shapes,
        paper: paper,
      ),
    );
  }

  List<List<String>> _coordRowsEcc(FlatPatternPart part, bool full) {
    final bottom = <String, Pt>{};
    final top = <String, Pt>{};
    for (final m in part.marks) {
      if (m.label.endsWith("'")) {
        top[m.label.substring(0, m.label.length - 1)] = m.at;
      } else {
        bottom[m.label] = m.at;
      }
    }
    return [
      for (final e in bottom.entries)
        [
          e.key,
          _len(e.value.x),
          _len(e.value.y),
          if (!full) ...[
            top[e.key] == null ? '—' : _len(top[e.key]!.x),
            top[e.key] == null ? '—' : _len(top[e.key]!.y),
          ],
        ],
    ];
  }

  // ── Przejście kwadrat–koło ───────────────────────────────────────────────

  _Outcome _transition() {
    final input = _trInput;
    final inputs = [
      QuoteSection(
        title: context.tr(pl: 'Wymiary przejścia', en: 'Transition dimensions'),
        subtitle: context.tr(
            pl: 'Prostokąt A × B (A wzdłuż X), koło D na wysokości H. Naroża A, B, C, D przeciwnie do zegara od +X+Y.',
            en: 'Rectangle A × B (A along X), circle D at height H. Corners A, B, C, D anticlockwise from +X+Y.'),
        children: [
          FieldPair(
            left: _numField(_a, context.tr(pl: 'Bok A', en: 'Side A'),
                key: 'tr-A'),
            right: _numField(_b, context.tr(pl: 'Bok B', en: 'Side B'),
                key: 'tr-B'),
          ),
          const SizedBox(height: 10),
          FieldPair(
            left: _numField(
                _dT, context.tr(pl: 'Średnica koła D', en: 'Circle dia. D'),
                key: 'tr-D'),
            right: _numField(_hT, context.tr(pl: 'Wysokość H', en: 'Height H'),
                key: 'tr-H'),
          ),
          const SizedBox(height: 10),
          FieldPair(
            left: _numField(_ex,
                context.tr(pl: 'Przesunięcie koła X', en: 'Circle offset X'),
                key: 'tr-ex', signed: true),
            right: _numField(_ey,
                context.tr(pl: 'Przesunięcie koła Y', en: 'Circle offset Y'),
                key: 'tr-ey', signed: true),
          ),
          ..._thicknessBlock(),
          ..._divisionsAndParts(),
          _caption(context.tr(pl: 'Szew', en: 'Seam')),
          _chips<TransitionSeam>([
            (
              TransitionSeam.sideA,
              'tr-seam-sideA',
              context.tr(pl: 'środek boku A', en: 'middle of side A')
            ),
            (
              TransitionSeam.sideB,
              'tr-seam-sideB',
              context.tr(pl: 'środek boku B', en: 'middle of side B')
            ),
            (
              TransitionSeam.corner,
              'tr-seam-corner',
              context.tr(pl: 'w narożu', en: 'at a corner')
            ),
          ], _seam, (v) => _seam = v),
        ],
      ),
    ];
    final problems = input.problems;
    final r = computeTransition(input);
    if (problems.isNotEmpty || r == null) {
      return _Outcome(
          inputs: inputs, problems: problems.map(_trProblem).toList());
    }
    final view = _viewPart.clamp(0, r.parts.length - 1);
    final tp = r.parts[view];
    final part = tp.pattern;
    List<List<String>> lineRows(TransitionPart p) => [
          for (final l in p.trueLines) [l.label, _len(l.lengthMm)],
        ];
    List<List<String>> chordRows(TransitionPart p) => [
          for (final l in p.topChords) [l.label, _len(l.lengthMm)],
          for (final l in p.bottomEdges) [l.label, _len(l.lengthMm)],
        ];
    List<List<String>> coordRows(TransitionPart p) => [
          for (final m in p.pattern.marks)
            [m.label, _len(m.at.x), _len(m.at.y)],
        ];
    String sameNote(TransitionPart p) => p.sameAs == null
        ? ''
        : p.mirrored
            ? context.tr(
                pl:
                    ' = część ${p.sameAs! + 1} w odbiciu lustrzanym (odwróć szablon)',
                en: ' = part ${p.sameAs! + 1} mirrored (flip the template)')
            : context.tr(
                pl: ' = część ${p.sameAs! + 1}',
                en: ' = part ${p.sameAs! + 1}');
    final pt = context.tr(pl: 'Pkt', en: 'Pt');
    final lineH = [
      context.tr(pl: 'Linia', en: 'Line'),
      context.tr(pl: 'Długość', en: 'Length')
    ];
    final results = <Widget>[
      QuoteSection(
        title: context.tr(pl: 'Rozwinięcie', en: 'Flat pattern'),
        children: [
          Readout(
            key: const ValueKey('tr-rect'),
            label: context.tr(
                pl: 'Prostokąt blachy — ${_partName(view).toLowerCase()}',
                en: 'Plate rectangle — ${_partName(view).toLowerCase()}'),
            value: '${_len(part.widthMm)} × ${_len(part.heightMm)}',
            unit: _u,
            hot: true,
          ),
          const SizedBox(height: 12),
          _kv(
              context.tr(
                  pl: 'Wymiary obliczeniowe A × B, D', en: 'Neutral A × B, D'),
              '${_len(r.meanAMm)} × ${_len(r.meanBMm)}, ${_len(r.meanDMm)} $_u'),
          for (final s in r.sides)
            _kv(
                context.tr(
                    pl: 'Trójkąt na boku ${s.label}: wysokość',
                    en: 'Triangle on side ${s.label}: height'),
                _lenU(s.heightMm)),
          _kv(
              context.tr(
                  pl: 'Krawędź prostokąta / koła na blasze',
                  en: 'Rectangle / circle edge on the plate'),
              '${_len(r.bottomEdgeMm)} / ${_len(r.topEdgeMm)} $_u',
              key: const ValueKey('tr-edges')),
          _kv(
              context.tr(
                  pl: 'Największe pochylenie ścianki od pionu',
                  en: 'Steepest wall slope from vertical'),
              _deg(r.maxWallSlopeDeg, d: 1),
              key: const ValueKey('tr-slope')),
        ],
      ),
      if (r.steepWalls)
        QuoteNotice(
          key: const ValueKey('tr-slope-note'),
          text: context.tr(
              pl: 'Ścianki pochylone do ${_deg(r.maxWallSlopeDeg, d: 1)} od pionu. Program liczy wymiar ∓ t, '
                  'a przy pochylonej ściance oś obojętna w płaszczyźnie podstawy leży o t/(2·cos β) od powierzchni — '
                  'różnica do ${_lenU(r.neutralShiftErrorMm, d: _inch ? 3 : 2)} na stronę. Przy grubej blasze '
                  'uwzględnij to przy trasowaniu (albo podaj wymiary średnie).',
              en: 'Walls slope up to ${_deg(r.maxWallSlopeDeg, d: 1)} from vertical. The tool uses size ∓ t, '
                  'but on a sloping wall the neutral axis in the base plane lies t/(2·cos β) from the surface — '
                  'up to ${_lenU(r.neutralShiftErrorMm, d: _inch ? 3 : 2)} per side. With thick plate allow '
                  'for it when marking (or enter mean sizes).'),
        ),
      if (input.circleOverhangs)
        QuoteNotice(
          key: const ValueKey('tr-overhang'),
          text: context.tr(
              pl: 'Koło w rzucie wystaje poza prostokąt — kształt nietypowy, sprawdź rysunek przed cięciem.',
              en: 'In plan the circle sticks out of the rectangle — unusual shape, check the drawing before cutting.'),
        ),
      QuoteSection(
        title: context.tr(pl: 'Podgląd', en: 'Preview'),
        subtitle: context.tr(
            pl: 'Linie przerywane — linie gięcia (z naroży do punktów koła). Numery punktów koła od +X.',
            en: 'Dashed lines — bend lines (corners to circle points). Circle points numbered from +X.'),
        children: [
          _partPicker(r.parts.length, _partName),
          if (tp.sameAs != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${_partName(view)}${sameNote(tp)}',
                  key: const ValueKey('tr-same'),
                  style: const TextStyle(color: kTextSec, fontSize: 12.5)),
            ),
          _PatternView(part: part),
        ],
      ),
      QuoteSection(
        title: context.tr(
            pl: 'Linie prawdziwe — ${_partName(view).toLowerCase()}',
            en: 'True lengths — ${_partName(view).toLowerCase()}'),
        subtitle: context.tr(
            pl: 'Od szwu kolejno. Cięciwy koła NA BLASZE (w rzucie ${_lenU(r.planChordMm)} — nie używaj, skraca obwód).',
            en: 'In order from the seam. Circle chords ON THE PLATE (plan chord ${_lenU(r.planChordMm)} — do not use, it shortens the edge).'),
        children: [
          _grid('tr-lines', lineH, lineRows(tp),
              copyLabel: context.tr(pl: 'Linie prawdziwe', en: 'True lengths')),
          const SizedBox(height: 10),
          Text(context.tr(pl: 'Cięciwy i boki', en: 'Chords and sides'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          _grid('tr-chords', lineH, chordRows(tp)),
        ],
      ),
      QuoteSection(
        title: context.tr(
            pl: 'Współrzędne punktów — ${_partName(view).toLowerCase()}',
            en: 'Point coordinates — ${_partName(view).toLowerCase()}'),
        subtitle: context.tr(
            pl: 'X od lewej, Y od dołu prostokąta blachy ($_u).',
            en: 'X from the left, Y from the bottom of the plate rectangle ($_u).'),
        children: [
          _grid('tr-coords', [pt, 'X', 'Y'], coordRows(tp),
              copyLabel: context.tr(pl: 'Współrzędne', en: 'Coordinates')),
        ],
      ),
    ];
    final printed = [
      for (final (p, x) in r.parts.indexed)
        if (x.sameAs == null)
          _shapeOf(
              x.pattern,
              r.parts.length == 1
                  ? context.tr(pl: 'Rozwinięcie', en: 'Flat pattern')
                  : '${_partName(p)}'
                      '${r.parts.where((o) => o.sameAs == p).isEmpty ? '' : ' (+ ${[
                          for (final (q, o) in r.parts.indexed)
                            if (o.sameAs == p)
                              '${q + 1}${o.mirrored ? context.tr(pl: ' lustro', en: ' mirror') : ''}'
                        ].join(', ')})'}'),
    ];
    final summary = [
      'A ${_len(input.sideAMm)} × B ${_len(input.sideBMm)} $_u, D ${_len(input.diameterMm)} $_u (${_refText(input.ref)}), '
          't ${_len(input.thicknessMm)} $_u, H ${_len(input.heightMm)} $_u, '
          '${context.tr(pl: 'przesunięcie', en: 'offset')} ${_len(input.offsetXMm)} / ${_len(input.offsetYMm)} $_u',
      '${context.tr(pl: 'Podział', en: 'Divisions')} ${input.divisions} · ${context.tr(pl: 'części', en: 'parts')} ${r.parts.length}',
      for (final s in r.sides)
        '${context.tr(pl: 'Trójkąt', en: 'Triangle')} ${s.label}: ${context.tr(pl: 'bok', en: 'side')} ${_len(s.lengthMm)}, '
            '${context.tr(pl: 'wysokość', en: 'height')} ${_len(s.heightMm)} $_u',
      for (final (p, x) in r.parts.indexed)
        '${_partName(p)}: ${_len(x.pattern.widthMm)} × ${_len(x.pattern.heightMm)} $_u${sameNote(x)}',
      if (r.steepWalls)
        context.tr(
            pl: 'Uwaga: ścianki pochylone do ${_deg(r.maxWallSlopeDeg, d: 1)} — oś obojętna w podstawie '
                'przesunięta o t/(2·cos β), różnica do ${_lenU(r.neutralShiftErrorMm, d: _inch ? 3 : 2)} na stronę względem ∓ t.',
            en: 'Note: walls slope up to ${_deg(r.maxWallSlopeDeg, d: 1)} — the neutral axis in the base '
                'shifts by t/(2·cos β), up to ${_lenU(r.neutralShiftErrorMm, d: _inch ? 3 : 2)} per side more than ∓ t.'),
    ];
    final tables = [
      for (final (p, x) in r.parts.indexed)
        if (x.sameAs == null) ...[
          FlatTemplateTable(
              '${context.tr(pl: 'Linie prawdziwe', en: 'True lengths')} — ${_partName(p)} ($_u)',
              lineH,
              [...lineRows(x), ...chordRows(x)]),
          FlatTemplateTable(
              '${context.tr(pl: 'Współrzędne', en: 'Coordinates')} — ${_partName(p)} ($_u)',
              [pt, 'X', 'Y'],
              coordRows(x)),
        ],
    ];
    return _Outcome(
      inputs: inputs,
      problems: const [],
      results: results,
      shareText: _tablesText(
          context.tr(
              pl: 'Przejście kwadrat–koło — rozwinięcie',
              en: 'Square to round — flat pattern'),
          summary,
          tables),
      shapes: printed,
      partSizes: [
        for (final x in r.parts)
          if (x.sameAs == null) (x.pattern.widthMm, x.pattern.heightMm)
      ],
      fileName:
          'przejscie_${_num(r.meanAMm, 0)}x${_num(r.meanBMm, 0)}_${_num(r.meanDMm, 0)}.pdf',
      spec: (paper) => FlatTemplateSpec(
        title: context.tr(
            pl: 'Rozwinięcie przejścia kwadrat–koło',
            en: 'Square to round flat pattern'),
        summaryLines: summary,
        tables: tables,
        instructions: [
          context.tr(
              pl: 'Naroża A–D na krawędzi prostokąta, punkty koła 1…N. Linie przerywane — gięcie (z naroża do punktów koła).',
              en: 'Corners A–D on the rectangle edge, circle points 1…N. Dashed lines — bends (corner to circle points).'),
        ],
        note: _neutralNote(),
        shapes: printed,
        paper: paper,
      ),
    );
  }

  String _tablesText(
      String title, List<String> summary, List<FlatTemplateTable> tables) {
    final lines = <String>['$title (Fitter Welder Pro)', ...summary];
    for (final t in tables) {
      lines
        ..add('')
        ..add(t.title)
        ..add(t.headers.join(' | '))
        ..addAll([for (final r in t.rows) r.join(' | ')]);
    }
    lines
      ..add('')
      ..add(_neutralNote());
    return lines.join('\n');
  }

  FlatTemplateShape _shapeOf(FlatPatternPart p, String name) =>
      FlatTemplateShape(
        name: name,
        widthMm: p.widthMm,
        heightMm: p.heightMm,
        cutLines: [p.outline],
        bendLines: p.bendLines,
        dashedLines: [if (p.allowance.isNotEmpty) p.allowance],
        labels: [
          for (final m in p.marks) FlatTemplateLabel(m.at.x, m.at.y, m.label)
        ],
      );

  // ── Arkusz i wydruk ──────────────────────────────────────────────────────

  Widget _printSection(_Outcome out) {
    final sheet = _sheet;
    final sizes = out.partSizes;
    final sheets = flatTemplateSheetCount(sizes, _paper);
    final tooBig = _printTooBig(out);
    final fits = sheet == null
        ? null
        : sizes.every((s) => fitsRect(s.$1, s.$2, sheet.$1, sheet.$2));
    return QuoteSection(
      key: const ValueKey('cone-print'),
      title:
          context.tr(pl: 'Blacha i szablon 1:1', en: 'Plate and 1:1 template'),
      children: [
        FieldPair(
          left: _numField(
              _sheetW, context.tr(pl: 'Arkusz — szerokość', en: 'Sheet width'),
              key: 'cone-sheet-w'),
          right: _numField(
              _sheetL, context.tr(pl: 'Arkusz — długość', en: 'Sheet length'),
              key: 'cone-sheet-l'),
        ),
        if (fits != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                    fits
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: fits ? kPass : kWarn),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fits
                        ? context.tr(
                            pl: 'Każda część mieści się na arkuszu.',
                            en: 'Every part fits the sheet.')
                        : context.tr(
                            pl: 'Część nie mieści się na arkuszu — zwiększ podział.',
                            en: 'A part does not fit the sheet — split it further.'),
                    key: const ValueKey('cone-fit'),
                    style: const TextStyle(fontSize: 13, color: kTextSec),
                  ),
                ),
              ],
            ),
          ),
        _caption(context.tr(pl: 'Kartki do druku', en: 'Print sheets')),
        _chips<TemplatePaper>([
          (TemplatePaper.a4, 'cone-paper-a4', 'A4'),
          (TemplatePaper.a3, 'cone-paper-a3', 'A3'),
        ], _paper, (v) => _paper = v),
        const SizedBox(height: 10),
        if (tooBig)
          QuoteNotice(
            key: const ValueKey('cone-pdf-too-big'),
            text: context.tr(
                pl: 'Wydruk byłby na $sheets arkuszach ${_paper.label} — trasuj z tabeli.',
                en: 'The print would take $sheets ${_paper.label} sheets — mark out from the table.'),
          )
        else
          FilledButton.icon(
            key: const ValueKey('cone-pdf'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: kArc,
              foregroundColor: kOnArc,
            ),
            onPressed: _exporting || out.spec == null
                ? null
                : () => unawaited(_sharePdf(out.spec!(_paper), out.fileName)),
            icon: const Icon(Icons.print_outlined),
            label: Text(
                context.tr(
                    pl: 'Szablon 1:1 do druku (PDF, $sheets ark. ${_paper.label})',
                    en: '1:1 printable template (PDF, $sheets ${_paper.label} sheets)'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('cone-share-text'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kMinTapTarget)),
          onPressed:
              out.shareText == null ? null : () => _shareText(out.shareText!),
          icon: const Icon(Icons.share_outlined),
          label: Text(context.tr(
              pl: 'Udostępnij wymiary (tekst)', en: 'Share dimensions (text)')),
        ),
      ],
    );
  }
}

/// Wynik budowy jednego kształtu: pola, komunikaty, wyniki, eksport.
class _Outcome {
  final List<Widget> inputs;
  final List<String> problems;
  final List<Widget> results;
  final String? shareText;
  final List<FlatTemplateShape> shapes;
  final List<(double, double)> partSizes;
  final String fileName;
  final FlatTemplateSpec Function(TemplatePaper paper)? spec;

  const _Outcome({
    required this.inputs,
    required this.problems,
    this.results = const [],
    this.shareText,
    this.shapes = const [],
    this.partSizes = const [],
    this.fileName = 'rozwiniecie.pdf',
    this.spec,
  });
}

/// Podgląd rozwinięcia: obrys, linie gięcia, przekątne, naddatek, punkty.
class _PatternView extends StatelessWidget {
  final FlatPatternPart part;
  const _PatternView({required this.part});

  @override
  Widget build(BuildContext context) {
    final ratio = part.heightMm > 0
        ? (part.widthMm / part.heightMm).clamp(0.8, 2.2)
        : 1.4;
    return AspectRatio(
      key: const ValueKey('cone-preview'),
      aspectRatio: ratio,
      child: CustomPaint(painter: _PatternPainter(part)),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final FlatPatternPart p;
  _PatternPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 14.0;
    final w = math.max(p.widthMm, 1e-6), h = math.max(p.heightMm, 1e-6);
    final s = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * s) / 2, oy = (size.height - h * s) / 2;
    Offset map(Pt q) => Offset(ox + q.x * s, size.height - oy - q.y * s);
    Path path(List<Pt> pts, {bool close = false}) {
      final path = Path();
      if (pts.isEmpty) return path;
      path.moveTo(map(pts.first).dx, map(pts.first).dy);
      for (final q in pts.skip(1)) {
        path.lineTo(map(q).dx, map(q).dy);
      }
      if (close) path.close();
      return path;
    }

    // Prostokąt blachy.
    final rect = Rect.fromLTWH(ox, oy, w * s, h * s);
    canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = kBorder);
    // Naddatek.
    if (p.allowance.isNotEmpty) {
      final a = path(p.allowance, close: true);
      canvas.drawPath(a, Paint()..color = kWarn.withValues(alpha: 0.18));
      canvas.drawPath(
          a,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = kWarn);
    }
    // Rozwinięcie.
    final outline = path(p.outline, close: true);
    canvas.drawPath(outline, Paint()..color = kArc.withValues(alpha: 0.12));
    final helper = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = kTextMut.withValues(alpha: 0.7);
    for (final l in p.helperLines) {
      canvas.drawPath(path(l), helper);
    }
    final bend = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = kTextSec;
    for (final l in p.bendLines) {
      _dashed(canvas, map(l.first), map(l.last), bend);
    }
    canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = kArc);
    // Punkty.
    final dot = Paint()..color = kText;
    final every = p.marks.length <= 50 ? 1 : (p.marks.length / 40).ceil();
    for (final (i, m) in p.marks.indexed) {
      final o = map(m.at);
      canvas.drawCircle(o, 2.2, dot);
      if (i % every != 0) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: m.label,
            style: const TextStyle(color: kTextSec, fontSize: 9.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o + const Offset(3, -12));
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = b - a;
    final len = d.distance;
    if (len <= 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += 7) {
      canvas.drawLine(a + u * t, a + u * math.min(t + 4, len), paint);
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.p != p;
}
