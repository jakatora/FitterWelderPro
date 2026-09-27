/// Spójność dokumentu odbiorowego spoiny — status, odbiór inspektora, NDT,
/// daty, PWHT i kupon próbny muszą mówić to samo.
///
/// Dawniej status OK i „Odbiór — inspektor / data” były niezależne od
/// wyników badań: dało się zapisać OK przy RT = NOK, odbiór przy spoinie
/// czekającej na badanie albo datę odbioru sprzed spawania. W PDF data booka
/// wyglądało to jak przyjęta spoina. Tu są reguły; edytor i dialog statusu
/// pokazują niespójność jako jawne ostrzeżenie („Popraw” / „Zapisz mimo to”),
/// a decyzja „mimo to” trafia do historii spoiny — tak jak ostrzeżenie WPS.
///
/// Czysty Dart: bez Fluttera i bez bazy.
library;

import 'coupon_entry.dart';
import 'weld_dates.dart';
import 'weld_entry.dart';
import 'weld_ndt.dart';

/// Stan kuponu podpiętego do spoiny, odczytany z logu kuponów.
enum CouponLinkState {
  /// Spoina nie jest powiązana z logiem (brak kuponu albo wolny tekst).
  none,
  ok,
  pending,
  nok,

  /// Kupon usunięty z logu (miękko, v25).
  deleted,

  /// W logu nie ma takiego kuponu (usunięty na twardo przed v25).
  missing,
}

/// Stan kuponu spoiny [e]; [coupon] — wiersz logu o `id == e.couponId`
/// (także usunięty) albo `null`, gdy go nie ma.
CouponLinkState couponLinkState(WeldEntry e, CouponEntry? coupon) {
  final id = e.couponId;
  if (id == null || id.isEmpty) return CouponLinkState.none;
  if (coupon == null) return CouponLinkState.missing;
  if (coupon.isDeleted) return CouponLinkState.deleted;
  if (coupon.isRejected) return CouponLinkState.nok;
  if (coupon.isOk) return CouponLinkState.ok;
  return CouponLinkState.pending;
}

/// Kupon wymaga uwagi (NOK, usunięty, nieistniejący).
bool couponLinkIsBad(CouponLinkState s) =>
    s == CouponLinkState.nok ||
    s == CouponLinkState.deleted ||
    s == CouponLinkState.missing;

/// Opis stanu kuponu do karty spoiny.
String couponLinkLabel(CouponLinkState s, {required bool en}) => switch (s) {
      CouponLinkState.none => '',
      CouponLinkState.ok =>
        en ? 'Coupon in the log: OK' : 'Kupon w logu: OK',
      CouponLinkState.pending => en
          ? 'Coupon in the log: not assessed yet'
          : 'Kupon w logu: jeszcze nieoceniony',
      CouponLinkState.nok =>
        en ? 'Coupon in the log: NOK' : 'Kupon w logu: NOK',
      CouponLinkState.deleted => en
          ? 'Coupon deleted from the log'
          : 'Kupon usunięty z logu kuponów',
      CouponLinkState.missing => en
          ? 'Coupon not found in the log'
          : 'Kuponu nie ma w logu kuponów',
    };

/// Jedna niespójność dokumentu.
class WeldConsistencyIssue {
  /// Stały kod (porównanie „nowa czy była już wcześniej”).
  final String code;
  final String pl;
  final String en;
  const WeldConsistencyIssue(this.code, this.pl, this.en);

  String text({required bool en}) => en ? this.en : pl;

