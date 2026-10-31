// Persistent welder/fitter identity store.
//
// Built for P0-08 (audit 2026-06-08). ISO 3834, EN ISO 9606 and ASME IX
// QW-301 require a unique welder identifier on every joint. Before this
// the app stored users in an in-memory map (AuthService) that vanished
// on every restart — weld_journal "welder" field was free text typed by
// hand on each save, creating "ghost welder" entries no audit could
// reconcile.
//
// v1 persists to SharedPreferences. We deliberately don't introduce a
// new sqflite table yet — the data model is tiny (one row per device),
// SharedPreferences is already in the dependency graph, and we avoid a
// migration story for users who upgrade.
//
// All fields are nullable except `stamp` — only the stamp identifier is
// strictly required by the standards.
//
// v21 (2026-09): the welder's QUALIFICATIONS moved out of this object into
// the certificate register (`welder_certificates`, see
// lib/services/welder_qualification_service.dart) — many certificates, each
// with its standard (EN ISO 9606-1 / ASME IX WPQ), range and 6-month
// continuity. The old `wpqrNo` / `wpqrExpiry` / `certBody` fields were both
// too little (one number, one date) and mislabelled: a WPQR is the PROCEDURE
// qualification record (EN ISO 15614-1), not the welder's certificate. They
// stay here, read-only, so nothing a user typed is ever lost and the JSON
// keys stay compatible; the register migrates them once. The STAMP stays
// here — the weld journal reads `current?.stamp` as the default welder.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_record_owner.dart';
import 'account_service.dart';
import 'welder_qualification_service.dart';

/// Body that issued the welder's qualification certificate.
/// Codified set to keep the data clean; UI surfaces the human label and
/// stores the enum name for forward-compatible serialisation.
enum CertificationBody {
  tuv, // TÜV (DE/PL most common)
  udt, // Urząd Dozoru Technicznego (PL)
  lrs, // Lloyd's Register
  dnv, // DNV
  bv, // Bureau Veritas
  asme, // ASME (US)
  other,
}

extension CertificationBodyX on CertificationBody {
  String get label {
    switch (this) {
      case CertificationBody.tuv:
        return 'TÜV';
      case CertificationBody.udt:
        return 'UDT';
      case CertificationBody.lrs:
        return "Lloyd's Register";
      case CertificationBody.dnv:
        return 'DNV';
      case CertificationBody.bv:
        return 'Bureau Veritas';
      case CertificationBody.asme:
        return 'ASME';
      case CertificationBody.other:
        return 'Inne / Other';
    }
  }
}

class WelderIdentity {
  /// Welder stamp — uppercase short identifier punched into every joint.
  /// Regex `^[A-Z0-9-]{2,12}$` enforced at the setup screen. Required.
  final String stamp;

  /// LEGACY (before v21): the number typed into the old "WPQR / WPS no" field
  /// — in practice the welder's certificate number, sometimes a WPS number.
  /// Migrated once into the certificate register; no longer edited.
  final String? wpqrNo;

  /// LEGACY (before v21): the old single "WPQR expiry" date — really the
  /// welder certificate's expiry. Migrated once into the register.
  final DateTime? wpqrExpiry;

  /// LEGACY (before v21): body that issued the certificate. Migrated into the
  /// register as the examiner.
  final CertificationBody certBody;

  /// Display name (e.g. "Jan Kowalski"). Optional — stamp is enough.
  final String? displayName;

  /// Email (for VAT invoice + Stripe receipts). Optional.
  final String? email;

  /// Timestamp the user accepted GDPR / RODO data-processing notice.
  /// Required by Polish UODO + EU GDPR Art. 6(1)(a) consent records.
  final DateTime gdprConsentAt;

  /// Timestamp the user declared they are qualified for the work they
  /// will document in this app. PED 2014/68/EU Annex I 3.1.2 documented-
  /// personnel link.
  final DateTime qualificationDeclaredAt;

  const WelderIdentity({
    required this.stamp,
    this.wpqrNo,
    this.wpqrExpiry,
    this.certBody = CertificationBody.other,
    this.displayName,
    this.email,
    required this.gdprConsentAt,
    required this.qualificationDeclaredAt,
  });

  /// Returns true when the WPQR is present and has at least 30 days left.
  /// Surfaced as an amber chip in the editor so the welder gets a nudge
  /// to re-qualify BEFORE the audit fails.
  bool get wpqrExpiringSoon {
    if (wpqrExpiry == null) return false;
    final daysLeft = wpqrExpiry!.difference(DateTime.now()).inDays;
    return daysLeft >= 0 && daysLeft <= 30;
  }

