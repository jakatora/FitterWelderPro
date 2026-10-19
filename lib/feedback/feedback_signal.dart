// Sygnał feedbacku — jeden element partii `POST /api/fitter/feedback`.
//
// Kontrakt z backendem (wersja 1, wzorzec: test/fixtures/feedback_signal_v1.json,
// ta sama kopia w backend/test/fixtures/):
//   body {"version": 1, "items": [<sygnał>, ...]}, partia ≤ 20;
//   sygnał: id, kind, text (≤ 500, po maskowaniu; pusty dla `error`),
//   tool i skill (≤ 64 albo null), skillsVersion, app, platform
//   (android|ios|windows|web|other), lang (pl|en), at (ISO 8601 UTC, ms),
//   errorType (albo null).
//
// Sygnał NIE niesie identyfikatora urządzenia czatu ani niczego o osobie —
// instalację wskazuje wyłącznie nagłówek `X-Feedback-Id` (feedback_consent.dart).

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/app_version.dart';
import '../i18n/app_language.dart';
import 'redact.dart';

/// Wersja ciała żądania `POST /api/fitter/feedback`.
const int kFeedbackPayloadVersion = 1;

/// Maksymalna długość tekstu sygnału (po maskowaniu).
const int kFeedbackTextMax = 500;

/// Maksymalna długość `tool` i `skill`.
const int kFeedbackTagMax = 64;

/// Maksymalna długość `errorType`.
const int kFeedbackErrorTypeMax = 80;

/// Maksymalna liczba sygnałów w jednej partii.
const int kFeedbackBatchMax = 20;

const int _kAppMax = 32;
const int _kIdMax = 64;

const Set<String> kFeedbackPlatforms = {
  'android',
  'ios',
  'windows',
  'web',
  'other',
};

const Set<String> kFeedbackLangs = {'pl', 'en'};

/// Rodzaj sygnału. Nazwy wartości są nazwami w JSON (`kind`).
enum FeedbackKind {
  /// Użytkownik sam zgłosił problem („zgłoś problem …”, przycisk).
  explicit,

  /// Narzekanie wykryte w wypowiedzi (z odniesieniem do aplikacji albo po
  /// nieudanej turze).
  complaint,

  /// „Gdzie jest…”, „nie mogę znaleźć…”.
  cantFind,

  /// Polecenie nierozpoznane (dwa razy z rzędu = jeden sygnał, liczy 5.1b).
  notUnderstood,

  /// Błąd aplikacji — tylko typ błędu i moduł, bez treści.
  error;

  static FeedbackKind? parse(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// Platforma w nazewnictwie kontraktu.
String feedbackPlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.windows => 'windows',
    _ => 'other',
  };
}

@immutable
class FeedbackSignal {
  const FeedbackSignal({
    required this.id,
    required this.kind,
    required this.text,
    required this.tool,
    required this.skill,
    required this.skillsVersion,
    required this.app,
    required this.platform,
    required this.lang,
    required this.at,
    required this.errorType,
  });

  /// Nowy sygnał z bieżącego stanu aplikacji.
  ///
  /// - tekst przechodzi przez [prepareFeedbackText] (maskowanie telefonów,
  ///   e-maili i długich ciągów cyfr, przycięcie do 500 znaków);
  /// - dla [FeedbackKind.error] tekst jest zawsze pusty, dla pozostałych
  ///   rodzajów MUSI być niepusty (inaczej [contractViolation] = 'text'
  ///   i kolejka go nie przyjmie);
  /// - `tool`, `skill`, `errorType` puste → null, za długie (64 / 64 / 80)
  ///   → przycięte;
  /// - czas w UTC z dokładnością do milisekund.
  factory FeedbackSignal.create({
    required FeedbackKind kind,
    String text = '',
    String? tool,
    String? skill,
    String? errorType,
    int skillsVersion = 1,
    AppLanguage? lang,
    DateTime? at,
    String? id,
    String? platform,
    String? app,
  }) {
    final when = (at ?? DateTime.now()).toUtc();
    return FeedbackSignal(
      id: id ?? const Uuid().v4(),
      kind: kind,
      text: kind == FeedbackKind.error ? '' : prepareFeedbackText(text),
      tool: _tag(tool),
      skill: _tag(skill),
      skillsVersion: skillsVersion,
      app: app ?? kAppVersion,
      platform: platform ?? feedbackPlatform(),
      lang: (lang ?? AppLanguageController.current).name,
      at: DateTime.fromMillisecondsSinceEpoch(when.millisecondsSinceEpoch,
          isUtc: true),
      errorType: _tag(errorType, kFeedbackErrorTypeMax),
    );
  }

