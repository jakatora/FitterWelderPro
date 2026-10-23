import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/passivation_dao.dart';
import '../domain/passivation/passivation_record.dart';
import '../domain/weld_journal/weld_dates.dart';
import '../i18n/app_language.dart';
import '../services/passivation_export.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart' show kTextMut, kArc, kOnArc, kPass, kFail;
import '../widgets/number_field.dart';
import '../widgets/local_record_scope.dart';

const _kCard = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kBlue = Color(0xFF4A9EFF);
const _kRed = Color(0xFFE74C3C);
const _kSec = Color(0xFF9BA3C7);
const _kMuted = kTextMut; // token motywu (kontrast ≥ 4,5:1)

class _Step {
  final String pl;
  final String en;
  const _Step(this.pl, this.en);
}

// Post-weld surface treatment guide for stainless steel in food & pharma.
// This is a PROCESS guide — the steps, the order, the hazards — not a recipe:
// concentrations and dwell times always come from the product data sheet of
// the paste/bath actually used, and from the project specification.

const List<_Step> _pickling = [
  _Step(
      'Odtłuść spoinę i strefę wpływu ciepła — brak smaru, oleju, odcisków palców.',
      'Degrease the weld and heat-affected zone — no grease, oil or fingerprints.'),
  _Step(
      'Usuń luźne tlenki / żużel mechanicznie szczotką ze stali nierdzewnej (dedykowaną).',
      'Remove loose oxide / slag mechanically with a dedicated stainless brush.'),
  _Step(
      'Nałóż pastę trawiącą równomiernie na spoinę i przebarwienia (heat tint).',
      'Apply pickling paste evenly over the weld and the heat-tint band.'),
  _Step(
      'Odczekaj czas oddziaływania WG KARTY PRODUKTU — zależny od temperatury otoczenia.',
      'Leave for the dwell time PER THE DATA SHEET — depends on ambient temperature.'),
  _Step(
      'Spłucz obficie wodą demineralizowaną — usuń całą pastę, też od wewnątrz rury.',
      'Rinse thoroughly with demineralised water — remove all paste, inside the tube too.'),
  _Step(
      'Sprawdź: powierzchnia jednolicie matowa, bez przebarwień i śladów pasty.',
      'Check: surface uniformly matt, no tint and no paste residue left.'),
];

const List<_Step> _passivation = [
  _Step(
      'Powierzchnia czysta i sucha — po trawieniu i płukaniu, po obróbce '
          'mechanicznej albo (instalacje BPE) w obiegu chemicznym wg procedury.',
      'Surface clean and dry — after pickling and rinsing, after mechanical '
          'finishing or (BPE systems) by circulation per the procedure.'),
  _Step(
      'Nałóż środek pasywujący (kwas azotowy lub — bezpieczniejszy — kwas cytrynowy).',
      'Apply the passivation agent (nitric acid or — safer — citric acid).'),
  _Step('Odczekaj czas WG SPECYFIKACJI / karty produktu.',
      'Leave for the time PER THE SPECIFICATION / data sheet.'),
  _Step('Spłucz wodą demineralizowaną i wysusz czystym, niepylącym materiałem.',
      'Rinse with demineralised water and dry with a clean, lint-free cloth.'),
  _Step(
      'Wykonaj test pasywacji (np. ferroxyl / test wilgotnościowy) jeśli wymaga '
          'specyfikacja. Na powierzchniach produktowych pharma ferroxyl bywa '
          'zakazany (pozostałości) — sprawdź specyfikację. Zapisz zabieg w '
          'zakładce „Rejestr”.',
      'Run a passivation test (e.g. ferroxyl / humidity test) if the spec '
          'requires it. On pharma product-contact surfaces ferroxyl may be '
          'prohibited (residues) — check the spec. Record the treatment in the '
          '"Register" tab.'),
];

