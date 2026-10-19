// Mózg asystenta (spec §4.3, plan zadanie 1.3) — lokalny i deterministyczny.
//
// Kolejność na jedną turę:
//   1. pytanie w toku: wypowiedź z wartością slotu → `run` z dołożonym
//      slotem; „anuluj / nie / stop" → kasuje; inna umiejętność ≥ progu →
//      kasuje pytanie i obsługuje nową; bełkot → to samo pytanie;
//   2. ocena wszystkich zwykłych umiejętności dla tekstu i każdej
//      alternatywy N-best (premia kontekstu dla bieżącego modułu); remis
//      umiejętności z różnych modułów → „Chodzi o … czy …?";
//   3. kontynuacja („a dla DN50?" w ciągu 2 min) i dopowiedzenie (8 s, bez
//      słowa kontynuacji) — ostatnia umiejętność z nowymi slotami; oceniane
//      RAZEM z punktem 2 (kontynuacja ze słowem „a/and" ma 0,8, więc samo
//      „DN50" innej umiejętności, warte 0,7, jej nie podbierze, a jawne
//      słowa zamiaru, warte 0,9, tak);
//   4. fallbacki w kolejności `fallbackOrder` (co umiem → otwórz → wyjaśnij
//      → wiedza);
//   5. „nie rozumiem" z 3 propozycjami narzędzi;
//   6. wyjątek w `run` → [FailedResult] (karta „Nie udało się").
//
// Polecenie rozpoznane tutaj nigdy nie idzie na serwer (spec §3.7) — mózg
// nie ma klienta HTTP.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../i18n/app_language.dart';
import '../../widgets/tool_registry.dart' show toolById;
import 'skill.dart';
import 'tool_lookup.dart';

class BrainReply {
  const BrainReply(this.result,
      {this.match, this.notUnderstood = false, this.usedAlternative});

  final SkillResult result;

  /// Trafienie, które dało wynik (null przy „nie rozumiem" i „anuluj").
  final SkillMatch? match;

  /// Sygnał feedbacku „nie rozumiem" (zadanie 5.1b).
  final bool notUnderstood;

  /// Alternatywa N-best, która wygrała z tekstem głównym (null = tekst).
  final String? usedAlternative;
}

/// Wynik kontynuacji ze słowem „a / and / what about".
const double _continuationScore = 0.8;

/// Wynik dopowiedzenia (do 8 s, bez słowa kontynuacji).
const double _appendScore = 0.6;

final RegExp _cancelRe = RegExp(
    r'^(?:(?:no|ok|okej|dobra)\s+)?(?:anuluj\w*|nie|stop|zostaw|nic|niewazne|'
    r'nie wazne|koniec|daj spokoj|cancel|never ?mind|no|forget it|leave it)'
    r'(?:\s+(?:to|it|tego|juz|already))?$');

final RegExp _firstRe = RegExp(r'^(?:to |the )?(?:pierwsz\w*|first|1|jeden|jedno)$');
final RegExp _secondRe =
    RegExp(r'^(?:to |the )?(?:drug\w*|second|2|dwa|drugie)$');

class _Scored {
  _Scored(this.match, this.score, this.candidate, this.order);
  final SkillMatch match;
  final double score;

  /// 0 = tekst główny, 1.. = alternatywy.
  final int candidate;

  /// Kolejność umiejętności w katalogu (rozstrzyga pełny remis).
  final int order;
}

class AssistantBrain {
  AssistantBrain({
    required List<AssistantSkill> skills,
    this.threshold = 0.55,
    this.ambiguityGap = 0.08,
    this.contextBonus = 0.1,
    List<FollowUp> Function(Utterance u)? suggest,
  })  : skills = List.unmodifiable(skills),
        _suggest = suggest ?? suggestTools;

  /// Katalog (zwykłe umiejętności i fallbacki).
  final List<AssistantSkill> skills;
  final double threshold;
  final double ambiguityGap;
  final double contextBonus;
  final List<FollowUp> Function(Utterance u) _suggest;

  AskResult? _pending;
  List<SkillMatch>? _tie;
  Future<void> _tail = Future<void>.value();

  /// Pytanie, na które asystent czeka.
  AskResult? get pending => _pending;

  void cancelPending() {
    _pending = null;
    _tie = null;
  }

  late final List<AssistantSkill> _regular = [
    for (final s in skills)
      if (s.fallbackOrder == null) s,
  ];

  late final List<AssistantSkill> _fallbacks = [
    for (final s in skills)
      if (s.fallbackOrder != null) s,
  ]..sort((a, b) => a.fallbackOrder!.compareTo(b.fallbackOrder!));

