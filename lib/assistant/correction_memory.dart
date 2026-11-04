import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../database/local_record_owner.dart';
import '../security/credential_text.dart';
import '../i18n/app_language.dart';
import 'core/utterance.dart';

const _ignoredWords = {
  'jak',
  'jaki',
  'jaka',
  'jakie',
  'czym',
  'czy',
  'nie',
  'dlaczego',
  'czemu',
  'kiedy',
  'mozna',
  'jest',
  'oraz',
  'moge',
  'dla',
  'ile',
  'mam',
  'prosze',
  'wyjasnij',
  'pomoz',
  'chodzi',
  'pytanie',
  'sprawdz',
  'obliczyc',
  'policzyc',
  'dziala',
  'dzialac',
  'wybrac',
  'dobrac',
  // These words describe the form of a question, not its subject. Matching
  // on them alone would carry a TIG correction into an unrelated MIG query.
  'metoda',
  'metode',
  'metody',
  'metodzie',
  'metodami',
  'metod',
  'method',
  'methods',
  'rodzaj',
  'rodzaju',
  'rodzaje',
  'spawanie',
  'spawac',
  'rura',
  'rury',
  'material',
  'materialu',
  'stal',
  'what',
  'which',
  'does',
  'not',
  'why',
  'when',
  'can',
  'could',
  'would',
  'should',
  'with',
  'about',
  'please',
  'explain',
  'this',
  'that',
  'help',
  'tell',
  'how',
  'the',
  'for',
  'and',
};

final _gasForms = RegExp(r'^gaz(?:u|em|ie|y|ow|ami)?$');
final _heliumForms = RegExp(r'^hel(?:u|em|ie)?$');

String _canonicalTopic(String word) {
  // Small, explicit families avoid treating arbitrary personal names as
  // equivalent. Do not strip generic Polish suffixes from every word.
  if (word.startsWith('alumini')) return 'aluminium';
  if (word.startsWith('nierdzew')) return 'nierdzewna';
  if (word.startsWith('kolnierz')) return 'kolnierz';
  if (word.startsWith('kolan')) return 'kolano';
  if (word.startsWith('argon')) return 'argon';
  if (word.startsWith('koroz')) return 'korozja';
  if (word.startsWith('spoin')) return 'spoina';
  if (word == 'gas' || _gasForms.hasMatch(word)) {
    return 'gaz';
  }
  if (word.startsWith('oslonow') || word == 'shielding') return 'oslonowy';
  if (word.startsWith('przeplyw') || word == 'flow') return 'przeplyw';
  if (word.startsWith('cisnien') || word == 'pressure') return 'cisnienie';
  if (word.startsWith('temperatur') || word == 'temperature') return 'temperatura';
  if (word.startsWith('podgrzew') || word.startsWith('preheat')) return 'preheat';
  if (word.startsWith('srednic') || word == 'diameter') return 'srednica';
  if (word.startsWith('dlugosc') || word == 'length') return 'dlugosc';
  if (word == 'helium' || _heliumForms.hasMatch(word)) return 'hel';
  return word;
}

Set<String> _topicWords(String text) => Utterance(text, lang: AppLanguage.pl)
    .folded
    .replaceAllMapped(RegExp(r'\bdn\s+(\d{1,4})\b'), (match) => 'dn${match[1]}')
    .split(' ')
    .where((word) => word.length >= 3 && !_ignoredWords.contains(word))
    .map(_canonicalTopic)
    .toSet();

final _technicalCode =
    RegExp(r'^(?:tig|mig|mag|mma|wps|wpqr|dn\d+[a-z]?|\d{3}[a-z])$');
const _correctionTopics = {
  'aluminium',
  'nierdzewna',
  'kolnierz',
  'kolano',
  'argon',
  'korozja',
  'spoina',
  'gaz',
  'preheat',
  'hel',
};

Set<String> _correctionTechnicalTopics(Set<String> words) => words
    .where((word) =>
        _correctionTopics.contains(word) || _technicalCode.hasMatch(word))
    .toSet();

const _qualifierGroups = [
  {'tig', 'mig', 'mag', 'mma'},
  {'aluminium', 'nierdzewna'},
  {'argon', 'hel'},
];

final _explicitReplacement = RegExp(
    r'\b(?:nie|not)\s+(?:gaz\w*\s+)?'
    r'(?:chodz(?:i|ilo)\s+(?:mi\s+)?o\s+)?'
    r'(tig|mig|mag|mma|alumini\w*|nierdzew\w*|argon\w*|hel\w*)\s+'
    r'(?:tylko|lecz|but)\s+(?:o\s+)?(?:(?:stal|gaz)\w*\s+)?'
    r'(tig|mig|mag|mma|alumini\w*|nierdzew\w*|argon\w*|hel\w*)\b');

