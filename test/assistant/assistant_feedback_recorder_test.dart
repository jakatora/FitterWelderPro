import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/assistant_feedback_recorder.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('brak zgody: raport tylko lokalny, maskowanie danych i deduplikacja',
      () async {
    var uploads = 0;
    final recorder = AssistantFeedbackRecorder(upload: () async {
      uploads++;
    });
    const text = 'Brak funkcji. Kontakt jan@example.com tel 501234567';
    await recorder.missing(text, tool: 'iso_notebook', lang: AppLanguage.pl);
    await recorder.missing(text, tool: 'iso_notebook', lang: AppLanguage.pl);
    final signals = await FeedbackStore.instance.list();
    expect(signals, hasLength(1));
    expect(signals.single.text, isNot(contains('jan@example.com')));
    expect(signals.single.text, isNot(contains('501234567')));
    expect(uploads, 0);
  });
  test('osobna zgoda pozwala uruchomić wysyłkę raportu', () async {
    await FeedbackConsent.instance.grant();
    var uploads = 0;
    final recorder = AssistantFeedbackRecorder(upload: () async {
      uploads++;
    });
    await recorder.missing('narysuj trójnik',
        tool: 'iso_notebook', skill: 'iso.unsupported', lang: AppLanguage.pl);
    expect(uploads, 1);
  });
}
