import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/assistant_feedback_recorder.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/feedback/feedback_signal.dart';
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

  test('zgłoszenie problemu: bez zgody zostaje na telefonie, raz', () async {
    var uploads = 0;
    final recorder = AssistantFeedbackRecorder(upload: () async {
      uploads++;
    });
    const text = 'nie działa mi zapis wyceny, zgłoś to';
    expect(
        await recorder.report(text, FeedbackKind.explicit,
            tool: 'weld_quotes', lang: AppLanguage.pl),
        isFalse);
    expect(
        await recorder.report(text, FeedbackKind.explicit,
            tool: 'weld_quotes', lang: AppLanguage.pl),
        isFalse);
    final signals = await FeedbackStore.instance.list();
    expect(signals, hasLength(1));
    expect(signals.single.kind, FeedbackKind.explicit);
    expect(signals.single.tool, 'weld_quotes');
    expect(uploads, 0);
  });
  test('zgłoszenie problemu: ze zgodą rusza wysyłka, błąd wysyłki nie psuje',
      () async {
    await FeedbackConsent.instance.grant();
    var uploads = 0;
    final recorder = AssistantFeedbackRecorder(upload: () async {
      uploads++;
      throw StateError('offline');
    });
    expect(
        await recorder.report('kalkulator źle liczy', FeedbackKind.complaint,
            lang: AppLanguage.pl),
        isTrue);
    await pumpEventQueue();
    expect(uploads, 1);
    expect((await FeedbackStore.instance.list()).single.kind,
        FeedbackKind.complaint);
  });
}
