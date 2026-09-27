import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/feature_flags.dart';
import '../database/iso_scan_dao.dart';
import '../i18n/app_language.dart';
import '../services/heat_photo_storage.dart';
import '../services/iso_scanner_ai.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/haptic.dart';
import '../widgets/premium_gate.dart';
import '../widgets/scan_consent_gate.dart';
import 'scan_review_screen.dart';

const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kBlue   = Color(0xFF4A9EFF);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = kTextMut; // token motywu (kontrast ≥ 4,5:1)

// ═══════════════════════════════════════════════════════════════════════════
// ISO SCANNER — read a piping isometric from a phone photo / scan and turn
// it into a cut list.
//
// The fitter loads a photo of the iso, pans / zooms it on the top half of
// the screen, and sends it to the AI. What comes back is listed as READ —
// dimensions as printed (ISO), never as cut lengths. The cut list is made on
// the review screen (ScanReviewScreen → ProjectDao/SegmentDao) by the one
// engine, with take-outs, root gap and blocks on uncertain values.
//
// Until 2026-09 this screen kept its own list with its own "CUT" = ISO minus
// typed deducts: a 1200 elbow–elbow run showed and copied "CUT 1200" while
// the review said 892. That second formula is gone. Every reading is stored
// on the phone (iso_scans, schema v24) and reopens without a second scan.
//
// This is the ONLY screen in the app that needs a connection: the scan is a
// Claude Vision call on the Railway backend. Everything else — calculators,
// cut lists, journals — works with the phone in flight mode, so the screen
// says so out loud instead of letting a failed scan read as a broken app.
// ═══════════════════════════════════════════════════════════════════════════

/// Per-install daily scan budget.
///
/// Every scan is a paid Vision call. The backend (version of 2026-09-24)
/// enforces its own per-device and per-IP daily limits and a monthly budget
/// (see [kAiScannerEnabled]); this counter is the phone-side fuse on top of
/// them, kept in the fitter's own SharedPreferences and shown to him
/// ("Pozostało dziś: N") before he spends a scan.
/// Kept deliberately dumb: a day string plus a counter. It rolls over on the
/// local calendar day, which is the "resets at midnight" the UI promises.
class _ScanBudget {
  static const String _kDayKey = 'iso_scan_day_v1';
  static const String _kCountKey = 'iso_scan_count_v1';

  static String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// Scans already spent today. A storage failure returns 0 — a fitter who
  /// paid for Premium must not be locked out because SharedPreferences
  /// hiccuped; the paywall is still in front of him.
  static Future<int> usedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kDayKey) != _today()) return 0;
      return prefs.getInt(_kCountKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> remainingToday() async =>
      (kAiScanDailyLimitPerDevice - await usedToday()).clamp(0, 1 << 30);

  /// Marks today's budget as spent — the server said its daily limit for this
  /// install or network is used up, so the counter must not promise more.
  static Future<void> exhaust() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDayKey, _today());
      await prefs.setInt(_kCountKey, kAiScanDailyLimitPerDevice);
    } catch (_) {}
  }

  /// Books one scan. Called when a request actually reached the model, i.e.
  /// when the money was (or may have been) spent — never for a request that
  /// died on the device or was refused before it got there.
  static Future<void> record() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _today();
      final used = prefs.getString(_kDayKey) == today
          ? (prefs.getInt(_kCountKey) ?? 0)
          : 0;
      await prefs.setString(_kDayKey, today);
      await prefs.setInt(_kCountKey, used + 1);
    } catch (_) {
      // Losing one tick of the counter is not worth failing a scan the
      // fitter already paid for.
    }
  }
}

class IsoScannerScreen extends StatefulWidget {
  /// Scan result to start from.
  ///
  /// Production always leaves this null and gets its result from the network.
  /// A widget test injects one so the path from a finished scan to the review
  /// screen can be walked without spending a Vision call.
  @visibleForTesting
  final AiScanResult? initialScan;

  const IsoScannerScreen({super.key, this.initialScan});

  @override
  State<IsoScannerScreen> createState() => _IsoScannerScreenState();
}

class _IsoScannerScreenState extends State<IsoScannerScreen> {
  String? _imagePath;
  final _projectName = TextEditingController();

  /// Readings stored on this phone (newest first) — reopened without a
  /// second, paid scan.
  List<IsoScanRecord> _savedScans = const [];
  final TransformationController _viewer = TransformationController();

  bool _aiBusy = false;
  String? _aiStatus; // shown under the image during scan
  AiScanResult? _lastScan; // for title block strip, BOM and weld list views

