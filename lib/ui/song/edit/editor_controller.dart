import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/log/logger.dart';
import '../../../data/song/song.dart';
import '../../../services/assets/get_song_asset.dart';
import '../../../services/assets/pick_asset.dart';
import '../../../services/assets/write_song_asset.dart';
import '../../../services/song/from_uuid.dart';
import '../../../services/songs/write_song.dart';
import 'autosave_indicator.dart';

part 'editor_controller.g.dart';

/// Everything the local song editor shows and edits.
@immutable
class LocalSongEditorState {
  const LocalSongEditorState({
    required this.song,
    required this.title,
    required this.lyrics,
    required this.contentMap,
    required this.keyField,
    this.status = AutosaveStatus.idle,
    this.deleted = false,
  });

  /// Starts a session from the stored [song].
  factory LocalSongEditorState.fromSong(Song song) => LocalSongEditorState(
    song: song,
    title: song.title,
    lyrics: song.lyrics ?? '',
    contentMap: Map.of(song.contentMap),
    keyField: List.of(song.keyField),
  );

  /// The last stored version; the source of truth for attachments.
  final Song song;

  final String title;
  final String lyrics;

  /// The draft metadata. Attachment keys mirror [song]'s.
  final Map<String, Object> contentMap;
  final List<KeyField> keyField;

  final AutosaveStatus status;

  /// The song was deleted (by us or from elsewhere): nothing is saved anymore.
  final bool deleted;

  /// [song] with the draft edits applied. Attachment references always come
  /// from [song], never from the draft.
  Song get draft {
    final map = Map<String, Object>.of(contentMap);
    for (final key in assetFieldExtensions.keys) {
      map.remove(key);
      final stored = song.contentMap[key];
      if (stored != null) map[key] = stored;
    }
    return song.copyWith(
      title: title,
      lyrics: lyrics,
      contentMap: map,
      keyField: List.of(keyField),
    );
  }

  LocalSongEditorState copyWith({
    Song? song,
    String? title,
    String? lyrics,
    Map<String, Object>? contentMap,
    List<KeyField>? keyField,
    AutosaveStatus? status,
    bool? deleted,
  }) => LocalSongEditorState(
    song: song ?? this.song,
    title: title ?? this.title,
    lyrics: lyrics ?? this.lyrics,
    contentMap: contentMap ?? this.contentMap,
    keyField: keyField ?? this.keyField,
    status: status ?? this.status,
    deleted: deleted ?? this.deleted,
  );
}

/// Owns the draft of one local song being edited, its debounced autosave,
/// attachment writes and deletion.
///
/// Every database write goes through one sequential queue, so no two writes
/// for this song overlap. Each edit bumps a revision; a save only settles to
/// "saved" when no newer edit arrived while it was writing.
@riverpod
class LocalSongEditorController extends _$LocalSongEditorController {
  static const _saveDebounce = Duration(milliseconds: 500);
  static const _savedLinger = Duration(seconds: 2);

  Timer? _debounce;
  Timer? _linger;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// The editor is closing: nobody is left to watch the saved confirmation.
  bool _closing = false;

  /// Bumped by every edit.
  int _revision = 0;

  /// The revision the last successful save wrote.
  int _savedRevision = 0;

  /// Mirror of the latest state, readable while disposing.
  LocalSongEditorState? _current;

  @override
  Future<LocalSongEditorState> build(String uuid) async {
    ref.onDispose(_onDispose);

    final song = await dbSongFromUuid(uuid);
    if (song == null) {
      throw Exception("Úgy tűnik, ez a dal nincs a táradban: $uuid");
    }
    final initial = LocalSongEditorState.fromSong(song);
    _current = initial;
    return initial;
  }

