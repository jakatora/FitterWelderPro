// Historia zatwierdzonych operacji asystenta (spec §3 pkt 3) i jego ustawienia.
// Tylko lokalnie (SharedPreferences) — nic stąd nie wychodzi z telefonu.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/local_record_owner.dart';
import '../services/account_service.dart';

class AssistantHistoryEntry {
  final String id;

  /// Intencja, np. `save_weld_parameter`.
  final String kind;

  /// Jednolinijkowy opis tego, co zapisano („TIG bez drutu · SS · t 2 mm · 60 A").
  final String summary;

  /// Identyfikator zapisanego rekordu (do „Cofnij").
  final String recordId;
  final DateTime at;
  final bool byVoice;
  final bool undone;

  /// Konto, którego to operacja. Pusty = jeszcze nieprzypisany:
  /// [AssistantHistoryStore.add] wpisuje bieżące konto. Wpisy sprzed kont
  /// (bez pola w JSON) należą do gościa.
  final String ownerScope;

  const AssistantHistoryEntry({
    required this.id,
    required this.kind,
    required this.summary,
    required this.recordId,
    required this.at,
    required this.byVoice,
    this.undone = false,
    this.ownerScope = '',
  });

  AssistantHistoryEntry markUndone() => _copy(undone: true);

  AssistantHistoryEntry withOwner(String owner) => _copy(ownerScope: owner);

  AssistantHistoryEntry _copy({bool? undone, String? ownerScope}) =>
      AssistantHistoryEntry(
        id: id,
        kind: kind,
        summary: summary,
        recordId: recordId,
        at: at,
        byVoice: byVoice,
        undone: undone ?? this.undone,
        ownerScope: ownerScope ?? this.ownerScope,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'kind': kind,
        'summary': summary,
        'recordId': recordId,
        'at': at.millisecondsSinceEpoch,
        'byVoice': byVoice,
        'undone': undone,
        'ownerScope': ownerScope,
      };

  static AssistantHistoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kind = raw['kind'];
    final summary = raw['summary'];
    final recordId = raw['recordId'];
    final at = raw['at'];
    if (id is! String ||
        kind is! String ||
        summary is! String ||
        recordId is! String ||
        at is! num) {
      return null;
    }
    return AssistantHistoryEntry(
      id: id,
      kind: kind,
      summary: summary,
      recordId: recordId,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      byVoice: raw['byVoice'] == true,
      undone: raw['undone'] == true,
      ownerScope:
          raw['ownerScope'] is String ? raw['ownerScope'] as String : 'guest',
    );
  }
}

class AssistantHistoryStore extends ChangeNotifier {
  AssistantHistoryStore._();
  static final AssistantHistoryStore instance = AssistantHistoryStore._();

  static const _kKey = 'assistant_history_v1';
  static const _kSpeakKey = 'assistant_speak_replies_v1';

  /// Najwięcej wpisów trzymanych w historii (najstarsze wypadają).
  static const int maxEntries = 100;