  /// Odczyt z JSON (kolejka lokalna, fixture). Sprawdza tylko STRUKTURĘ
  /// (typy pól, znany `kind`, czytelna data) i rzuca [FormatException], gdy
  /// się nie zgadza. Reguły serwera (długości, listy wartości, pusty tekst)
  /// sprawdza [contractViolation] — element strukturalnie poprawny, ale
  /// niezgodny z kontraktem (np. zapisany przez starszą wersję przy luźniejszych
  /// regułach) zostaje w kolejce, a uploader odsiewa go przed wysyłką.
  factory FeedbackSignal.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final kind = FeedbackKind.parse(json['kind']);
    final text = json['text'];
    final tool = json['tool'];
    final skill = json['skill'];
    final skillsVersion = json['skillsVersion'];
    final app = json['app'];
    final platform = json['platform'];
    final lang = json['lang'];
    final at = json['at'];
    final errorType = json['errorType'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('feedback: id');
    }
    if (kind == null) throw const FormatException('feedback: kind');
    if (text is! String) throw const FormatException('feedback: text');
    if (tool is! String?) throw const FormatException('feedback: tool');
    if (skill is! String?) throw const FormatException('feedback: skill');
    if (skillsVersion is! int) {
      throw const FormatException('feedback: skillsVersion');
    }
    if (app is! String) throw const FormatException('feedback: app');
    if (platform is! String) throw const FormatException('feedback: platform');
    if (lang is! String) throw const FormatException('feedback: lang');
    final parsedAt = at is String ? DateTime.tryParse(at) : null;
    if (parsedAt == null) throw const FormatException('feedback: at');
    if (errorType is! String?) {
      throw const FormatException('feedback: errorType');
    }

    return FeedbackSignal(
      id: id,
      kind: kind,
      text: text,
      tool: tool,
      skill: skill,
      skillsVersion: skillsVersion,
      app: app,
      platform: platform,
      lang: lang,
      at: parsedAt.toUtc(),
      errorType: errorType,
    );
  }

  final String id;
  final FeedbackKind kind;
  final String text;
  final String? tool;
  final String? skill;
  final int skillsVersion;
  final String app;
  final String platform;
  final String lang;
  final DateTime at;
  final String? errorType;

  /// Jawne zgłoszenie nigdy nie wypada z kolejki przy przepełnieniu.
  bool get isExplicit => kind == FeedbackKind.explicit;

  /// Kopia z tekstem zamaskowanym i przyciętym jak w [FeedbackSignal.create]
  /// (pusty dla `error`) i oczyszczonymi tagami. Kolejka woła to przy każdym
  /// `add`, więc nawet sygnał zbudowany konstruktorem nie zapisze telefonu.
  FeedbackSignal sanitized() => FeedbackSignal(
        id: id,
        kind: kind,
        text: kind == FeedbackKind.error ? '' : prepareFeedbackText(text),
        tool: _tag(tool),
        skill: _tag(skill),
        skillsVersion: skillsVersion,
        app: app,
        platform: platform,
        lang: lang,
        at: at,
        errorType: _tag(errorType, kFeedbackErrorTypeMax),
      );

  /// Pierwsze pole niezgodne z regułami serwera albo null (można wysłać).
  ///
  /// Serwer odrzuca CAŁĄ partię (400), gdy choć jeden element jest zły,
  /// dlatego kolejka nie przyjmuje takich elementów, a uploader odsiewa je
  /// przed wysyłką (licznik `rejected`).
  String? get contractViolation {
    if (id.isEmpty || id.length > _kIdMax) return 'id';
    if (text.length > kFeedbackTextMax) return 'text';
    if (kind == FeedbackKind.error ? text.isNotEmpty : text.trim().isEmpty) {
      return 'text';
    }
    if (!_validTag(tool, kFeedbackTagMax)) return 'tool';
    if (!_validTag(skill, kFeedbackTagMax)) return 'skill';
    if (skillsVersion < 0) return 'skillsVersion';
    if (app.isEmpty || app.length > _kAppMax) return 'app';
    if (!kFeedbackPlatforms.contains(platform)) return 'platform';
    if (!kFeedbackLangs.contains(lang)) return 'lang';
    if (!_validTag(errorType, kFeedbackErrorTypeMax)) return 'errorType';
    return null;
  }

  /// Zgodny z kontraktem — może iść na serwer.
  bool get isValidForUpload => contractViolation == null;

  /// Klucze i kolejność dokładnie jak w kontrakcie.
  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'text': text,
        'tool': tool,
        'skill': skill,
        'skillsVersion': skillsVersion,
        'app': app,
        'platform': platform,
        'lang': lang,
        'at': at.toUtc().toIso8601String(),
        'errorType': errorType,
      };

  @override
  bool operator ==(Object other) =>
      other is FeedbackSignal &&
      other.id == id &&
      other.kind == kind &&
      other.text == text &&
      other.tool == tool &&
      other.skill == skill &&
      other.skillsVersion == skillsVersion &&
      other.app == app &&
      other.platform == platform &&
      other.lang == lang &&
      other.at == at &&
      other.errorType == errorType;

  @override
  int get hashCode => Object.hash(id, kind, text, tool, skill, skillsVersion,
      app, platform, lang, at, errorType);

  @override
  String toString() => 'FeedbackSignal(${kind.name}, $id)';
}

/// Ciało żądania dla partii (bez kontroli długości — pilnuje jej uploader).
Map<String, Object?> feedbackPayload(List<FeedbackSignal> items) => {
      'version': kFeedbackPayloadVersion,
      'items': [for (final s in items) s.toJson()],
    };

String? _tag(String? raw, [int max = kFeedbackTagMax]) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  return truncateUtf16(t, max);
}

bool _validTag(String? v, int max) =>
    v == null || (v.isNotEmpty && v.length <= max);
