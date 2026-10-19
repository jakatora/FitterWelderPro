// Wspólne ziarna testów feedbacku (bez sieci, SharedPreferences w pamięci).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_signal.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/feedback/feedback_uploader.dart';
import 'package:cut_list_app/i18n/app_language.dart';

/// Czysty stan: puste preferencje, singletony od zera.
void seedFeedback([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues({...values});
  FeedbackStore.instance.resetForTest();
  FeedbackConsent.instance.resetForTest();
  FeedbackUploader.instance.resetForTest();
}

/// Przewidywalny UUID (serwer przyjmuje tylko UUID jako `id`).
String uid(int i) =>
    '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';

/// Sygnał testowy o przewidywalnym id i czasie.
FeedbackSignal sig(
  int i, {
  FeedbackKind kind = FeedbackKind.notUnderstood,
  String? text,
}) =>
    FeedbackSignal.create(
      kind: kind,
      text: text ?? 'polecenie $i',
      tool: 'iso_notebook',
      id: uid(i),
      lang: AppLanguage.pl,
      at: DateTime.utc(2026, 10, 19, 12).add(Duration(seconds: i)),
    );

/// Zapis kolejki w formacie `feedback_queue_v1` (szybkie ziarno dużych kolejek).
String queueJson(List<Object> items, {int dropped = 0}) => jsonEncode({
      'v': 1,
      'items': [
        for (final s in items) s is FeedbackSignal ? s.toJson() : s,
      ],
      'dropped': dropped,
      'rejected': 0,
      'sent': 0,
      'corrupt': false,
    });

/// Wypełnia kolejkę sygnałami [from]..[to) (po kolei, czekając na zapis).
Future<void> fill(int from, int to,
    {FeedbackKind kind = FeedbackKind.notUnderstood}) async {
  for (var i = from; i < to; i++) {
    await FeedbackStore.instance.add(sig(i, kind: kind));
  }
}
