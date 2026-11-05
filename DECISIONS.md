# Decisions

Append-only log of design decisions. Add new entries at the end; when a
decision is replaced, add a new entry that says so instead of editing the old
one.

## Local songs

### 2026-11-05 — Copy-to-edit, not overlays
Editing a bank song makes a local copy in the built-in local bank
(`BankAccess.local`), linked back with a `SongLinks` `localCopyOf` row that
stores the bank song's uuid and its `contentHash` at copy time. OpenSong lyrics
have no stable line identity, so overlays/merging are not attempted.

### 2026-11-05 — One owner of the song being edited
- Data layer (`lib/services/songs/write_song.dart`,
  `lib/services/assets/write_song_asset.dart`): `createLocalSong` is insert
  only; `updateLocalSong` is update only (returns null when the song is gone,
  never resurrects it) and always keeps the stored attachment references.
  Multi-statement writes run in one transaction. Functions return new `Song`s
  and never mutate the caller's; `Song.contentMap` is final.
- Editor (`lib/ui/song/edit/editor_controller.dart`): one Riverpod controller
  owns the draft, the debounced autosave, a sequential write queue, deletion
  and the flush on exit. The page only displays and wires.

### 2026-11-05 — Local attachments are named by their content
- A local song's attachment value in `contentMap` (`svg`, `pdf`) is the md5
  hex of the file's bytes: a plain string, no URI scheme, no asset uuid.
  A `contentMap` attachment value means "a file reference in the owning
  bank's namespace": remote banks use download paths, the local bank uses
  content hashes. Which one applies is decided by the song's bank, never by
  parsing the value.
- Because of that, `contentHash` needs no special casing and comes out the
  same for identical songs on every device.
- The bytes stay in the `Assets` table, one row per (song, field), owned by
  that song: no sharing between songs, no reference counting. Deleting a song
  deletes its rows. Replacing an attachment updates the row and the md5 in
  one transaction.
- Copy stores the bytes under the new song and writes the md5.
- Bank songs, the bank file cache and the "downloaded" query are unchanged.
- Local songs were never shipped: no conversion of earlier local data.
- Storage (schema 10): `Assets.sourceUrl` is nullable (local rows have none;
  the unique index on it ignores nulls). Uniqueness of (song, field) is kept
  in code only, because the bank cache can hold several URLs per (song,
  field). A md5 mismatch between bytes and `contentMap` value is logged when
  reading, the bytes are still returned. The 9->10 migration deletes local
  songs with their links and assets.
