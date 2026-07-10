import 'package:sqflite_common/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Baza w przeglądarce: SQLite skompilowany do WebAssembly, dane trzymane
/// w IndexedDB.
///
/// Świadomie używamy wariantu BEZ web-workera. Oficjalny `databaseFactoryFfiWeb`
/// wymaga pliku `web/sqflite_sw.js`, który generuje `dart run
/// sqflite_common_ffi_web:setup` — a ten skrypt wywraca się na obecnym SDK
/// (`'dart compile' does not support build hooks`). Wariant no-worker potrzebuje
/// wyłącznie `web/sqlite3.wasm` i działa w izolacie głównym: zapytania blokują
/// wątek UI, więc nadaje się do wersji webowej jako podglądu, nie do ciężkiego
/// przetwarzania.
///
/// `web/sqlite3.wasm` musi odpowiadać wersji pakietu `sqlite3` z `pubspec.lock`
/// (obecnie 2.4.5), inaczej ładowanie modułu padnie w czasie działania.
void initDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
