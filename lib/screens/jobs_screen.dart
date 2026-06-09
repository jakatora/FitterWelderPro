// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/job_listing.dart';
import '../services/jobs_service.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import 'job_add_screen.dart';

// "Praca" module — local-first job board. Lists postings from the on-device
// SQLite store, filters by location, lets the user add new ones. Once Phase
// 6b adds Firestore sync + Stripe one-time payment, the same UI continues
// to work — the DAO swaps to a Firestore-backed repository under the hood.

const _kBg = Color(0xFF0F1117);
const _kCard = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kAccent = Color(0xFFE57373);
const _kGold = Color(0xFFE8C14B);
const _kTextSec = Color(0xFF9BA3C7);
const _kTextMut = Color(0xFF55607A);

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final _filterCtrl = TextEditingController();
  List<JobListing> _listings = const [];
  bool _loading = true;
  String? _error;
  // P1-11 — set while we're inside the post-Stripe webhook poll loop so we can
  // render a "waiting for payment confirmation" banner and disable the Add FAB
  // (prevents a second Stripe Checkout session being created while the first
  // webhook is still in flight on flaky basement/jobsite cellular).
  bool _waitingForWebhook = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await JobsService.instance.listPublic(
        locationLike: _filterCtrl.text.trim().isEmpty
            ? null
            : _filterCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _listings = all;
        _loading = false;
      });
    } catch (e) {
      // P1-01 — DAO/HTTP failure must always reset the spinner AND surface a
      // Ponów/Retry SnackBar (frozen orange spinner is the #1 "is the app
      // broken?" symptom on slow workshop signal — users force-quit).
      debugPrint('[JobsScreen._load] failed: $e');
      if (!mounted) return;
      // P2-08 — if we already have cached listings on screen (refresh-after-
      // stale-cache: pull-to-refresh or filter-change failed but the list is
      // populated), DON'T blank the list — keep the cached rows visible and
      // surface a distinct "showing saved data" SnackBar so the fitter knows
      // the numbers may be out of date. Only on a cold-start failure do we
      // expose the generic "could not load" + empty-state error path.
      final hasStaleCache = _listings.isNotEmpty;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(hasStaleCache
              ? context.tr(
                  pl: 'Nie udało się odświeżyć — pokazuję zapisane dane.',
                  en: 'Could not refresh — showing saved data.',
                )
              : context.tr(
                  pl: 'Nie udało się wczytać ogłoszeń.',
                  en: 'Could not load listings.',
                )),
          action: SnackBarAction(
            label: context.tr(pl: 'Ponów', en: 'Retry'),
            onPressed: _load,
          ),
        ));
    }
  }

  Future<void> _addNew() async {
    // JobAddScreen now returns `true` after the user is sent to Stripe
    // Checkout — the listing isn't visible until webhook completes, so we
    // refresh after a short delay to let the round-trip finish.
    final res = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const JobAddScreen()),
    );
    if (res == true) {
      // P1-11 — flip the banner on while we're waiting for the webhook so
      // the user sees confirmation that something is happening; also gates
      // the Add FAB to prevent a second Stripe Checkout being created.
      if (!mounted) return;
      setState(() => _waitingForWebhook = true);
      try {
        // Webhook usually fires within ~1.5 s of the user finishing the Stripe
        // form; the old fixed 3 s delay was either a wait-too-long (slow
        // perceived UX) or a wait-too-short (listing missing). Poll the
        // public list every 1.5 s up to 12 s and stop as soon as the listing
        // count changes — the first new paid id will be the user's own.
        final before = _listings.length;
        for (var i = 0; i < 8; i++) {
          await Future.delayed(const Duration(milliseconds: 1500));
          if (!mounted) return;
          try {
            final fresh = await JobsService.instance.listPublic(
              locationLike: _filterCtrl.text.trim().isEmpty
                  ? null
                  : _filterCtrl.text.trim(),
            );
            if (!mounted) return;
            if (fresh.length != before) {
              setState(() => _listings = fresh);
              return;
            }
          } catch (e) {
            // P1-01 — log but don't bail; the next tick will retry. Only a
            // total-window failure surfaces a SnackBar (below).
            debugPrint('[JobsScreen._addNew] poll tick $i failed: $e');
          }
        }
        // Webhook didn't fire within the window — fall back to a manual reload
        // and surface a Ponów action so the user can re-poll on demand.
        if (!mounted) return;
        try {
          await _load();
        } catch (e) {
          debugPrint('[JobsScreen._addNew] fallback _load failed: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(context.tr(
                pl: 'Płatność jeszcze nie potwierdzona. Spróbuj odświeżyć za chwilę.',
                en: 'Payment not confirmed yet. Try refreshing in a moment.',
              )),
              action: SnackBarAction(
                label: context.tr(pl: 'Ponów', en: 'Retry'),
                onPressed: _load,
              ),
            ));
        }
      } finally {
        // Always lower the banner / re-enable the FAB, even on early-return
        // (unmount, success) or a thrown poll exception.
        if (mounted) setState(() => _waitingForWebhook = false);
      }
    }
  }

  Future<void> _openDetail(JobListing j) async {
    final res = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _JobDetailScreen(listing: j)),
    );
    if (res == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(context.tr(pl: 'Praca', en: 'Jobs')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: context.tr(pl: 'Dodaj ogłoszenie', en: 'Add listing'),
            // P1-11 — same gate as the FAB so the duplicate-Stripe-session
            // window is closed from every entrypoint.
            onPressed: _waitingForWebhook ? null : _addNew,
          ),
        ],
      ),
      body: Column(
        children: [
          // P1-11 — webhook-polling banner. Pinned to top of body so it sits
          // above the filter + list and is visible regardless of scroll.
          if (_waitingForWebhook)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: _kGold.withValues(alpha: 0.15),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kGold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(
                        pl: 'Czekamy na potwierdzenie płatności…',
                        en: 'Waiting for payment confirmation…',
                      ),
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFE8ECF0),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _filterCtrl,
              style: const TextStyle(color: Color(0xFFE8ECF0)),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.tr(
                  pl: 'Filtruj po lokalizacji (np. Płock, Niemcy)',
                  en: 'Filter by location (e.g. Gdańsk, Germany)',
                ),
                hintStyle: const TextStyle(color: _kTextMut, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: _kTextSec),
                suffixIcon: _filterCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: _kTextSec),
                        tooltip: context.tr(pl: 'Wyczyść filtr', en: 'Clear filter'),
                        onPressed: () {
                          _filterCtrl.clear();
                          _load();
                        },
                      )
                    : null,
                filled: true,
                fillColor: _kCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kBorder),
                ),
              ),
              onSubmitted: (_) => _load(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _loading
                // P2-15 — replace the centred CircularProgressIndicator with a
                // 3-card shimmer skeleton + "Ładuję ogłoszenia…" label and a
                // 6 s slow-network prompt. Mirrors the actual _JobCard layout
                // so the LCP shift on success is minimal — the fitter sees the
                // list materialise rather than a blank flash.
                ? _LoadingSkeleton(onRetry: _load)
                : _error != null && _listings.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off,
                                  color: _kTextMut, size: 40),
                              const SizedBox(height: 10),
                              Text(
                                context.tr(
                                  pl: 'Brak połączenia z modułem Praca.',
                                  en: 'Jobs module unreachable.',
                                ),
                                style: const TextStyle(color: _kTextSec),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: Text(context.tr(
                                    pl: 'Spróbuj ponownie', en: 'Retry')),
                              ),
                            ],
                          ),
                        ),
                      )
                : _listings.isEmpty
                    // P1-10 — distinguish "no listings match this filter" from
                    // "no listings at all". A filter-empty state must offer a
                    // "Wyczyść filtr" action so the user doesn't conclude the
                    // module is broken when they typed e.g. "Płlock".
                    ? (_filterCtrl.text.trim().isNotEmpty
                        ? _FilterEmptyState(
                            query: _filterCtrl.text.trim(),
                            onClear: () {
                              _filterCtrl.clear();
                              setState(() {});
                              _load();
                            },
                          )
                        : _EmptyState(onAdd: _addNew))
                    : RefreshIndicator(
                        color: _kAccent,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: _listings.length,
                          itemBuilder: (context, i) {
                            final j = _listings[i];
                            return _JobCard(
                              listing: j,
                              onTap: () => _openDetail(j),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // P1-11 — disable while a Stripe webhook poll is in flight so the user
        // can't tap-mash a second Checkout session into existence.
        backgroundColor: _waitingForWebhook
            ? _kAccent.withValues(alpha: 0.4)
            : _kAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(context.tr(pl: 'Dodaj', en: 'Add')),
        onPressed: _waitingForWebhook ? null : _addNew,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Job card (list item)
// ════════════════════════════════════════════════════════════════════════════
class _JobCard extends StatelessWidget {
  final JobListing listing;
  final VoidCallback onTap;
  const _JobCard({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final reqs = listing.requirements;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: listing.isPaid ? _kGold.withValues(alpha: 0.4) : _kBorder,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listing.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE8ECF0),
                        ),
                      ),
                    ),
                    if (listing.isPaid)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kGold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.tr(pl: 'WYRÓŻNIONE', en: 'FEATURED'),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: _kGold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.business_outlined, size: 13, color: _kTextMut),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        listing.company,
                        style: const TextStyle(fontSize: 12, color: _kTextSec),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.place_outlined, size: 13, color: _kTextMut),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        listing.location,
                        style: const TextStyle(fontSize: 12, color: _kTextSec),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (listing.rate != null && listing.rate!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.payments_outlined, size: 13, color: _kAccent),
                      const SizedBox(width: 4),
                      Text(
                        listing.rate!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kAccent,
                        ),
                      ),
                    ],
                  ),
                ],
                if (reqs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: reqs.take(6).map((r) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kBorder.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          r,
                          style: const TextStyle(
                              fontSize: 10, color: _kTextSec),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _formatPostedAt(context, listing.createdAt),
                  style: const TextStyle(fontSize: 10, color: _kTextMut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatPostedAt(BuildContext context, int ms) {
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms))
        .inHours;
    // Clamp future timestamps (device-clock skew or backend timezone drift)
    // so we never show "Dodano -3 h temu".
    if (diff < 1) {
      return context.tr(pl: 'Dodano przed chwilą', en: 'Just posted');
    } else if (diff < 24) {
      return context.tr(pl: 'Dodano $diff h temu', en: 'Posted ${diff}h ago');
    } else {
      final days = (diff / 24).round();
      // Polish plural: 1 → "dzień", 2-4 / 22-24 / ... → "dni" (was always "dni",
      // which is wrong for the singular "1 dni temu" edge case).
      final plDay = days == 1 ? 'dzień' : 'dni';
      return context.tr(
          pl: 'Dodano $days $plDay temu', en: 'Posted ${days}d ago');
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Empty state
// ════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.work_outline,
                  size: 44, color: _kAccent),
            ),
            const SizedBox(height: 14),
            Text(
              context.tr(pl: 'Brak ogłoszeń', en: 'No listings yet'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE8ECF0),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                pl: 'Bądź pierwszy — opublikuj ogłoszenie. '
                    'Synchronizacja między urządzeniami pojawi się w kolejnej aktualizacji.',
                en: 'Be the first — publish a listing. '
                    'Cross-device sync arrives in the next update.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _kTextSec, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(
                  context.tr(pl: 'Dodaj ogłoszenie', en: 'Add listing')),
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Filter-empty state (P1-10) — separate from no-data empty state so a typoed
// filter doesn't look like a broken module.
// ════════════════════════════════════════════════════════════════════════════
class _FilterEmptyState extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  const _FilterEmptyState({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, color: _kTextMut, size: 44),
            const SizedBox(height: 12),
            Text(
              context.tr(
                pl: 'Brak ogłoszeń dla "$query"',
                en: 'No listings for "$query"',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE8ECF0),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                pl: 'Spróbuj innej lokalizacji lub wyczyść filtr.',
                en: 'Try another location or clear the filter.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: _kTextSec, height: 1.5),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear),
              label: Text(context.tr(pl: 'Wyczyść filtr', en: 'Clear filter')),
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Detail screen
// ════════════════════════════════════════════════════════════════════════════
class _JobDetailScreen extends StatelessWidget {
  final JobListing listing;
  const _JobDetailScreen({required this.listing});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(context.tr(pl: 'Ogłoszenie', en: 'Listing')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.tr(pl: 'Edytuj', en: 'Edit'),
            onPressed: () async {
              // Guard the edit-route push: if JobAddScreen's initState throws
              // (e.g. SQLite handle stale after low-memory kill), the
              // unhandled future error would otherwise crash the route with a
              // red screen mid-edit — a fitter loses both context and the
              // half-typed posting. Surface as a SnackBar instead.
              try {
                final res = await Navigator.push<JobListing>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => JobAddScreen(existing: listing)),
                );
                if (res != null && context.mounted) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(context.tr(
                    pl: 'Nie udało się otworzyć edycji: $e',
                    en: 'Could not open editor: $e',
                  )),
                ));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
            onPressed: () {
              // Gloved tap on a destructive icon — confirm registration
              // before the dialog covers the button.
              Haptic.tap();
              _confirmDelete(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            listing.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFFE8ECF0),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.business_outlined, size: 16, color: _kTextSec),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${listing.company}  •  ${listing.location}',
                  style: const TextStyle(fontSize: 14, color: _kTextSec),
                ),
              ),
            ],
          ),
          if (listing.rate != null && listing.rate!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments, color: _kAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(pl: 'Stawka', en: 'Rate'),
                          style: const TextStyle(
                              fontSize: 11, color: _kTextMut, letterSpacing: 1),
                        ),
                        Text(
                          listing.rate!,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE8ECF0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (listing.requirements.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              context.tr(pl: 'WYMAGANIA', en: 'REQUIREMENTS'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _kTextMut,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: listing.requirements.map((r) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Text(
                    r,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFE8ECF0)),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            context.tr(pl: 'OPIS', en: 'DESCRIPTION'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _kTextMut,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: SelectableText(
              listing.description,
              style: const TextStyle(
                fontSize: 14, color: Color(0xFFE8ECF0), height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 18),
          if ((listing.contactEmail?.isNotEmpty ?? false) ||
              (listing.contactPhone?.isNotEmpty ?? false)) ...[
            Text(
              context.tr(pl: 'KONTAKT', en: 'CONTACT'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _kTextMut,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            if (listing.contactEmail?.isNotEmpty ?? false)
              _ContactRow(
                icon: Icons.email_outlined,
                label: listing.contactEmail!,
                onCopy: () => _copy(context, listing.contactEmail!),
              ),
            if (listing.contactPhone?.isNotEmpty ?? false)
              _ContactRow(
                icon: Icons.phone_outlined,
                label: listing.contactPhone!,
                onCopy: () => _copy(context, listing.contactPhone!),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text(
          context.tr(pl: 'Usunąć ogłoszenie?', en: 'Delete listing?'),
          style: const TextStyle(color: Color(0xFFE8ECF0)),
        ),
        content: Text(
          context.tr(
              pl: 'Tej akcji nie można cofnąć.',
              en: 'This action cannot be undone.'),
          style: const TextStyle(color: _kTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      // Backend listings auto-expire 30 days after payment — there is no
      // user-initiated delete endpoint in the MVP. Surface that to the user
      // instead of pretending the delete worked.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
          pl: 'Ogłoszenie znika automatycznie po 30 dniach od opłacenia.',
          en: 'Listings auto-expire 30 days after payment.',
        )),
      ));
    }
  }

  void _copy(BuildContext context, String value) {
    // Route via the shared helper so contact copies match calculator-screen
    // behaviour: haptic confirmation + de-duped snackbar (hideCurrent first).
    copyToClipboard(context, value);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Loading skeleton (P2-15) — 3 shimmer-pulse placeholder job cards + label
// "Ładuję ogłoszenia…" + 6 s slow-network nudge ("Wolne połączenie? Ponów").
// Stateful so we own the shimmer AnimationController + the 6 s Timer and can
// dispose both cleanly when _loading flips false (parent re-creates this
// subtree on every list state transition).
// ════════════════════════════════════════════════════════════════════════════
class _LoadingSkeleton extends StatefulWidget {
  final VoidCallback onRetry;
  const _LoadingSkeleton({required this.onRetry});

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    // P2-15 — 6 s threshold; after that, surface a slow-network prompt with
    // Ponów so the fitter on basement / depot signal can choose to retry
    // rather than stare at the shimmer indefinitely.
    _slowTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kAccent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                context.tr(
                  pl: 'Ładuję ogłoszenia…',
                  en: 'Loading listings…',
                ),
                style: const TextStyle(
                  fontSize: 13,
                  color: _kTextSec,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // 3-4 shimmer skeleton job cards mirroring _JobCard's layout.
        for (var i = 0; i < 3; i++)
          _SkeletonJobCard(pulse: _pulse, indexSeed: i),
        if (_slow) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kGold.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.sync_problem, size: 18, color: _kGold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr(
                      pl: 'Wolne połączenie. Spróbuj ponownie lub poczekaj chwilę.',
                      en: 'Slow connection. Try again or wait a moment.',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFE8ECF0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  child: TextButton(
                    onPressed: widget.onRetry,
                    child: Text(
                      context.tr(pl: 'Ponów', en: 'Retry'),
                      style: TextStyle(
                        color: _kAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// Single shimmer-pulsing skeleton card. Mirrors _JobCard padding/shape so the
// transition to real data looks like content materialising in place rather
// than a flash. `indexSeed` desynchronises the pulse a touch between cards.
class _SkeletonJobCard extends StatelessWidget {
  final AnimationController pulse;
  final int indexSeed;
  const _SkeletonJobCard({required this.pulse, required this.indexSeed});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        // Offset each card's phase slightly so they don't strobe in lockstep.
        final phased = (pulse.value + indexSeed * 0.18) % 1.0;
        // Triangle wave 0.35 → 0.75 → 0.35 — keeps contrast above the kBg.
        final t = phased < 0.5 ? phased * 2 : (1 - phased) * 2;
        final alpha = 0.35 + 0.40 * t;
        final barColor = _kBorder.withValues(alpha: alpha);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(width: 200, height: 14, color: barColor),
              const SizedBox(height: 10),
              Row(
                children: [
                  _bar(width: 110, height: 10, color: barColor),
                  const SizedBox(width: 12),
                  _bar(width: 90, height: 10, color: barColor),
                ],
              ),
              const SizedBox(height: 12),
              _bar(width: 70, height: 10, color: barColor),
              const SizedBox(height: 12),
              Row(
                children: [
                  _bar(width: 40, height: 14, color: barColor),
                  const SizedBox(width: 6),
                  _bar(width: 52, height: 14, color: barColor),
                  const SizedBox(width: 6),
                  _bar(width: 36, height: 14, color: barColor),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar({required double width, required double height, required Color color}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onCopy;
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _kAccent),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFFE8ECF0)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16, color: _kTextMut),
              tooltip: context.tr(pl: 'Kopiuj', en: 'Copy'),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}
