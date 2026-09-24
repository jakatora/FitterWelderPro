// Ostrzeżenie o uprawnieniach spawacza — baner w menu SPAWACZ i w profilu.
//
// TERMINOLOGIA: plik nosi historyczną nazwę `wpqr_chip.dart`, bo importuje go
// profil (`WpqrChipLive`), ale treść jest poprawiona. WPQR to protokół
// kwalifikowania PROCEDURY (EN ISO 15614-1). Spawacz ma UPRAWNIENIE —
// certyfikat wg EN ISO 9606-1 albo WPQ wg ASME IX — i o nim jest ten baner.
//
// Źródło prawdy od v21: rejestr uprawnień (WelderQualificationService) —
// wiele certyfikatów, data ważności ORAZ termin 6-miesięczny (ISO 9606-1 §9.2
// potwierdzenie koordynatora / ASME IX QW-322.1 spawanie procesem). Baner
// pokazuje najpilniejszy problem i liczbę pozostałych; stuknięcie otwiera
// rejestr.
//
// Publiczne API zachowane dla profilu: `WpqrChipLive({padding})`. Klasa
// `WpqrChip(identity:)` i funkcje `wpqrWarningOf` / `wpqrDaysLeft` zostają dla
// zgodności (dawna tożsamość z jedną datą), z poprawioną terminologią.

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/qualification/certificate_status.dart';
import '../domain/qualification/qualification_dates.dart';
import '../features/qualification/certificate_register_page.dart';
import '../i18n/app_language.dart';
import '../services/welder_identity.dart';
import '../services/welder_qualification_service.dart';
import '../theme/app_theme.dart';

String _daysPl(int d) => d == 1 ? '1 dzień' : '$d dni';
String _daysEn(int d) => d == 1 ? '1 day' : '$d days';

/// Tekst ostrzeżenia dla jednego certyfikatu wymagającego uwagi. Czysta
/// funkcja — testowana bez widżetów.
String qualificationWarningText(
  CertificateEvaluation e, {
  required bool english,
}) {
  final title = e.certificate.shortTitle(english: english);
  final asme = e.rule == ContinuityRule.processUse;
  switch (e.state) {
    case QualificationState.valid:
      return '';
    case QualificationState.expired:
      final date = formatIsoDate(e.expiryDate!);
      return english
          ? 'Welder qualification expired $date ($title) — welds made now '
              'are not covered by it. Renew the qualification before your '
              'next shift.'
          : 'Uprawnienie spawacza wygasło $date ($title) — spoiny wykonane '
              'teraz nie są nim objęte. Odnów uprawnienie przed kolejną zmianą.';
    case QualificationState.lapsed:
      final date = formatIsoDate(e.continuityDeadline!);
      if (asme) {
        return english
            ? 'WPQ lapsed: no weld with this process for 6 months (deadline '
                '$date, ASME IX QW-322.1) — $title. Re-qualification needed.'
            : 'WPQ wygasło: brak spoiny tym procesem przez 6 miesięcy (termin '
                '$date, ASME IX QW-322.1) — $title. Potrzebna ponowna '
                'kwalifikacja.';
      }
      return english
          ? 'Welder qualification lapsed: no 6-month confirmation by $date '
              '(EN ISO 9606-1 §9.2) — $title.'
          : 'Uprawnienie spawacza przeterminowane: brak potwierdzenia '
              '6-miesięcznego do $date (EN ISO 9606-1 §9.2) — $title.';
    case QualificationState.expiringSoon:
      final date = formatIsoDate(e.expiryDate!);
      final days = e.daysToExpiry!;
      if (days <= 0) {
        return english
            ? 'Welder qualification expires today ($date) — $title. Book the '
                'renewal.'
            : 'Uprawnienie spawacza wygasa dziś ($date) — $title. Umów '
                'przedłużenie.';
      }
      return english
          ? 'Welder qualification expires in ${_daysEn(days)} ($date) — '
              '$title. Book the renewal.'
          : 'Uprawnienie spawacza wygasa za ${_daysPl(days)} ($date) — '
              '$title. Umów przedłużenie.';
    case QualificationState.confirmationDue:
      final date = formatIsoDate(e.continuityDeadline!);
      final days = e.daysToContinuityDeadline!;
      final whenPl = days <= 0 ? 'dziś' : 'za ${_daysPl(days)}';
      final whenEn = days <= 0 ? 'today' : 'in ${_daysEn(days)}';
      if (asme) {
        return english
            ? 'WPQ continuity ends $whenEn ($date) — $title. Weld with this '
                'process and log it in the journal.'
            : 'Ciągłość WPQ kończy się $whenPl ($date) — $title. Wykonaj '
                'spoinę tym procesem i zapisz ją w dzienniku.';
      }
      return english
          ? '6-month confirmation due $whenEn ($date) — $title. Ask the '
              'welding coordinator to sign it.'
          : 'Potwierdzenie 6-miesięczne $whenPl ($date) — $title. Poproś '
              'koordynatora spawania o podpis.';
  }
}

/// Baner o stanie rejestru uprawnień. Nic nie rysuje (i nie zajmuje
/// miejsca), gdy wszystko jest ważne albo rejestr pusty.
class QualificationBanner extends StatelessWidget {
  final QualificationOverview? overview;

  /// Margines stosowany TYLKO, gdy baner coś rysuje.
  final EdgeInsetsGeometry padding;

  /// Stuknięcie — zwykle otwiera rejestr uprawnień.
  final VoidCallback? onTap;

