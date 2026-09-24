import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import 'api_client.dart';
import 'premium_service.dart';

// „Usuń moje dane" — część serwerowa (RODO art. 17, Google Play Data Safety).
//
// `DELETE /api/fitter/me` z nagłówkami X-Device-Id / X-Install-Secret usuwa z
// serwera: wiadomości z czatu, zgłoszenia (złożone i na nasze wiadomości),
// ogłoszenia, powiązanie sekretu instalacji i liczniki limitów. Musi pójść
// PRZED skasowaniem device_id i sekretu na telefonie — potem serwer nie ma już
// jak rozpoznać, czyje dane usunąć.
//
// Aplikacja ma działać ze starym backendem (bez tej trasy → 404) i z nowym.
// Stąd [ServerDeletionStatus.notSupported]: wtedy ekran kieruje do usunięcia
// mailowego zamiast udawać, że dane zniknęły.

enum ServerDeletionStatus {
  /// 200 — serwer usunął dane (liczby w [ServerDeletionResult.deleted]).
  deleted,

  /// Na telefonie nigdy nie zapisano device_id — nie ma czego szukać na
  /// serwerze. Żadne żądanie nie wyszło.
  nothingToDelete,

  /// 404 — stary backend bez `/api/fitter/me`. Dane z serwera usuwamy mailowo.
  notSupported,

  /// 429 — limit żądań usunięcia z tej sieci. Na telefonie niczego nie
  /// ruszamy, żeby dało się ponowić później.
  rateLimited,

  /// Brak sieci / timeout.
  offline,

  /// 401/400 `INSTALL_SECRET_*` — serwer nie uznał tej instalacji.
  rejected,

  /// 5xx i inne błędy.
  failed,
}

class ServerDeletionResult {
  final ServerDeletionStatus status;

  /// Liczniki z odpowiedzi serwera: `chat_messages`, `chat_reports`,
  /// `job_listings`, `device_secret`, `rate_counters`, `premium`.
  final Map<String, int> deleted;

  /// `true` — subskrypcja Premium jest jeszcze aktywna w Stripe i jej dane
  /// zostają na serwerze do jej zakończenia.
  final bool premiumRetained;

  /// Komunikat serwera (po polsku) — tylko pomocniczo, UI mówi własnym tekstem.
  final String? serverMessage;

  const ServerDeletionResult(
    this.status, {
    this.deleted = const {},
    this.premiumRetained = false,
    this.serverMessage,
  });

  bool get serverDataDeleted => status == ServerDeletionStatus.deleted;

  int count(String key) => deleted[key] ?? 0;
}

class ServerDataDeletion {
  ServerDataDeletion._();

  /// Woła `DELETE /api/fitter/me`. Nigdy nie rzuca — każdy wynik to
  /// [ServerDeletionResult], a surowy błąd idzie tylko do `debugPrint`.
  static Future<ServerDeletionResult> deleteMyServerData() async {
    if (!await PremiumService.instance.hasStoredDeviceId()) {
      return const ServerDeletionResult(ServerDeletionStatus.nothingToDelete);
    }
    try {
      final headers = await PremiumService.instance.authHeaders();
      final body = await ApiClient.instance.deleteJson(
        BackendConfig.me,
        headers: headers,
        timeout: const Duration(seconds: 15),
      );
      final raw = body['deleted'];
      final counts = <String, int>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is num) counts['$k'] = v.toInt();
        });
      }
      return ServerDeletionResult(
        ServerDeletionStatus.deleted,
        deleted: counts,
        premiumRetained: body['premium_retained'] == true,
        serverMessage: body['message'] as String?,
      );
    } on ApiException catch (e) {
      debugPrint('ServerDataDeletion: $e');
      if (e.statusCode == 404) {
        return const ServerDeletionResult(ServerDeletionStatus.notSupported);
      }
      if (e.statusCode == 429) {
        return const ServerDeletionResult(ServerDeletionStatus.rateLimited);
      }
      if (e.isInstallSecretError) {
        return const ServerDeletionResult(ServerDeletionStatus.rejected);
      }
      return const ServerDeletionResult(ServerDeletionStatus.failed);
    } on SocketException catch (e) {
      debugPrint('ServerDataDeletion offline: $e');
      return const ServerDeletionResult(ServerDeletionStatus.offline);
    } on TimeoutException catch (e) {
      debugPrint('ServerDataDeletion timeout: $e');
      return const ServerDeletionResult(ServerDeletionStatus.offline);
    } on http.ClientException catch (e) {
      debugPrint('ServerDataDeletion offline: $e');
      return const ServerDeletionResult(ServerDeletionStatus.offline);
    } catch (e) {
      debugPrint('ServerDataDeletion: $e');
      return const ServerDeletionResult(ServerDeletionStatus.failed);
    }
  }
}
