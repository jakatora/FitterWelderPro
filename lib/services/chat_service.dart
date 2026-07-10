import 'dart:math' as math;


import '../config/backend_config.dart';
import 'api_client.dart';
import 'premium_service.dart';
import 'user_profile.dart';

// Public chat for Fitter Welder Pro. Polls the Railway backend at
// /api/fitter/chat — no auth, device_id + nickname identify the user.
// MVP keeps it simple: 4 hardcoded rooms (the same set the backend exposes),
// HTTP polling for new messages (8s while a room is open), POST to send.
//
// Podpis pod wiadomością bierzemy z profilu (imię i nazwisko) — patrz
// [getNickname]. Nie ma osobnej ksywki i nie zapisujemy jej w
// SharedPreferences: jedno źródło prawdy zamiast kopii, która rozjeżdża się
// po pierwszej zmianie nazwy.
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
  final String deviceId;
  final String nickname;
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
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as int,
        room: j['room'] as String,
        deviceId: j['device_id'] as String,
        nickname: j['nickname'] as String,
        text: j['text'] as String,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
        flags: j['flags'] as int? ?? 0,
      );
}

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

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
      descPl: 'Szukam ekipy, szukam roboty, wymiana CV.',
      descEn: 'Looking for crew, looking for work, CV swaps.',
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
    final profile = await UserProfileService.instance.get();
    final full = profile?.fullName.trim() ?? '';
    if (full.length >= 2) {
      return full.length > 32 ? full.substring(0, 32) : full;
    }
    // Profil jest wymuszony przy pierwszym uruchomieniu, więc tutaj trafiamy
    // tylko po awarii odczytu — wtedy nie blokujemy czatu.
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
    final body = await ApiClient.instance.getJson(
      BackendConfig.chatMessages,
      query: {
        'room': room,
        'limit': '${math.min(limit, 200)}',
        if (sinceIso != null) 'since': sinceIso,
      },
      timeout: const Duration(seconds: 8),
    );
    final raw = body['messages'] as List<dynamic>? ?? const [];
    return raw
        .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> postMessage({
    required String room,
    required String text,
  }) async {
    final nick = await getNickname();
    await PremiumService.instance.init();
    final deviceId = PremiumService.instance.deviceId;
    final body = await ApiClient.instance.postJson(
      BackendConfig.chatMessages,
      body: {
        'room': room,
        'device_id': deviceId,
        'nickname': nick,
        'text': text,
      },
      timeout: const Duration(seconds: 8),
    );
    return ChatMessage.fromJson(body['message'] as Map<String, dynamic>);
  }

  Future<void> report(int messageId) async {
    if (!BackendConfig.chatBackendLive) return;
    await PremiumService.instance.init();
    final deviceId = PremiumService.instance.deviceId;
    // Fire-and-forget; report failure is non-actionable for the user. We
    // swallow exceptions instead of bubbling them up.
    try {
      await ApiClient.instance.postJson(
        BackendConfig.chatReport,
        body: {'id': messageId, 'device_id': deviceId},
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}
  }
}