  List<AssistantHistoryEntry> _entries = const [];
  bool _speakReplies = false;
  bool _loaded = false;
  bool _readFailed = false;
  bool _saveFailed = false;
  bool get persistenceFailed => _readFailed || _saveFailed;
  Future<void>? _loading;
  Future<void>? _writes;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _writes;
    final result =
        previous == null ? operation() : previous.then((_) => operation());
    final settled =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return result;
  }

  Future<T> _serialOwned<T>(Future<T> Function(LocalRecordOwner) operation) {
    Object? captureError;
    StackTrace? captureStack;
    final ownerReady = LocalRecordOwner.capture().then<LocalRecordOwner?>(
      (owner) => owner,
      onError: (Object error, StackTrace stack) {
        captureError = error;
        captureStack = stack;
        return null;
      },
    );
    return _serial(() async {
      final owner = await ownerReady;
      if (owner == null) {
        Error.throwWithStackTrace(captureError!, captureStack!);
      }
      owner.requireCurrent();
      return operation(owner);
    });
  }

  /// Operacje bieżącego konta, najnowsze pierwsze. Historia opisuje zapisy
  /// zawodowe (spoiny, protokoły, wyceny) — inne konto na tym telefonie jej
  /// nie widzi.
  List<AssistantHistoryEntry> get entries {
    final owner = _currentOwner();
    return _entries
        .where((entry) => entry.ownerScope == owner)
        .toList(growable: false);
  }

  static String? _currentOwner() {
    final account = AccountService.instance;
    final id = account.account?['id'] ?? account.localOwnerId;
    return id is String
        ? 'account:$id'
        : (account.needsIdentityRefresh ? null : LocalRecordOwner.guest);
  }

  /// Czytanie odpowiedzi na głos — domyślnie WYŁĄCZONE.
  bool get speakReplies => _speakReplies;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _loadNow().whenComplete(() => _loading = null);
  }

  Future<void> _loadNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          _entries = list
              .map(AssistantHistoryEntry.fromJson)
              .whereType<AssistantHistoryEntry>()
              .toList(growable: false);
          _readFailed = _entries.length != list.length;
        } else {
          _readFailed = true;
        }
      }
      _speakReplies = prefs.getBool(_kSpeakKey) ?? false;
    } catch (e) {
      _readFailed = true;
      debugPrint('AssistantHistoryStore.load: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(AssistantHistoryEntry entry) {
    if (entry.ownerScope.isEmpty) {
      return _serialOwned((owner) => _addNow(entry.withOwner(owner.key)));
    }
    return _serial(() => _addNow(entry));
  }

  Future<void> _addNow(AssistantHistoryEntry entry) async {
    await load();
    // [maxEntries] na konto — wpisy jednego konta nie wypychają drugiego.
    final perOwner = <String, int>{};
    _entries = [
      for (final e in [entry, ..._entries])
        if ((perOwner[e.ownerScope] = (perOwner[e.ownerScope] ?? 0) + 1) <=
            maxEntries)
          e,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> markUndone(String entryId) => _serialOwned((owner) async {
        await load();
        _entries = [
          for (final e in _entries)
            e.id == entryId && e.ownerScope == owner.key ? e.markUndone() : e,
        ];
        notifyListeners();
        await _save();
      });

  Future<bool> setSpeakReplies(bool value) => _serial(() async {
        await load();
        _speakReplies = value;
        notifyListeners();
        try {
          final prefs = await SharedPreferences.getInstance();
          if (!await prefs.setBool(_kSpeakKey, value)) return false;
          await prefs.reload();
          return prefs.getBool(_kSpeakKey) == value;
        } catch (e) {
          debugPrint('AssistantHistoryStore.setSpeakReplies: $e');
          return false;
        }
      });

  Future<bool> _save() async {
    final saved = await _persistNow();
    _saveFailed = !saved;
    notifyListeners();
    return saved;
  }

  Future<bool> _persistNow() async {
    if (_readFailed) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
      if (!await prefs.setString(_kKey, encoded)) return false;
      await prefs.reload();
      return prefs.getString(_kKey) == encoded;
    } catch (e) {
      debugPrint('AssistantHistoryStore.save: $e');
      return false;
    }
  }

  /// Kasuje historię operacji (pamięć i dysk) — „Usuń moje dane" w profilu.
  /// Ustawienie czytania na głos zostaje: to preferencja, nie dane.
  ///
  /// Tylko wpisy bieżącego konta — „moje dane” nie obejmują operacji innego
  /// konta na tym samym telefonie.
  Future<bool> clear() => _serialOwned((owner) async {
        await load();
        owner.requireCurrent();
        if (_readFailed) return false;
        _entries = [
          for (final e in _entries)
            if (e.ownerScope != owner.key) e
        ];
        notifyListeners();
        if (_entries.isNotEmpty) return _save();
        try {
          final prefs = await SharedPreferences.getInstance();
          final removed = await prefs.remove(_kKey);
          await prefs.reload();
          return removed && !prefs.containsKey(_kKey);
        } catch (e) {
          debugPrint('AssistantHistoryStore.clear: $e');
          return false;
        }
      });

  @visibleForTesting
  void resetForTest() {
    _entries = const [];
    _speakReplies = false;
    _loaded = false;
    _readFailed = false;
    _saveFailed = false;
    _loading = null;
    _writes = null;
  }
}
