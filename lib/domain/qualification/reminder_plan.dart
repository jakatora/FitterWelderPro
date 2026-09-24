// Plan lokalnych przypomnień o uprawnieniach — czysta funkcja.
//
// Które przypomnienia i kiedy — bez wołania platformy, żeby dało się to
// przetestować tabelarycznie. Warstwa wtyczki
// (lib/services/qualification_reminders.dart) tylko wykonuje ten plan.
//
// Zasady:
//  • dla każdego certyfikatu dwa terminy: data ważności i termin ciągłości
//    6-miesięcznej (ISO 9606-1 §9.2 / ASME IX QW-322.1(a));
//  • przypomnienia 30 i 7 dni przed każdym z nich, o 9:00 czasu lokalnego;
//  • tylko te, których pora jeszcze nie minęła — przypomnienie „30 dni
//    przed" dla terminu za 12 dni nie ma sensu; to, że termin jest blisko,
//    mówi baner w menu SPAWACZ;
//  • termin już po czasie — żadnych przypomnień (status czerwony na
//    banerze);
//  • iOS trzyma maksymalnie 64 zaplanowane powiadomienia na aplikację,
//    dlatego plan jest ucięty do [kMaxPlannedReminders] najbliższych.

import 'certificate_status.dart';
import 'qualification_dates.dart';

/// Ile dni przed terminem przypominamy.
const List<int> kReminderLeadDays = <int>[30, 7];

/// Godzina przypomnienia (czas lokalny).
const int kReminderHour = 9;

/// Limit zaplanowanych przypomnień (iOS: 64 na aplikację; zostawiamy zapas).
const int kMaxPlannedReminders = 48;

/// Którego terminu dotyczy przypomnienie.
enum ReminderKind { expiry, continuity }

class PlannedReminder {
  /// Stabilny identyfikator powiadomienia (31 bitów, dodatni) — ten sam dla
  /// tego samego certyfikatu, terminu i wyprzedzenia, więc ponowne
  /// planowanie nadpisuje, a nie dubluje.
  final int id;
  final DateTime fireAt;
  final String certificateId;
  final ReminderKind kind;
  final int daysBefore;
  final DateTime deadline;
  final String title;
  final String body;

  const PlannedReminder({
    required this.id,
    required this.fireAt,
    required this.certificateId,
    required this.kind,
    required this.daysBefore,
    required this.deadline,
    required this.title,
    required this.body,
  });

  @override
  String toString() =>
      'PlannedReminder(${kind.name} $certificateId -$daysBefore d @ $fireAt)';
}

/// FNV-1a 32 bit, obcięty do 31 bitów — identyfikator powiadomienia musi być
/// dodatnim int32 na Androidzie. Nie `String.hashCode`: ten nie jest stabilny
/// między uruchomieniami, a stary identyfikator trzeba umieć anulować.
int reminderId(String certificateId, ReminderKind kind, int daysBefore) {
  var hash = 0x811c9dc5;
  for (final unit in '$certificateId|${kind.name}|$daysBefore'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final id = hash & 0x7FFFFFFF;
  return id == 0 ? 1 : id;
}

String _daysPl(int d) => d == 1 ? '1 dzień' : '$d dni';
String _daysEn(int d) => d == 1 ? '1 day' : '$d days';

/// Plan przypomnień dla [evaluations], liczony w chwili [now].
List<PlannedReminder> planQualificationReminders(
  Iterable<CertificateEvaluation> evaluations, {
  required DateTime now,
  required bool english,
  List<int> leadDays = kReminderLeadDays,
  int hour = kReminderHour,
  int maxCount = kMaxPlannedReminders,
}) {
  final out = <PlannedReminder>[];
  final usedIds = <int>{};

  void add(CertificateEvaluation e, ReminderKind kind, DateTime deadline) {
    final title = e.certificate.shortTitle(english: english);
    for (final days in leadDays) {
      final day = DateTime(deadline.year, deadline.month, deadline.day - days);
      final fireAt = DateTime(day.year, day.month, day.day, hour);
      if (!fireAt.isAfter(now)) continue;
      var id = reminderId(e.certificate.id, kind, days);
      // Kolizja skrótu w obrębie jednego planu — przesuń do wolnego.
      while (usedIds.contains(id)) {
        id = id == 0x7FFFFFFF ? 1 : id + 1;
      }
      usedIds.add(id);
      final date = formatIsoDate(deadline);
      final String head;
      final String body;
      if (kind == ReminderKind.expiry) {
        head = english
            ? 'Welder qualification expires in ${_daysEn(days)}'
            : 'Uprawnienie spawacza wygasa za ${_daysPl(days)}';
        body = english
            ? '$title — valid until $date. Book the renewal.'
            : '$title — ważne do $date. Umów przedłużenie.';
      } else if (e.rule == ContinuityRule.processUse) {
        head = english
            ? 'Welder qualification: 6-month continuity in ${_daysEn(days)}'
            : 'Uprawnienie spawacza: ciągłość 6 mies. za ${_daysPl(days)}';
        body = english
            ? '$title — weld with this process by $date '
                '(ASME IX QW-322.1) or the WPQ lapses.'
            : '$title — spoina tym procesem do $date '
                '(ASME IX QW-322.1), inaczej WPQ wygaśnie.';
      } else {
        head = english
            ? 'Welder qualification: 6-month confirmation in ${_daysEn(days)}'
            : 'Uprawnienie spawacza: potwierdzenie 6 mies. za ${_daysPl(days)}';
        body = english
            ? '$title — the welding coordinator must confirm it by $date '
                '(EN ISO 9606-1 §9.2).'
            : '$title — koordynator spawania musi potwierdzić do $date '
                '(EN ISO 9606-1 §9.2).';
      }
      out.add(PlannedReminder(
        id: id,
        fireAt: fireAt,
        certificateId: e.certificate.id,
        kind: kind,
        daysBefore: days,
        deadline: deadline,
        title: head,
        body: body,
      ));
    }
  }

  final today = dateOnly(now);
  for (final e in evaluations) {
    final expiry = e.expiryDate;
    if (expiry != null && !dateOnly(expiry).isBefore(today)) {
      add(e, ReminderKind.expiry, dateOnly(expiry));
    }
    final deadline = e.continuityDeadline;
    if (deadline != null && !deadline.isBefore(today)) {
      // Termin ciągłości po dacie ważności nie ma znaczenia — uprawnienie i tak
      // wygaśnie wcześniej, a dwa powiadomienia o jednym problemie to szum.
      if (expiry == null || deadline.isBefore(dateOnly(expiry))) {
        add(e, ReminderKind.continuity, deadline);
      }
    }
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out.length > maxCount ? out.sublist(0, maxCount) : out;
}
