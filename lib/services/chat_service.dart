import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/backend_config.dart';
import '../config/feature_flags.dart';
import 'api_client.dart';
import 'account_service.dart';
import 'legal_consent.dart';
import 'premium_service.dart';
import 'user_profile.dart';

// Public chat for Fitter Welder Pro. Polls the Railway backend at
// /api/fitter/chat — no accounts; device_id + install secret identify the
// install (nagłówki X-Device-Id / X-Install-Secret), nickname signs messages.
// MVP keeps it simple: 4 hardcoded rooms (the same set the backend exposes),
// HTTP polling for new messages (8s while a room is open), POST to send.
//
// Podpis pod wiadomością bierzemy z profilu (imię i nazwisko) — patrz
// [getNickname]. Nie ma osobnej ksywki i nie zapisujemy jej w
// SharedPreferences: jedno źródło prawdy zamiast kopii, która rozjeżdża się
// po pierwszej zmianie nazwy.
//
// Tożsamość autora (nowy backend, 2026-09-24): cudze wiadomości przychodzą z
// `author_id` (nieodwracalny pseudonim) zamiast surowego device_id, a własne
// rozpoznajemy po polu `mine`. Stary backend tych pól nie zna — wtedy
// porównujemy device_id jak dotąd. Obie wersje działają z tym samym kodem.
//
// Blokowanie autorów jest lokalne — patrz services/blocked_users.dart.

class ChatRoom {
  final String id;
  final String namePl;
  final String nameEn;
  final String descPl;
  final String descEn;
  const ChatRoom({
    required this.id,
    required this.namePl,
    required this.nameEn,
    required this.descPl,
    required this.descEn,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> j) => ChatRoom(
        id: j['id'] as String,
        namePl: j['pl'] as String? ?? j['id'] as String,
        nameEn: j['en'] as String? ?? j['id'] as String,
        descPl: j['desc_pl'] as String? ?? '',
        descEn: j['desc_en'] as String? ?? '',
      );
}

class ChatMessage {
  final int id;
  final String room;

  /// Stary backend: surowy device_id autora. Nowy backend: dla cudzych
  /// wiadomości = [authorId], dla własnych = surowy device_id czytelnika.
  final String deviceId;

  /// Stabilny pseudonim autora (`a_` + 32 hex) — `null` na starym backendzie.
  final String? authorId;

  /// `true` = wiadomość czytelnika. `null`, gdy serwer tego pola nie odsyła
  /// (stary backend) — wtedy rozstrzyga porównanie device_id.
  final bool? mine;

  final String nickname;
  final Map<String, dynamic>? professionalProfile;
  final String text;
  final DateTime createdAt;
  final int flags;
  const ChatMessage({
    required this.id,
    required this.room,
    required this.deviceId,
    required this.nickname,
    required this.text,
    required this.createdAt,
    required this.flags,
    this.authorId,
    this.professionalProfile,
    this.mine,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final author = j['author_id'];
    final mine = j['mine'];
    return ChatMessage(
      id: j['id'] as int,
      room: j['room'] as String,
      deviceId: j['device_id'] as String,
      authorId: author is String && author.isNotEmpty ? author : null,
      mine: mine is bool ? mine : null,
      nickname: j['nickname'] as String,
      professionalProfile: j['professional_profile'] is Map
          ? Map<String, dynamic>.from(j['professional_profile'] as Map)
          : null,
      text: j['text'] as String,
      createdAt:
          DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      flags: j['flags'] as int? ?? 0,
    );
  }

  /// Klucz blokady: `author_id`, a na starym backendzie device_id.
  String get blockKey => authorId ?? deviceId;

  /// Czy to wiadomość czytelnika. Kolejność: pole `mine` od serwera,
  /// potem `author_id` z rejestracji, na końcu porównanie device_id (stary
  /// backend). Pusty [myDeviceId] nigdy nie pasuje — inaczej przed
  /// wczytaniem tożsamości wszystko wyglądałoby na własne.
  bool isMine({required String myDeviceId, String? myAuthorId}) {
    final fromServer = mine;
    if (fromServer != null) return fromServer;
    if (myAuthorId != null && authorId != null && authorId == myAuthorId) {
      return true;
    }
    return myDeviceId.isNotEmpty && deviceId == myDeviceId;
  }
}

/// Dlaczego zapis na czacie (wiadomość, zgłoszenie) się nie udał.
enum ChatFailure {
  accountRequired,

