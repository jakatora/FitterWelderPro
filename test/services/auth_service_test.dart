// AuthService (relikt prototypu, ekran rejestracji jest nieosiągalny) miał
// zaszytego użytkownika demo test@example.com / password123. Hasło w kodzie
// źle wygląda w audycie bezpieczeństwa i pozwalało „zalogować się" każdemu.
// Decyzja o usunięciu całego modułu należy do właściciela — tu tylko pilnujemy,
// że nie ma kont wbudowanych w kod.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/auth_service.dart';

void main() {
  test('brak wbudowanego użytkownika demo', () async {
    expect(
        await AuthService.authenticate('test@example.com', 'password123'),
        isFalse);
  });

  test('w kodzie nie ma hasła demo', () {
    final src = File('lib/services/auth_service.dart').readAsStringSync();
    expect(src, isNot(contains('password123')));
    expect(src, isNot(contains('test@example.com')));
  });

  test('rejestracja i logowanie w pamięci dalej działają', () async {
    expect(await AuthService.register('Jan@Budowa.pl', 'tajne-haslo'), isTrue);
    expect(await AuthService.register('jan@budowa.pl', 'inne'), isFalse);
    expect(await AuthService.authenticate('jan@budowa.pl', 'tajne-haslo'),
        isTrue);
    expect(await AuthService.authenticate('jan@budowa.pl', 'zle'), isFalse);
  });
}
