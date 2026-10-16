/// „Moje stawki" i dane firmy do ofert — SharedPreferences
/// (`quote_settings_v1`).
///
/// Ustawienia są SZABLONEM nowej wyceny: przy tworzeniu wyceny stawki i ceny
/// kopiują się do niej (weld_quote.dart) i od tej chwili żyją w wycenie.
/// Zmiana tutaj nie przelicza ofert już wysłanych.
///
/// Uwaga: SharedPreferences nie wchodzą do kopii zapasowej (data_backup.dart),
/// ale same wyceny — z kopią stawek — wchodzą.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/quotes/hourly_rate.dart';
import '../domain/quotes/quote_process.dart';
import '../domain/quotes/weld_quote.dart';

/// Dane kalkulatora „Ile muszę brać za godzinę?" (`hourly_rate_v1`).
class HourlyRateStore {
  static const String key = 'hourly_rate_v1';

  const HourlyRateStore();

  Future<HourlyRateInput> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const HourlyRateInput();
    try {
      return HourlyRateInput.fromJson(jsonDecode(raw));
    } on FormatException {
      return const HourlyRateInput();
    }
  }

  Future<void> save(HourlyRateInput i) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(i.toJson()));
  }
}

/// Dane wystawcy oferty (nagłówek PDF).
class QuoteCompany {
  final String name;
  final String taxId;
  final String address;
  final String phone;
  final String email;

  /// Osoba wystawiająca / kontakt.
  final String person;

  const QuoteCompany({
    this.name = '',
    this.taxId = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.person = '',
  });

  bool get isEmpty => [name, taxId, address, phone, email, person]
      .every((s) => s.trim().isEmpty);

  QuoteCompany copyWith({
    String? name,
    String? taxId,
    String? address,
    String? phone,
    String? email,
    String? person,
  }) =>
      QuoteCompany(
        name: name ?? this.name,
        taxId: taxId ?? this.taxId,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        person: person ?? this.person,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'nip': taxId,
        'addr': address,
        'phone': phone,
        'email': email,
        'person': person,
      };

  static QuoteCompany fromJson(Object? raw) {
    if (raw is! Map) return const QuoteCompany();
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    return QuoteCompany(
      name: s('name'),
      taxId: s('nip'),
      address: s('addr'),
      phone: s('phone'),
      email: s('email'),
      person: s('person'),
    );
  }
}

class QuoteSettings {
  /// Stawki bazowe (robocizna, gazy, energia, narzut, zysk, VAT, NDT).
  /// Ceny spoiw są osobno, per materiał — [fillerPrices].
  final QuoteRates baseRates;

  /// Zapamiętane ceny spoiw per materiał (nadpisują [kDefaultFillerPrices]).
  final Map<QuoteMaterial, Map<QuoteProcess, double>> fillerPrices;

  final QuoteCompany company;
  final QuoteMaterial material;
  final WeldScheme scheme;
  final QuoteSite site;
  final int validityDays;

  /// Warunki na ofercie (płatność, termin realizacji, co nie wchodzi).
  final String terms;

  const QuoteSettings({
    this.baseRates = const QuoteRates(),
    this.fillerPrices = const {},
    this.company = const QuoteCompany(),
    this.material = QuoteMaterial.carbon,
    this.scheme =
        const WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mma),
    this.site = QuoteSite.shop,
    this.validityDays = 30,
    this.terms = '',
  });

  /// Stawki dla nowej wyceny z danego materiału.
  QuoteRates ratesFor(QuoteMaterial m) => QuoteRates.defaultsFor(m,
      base: baseRates, savedFillerPrices: fillerPrices[m]);

  QuoteSettings copyWith({
    QuoteRates? baseRates,
    Map<QuoteMaterial, Map<QuoteProcess, double>>? fillerPrices,
    QuoteCompany? company,
    QuoteMaterial? material,
    WeldScheme? scheme,
    QuoteSite? site,
    int? validityDays,
    String? terms,
  }) =>
      QuoteSettings(
        baseRates: baseRates ?? this.baseRates,
        fillerPrices: fillerPrices ?? this.fillerPrices,
        company: company ?? this.company,
        material: material ?? this.material,
        scheme: scheme ?? this.scheme,
        site: site ?? this.site,
        validityDays: validityDays ?? this.validityDays,
        terms: terms ?? this.terms,
      );

  /// Zapamiętuje ceny spoiw [prices] dla materiału [m].
  QuoteSettings withFillerPrices(
          QuoteMaterial m, Map<QuoteProcess, double> prices) =>
      copyWith(fillerPrices: {...fillerPrices, m: Map.of(prices)});

  Map<String, Object?> toJson() => {
        'rates': baseRates.copyWith(fillerPrices: const {}).toJson(),
        'filler': {
          for (final e in fillerPrices.entries)
            e.key.code: {for (final p in e.value.entries) p.key.code: p.value},
        },
        'company': company.toJson(),
        'material': material.code,
        'scheme': scheme.code,
        'site': site.code,
        'validity': validityDays,
        'terms': terms,
      };

  static QuoteSettings fromJson(Object? raw) {
    if (raw is! Map) return const QuoteSettings();
    final filler = <QuoteMaterial, Map<QuoteProcess, double>>{};
    final fr = raw['filler'];
    if (fr is Map) {
      for (final e in fr.entries) {
        final m =
            QuoteMaterial.values.where((x) => x.code == e.key).firstOrNull;
        if (m == null || e.value is! Map) continue;
        final prices = <QuoteProcess, double>{};
        for (final p in (e.value as Map).entries) {
          final proc = QuoteProcess.fromCode(p.key as String?);
          if (proc != null && p.value is num && (p.value as num).isFinite) {
            prices[proc] = (p.value as num).toDouble();
          }
        }
        filler[m] = prices;
      }
    }
    return QuoteSettings(
      baseRates: QuoteRates.fromJson(raw['rates']),
      fillerPrices: filler,
      company: QuoteCompany.fromJson(raw['company']),
      material: QuoteMaterial.fromCode(raw['material'] as String?),
      scheme: WeldScheme.fromCode(raw['scheme'] as String?) ??
          const WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mma),
      site: QuoteSite.fromCode(raw['site'] as String?),
      validityDays:
          raw['validity'] is num ? (raw['validity'] as num).toInt() : 30,
      terms: raw['terms'] is String ? raw['terms'] as String : '',
    );
  }
}

class QuoteSettingsStore {
  static const String key = 'quote_settings_v1';

  const QuoteSettingsStore();

  Future<QuoteSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const QuoteSettings();
    try {
      return QuoteSettings.fromJson(jsonDecode(raw));
    } on FormatException {
      return const QuoteSettings();
    }
  }

  Future<void> save(QuoteSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(s.toJson()));
  }
}