  /// 429 — limit wiadomości/zgłoszeń. Czekać, nie ponawiać od razu.
  rateLimited,

  /// 400/422 — treść odrzucona (link, niedozwolone słowo, zły format).
  rejected,

  /// 401/400 `INSTALL_SECRET_*` — serwer nie uznał tej instalacji.
  installSecret,

  /// Brak sieci / timeout.
  offline,

  /// 5xx i wszystko inne — warto ponowić.
  server,
}

/// Mapuje wyjątek z [ChatService] na [ChatFailure]. Surowy wyjątek zostaje
/// dla `debugPrint` — użytkownik dostaje tylko zrozumiały komunikat.
ChatFailure classifyChatError(Object error) {
  if (error is AccountException) return ChatFailure.accountRequired;
  if (error is ApiException) {
    if (error.isInstallSecretError) return ChatFailure.installSecret;
    if (error.statusCode == 429) return ChatFailure.rateLimited;
    if (error.statusCode == 400 || error.statusCode == 422) {
      return ChatFailure.rejected;
    }
    return ChatFailure.server;
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return ChatFailure.offline;
  }
  return ChatFailure.server;
}

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  void _requireChatSession(AccountService account, int revision) {
    if (!identical(account, AccountService.instance) ||
        account.sessionRevision != revision) {
      throw AccountException(
          'Sesja zmieniła się. Spróbuj ponownie. / Session changed. Please try again.');
    }
  }

  Future<Map<String, dynamic>> _accountError(
      Object error, AccountService account, int revision) async {
    _requireChatSession(account, revision);
    if (error is ApiException &&
        error.statusCode == 401 &&
        !error.isInstallSecretError) {
      await account.invalidateSession();
      throw AccountException(
          'Sesja wygasła. Zaloguj się ponownie / Session expired. Sign in again.');
    }
    throw error;
  }

  /// Default rooms used while the network call hasn't returned yet (e.g.
  /// first open). The backend returns the same set; we keep this list in
  /// sync so the UI has something to show offline.
  static const List<ChatRoom> _fallbackRooms = [
    ChatRoom(
      id: 'general',
      namePl: 'Ogólny',
      nameEn: 'General',
      descPl: 'Wszystko o robocie, pytania, śmieszki.',
      descEn: 'Anything goes — questions, banter, war stories.',
    ),
    ChatRoom(
      id: 'welding',
      namePl: 'Spawanie',
      nameEn: 'Welding',
      descPl: 'WPS-y, parametry, materiały, NDT, kalibracja.',
      descEn: 'WPS, parameters, materials, NDT, calibration.',
    ),
    ChatRoom(
      id: 'fitting',
      namePl: 'Montaż rurociągów',
      nameEn: 'Pipe fitting',
      descPl: 'Iso, prefabrykacja, montaż, supporty.',
      descEn: 'Isometric work, prefab, erection, supports.',
    ),
    ChatRoom(
      id: 'jobs',
      namePl: 'Praca / brygady',
      nameEn: 'Jobs / crews',
      // Bez „wymiany CV": czat jest publiczny, a polityka prosi, żeby nie
      // publikować telefonów ani adresów. Kontakt — prywatnymi kanałami.
      descPl: 'Szukam ekipy, szukam roboty. Kontakt ustalcie prywatnie — '
          'bez telefonów i adresów na czacie.',
      descEn: 'Looking for a crew or for work. Swap contact details '
          'privately — no phone numbers or addresses in chat.',
    ),
  ];

