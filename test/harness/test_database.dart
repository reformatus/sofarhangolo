import 'package:drift/native.dart';
import 'package:sofarhangolo/data/database.dart';

/// Creates an in-memory database for testing.
///
/// Each call returns an isolated database instance that doesn't persist
/// between tests. Use this instead of the global `db` in unit tests.
///
/// **Note:** Requires libsqlite3 on Linux. Install with:
/// ```bash
/// sudo apt install libsqlite3-dev
/// ```
/// Or on macOS: `brew install sqlite3`
///
/// If SQLite is not available, tests using this will fail with a descriptive error.
LyricDatabase createTestDatabase() {
  try {
    return LyricDatabase(
      NativeDatabase.memory(
        setup: (db) {
          // Enable foreign keys for referential integrity in tests
          db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  } catch (e) {
    throw StateError(
      'Could not create test database. '
      'Ensure SQLite is installed:\n'
      '  Linux: sudo apt install libsqlite3-dev\n'
      '  macOS: brew install sqlite3\n'
      'Original error: $e',
    );
  }
}

/// Extension to help with common test database operations.
extension TestDatabaseExtensions on LyricDatabase {
  /// Clears all data from all tables (useful for test isolation).
  /// Temporarily disables foreign key checks to avoid constraint issues.
  Future<void> clearAllTables() async {
    // Disable FK checks during cleanup
    await customStatement('PRAGMA foreign_keys = OFF');
    await delete(cues).go();
    await delete(assets).go();
    await delete(songs).go();
    await delete(banks).go();
    await delete(preferenceStorage).go();
    // Re-enable FK checks
    await customStatement('PRAGMA foreign_keys = ON');
  }
}