  /// Already expired — UI shows a red chip; the welder may NOT be
  /// allowed by their employer to strike arc on coded work.
  bool get wpqrExpired {
    if (wpqrExpiry == null) return false;
    return wpqrExpiry!.isBefore(DateTime.now());
  }

  Map<String, Object?> toJson() => {
        'stamp': stamp,
        'wpqrNo': wpqrNo,
        'wpqrExpiry': wpqrExpiry?.toIso8601String(),
        'certBody': certBody.name,
        'displayName': displayName,
        'email': email,
        'gdprConsentAt': gdprConsentAt.toIso8601String(),
        'qualificationDeclaredAt': qualificationDeclaredAt.toIso8601String(),
      };

  static WelderIdentity? fromJson(Map<String, Object?> json) {
    final stamp = json['stamp'] as String?;
    final gdprStr = json['gdprConsentAt'] as String?;
    final qualStr = json['qualificationDeclaredAt'] as String?;
    if (stamp == null || stamp.isEmpty || gdprStr == null || qualStr == null) {
      return null;
    }
    final gdpr = DateTime.tryParse(gdprStr);
    final qual = DateTime.tryParse(qualStr);
    if (gdpr == null || qual == null) return null;
    final certName = json['certBody'] as String?;
    final cert = CertificationBody.values.firstWhere(
      (c) => c.name == certName,
      orElse: () => CertificationBody.other,
    );
    final wpqrExpStr = json['wpqrExpiry'] as String?;
    return WelderIdentity(
      stamp: stamp,
      wpqrNo: json['wpqrNo'] as String?,
      wpqrExpiry: wpqrExpStr == null ? null : DateTime.tryParse(wpqrExpStr),
      certBody: cert,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      gdprConsentAt: gdpr,
      qualificationDeclaredAt: qual,
    );
  }
}

/// Regex used to validate the stamp at the setup screen and in
/// auto-fill paths. Public so the UI can mirror it in `errorText` /
/// `helperText` and tests can pin it.
final RegExp kStampRegex = RegExp(r'^[A-Z0-9-]{2,12}$');

class WelderIdentityService {
  WelderIdentityService._();

  /// Fresh instance for tests (no state shared with [instance]).
  @visibleForTesting
  WelderIdentityService.forTesting();

  static final WelderIdentityService instance = WelderIdentityService._();

  static const _kPrefsKey = 'welder_identity_v1';

  /// Guest keeps the pre-account key (`welder_identity_v1`), so a device's
  /// identity from before accounts stays exactly where it was. Each account
  /// gets its own key — like the certificate register (schema32), a stamp
  /// never follows the user into another account.
  @visibleForTesting
  static String prefsKeyFor(LocalRecordOwner owner) =>
      owner.key == LocalRecordOwner.guest
          ? _kPrefsKey
          : '$_kPrefsKey.owner.${Uri.encodeComponent(owner.key)}';

  /// Identity of ONE captured owner; valid only while that session is current.
  _IdentitySnapshot? _snapshot;
  AccountService? _watched;
  bool _refreshing = false;

  final _changeController = StreamController<WelderIdentity?>.broadcast();

  /// Emits the new identity (or null when cleared or when the account
  /// changed and the new one has none). The weld_journal editor subscribes
  /// so any change instantly re-pre-fills the welder field.
  Stream<WelderIdentity?> get changes {
    _watchAccount();
    return _changeController.stream;
  }

