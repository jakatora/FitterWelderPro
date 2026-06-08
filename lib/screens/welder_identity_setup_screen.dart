// P0-08 (audit 2026-06-08). Replaces the vestigial in-memory
// register_screen with a persistent welder identity setup flow that
// satisfies ISO 3834, EN ISO 9606 and ASME IX QW-301 documentation
// requirements (unique welder identifier on every joint).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../services/welder_identity.dart';

class WelderIdentitySetupScreen extends StatefulWidget {
  const WelderIdentitySetupScreen({super.key});

  @override
  State<WelderIdentitySetupScreen> createState() =>
      _WelderIdentitySetupScreenState();
}

class _WelderIdentitySetupScreenState
    extends State<WelderIdentitySetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _stampCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _wpqrNoCtrl = TextEditingController();

  DateTime? _wpqrExpiry;
  CertificationBody _certBody = CertificationBody.udt;
  bool _gdprConsent = false;
  bool _qualDeclared = false;
  bool _saving = false;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final existing = await WelderIdentityService.instance.get();
    if (!mounted || existing == null) return;
    setState(() {
      _stampCtrl.text = existing.stamp;
      _nameCtrl.text = existing.displayName ?? '';
      _emailCtrl.text = existing.email ?? '';
      _wpqrNoCtrl.text = existing.wpqrNo ?? '';
      _wpqrExpiry = existing.wpqrExpiry;
      _certBody = existing.certBody;
      // Consent + declaration timestamps already captured — pre-tick them
      // so the welder doesn't have to re-affirm a returning-user edit.
      _gdprConsent = true;
      _qualDeclared = true;
    });
  }

  @override
  void dispose() {
    _stampCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _wpqrNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickWpqrExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _wpqrExpiry ?? DateTime(now.year + 3, now.month, now.day),
      // EN ISO 9606 qualifications are typically valid for 3 years.
      // Allow back-dating in case the welder is recording an already-
      // expired cert; cap forward window at 6 y (TÜV/ASME extended).
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 6),
    );
    if (picked != null) {
      setState(() => _wpqrExpiry = picked);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_gdprConsent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'Aby zapisać tożsamość, musisz wyrazić zgodę RODO.',
          'You must consent to data processing to save your identity.',
        )),
      ));
      return;
    }
    if (!_qualDeclared) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'Potwierdź swoje kwalifikacje przed zapisem.',
          'Please confirm your qualifications before saving.',
        )),
      ));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = WelderIdentityService.instance.current;
    final identity = WelderIdentity(
      stamp: _stampCtrl.text.trim().toUpperCase(),
      wpqrNo: _wpqrNoCtrl.text.trim().isEmpty
          ? null
          : _wpqrNoCtrl.text.trim(),
      wpqrExpiry: _wpqrExpiry,
      certBody: _certBody,
      displayName: _nameCtrl.text.trim().isEmpty
          ? null
          : _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      // Preserve original consent/declaration timestamps for returning
      // users — re-saving an edit doesn't restart the audit clock.
      gdprConsentAt: existing?.gdprConsentAt ?? now,
      qualificationDeclaredAt: existing?.qualificationDeclaredAt ?? now,
    );
    final ok = await WelderIdentityService.instance.save(identity);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'Nie udało się zapisać tożsamości. Sprawdź pamięć urządzenia.',
          'Failed to save identity. Check device storage.',
        )),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_tr(
        'Tożsamość spawacza zapisana.',
        'Welder identity saved.',
      )),
    ));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Tożsamość spawacza', 'Welder identity')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Text(
              _tr(
                'Dane są zapisywane lokalnie na urządzeniu — używane do '
                    'identyfikacji spawacza na każdej spoinie w dzienniku '
                    '(ISO 3834 · EN ISO 9606 · ASME IX QW-301).',
                'Stored locally on this device — used to identify the '
                    'welder on every joint in the journal '
                    '(ISO 3834 · EN ISO 9606 · ASME IX QW-301).',
              ),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _stampCtrl,
              autofocus: true,
              maxLength: 12,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9a-z-]')),
              ],
              decoration: InputDecoration(
                labelText: _tr('Stempel (wymagane)', 'Stamp (required)'),
                helperText: _tr(
                  'Wielkie litery, cyfry, myślnik. 2–12 znaków. '
                      'np. JK-014, WP12.',
                  'Uppercase letters, digits, hyphen. 2–12 chars. '
                      'e.g. JK-014, WP12.',
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (raw) {
                final v = (raw ?? '').trim().toUpperCase();
                if (v.isEmpty) {
                  return _tr('Stempel jest wymagany.', 'Stamp is required.');
                }
                if (!kStampRegex.hasMatch(v)) {
                  return _tr(
                    'Nieprawidłowy format. Tylko A–Z, 0–9, "-". 2–12 znaków.',
                    'Invalid format. Only A–Z, 0–9, "-". 2–12 chars.',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              maxLength: 80,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
              ],
              decoration: InputDecoration(
                labelText:
                    _tr('Imię i nazwisko (opcjonalne)', 'Full name (optional)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              maxLength: 80,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\r\n\s]')),
              ],
              decoration: InputDecoration(
                labelText: _tr(
                  'E-mail (do faktury, opcjonalne)',
                  'Email (for invoices, optional)',
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (raw) {
                final v = (raw ?? '').trim();
                if (v.isEmpty) return null;
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                  return _tr('Nieprawidłowy e-mail.', 'Invalid email.');
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CertificationBody>(
              initialValue: _certBody,
              decoration: InputDecoration(
                labelText: _tr('Jednostka certyfikująca',
                    'Certification body'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in CertificationBody.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) =>
                  setState(() => _certBody = v ?? CertificationBody.other),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _wpqrNoCtrl,
              maxLength: 40,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
              ],
              decoration: InputDecoration(
                labelText: _tr(
                  'Nr WPQR / WPS (opcjonalnie)',
                  'WPQR / WPS no (optional)',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickWpqrExpiry,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _tr(
                    'Data ważności WPQR (opcjonalnie)',
                    'WPQR expiry (optional)',
                  ),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                  _wpqrExpiry == null
                      ? _tr('Nie ustawiono', 'Not set')
                      : '${_wpqrExpiry!.year}-'
                          '${_wpqrExpiry!.month.toString().padLeft(2, "0")}-'
                          '${_wpqrExpiry!.day.toString().padLeft(2, "0")}',
                ),
              ),
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              value: _gdprConsent,
              onChanged: (v) => setState(() => _gdprConsent = v ?? false),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                _tr(
                  'Wyrażam zgodę na przetwarzanie powyższych danych '
                      'lokalnie na urządzeniu w celach identyfikacji '
                      'spawacza w dzienniku spoin (GDPR / RODO Art. 6(1)(a)).',
                  'I consent to local processing of these data on this '
                      'device for the purpose of welder identification '
                      'in the joint log (GDPR Art. 6(1)(a)).',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            CheckboxListTile(
              value: _qualDeclared,
              onChanged: (v) => setState(() => _qualDeclared = v ?? false),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                _tr(
                  'Oświadczam, że posiadam kwalifikacje odpowiednie do '
                      'rejestrowanych w aplikacji spoin (PED 2014/68/EU '
                      'Aneks I 3.1.2).',
                  'I declare that I am qualified for the joints I will '
                      'document in this app (PED 2014/68/EU Annex I 3.1.2).',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                  _saving ? _tr('Zapisuję…', 'Saving…') : _tr('Zapisz', 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}
