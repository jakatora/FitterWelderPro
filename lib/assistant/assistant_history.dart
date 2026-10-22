// Historia zatwierdzonych operacji asystenta (spec §3 pkt 3) i jego ustawienia.
// Tylko lokalnie (SharedPreferences) — nic stąd nie wychodzi z telefonu.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final String ownerScope;

  const AssistantHistoryEntry({
    required this.id,
    required this.kind,
    required this.summary,
    required this.recordId,
    required this.at,
    required this.byVoice,
    this.undone = false,
    this.ownerScope = 'guest',
  });

  AssistantHistoryEntry markUndone() => AssistantHistoryEntry(
        id: id,
        kind: kind,
        summary: summary,
        recordId: recordId,
        at: at,
        byVoice: byVoice,
        undone: true,
        ownerScope: ownerScope,
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

  /// Najnowsze pierwsze.
  List<AssistantHistoryEntry> get entries {
    final account = AccountService.instance;
    final id = account.account?['id'] ?? account.localOwnerId;
    final owner = id is String
        ? 'account:$id'
        : (account.needsIdentityRefresh ? null : 'guest');
    return _entries
        .where((entry) =>
            !const {
              'save_weld_parameter',
              'add_weld_journal_entry',
              'interpass.reading'
            }.contains(entry.kind) ||
            entry.ownerScope == owner)
        .toList(growable: false);
  }

  /// Czytanie odpowiedzi na głos — domyślnie WYŁĄCZONE.
  bool get speakReplies => _speakReplies;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          _entries = list
              .map(AssistantHistoryEntry.fromJson)
              .whereType<AssistantHistoryEntry>()
              .toList(growable: false);
        }
      }
      _speakReplies = prefs.getBool(_kSpeakKey) ?? false;
    } catch (e) {
      debugPrint('AssistantHistoryStore.load: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(AssistantHistoryEntry entry) async {
    await load();
    _entries = [entry, ..._entries].take(maxEntries).toList(growable: false);
    notifyListeners();
    await _save();
  }

  Future<void> markUndone(String entryId) async {
    await load();
    _entries = [
      for (final e in _entries) e.id == entryId ? e.markUndone() : e,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> setSpeakReplies(bool value) async {
    await load();
    _speakReplies = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSpeakKey, value);
    } catch (e) {
      debugPrint('AssistantHistoryStore.setSpeakReplies: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('AssistantHistoryStore.save: $e');
    }
  }

  /// Kasuje historię operacji (pamięć i dysk) — „Usuń moje dane" w profilu.
  /// Ustawienie czytania na głos zostaje: to preferencja, nie dane.
  Future<void> clear() async {
    _entries = const [];
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    } catch (e) {
      debugPrint('AssistantHistoryStore.clear: $e');
    }
  }

  @visibleForTesting
  void resetForTest() {
    _entries = const [];
    _speakReplies = false;
    _loaded = false;
  }
}