// Recognize assertions, not questions such as “Can I use helium instead of
// argon?”. Keeping this anchored also avoids reversing “I do not use…”.
final _usedGasInstead = RegExp(
    r'^(?:ja )?uzywam (hel(?:u|em|ie)?|argon\w*) zamiast (hel(?:u|em|ie)?|argon\w*)\b');
final _insteadUseGas = RegExp(
    r'^zamiast (hel(?:u|em|ie)?|argon\w*) uzywam (hel(?:u|em|ie)?|argon\w*)\b');
final _useGasInstead = RegExp(
    r'^(?:i )?use (helium|argon) instead of (helium|argon)\b');

Set<String> _effectiveCorrectionWords(String text) {
  final words = _topicWords(text);
  final folded = Utterance(text, lang: AppLanguage.pl).folded;
  void removeRejected(String rejectedWord, String acceptedWord) {
    final rejected = _canonicalTopic(rejectedWord);
    final accepted = _canonicalTopic(acceptedWord);
    if (rejected != accepted &&
        _qualifierGroups.any((group) => group.contains(rejected) && group.contains(accepted))) {
      words.remove(rejected);
    }
  }
  for (final match in _explicitReplacement.allMatches(folded)) {
    removeRejected(match[1]!, match[2]!);
  }
  final used = _usedGasInstead.firstMatch(folded) ?? _useGasInstead.firstMatch(folded);
  if (used != null) removeRejected(used[2]!, used[1]!);
  final instead = _insteadUseGas.firstMatch(folded);
  if (instead != null) removeRejected(instead[1]!, instead[2]!);
  return words;
}

bool _hasConflictingQualifier(
    Set<String> question, Set<String> original, Set<String> correction) {
  for (final group in _qualifierGroups) {
    final current = question.intersection(group);
    final corrected = correction.intersection(group);
    final remembered = corrected.isNotEmpty ? corrected : original.intersection(group);
    if (current.isNotEmpty && remembered.isNotEmpty &&
        current.intersection(remembered).isEmpty) {
      return true;
    }
  }
  return false;
}

/// Only attach memories sharing a topic with the current question. These are
/// unverified user statements, never a replacement for current input or WPS.
List<RememberedCorrection> relevantCorrections(
    String question, List<RememberedCorrection> records,
    {List<String> priorUserTurns = const []}) {
  final turns = [...priorUserTurns, question];
  final words = turns.expand(_topicWords).toSet();
  if (words.isEmpty) return const [];
  final qualifiers = <String>{};
  for (final group in _qualifierGroups) {
    for (final turn in turns.reversed) {
      final found = _effectiveCorrectionWords(turn).intersection(group);
      if (found.isNotEmpty) {
        qualifiers.addAll(found);
        break;
      }
    }
  }
  final ranked = <({RememberedCorrection record, int score, int order})>[];
  for (var i = 0; i < records.length; i++) {
    final record = records[i];
    final originalWords = _topicWords(record.question);
    final correctionWords = _effectiveCorrectionWords(record.correction);
    if (_hasConflictingQualifier(qualifiers, originalWords, correctionWords)) continue;
    final originalMatches = originalWords.intersection(words).length;
    final correctionMatches = _correctionTechnicalTopics(correctionWords)
        .intersection(words).length;
    final score = originalMatches * 2 + correctionMatches;
    if (score > 0) ranked.add((record: record, score: score, order: i));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.order.compareTo(b.order);
  });
  return ranked.take(3).map((entry) => entry.record).toList();
}

class RememberedCorrection {
  const RememberedCorrection(
      {required this.question, required this.correction});
  final String question;
  final String correction;

  Map<String, String> toJson() =>
      {'question': question, 'correction': correction};

  static RememberedCorrection parse(Object? raw) {
    if (raw is! Map ||
        raw['question'] is! String ||
        raw['correction'] is! String) {
      throw const FormatException('Invalid correction record');
    }
    final record = RememberedCorrection(
        question: raw['question'] as String,
        correction: raw['correction'] as String);
    _validate(record);
    return record;
  }
}

void _validate(RememberedCorrection entry) {
  for (final text in [entry.question, entry.correction]) {
    if (text.trim().isEmpty ||
        text.length > 500 ||
        containsCredentialValue(text)) {
      throw const FormatException('Invalid correction');
    }
  }
}

