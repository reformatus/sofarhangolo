import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../data/database.dart';
import '../../data/log/logger.dart';

/// SQLite's `SQLITE_CORRUPT_VTAB`.
const _corruptVtabCode = 267;

/// SQLite's `SQLITE_CORRUPT`.
const _corruptCode = 11;

/// The message both codes carry; matched as text too, for the executors that
/// hand errors over without the type.
const _corruptMessage = 'database disk image is malformed';

/// Whether [error] means the search index cannot be read.
///
/// `songs_fts` is external-content: it reads titles and lyrics out of `songs`
/// by rowid, so an index row whose song is gone breaks `snippet()`. A plain
/// `MATCH` and `bm25()` answer from the index alone, and FTS5's own
/// `integrity-check` only notices with the content check
/// (`('integrity-check', 1)`).
bool isSearchIndexCorruption(Object error) {
  if (error is SqliteException) {
    return error.extendedResultCode == _corruptVtabCode ||
        error.resultCode == _corruptCode;
  }
  return error.toString().contains(_corruptMessage);
}

/// Rebuilds `songs_fts` from `songs`. The index is derived data, so FTS5's
/// external-content `rebuild` is always safe, just not free.
Future<void> rebuildSearchIndex() => db.customStatement(
  "INSERT INTO songs_fts(songs_fts) VALUES('rebuild')",
);

Future<void>? _repairInFlight;

/// [rebuildSearchIndex], shared between concurrent callers.
Future<void> repairSearchIndex() {
  return _repairInFlight ??= rebuildSearchIndex().whenComplete(
    () => _repairInFlight = null,
  );
}

/// [search], rebuilt and rerun once when SQLite reports a corrupt index.
///
/// Nothing is swallowed: a failed rebuild, or a query that fails again, streams
/// its error on to the caller. A stream that already emitted is not rerun (it
/// would repeat the value), and other errors pass through untouched.
Stream<T> withSearchIndexRepair<T>(Stream<T> Function() search) async* {
  var produced = false;
  try {
    // `await for`, not `yield*`: the latter forwards a failing stream's error
    // to its own subscriber without throwing it here, skipping the repair.
    await for (final value in search()) {
      produced = true;
      yield value;
    }
  } catch (error, stackTrace) {
    if (produced || !isSearchIndexCorruption(error)) rethrow;
    log.warning('Keresőindex újraépítése...', error, stackTrace);
    await repairSearchIndex();
    await for (final value in search()) {
      yield value;
    }
  }
}
