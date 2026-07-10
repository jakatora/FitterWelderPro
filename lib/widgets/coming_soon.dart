import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

// Shared "Wkrótce" (coming soon) placeholder for parked PRO features.
// A single, polished screen so every gated entry point (Premium, Chat,
// Jobs, ISO Scanner) lands on the same on-brand message instead of opening
// a live-but-parked feature. Reversible from lib/config/feature_flags.dart.

const _kBg = Color(0xFF0B0E13);
const _kCard = Color(0xFF141821);
const _kGold = Color(0xFFE8C14B);
const _kOrange = Color(0xFFFF8E1E);
const _kText = Color(0xFFE7ECF3);
const _kTextSec = Color(0xFF9BA3C7);

/// Push the full-screen "coming soon" placeholder for a parked feature.
Future<void> openComingSoon(
  BuildContext context, {
  required String featureName,
  String? description,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ComingSoonScreen(
        featureName: featureName,
        description: description,
      ),
    ),
  );
}

class ComingSoonScreen extends StatelessWidget {
  final String featureName;
  final String? description;

  const ComingSoonScreen({
    super.key,
    required this.featureName,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(
          featureName.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: _kText,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _kOrange.withValues(alpha: 0.20),
                      _kGold.withValues(alpha: 0.10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _kGold.withValues(alpha: 0.35), width: 1.5),
                ),
                child: const Icon(Icons.rocket_launch_outlined,
                    color: _kGold, size: 44),
              ),
              const SizedBox(height: 22),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [_kOrange, _kGold],
                ).createShader(b),
                child: Text(
                  context.tr(pl: 'Wkrótce', en: 'Coming soon'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                featureName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description ??
                    context.tr(
                      pl: 'Ta funkcja jest w przygotowaniu i pojawi się '
                          'w kolejnej aktualizacji. Wszystkie narzędzia '
                          'montersko-spawalnicze działają już teraz.',
                      en: 'This feature is under construction and will arrive '
                          'in a future update. Every fitter/welder tool is '
                          'ready to use right now.',
                    ),
                style: const TextStyle(
                    fontSize: 13, color: _kTextSec, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(
                      context.tr(pl: 'Wróć do narzędzi', en: 'Back to tools')),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
