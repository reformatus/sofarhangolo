import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../data/database.dart';
import '../../data/log/logger.dart';

/// SQLite's `SQLITE_CORRUPT_VTAB`: a virtual table (here the FTS5 index)
/// reported itself as unusable.
const _corruptVtabCode = 267;

/// SQLite's `SQLITE_CORRUPT`.
const _corruptCode = 11;

/// The message SQLite gives for both codes. Matched as text too, because some
/// executors (the web and remote ones) hand the error over without the type.
const _corruptMessage = 'database disk image is malformed';

/// Whether [error] means the song search index cannot be read.
///
/// `songs_fts` is external-content (see song.drift): it stores only the index
/// and reads titles and lyrics out of `songs` by rowid. An index row whose song
/// is gone - what an upsert through REPLACE leaves behind, since REPLACE's
/// implicit delete skips the DELETE triggers - makes `snippet()` fail on that
/// row with "database disk image is malformed".
///
/// FTS5 only notices when the content table is actually read. A plain `MATCH`
/// and `bm25()` answer from the index alone, so a database can search fine and
/// still be broken: it fails only once a query asks for a snippet of an
/// orphaned row - which the search does for every matched row, because it
/// materialises the hits. FTS5's own `integrity-check` has the same blind spot
/// unless the content table is included (`('integrity-check', 1)`).
bool isSearchIndexCorruption(Object error) {
  if (error is SqliteException) {
    return error.extendedResultCode == _corruptVtabCode ||
        error.resultCode == _corruptCode;
  }
  return error.toString().contains(_corruptMessage);
}

/// Rebuilds `songs_fts` from `songs`.
///
/// The index is derived data, so FTS5's external-content `rebuild` command -
/// which re-reads the whole content table and rewrites the index - is always
/// safe, just not free (tens of milliseconds for a few hundred songs).
Future<void> rebuildSearchIndex() => db.customStatement(
  "INSERT INTO songs_fts(songs_fts) VALUES('rebuild')",
);

Future<void>? _repairInFlight;

/// [rebuildSearchIndex], shared between concurrent callers: an index found
/// corrupt by several queries at once is repaired once, not once per query.
Future<void> repairSearchIndex() {
  return _repairInFlight ??= rebuildSearchIndex().whenComplete(
    () => _repairInFlight = null,
  );
}

/// [search], rebuilt and retried once if SQLite reports the index as corrupt.
///
/// The healthy path pays nothing: the repair only runs when a query actually
/// failed on the index. When it does, the index is rebuilt from `songs` and the
/// search is simply run again, so the caller - and the UI - sees results rather
/// than a database error.
///
/// Two cases are left alone. A stream that already produced a value is not
/// retried, because running it again would repeat that value; and an error that
/// is not index corruption is passed through untouched, so real problems stay
/// visible.
Stream<T> withSearchIndexRepair<T>(Stream<T> Function() search) async* {
  var produced = false;
  try {
    // `await for`, not `yield*`: the latter forwards a failing stream's errors
    // to its own subscriber without throwing them here, so the repair below
    // would never run.
    await for (final value in search()) {
      produced = true;
      yield value;
    }
  } catch (error, stackTrace) {
    if (produced || !isSearchIndexCorruption(error)) rethrow;
    log.warning(
      'A dalok keresőindexe sérült volt, újraépítem.',
      error,
      stackTrace,
    );
    await repairSearchIndex();
    await for (final value in search()) {
      yield value;
    }
  }
}