  /// Ocena tekstu i alternatyw; wybór najwyższego wyniku. Jedna tura naraz —
  /// kolejne wywołania czekają na poprzednie.
  Future<BrainReply> handle(Utterance u, AssistantContext ctx) {
    final next = _tail.then((_) => _handle(u, ctx));
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<BrainReply> _handle(Utterance u, AssistantContext ctx) async {
    final cands = <Utterance>[
      u,
      for (final alt in u.alternatives.toSet())
        if (alt.trim().isNotEmpty && alt.trim() != u.raw.trim()) u.withRaw(alt),
    ];
    if (u.folded.isEmpty && cands.length == 1) return _notUnderstood(u);

    final p = _pending;
    if (p != null) {
      final answered = _answerPending(p, cands, ctx);
      if (answered != null) return _run(answered.$1, ctx, answered.$2);
      if (cands.any((c) => _cancelRe.hasMatch(c.folded))) {
        cancelPending();
        return const BrainReply(AnswerResult(AssistantAnswer(
            text: AssistantText('Dobrze, zostawiam.', 'OK, dropped.'))));
      }
      final routed = await _route(cands, ctx, keepPending: p);
      if (routed != null) return routed;
      // Nic innego — powtarzamy pytanie.
      return BrainReply(p, match: p.partial);
    }
    return await _route(cands, ctx) ?? _notUnderstood(u);
  }

  /// Odpowiedź na pytanie w toku: (trafienie z dołożonym slotem, alternatywa).
  (SkillMatch, String?)? _answerPending(
      AskResult p, List<Utterance> cands, AssistantContext ctx) {
    final tie = _tie;
    if (p.slot == 'skill' && tie != null) {
      for (final c in cands) {
        final i = _tieChoice(p, c);
        if (i != null) {
          cancelPending();
          final m = tie[i];
          return (m, c == cands.first ? null : c.raw);
        }
      }
      return null;
    }
    for (final c in cands) {
      Map<String, Object?>? slots;
      try {
        slots = p.partial.skill.fillSlot(p.slot, c, ctx);
      } catch (e) {
        debugPrint('Asystent: fillSlot ${p.partial.skill.id}: $e');
      }
      if (slots == null) continue;
      cancelPending();
      final m = p.partial.copyWith(
          slots: {...p.partial.slots, ...slots}, missing: const [], utterance: c);
      return (m, c == cands.first ? null : c.raw);
    }
    return null;
  }

  int? _tieChoice(AskResult p, Utterance c) {
    final f = c.folded;
    if (_firstRe.hasMatch(f)) return 0;
    if (_secondRe.hasMatch(f)) return 1;
    for (var i = 0; i < p.choices.length; i++) {
      final ch = p.choices[i];
      final options = {
        Utterance(ch.utterance, lang: c.lang).folded,
        Utterance(ch.label.pl, lang: c.lang).folded,
        Utterance(ch.label.en, lang: c.lang).folded,
      };
      if (options.contains(f)) return i;
    }
    return null;
  }

  /// Ocena zwykłych umiejętności + kontynuacja, potem fallbacki. null = nic.
  /// [keepPending] — pytanie w toku, które kasujemy tylko, gdy coś trafi.
  Future<BrainReply?> _route(List<Utterance> cands, AssistantContext ctx,
      {AskResult? keepPending}) async {
    final scored = <_Scored>[];
    for (var ci = 0; ci < cands.length; ci++) {
      final c = cands[ci];
      for (var si = 0; si < _regular.length; si++) {
        final s = _regular[si];
        final m = _safeMatch(s, c, ctx);
        if (m == null) continue;
        var score = m.score;
        if (s.toolId != null && s.toolId == ctx.modules.activeToolId) {
          score += contextBonus;
        }
        scored.add(_Scored(m, score, ci, si));
      }
      final cont = _continuation(c, ctx);
      if (cont != null) {
        scored.add(_Scored(cont, cont.score, ci, -1));
      }
    }
    scored.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final c = a.candidate.compareTo(b.candidate);
      if (c != 0) return c;
      return a.order.compareTo(b.order);
    });

    if (scored.isNotEmpty && scored.first.score >= threshold) {
      final best = scored.first;
      if (keepPending != null) cancelPending();
      final rival = _rival(best, scored);
      if (rival != null) return _askTie(best, rival, ctx);
      return _run(best.match, ctx,
          best.candidate == 0 ? null : cands[best.candidate].raw);
    }

