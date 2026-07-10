// Wybór fabryki bazy danych zależnie od platformy — rozstrzygany w czasie
// KOMPILACJI, nie działania. To konieczne, bo:
//   • `sqflite_common_ffi` ciągnie `dart:ffi`, którego nie ma w przeglądarce,
//   • `sqflite_common_ffi_web` ciągnie `dart:js_interop`, którego nie ma na
//     Androidzie i iOS.
// Zwykły `if (kIsWeb)` nie wystarczy — obie gałęzie musiałyby się skompilować.
//
// Użycie: `initDatabaseFactory()` raz, w `main()`, przed pierwszym zapytaniem.

export 'db_bootstrap_io.dart'
    if (dart.library.js_interop) 'db_bootstrap_web.dart';