  /// Scans left in today's per-install budget. Null until the first read of
  /// SharedPreferences comes back.
  int? _scansLeft;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _lastScan = widget.initialScan;
    _refreshBudget();
    unawaited(_loadSavedScans());
  }

  Future<void> _loadSavedScans() async {
    try {
      final list = await IsoScanDao().listRecent(limit: 10);
      if (!mounted) return;
      setState(() => _savedScans = list);
    } catch (e) {
      // No stored readings to offer is not a reason to fail the screen.
      debugPrint('ISO scanner: reading stored scans failed: $e');
    }
  }

  /// Stores a finished reading (envelope + a copy of the photo in the
  /// backed-up photo folder) so it survives the app being killed and can be
  /// reopened without spending another scan.
  Future<void> _persistScan(AiScanResult result, String? photoPath) async {
    final envelope = result.envelope;
    if (envelope == null) return;
    String? kept;
    if (photoPath != null) {
      try {
        kept = await persistPickedHeatPhoto(photoPath);
      } catch (e) {
        debugPrint('ISO scanner: keeping the photo failed: $e');
      }
    }
    try {
      final name = _projectName.text.trim();
      await IsoScanDao().insert(IsoScanRecord(
        id: const Uuid().v4(),
        name: name.isEmpty ? result.titleBlock.lineNumber : name,
        imagePath: kept,
        envelopeJson: jsonEncode(envelope),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (kept != null && mounted) setState(() => _imagePath = kept);
      await _loadSavedScans();
    } catch (e) {
      debugPrint('ISO scanner: storing the scan failed: $e');
    }
  }

  /// Puts a stored reading back on screen — no network, no budget.
  void _reopenScan(IsoScanRecord r) {
    final env = r.envelope;
    if (env == null) {
      _toast(_tr('Tego odczytu nie da się otworzyć.',
          'This reading cannot be opened.'));
      return;
    }
    final scan = AiScanResult.fromEnvelope(env);
    final photo = r.imagePath;
    setState(() {
      _lastScan = scan;
      _imagePath = (photo != null && File(photo).existsSync()) ? photo : null;
      _aiStatus = null;
      if (_projectName.text.trim().isEmpty && (r.name ?? '').isNotEmpty) {
        _projectName.text = r.name!;
      }
    });
  }

  Future<void> _pickSavedScan() async {
    await _loadSavedScans();
    if (!mounted) return;
    if (_savedScans.isEmpty) {
      _toast(_tr('Nie ma zapisanych skanów.', 'There are no stored scans.'));
      return;
    }
    final picked = await showModalBottomSheet<IsoScanRecord>(
      context: context,
      backgroundColor: _kCard,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _tr('Zapisane skany — otwarcie nie zużywa limitu',
                    'Stored scans — reopening costs no scan'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            for (final r in _savedScans)
              ListTile(
                minVerticalPadding: 12,
                leading: const Icon(Icons.history, color: _kOrange),
                title: Text((r.name ?? '').isEmpty
                    ? _tr('Skan bez nazwy', 'Unnamed scan')
                    : r.name!),
                subtitle: Text(_scanDate(r.createdAt)),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _reopenScan(picked);
  }

  String _scanDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _refreshBudget() async {
    final left = await _ScanBudget.remainingToday();
    if (!mounted) return;
    setState(() => _scansLeft = left);
  }

  @override
  void dispose() {
    _projectName.dispose();
    _viewer.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // File picker can throw on Android (permission denied, security
    // exception, OEM picker crash) or iOS (PhotoKit not authorised). Without
    // a catch the tap silently does nothing and the fitter is stuck staring
    // at the empty state with no idea why — offer a Retry instead.
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = res?.files.single.path;
      if (!mounted || path == null) return;

      // P1-02: validate picked image before any AI call. Cloud-stub photos,
      // zero-byte temp files and 12 MP HDR shots burn Claude Vision tokens
      // and jobsite 4G bandwidth — refuse them up front with a specific
      // PL/EN toast so the fitter picks a real photo instead.
      final file = File(path);
      if (!file.existsSync()) {
        await Haptic.error();
        if (!mounted) return;
        _toast(_tr(
          'Plik nie istnieje lub jest niedostępny. Wybierz inne zdjęcie.',
          'File does not exist or is unavailable. Pick another photo.',
        ));
        return;
      }
      final ext = path.toLowerCase().split('.').last;
      // Same set iso_scanner_ai.dart recognises by magic bytes; HEIC/HEIF is
      // converted to JPEG before upload (or refused there with a clear
      // message if the platform cannot decode it).
      const allowedExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif'};
      if (!allowedExt.contains(ext)) {
        await Haptic.error();
        if (!mounted) return;
        _toast(_tr(
          'Nieobsługiwany format. Użyj JPG, PNG, WEBP lub HEIC.',
          'Unsupported format. Use JPG, PNG, WEBP or HEIC.',
        ));
        return;
      }
      final size = file.lengthSync();
      const minBytes = 1024; // 1 KB — anything smaller is a stub/placeholder.
      // The upload is downscaled to 2576 px on the long side before it leaves
      // the phone (iso_scanner_ai.dart), so the raw file may be a full-size
      // camera shot; this only stops absurd files from being decoded at all.
      const maxBytes = 25 * 1024 * 1024;
      if (size < minBytes) {
        await Haptic.error();
        if (!mounted) return;
        _toast(_tr(
          'Zdjęcie jest zbyt małe lub uszkodzone. Wybierz inne.',
          'Photo is too small or corrupted. Pick another one.',
        ));
        return;
      }
      if (size > maxBytes) {
        await Haptic.error();
        if (!mounted) return;
        _toast(_tr(
          'Plik przekracza 25 MB. Zrób zwykłe zdjęcie (nie RAW) i spróbuj ponownie.',
          'File exceeds 25 MB. Take a regular photo (not RAW) and try again.',
        ));
        return;
      }

      setState(() {
        _imagePath = path;
        _aiStatus = null;
        _lastScan = null; // a new photo invalidates the previous AI read
      });
    } catch (_) {
      await Haptic.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'Nie udało się otworzyć galerii. Sprawdź uprawnienia do zdjęć.',
            'Could not open the gallery. Check photo permissions.',
          )),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: _tr('Ponów', 'Retry'),
            onPressed: _pickImage,
          ),
        ),
      );
    }
  }

  // ── AI analysis ─────────────────────────────────────────────────────────
  Future<void> _runAiAnalysis() async {
    final path = _imagePath;
    if (path == null) return;

    // Spend the daily budget before the request, not after: a scan the
    // fitter cannot afford should never leave the phone.
    final left = await _ScanBudget.remainingToday();
    if (!mounted) return;
    setState(() => _scansLeft = left);
    if (left <= 0) {
      await Haptic.error();
      if (!mounted) return;
      _toast(_tr(
        'Dzienny limit skanów wyczerpany '
            '($kAiScanDailyLimitPerDevice/$kAiScanDailyLimitPerDevice). '
            'Odnowi się po północy — do tego czasu użyj Zeszytu ISO albo '
            'kreatora segmentu.',
        'Daily scan limit used up '
            '($kAiScanDailyLimitPerDevice/$kAiScanDailyLimitPerDevice). '
            'It resets after midnight — until then use the ISO notebook or '
            'the segment builder.',
      ));
      return;
    }

    // The photo leaves the phone for our server and Anthropic — ask once
    // (and again after the rules change) before the first upload.
    if (!await ensureScanConsent(context)) return;
    if (!mounted) return;

    setState(() {
      _aiBusy = true;
      _aiStatus = _tr('Wysyłam zdjęcie do AI…', 'Sending photo to AI…');
    });
    Haptic.tap();

    // Progress nudges so the user knows the request is still in flight on
    // slow connections. Sonnet vision typically returns in 20-40 s; on 4G
    // it can stretch to 60-90 s. Without these the spinner looks frozen.
    Timer? nudge30, nudge60;
    nudge30 = Timer(const Duration(seconds: 30), () {
      if (!mounted || !_aiBusy) return;
      setState(() => _aiStatus = _tr(
            'Wciąż pracuję — AI analizuje rysunek (potrafi potrwać do minuty).',
            'Still working — AI is reading the drawing (can take up to a minute).',
          ));
    });
    nudge60 = Timer(const Duration(seconds: 60), () {
      if (!mounted || !_aiBusy) return;
      setState(() => _aiStatus = _tr(
            'Skanowanie trwa dłużej niż zwykle. Daj jeszcze chwilę…',
            'The scan is taking longer than usual. Hold on a moment…',
          ));
    });

    try {
      // ~30-60s round trip on Sonnet. Don't block UI; user sees the spinner.
      final result = await scanIsoImage(path);

      // The model ran, so the call was billed whatever the drawing turned
      // out to be — book it against today's budget before anything else.
      await _ScanBudget.record();
      unawaited(_refreshBudget());

      if (!mounted) return;

      if (result.isError) {
        setState(() {
          _aiBusy = false;
          _aiStatus = null;
        });
        await Haptic.error();
        _toast(_tr(
          'To nie wygląda na rysunek izometryczny.',
          'This does not look like an isometric drawing.',
        ));
        return;
      }

      _applyAiResult(result);
      // The reading was paid for: keep it (and the photo) on the phone
      // before anything else can throw it away.
      await _persistScan(result, path);
      if (!mounted) return;

      await Haptic.saved();
      setState(() {
        _aiBusy = false;
        _aiStatus = _tr(
          'AI rozpoznała ${result.segments.length} odcinków '
              'i ${result.components.length} elementów'
              '${result.tookMs != null ? " (${(result.tookMs! / 1000).toStringAsFixed(1)} s)" : ""}.',
          'AI found ${result.segments.length} segments '
              'and ${result.components.length} components'
              '${result.tookMs != null ? " (${(result.tookMs! / 1000).toStringAsFixed(1)} s)" : ""}.',
        );
      });

      // If there are uncertainties or missing inputs, prompt the user.
      if (result.needsUserInput.isNotEmpty || result.uncertainty.isNotEmpty) {
        await _showAiReview(result);
      }
    } on IsoScannerAiException catch (e) {
      // The request reached the server. Whether it reached the model depends
      // on the answer: a 5xx after the model call or a timeout can mean the
      // scan was billed and the answer got lost, so those count against the
      // budget; a refusal before the model (limits, budget gate, Premium,
      // bad format, missing route) never got that far and must not.
      if (e.reachedModel) await _ScanBudget.record();
      // The server's own daily limit is spent — the counter on screen must
      // say 0, not promise scans the server will refuse.
      if (e.isDailyLimit) await _ScanBudget.exhaust();
      unawaited(_refreshBudget());
      await _failScan(_serverErrorMessage(e));
    } on TimeoutException {
      // 150 s without an answer. Sonnet may well have run and been charged.
      await _ScanBudget.record();
      unawaited(_refreshBudget());
      await _failScan(_tr(
        'Serwer nie odpowiedział w czasie. Przy słabym zasięgu spróbuj '
            'jeszcze raz albo zrób mniejsze zdjęcie.',
        'The server did not answer in time. On a weak signal try again or '
            'use a smaller photo.',
      ));
    } on SocketException {
      await _failScan(_offlineMessage());
    } on http.ClientException {
      await _failScan(_offlineMessage());
    } catch (e) {
      await _failScan(_tr(
        'Skan się nie udał: $e',
        'The scan failed: $e',
      ));
    } finally {
      nudge30.cancel();
      nudge60.cancel();
    }
  }

  /// Clears the busy state and explains what went wrong.
  Future<void> _failScan(String message) async {
    if (!mounted) return;
    await Haptic.error();
    if (!mounted) return;
    setState(() {
      _aiBusy = false;
      _aiStatus = null;
    });
    _toast(message);
  }

  /// The one error the rest of this app never produces.
  ///
  /// Every other tool works in flight mode, so "no connection" has to be
  /// said in full here — otherwise a fitter in a cellar reads a failed scan
  /// as a broken app and stops trusting the numbers it does have.
  String _offlineMessage() => _tr(
        'Brak połączenia z internetem. Skan rysunku to jedyna funkcja, która '
            'go wymaga — reszta aplikacji działa offline. Wpisz wymiary '
            'ręcznie albo spróbuj w zasięgu.',
        'No internet connection. Scanning a drawing is the only feature that '
            'needs one — the rest of the app works offline. Type the '
            'dimensions in by hand, or try again in coverage.',
      );

  /// Turns an HTTP failure into something a fitter can act on.
  ///
  /// [scanIsoImage] already translates the refusals the fitter cannot fix by
  /// retrying — daily limit (with the renewal time), per-minute limit,
  /// monthly AI budget, Premium, old backend (404 / 500) — into
  /// [IsoScannerAiException.message] (`friendlyScanError`). What is left here
  /// are the statuses whose server text still needs framing.
  String _serverErrorMessage(IsoScannerAiException e) {
    switch (e.statusCode) {
      case 429:
      case 402:
      case 404:
        return e.message;
      case 503:
        if (e.code != null) return e.message;
        return _tr(
          'Skaner AI jest chwilowo wyłączony po stronie serwera. '
              'Spróbuj później — wymiary możesz wpisać ręcznie.',
          'The AI scanner is switched off on the server for now. Try later — '
              'you can type the dimensions in by hand.',
        );
      case 413:
        return _tr(
          'Zdjęcie jest za duże dla serwera. Zrób je jeszcze raz w niższej '
              'rozdzielczości albo przytnij do samego rysunku.',
          'The photo is too large for the server. Retake it at a lower '
              'resolution or crop it to the drawing.',
        );
      case 400:
        return _tr(
          'Serwer odrzucił zdjęcie: ${e.message}',
          'The server rejected the photo: ${e.message}',
        );
      default:
        final status = e.statusCode ?? 0;
        // 500 (old backend) and coded 5xx (AI_BUSY, AI_CONFIG…) already
        // carry a message written for the fitter.
        if (status == 500 || (status > 500 && e.code != null)) {
          return e.message;
        }
        if (status >= 500) {
          return _tr(
            'Błąd serwera skanera (${e.statusCode}). To nie Twoje zdjęcie — '
                'spróbuj ponownie za chwilę.',
            'Scanner server error (${e.statusCode}). It is not your photo — '
                'try again in a moment.',
          );
        }
        return e.message;
    }
  }

  /// Takes an AI reading on screen: the title-block strip, the line name,
  /// and the list of what was read. The screen itself never turns a
  /// dimension into a cut length — the review screen does, through the one
  /// engine, with the fittings' take-outs and the root gap.
  void _applyAiResult(AiScanResult result) {
    // P1-13: AI-returned line numbers occasionally carry embedded CR/LF from
    // multi-line OCR. Strip them and clamp to the same 80-char ceiling the
    // _projectName field enforces so the auto-fill stays within bounds.
    final tbLineRaw = result.titleBlock.lineNumber;
    final tbLine = tbLineRaw?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if ((tbLine ?? '').isNotEmpty && _projectName.text.trim().isEmpty) {
      final clamped = tbLine!.length > 80 ? tbLine.substring(0, 80) : tbLine;
      _projectName.text = clamped;
    }
    setState(() {
      _lastScan = result;
    });
  }

  /// Bottom-sheet review of AI findings — the key UX moment.
  ///
  /// For every "missing input" the AI reported (typically a fitting
  /// take-out it could not read from the drawing), we look up a suggested
  /// value in our own offline ASME B16.9 / B16.28 table and present it
  /// with one-tap accept. Hygienic / BPE drawings get a hint about
  /// orbital welds skipping the take-out catalogue entirely.
  Future<void> _showAiReview(AiScanResult result) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _kBorder,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: _kOrange, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _tr('Wynik analizy AI', 'AI analysis result'),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                            const Spacer(),
                            // Standard / size-notation pill so the fitter
                            // immediately sees "is this ASME inch or ISO DN"
                            // — drives everything downstream.
                            _StdPill(result: result, tr: _tr),
                          ],
                        ),
                        if (result.isHygienic)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _kBlue.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: _kBlue.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.water_drop_outlined,
                                      color: _kBlue, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _tr(
                                        'Rurociąg sanitarny / BPE wykryty. Spoiny orbitalne — take-outów dla butt-weldów się NIE odejmuje. Sprawdź czystość, purge, Ra powierzchni.',
                                        'Hygienic / BPE pipework detected. Orbital butt welds carry no take-outs. Mind cleanliness, purge, surface Ra.',
                                      ),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),

                        // ── Missing inputs with B16.9 suggestions ────────────
                        if (result.needsUserInput.isNotEmpty) ...[
                          _SectionLabel(
                            text: _tr('Brakujące wymiary',
                                'Missing dimensions'),
                          ),
                          const SizedBox(height: 6),
                          for (final need in result.needsUserInput)
                            _MissingInputRow(need: need, tr: _tr),
                          const SizedBox(height: 10),
                        ],

                        // ── Welds list — copy-ready for the welder ───────────
                        if (result.welds.isNotEmpty) ...[
                          _SectionLabel(
                            text: _tr('Spoiny rozpoznane na rysunku',
                                'Welds detected on drawing'),
                            count: result.welds.length,
                          ),
                          const SizedBox(height: 6),
                          for (final w in result.welds)
                            _WeldRow(w: w),
                          const SizedBox(height: 10),
                        ],

                        // ── Uncertainty notes ────────────────────────────────
                        if (result.uncertainty.isNotEmpty) ...[
                          _SectionLabel(
                            text: _tr('Niepewne odczyty',
                                'Uncertain readings'),
                          ),
                          const SizedBox(height: 6),
                          for (final note in result.uncertainty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('•  ',
                                      style: TextStyle(
                                          color: _kRed, fontSize: 14)),
                                  Expanded(
                                    child: Text(note,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            height: 1.4)),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                        ],
                        if (result.warnings.isNotEmpty) ...[
                          _SectionLabel(
                              text: _tr('Uwagi', 'Warnings')),
                          const SizedBox(height: 6),
                          for (final w in result.warnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('•  $w',
                                  style: const TextStyle(
                                      color: _kMuted,
                                      fontSize: 12,
                                      height: 1.4)),
                            ),
                          const SizedBox(height: 10),
                        ],
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(_tr('Gotowe', 'Done')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    // Tune dwell to message length so a glanced glove-tap doesn't dismiss a
    // long error before the fitter has read it (≈18 chars/sec, 4-9s window).
    final secs = (msg.length / 18).ceil().clamp(4, 9);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: _kRed, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        duration: Duration(seconds: secs),
        action: SnackBarAction(
          label: _tr('Zamknij', 'Dismiss'),
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }

  // Dirty when the fitter has a photo loaded, an AI scan result or a project
  // name. Accidental swipe-back on a shop-floor phone would otherwise wipe
  // them without a word (a finished reading is stored, see _persistScan,
  // and the dialog says so).
  bool get _isDirty {
    if (_imagePath != null) return true;
    if (_lastScan != null) return true;
    if (_projectName.text.trim().isNotEmpty) return true;
    return false;
  }

  Future<bool> _confirmDiscard() async {
    final stored = _lastScan?.envelope != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Wyjść ze skanera?', 'Leave the scanner?')),
        content: Text(stored
            ? _tr(
                'Odczyt AI jest zapisany w telefonie — otworzysz go z '
                    '„Zapisane skany” bez ponownego skanowania.',
                'The AI reading is stored on the phone — reopen it from '
                    '“Stored scans” without scanning again.')
            : _tr(
                'Zdjęcie i niezapisany wynik zostaną utracone.',
                'The photo and any unsaved result will be lost.',
              )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('Wróć', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Porzuć', 'Discard')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Whether a scan result is on hand that the planner can work from.
  bool get _canOpenReview {
    final scan = _lastScan;
    return !_aiBusy && scan != null && !scan.isError && scan.segments.isNotEmpty;
  }

  /// Hands the scan to the review screen — the only place a dimension of
  /// the drawing becomes a cut length (one engine: take-outs, gap, blocks).
  void _openScanReview() {
    final scan = _lastScan;
    if (scan == null) return;
    Haptic.tap();
    final name = _projectName.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanReviewScreen(
          scan: scan,
          suggestedName: name.isEmpty ? null : name,
          imagePath: _imagePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Free tier (kAiScannerFreeTier): no Premium gate — the daily limits
    // (server + this phone) and the monthly AI budget on the server cap the
    // bill instead, and the first scan asks for consent to send the photo.
    if (kAiScannerFreeTier) return _buildScannerScaffold(context);
    // Scanner hits Claude Vision per scan → real $$ cost per call. Without
    // the free tier it stays gated even while the rest of PRO is free.
    return PremiumGate(
      featureName: _tr('Skaner izometryku', 'Isometric scanner'),
      alwaysEnforced: true,
      child: _buildScannerScaffold(context),
    );
  }

  /// One line the fitter reads before he spends a scan: that this screen
  /// needs a connection (nothing else in the app does), and how many scans
  /// today's budget has left.
  Widget _scanBudgetStrip() {
    final left = _scansLeft;
    final exhausted = left != null && left <= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: _kCard,
      child: Row(
        children: [
          Icon(
            exhausted ? Icons.hourglass_bottom : Icons.wifi_tethering,
            size: 14,
            color: exhausted ? _kRed : _kBlue,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              exhausted
                  ? _tr(
                      'Limit skanów na dziś wyczerpany — odnowi się po '
                          'północy. Zapisane skany otworzysz bez limitu.',
                      'Today\'s scan budget is used up — it resets after '
                          'midnight. Stored scans reopen without it.',
                    )
                  : _tr(
                      'Skan wymaga internetu (reszta aplikacji działa '
                          'offline).',
                      'Scanning needs internet (the rest of the app works '
                          'offline).',
                    ),
              style: TextStyle(
                fontSize: 11.5,
                color: exhausted ? _kRed : _kSec,
                fontWeight: exhausted ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (left != null) ...[
            const SizedBox(width: 8),
            Text(
              _tr('Pozostało dziś: $left z $kAiScanDailyLimitPerDevice',
                  'Left today: $left of $kAiScanDailyLimitPerDevice'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: exhausted ? _kRed : _kMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Two short lines shown before a scan: what happens to the photo, and
  /// that the reading is a draft to be checked. The full wording (and the
  /// consent) comes in the dialog before the first upload.
  Widget _scanPrivacyNote() {
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 13, color: _kSec),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                      fontSize: 11, height: 1.3, color: _kSec),
                ),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      color: _kCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(
            Icons.cloud_upload_outlined,
            _tr(
              'Zdjęcie idzie na nasz serwer i do Anthropic (Claude) tylko do '
                  'odczytu rysunku — serwer go nie zapisuje.',
              'The photo goes to our server and to Anthropic (Claude) only to '
                  'read the drawing — the server does not store it.',
            ),
          ),
          line(
            Icons.fact_check_outlined,
            _tr(
              'Wynik trzeba sprawdzić — niepewne wartości są oznaczone i nie '
                  'staną się cięciem bez Twojego potwierdzenia.',
              'Check the result — uncertain values are flagged and never '
                  'become a cut without your confirmation.',
            ),
          ),
        ],
      ),
    );
  }

  /// Below the photo: before a scan, the stored readings; after it, what the
  /// model read (dimensions as printed — labelled ISO, not CUT) and the big
  /// button to the review screen, where cuts are computed and saved.
  Widget _resultsPanel() {
    final scan = _lastScan;
    if (scan == null || scan.isError) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          Text(
            _tr(
                'Po skanie zobaczysz tu odczytane wymiary. Długości cięcia '
                    'policzy przegląd skanu — z odliczeniami kształtek, '
                    'szczeliną i blokadą niepewnych wartości.',
                'After a scan the dimensions read will be listed here. Cut '
                    'lengths are computed on the review screen — with the '
                    'fittings\' take-outs, the root gap and blocks on '
                    'uncertain values.'),
            style: const TextStyle(fontSize: 13, height: 1.35, color: _kSec),
          ),
          if (_savedScans.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionLabel(
              text: _tr('Zapisane skany', 'Stored scans'),
              count: _savedScans.length,
            ),
            const SizedBox(height: 6),
            for (final r in _savedScans.take(3))
              Card(
                color: _kCard,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  minVerticalPadding: 12,
                  leading: const Icon(Icons.history, color: _kOrange),
                  title: Text((r.name ?? '').isEmpty
                      ? _tr('Skan bez nazwy', 'Unnamed scan')
                      : r.name!),
                  subtitle: Text(
                      '${_scanDate(r.createdAt)} · ${_tr('otwarcie bez limitu', 'no scan spent')}'),
                  onTap: _aiBusy ? null : () => _reopenScan(r),
                ),
              ),
          ],
        ],
      );
    }
    final segments = scan.segments.where((s) => !s.auxiliary).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            key: const ValueKey('scan-open-review'),
            onPressed: _canOpenReview ? _openScanReview : null,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              _tr('Sprawdź cięcia i utwórz projekt',
                  'Check the cuts and create a project'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _tr(
              'Poniżej wymiary tak, jak je odczytała AI (ISO z rysunku) — to '
                  'NIE są długości cięcia. CUT liczy przegląd.',
              'Below: the dimensions as the AI read them (ISO from the '
                  'drawing) — NOT cut lengths. The review computes the CUT.'),
          style: const TextStyle(fontSize: 12.5, height: 1.35, color: _kSec),
        ),
        const SizedBox(height: 8),
        _SectionLabel(
          text: _tr('Odczytane wymiary', 'Dimensions read'),
          count: segments.length,
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < segments.length; i++)
          _ReadDimensionRow(index: i + 1, segment: segments[i], tr: _tr),
        if (segments.isEmpty)
          Text(
            _tr('AI nie odczytała żadnego odcinka rury.',
                'The AI read no pipe runs.'),
            style: const TextStyle(color: _kRed, fontSize: 13),
          ),
      ],
    );
  }

  Widget _buildScannerScaffold(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (discard && mounted) nav.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_tr('Skaner izometryku', 'Isometric scanner')),
        actions: [
          // The big one: ask Claude Vision to read the drawing.
          IconButton(
            icon: _aiBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kOrange,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            tooltip: _tr('Analizuj AI', 'Analyse with AI'),
            onPressed: (_imagePath == null || _aiBusy) ? null : _runAiAnalysis,
          ),
          // The way out that ends in a cut list instead of a clipboard.
          // Only live once a scan actually came back — a hand-typed segment
          // list has no components for the planner to work from.
          IconButton(
            icon: const Icon(Icons.playlist_add_check_circle_outlined),
            tooltip: _tr('Utwórz projekt z tego skanu',
                'Create a project from this scan'),
            onPressed: _canOpenReview ? _openScanReview : null,
          ),
          // Stored readings — reopened without a second, paid scan.
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: _tr('Zapisane skany', 'Stored scans'),
            onPressed: _aiBusy ? null : _pickSavedScan,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Image viewer / pick button ─────────────────────────────────
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF0B0E13),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _imagePath == null
                        ? Center(child: _PickEmpty(onPick: _pickImage, tr: _tr))
                        : _ImageViewer(
                            path: _imagePath!,
                            viewer: _viewer,
                            onChange: _pickImage,
                            onResetZoom: () =>
                                _viewer.value = Matrix4.identity(),
                            tr: _tr,
                          ),
                  ),
                  // Spinner overlay while AI is working — dims the photo
                  // and shows a status line so the fitter knows we're alive.
                  if (_aiBusy)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: _kOrange),
                            const SizedBox(height: 12),
                            Text(
                              _aiStatus ?? _tr('Analiza AI…', 'AI analysis…'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Small banner with last AI status while idle.
                  if (!_aiBusy && _aiStatus != null)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 14, color: _kOrange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _aiStatus!,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── What the scan costs and what it needs ──────────────────────
          _scanBudgetStrip(),

          // ── Before the first scan: where the photo goes, and that the
          //    result has to be checked ────────────────────────────────────
          if (_lastScan == null && !_aiBusy) _scanPrivacyNote(),

          // ── Title block strip from AI (line number, class, material…) ──
          if (_lastScan != null && _lastScan!.titleBlock.hasAnything)
            _TitleBlockStrip(scan: _lastScan!, tr: _tr),

          // ── Project name ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            color: _kCard,
            child: TextField(
              controller: _projectName,
              // P1-13: cap project name length and strip newlines so the
              // value is safe for clipboard, PDF watermark and AI prompts.
              maxLength: 80,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
              ],
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                labelText:
                    _tr('Nazwa rurociągu / linia', 'Pipe run / line name'),
                hintText: _tr('np. 6"-CWS-1234', 'e.g. 6"-CWS-1234'),
                prefixIcon: const Icon(Icons.label_outline, size: 18),
              ),
            ),
          ),

          // ── What was read, and the one way to a cut list ───────────────
          // This screen shows the drawing's dimensions as read, never a
          // "CUT": a cut length needs the fittings' take-outs, the root gap
          // and the blocks on uncertain values — the review screen computes
          // all of that through the one engine.
          Expanded(
            flex: 7,
            child: _resultsPanel(),
          ),
        ],
      ),
    ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _PickEmpty extends StatelessWidget {
  final VoidCallback onPick;
  final String Function(String, String) tr;
  const _PickEmpty({required this.onPick, required this.tr});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_search, size: 48, color: _kMuted),
          const SizedBox(height: 12),
          Text(
            tr('Wybierz zdjęcie izometryku',
                'Pick a photo of the isometric'),
            style: const TextStyle(color: _kSec, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(tr('Wybierz zdjęcie', 'Choose photo')),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
                'Zoom dwoma palcami • przeciągaj jednym palcem',
                'Pinch to zoom • drag with one finger'),
            style: const TextStyle(color: _kMuted, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
                'Analiza AI wymaga internetu — reszta aplikacji działa offline.',
                'AI analysis needs internet — the rest of the app works offline.'),
            style: const TextStyle(color: _kBlue, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Image viewer with zoom/pan ───────────────────────────────────────────────

class _ImageViewer extends StatelessWidget {
  final String path;
  final TransformationController viewer;
  final VoidCallback onChange;
  final VoidCallback onResetZoom;
  final String Function(String, String) tr;
  const _ImageViewer({
    required this.path,
    required this.viewer,
    required this.onChange,
    required this.onResetZoom,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: viewer,
            minScale: 0.5,
            maxScale: 8.0,
            child: Center(
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                // Dekoduj do ~2048 px zamiast surowych ~4000 px z aparatu —
                // duzo mniej pamieci, a zoom (do 8x) nadal ostry. (Play:
                // "probkowanie w dol bitmap")
                cacheWidth: 2048,
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _IconBtn(
                icon: Icons.center_focus_strong,
                tooltip: tr('Resetuj zoom', 'Reset zoom'),
                onTap: onResetZoom,
              ),
              const SizedBox(width: 6),
              _IconBtn(
                icon: Icons.swap_horiz,
                tooltip: tr('Zmień zdjęcie', 'Change photo'),
                onTap: onChange,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Title-block strip shown below the photo after a successful AI scan ──────

class _TitleBlockStrip extends StatelessWidget {
  final AiScanResult scan;
  final String Function(String, String) tr;
  const _TitleBlockStrip({required this.scan, required this.tr});

  @override
  Widget build(BuildContext context) {
    final tb = scan.titleBlock;
    final chips = <(String, String)>[
      if (tb.lineNumber != null) (tr('Linia', 'Line'), tb.lineNumber!),
      if (tb.pipeClass != null) (tr('Klasa', 'Class'), tb.pipeClass!),
      if (tb.material != null) (tr('Materiał', 'Material'), tb.material!),
      if (tb.schedule != null) (tr('Sch', 'Sch'), tb.schedule!),
      if (tb.designPressure != null) ('P', tb.designPressure!),
      if (tb.designTemperature != null) ('T', tb.designTemperature!),
      if (tb.fluidService != null) (tr('Medium', 'Fluid'), tb.fluidService!),
      if (tb.insulationThickness != null)
        (tr('Izol.', 'Insul.'), tb.insulationThickness!),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.fact_check_outlined,
                size: 14, color: _kOrange),
            const SizedBox(width: 6),
            for (final c in chips)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _kBlue.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${c.$1}: ',
                          style: const TextStyle(
                              color: _kSec,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                      Text(c.$2,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── AI review sub-widgets ────────────────────────────────────────────────────

class _StdPill extends StatelessWidget {
  final AiScanResult result;
  final String Function(String, String) tr;
  const _StdPill({required this.result, required this.tr});

  @override
  Widget build(BuildContext context) {
    final bits = <String>[];
    if (result.drawingStandard != 'unknown') {
      bits.add(result.drawingStandard);
    }
    if (result.sizeNotation != 'unknown') bits.add(result.sizeNotation);
    if (bits.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kOrange.withValues(alpha: 0.4)),
      ),
      child: Text(
        bits.join(' · '),
        style: const TextStyle(
            color: _kOrange, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final int? count;
  const _SectionLabel({required this.text, this.count});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
              color: _kMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('($count)',
              style: const TextStyle(color: _kMuted, fontSize: 11)),
        ],
      ],
    );
  }
}

/// "The AI needs a take-out" with the offline ASME value, for information:
/// the take-out itself is set (and its CUT computed) on the review screen.
class _MissingInputRow extends StatelessWidget {
  final AiNeedsInput need;
  final String Function(String, String) tr;
  const _MissingInputRow({required this.need, required this.tr});

  @override
  Widget build(BuildContext context) {
    final suggested = need.suggestedTakeoutMm();
    final dn = need.guessDn();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.help_outline, color: _kOrange, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(need.ask,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),
              ),
            ],
          ),
          if (need.hint != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(need.hint!,
                  style: const TextStyle(
                      color: _kMuted, fontSize: 11, height: 1.3)),
            ),
          ],
          if (suggested != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                '${tr('Tabela', 'Table')}: $suggested mm  ·  ASME B16.9 '
                    'DN${dn ?? ""}'
                    '${need.is45 ? " 45°" : need.isShortRadius ? " SR" : " LR"}'
                    ' — ${tr('ustawisz w przeglądzie', 'set it on the review')}',
                style: const TextStyle(
                    color: _kBlue, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One dimension as the AI read it: the drawing's number (ISO) and how sure
/// the model was. Deliberately no CUT — see [_IsoScannerScreenState].
class _ReadDimensionRow extends StatelessWidget {
  final int index;
  final AiSegment segment;
  final String Function(String, String) tr;
  const _ReadDimensionRow({
    required this.index,
    required this.segment,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final raw = segment.rawDimension?.trim();
    final mm = segment.dimensionMm;
    final shown = (raw != null && raw.isNotEmpty)
        ? raw
        : (mm != null ? '${mm.toStringAsFixed(mm == mm.roundToDouble() ? 0 : 1)} mm' : '—');
    final (Color c, String conf) = switch (segment.confidence) {
      AiConfidence.high => (_kSec, tr('pewny', 'sure')),
      AiConfidence.medium => (const Color(0xFFFFC44D), tr('średnio pewny', 'medium')),
      _ => (_kRed, tr('niepewny', 'unsure')),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Text('$index.',
              style: const TextStyle(
                  color: _kBlue, fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Text('ISO ',
              style: const TextStyle(
                  color: _kSec, fontSize: 12, fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(shown,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ),
          Text(conf,
              style: TextStyle(
                  color: c, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _WeldRow extends StatelessWidget {
  final AiComponent w;
  const _WeldRow({required this.w});
  @override
  Widget build(BuildContext context) {
    final isField = w.isField == true || w.type == 'fieldWeld';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(
            isField ? Icons.flag_circle : Icons.circle_outlined,
            size: 14,
            color: isField ? _kRed : _kBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                if (w.weldNo != null) w.weldNo,
                if (w.weldType != null) w.weldType!,
                if (w.weldPosition != null) 'pos. ${w.weldPosition}',
                if (w.throatA != null) 'a${w.throatA}',
                if (w.weldNde != null) 'NDE: ${w.weldNde}',
                if (w.weldPwht == true) 'PWHT',
              ].whereType<String>().join('  ·  '),
              style:
                  const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          if (isField)
            Text('FW',
                style: TextStyle(
                    color: _kRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 18, color: Colors.white),
        tooltip: tooltip,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
