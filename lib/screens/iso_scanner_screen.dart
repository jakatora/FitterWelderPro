import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../services/iso_parser.dart';
import '../services/iso_scanner_ai.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import '../widgets/premium_gate.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

// ═══════════════════════════════════════════════════════════════════════════
// ISO SCANNER — read a piping isometric from a phone photo / scan and turn
// it into a cut list.
//
// The fitter loads a photo of the iso, pans / zooms it on the top half of
// the screen, and on the bottom enters each pipe run from the drawing:
//   - the ISO dimension (face-to-face / centre-to-centre)
//   - the take-outs of the components on each end (elbow centre-to-face,
//     flange thickness, valve width…)
//
// CUT = ISO − Σ take-outs. Per-segment results and a grand total are shown
// live; the whole cut list is one tap away from the clipboard.
// ═══════════════════════════════════════════════════════════════════════════

class IsoScannerScreen extends StatefulWidget {
  const IsoScannerScreen({super.key});

  @override
  State<IsoScannerScreen> createState() => _IsoScannerScreenState();
}

class _Deduct {
  final TextEditingController name;
  final TextEditingController value;
  _Deduct([String n = '', String v = ''])
      : name = TextEditingController(text: n),
        value = TextEditingController(text: v);
  void dispose() {
    name.dispose();
    value.dispose();
  }
}

class _Segment {
  final TextEditingController iso;
  final List<_Deduct> deducts;
  _Segment()
      : iso = TextEditingController(),
        deducts = [];
  void dispose() {
    iso.dispose();
    for (final d in deducts) {
      d.dispose();
    }
  }

  /// CUT length in mm based on what's typed. NaN when ISO can't be parsed.
  double get cutMm {
    double v;
    try {
      v = parseIsoExpression(iso.text);
    } catch (_) {
      return double.nan;
    }
    for (final d in deducts) {
      if (d.value.text.trim().isEmpty) continue;
      try {
        v -= parseIsoExpression(d.value.text);
      } catch (_) {}
    }
    return v;
  }
}

class _IsoScannerScreenState extends State<IsoScannerScreen> {
  String? _imagePath;
  final List<_Segment> _segments = [_Segment()];
  final _projectName = TextEditingController();
  final TransformationController _viewer = TransformationController();

  bool _aiBusy = false;
  String? _aiStatus; // shown under the image during scan
  AiScanResult? _lastScan; // for title block strip, BOM and weld list views

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    for (final s in _segments) {
      s.dispose();
    }
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

      // Replace current segments with the ones the AI read off the drawing.
      _applyAiResult(result);

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
      if (!mounted) return;
      await Haptic.error();
      setState(() {
        _aiBusy = false;
        _aiStatus = null;
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      await Haptic.error();
      setState(() {
        _aiBusy = false;
        _aiStatus = null;
      });
      _toast(_tr(
        'Nie udało się połączyć z serwerem AI. Sprawdź internet.',
        'Could not reach the AI server. Check your connection.',
      ));
    } finally {
      nudge30.cancel();
      nudge60.cancel();
    }
  }

