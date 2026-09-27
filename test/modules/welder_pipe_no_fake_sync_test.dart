// Przegląd G7: „Dodaj do puli 100/100 (społeczność)” oznaczał wpisy jako
// wysłane bez żadnego żądania HTTP (community_sync_service.dart) — atrapa
// usunięta razem z martwym DeviceIdProvider. Zapis parametrów jest lokalny.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brak atrapy wysyłki do „puli 100/100”', () {
    expect(File('lib/modules/welder_pipe/community_sync_service.dart').existsSync(),
        isFalse);
    expect(File('lib/modules/welder_pipe/device_id.dart').existsSync(), isFalse);
    final screen = File(
            'lib/modules/welder_pipe/ui/welder_pipe_param_edit_screen.dart')
        .readAsStringSync();
    expect(screen, isNot(contains('Dodaj do puli')));
    expect(screen, isNot(contains('submitMyParamToCommunity')));
    final repo =
        File('lib/modules/welder_pipe/local_repo.dart').readAsStringSync();
    expect(repo, isNot(contains('markOutboxSent')));
  });
}
