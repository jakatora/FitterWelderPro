// Zasady, zgoda i filtr treści — trzy rzeczy, których Apple wymaga przy
// treściach tworzonych przez użytkowników (wytyczna 1.2).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/services/content_filter.dart';
import 'package:cut_list_app/services/legal_consent.dart';

void main() {
  group('filtr treści', () {
    test('przepuszcza normalną rozmowę montera', () {
      const ok = [
        'Kto robił P91 25 mm? Jaki preheat trzymacie?',
        'Weź szmatę i przetrzyj rowek przed spawaniem.',
        'Ciężka robota, ale kolano wyszło idealnie.',
        'DN100, ścianka 6 mm, takeout 45° to 64 mm.',
        'Chełm, Kraków, Gdańsk — wszędzie ta sama stal.',
      ];
      for (final t in ok) {
        expect(ContentFilter.isObjectionable(t), isFalse, reason: 'zablokowano: "$t"');
      }
    });

    test('zatrzymuje wyzwiska', () {
      const bad = ['ty debilu', 'kurwa mać', 'chujowa robota', 'fuck this'];
      for (final t in bad) {
        expect(ContentFilter.isObjectionable(t), isTrue, reason: 'przepuszczono: "$t"');
      }
    });

    test('radzi sobie z polskimi znakami i leetspeakiem', () {
      expect(ContentFilter.isObjectionable('pedał'), isTrue);
      expect(ContentFilter.isObjectionable('ch0j'), isFalse); // 0->o daje "choj"
      expect(ContentFilter.isObjectionable('deb1l'), isTrue); // 1->i
      expect(ContentFilter.isObjectionable('f4ck'), isFalse); // 4->a daje "fack"
      expect(ContentFilter.isObjectionable('fu4k'), isFalse);
    });

    test('dopasowuje całe słowa, nie fragmenty', () {
      // „ciotka" nie zawiera zabronionego „ciota".
      expect(ContentFilter.isObjectionable('moja ciotka spawa lepiej'), isFalse);
    });

    test('zwraca dopasowany rdzeń do logu moderacji', () {
      expect(ContentFilter.firstOffense('to jest chujowe'), 'chuj');
      expect(ContentFilter.firstOffense('wszystko gra'), isNull);
    });
  });

  group('zgoda na zasady', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LegalConsent.instance.resetForTest();
    });

    test('świeża instalacja nie ma zgody', () async {
      await LegalConsent.instance.load();
      expect(LegalConsent.instance.isAccepted, isFalse);
    });

    test('akceptacja jest trwała', () async {
      await LegalConsent.instance.load();
      await LegalConsent.instance.accept();
      expect(LegalConsent.instance.isAccepted, isTrue);

      LegalConsent.instance.resetForTest();
      await LegalConsent.instance.load();
      expect(LegalConsent.instance.isAccepted, isTrue);
      expect(LegalConsent.instance.acceptedAt, isNotNull);
    });

    test('zgoda na STARSZĄ wersję zasad nie wystarcza', () async {
      // Ktoś zaakceptował dokument, którego już nie ma. Musi zobaczyć nowy.
      SharedPreferences.setMockInitialValues({
        'legal_consent_v1': jsonEncode({
          'version': kLegalVersion - 1,
          'acceptedAt': '2026-01-01T00:00:00.000',
        }),
      });
      LegalConsent.instance.resetForTest();
      await LegalConsent.instance.load();

      expect(LegalConsent.instance.isAccepted, isFalse);
    });

    test('usunięcie danych kasuje zgodę', () async {
      await LegalConsent.instance.load();
      await LegalConsent.instance.accept();
      await LegalConsent.instance.clear();
      expect(LegalConsent.instance.isAccepted, isFalse);
    });
  });

  group('dokumenty', () {
    test('wersja i data są ustawione', () {
      expect(kLegalVersion, greaterThanOrEqualTo(1));
      expect(kLegalUpdated, isNotEmpty);
      expect(kMinimumAge, greaterThanOrEqualTo(13));
    });
  });
}
