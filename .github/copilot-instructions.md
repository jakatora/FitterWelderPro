# Cut List App - AI Coding Guidelines

## Project Overview
Cut List App is a **Flutter desktop/mobile application** for pipe cutting and welding parameter management. It targets Windows (primary), Android, and iOS platforms. The app helps welders and fitters manage pipe cut lists, heat treatments, and welding parameters.

## Architecture

### Data Layer (Repository + DAO Pattern)
- **`lib/data/`**: Repositories (ProjectRepository, etc.) act as data access facades
- **`lib/database/`**: Data Access Objects (DAOs) handle individual table operations
  - DAOs: `project_dao.dart`, `segment_dao.dart`, `component_heat_dao.dart`, etc.
  - `db.dart`: Raw SQLite initialization using sqflite (desktop) and sqflite_common_ffi
  - **Database is versioned** (currently v9) with migration support in `onCreate`/`onUpgrade`
- **Key Models**: [Project](lib/models/project.dart), [Segment](lib/models/segment.dart), SegmentItem, Component

### Persistence
- **SQLite via sqflite**: Desktop (Windows/Linux/macOS) uses `sqflite_common_ffi` initialized in [main.dart](lib/main.dart)
- **Database init**: Happens in `WidgetsFlutterBinding.ensureInitialized()` before `runApp()`
- **Shared storage**: Desktop uses `getApplicationDocumentsDirectory()` from `path_provider`

### Services Layer
- [CutListService](lib/services/cut_list_service.dart): Business logic for cut calculations, ISO checks, validation
- [CutPackingService](lib/services/cut_packing_service.dart): Optimizes cut packing/nesting
- [DatabaseService](lib/services/database_service.dart): Database coordination
- **Result Types**: Services return result objects (`ValidationResult`, `CutCalculationResult`) not raw values
- No dependency injection framework—services are instantiated directly or via DAOs

### Community Sync (Experimental)
- [WelderPipeCommunitySyncService](lib/modules/welder_pipe/community_sync_service.dart): Sends welding parameters to Firebase
- Firebase is **commented out** in `pubspec.yaml` (requires C++ SDK for Windows)
- Uses device ID tracking and signature-based submission queueing

### UI Layer
- **State Management**: Plain `StatefulWidget` + `setState()` (no Provider, GetX, or Riverpod)
- **Navigation**: Standard Flutter routing via `Navigator.push()` and named routes
- **Multi-screen workflows**: E.g., cut list editor flows through segment builder → component selection
- **Localization**: [l10n/app_en.arb](lib/l10n/app_en.arb) and [app_pl.arb](lib/l10n/app_pl.arb) for English/Polish

## Key Workflows & Patterns

### Add a Feature Touching Multiple Layers
1. **Model**: Add field to model class (e.g., `lib/models/project.dart`), implement `toMap()`/`fromMap()`
2. **Database**: Add migration in [db.dart](lib/database/db.dart) (increment version, add `onUpgrade` block)
3. **DAO**: Add query method to corresponding DAO
4. **Repository**: Wrap DAO calls with business logic
5. **Service**: Add calculation/validation logic if needed
6. **UI**: Call service from `initState()` or button callback, use `setState()` to refresh

### Handling Data Flows
- Projects contain multiple Segments
- Segments contain SegmentItems (components, pipes, elbows)
- Cut calculations aggregate items across segments
- ISO reference marks trigger validation checks via `CutListService.checkISO()`

### Building Windows Desktop
- Run `build_windows.bat` or `build_windows_fixed.bat` (handles missing Flutter assets)
- Generates native Windows app with embedded Flutter runtime
- Database path is in user's Documents folder

## Conventions & Gotchas

### Database
- Always increment schema version when adding tables/columns
- Use `_ensureColumn()` helper to avoid "column already exists" errors during upgrades
- Foreign keys are enabled via `PRAGMA foreign_keys = ON`
- Timestamps stored as milliseconds since epoch (not strings)

### Models
- All models have `toMap()`, `fromMap()`, `copyWith()`, `toJson()`/`fromJson()` methods
- Use nullable fields (`?`) for optional data; defaults are set in constructor
- Material group (SS/CS) is a recurring concept in projects and component libraries

### UI
- No async state needed—use `FutureBuilder` only when loading async data in build
- Multi-line text fields use `maxLines: null`
- Dialog confirmations follow Material design patterns
- Polish translations required for user-facing strings

### Testing
- `test/widget_test.dart` exists but sparse (add widget tests for complex screens)
- Manual testing on Windows recommended due to desktop-specific quirks

## Critical Dependencies
- `sqflite` + `sqflite_common_ffi`: SQLite abstraction
- `file_picker`: File dialogs
- `intl`: Date/number formatting
- `shared_preferences`: Simple key-value store
- `uuid`: Unique IDs
- `crypto`: SHA256 hashing (for sync signatures)

## Common Tasks

### Query Data
```dart
final db = await AppDatabase.instance.db;
final rows = await db.query('projects', where: 'id = ?', whereArgs: [id]);
```

### Validate Before Save
```dart
final result = CutListService.validateSegment(segment);
if (!result.isValid) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(text: result.errorMessage));
  return;
}
```

### Refresh UI After Data Change
```dart
await repository.updateProject(project);
setState(() {}); // Trigger rebuild
```

## Files to Review First
1. [lib/models/index.dart](lib/models/index.dart) — All model exports
2. [lib/services/cut_list_service.dart](lib/services/cut_list_service.dart) — Core business logic
3. [lib/database/db.dart](lib/database/db.dart) — Database schema & migrations
4. [lib/screens/home_screen.dart](lib/screens/home_screen.dart) — Navigation hub
