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

### 2026-11-05 — Song bundle file (v1): format and import choices
- **Format:** a zip (`.sofar`, constant `songBundleExtension`) with
  `manifest.json` (`format: "sofarhangolo.songs"`, `version: 1`, `songs`,
  `cue`) and `assets/<md5>` (deduplicated). A song entry has uuid, title,
  lyrics, lyricsFormat, keyField (DB string encoding), contentMap (attachment
  values are md5s), checkpoints and `origin` (`bankSongUuid`,
  `bankContentHash`, `bankUuid`) from its `localCopyOf` link. The current hash
  and sourceBank are never sent. Only local-bank songs are exported; bank
  songs in a cue are referenced by uuid. Export first checkpoints every
  exported song. Reading: unknown format / newer version / malformed are typed
  errors; an attachment whose md5 does not match is dropped from its song and
  reported, the rest imports.
- **Plan, then apply:** planning writes nothing; applying runs in one
  transaction and re-classifies each song inside it, so a database that
  changed after planning is still handled correctly.
- **Choices:** conflict: overwrite / keepBoth; sibling: replace / keepBoth.
  A missing choice means keepBoth (never destructive).
- **Several local copies of the same bank song (sibling):** one with identical
  content wins (no-op); otherwise the oldest copy (lowest link id) is offered.
- **Replace keeps my uuid** (my cues stay valid). Cue slides of the imported
  cue that point at the incoming uuid are remapped to my uuid (replace,
  identical sibling) or to the fresh uuid (keepBoth).
- **Keep both:** the incoming song keeps its title unchanged (a suffix would
  change its hash and break checkpoint matching later), gets a fresh uuid, its
  origin link and a `importedCopyOf` link (new last `SongLinkType` value, stored
  as an int: no schema change) to the uuid it had in the file.
- **Checkpoints on receive:** new/keep-both: incoming list + incoming hash;
  replace: mine, then incoming entries I lack, then incoming hash; identical /
  stale / identical sibling: mine plus incoming entries I lack. Capped at 50.
- **Cue with an existing uuid:** `CueImportChoice` overwrite / keepBoth (fresh
  cue uuid, the default) / skip.
- **Origin link without the bank song:** the link is imported as is, so if the
  recipient lacks that bank song the editor's original card reports "missing".
  That is misleading for an imported song; suggest a distinct "bank song not
  installed" state (e.g. mark imported links with `note`) when the UI step
  touches it.

### 2026-11-05 — Sharing and importing song files: UI choices
- **Local songs have no link or QR code.** The share dialog for a local song
  shows only "Megosztás fájlként" (and the existing "Kotta" tab); a link or
  code that opens nothing on the recipient's device is worse than none.
  `showShareDialog` takes a nullable `sharedLink` and an optional
  `ShareFileOption`. The local song editor has no share button: it would
  export the database copy while an autosave may still be pending; the song
  page (one step back) has the share button.
- **Cues keep the link** (bank songs resolve by uuid) and gain a file button
  with a one-line reason when the cue has local-bank song slides
  (`cueLocalSongUuids`). The file holds the cue and those songs.
- **File handover:** mobile uses the system share sheet; desktop (incl.
  Linux, where the share sheet does not exist) and web use
  `FilePicker.saveFile` (save dialog / browser download).
- **Import lives where things are managed:** a small button above "Új dal"
  on the songs page and an app bar button on "Listáim". Both call
  `pickAndImportSongBundle`, which ends in the reusable
  `importSongBundleFromBytes(context, ref, bytes)` (future OS "open with").
  Mobile pickers accept any file (an unknown extension is unreliable there);
  the bundle check rejects non-bundles.
- **Choices:** one dialog for all clashing songs plus an existing cue,
  defaulting to keep both; Cancel writes nothing. A single imported song is
  opened, an imported cue is opened (an overwritten active cue is reloaded).
- **Original status:** the origin link of an imported song gets
  `note = importedOriginLinkNote`. If its bank song is not here the status is
  `notInstalled` (no card), not `missing` ("removed"). It turns into
  `unchanged`/`changed` once the bank song is present. A later deletion of that
  bank song is not distinguishable and also shows nothing.
