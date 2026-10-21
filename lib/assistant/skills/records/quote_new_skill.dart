import 'package:uuid/uuid.dart';
import '../../../database/weld_quote_dao.dart';
import '../../../domain/quotes/weld_quote.dart';
import '../../../domain/quotes/quote_process.dart';
import '../../../services/quote_settings.dart';
import '../../assistant_history.dart';
import '../../core/skill.dart';

final _intent = RegExp(
    r'^(?:(?:prosze|please)\s+)*(?:(?:utworz|stworz|przygotuj|dodaj|zrob)\s+(?:nowa\s+)?wycene|(?:create|prepare|add|make)\s+(?:a\s+)?(?:new\s+)?(?:welding\s+)?quote)\b');
final _labels = RegExp(r'\b(tytuł|tytul|title|klient|client|notatka|note)\s*:',
    caseSensitive: false);

class QuoteNewSkill extends AssistantSkill {
  QuoteNewSkill(
      {WeldQuoteDao? dao,
      this.store = const QuoteSettingsStore(),
      String Function()? newId})
      : dao = dao ?? WeldQuoteDao(),
        _newId = newId ?? const Uuid().v4;
  final WeldQuoteDao dao;
  final QuoteSettingsStore store;
  final String Function() _newId;
  @override
  String get id => 'quote.new';
  @override
  String get toolId => 'weld_quotes';
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => const [
        SkillExample('Utwórz nową wycenę', 'Create a new quote'),
        SkillExample('Przygotuj wycenę stal nierdzewna',
            'Prepare quote stainless steel'),
        SkillExample(
            'Stwórz wycenę TIG + MMA', 'Create welding quote TIG + MMA'),
        SkillExample('Dodaj wycenę w warsztacie', 'Add quote in shop'),
        SkillExample('Zrób wycenę duplex TIG', 'Make quote duplex TIG'),
        SkillExample('Utwórz wycenę aluminium na obiekcie',
            'Create quote aluminium in field'),
      ];
  @override
  List<SkillRejection> get rejections => const [
        SkillRejection('otwórz wyceny', routesTo: 'tool.open'),
        SkillRejection('zmień stawkę spawacza na 100 zł'),
        SkillRejection('wyślij wycenę klientowi'),
      ];
  @override
  SkillMatch? match(
          Utterance u, AssistantContext ctx) =>
      _intent.hasMatch(u.folded)
          ? SkillMatch(this, .99,
              slots: {...slotsFrom(u, ctx), 'origin_voice': u.byVoice},
              utterance: u)
          : null;
  @override
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) {
    final result = <String, Object?>{};
    final labels = _labels.allMatches(u.raw).toList();
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i][1]!.toLowerCase();
      final key = const ['tytuł', 'tytul', 'title'].contains(label)
          ? 'title'
          : const ['klient', 'client'].contains(label)
              ? 'client'
              : 'note';
      final value = u.raw
          .substring(labels[i].end,
              i + 1 < labels.length ? labels[i + 1].start : u.raw.length)
          .trim()
          .replaceAll(RegExp(r'[;,]+$'), '')
          .trim();
      if (result.containsKey(key) && result[key] != value) {
        result['ambiguous'] = true;
      }
      result[key] = value;
    }
    if (labels.isNotEmpty) {
      u = u.withRaw(u.raw.substring(0, labels.first.start));
    }
    if (RegExp(r'\b(?:stawka|stawke|stawki|rate|price|cena|cene|vat|marza|narzut|rabat|discount)\b.{0,25}\d')
            .hasMatch(u.folded) ||
        RegExp(r'\d+(?:[.,]\d+)?\s*(?:pln|zl|zlotych|zlote|zloty|eur|usd)\b')
            .hasMatch(u.folded)) {
      result['unsupported_price'] = true;
    }
    final materials = <String>{};
    if (u.hasStem(const ['nierdzewn', 'stainless']) || u.hasAny(const ['ss'])) {
      materials.add('SS');
    }
    if (u.hasStem(const ['weglow', 'niestopow']) ||
        u.hasAny(const ['carbon steel', 'cs'])) {
      materials.add('CS');
    }
    if (u.hasStem(const ['duplex'])) materials.add('DUPLEX');
    if (u.hasStem(const ['alumin'])) materials.add('AL');
    if (u.hasAny(const ['cr mo', 'crmo', 'p11', 'p22', 'p91'])) {
      materials.add('CRMO');
    }
    if (materials.isNotEmpty) {
      result['material'] = materials.length == 1 ? materials.single : '';
    }
    final processes = RegExp(
            r'\b(TIG|MMA|MAG|FCAW|MIG|SAW|141|111|135|136|131|121)\b',
            caseSensitive: false)
        .allMatches(u.raw)
        .map((m) => QuoteProcess.values.firstWhere(
            (p) => p.code == m[1]!.toUpperCase() || p.isoNo == m[1]!))
        .toList();
    for (var i = processes.length - 1; i > 0; i--) {
      if (processes[i] == processes[i - 1]) processes.removeAt(i);
    }
    final processCodes = {
      for (final p in QuoteProcess.values) ...[p.code, p.isoNo]
    };
    final unknownPair = RegExp(r'\b([A-Za-z0-9]+)\s*\+\s*([A-Za-z0-9]+)\b')
        .allMatches(u.raw)
        .any((m) =>
            !processCodes.contains(m[1]!.toUpperCase()) ||
            !processCodes.contains(m[2]!.toUpperCase()));
    if (unknownPair ||
        (processes.isNotEmpty && u.hasAny(const ['lub', 'albo', 'or']))) {
      result['scheme'] = '';
    } else if (processes.isNotEmpty) {
      result['scheme'] = processes.length == 1
          ? processes.single.code
          : processes.length == 2
              ? '${processes.first.code}+${processes.last.code}'
              : '';
    }
    final sites = <String>{};
    if (u.hasStem(const ['warszt', 'prefabryk', 'shop', 'prefabricat'])) {
      sites.add('SHOP');
    }
    if (u.hasAny(
        const ['na obiekcie', 'montaz na obiekcie', 'field', 'on site'])) {
      sites.add('FIELD');
    }
    if (u.hasAny(const [
      'trudny dostep',
      'difficult access',
      'na wysokosci',
      'at height',
      'ciasno',
      'tight space'
    ])) {
      sites.add('HARD');
    }
    if (sites.isNotEmpty) {
      result['site'] = sites.length == 1 ? sites.single : '';
    }
    return result;
  }

  @override
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final result = slotsFrom(u, ctx);
    return result.containsKey(slot) ? result : null;
  }

  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext ctx) async {
    final s = m.slots;
    if (s['unsupported_price'] == true) {
      return const FailedResult(
          AssistantText(
              'To polecenie określa stawkę, cenę lub podatek. Tworzenie szkicu kopiuje szablon i nie obsługuje jeszcze takich zmian przez asystenta; możesz je wprowadzić w edytorze wyceny.',
              'This request specifies a rate, price or tax. Draft creation copies the template and does not yet support those assistant changes; edit them in the quote editor.'),
          reportMissingCapability: true);
    }

    if (s['ambiguous'] == true ||
        const ['title', 'client', 'note'].any((k) =>
            s[k] != null &&
            (s[k] is! String || (s[k] as String).length > 1000))) {
      return const FailedResult(AssistantText(
          'Podaj jedną wartość każdego pola, maksymalnie 1000 znaków.',
          'Give one value per field, up to 1000 characters.'));
    }
    final material =
        QuoteMaterial.values.where((x) => x.code == s['material']).firstOrNull;
    if (material == null) {
      return AskResult(
          'material',
          const AssistantText(
              'Jaki materiał: stal węglowa, nierdzewna, duplex, Cr-Mo czy aluminium?',
              'Which material: carbon steel, stainless, duplex, Cr-Mo or aluminium?'),
          partial: m,
          choices: [
            for (final x in QuoteMaterial.values)
              FollowUp(AssistantText(x.labelPl, x.labelEn), x.labelEn)
          ]);
    }
    final scheme = WeldScheme.fromCode(s['scheme'] as String?);
    if (scheme == null) {
      return AskResult(
          'scheme',
          const AssistantText(
              'Jakim procesem? Podaj jeden proces albo kolejno grań i wypełnienie, np. TIG + MMA.',
              'Which process? Give one process or root then fill, e.g. TIG + MMA.'),
          partial: m,
          choices: [
            for (final x in kCommonSchemes)
              FollowUp(AssistantText.same(x.label), x.label)
          ]);
    }
    final site = QuoteSite.values.where((x) => x.code == s['site']).firstOrNull;
    if (site == null) {
      return AskResult(
          'site',
          const AssistantText(
              'Gdzie będą prowadzone prace: warsztat, obiekt czy trudny dostęp?',
              'Where is the work: shop, field or difficult access?'),
          partial: m,
          choices: const [
            FollowUp(AssistantText('Warsztat', 'Shop'), 'shop'),
            FollowUp(AssistantText('Na obiekcie', 'Field'), 'field'),
            FollowUp(AssistantText('Trudny dostęp', 'Difficult access'),
                'difficult access')
          ]);
    }
    ({QuoteSettings settings, bool saved}) template;
    try {
      template = await store.loadForAssistant();
    } catch (_) {
      return const FailedResult(AssistantText(
          'Nie udało się bezpiecznie odczytać szablonu stawek. Sprawdź „Moje stawki” przed utworzeniem wyceny.',
          'Could not safely read the rate template. Review “My rates” before creating a quote.'));
    }
    final at = ctx.now().millisecondsSinceEpoch;
    final draft = WeldQuote(
        id: _newId(),
        title: s['title'] as String? ?? '',
        client: s['client'] as String? ?? '',
        notes: s['note'] as String? ?? '',
        material: material,
        scheme: scheme,
        site: site,
        purge: material.purgeByDefault,
        rates: template.settings.ratesFor(material),
        validityDays: template.settings.validityDays,
        createdAt: at,
        updatedAt: at);
    final en = ctx.lang.name == 'en';
    final summary = AssistantAnswer(
        text: const AssistantText(
            'Utworzę szkic z kopią stawek. Numer zostanie nadany przy zapisie; zakres spoin i koszty uzupełnisz w wycenie.',
            'I will create a draft with a rate snapshot. Its number is assigned when saved; add joints and costs in the quote.'),
        lines: [
          AnswerLine(const AssistantText('Materiał', 'Material'),
              en ? material.labelEn : material.labelPl),
          AnswerLine(
              const AssistantText('Schemat', 'Process scheme'), scheme.label),
          AnswerLine(const AssistantText('Miejsce', 'Work site'),
              en ? site.labelEn : site.labelPl),
          if (draft.title.isNotEmpty)
            AnswerLine(const AssistantText('Tytuł', 'Title'), draft.title),
          if (draft.client.isNotEmpty)
            AnswerLine(const AssistantText('Klient', 'Client'), draft.client),
          if (draft.notes.isNotEmpty)
            AnswerLine(const AssistantText('Notatka', 'Note'), draft.notes),
          AnswerLine(
              const AssistantText('Źródło stawek', 'Rate source'),
              template.saved
                  ? (en
                      ? 'Saved template; missing prices use module defaults'
                      : 'Zapisany szablon; brakujące ceny z domyślnych modułu')
                  : (en ? 'Module defaults' : 'Domyślne modułu')),
          AnswerLine(
              const AssistantText(
                  'Spawacz / monter netto', 'Welder / fitter net'),
              '${draft.rates.welderRate} / ${draft.rates.fitterRate} PLN/h'),
          AnswerLine(const AssistantText('VAT', 'VAT'), draft.rates.vat.label),
          AnswerLine(
              const AssistantText('Formowanie grani', 'Root purging'),
              draft.purge
                  ? (en
                      ? 'On (material default)'
                      : 'Włączone (domyślne materiału)')
                  : (en ? 'Off' : 'Wyłączone')),
        ]);
    return ConfirmResult(summary, () async {
      final saved = await dao.insertNewDraft(draft);
      final historyId = 'quote.new:${saved.id}';
      await AssistantHistoryStore.instance.add(AssistantHistoryEntry(
          id: historyId,
          kind: id,
          summary:
              '${saved.number} · ${saved.title} · ${material.code} · ${scheme.label}',
          recordId: saved.id,
          at: ctx.now(),
          byVoice:
              s['origin_voice'] == true || (m.utterance?.byVoice ?? false)));
      return () async {
        if (!await dao.softDeleteIfUnchanged(saved)) {
          throw StateError('The quote was edited after confirmation');
        }
        await AssistantHistoryStore.instance.markUndone(historyId);
      };
    }, show: ShowInModule(toolId, {'quote_id': draft.id}));
  }
}
