import '../config/backend_config.dart';
import '../models/job_listing.dart';
import 'api_client.dart';
import 'premium_service.dart';

// Backend-backed job listings (49 PLN per posting via Stripe one-time).
// Flow per posting:
//   1. createCheckout(draft) → returns { listing_id, checkout_url }
//   2. Client launches checkout_url in external browser
//   3. After Stripe success, client polls listMine() until the new id appears
//      with isPaid = true (set by webhook)
//   4. Listing is then visible in listPublic() for everyone

class JobsService {
  JobsService._();
  static final JobsService instance = JobsService._();

  /// Public browse view (paid + non-expired).
  Future<List<JobListing>> listPublic({String? locationLike, int limit = 100}) async {
    if (!BackendConfig.stripeBackendLive) return const [];
    final q = <String, String>{'limit': '$limit'};
    if (locationLike != null && locationLike.isNotEmpty) {
      q['location'] = locationLike;
    }
    final body = await ApiClient.instance.getJson(
      BackendConfig.jobsList,
      query: q,
    );
    final raw = body['listings'] as List<dynamic>? ?? const [];
    return raw.map((j) => _fromBackendRow(j as Map<String, dynamic>)).toList();
  }

  /// Listings owned by this device — paid + draft (un-paid).
  Future<List<JobListing>> listMine() async {
    if (!BackendConfig.stripeBackendLive) return const [];
    await PremiumService.instance.init();
    final deviceId = PremiumService.instance.deviceId;
    final body = await ApiClient.instance.getJson(
      '${BackendConfig.jobsList}/mine',
      query: {'device_id': deviceId},
    );
    final raw = body['listings'] as List<dynamic>? ?? const [];
    return raw.map((j) => _fromBackendRow(j as Map<String, dynamic>)).toList();
  }

  /// Create a DRAFT listing + Stripe Checkout session. Returns the URL the
  /// client should open. The listing won't be public until the user pays
  /// and the webhook fires.
  Future<({String listingId, String checkoutUrl, String sessionId})>
      createCheckout({
    required String title,
    required String company,
    required String location,
    String? rate,
    required String description,
    String requirementsCsv = '',
    String? contactEmail,
    String? contactPhone,
  }) async {
    await PremiumService.instance.init();
    final deviceId = PremiumService.instance.deviceId;
    final body = <String, dynamic>{
      'device_id': deviceId,
      'title': title,
      'company': company,
      'location': location,
      'description': description,
      if (rate != null && rate.isNotEmpty) 'rate': rate,
      if (requirementsCsv.isNotEmpty) 'requirements_csv': requirementsCsv,
      if (contactEmail != null && contactEmail.isNotEmpty)
        'contact_email': contactEmail,
      if (contactPhone != null && contactPhone.isNotEmpty)
        'contact_phone': contactPhone,
    };
    final j = await ApiClient.instance.postJson(
      '${BackendConfig.jobsList}/checkout',
      body: body,
    );
    return (
      listingId: j['listing_id'] as String,
      checkoutUrl: j['checkout_url'] as String,
      sessionId: j['session_id'] as String,
    );
  }

  /// Backend → local model conversion. Backend returns ISO timestamps + DN
  /// fields named in snake_case; the [JobListing] model uses unix millis.
  JobListing _fromBackendRow(Map<String, dynamic> row) {
    int parseMs(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      final s = v.toString();
      return DateTime.tryParse(s)?.millisecondsSinceEpoch ?? 0;
    }
    return JobListing(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      company: row['company'] as String? ?? '',
      location: row['location'] as String? ?? '',
      rate: row['rate'] as String?,
      description: row['description'] as String? ?? '',
      requirementsCsv: row['requirements_csv'] as String? ?? '',
      contactEmail: row['contact_email'] as String?,
      contactPhone: row['contact_phone'] as String?,
      createdAt: parseMs(row['created_at']),
      expiresAt: row['expires_at'] == null ? null : parseMs(row['expires_at']),
      isPaid: (row['is_paid'] as int? ?? 0) == 1,
    );
  }
}
