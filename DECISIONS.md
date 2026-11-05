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

### 2026-11-05 — Local songs are shared by file only
Links would grow too large. Song and cue links keep carrying uuids only;
local songs travel in an export file that also carries their attachments.

### 2026-11-05 — Received songs keep their uuid and go into the recipient's local songs
No separate read-only "received" bank (it duplicates songs on every round
trip). Conflicts are detected by hashes, see below.

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
- Copy and import store the bytes under the new song and write the md5;
  import verifies the md5 of the received bytes.
- Bank songs, the bank file cache and the "downloaded" query are unchanged.
- Local songs were never shipped: no conversion of earlier local data.
- Storage (schema 10): `Assets.sourceUrl` is nullable (local rows have none;
  the unique index on it ignores nulls). Uniqueness of (song, field) is kept
  in code only, because the bank cache can hold several URLs per (song,
  field). A md5 mismatch between bytes and `contentMap` value is logged when
  reading, the bytes are still returned. The 9->10 migration deletes local
  songs with their links and assets.

### 2026-11-05 — Song version identity: current, checkpoints, bank origin
- **Current:** `contentHash` of the song as it is now. Computed, never stored
  or sent.
- **Checkpoints:** a JSON list column on `songs` (empty for bank songs) of
  `contentHash`es recorded when the song crosses a device boundary: copy from
  bank, export, import. Never on autosave. The newest checkpoint is the
  "base". `updateLocalSong` preserves it; it is not part of `contentHash`.
  The export file carries the whole list.
- **Bank origin:** the existing `localCopyOf` link (bank song uuid, which
  survives bank updates, plus the bank `contentHash` at copy time). Carried
  in the export file.
- The export file has a format version; an unknown version always asks.

### 2026-11-05 — Receive rules
For an incoming song whose uuid I already have:

| Check | Outcome |
|---|---|
| incoming == my current | no-op; merge checkpoint lists |
| my current ∈ incoming checkpoints | built on my edits → update silently |
| incoming ∈ my checkpoints | old version I already had/sent → ignore |
| otherwise | conflict: overwrite, or keep both (incoming gets a new uuid with a link to the original; cues in the same import are remapped to it) |

For an unknown uuid whose bank origin matches one of my local copies
(independent copies of the same bank song): identical hash → no-op; else ask
"you already have your own version: keep both / replace".