    for (final s in _fallbacks) {
      for (var ci = 0; ci < cands.length; ci++) {
        final m = _safeMatch(s, cands[ci], ctx);
        if (m == null || m.score < threshold) continue;
        if (keepPending != null) cancelPending();
        return _run(m, ctx, ci == 0 ? null : cands[ci].raw);
      }
    }
    return null;
  }

  /// Kontynuacja / dopowiedzenie ostatniej umiejętności dla [c] albo null.
  SkillMatch? _continuation(Utterance c, AssistantContext ctx) {
    final last = ctx.recentMatch();
    if (last == null || last.skill.fallbackOrder != null) return null;
    final marker = c.isContinuation;
    if (!marker && ctx.recentMatch(within: kAppendWindow) == null) return null;
    Map<String, Object?> slots;
    try {
      slots = last.skill.slotsFrom(c, ctx);
    } catch (e) {
      debugPrint('Asystent: slotsFrom ${last.skill.id}: $e');
      return null;
    }
    if (slots.isEmpty) return null;
    return last.copyWith(
      score: marker ? _continuationScore : _appendScore,
      slots: {...last.slots, ...slots},
      missing: const [],
      utterance: c,
    );
  }

  /// Najlepszy konkurent z INNEGO modułu w odległości < [ambiguityGap].
  _Scored? _rival(_Scored best, List<_Scored> scored) {
    final bestSkill = best.match.skill;
    for (final s in scored.skip(1)) {
      if (best.score - s.score >= ambiguityGap) return null;
      if (s.score < threshold) return null;
      final skill = s.match.skill;
      if (identical(skill, bestSkill)) continue;
      if (skill.toolId != null && skill.toolId == bestSkill.toolId) continue;
      return s;
    }
    return null;
  }

  BrainReply _askTie(_Scored a, _Scored b, AssistantContext ctx) {
    final la = _skillLabel(a.match.skill), lb = _skillLabel(b.match.skill);
    final ask = AskResult(
      'skill',
      AssistantText('Chodzi o „${la.pl}” czy „${lb.pl}”?',
          'Do you mean "${la.en}" or "${lb.en}"?'),
      partial: a.match,
      choices: [
        FollowUp(la, la.of(ctx.lang)),
        FollowUp(lb, lb.of(ctx.lang)),
      ],
    );
    _pending = ask;
    _tie = [a.match, b.match];
    return BrainReply(ask, match: a.match);
  }

  AssistantText _skillLabel(AssistantSkill s) {
    final id = s.toolId;
    final tool = id == null ? null : toolById(id);
    if (tool != null) return toolTitleText(tool);
    final ex = s.examples.isEmpty ? null : s.examples.first;
    return ex == null ? AssistantText.same(s.id) : AssistantText(ex.pl, ex.en);
  }

  SkillMatch? _safeMatch(AssistantSkill s, Utterance u, AssistantContext ctx) {
    try {
      return s.match(u, ctx);
    } catch (e) {
      // Błąd jednej umiejętności nie może wyłączyć całego asystenta.
      debugPrint('Asystent: match ${s.id}: $e');
      return null;
    }
  }

  Future<BrainReply> _run(
      SkillMatch m, AssistantContext ctx, String? usedAlternative) async {
    SkillResult r;
    try {
      r = await m.skill.run(m, ctx);
    } catch (e, st) {
      debugPrint('Asystent: run ${m.skill.id}: $e\n$st');
      return BrainReply(
        const FailedResult(AssistantText(
            'Nie udało się — spróbuj jeszcze raz albo otwórz moduł ręcznie.',
            'Something went wrong — try again or open the module by hand.')),
        match: m,
        usedAlternative: usedAlternative,
      );
    }
    switch (r) {
      case AskResult():
        _pending = r;
        _tie = null;
      case AnswerResult() || ConfirmResult():
        ctx.remember(m);
      case NotUnderstood() || FailedResult():
        break;
    }
    return BrainReply(r,
        match: m,
        notUnderstood: r is NotUnderstood,
        usedAlternative: usedAlternative);
  }

  BrainReply _notUnderstood(Utterance u) {
    List<FollowUp> tools;
    try {
      tools = _suggest(u);
    } catch (e) {
      debugPrint('Asystent: propozycje: $e');
      tools = const [];
    }
    final out = [...tools.take(3)];
    if (out.isEmpty) {
      out.add(FollowUp(const AssistantText('Co umiesz?', 'What can you do?'),
          u.lang == AppLanguage.en ? 'what can you do?' : 'co umiesz?'));
    }
    return BrainReply(NotUnderstood(out), notUnderstood: true);
  }
}