  void _onDispose() {
    _disposed = true;
    _debounce?.cancel();
    _linger?.cancel();

    // Flush any pending edit so a quick back navigation does not lose it.
    final current = _current;
    if (current != null && !current.deleted && _revision > _savedRevision) {
      final draft = current.draft;
      unawaited(
        _enqueue(() => updateLocalSong(draft)).then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) => log.warning(
            'Nem sikerült elmenteni a helyi dalt.',
            error,
            stackTrace,
          ),
        ),
      );
    }
  }

  bool _publishScheduled = false;

  /// Whether the widget tree is being built/unmounted right now (false in
  /// plain Dart tests, where no Flutter binding exists).
  bool get _buildingTree {
    try {
      return SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;
    } catch (_) {
      return false;
    }
  }

  /// Makes [next] the current state. The draft itself changes immediately,
  /// but while the widget tree is building or unmounting (the lyrics editor
  /// normalizes its text when it is disposed) listeners must not be notified:
  /// publishing is then deferred to a microtask.
  void _emit(LocalSongEditorState next) {
    _current = next;
    if (_disposed) return;

    if (!_buildingTree) {
      state = AsyncData(next);
      return;
    }
    if (_publishScheduled) return;
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      final latest = _current;
      if (!_disposed && latest != null) state = AsyncData(latest);
    });
  }

  /// Runs [task] after every previously queued write has finished.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// The state to edit, or null when edits are not accepted (not loaded,
  /// deleted or disposed).
  LocalSongEditorState? get _editable {
    final current = _current;
    if (_disposed || current == null || current.deleted) return null;
    return current;
  }

  void _edited(LocalSongEditorState next) {
    _closing = false;
    _revision++;
    _linger?.cancel();
    _emit(next.copyWith(status: AutosaveStatus.saving));
    _debounce?.cancel();
    _debounce = Timer(_saveDebounce, () => unawaited(_save()));
  }

  void setTitle(String title) {
    final current = _editable;
    if (current == null || current.title == title) return;
    _edited(current.copyWith(title: title));
  }

  void setLyrics(String lyrics) {
    final current = _editable;
    if (current == null || current.lyrics == lyrics) return;
    _edited(current.copyWith(lyrics: lyrics));
  }

  /// Updates one metadata field; blank values clear the key entirely.
  void setMetadataField(String apiName, Object? value) {
    final current = _editable;
    if (current == null) return;

    final cleared =
        value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is List && value.isEmpty);
    final map = Map<String, Object>.of(current.contentMap);
    if (cleared) {
      map.remove(apiName);
    } else {
      map[apiName] = value;
    }
    _edited(current.copyWith(contentMap: map));
  }

  void setKeys(List<KeyField> keys) {
    final current = _editable;
    if (current == null) return;
    _edited(current.copyWith(keyField: List.of(keys)));
  }

  /// Writes any unsaved edit right away instead of waiting for the debounce.
  /// The editor calls this when it closes, after its text fields have settled.
  void flush() {
    _closing = true;
    _linger?.cancel();
    final current = _editable;
    if (current == null || _revision == _savedRevision) return;
    _debounce?.cancel();
    unawaited(_save());
  }

  /// Saves again right away, e.g. after a failed save.
  void retrySave() {
    final current = _editable;
    if (current == null) return;
    _revision++;
    _debounce?.cancel();
    _linger?.cancel();
    _emit(current.copyWith(status: AutosaveStatus.saving));
    unawaited(_save());
  }

  Future<void> _save() => _enqueue(() async {
    final current = _editable;
    if (current == null) return;

    final revision = _revision;
    if (revision == _savedRevision) return;

    try {
      final saved = await updateLocalSong(current.draft);
      if (_disposed) return;
      if (saved == null) {
        // The song was deleted under us: nothing left to save.
        _debounce?.cancel();
        _linger?.cancel();
        _emit(_current!.copyWith(deleted: true, status: AutosaveStatus.idle));
        return;
      }
      _savedRevision = revision;
      _emit(_current!.copyWith(song: saved));
      _settleAfterWrite();
    } catch (error, stackTrace) {
      log.warning('Nem sikerült elmenteni a helyi dalt.', error, stackTrace);
      if (_disposed) return;
      _emit(_current!.copyWith(status: AutosaveStatus.error));
    }
  });

  /// After a successful write: shows the transient "saved" confirmation
  /// unless a newer edit is still waiting to be written.
  void _settleAfterWrite() {
    if (_disposed || _revision != _savedRevision) return;
    _emit(_current!.copyWith(status: AutosaveStatus.saved));
    _linger?.cancel();
    if (_closing) return;
    _linger = Timer(_savedLinger, () {
      final current = _current;
      if (_disposed || current == null) return;
      if (current.status == AutosaveStatus.saved) {
        _emit(current.copyWith(status: AutosaveStatus.upToDate));
      }
    });
  }

  /// Stores [bytes] as the song's [field] attachment (replacing any).
  Future<void> attach(String field, Uint8List bytes) => _enqueue(() async {
    if (_editable == null) return;
    try {
      final updated = await writeLocalSongAsset(
        _current!.song.uuid,
        field,
        bytes,
      );
      _adoptAttachment(updated, field);
    } catch (error, stackTrace) {
      log.warning('Nem sikerült csatolni a kottát.', error, stackTrace);
      if (_disposed) return;
      _emit(_current!.copyWith(status: AutosaveStatus.error));
    }
  });

  Future<void> removeAttachment(String field) => _enqueue(() async {
    if (_editable == null) return;
    try {
      final updated = await removeLocalSongAsset(_current!.song.uuid, field);
      _adoptAttachment(updated, field);
    } catch (error, stackTrace) {
      log.warning('Nem sikerült eltávolítani a kottát.', error, stackTrace);
      if (_disposed) return;
      _emit(_current!.copyWith(status: AutosaveStatus.error));
    }
  });

  /// Takes over the attachment reference of [field] from [updated] (the song
  /// as stored after an asset write), keeping the draft's own edits.
  void _adoptAttachment(Song updated, String field) {
    if (_disposed) return;
    final current = _current!;
    final map = Map<String, Object>.of(current.contentMap);
    final reference = updated.contentMap[field];
    if (reference == null) {
      map.remove(field);
    } else {
      map[field] = reference;
    }
    _emit(current.copyWith(song: updated, contentMap: map));
    ref.invalidate(getSongAssetProvider(updated, field));
    _settleAfterWrite();
  }

  /// Deletes the song. Edits and saves are ignored from now on; the delete
  /// itself waits for any write already in flight.
  Future<void> delete() async {
    final current = _editable;
    if (current == null) return;

    _debounce?.cancel();
    _linger?.cancel();
    _emit(current.copyWith(deleted: true, status: AutosaveStatus.idle));

    try {
      await _enqueue(() => deleteLocalSong(_current!.song));
    } catch (error, stackTrace) {
      log.warning('Nem sikerült törölni a helyi dalt.', error, stackTrace);
      if (!_disposed) {
        _emit(_current!.copyWith(deleted: false, status: AutosaveStatus.error));
      }
      rethrow;
    }
  }
}