  /// Podpis pod wiadomością = imię i nazwisko z profilu.
  ///
  /// Świadomie NIE ma osobnej, dowolnie zmiennej ksywki. Pseudonim, który każdy
  /// może w sekundę przestawić na cudze nazwisko, w sieci zawodowej niszczy
  /// odpowiedzialność za słowo i pozwala podszyć się pod kolegę — a tu ludzie
  /// wymieniają się parametrami spawania i szukają brygad. Nazwę zmienia się
  /// w profilu i zmienia się wszędzie naraz.
  ///
  /// Nie zapisujemy jej osobno: jedno źródło prawdy zamiast kopii, która
  /// rozjeżdża się po pierwszej zmianie.
  Future<String> getNickname() async {
    final accountName =
        AccountService.instance.account?['displayName'] as String?;
    if (accountName != null && accountName.isNotEmpty) return accountName;
    final profile = await UserProfileService.instance.get();
    final full = profile?.fullName.trim() ?? '';
    if (full.length >= 2) {
      return full.length > 32 ? full.substring(0, 32) : full;
    }
    // Bramka przed czatem (widgets/community_gate.dart) wymusza imię i
    // nazwisko, więc tutaj trafiamy tylko po awarii odczytu profilu — wtedy
    // nie blokujemy czatu.
    await PremiumService.instance.init();
    final id = PremiumService.instance.deviceId;
    final suffix =
        id.length >= 4 ? id.substring(id.length - 4).toUpperCase() : 'XXXX';
    return 'Monter $suffix';
  }

  /// Fetch the canonical rooms list from the backend (with the fallback list
  /// returned immediately on first call so the UI doesn't flash empty).
  Future<List<ChatRoom>> listRooms() async {
    if (!BackendConfig.chatBackendLive) return _fallbackRooms;
    try {
      final body = await ApiClient.instance.getJson(
        BackendConfig.chatRooms,
        timeout: const Duration(seconds: 8),
      );
      final rooms = (body['rooms'] as List<dynamic>? ?? const [])
          .map((j) => ChatRoom.fromJson(j as Map<String, dynamic>))
          .toList();
      return rooms.isEmpty ? _fallbackRooms : rooms;
    } catch (_) {
      return _fallbackRooms;
    }
  }