  /// Identity of the current account (guest or signed in). Never throws:
  /// when the owner cannot be established (session changing, identity of
  /// a signed-in account not verified yet) it returns null — an empty
  /// welder field is safe, another person's stamp is not.
  Future<WelderIdentity?> get() async {
    _watchAccount();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final owner = await LocalRecordOwner.capture();
        final cached = _snapshot;
        if (cached != null &&
            cached.owner.isCurrent &&
            cached.owner.key == owner.key) {
          return cached.value;
        }
        final value = await _read(owner);
        if (!owner.isCurrent) continue; // account changed mid-read: retry
        _snapshot = _IdentitySnapshot(owner, value);
        return value;
      } on AccountException {
        return null;
      }
    }
    return null;
  }

  /// Sync access for hot paths (UI build). Null until [get] has resolved for
  /// the CURRENT session — after a sign-in/out it is null (and a refresh is
  /// scheduled, announced on [changes]) instead of the previous account's
  /// identity.
  WelderIdentity? get current {
    _watchAccount();
    final cached = _snapshot;
    if (cached == null || !cached.owner.isCurrent) {
      _scheduleRefresh();
      return null;
    }
    return cached.value;
  }

  Future<WelderIdentity?> _read(LocalRecordOwner owner) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKeyFor(owner));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return WelderIdentity.fromJson(decoded);
      }
      if (decoded is Map) {
        return WelderIdentity.fromJson(Map<String, Object?>.from(decoded));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _watchAccount() {
    final account = AccountService.instance;
    if (identical(account, _watched)) return;
    _watched?.removeListener(_onAccountChanged);
    _watched = account;
    account.addListener(_onAccountChanged);
  }

  void _onAccountChanged() {
    final cached = _snapshot;
    if (cached != null && cached.owner.isCurrent) return; // profile edit only
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    if (_refreshing) return;
    _refreshing = true;
    unawaited(Future<void>(() async {
      try {
        final value = await get();
        final cached = _snapshot;
        if (cached != null && cached.owner.isCurrent) {
          _changeController.add(value);
        }
      } finally {
        _refreshing = false;
      }
    }));
  }

  Future<void>? _writes;

  Future<bool> _serialForOwner(LocalRecordOwner? expectedOwner,
      Future<bool> Function(LocalRecordOwner owner) operation) {
    _watchAccount();
    // Capture at invocation, before waiting behind an earlier owner's write.
    final captured = (expectedOwner == null
            ? LocalRecordOwner.capture()
            : Future.value(expectedOwner))
        .then<LocalRecordOwner?>((owner) => owner,
            onError: (Object _, StackTrace __) => null);
    Future<bool> run() async {
      try {
        final owner = await captured;
        if (owner == null) return false;
        owner.requireCurrent();
        return await operation(owner);
      } catch (_) {
        return false;
      }
    }

    final previous = _writes;
    final pending = previous == null ? run() : previous.then((_) => run());
    final settled = pending.then<void>((_) {});
    _writes = settled;
    settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    });
    return pending;
  }

  /// Saves the identity of [expectedOwner] (the account the editor was
  /// opened for) or of the current account. Refused — `false`, nothing
  /// written — when that session is no longer current.
  Future<bool> save(WelderIdentity identity,
          {LocalRecordOwner? expectedOwner}) =>
      _serialForOwner(expectedOwner, (owner) => _saveNow(identity, owner));

  Future<bool> _saveNow(WelderIdentity identity, LocalRecordOwner owner) async {
    try {
      owner.requireCurrent();
      final prefs = await SharedPreferences.getInstance();
      owner.requireCurrent();
      final raw = jsonEncode(identity.toJson());
      final ok = await prefs.setString(prefsKeyFor(owner), raw);
      if (!ok) return false;
      await prefs.reload();
      if (prefs.getString(prefsKeyFor(owner)) != raw) return false;
      if (owner.isCurrent) {
        _snapshot = _IdentitySnapshot(owner, identity);
        _changeController.add(identity);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Delete my data": the identity AND the welder's certificate register
  /// (numbers, dates, scanned certificates, scheduled reminders) of ONE
  /// owner. Since v21 the certificate data lives in the register, and the
  /// profile's delete dialog promises to erase the qualification number and
  /// expiry — calling only the preferences half would silently break that
  /// promise.
  ///
  /// The owner is captured once, before any I/O; the register is cleared
  /// first (owner-bound transaction). If the session changed in between,
  /// nothing of the NEW account is touched and the identity is kept so the
  /// state is never half-deleted — returns false and the user can retry.
  Future<bool> clear({LocalRecordOwner? expectedOwner}) =>
      _serialForOwner(expectedOwner, _clearNow);

  Future<bool> _clearNow(LocalRecordOwner owner) async {
    if (!await WelderQualificationService.instance.clearAll(owner: owner)) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      owner.requireCurrent();
      if (!await prefs.remove(prefsKeyFor(owner))) return false;
      await prefs.reload();
      if (prefs.containsKey(prefsKeyFor(owner))) return false;
    } catch (_) {
      return false;
    }
    if (owner.isCurrent) {
      _snapshot = _IdentitySnapshot(owner, null);
      _changeController.add(null);
    }
    return true;
  }
}

class _IdentitySnapshot {
  _IdentitySnapshot(this.owner, this.value);
  final LocalRecordOwner owner;
  final WelderIdentity? value;
}