  const QualificationBanner({
    super.key,
    required this.overview,
    this.padding = EdgeInsets.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final urgent = overview?.needingAttention ?? const [];
    if (urgent.isEmpty) return const SizedBox.shrink();
    final first = urgent.first;
    final red = first.state.severity >= 2;
    final accent = red ? kFail : kWarn;
    final english = context.language == AppLanguage.en;
    var text = qualificationWarningText(first, english: english);
    final more = urgent.length - 1;
    if (more > 0) {
      text += english
          ? ' (+$more more — see register)'
          : ' (+$more w rejestrze)';
    }
    return Padding(
      padding: padding,
      child: Semantics(
        liveRegion: true,
        button: onTap != null,
        child: Material(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    red ? Icons.gpp_bad_outlined : Icons.warning_amber_rounded,
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 18, color: accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Baner podpięty do rejestru uprawnień — do menu SPAWACZ i profilu.
///
/// Przy wejściu przelicza rejestr (daty biegną, a dziennik mógł dostać nowe
/// spoiny), słucha zmian rejestru i tożsamości (np. „Usuń moje dane" chowa
/// baner od razu). Stuknięcie otwiera rejestr uprawnień.
class WpqrChipLive extends StatefulWidget {
  /// Margines stosowany tylko, gdy baner coś rysuje.
  final EdgeInsetsGeometry padding;

  const WpqrChipLive({super.key, this.padding = EdgeInsets.zero});

  @override
  State<WpqrChipLive> createState() => _WpqrChipLiveState();
}

class _WpqrChipLiveState extends State<WpqrChipLive> {
  StreamSubscription<WelderIdentity?>? _identitySub;

  @override
  void initState() {
    super.initState();
    unawaited(WelderQualificationService.instance.refresh());
    _identitySub = WelderIdentityService.instance.changes.listen((_) {
      unawaited(WelderQualificationService.instance.refresh());
    });
  }

  @override
  void dispose() {
    _identitySub?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CertificateRegisterPage()),
    );
    unawaited(WelderQualificationService.instance.refresh());
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<QualificationOverview?>(
        valueListenable: WelderQualificationService.instance.overview,
        builder: (context, overview, _) => QualificationBanner(
          overview: overview,
          padding: widget.padding,
          onTap: _open,
        ),
      );
}

// ─── Zgodność wstecz: dawna tożsamość z jedną datą ──────────────────────────

/// Stan ostrzeżenia dla dawnej tożsamości (jedna data ważności).
enum WpqrWarning { none, expiringSoon, expired }

/// Ostrzeżenie dla dawnej tożsamości. „Wygasło" sprawdzane PIERWSZE: w dniu
/// wygaśnięcia oba gettery modelu zwracają true (Duration obcina w stronę
/// zera), a bursztynowe „wygasa dziś" na martwym uprawnieniu to komunikat,
/// który pozwala zapalić łuk, którego zapalić nie wolno.
WpqrWarning wpqrWarningOf(WelderIdentity? identity) {
  if (identity == null) return WpqrWarning.none;
  if (identity.wpqrExpired) return WpqrWarning.expired;
  if (identity.wpqrExpiringSoon) return WpqrWarning.expiringSoon;
  return WpqrWarning.none;
}

/// Pełne dni do daty ważności dawnej tożsamości (ta sama arytmetyka co
/// getter modelu). 0 bez daty.
int wpqrDaysLeft(WelderIdentity identity, {DateTime? now}) {
  final expiry = identity.wpqrExpiry;
  if (expiry == null) return 0;
  return expiry.difference(now ?? DateTime.now()).inDays;
}

/// Baner dla dawnej tożsamości z jedną datą ważności. Nieużywany przez
/// aplikację od v21 (zastąpiony przez [WpqrChipLive] / [QualificationBanner])
/// — zostaje, żeby istniejące wywołania dalej się kompilowały.
class WpqrChip extends StatelessWidget {
  final WelderIdentity? identity;
  final EdgeInsetsGeometry padding;

  const WpqrChip({
    super.key,
    required this.identity,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final warning = wpqrWarningOf(identity);
    if (warning == WpqrWarning.none) return const SizedBox.shrink();
    final expiry = identity!.wpqrExpiry;
    if (expiry == null) return const SizedBox.shrink();
    final expired = warning == WpqrWarning.expired;
    final accent = expired ? kFail : kWarn;
    final date = formatIsoDate(expiry);
    final days = wpqrDaysLeft(identity!);
    final String label;
    if (expired) {
      label = context.tr(
        pl: 'Uprawnienie spawacza wygasło $date — spoiny wykonane teraz mogą '
            'zostać unieważnione. Odnów uprawnienie przed kolejną zmianą.',
        en: 'Welder qualification expired $date — welds made now may be '
            'rejected. Renew the qualification before your next shift.',
      );
    } else if (days <= 0) {
      label = context.tr(
        pl: 'Uprawnienie spawacza wygasa dziś ($date). Umów przedłużenie.',
        en: 'Welder qualification expires today ($date). Book the renewal.',
      );
    } else {
      label = context.tr(
        pl: 'Uprawnienie spawacza wygasa za ${_daysPl(days)} ($date). '
            'Umów przedłużenie.',
        en: 'Welder qualification expires in ${_daysEn(days)} ($date). '
            'Book the renewal.',
      );
    }
    return Padding(
      padding: padding,
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                expired ? Icons.gpp_bad_outlined : Icons.warning_amber_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
