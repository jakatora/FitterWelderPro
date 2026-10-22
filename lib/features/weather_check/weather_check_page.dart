// Warunki do spawania na otwartym terenie: temperatura, wilgotność, punkt
// rosy, wiatr, opad, metoda, osłona, materiał → werdykt, lista warunków do
// odhaczenia, zalecenia (każde z podstawą), zapis do historii, tekst i PDF.
//
// Logika i źródła: lib/domain/welding/weather_conditions.dart. Dane wpisuje
// spawacz — ekran nie pobiera pogody z internetu.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../assistant/core/tool_bridge.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/welding/weather_conditions.dart';
import '../../i18n/app_language.dart';
import '../../services/weather_check_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';
import 'weather_check_store.dart';
import 'weather_history_view.dart';
import 'weather_thresholds_view.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef WeatherShareText = Future<void> Function(String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef WeatherSharePdf = Future<void> Function(
    WeatherCheckRecord record, bool english);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Future<void> _defaultSharePdf(WeatherCheckRecord record, bool english) =>
    WeatherCheckExport.sharePdf(record, english: english);

class WeatherCheckPage extends StatefulWidget {
  const WeatherCheckPage({
    super.key,
    this.now,
    this.shareText = _defaultShareText,
    this.sharePdf = _defaultSharePdf,
    this.store = const WeatherCheckStore(),
  });

  /// Zegar (test podaje stałą datę).
  final DateTime Function()? now;
  final WeatherShareText shareText;
  final WeatherSharePdf sharePdf;
  final WeatherCheckStore store;

  @override
  State<WeatherCheckPage> createState() => _WeatherCheckPageState();
}

