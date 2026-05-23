import 'dart:io';
import 'package:flutter/services.dart';

/// Helpers for fitter/welder feedback. Phone usually sits in a pocket or in
/// a chest bracket; gloves block visual confirmation, so we lean on haptics.
/// All calls are best-effort — never throw, never block.
class Haptic {
  /// Fires when a segment / weld / measurement is saved.
  static Future<void> saved() => _safe(HapticFeedback.mediumImpact);

  /// Fires when a value is copied to the clipboard.
  static Future<void> copied() => _safe(HapticFeedback.selectionClick);

  /// Fires on validation errors that need user attention.
  static Future<void> error() => _safe(HapticFeedback.heavyImpact);

  /// Fires on minor selection changes (e.g. dropdown choice).
  static Future<void> tap() => _safe(HapticFeedback.lightImpact);

  static Future<void> _safe(Future<void> Function() f) async {
    if (!_isMobile) return;
    try {
      await f();
    } catch (_) {
      // Some emulators/desktops throw — silently swallow.
    }
  }

  static bool get _isMobile {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }
}