  /// Fetch messages for [room]. If [sinceIso] is provided, returns only
  /// newer ones (used by the polling loop on the room screen). Without
  /// [sinceIso] returns the last 50 messages.
  Future<List<ChatMessage>> listMessages(String room,
      {String? sinceIso, int limit = 100}) async {
    if (!BackendConfig.chatBackendLive) return const [];
    final account = AccountService.instance;
    final revision = account.sessionRevision;
    await account.load();
    _requireChatSession(account, revision);
    // Nagłówki tożsamości: dzięki nim nowy backend odsyła `mine` i surowy
    // device_id przy NASZYCH wiadomościach. Do pokoju wchodzi się tylko przez
    // bramkę zgody (community_gate.dart), więc nic nie wychodzi przed zgodą.
    final headers = {
      ...await PremiumService.instance.authHeaders(),
      ...await account.headers()
    };
    _requireChatSession(account, revision);
    final body = await ApiClient.instance
        .getJson(
          BackendConfig.chatMessages,
          query: {
            'room': room,
            'limit': '${math.min(limit, 200)}',
            if (sinceIso != null) 'since': sinceIso,
          },
          headers: headers,
          timeout: const Duration(seconds: 8),
        )
        .catchError((Object error) => _accountError(error, account, revision));
    _requireChatSession(account, revision);
    final raw = body['messages'] as List<dynamic>? ?? const [];
    return raw
        .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Nowy klucz idempotencji (UUID v4) — jeden na wiadomość albo zgłoszenie.
  static String newIdempotencyKey() => const Uuid().v4();

  /// Wysyła wiadomość. [idempotencyKey] identyfikuje TĘ wiadomość: ApiClient
  /// ponawia po timeoucie z tym samym kluczem, a ekran przy „Ponów" podaje
  /// klucz nieudanej próby — serwer (deduplikacja 24 h per urządzenie) nie
  /// zapisze jej drugi raz, nawet gdy pierwsza próba jednak doszła.
  Future<ChatMessage> postMessage({
    required String room,
    required String text,
    String? idempotencyKey,
  }) async {
    final account = AccountService.instance;
    final revision = account.sessionRevision;
    await account.load();
    _requireChatSession(account, revision);
    if (account.account == null) {
      throw AccountException(
          'Zaloguj się w Profil → Konto / Sign in under Profile → Account');
    }
    final fullName = account.account!['displayName'] as String;
    final nick = fullName.length > 32 ? fullName.substring(0, 32) : fullName;
    final headers = {
      ...await PremiumService.instance.authHeaders(),
      ...await account.headers()
    };
    _requireChatSession(account, revision);
    final deviceId = PremiumService.instance.deviceId;
    _requireChatSession(account, revision);
    final body = await ApiClient.instance
        .postJson(
          BackendConfig.chatMessages,
          body: {
            'room': room,
            'device_id': deviceId,
            'nickname': nick,
            'text': text,
          },
          headers: {
            ...headers,
            kIdempotencyKeyHeader: idempotencyKey ?? newIdempotencyKey(),
          },
          timeout: const Duration(seconds: 8),
        )
        .catchError((Object error) => _accountError(error, account, revision));
    _requireChatSession(account, revision);
    return ChatMessage.fromJson(body['message'] as Map<String, dynamic>);
  }

  /// Zgłasza wiadomość do moderacji. Rzuca przy niepowodzeniu — ekran mówi
  /// wtedy, że zgłoszenie nie doszło (wcześniej błąd był połykany, a monter
  /// widział „Zgłoszono." także wtedy, gdy nic nie dotarło na serwer).
  Future<void> report(int messageId) async {
    if (!BackendConfig.chatBackendLive) return;
    final account = AccountService.instance;
    final revision = account.sessionRevision;
    await account.load();
    _requireChatSession(account, revision);
    final headers = {
      ...await PremiumService.instance.authHeaders(),
      ...await account.headers()
    };
    _requireChatSession(account, revision);
    final deviceId = PremiumService.instance.deviceId;
    await ApiClient.instance
        .postJson(
          BackendConfig.chatReport,
          body: {'id': messageId, 'device_id': deviceId},
          headers: {...headers, kIdempotencyKeyHeader: newIdempotencyKey()},
          timeout: const Duration(seconds: 8),
        )
        .catchError((Object error) => _accountError(error, account, revision));
    _requireChatSession(account, revision);
  }

  /// Rejestruje sekret instalacji na serwerze — ale TYLKO wtedy, gdy monter
  /// ma profil i zaakceptował bieżące zasady czatu. Bez zgody nic nie wychodzi
  /// z telefonu. Wołane przy starcie aplikacji (main.dart) i przy wejściu na
  /// czat (ChatScreen). Zwraca `null`, gdy nic nie wysłano. Nigdy nie rzuca.
  Future<DeviceRegistration?> registerDeviceIfConsented() async {
    if (!kCommunityEnabled || !BackendConfig.chatBackendLive) return null;
    try {
      final profile = await UserProfileService.instance.get();
      await LegalConsent.instance.load();
      if (profile == null || !LegalConsent.instance.isAccepted) return null;
      final result = await PremiumService.instance.registerDevice(
        canRegister: () =>
            UserProfileService.instance.hasProfile &&
            LegalConsent.instance.isAccepted,
      );
      return result == DeviceRegistration.cancelled ? null : result;
    } catch (e) {
      // registerDevice sam nie rzuca; to łapie awarię odczytu profilu/zgody.
      return null;
    }
  }
}