  /// Translates an [AiScanResult] into the screen's segment list.
  ///
  /// Each AI segment becomes a _Segment with its dimension pre-filled. We
  /// don't auto-fill take-outs — the AI never invents those, the user
  /// fills them in by hand (or accepts the hint from B16.9 in the
  /// "review" dialog).
  void _applyAiResult(AiScanResult result) {
    // Clear current segments.
    for (final s in _segments) {
      s.dispose();
    }
    _segments.clear();

    if (result.segments.isEmpty) {
      _segments.add(_Segment());
    } else {
      for (final aiSeg in result.segments) {
        if (aiSeg.auxiliary) continue; // skip auxiliary / hidden lines
        final seg = _Segment();
        // Clamp AI-suggested dimensions to a sane prefab range. Vision
        // models occasionally hallucinate negative values or order-of-
        // magnitude misreads (e.g. "1500 mm" → 150000) which would silently
        // poison the cut list.
        //
        // P0r-02: the previous fallback to rawDimension silently re-routed
        // the same out-of-band number through the parser as a string,
        // bypassing this guard. Now we try-parse rawDimension and re-apply
        // the (0, 100000) gate; if it still fails, the row is left blank
        // so the fitter sees an empty field + the "do sprawdzenia" chip
        // instead of an absurd auto-filled number.
        final dim = aiSeg.dimensionMm;
        if (dim != null && dim > 0 && dim < 100000 && dim.isFinite) {
          seg.iso.text = dim.toStringAsFixed(0);
        } else {
          final raw = aiSeg.rawDimension;
          if (raw != null && raw.isNotEmpty) {
            try {
              final parsed = parseIsoExpression(raw);
              if (parsed.isFinite && parsed > 0 && parsed < 100000) {
                seg.iso.text = raw;
              }
            } catch (_) {
              // Unparseable raw + rejected dim → leave blank, surface via chip.
            }
          }
        }
        _segments.add(seg);
      }
      if (_segments.isEmpty) _segments.add(_Segment());
    }

    // Prefer the line number from the title block (richer), fall back to
    // the top-level lineNumber.
    final tbLine = result.titleBlock.lineNumber;
    if ((tbLine ?? '').isNotEmpty && _projectName.text.trim().isEmpty) {
      _projectName.text = tbLine!;
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
                            _MissingInputRow(
                              need: need,
                              segments: _segments,
                              onApply: (segIdx, name, value) {
                                if (segIdx < 0 ||
                                    segIdx >= _segments.length) {
                                  return;
                                }
                                final seg = _segments[segIdx];
                                seg.deducts.add(_Deduct(name, value));
                                setState(() {});
                                setLocal(() {});
                              },
                              tr: _tr,
                            ),
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

  // Dirty when the fitter has a photo loaded, an AI scan result, a project
  // name, or any typed segment data. Accidental swipe-back on a shop-floor
  // phone (especially after a 30-90s AI scan that cost a Vision API call)
  // would silently wipe everything.
  bool get _isDirty {
    if (_imagePath != null) return true;
    if (_lastScan != null) return true;
    if (_projectName.text.trim().isNotEmpty) return true;
    for (final s in _segments) {
      if (s.iso.text.trim().isNotEmpty) return true;
      for (final d in s.deducts) {
        if (d.name.text.trim().isNotEmpty) return true;
        if (d.value.text.trim().isNotEmpty) return true;
      }
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Porzucić skan?', 'Discard scan?')),
        content: Text(_tr(
          'Zdjęcie, wynik AI i wpisane wymiary zostaną utracone.',
          'The photo, AI result and entered dimensions will be lost.',
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

  void _addSegment() {
    Haptic.tap();
    setState(() => _segments.add(_Segment()));
  }

  void _removeSegment(int i) {
    if (_segments.length <= 1) {
      // Last segment — clear instead of removing.
      Haptic.tap();
      setState(() {
        _segments[i].dispose();
        _segments[i] = _Segment();
      });
      return;
    }
    Haptic.tap();
    setState(() {
      _segments[i].dispose();
      _segments.removeAt(i);
    });
  }

  void _addDeduct(int segIdx) {
    Haptic.tap();
    setState(() => _segments[segIdx].deducts.add(_Deduct()));
  }

  void _removeDeduct(int segIdx, int dedIdx) {
    Haptic.tap();
    setState(() {
      _segments[segIdx].deducts[dedIdx].dispose();
      _segments[segIdx].deducts.removeAt(dedIdx);
    });
  }

  double get _totalCutMm {
    double sum = 0;
    for (final s in _segments) {
      final c = s.cutMm;
      // Drop NaN / infinite (unparseable ISO) AND drop negative cuts (a
      // deduct typo or AI hallucination producing CUT < 0 would otherwise
      // silently shrink the total — fitter cuts pipe stock by metres less
      // than needed). `_invalidSegmentCount` surfaces the dropped count in
      // the UI so the user knows the headline number is exclusive.
      if (c.isFinite && c >= 0) sum += c;
    }
    return sum;
  }

  /// Number of segments excluded from `_totalCutMm` due to unparseable ISO
  /// or a negative computed CUT. Drives the warning chip in the cut-list UI.
  ///
  /// P0r-03: also counts the "ISO blank + deducts populated" case. The old
  /// `continue` on empty-ISO silently hid these rows from BOTH the total and
  /// the warning chip — fitter walked to the saw missing an entire cut.
  int get _invalidSegmentCount {
    int n = 0;
    for (final s in _segments) {
      final isoEmpty = s.iso.text.trim().isEmpty;
      final anyDeduct = s.deducts.any((d) => d.value.text.trim().isNotEmpty);
      // Fully-empty row → not yet filled in by the user, no warning.
      if (isoEmpty && !anyDeduct) continue;
      // Empty ISO + populated deduct → row is in a half-filled state that
      // produces NaN; flag explicitly so the user knows to type the ISO.
      if (isoEmpty && anyDeduct) {
        n++;
        continue;
      }
      final c = s.cutMm;
      if (!c.isFinite || c < 0) n++;
    }
    return n;
  }

  int get _dimensionedCount =>
      _segments.where((s) => s.iso.text.trim().isNotEmpty).length;

  Future<void> _copySummary() async {
    final buf = StringBuffer();
    buf.writeln(_projectName.text.trim().isEmpty
        ? _tr('Skan izometryku', 'Isometric scan')
        : _projectName.text.trim());
    buf.writeln('═' * 28);
    if (_imagePath != null) {
      buf.writeln('${_tr('Źródło', 'Source')}: ${_imagePath!.split(Platform.pathSeparator).last}');
      buf.writeln();
    }

    buf.writeln(_tr('CUT LIST', 'CUT LIST'));
    for (var i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      if (s.iso.text.trim().isEmpty) continue;
      final cut = s.cutMm;
      final cutStr = cut.isFinite
          ? '${cut.toStringAsFixed(1)} mm'
          : _tr('(nieczytelne)', '(unreadable)');
      final hasDeducts = s.deducts.any((d) => d.value.text.trim().isNotEmpty);
      if (!hasDeducts) {
        buf.writeln('  ${i + 1}. ${s.iso.text.trim()} = $cutStr');
      } else {
        buf.writeln('  ${i + 1}. ${_tr('ISO', 'ISO')}: ${s.iso.text.trim()}');
        for (final d in s.deducts) {
          if (d.value.text.trim().isEmpty) continue;
          final tag = d.name.text.trim().isEmpty ? '?' : d.name.text.trim();
          buf.writeln('       − $tag: ${d.value.text.trim()}');
        }
        buf.writeln('     ${_tr('CUT', 'CUT')}: $cutStr');
      }
    }
    buf.writeln('  ${'─' * 24}');
    buf.writeln('  ${_tr('Suma CUT', 'Total CUT')}: '
        '${_totalCutMm.toStringAsFixed(1)} mm');

    if (!mounted) return;
    await copyToClipboard(context, buf.toString(),
        label: _tr('Zestawienie', 'Summary'));
  }

  @override
  Widget build(BuildContext context) {
    // Scanner hits Claude Vision per scan → real $$ cost per call. Stays
    // gated even while the rest of PRO is free during beta.
    return PremiumGate(
      featureName: _tr('Skaner izometryku', 'Isometric scanner'),
      alwaysEnforced: true,
      child: _buildScannerScaffold(context),
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
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _tr('Kopiuj zestawienie', 'Copy summary'),
            onPressed: _dimensionedCount == 0 ? null : _copySummary,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Image viewer / pick button ─────────────────────────────────
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF0F1117),
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

          // ── Title block strip from AI (line number, class, material…) ──
          if (_lastScan != null && _lastScan!.titleBlock.hasAnything)
            _TitleBlockStrip(scan: _lastScan!, tr: _tr),

          // ── Project name ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            color: _kCard,
            child: TextField(
              controller: _projectName,
              decoration: InputDecoration(
                isDense: true,
                labelText:
                    _tr('Nazwa rurociągu / linia', 'Pipe run / line name'),
                hintText: _tr('np. 6"-CWS-1234', 'e.g. 6"-CWS-1234'),
                prefixIcon: const Icon(Icons.label_outline, size: 18),
              ),
            ),
          ),

          // ── Cut list summary strip ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            color: _kCard,
            child: Row(
              children: [
                Icon(Icons.content_cut, size: 14, color: _kOrange),
                const SizedBox(width: 6),
                Text(
                  '${_tr('Odcinki', 'Segments')}: '
                  '$_dimensionedCount/${_segments.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: _kSec,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // Warning chip — surfaces segments excluded from the total
                // because their ISO was unparseable OR resolved to a
                // negative CUT (deduct typo, AI hallucination). Without
                // this, a corrupt segment silently shrinks the total and
                // the fitter pulls too little stock.
                if (_invalidSegmentCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kRed.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: _kRed.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: Text(
                      '$_invalidSegmentCount '
                      '${_tr('do sprawdzenia', 'to check')}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _kRed),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${_tr('Suma CUT', 'Total CUT')}: '
                  '${_totalCutMm.toStringAsFixed(1)} mm',
                  style: const TextStyle(
                      fontSize: 13,
                      color: _kOrange,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),

          // ── Segments list ──────────────────────────────────────────────
          Expanded(
            flex: 7,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              itemCount: _segments.length + 1,
              itemBuilder: (_, i) {
                if (i == _segments.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: _addSegment,
                      icon: const Icon(Icons.add),
                      label: Text(_tr('Dodaj odcinek', 'Add segment')),
                    ),
                  );
                }
                return _SegmentCard(
                  index: i,
                  segment: _segments[i],
                  onRemove: () => _removeSegment(i),
                  onAddDeduct: () => _addDeduct(i),
                  onRemoveDeduct: (k) => _removeDeduct(i, k),
                  onChanged: () => setState(() {}),
                  tr: _tr,
                );
              },
            ),
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

class _MissingInputRow extends StatelessWidget {
  final AiNeedsInput need;
  final List<_Segment> segments;
  final void Function(int segIdx, String name, String value) onApply;
  final String Function(String, String) tr;
  const _MissingInputRow({
    required this.need,
    required this.segments,
    required this.onApply,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    // AI suggests "give me a take-out". Our offline B16.9 table almost
    // always has a sensible default — pre-fill it.
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$suggested mm  ·  ASME B16.9 DN${dn ?? ""}'
                          '${need.is45 ? " 45°" : need.isShortRadius ? " SR" : " LR"}',
                      style: const TextStyle(
                          color: _kBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: Text(tr('Dodaj do odcinka',
                        'Add to segment')),
                    onPressed: () =>
                        _pickSegmentAndApply(context, suggested),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Tiny dialog asking which segment the take-out belongs to.
  /// (AI gives us the component id, but mapping component → segment
  /// reliably is fragile; the fitter knows immediately by glancing at the
  /// drawing.)
  Future<void> _pickSegmentAndApply(
      BuildContext context, int suggestedMm) async {
    final pick = await showDialog<int>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: Text(tr('Do którego odcinka odjąć?',
              'Subtract from which segment?')),
          content: SizedBox(
            width: 320,
            // Cap height so a long list (40+ segments scanned from a busy
            // drawing) scrolls instead of pushing the dialog off-screen on
            // small phones.
            height: MediaQuery.of(dctx).size.height * 0.5,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: segments.length,
              itemBuilder: (_, i) {
                final s = segments[i];
                final iso = s.iso.text.trim().isEmpty
                    ? tr('(pusty)', '(empty)')
                    : s.iso.text;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: _kBlue.withValues(alpha: 0.18),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: _kBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                  title: Text('${tr('Odcinek', 'Segment')} ${i + 1}'),
                  subtitle: Text(iso),
                  onTap: () => Navigator.pop(dctx, i),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: Text(tr('Anuluj', 'Cancel')),
            ),
          ],
        );
      },
    );
    if (pick == null) return;
    final label = need.componentId ?? need.type;
    onApply(pick, label, suggestedMm.toString());
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

// ── One segment card ─────────────────────────────────────────────────────────

class _SegmentCard extends StatelessWidget {
  final int index;
  final _Segment segment;
  final VoidCallback onRemove;
  final VoidCallback onAddDeduct;
  final void Function(int) onRemoveDeduct;
  final VoidCallback onChanged;
  final String Function(String, String) tr;

  const _SegmentCard({
    required this.index,
    required this.segment,
    required this.onRemove,
    required this.onAddDeduct,
    required this.onRemoveDeduct,
    required this.onChanged,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final cut = segment.cutMm;
    final hasIso = segment.iso.text.trim().isNotEmpty;
    // A finite cut is fine. An unparseable ISO with non-empty text needs an
    // inline hint so the fitter knows WHY the result is "—" instead of
    // staring at a blank dash.
    final parseError = hasIso && !cut.isFinite;
    final cutLabel = cut.isFinite
        ? '${cut.toStringAsFixed(1)} mm'
        : (hasIso ? tr('błąd składni', 'syntax error') : '—');
    final cutColor =
        cut.isFinite && cut < 0 ? _kRed : (cut.isFinite ? _kOrange : _kMuted);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${index + 1}',
                    style: const TextStyle(
                        color: _kBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: segment.iso,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: tr('ISO segmentu', 'Segment ISO'),
                    hintText: tr('np. 3000+525-80', 'e.g. 3000+525-80'),
                    suffixText: 'mm',
                    errorText: parseError
                        ? tr(
                            'Sprawdź składnię: liczby + − × ( )',
                            'Check syntax: numbers + − × ( )',
                          )
                        : null,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: tr('Usuń odcinek', 'Remove segment'),
                onPressed: onRemove,
              ),
            ],
          ),
          if (segment.deducts.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (var k = 0; k < segment.deducts.length; k++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 36),
                child: Row(
                  children: [
                    Text('−',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.tertiary)),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: segment.deducts[k].name,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: tr('komponent', 'component'),
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: Builder(builder: (_) {
                        // Sanity-check the typed deduct: empty is fine, a
                        // parse failure is caught elsewhere, but a NEGATIVE
                        // deduct (− of −) or one larger than any real fitting
                        // allowance (>5000 mm) is almost always a typo that
                        // would silently wreck the CUT total.
                        final raw = segment.deducts[k].value.text.trim();
                        double? parsed;
                        if (raw.isNotEmpty) {
                          try {
                            parsed = parseIsoExpression(raw);
                          } catch (_) {}
                        }
                        final outOfRange = parsed != null &&
                            (parsed < 0 || parsed > 5000);
                        return TextField(
                          controller: segment.deducts[k].value,
                          // Deducts are typically a single mm value (gasket,
                          // fitting allowance). Number pad keeps gloved entry
                          // fast; parser already accepts both "," and "."
                          // so the locale comma key on Android works too.
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '76',
                            suffixText: 'mm',
                            errorText: outOfRange
                                ? tr('Zakres 0–5000 mm', 'Range 0–5000 mm')
                                : null,
                          ),
                          onChanged: (_) => onChanged(),
                        );
                      }),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: () => onRemoveDeduct(k),
                    ),
                  ],
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 6),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(tr('Dodaj komponent', 'Add component'),
                      style: const TextStyle(fontSize: 12)),
                  onPressed: onAddDeduct,
                ),
                const Spacer(),
                // CUT result pill — tinted background gives the headline
                // value visual weight so it's scannable in a long list.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cut.isFinite
                        ? cutColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: cut.isFinite
                          ? cutColor.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${tr('CUT', 'CUT')}  ',
                        style: const TextStyle(
                            fontSize: 11,
                            color: _kSec,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                      Text(cutLabel,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cutColor,
                            letterSpacing: -0.3,
                          )),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