/// Account-scoped local records. They remain user statements, not verified
/// technical facts. This store does not send anything to a model.
class CorrectionMemoryStore {
  CorrectionMemoryStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  static final instance = CorrectionMemoryStore();
  static const maxRecords = 20;
  final FlutterSecureStorage _storage;
  Future<void> _tail = Future<void>.value();
  int _revision = 0;
  int _pendingMutations = 0;

  @visibleForTesting
  void resetForTest() => _tail = Future<void>.value();

  String _key(LocalRecordOwner owner) =>
      'assistant_corrections_v1_${sha256.convert(utf8.encode(owner.key))}';

  Future<T> _serial<T>(Future<T> Function(LocalRecordOwner) action) {
    Object? captureError;
    StackTrace? captureStack;
    final owner = LocalRecordOwner.capture().then<LocalRecordOwner?>(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        captureError = error;
        captureStack = stack;
        return null;
      },
    );
    final result = _tail.then((_) async {
      final captured = await owner;
      if (captured == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      captured.requireCurrent();
      final value = await action(captured);
      captured.requireCurrent();
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<List<RememberedCorrection>> _read(LocalRecordOwner owner) async {
    final raw = await _storage.read(key: _key(owner));
    owner.requireCurrent();
    if (raw == null) return const [];
    final value = jsonDecode(raw);
    if (value is! List || value.length > maxRecords) {
      throw const FormatException('Invalid correction memory');
    }
    return List.unmodifiable(value.map(RememberedCorrection.parse));
  }

  Future<List<RememberedCorrection>> list() => _serial(_read);

  Future<CorrectionMemorySnapshot> capture(String question,
          {List<String> priorUserTurns = const []}) =>
      _serial((owner) async {
        final records = relevantCorrections(question, await _read(owner),
            priorUserTurns: priorUserTurns);
        if (_pendingMutations != 0) throw const CorrectionMemoryChanged();
        return CorrectionMemorySnapshot._(this, owner, _revision, records);
      });

  Future<void> remember(RememberedCorrection entry) {
    _validate(entry);
    _revision++;
    _pendingMutations++;
    return _serial((owner) async {
      try {
        final old = await _read(owner);
        final next = [
          entry,
          ...old.where((e) =>
              e.question != entry.question || e.correction != entry.correction)
        ].take(maxRecords).toList();
        owner.requireCurrent();
        await _storage.write(key: _key(owner), value: jsonEncode(next));
      } finally {
        _revision++;
      }
    }).whenComplete(() => _pendingMutations--);
  }

  /// Captures the owner before account deletion. The returned operation only
  /// deletes this owner's partition, even if another account becomes active.
  Future<Future<void> Function()> prepareAccountDeletion() async {
    final owner = await LocalRecordOwner.capture();
    owner.requireCurrent();
    if (!owner.key.startsWith('account:')) {
      throw StateError('No account to delete');
    }
    return () {
      _revision++;
      _pendingMutations++;
      final result = _tail.then((_) => _storage.delete(key: _key(owner)));
      _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      return result.whenComplete(() {
        _revision++;
        _pendingMutations--;
      });
    };
  }

  Future<void> clear() {
    _revision++;
    _pendingMutations++;
    return _serial((owner) async {
      try {
        owner.requireCurrent();
        await _storage.delete(key: _key(owner));
      } finally {
        _revision++;
      }
    }).whenComplete(() => _pendingMutations--);
  }

  Future<void> forget(RememberedCorrection entry) {
    _revision++;
    _pendingMutations++;
    return _serial((owner) async {
      try {
        final old = await _read(owner);
        final remaining = old
            .where((item) =>
                item.question != entry.question ||
                item.correction != entry.correction)
            .toList();
        if (remaining.length == old.length) return;
        owner.requireCurrent();
        if (remaining.isEmpty) {
          await _storage.delete(key: _key(owner));
        } else {
          await _storage.write(key: _key(owner), value: jsonEncode(remaining));
        }
      } finally {
        _revision++;
      }
    }).whenComplete(() => _pendingMutations--);
  }
}

class CorrectionMemorySnapshot {
  CorrectionMemorySnapshot._(
      this._store, this._owner, this._revision, this.records);
  final CorrectionMemoryStore _store;
  final LocalRecordOwner _owner;
  final int _revision;
  final List<RememberedCorrection> records;

  void requireCurrent() {
    _owner.requireCurrent();
    if (_store._revision != _revision || _store._pendingMutations != 0) {
      throw const CorrectionMemoryChanged();
    }
  }
}

class CorrectionMemoryChanged implements Exception {
  const CorrectionMemoryChanged();
}
