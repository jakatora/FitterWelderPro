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

import 'package:shared_preferences/shared_preferences.dart';

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
  static final WelderIdentityService instance = WelderIdentityService._();

  static const _kPrefsKey = 'welder_identity_v1';

  WelderIdentity? _cache;
  bool _hydrated = false;

  final _changeController = StreamController<WelderIdentity?>.broadcast();

  /// Emits the new identity (or null when cleared). The weld_journal
  /// editor subscribes so any change instantly re-pre-fills the welder
  /// field.
  Stream<WelderIdentity?> get changes => _changeController.stream;

  Future<WelderIdentity?> get() async {
    if (!_hydrated) {
      await _hydrate();
    }
    return _cache;
  }

  /// Sync access for hot paths (UI build) — returns null until [get] has
  /// been awaited at least once at app startup.
  WelderIdentity? get current => _cache;

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw == null || raw.isEmpty) {
        _cache = null;
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          _cache = WelderIdentity.fromJson(decoded);
        } else if (decoded is Map) {
          _cache = WelderIdentity.fromJson(Map<String, Object?>.from(decoded));
        } else {
          _cache = null;
        }
      }
    } catch (_) {
      _cache = null;
    } finally {
      _hydrated = true;
    }
  }

  Future<bool> save(WelderIdentity identity) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, jsonEncode(identity.toJson()));
      _cache = identity;
      _hydrated = true;
      _changeController.add(identity);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Delete my data": the identity AND the welder's certificate register
  /// (numbers, dates, scanned certificates, scheduled reminders). Since v21
  /// the certificate data lives in the register, and the profile's delete
  /// dialog promises to erase the qualification number and expiry — calling
  /// only the preferences half would silently break that promise.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefsKey);
    } catch (_) {
      // Even if the remove fails, drop the in-memory cache so the user
      // sees an empty form next time — they can re-save.
    }
    _cache = null;
    _hydrated = true;
    _changeController.add(null);
    // Never throws: a missing database must not block the rest of the wipe.
    await WelderQualificationService.instance.clearAll();
  }
}
