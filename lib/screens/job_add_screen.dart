// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/app_language.dart';
import '../models/job_listing.dart';
import '../services/jobs_service.dart';

// Form for adding a new job listing. Posting costs 49 PLN one-time via Stripe
// — there is no free tier (even Premium subscribers pay per posting). Flow:
//   1. User fills form → tap "Opłać 49 PLN i opublikuj"
//   2. Backend creates a DRAFT row + Stripe Checkout Session, returns URL
//   3. Client launches the URL in an external browser
//   4. Stripe webhook flips the draft to is_paid=1 and sets expires_at=+30d
//   5. JobsScreen picks the listing up on next refresh

const _kBg = Color(0xFF0F1117);
const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kAccent = Color(0xFFE57373); // matches the home "PRACA" tile colour
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);

class JobAddScreen extends StatefulWidget {
  /// Edit mode is signalled by passing an existing listing; null = create new.
  final JobListing? existing;
  const JobAddScreen({super.key, this.existing});

  @override
  State<JobAddScreen> createState() => _JobAddScreenState();
}

class _JobAddScreenState extends State<JobAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _requirementsCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;
  // Snapshot of field values at entry time — used by PopScope to detect that
  // the welder/fitter has typed something they would lose by backing out
  // (a 5-line job description retyped on a phone in gloves is misery).
  late final List<String> _initialSnapshot;
  // Cache for the 14 requirement-chip widgets. Tapping a chip calls setState
  // (line ~161) which rebuilds the form — without this cache we'd reallocate
  // 14 Tooltips + 14 ActionChips + 14 Text widgets and re-run context.tr 14
  // times on every chip tap. Invalidated on locale switch.
  List<Widget>? _chipCache;
  AppLanguage? _chipCacheLang;

  static const _commonReqs = [
    'TIG 141',
    'MMA 111',
    'MIG/MAG 135',
    'P-1 (CS)',
    'P-8 (SS)',
    'P-22 (P22)',
    '6G',
    '6GR',
    'NACE MR0175',
    'API 1104',
    'PED',
    'ISO 9606',
    // ASME B31.3 is the process-piping code referenced by virtually every
    // refinery / chemical-plant job spec — recruiters expect to see it on
    // both the listing and the welder's CV.
    'ASME B31.3',
    'WPS/WPQR',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _companyCtrl.text = e.company;
      _locationCtrl.text = e.location;
      _rateCtrl.text = e.rate ?? '';
      _descriptionCtrl.text = e.description;
      _requirementsCtrl.text = e.requirementsCsv;
      _emailCtrl.text = e.contactEmail ?? '';
      _phoneCtrl.text = e.contactPhone ?? '';
    }
    _initialSnapshot = _currentSnapshot();
  }

  List<String> _currentSnapshot() => [
        _titleCtrl.text,
        _companyCtrl.text,
        _locationCtrl.text,
        _rateCtrl.text,
        _descriptionCtrl.text,
        _requirementsCtrl.text,
        _emailCtrl.text,
        _phoneCtrl.text,
      ];

  bool get _isDirty {
    final now = _currentSnapshot();
    for (var i = 0; i < now.length; i++) {
      if (now[i] != _initialSnapshot[i]) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text(
          context.tr(pl: 'Porzucić zmiany?', en: 'Discard changes?'),
          style: const TextStyle(color: Color(0xFFE8ECF0)),
        ),
        content: Text(
          context.tr(
            pl: 'Wpisane dane ogłoszenia zostaną utracone.',
            en: 'The data you entered will be lost.',
          ),
          style: const TextStyle(color: _kTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(pl: 'Wróć do edycji', en: 'Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _kAccent),
            child: Text(context.tr(pl: 'Porzuć', en: 'Discard')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _companyCtrl.dispose();
    _locationCtrl.dispose();
    _rateCtrl.dispose();
    _descriptionCtrl.dispose();
    _requirementsCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _addRequirement(String tag) {
    final current = _requirementsCtrl.text.trim();
    if (current.isEmpty) {
      _requirementsCtrl.text = tag;
    } else {
      // Don't duplicate.
      final parts = current.split(',').map((s) => s.trim()).toList();
      if (parts.contains(tag)) return;
      _requirementsCtrl.text = '$current, $tag';
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    try {
      final session = await JobsService.instance.createCheckout(
        title: _titleCtrl.text.trim(),
        company: _companyCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        rate: _rateCtrl.text.trim().isEmpty ? null : _rateCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        requirementsCsv: _requirementsCtrl.text.trim(),
        contactEmail:
            _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        contactPhone:
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      );
      if (!mounted) return;
      final ok = await launchUrl(
        Uri.parse(session.checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
            pl: 'Nie udało się otworzyć przeglądarki.',
            en: 'Failed to open browser.',
          )),
        ));
        setState(() => _saving = false);
        return;
      }
      // Pop with `true` so the previous screen knows to refresh — the actual
      // listing won't be visible until Stripe webhook fires + user pulls to
      // refresh JobsScreen.
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('JobAddScreen.save error: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Nie udało się utworzyć płatności. Sprawdź połączenie.',
          en: 'Could not create the payment. Check your connection.',
        )),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: context.tr(pl: 'Ponów', en: 'Retry'),
          onPressed: _save,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return PopScope(
      canPop: !_isDirty || _saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (discard && mounted) nav.pop();
      },
      child: Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(
          isEdit
              ? context.tr(pl: 'Edytuj ogłoszenie', en: 'Edit listing')
              : context.tr(pl: 'Nowe ogłoszenie', en: 'New listing'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _SectionLabel(context.tr(pl: 'Stanowisko', en: 'Job')),
            const SizedBox(height: 8),
            _Field(
              label: context.tr(pl: 'Tytuł ogłoszenia *', en: 'Title *'),
              ctrl: _titleCtrl,
              hint: context.tr(
                pl: 'np. Spawacz TIG 141 — rurociągi SS',
                en: 'e.g. TIG 141 welder — SS piping',
              ),
              validator: _req,
            ),
            const SizedBox(height: 10),
            _Field(
              label: context.tr(pl: 'Firma *', en: 'Company *'),
              ctrl: _companyCtrl,
              validator: _req,
            ),
            const SizedBox(height: 10),
            _Field(
              label: context.tr(pl: 'Lokalizacja *', en: 'Location *'),
              ctrl: _locationCtrl,
              hint: context.tr(pl: 'Miasto / kraj', en: 'City / country'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            _Field(
              label: context.tr(pl: 'Stawka', en: 'Rate'),
              ctrl: _rateCtrl,
              hint: context.tr(pl: 'np. 150 PLN/h netto', en: 'e.g. 150 PLN/h net'),
            ),
            const SizedBox(height: 16),

            _SectionLabel(context.tr(pl: 'Wymagania', en: 'Requirements')),
            const SizedBox(height: 8),
            _Field(
              label: context.tr(pl: 'Kwalifikacje (csv)', en: 'Qualifications (csv)'),
              ctrl: _requirementsCtrl,
              hint: context.tr(
                pl: 'np. TIG 141, P-1, 6G, NACE',
                en: 'e.g. TIG 141, P-1, 6G, NACE',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.touch_app_outlined,
                    size: 13, color: _kTextMut),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Stuknij chip aby dodać do wymagań (bez duplikatów):',
                      en: 'Tap a chip to add it to requirements (no duplicates):',
                    ),
                    style: const TextStyle(fontSize: 11, color: _kTextMut),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _buildReqChips(context),
            ),
            const SizedBox(height: 16),

            _SectionLabel(context.tr(pl: 'Opis', en: 'Description')),
            const SizedBox(height: 8),
            _Field(
              label: context.tr(pl: 'Opis stanowiska *', en: 'Description *'),
              ctrl: _descriptionCtrl,
              maxLines: 5,
              hint: context.tr(
                pl: 'Zakres prac, obiekt, czas trwania zlecenia, zakwaterowanie…',
                en: 'Scope, site, contract length, accommodation…',
              ),
              validator: _req,
            ),
            const SizedBox(height: 16),

            _SectionLabel(context.tr(pl: 'Kontakt', en: 'Contact')),
            const SizedBox(height: 8),
            _Field(
              label: 'Email',
              ctrl: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            _Field(
              label: context.tr(pl: 'Telefon', en: 'Phone'),
              ctrl: _phoneCtrl,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            _SectionLabel(context.tr(pl: 'Płatność', en: 'Payment')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: _kAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(
                            pl: '49 PLN za 30 dni publikacji',
                            en: '49 PLN for 30 days listed',
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE8ECF0),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr(
                            pl: 'Stripe (karta, BLIK, Apple/Google Pay). Po opłaceniu pojawi się dla wszystkich.',
                            en: 'Stripe (card, BLIK, Apple/Google Pay). Goes live for everyone once paid.',
                          ),
                          style: const TextStyle(
                              fontSize: 11, color: _kTextMut, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.payments_outlined),
                label: Text(
                  _saving
                      ? context.tr(pl: 'Tworzę sesję…', en: 'Creating session…')
                      : context.tr(
                          pl: 'Opłać 49 PLN i opublikuj',
                          en: 'Pay 49 PLN and publish',
                        ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                pl: '* Pola wymagane. Ogłoszenie jest zapisywane lokalnie '
                    '(MVP). Synchronizacja między urządzeniami i płatne wyróżnienia '
                    'pojawią się w kolejnej aktualizacji.',
                en: '* Required fields. Listing is saved locally (MVP). '
                    'Cross-device sync and paid highlighting arrive in the next update.',
              ),
              style: const TextStyle(fontSize: 11, color: _kTextMut, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _buildReqChips(BuildContext context) {
    final lang = context.language;
    final cached = _chipCache;
    if (cached != null && _chipCacheLang == lang) return cached;
    final built = _commonReqs
        .map((tag) => Tooltip(
              message: context.tr(
                pl: 'Dodaj $tag do wymagań',
                en: 'Add $tag to requirements',
              ),
              child: ActionChip(
                label: Text(tag, style: const TextStyle(fontSize: 11)),
                onPressed: () => _addRequirement(tag),
                backgroundColor: _kCard,
                side: const BorderSide(color: _kBorder),
                visualDensity: VisualDensity.compact,
              ),
            ))
        .toList(growable: false);
    _chipCache = built;
    _chipCacheLang = lang;
    return built;
  }

  String? _req(String? v) {
    if (v == null || v.trim().isEmpty) {
      return context.tr(pl: 'Pole wymagane', en: 'Required');
    }
    return null;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: _kTextMut,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.label,
    required this.ctrl,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Color(0xFFE8ECF0)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSec, fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(color: _kTextMut, fontSize: 12),
        filled: true,
        fillColor: _kCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _kAccent, width: 1.2),
        ),
      ),
    );
  }
}