class PassivationScreen extends StatelessWidget {
  const PassivationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(
              pl: 'Trawienie i pasywacja', en: 'Pickling & passivation')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.tr(pl: 'Trawienie', en: 'Pickling')),
              Tab(text: context.tr(pl: 'Pasywacja', en: 'Passivation')),
              Tab(text: context.tr(pl: 'Rejestr', en: 'Register')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _StepList(
              intro: context.tr(
                pl: 'Trawienie (pickling) usuwa przebarwienia i warstwę zubożoną '
                    'w chrom po spawaniu — przywraca odporność korozyjną spoiny.',
                en: 'Pickling removes heat tint and the chromium-depleted layer '
                    'left by welding — it restores the weld\'s corrosion resistance.',
              ),
              steps: _pickling,
              showHfWarning: true,
            ),
            _StepList(
              intro: context.tr(
                pl: 'Pasywacja odtwarza pasywną warstwę tlenku chromu na '
                    'powierzchni — wymóg dla instalacji spożywczych i farmaceutycznych.',
                en: 'Passivation rebuilds the passive chromium-oxide layer on the '
                    'surface — a requirement for food and pharma installations.',
              ),
              steps: _passivation,
              showHfWarning: false,
            ),
            // v34: rejestr należy do konta — po zmianie konta od nowa.
            LocalRecordScope(builder: (_, __) => const PassivationRegister()),
          ],
        ),
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  final String intro;
  final List<_Step> steps;
  final bool showHfWarning;
  const _StepList({
    required this.intro,
    required this.steps,
    required this.showHfWarning,
  });

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text(intro,
            style: const TextStyle(color: _kSec, fontSize: 13, height: 1.5)),
        const SizedBox(height: 16),
        ...steps.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: _kBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(isPl ? s.pl : s.en,
                      style: const TextStyle(
                          color: Color(0xFFE7ECF3),
                          fontSize: 13,
                          height: 1.45)),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),

        // Mandatory safety note.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kRed.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.dangerous_outlined, color: _kRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  showHfWarning
                      ? context.tr(
                          pl: 'BHP: pasty trawiące zawierają kwas fluorowodorowy (HF) — '
                              'skrajnie niebezpieczny, wchłania się przez skórę. Wymagane: '
                              'odzież kwasoodporna, gogle, wentylacja, glukonian wapnia w '
                              'zasięgu. Zawsze stosuj kartę charakterystyki (SDS).',
                          en: 'SAFETY: pickling pastes contain hydrofluoric acid (HF) — '
                              'extremely hazardous, absorbed through skin. Required: '
                              'acid-resistant PPE, goggles, ventilation, calcium gluconate '
                              'on hand. Always follow the safety data sheet (SDS).',
                        )
                      : context.tr(
                          pl: 'BHP: środki pasywujące to kwasy — stosuj odzież ochronną, '
                              'gogle i wentylację. Zawsze według karty charakterystyki (SDS). '
                              'Stężenia i czasy — wg karty produktu, nie z pamięci.',
                          en: 'SAFETY: passivation agents are acids — use protective PPE, '
                              'goggles and ventilation. Always per the safety data sheet '
                              '(SDS). Concentrations and times — from the data sheet, not memory.',
                        ),
                  style:
                      const TextStyle(color: _kSec, fontSize: 12, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.menu_book_outlined, color: _kOrange, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr(
                  pl: 'Przewodnik procesowy — kolejność i kontrola. '
                      'Wiążące parametry: karta produktu + specyfikacja projektu.',
                  en: 'Process guide — sequence and checks. '
                      'Binding parameters: product data sheet + project specification.',
                ),
                style: const TextStyle(
                    color: _kMuted, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rejestr wykonanych zabiegów (v25) — lista, dodawanie, edycja, miękkie
/// usuwanie z „Cofnij” i eksport CSV / PDF do data booka.
class PassivationRegister extends StatefulWidget {
  final PassivationDao? dao;
  const PassivationRegister({super.key, this.dao});

  @override
  State<PassivationRegister> createState() => _PassivationRegisterState();
}

class _PassivationRegisterState extends State<PassivationRegister> {
  late final PassivationDao _dao = widget.dao ?? PassivationDao();
  List<PassivationRecord> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _dao.listAll();
      if (!mounted) return;
      setState(() {
        _items = all;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[passivation] load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([PassivationRecord? r]) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = r ??
        PassivationRecord(
          id: const Uuid().v4(),
          date: isoDate(DateTime.now()),
          byStamp: WelderIdentityService.instance.current?.stamp ?? '',
          createdAt: now,
          updatedAt: now,
        );
    final saved = await showModalBottomSheet<PassivationRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _kCard,
      builder: (_) => _PassivationForm(initial: record),
    );
    if (saved == null) return;
    try {
      await _dao.save(saved);
    } catch (e) {
      debugPrint('[passivation] save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie udało się zapisać zabiegu.',
            en: 'Could not save the treatment.')),
      ));
      return;
    }
    await _load();
  }

  Future<void> _delete(PassivationRecord r) async {
    await _dao.softDelete(r.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(pl: 'Usunięto wpis.', en: 'Entry deleted.')),
      action: SnackBarAction(
        label: context.tr(pl: 'Cofnij', en: 'Undo'),
        onPressed: () async {
          await _dao.restore(r.id);
          await _load();
        },
      ),
    ));
  }

  Future<void> _export(Future<void> Function() job) async {
    if (_items.isEmpty) return;
    try {
      await job();
    } catch (e) {
      debugPrint('[passivation] export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = AppLanguageController.isEnglish;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kArc));
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text(
          context.tr(
              pl: 'Zapis zabiegów do data booka: linia / pakiet testowy, '
                  'środek i partia, czas, temperatura, płukanie, test.',
              en: 'Treatment records for the data book: line / test package, '
                  'agent and batch, time, temperature, rinse, test.'),
          style: const TextStyle(color: _kSec, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('passivation-add'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: kArc,
                  foregroundColor: kOnArc),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(context.tr(pl: 'Dodaj zabieg', en: 'Add treatment')),
            ),
          ),
          IconButton(
            tooltip: context.tr(pl: 'Eksport CSV', en: 'Export CSV'),
            onPressed: _items.isEmpty
                ? null
                : () => _export(() => PassivationExport.shareCsv(_items)),
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(
            tooltip: context.tr(pl: 'Eksport PDF', en: 'Export PDF'),
            onPressed: _items.isEmpty
                ? null
                : () => _export(() => PassivationExport.sharePdf(_items)),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ]),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          Text(context.tr(pl: 'Brak wpisów.', en: 'No records yet.'),
              style: const TextStyle(color: _kMuted)),
        for (final r in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // Material, nie kolorowy Container: ListTile rysuje tło
            // i „atrament" na najbliższym Material.
            child: Material(
              color: _kCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: _kBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: () => _edit(r),
                title: Text(
                  [
                    r.date,
                    PassivationTreatment.label(r.treatment, en: en),
                    if (r.line.isNotEmpty) r.line,
                    if (r.testPackage.isNotEmpty) r.testPackage,
                  ].join(' · '),
                  style: const TextStyle(
                      color: Color(0xFFE7ECF3),
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (r.agent.isNotEmpty)
                      '${r.agent}${r.agentBatch.isEmpty ? '' : ' (${r.agentBatch})'}',
                    if (r.testMethod.isNotEmpty)
                      '${r.testMethod} ${r.testResult}'.trim(),
                    if (r.byStamp.isNotEmpty) r.byStamp,
                  ].join(' · '),
                  style: const TextStyle(color: _kSec, fontSize: 12),
                ),
                trailing: IconButton(
                  tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
                  icon: const Icon(Icons.delete_outline, color: _kMuted),
                  onPressed: () => _delete(r),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PassivationForm extends StatefulWidget {
  final PassivationRecord initial;
  const _PassivationForm({required this.initial});

  @override
  State<_PassivationForm> createState() => _PassivationFormState();
}

class _PassivationFormState extends State<_PassivationForm> {
  late final PassivationRecord _r = widget.initial;
  late String _treatment = _r.treatment;
  late String _result = _r.testResult;
  late final _date = TextEditingController(text: _r.date);
  late final _line = TextEditingController(text: _r.line);
  late final _pkg = TextEditingController(text: _r.testPackage);
  late final _area = TextEditingController(text: _r.area);
  late final _agent = TextEditingController(text: _r.agent);
  late final _batch = TextEditingController(text: _r.agentBatch);
  late final _dwell =
      TextEditingController(text: formatPassivationNumber(_r.dwellMin));
  late final _temp =
      TextEditingController(text: formatPassivationNumber(_r.tempC));
  late final _rinse =
      TextEditingController(text: formatPassivationNumber(_r.rinseUsCm));
  late final _test = TextEditingController(text: _r.testMethod);
  late final _by = TextEditingController(text: _r.byStamp);
  late final _notes = TextEditingController(text: _r.notes);
  String? _dateError;

  List<TextEditingController> get _all => [
        _date,
        _line,
        _pkg,
        _area,
        _agent,
        _batch,
        _dwell,
        _temp,
        _rinse,
        _test,
        _by,
        _notes,
      ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final date = normalizeWeldDate(_date.text);
    if (date == null || date.isEmpty) {
      setState(() => _dateError = context.tr(
          pl: 'Data RRRR-MM-DD lub DD.MM.RRRR',
          en: 'Date YYYY-MM-DD or DD.MM.YYYY'));
      return;
    }
    Navigator.pop(
      context,
      PassivationRecord(
        id: _r.id,
        date: date,
        treatment: _treatment,
        line: _line.text.trim(),
        testPackage: _pkg.text.trim(),
        area: _area.text.trim(),
        agent: _agent.text.trim(),
        agentBatch: _batch.text.trim(),
        dwellMin: parsePassivationNumber(_dwell.text),
        tempC: parsePassivationNumber(_temp.text),
        rinseUsCm: parsePassivationNumber(_rinse.text),
        testMethod: _test.text.trim(),
        testResult: _result,
        byStamp: _by.text.trim(),
        notes: _notes.text.trim(),
        createdAt: _r.createdAt,
        updatedAt: _r.updatedAt,
      ),
    );
  }

  Widget _field(TextEditingController c, String pl, String en,
          {bool numeric = false, String? error}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: numeric ? numberKeyboard() : TextInputType.text,
          inputFormatters: numeric ? numberInputFormatters() : null,
          decoration: InputDecoration(
              labelText: context.tr(pl: pl, en: en), errorText: error),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final en = AppLanguageController.isEnglish;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    context.tr(pl: 'Zabieg', en: 'Treatment'),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE7ECF3)),
                  ),
                ),
                IconButton(
                  tooltip: context.tr(pl: 'Zamknij', en: 'Close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final t in PassivationTreatment.values)
                      ChoiceChip(
                        label: Text(PassivationTreatment.label(t, en: en)),
                        selected: _treatment == t,
                        onSelected: (_) => setState(() => _treatment = t),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ]),
                  const SizedBox(height: 10),
                  _field(_date, 'Data', 'Date', error: _dateError),
                  _field(_line, 'Linia', 'Line'),
                  _field(_pkg, 'Pakiet testowy', 'Test package'),
                  _field(_area, 'Obszar / zakres', 'Area / scope'),
                  _field(_agent, 'Środek (produkt)', 'Agent (product)'),
                  _field(_batch, 'Partia środka', 'Agent batch'),
                  _field(_dwell, 'Czas (min)', 'Time (min)', numeric: true),
                  _field(_temp, 'Temperatura (°C)', 'Temperature (°C)',
                      numeric: true),
                  _field(_rinse, 'Płukanie — konduktywność (µS/cm)',
                      'Rinse — conductivity (µS/cm)',
                      numeric: true),
                  _field(_test, 'Test (np. ferroxyl)', 'Test (e.g. ferroxyl)'),
                  Wrap(spacing: 8, children: [
                    for (final r in [
                      (PassivationResult.none, '—', _kSec),
                      (PassivationResult.ok, 'OK', kPass),
                      (PassivationResult.nok, 'NOK', kFail),
                    ])
                      ChoiceChip(
                        label: Text(r.$2),
                        selected: _result == r.$1,
                        selectedColor: r.$3.withValues(alpha: 0.25),
                        onSelected: (_) => setState(() => _result = r.$1),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ]),
                  const SizedBox(height: 10),
                  _field(_by, 'Wykonał (stempel)', 'Performed by (stamp)'),
                  _field(_notes, 'Uwagi', 'Notes'),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, 8 + MediaQuery.viewPaddingOf(context).bottom),
              child: FilledButton.icon(
                key: const ValueKey('passivation-save'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: kArc,
                    foregroundColor: kOnArc),
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(context.tr(pl: 'Zapisz', en: 'Save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