  @override
  bool operator ==(Object other) =>
      other is WeldConsistencyIssue && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

String _methods(Iterable<NdtMethod> ms) => ms.map((m) => m.code).join(', ');

/// Niespójności spoiny [e]. [coupon] — kupon z logu (patrz
/// [couponLinkState]); [today] — do ostrzeżenia o dacie z przyszłości.
List<WeldConsistencyIssue> weldConsistencyIssues(
  WeldEntry e, {
  CouponEntry? coupon,
  bool couponKnown = false,
  DateTime? today,
}) {
  final out = <WeldConsistencyIssue>[];
  final statusOk = e.status == WeldStatus.ok;
  final acceptance =
      e.inspector.trim().isNotEmpty || e.inspectedAt.trim().isNotEmpty;
  final rejected = [
    for (final m in NdtMethod.values)
      if (e.ndtOf(m).isRejected) m,
  ];
  final awaiting = [
    for (final m in NdtMethod.values)
      if (e.ndtOf(m).isAwaiting) m,
  ];

  if (statusOk && rejected.isNotEmpty) {
    out.add(WeldConsistencyIssue(
      'ok-nok',
      'Status OK przy wyniku NDT NOK (${_methods(rejected)}).',
      'Status OK with an NDT result NOK (${_methods(rejected)}).',
    ));
  }
  if (statusOk && awaiting.isNotEmpty) {
    out.add(WeldConsistencyIssue(
      'ok-awaiting',
      'Status OK, a badanie ${_methods(awaiting)} nie ma jeszcze wyniku.',
      'Status OK while ${_methods(awaiting)} has no result yet.',
    ));
  }
  if (acceptance && !statusOk) {
    out.add(WeldConsistencyIssue(
      'accept-status',
      'Odbiór inspektora wpisany przy statusie ${e.status}.',
      'Inspector acceptance recorded with status ${e.status}.',
    ));
  }
  if (acceptance && rejected.isNotEmpty && statusOk == false) {
    out.add(WeldConsistencyIssue(
      'accept-nok',
      'Odbiór przy wyniku NDT NOK (${_methods(rejected)}).',
      'Acceptance with an NDT result NOK (${_methods(rejected)}).',
    ));
  }
  if (acceptance && awaiting.isNotEmpty && !statusOk) {
    out.add(WeldConsistencyIssue(
      'accept-awaiting',
      'Odbiór, a badanie ${_methods(awaiting)} nie ma jeszcze wyniku.',
      'Acceptance while ${_methods(awaiting)} has no result yet.',
    ));
  }

  final inspected = e.inspectedAt.trim();
  final welded = e.date.trim();
  if (isIsoWeldDate(inspected) &&
      isIsoWeldDate(welded) &&
      inspected.compareTo(welded) < 0) {
    out.add(WeldConsistencyIssue(
      'accept-before-weld',
      'Data odbioru $inspected jest wcześniejsza niż data spawania $welded.',
      'Acceptance date $inspected is before the weld date $welded.',
    ));
  }
  if (isIsoWeldDate(inspected)) {
    final later = [
      for (final m in NdtMethod.values)
        if (isIsoWeldDate(e.ndtOf(m).date) &&
            e.ndtOf(m).date.compareTo(inspected) > 0)
          m,
    ];
    if (later.isNotEmpty) {
      out.add(WeldConsistencyIssue(
        'accept-before-ndt',
        'Data odbioru $inspected jest wcześniejsza niż badanie '
            '${_methods(later)}.',
        'Acceptance date $inspected is before the ${_methods(later)} '
            'examination.',
      ));
    }
  }
  if (isFutureWeldDate(welded, today: today)) {
    out.add(WeldConsistencyIssue(
      'weld-future',
      'Data spawania $welded jest z przyszłości.',
      'Weld date $welded is in the future.',
    ));
  }
  if (e.pwhtRequired == true &&
      (statusOk || acceptance) &&
      e.pwhtChart.trim().isEmpty) {
    out.add(const WeldConsistencyIssue(
      'pwht-missing',
      'PWHT wymagane, a brak numeru wykresu PWHT.',
      'PWHT required but no PWHT chart number.',
    ));
  }

  if (couponKnown) {
    switch (couponLinkState(e, coupon)) {
      case CouponLinkState.nok:
        out.add(const WeldConsistencyIssue(
          'coupon-nok',
          'Spoina na kuponie próbnym NOK.',
          'The weld refers to a NOK test coupon.',
        ));
      case CouponLinkState.deleted:
        out.add(const WeldConsistencyIssue(
          'coupon-deleted',
          'Kupon próbny spoiny usunięto z logu kuponów.',
          'The weld\'s test coupon was deleted from the coupon log.',
        ));
      case CouponLinkState.missing:
        out.add(const WeldConsistencyIssue(
          'coupon-missing',
          'Kuponu próbnego spoiny nie ma w logu kuponów.',
          'The weld\'s test coupon is not in the coupon log.',
        ));
      case CouponLinkState.pending:
        if (statusOk) {
          out.add(const WeldConsistencyIssue(
            'coupon-pending',
            'Status OK, a kupon próbny jest jeszcze nieoceniony.',
            'Status OK while the test coupon is not assessed yet.',
          ));
        }
      case CouponLinkState.ok:
      case CouponLinkState.none:
        break;
    }
  }
  return out;
}

/// Niespójności [after], których nie było w [before] — o nie pytamy przy
/// zapisie (stara, znana niespójność nie wraca przy każdej edycji notatki).
List<WeldConsistencyIssue> newConsistencyIssues(
  List<WeldConsistencyIssue> before,
  List<WeldConsistencyIssue> after,
) =>
    [
      for (final i in after)
        if (!before.contains(i)) i,
    ];

/// Wpis do historii, gdy zapisano mimo niespójności.
String consistencyHistoryText(List<WeldConsistencyIssue> issues,
        {required bool en}) =>
    [
      en
          ? 'Saved despite document inconsistency:'
          : 'Zapisano mimo niespójności dokumentu:',
      for (final i in issues) '• ${i.text(en: en)}',
    ].join('\n');