class _WeatherCheckPageState extends State<WeatherCheckPage>
    with ToolHandleHost<WeatherCheckPage>
    implements InputToolHandle {
  @override
  String get toolId => 'weather_check';
  @override
  Set<String> get supportedFields => const {
        'ambient_c',
        'rh_pct',
        'wind_ms',
        'process',
        'material',
        'precipitation',
        'shelter',
        'surface_state'
      };
  @override
  Map<String, Object?> get inputFields => Map.unmodifiable({
        'ambient_c': _parse(_ambient),
        'rh_pct': _parse(_rh),
        'surface_c': _parse(_surface),
        'wind_ms': _windMs,
        'process': _process.name,
        'material': _material.name,
        'precipitation': _precip.name,
        'shelter': _shelter.name,
        'surface_state': _surfaceState.name,
      });

  /// Asystent wpisuje pomiar i wybory; odhaczone warunki się czyszczą jak
  /// przy każdej zmianie pomiaru. Wszystko albo nic.
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    if (!mounted || fields.keys.any((k) => !supportedFields.contains(k))) {
      return fields.keys.toSet();
    }
    T? pick<T extends Enum>(List<T> values, String key) =>
        values.where((v) => v.name == fields[key]).firstOrNull;
    final process = pick(WeatherProcess.values, 'process');
    final material = pick(WeatherMaterial.values, 'material');
    final precip = pick(Precipitation.values, 'precipitation');
    final shelter = pick(WeatherShelter.values, 'shelter');
    final surface = pick(SurfaceState.values, 'surface_state');
    double? n(String key) =>
        fields[key] is num && (fields[key] as num).isFinite
            ? (fields[key] as num).toDouble()
            : null;
    final ambient = n('ambient_c'), rh = n('rh_pct'), wind = n('wind_ms');
    final rejected = <String>{
      if (ambient == null) 'ambient_c',
      if (rh == null) 'rh_pct',
      if (wind == null || wind < 0) 'wind_ms',
      if (process == null) 'process',
      if (material == null) 'material',
      if (precip == null) 'precipitation',
      if (shelter == null) 'shelter',
      if (surface == null) 'surface_state',
    };
    if (rejected.isNotEmpty) return rejected;
    setState(() {
      _ambient.text = weatherNumAuto(ambient!, english: _en);
      _rh.text = weatherNumAuto(rh!, english: _en);
      _windUnit = WindUnit.ms;
      _windMs = wind;
      _beaufort = null;
      _wind.text = _windField(wind!);
      _process = process!;
      _material = material!;
      _precip = precip!;
      _shelter = shelter!;
      _surfaceState = surface!;
      _checked.clear();
    });
    return {};
  }

  final _ambient = TextEditingController();
  final _rh = TextEditingController();
  final _surface = TextEditingController();
  final _wind = TextEditingController();
  final _wps = TextEditingController();
  final _place = TextEditingController();

  WindUnit _windUnit = WindUnit.ms;
  Precipitation _precip = Precipitation.none;
  WeatherProcess _process = WeatherProcess.mma111;
  WeatherShelter _shelter = WeatherShelter.none;
  WeatherMaterial _material = WeatherMaterial.carbonSteel;
  SurfaceState _surfaceState = SurfaceState.unchecked;
  WeatherThresholds _thresholds = WeatherThresholds.defaults;

  /// Zapisane progi były uszkodzone i część zastąpiono domyślnymi.
  bool _thresholdsRepaired = false;

  /// Wiatr KANONICZNIE w m/s, pełna precyzja. Pole tekstowe tylko go
  /// pokazuje w wybranej jednostce — przełączenie jednostki ani wybór
  /// z Beauforta nie zaokrągla wartości, z której liczy się werdykt.
  double? _windMs;

  /// Stopień Beauforta wybrany z opisu (null — wpisano liczbę).
  BeaufortLevel? _beaufort;

  /// Odhaczone warunki (kody). Każda zmiana pomiaru je czyści — warunek
  /// odhaczony dla innych liczb nie przechodzi na nowe.
  final Set<String> _checked = {};
  int _historyCount = 0;

  /// Ile wpisów historii pominięto przy odczycie (uszkodzone); -1 — cały
  /// zapis nieczytelny.
  int _historySkipped = 0;
  bool _busyPdf = false;
  final _resultKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    markReady();
  }

  @override
  void dispose() {
    for (final c in [_ambient, _rh, _surface, _wind, _wps, _place]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    var t = WeatherThresholds.defaults;
    var repaired = false;
    var count = 0;
    var skipped = 0;
    try {
      final th = await widget.store.loadThresholdsDetailed();
      t = th.thresholds;
      repaired = th.repaired;
    } catch (_) {
      repaired = true;
    }
    try {
      final h = await widget.store.loadHistoryDetailed();
      count = h.records.length;
      skipped = h.unreadable ? -1 : h.skipped;
    } catch (_) {
      skipped = -1;
    }
    if (!mounted) return;
    setState(() {
      _thresholds = t;
      _thresholdsRepaired = repaired;
      _historyCount = count;
      _historySkipped = skipped;
    });
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  bool get _en => context.language == AppLanguage.en;

  String _n(double v, [int decimals = 1]) =>
      weatherNum(v, decimals: decimals, english: _en);

  /// Wartość wpisana / próg — z precyzją pola (do 2 miejsc, bez zer).
  String _v(double v) => weatherNumAuto(v, english: _en);

  /// Wiatr do pola: do 2 miejsc, zaokrąglony W GÓRĘ — pokazana prędkość
  /// nigdy nie jest mniejsza od tej, z której liczy się werdykt.
  String _windField(double ms) =>
      weatherNumAuto(ceilTo(windFromMs(ms, _windUnit), 2), english: _en);

  double? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t);
  }

  /// Pole z tekstem, który nie jest liczbą (np. sam „-”).
  bool _garbage(TextEditingController c) =>
      c.text.trim().isNotEmpty && parseDecimal(c.text) == null;

  void _changed() {
    setState(_checked.clear);
  }

  // ── Wejście → ocena ────────────────────────────────────────────────────

  ({List<String> problems, WeatherInput? input}) _readInput() {
    final ambient = _parse(_ambient);
    final rh = _parse(_rh);
    final surface = _parse(_surface);
    final wind = _windMs;
    final wps = _parse(_wps);
    final problems = <String>[
      for (final p in validateWeatherFields(
          ambientC: ambient,
          rhPct: rh,
          surfaceC: surface,
          windMs: wind,
          wpsPreheatC: wps))
        _problemText(p),
      if (_garbage(_surface))
        context.tr(
            pl: 'Temperatura powierzchni: wpisz liczbę albo zostaw puste.',
            en: 'Surface temperature: enter a number or leave it empty.'),
      if (_garbage(_wps))
        context.tr(
            pl: 'Podgrzewanie z WPS: wpisz liczbę albo zostaw puste.',
            en: 'WPS preheat: enter a number or leave it empty.'),
    ];
    if (problems.isNotEmpty) return (problems: problems, input: null);
    return (
      problems: const <String>[],
      input: WeatherInput(
        ambientC: ambient!,
        rhPct: rh!,
        surfaceC: surface,
        windMs: wind!,
        windUnit: _windUnit,
        precipitation: _precip,
        process: _process,
        shelter: _shelter,
        material: _material,
        wpsPreheatC: wps,
        surfaceState: _surfaceState,
      ),
    );
  }

  String _problemText(WeatherInputProblem p) => switch (p) {
        WeatherInputProblem.ambientMissing => context.tr(
            pl: 'Podaj temperaturę powietrza.',
            en: 'Enter the air temperature.'),
        WeatherInputProblem.ambientOutOfRange => context.tr(
            pl: 'Temperatura powietrza: od -60 do 60 °C.',
            en: 'Air temperature: -60 to 60 °C.'),
        WeatherInputProblem.rhMissing => context.tr(
            pl: 'Podaj wilgotność względną (higrometr, prognoza).',
            en: 'Enter the relative humidity (hygrometer, forecast).'),
        WeatherInputProblem.rhOutOfRange => context.tr(
            pl: 'Wilgotność: większa od 0 i najwyżej 100 %.',
            en: 'Humidity: above 0 and at most 100 %.'),
        WeatherInputProblem.surfaceOutOfRange => context.tr(
            pl: 'Temperatura powierzchni: od -60 do 400 °C.',
            en: 'Surface temperature: -60 to 400 °C.'),
        WeatherInputProblem.windMissing => context.tr(
            pl: 'Podaj prędkość wiatru albo wybierz ją ze skali Beauforta.',
            en: 'Enter the wind speed or pick it from the Beaufort scale.'),
        WeatherInputProblem.windOutOfRange => context.tr(
            pl: 'Wiatr: od 0 do 60 m/s (216 km/h).',
            en: 'Wind: 0 to 60 m/s (216 km/h).'),
        WeatherInputProblem.wpsPreheatOutOfRange => context.tr(
            pl: 'Podgrzewanie z WPS: od -60 do 400 °C.',
            en: 'WPS preheat: -60 to 400 °C.'),
      };

  WeatherCheckRecord _record(WeatherAssessment a) {
    final now = _now();
    return WeatherCheckRecord.fromAssessment(
      id: now.microsecondsSinceEpoch.toString(),
      takenAt: now,
      place: _place.text.trim(),
      assessment: a,
      checked: _checked,
    );
  }

  // ── Akcje ──────────────────────────────────────────────────────────────

  Future<void> _save(WeatherAssessment a) async {
    final r = _record(a);
    unawaited(Haptic.saved());
    ({List<WeatherCheckRecord> records, int dropped})? res;
    try {
      res = await widget.store.add(r);
    } catch (e) {
      debugPrint('[weather] save failed: $e');
    }
    if (!mounted) return;
    const max = WeatherCheckStore.maxRecords;
    final String message;
    if (res == null) {
      message = context.tr(
          pl: 'Nie udało się zapisać pomiaru.',
          en: 'Could not save the check.');
    } else {
      final n = res.records.length;
      setState(() {
        _historyCount = n;
        // Uszkodzony zapis został skopiowany (…_corrupt) i nadpisany.
        _historySkipped = 0;
      });
      message = res.dropped > 0
          ? context.tr(
              pl: 'Zapisano. Usunięto najstarsze wpisy ponad limit $max: '
                  '${res.dropped}.',
              en: 'Saved. Oldest entries over the $max limit removed: '
                  '${res.dropped}.')
          : n >= WeatherCheckStore.warnRecords
              ? context.tr(
                  pl: 'Zapisano. Historia: $n z $max — po przekroczeniu '
                      'najstarsze wpisy będą usuwane; udostępnij starsze.',
                  en: 'Saved. History: $n of $max — beyond that the oldest '
                      'entries are removed; share older ones.')
              : context.tr(pl: 'Zapisano w historii.', en: 'Saved to history.');
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _shareText(WeatherAssessment a) async {
    unawaited(Haptic.tap());
    final en = _en;
    await widget.shareText(weatherCheckText(_record(a), english: en),
        weatherCheckSubject(english: en));
  }

  Future<void> _sharePdf(WeatherAssessment a) async {
    if (_busyPdf) return;
    final en = _en;
    setState(() => _busyPdf = true);
    try {
      await widget.sharePdf(_record(a), en);
    } catch (e) {
      debugPrint('[weather] pdf export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się przygotować PDF.',
              en: 'Could not prepare the PDF.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  Future<void> _openThresholds() async {
    final t = await Navigator.of(context).push<WeatherThresholds>(
        MaterialPageRoute(
            builder: (_) => WeatherThresholdsView(initial: _thresholds)));
    if (t == null || !mounted) return;
    setState(() {
      _thresholds = t;
      _checked.clear();
    });
    var saved = true;
    try {
      await widget.store.saveThresholds(t);
    } catch (e) {
      debugPrint('[weather] thresholds save failed: $e');
      saved = false;
    }
    if (!mounted) return;
    if (saved) {
      setState(() => _thresholdsRepaired = false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie udało się zapisać progów — obowiązują tylko do '
                'zamknięcia ekranu.',
            en: 'Could not save the thresholds — they apply only until this '
                'screen is closed.')),
      ));
    }
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WeatherHistoryView(
              store: widget.store,
              shareText: widget.shareText,
              sharePdf: widget.sharePdf,
            )));
    if (!mounted) return;
    try {
      final h = await widget.store.loadHistoryDetailed();
      if (mounted) {
        setState(() {
          _historyCount = h.records.length;
          _historySkipped = h.unreadable ? -1 : h.skipped;
        });
      }
    } catch (_) {}
  }

  /// Wpisany tekst → kanoniczne m/s (pełna precyzja).
  void _windTyped() {
    final v = _parse(_wind);
    setState(() {
      _windMs = v == null ? null : windToMs(v, _windUnit);
      _beaufort = null;
      _checked.clear();
    });
  }

  /// Zmiana jednostki tylko PRZERYSOWUJE pole — [_windMs] zostaje bez zmian,
  /// więc werdykt nie zależy od wyświetlanej jednostki.
  void _setUnit(WindUnit u) {
    if (u == _windUnit) return;
    setState(() {
      _windUnit = u;
      final ms = _windMs;
      if (ms != null) _wind.text = _windField(ms);
    });
  }

  void _pickBeaufort(BeaufortLevel b) {
    unawaited(Haptic.tap());
    setState(() {
      _beaufort = b;
      _windMs = b.maxMs;
      _wind.text = _windField(b.maxMs);
      _checked.clear();
    });
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final read = _readInput();
    final a =
        read.input == null ? null : assessWeather(read.input!, _thresholds);
    return Scaffold(
      appBar: AppBar(
        title: Text(
            context.tr(pl: 'Warunki do spawania', en: 'Welding conditions')),
        actions: [
          IconButton(
            key: const ValueKey('wx-thresholds'),
            tooltip: context.tr(pl: 'Ustawienia progów', en: 'Thresholds'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _openThresholds,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            key: const ValueKey('wx-history'),
            tooltip: context.tr(
                pl: 'Historia pomiarów ($_historyCount)',
                en: 'Check history ($_historyCount)'),
            constraints: const BoxConstraints(
                minWidth: kMinTapTarget, minHeight: kMinTapTarget),
            onPressed: _openHistory,
            icon: Badge(
              isLabelVisible: _historyCount > 0,
              label: Text('$_historyCount'),
              child: const Icon(Icons.history),
            ),
          ),
        ],
      ),
      // Werdykt zawsze na dole ekranu — spawacz widzi skutek każdej zmiany
      // pola bez przewijania do wyniku.
      bottomNavigationBar: _verdictBar(a),
      // Ekran jest krótki — budujemy go całego (nie ListView), żeby
      // „Szczegóły” z paska zawsze miały dokąd przewinąć.
      body: SingleChildScrollView(
        key: const ValueKey('wx-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_thresholdsRepaired)
              QuoteNotice(
                key: const ValueKey('wx-thresholds-repaired'),
                color: kFail,
                icon: Icons.report_problem_outlined,
                text: context.tr(
                    pl: 'Zapisane progi były uszkodzone — nieczytelne wartości '
                        'zastąpiono domyślnymi (z norm). Jeśli projekt ma '
                        'własne progi, wpisz je ponownie w „Ustawieniach '
                        'progów”.',
                    en: 'The saved thresholds were damaged — unreadable values '
                        'were replaced with the defaults (code values). If the '
                        'project has its own thresholds, enter them again in '
                        '“Thresholds”.'),
              ),
            if (_historySkipped != 0)
              QuoteNotice(
                key: const ValueKey('wx-history-damaged'),
                color: kFail,
                icon: Icons.report_problem_outlined,
                text: _historyDamagedText(_historySkipped),
              ),
            if (!_thresholds.isDefault) _customThresholdsNotice(),
            _measureSection(),
            _windSection(),
            _precipSection(),
            _processSection(),
            _materialSection(),
            if (a == null)
              QuoteNotice(
                key: const ValueKey('wx-problems'),
                color: kTextSec,
                icon: Icons.edit_note,
                text: read.problems.isEmpty
                    ? context.tr(
                        pl: 'Nie da się policzyć punktu rosy dla tych danych.',
                        en: 'The dew point cannot be computed for these values.')
                    : read.problems.join('\n'),
              )
            else ...[
              KeyedSubtree(key: _resultKey, child: _resultSection(a)),
              if (a.stops.isNotEmpty) _stopsSection(a),
              if (a.conditions.isNotEmpty) _conditionsSection(a),
              _passedSection(a),
              if (a.recommendations.isNotEmpty) _recommendationsSection(a),
              _saveSection(a),
            ],
            QuoteNotice(
              key: const ValueKey('wx-disclaimer'),
              text: weatherDisclaimer(english: _en),
            ),
          ],
        ),
      ),
    );
  }

  String _historyDamagedText(int skipped) => skipped < 0
      ? context.tr(
          pl: 'Zapis historii pomiarów jest nieczytelny — nie da się go '
              'pokazać. Przy następnym zapisie jego kopia trafi pod '
              '„${WeatherCheckStore.corruptHistoryKey}”.',
          en: 'The saved check history is unreadable and cannot be shown. On '
              'the next save a copy is kept under '
              '“${WeatherCheckStore.corruptHistoryKey}”.')
      : context.tr(
          pl: 'Historia: $skipped uszkodzonych wpisów pominięto. Przy '
              'następnym zapisie kopia całego zapisu trafi pod '
              '„${WeatherCheckStore.corruptHistoryKey}”.',
          en: 'History: $skipped damaged entries skipped. On the next save a '
              'copy of the whole record is kept under '
              '“${WeatherCheckStore.corruptHistoryKey}”.');

  void _scrollToResult() {
    final ctx = _resultKey.currentContext;
    if (ctx == null) return;
    unawaited(Haptic.tap());
    unawaited(Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
  }

  Widget _verdictBar(WeatherAssessment? a) {
    final (Color color, IconData icon, String text) = a == null
        ? (
            kTextSec,
            Icons.edit_note,
            context.tr(
                pl: 'Uzupełnij pomiar, żeby zobaczyć werdykt',
                en: 'Complete the measurement to see the verdict'),
          )
        : switch (a.verdict) {
            WeatherVerdict.go => (
                kPass,
                Icons.check_circle_outline,
                weatherVerdictText(a.verdict, english: _en)
              ),
            WeatherVerdict.conditional => (
                kWarn,
                Icons.rule,
                weatherVerdictText(a.verdict, english: _en)
              ),
            WeatherVerdict.noGo => (
                kFail,
                Icons.block,
                weatherVerdictText(a.verdict, english: _en)
              ),
          };
    final looser = a != null && a.looserThresholds.isNotEmpty;
    return Material(
      key: const ValueKey('wx-bar'),
      color: kCard,
      shape: Border(top: BorderSide(color: color, width: 2)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        key: a == null
                            ? null
                            : ValueKey('wx-bar-${a.verdict.name}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: a == null ? kTextSec : color,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.25),
                      ),
                      if (looser)
                        Text(
                          context.tr(
                              pl: 'Progi łagodniejsze niż normy!',
                              en: 'Thresholds looser than the codes!'),
                          key: const ValueKey('wx-bar-looser'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: kFail,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ),
              if (a != null)
                TextButton(
                  key: const ValueKey('wx-bar-details'),
                  style: TextButton.styleFrom(
                      foregroundColor: kText,
                      minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
                  onPressed: _scrollToResult,
                  child: Text(context.tr(pl: 'Szczegóły', en: 'Details')),
                )
              else
                const SizedBox(height: kMinTapTarget),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customThresholdsNotice() => QuoteNotice(
        key: const ValueKey('wx-thresholds-custom'),
        color: kWarn,
        icon: Icons.tune,
        text: context.tr(
            pl: 'Progi zmienione względem domyślnych (np. wg specyfikacji '
                'projektu). Domyślne przywrócisz w „Ustawieniach progów”.',
            en: 'Thresholds changed from the defaults (e.g. per the project '
                'specification). Restore them in “Thresholds”.'),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    required Key key,
    String? unit,
    String? helper,
    String? hint,
    bool signed = false,
    VoidCallback? onChanged,
  }) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(signed: signed),
        inputFormatters: numberInputFormatters(signed: signed),
        onChanged: (_) => (onChanged ?? _changed)(),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          hintText: hint,
          helperMaxLines: 4,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _caption(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child:
            Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      ChoiceChip(
        key: key,
        label: Text(label),
        selected: selected,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) {
          unawaited(Haptic.tap());
          onTap();
        },
      );

  // ── Sekcje wejścia ─────────────────────────────────────────────────────

  Widget _measureSection() {
    return QuoteSection(
      title: context.tr(pl: 'Pomiar', en: 'Measurement'),
      subtitle: context.tr(
          pl: 'Termometr, higrometr; temperatury mogą być ujemne.',
          en: 'Thermometer, hygrometer; temperatures may be negative.'),
      children: [
        FieldPair(
          left: _field(_ambient,
              context.tr(pl: 'Temperatura powietrza', en: 'Air temperature'),
              key: const ValueKey('wx-ambient'), unit: '°C', signed: true),
          right: _field(_rh,
              context.tr(pl: 'Wilgotność względna', en: 'Relative humidity'),
              key: const ValueKey('wx-rh'), unit: '%'),
        ),
        const SizedBox(height: 10),
        _field(
          _surface,
          context.tr(
              pl: 'Temperatura powierzchni materiału (opcjonalnie)',
              en: 'Base metal surface temperature (optional)'),
          key: const ValueKey('wx-surface'),
          unit: '°C',
          signed: true,
          helper: context.tr(
              pl: 'Termometr kontaktowy przy złączu. Puste = przyjmę '
                  'temperaturę powietrza.',
              en: 'Contact thermometer at the joint. Empty = air temperature '
                  'is assumed.'),
        ),
        _label(context.tr(
            pl: 'Stan powierzchni złącza (oglądnij i dotknij)',
            en: 'Joint surface (look and touch)')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in SurfaceState.values)
              _chip(
                key: ValueKey('wx-surface-state-${s.name}'),
                label: s.label(_en),
                selected: _surfaceState == s,
                onTap: () => setState(() {
                  _surfaceState = s;
                  _checked.clear();
                }),
              ),
          ],
        ),
        _caption(context.tr(
            pl: 'Po deszczu, przy rosie albo z lodem na rurze złącze bywa '
                'mokre mimo braku opadu — AWS D1.1 zabrania spawania na '
                'mokrych powierzchniach.',
            en: 'After rain, with dew or ice on the pipe the joint can be wet '
                'with no precipitation — AWS D1.1 forbids welding on wet '
                'surfaces.')),
      ],
    );
  }

  Widget _windSection() {
    final ms = _windMs;
    return QuoteSection(
      title:
          context.tr(pl: 'Wiatr przy stanowisku', en: 'Wind at the workplace'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final u in WindUnit.values)
              _chip(
                key: ValueKey('wx-unit-${u.name}'),
                label: windUnitLabel(u),
                selected: _windUnit == u,
                onTap: () => _setUnit(u),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _field(
          _wind,
          context.tr(pl: 'Prędkość wiatru', en: 'Wind speed'),
          key: const ValueKey('wx-wind'),
          unit: windUnitLabel(_windUnit),
          onChanged: _windTyped,
        ),
        if (ms != null)
          _caption(
            '${_windUnit == WindUnit.ms ? '= ${weatherNumAuto(ceilTo(msToKmh(ms), 1), maxDecimals: 1, english: _en)} km/h' : '= ${weatherNumAuto(ceilTo(ms, 2), english: _en)} m/s'}'
            ' · ${beaufortText(ms, english: _en)}'
            '${_beaufort == null ? '' : context.tr(pl: ' (górna granica stopnia — strona bezpieczna)', en: ' (upper bound of the force — safe side)')}',
            key: const ValueKey('wx-wind-caption'),
          ),
        const SizedBox(height: 6),
        ExpansionTile(
          key: const ValueKey('wx-beaufort'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            context.tr(
                pl: 'Bez wiatromierza? Wybierz z objawów (Beaufort)',
                en: 'No anemometer? Pick from what you see (Beaufort)'),
            style: const TextStyle(fontSize: 14, color: kText),
          ),
          children: [
            for (final b in kBeaufortScale)
              ListTile(
                key: ValueKey('wx-bft-${b.force}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                selected: _beaufort?.force == b.force,
                selectedColor: kArc,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: kBorder,
                  child: Text('${b.force}',
                      style: const TextStyle(
                          color: kText, fontWeight: FontWeight.w700)),
                ),
                title: Text(_en ? b.signsEn : b.signsPl),
                subtitle: Text(
                    '${_en ? b.nameEn : b.namePl} · ${_v(b.minMs)}–${_v(b.maxMs)} m/s'),
                onTap: () => _pickBeaufort(b),
              ),
          ],
        ),
      ],
    );
  }

  Widget _precipSection() {
    return QuoteSection(
      title: context.tr(pl: 'Opad', en: 'Precipitation'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in Precipitation.values)
              _chip(
                key: ValueKey('wx-precip-${p.name}'),
                label: p.label(_en),
                selected: _precip == p,
                onTap: () => setState(() {
                  _precip = p;
                  _checked.clear();
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _processSection() {
    return QuoteSection(
      title: context.tr(pl: 'Metoda i osłona', en: 'Process and shelter'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in WeatherProcess.values)
              _chip(
                key: ValueKey('wx-process-${p.name}'),
                label: p.label(_en),
                selected: _process == p,
                onTap: () => setState(() {
                  _process = p;
                  _checked.clear();
                }),
              ),
          ],
        ),
        _caption(_process.windSensitive
            ? context.tr(
                pl: 'Gaz osłonowy / płomień — wrażliwe na wiatr.',
                en: 'Shielding gas / flame — sensitive to wind.')
            : context.tr(
                pl: 'Bez gazu osłonowego — mniej wrażliwa na wiatr.',
                en: 'No shielding gas — less sensitive to wind.')),
        _label(context.tr(pl: 'Osłona stanowiska', en: 'Shelter')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in WeatherShelter.values)
              _chip(
                key: ValueKey('wx-shelter-${s.name}'),
                label: s.label(_en),
                selected: _shelter == s,
                onTap: () => setState(() {
                  _shelter = s;
                  _checked.clear();
                }),
              ),
          ],
        ),
        _caption(context.tr(
            pl: 'Parawan chroni przed wiatrem, namiot także przed opadem '
                'i da się go ogrzać.',
            en: 'A windbreak stops wind; an enclosure also keeps off rain and '
                'snow and can be heated.')),
      ],
    );
  }

  Widget _materialSection() {
    return QuoteSection(
      title: context.tr(pl: 'Materiał', en: 'Material'),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in WeatherMaterial.values)
              _chip(
                key: ValueKey('wx-material-${m.name}'),
                label: m.label(_en),
                selected: _material == m,
                onTap: () => setState(() {
                  _material = m;
                  _checked.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          _wps,
          context.tr(
              pl: 'Minimalne podgrzewanie z WPS (opcjonalnie)',
              en: 'Minimum preheat from the WPS (optional)'),
          key: const ValueKey('wx-wps'),
          unit: '°C',
          signed: true,
          helper: context.tr(
              pl: 'Puste = WPS nie wymaga albo nie wiesz — liczą się wtedy '
                  'tylko minima z norm.',
              en: 'Empty = the WPS has none or you do not know — only the '
                  'code minimums count.'),
        ),
      ],
    );
  }

  // ── Wynik ──────────────────────────────────────────────────────────────

  Widget _verdictBanner(WeatherAssessment a) {
    final v = a.verdict;
    final (Color color, IconData icon) = switch (v) {
      WeatherVerdict.go => (kPass, Icons.check_circle_outline),
      WeatherVerdict.conditional => (kWarn, Icons.rule),
      WeatherVerdict.noGo => (kFail, Icons.block),
    };
    final all = a.conditions.isNotEmpty &&
        a.conditions.every((f) => _checked.contains(f.code));
    final sub = switch (v) {
      WeatherVerdict.go => context.tr(
          pl: 'Warunki atmosferyczne nie blokują spawania.',
          en: 'The weather does not prevent welding.'),
      WeatherVerdict.conditional => all
          ? context.tr(
              pl: 'Wszystkie warunki odhaczone — pilnuj ich w trakcie.',
              en: 'All conditions ticked — keep them in place while welding.')
          : context.tr(
              pl: 'Odhacz warunki z listy poniżej.',
              en: 'Tick the conditions in the list below.'),
      WeatherVerdict.noGo => context.tr(
          pl: 'Powody i co zmienić — poniżej.',
          en: 'Reasons and what to change — below.'),
    };
    return KeyedSubtree(
      key: ValueKey('wx-verdict-${v.name}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(weatherVerdictText(v, english: _en),
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1.2)),
                  const SizedBox(height: 4),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 13, color: kText, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Key? key}) => CopyOnLongPress(
        key: key,
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
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kText,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );

  Widget _resultSection(WeatherAssessment a) {
    final frost = a.frostPointC;
    return QuoteSection(
      title: context.tr(pl: 'Wynik', en: 'Result'),
      children: [
        _verdictBanner(a),
        if (weatherLooserWarning(a.thresholds, english: _en) case final w?)
          QuoteNotice(
            key: const ValueKey('wx-looser-warning'),
            color: kFail,
            icon: Icons.gpp_maybe_outlined,
            text: w,
          ),
        if (a.surfaceAssumed)
          QuoteNotice(
            key: const ValueKey('wx-surface-assumed'),
            color: kWarn,
            icon: Icons.thermostat,
            text: context.tr(
                pl: 'Założenie: temperatura powierzchni = temperatura '
                    'powietrza (${_v(a.surfaceC)} °C) — brak pomiaru '
                    'termometrem kontaktowym.',
                en: 'Assumption: surface temperature = air temperature '
                    '(${_v(a.surfaceC)} °C) — no contact thermometer '
                    'reading.'),
          ),
        Readout(
          key: const ValueKey('wx-dew'),
          label: context.tr(pl: 'Punkt rosy', en: 'Dew point'),
          value: _n(a.dewPointC),
          unit: context.tr(
              pl: '°C · zapas ${weatherMarginText(a, english: false)} K',
              en: '°C · margin ${weatherMarginText(a, english: true)} K'),
          hot: true,
        ),
        const SizedBox(height: 10),
        if (frost != null)
          _kv(context.tr(pl: 'Punkt szronu', en: 'Frost point'),
              '${_n(frost)} °C',
              key: const ValueKey('wx-frost')),
        _kv(
            a.surfaceAssumed
                ? context.tr(
                    pl: 'Powierzchnia (założona)', en: 'Surface (assumed)')
                : context.tr(
                    pl: 'Powierzchnia (pomiar)', en: 'Surface (measured)'),
            '${_v(a.surfaceC)} °C'),
        _kv(
            context.tr(
                pl: 'Zapas nad punktem ${frost != null ? 'szronu' : 'rosy'}',
                en: 'Margin above ${frost != null ? 'frost' : 'dew'} point'),
            '${weatherMarginText(a, english: _en)} K',
            key: const ValueKey('wx-margin')),
        _kv(
            context.tr(
                pl: 'Min. temperatura materiału',
                en: 'Min. base metal temperature'),
            '${weatherNumMin(a.requiredMaterialC, english: _en)} °C',
            key: const ValueKey('wx-required')),
        _kv(
            context.tr(
                pl: 'Złącze utrzymuj co najmniej',
                en: 'Keep the joint at least at'),
            '${weatherNumMin(a.targetSurfaceC, english: _en)} °C',
            key: const ValueKey('wx-target')),
        _caption(context.tr(
            pl: 'Punkt rosy: wzór Magnusa, stałe Alduchov–Eskridge (1996) za '
                'Lawrence (2005); poniżej 0 °C także punkt szronu (Buck 1996) '
                '— liczy się wyższy. Zapas ≥ '
                '${_v(_thresholds.dewMarginK)} K — dobra praktyka '
                'z ISO 8502-4 (malowanie), nie wymóg norm spawalniczych.',
            en: 'Dew point: Magnus formula, Alduchov–Eskridge (1996) '
                'constants after Lawrence (2005); below 0 °C also the frost '
                'point (Buck 1996) — the higher one counts. Margin ≥ '
                '${_v(_thresholds.dewMarginK)} K — good practice from '
                'ISO 8502-4 (coating), not a welding-code requirement.')),
      ],
    );
  }

  Widget _findingRow(WeatherFinding f, IconData icon, Color color,
          {Key? key}) =>
      Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.text(_en),
                      style: const TextStyle(
                          fontSize: 14, color: kText, height: 1.35)),
                  if (f.basis.isNotEmpty)
                    _caption(
                        '${context.tr(pl: 'Podstawa', en: 'Basis')}: ${f.basisText(_en)}'),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _stopsSection(WeatherAssessment a) => QuoteSection(
        title: context.tr(pl: 'Nie spawać, bo', en: 'Do not weld because'),
        children: [
          for (final f in a.stops)
            _findingRow(f, Icons.block, kFail,
                key: ValueKey('wx-stop-${f.code}')),
        ],
      );

  Widget _conditionsSection(WeatherAssessment a) {
    final conds = a.conditions;
    final done = conds.where((f) => _checked.contains(f.code)).length;
    return QuoteSection(
      title: context.tr(pl: 'Warunki do spełnienia', en: 'Conditions to meet'),
      subtitle: context.tr(
          pl: 'Odhaczone: $done z ${conds.length}',
          en: 'Ticked: $done of ${conds.length}'),
      children: [
        for (final f in conds)
          CheckboxListTile(
            key: ValueKey('wx-cond-${f.code}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: kArc,
            checkColor: kOnArc,
            value: _checked.contains(f.code),
            onChanged: (v) {
              unawaited(Haptic.tap());
              setState(() {
                if (v == true) {
                  _checked.add(f.code);
                } else {
                  _checked.remove(f.code);
                }
              });
            },
            title: Text(f.text(_en),
                style:
                    const TextStyle(fontSize: 14, color: kText, height: 1.35)),
            subtitle: Text(
                '${context.tr(pl: 'Podstawa', en: 'Basis')}: ${f.basisText(_en)}',
                style: const TextStyle(
                    fontSize: 12, color: kTextMut, height: 1.35)),
          ),
      ],
    );
  }

  Widget _passedSection(WeatherAssessment a) => QuoteSection(
        title: context.tr(pl: 'Sprawdzone — OK', en: 'Checked — OK'),
        children: [
          if (a.passed.isEmpty)
            Text(
                context.tr(
                    pl: 'Żaden punkt nie przeszedł bez uwag.',
                    en: 'No item passed without remarks.'),
                style: const TextStyle(fontSize: 13, color: kTextMut))
          else
            for (final f in a.passed)
              _findingRow(f, Icons.check_circle_outline, kPass,
                  key: ValueKey('wx-ok-${f.code}')),
        ],
      );

  Widget _recommendationsSection(WeatherAssessment a) => QuoteSection(
        title: context.tr(pl: 'Zalecenia', en: 'Recommendations'),
        children: [
          for (final f in a.recommendations)
            _findingRow(f, Icons.lightbulb_outline, kTextSec,
                key: ValueKey('wx-rec-${f.code}')),
        ],
      );

  Widget _saveSection(WeatherAssessment a) => QuoteSection(
        title: context.tr(pl: 'Zapis i udostępnianie', en: 'Save and share'),
        children: [
          TextField(
            key: const ValueKey('wx-place'),
            controller: _place,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Miejsce / opis (opcjonalnie)',
                  en: 'Location / description (optional)'),
              hintText: context.tr(
                  pl: 'np. Estakada E-3, spoina 12',
                  en: 'e.g. Pipe rack E-3, weld 12'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                key: const ValueKey('wx-save'),
                onPressed: () => _save(a),
                icon: const Icon(Icons.save_alt),
                label: Text(
                    context.tr(pl: 'Zapisz w historii', en: 'Save to history')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('wx-share-text'),
                onPressed: () => _shareText(a),
                icon: const Icon(Icons.ios_share),
                label: Text(context.tr(pl: 'Tekst', en: 'Text')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('wx-share-pdf'),
                onPressed: _busyPdf ? null : () => _sharePdf(a),
                icon: _busyPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kArc))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ],
          ),
        ],
      );
}
