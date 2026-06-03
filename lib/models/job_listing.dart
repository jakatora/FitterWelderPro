// Job listing for the "Praca" module. Used solely as the on-the-wire shape
// for the Railway backend (`/api/fitter/jobs`); we no longer ship any local
// SQLite copy. The class is kept because `JobsService` deserialises backend
// rows into it before the UI consumes them. The legacy `isPaid` / `toRow`
// helpers below are retained because backend payloads use the same flag.

class JobListing {
  final String id;
  final String title;
  final String company;
  final String location;
  final String? rate;          // "150 PLN/h", "30 zł/h netto", "umowa"
  final String description;
  /// Comma-separated requirement tags: e.g. "TIG 141, P-1, 6G, NACE".
  final String requirementsCsv;
  final String? contactEmail;
  final String? contactPhone;
  final int createdAt;         // unix millis
  final int? expiresAt;        // unix millis, null = no expiry
  /// `false` for free local listings (MVP), `true` once Stripe one-time
  /// payment is wired up in Phase 6b and the user paid for the boost.
  final bool isPaid;

  const JobListing({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.description,
    required this.requirementsCsv,
    required this.createdAt,
    this.rate,
    this.contactEmail,
    this.contactPhone,
    this.expiresAt,
    this.isPaid = false,
  });

  List<String> get requirements => requirementsCsv
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().millisecondsSinceEpoch > exp;
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'company': company,
        'location': location,
        'rate': rate,
        'description': description,
        'requirements_csv': requirementsCsv,
        'contact_email': contactEmail,
        'contact_phone': contactPhone,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'is_paid': isPaid ? 1 : 0,
      };

  static JobListing fromRow(Map<String, Object?> row) => JobListing(
        id: row['id'] as String,
        title: row['title'] as String,
        company: row['company'] as String,
        location: row['location'] as String,
        rate: row['rate'] as String?,
        description: row['description'] as String,
        requirementsCsv: (row['requirements_csv'] as String?) ?? '',
        contactEmail: row['contact_email'] as String?,
        contactPhone: row['contact_phone'] as String?,
        createdAt: row['created_at'] as int,
        expiresAt: row['expires_at'] as int?,
        isPaid: (row['is_paid'] as int? ?? 0) == 1,
      );
}
