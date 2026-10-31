// Wersja aplikacji jako stała w kodzie (pole `app` sygnału feedbacku).
//
// Bez `package_info_plus` (zasada: bez nowych pakietów) i bez wywołań platformy
// przy starcie. Test test/config/app_version_test.dart pilnuje zgodności z
// `version:` w pubspec.yaml — podbijasz wersję, podbijasz też tę stałą.

const String kAppVersion = '0.5.5+24';
