// Zaufanie w aplikacji społecznościowej sprowadza się do dwóch pytań:
// „kto to napisał?" i „jak sprawię, żeby przestał?". Te testy pinują odpowiedzi.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/chat_service.dart';
import 'package:cut_list_app/services/user_profile.dart';

void main() {
  group('podpis na czacie', () {
    test('to imię i nazwisko z profilu, nie osobna ksywka', () async {
      SharedPreferences.setMockInitialValues({
        'user_profile_v1':
            jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      });
      UserProfileService.instance.resetForTest();

      expect(await ChatService.instance.getNickname(), 'Marek Kowalczyk');
    });

    test('zmiana nazwy w profilu zmienia podpis natychmiast', () async {
      SharedPreferences.setMockInitialValues({
        'user_profile_v1': jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      });
      UserProfileService.instance.resetForTest();
      expect(await ChatService.instance.getNickname(), 'Marek Kowalczyk');

      await UserProfileService.instance
          .save(const UserProfile(firstName: 'Marek', lastName: 'Nowak'));

      // Brak zapisanej kopii nicka => brak rozjazdu.
      expect(await ChatService.instance.getNickname(), 'Marek Nowak');
    });

    test('stary klucz "fitter_chat_nickname" jest ignorowany', () async {
      // Instalacje sprzed zmiany mogą mieć zapisaną dowolną ksywkę.
      // Nie wolno jej użyć — to była właśnie furtka do podszywania się.
      SharedPreferences.setMockInitialValues({
        'fitter_chat_nickname': 'Tomasz W.',
        'user_profile_v1': jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
      });
      UserProfileService.instance.resetForTest();

      expect(await ChatService.instance.getNickname(), 'Marek Kowalczyk');
    });
  });

  group('blokowanie autorów', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BlockedUsers.instance.resetForTest();
    });

    test('trzyma się deviceId, nie nazwy — zmiana nazwy nie zdejmuje blokady',
        () async {
      await BlockedUsers.instance.load();
      await BlockedUsers.instance.block('dev-abc', 'Zbigniew Hałas');

      expect(BlockedUsers.instance.isBlocked('dev-abc'), isTrue);
      expect(BlockedUsers.instance.isBlocked('dev-inny'), isFalse);

      // Ten sam człowiek, nowa nazwa: blokada nadal działa.
      await BlockedUsers.instance.block('dev-abc', 'Zbyszek H.');
      expect(BlockedUsers.instance.isBlocked('dev-abc'), isTrue);
      expect(BlockedUsers.instance.count, 1);
    });

    test('przeżywa restart aplikacji', () async {
      await BlockedUsers.instance.load();
      await BlockedUsers.instance.block('dev-abc', 'Zbigniew Hałas');

      // Symulacja zimnego startu: nowy hydrat z tych samych preferencji.
      BlockedUsers.instance.resetForTest();
      await BlockedUsers.instance.load();

      expect(BlockedUsers.instance.isBlocked('dev-abc'), isTrue);
      expect(BlockedUsers.instance.all.single.name, 'Zbigniew Hałas');
    });

    test('odblokowanie działa i jest trwałe', () async {
      await BlockedUsers.instance.load();
      await BlockedUsers.instance.block('dev-abc', 'Zbigniew Hałas');
      await BlockedUsers.instance.unblock('dev-abc');

      BlockedUsers.instance.resetForTest();
      await BlockedUsers.instance.load();

      expect(BlockedUsers.instance.isBlocked('dev-abc'), isFalse);
      expect(BlockedUsers.instance.count, 0);
    });

    test('pusty deviceId nie tworzy blokady-widma', () async {
      await BlockedUsers.instance.load();
      await BlockedUsers.instance.block('', 'ktoś');
      expect(BlockedUsers.instance.count, 0);
    });
  });
}
