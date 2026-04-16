import 'dart:io' show Platform;

class PlatformSupport {
  static bool get isAndroid => Platform.isAndroid;

  /// W tej chwili: Google Sign-In aktywny na Android, wyłączony na Windows (bez crasha).
  static bool get googleSignInEnabled => isAndroid;
}
