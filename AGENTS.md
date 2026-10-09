# AGENTS.md — Sófár Hangoló (sofarhangolo)

## Project Overview
This is a Flutter/Dart app for displaying hymns and sheet music (OpenSong format) with features like transposition, PDF/SVG rendering, and cue/playlist management. Branded as "Sófár Hangoló" but powered by the Lyric framework.

## Critical Build Commands
After any dependency changes or first clone:
```bash
flutter pub get
dart run build_runner build  # Generates *.g.dart files for Drift, Riverpod, JSON
```

Code generation is required for:
- **Drift ORM** (database tables/queries) → `database.g.dart` and `.drift` SQL files
- **Riverpod** (state management) → `*.g.dart` from `@riverpod` annotations
- **JSON serialization** (though minimal usage currently)

Run `dart fix --apply` to auto-fix linter issues (unnecessary imports, etc).

## Architecture Patterns

### Code Generation & Part Files
- **Never manually edit `.g.dart` files** - they're code-generated
- Use `part` directives strategically:
  - [router.dart](lib/router.dart) is `part of 'main.dart'` - route config lives separately but is logically part of main
  - [slide_types/song_slide.dart](lib/data/cue/slide_types/song_slide.dart) is `part of '../slide.dart'` - slide implementations extend sealed `Slide` class
  - [preferences/classes](lib/services/preferences/classes) are `part of '../preferences_parent.dart'` - preference types share parent logic

### State Management (Riverpod)
- Use `@Riverpod(keepAlive: true)` for global app state (e.g., [banks.dart](lib/services/bank/banks.dart))
- Use `@riverpod` (auto-dispose) for page-specific state
- Providers in [lib/services/](lib/services/) expose business logic; UI in [lib/ui/](lib/ui/) consumes them
- Widget pattern: `ConsumerWidget` for stateless, `ConsumerStatefulWidget` for lifecycle hooks
- State lives in providers, not widgets - see [ui/cue/session/session_provider.dart](lib/ui/cue/session/session_provider.dart) for cue session patterns

### Database (Drift)
- Single database instance: `db` global from [database.dart](lib/data/database.dart)
- Tables defined with Drift annotations: see [data/cue/cue.dart](lib/data/cue/cue.dart), [data/song/song.dart](lib/data/song/song.dart)
- Complex queries use `.drift` files (e.g., [song.drift](lib/data/song/song.drift) has FTS5 triggers)
- JSON serialization in Drift: `CueContentConverter` maps `content` column to `List<Slide>`
- Config: [build.yaml](build.yaml) enables `json1`, `fts5` SQLite modules

### Navigation (go_router)
- Router in [router.dart](lib/router.dart) part of [main.dart](lib/main.dart)
- Shell route pattern: `BaseScaffold` wraps `/home`, `/bank`, `/cues` with persistent nav
- Full-screen routes (cue presentation) bypass shell via direct `/cue/:uuid/present` routes
- Deep linking: [app_links.dart](lib/services/app_links/app_links.dart) handles `lyric://` and `https://app.sofarkotta.hu` links

### Global Constants
Access via `globals` and `constants` records in [main.dart](lib/main.dart):
- `globals.isDesktop`/`isMobile`/`isWeb` - platform checks
- `globals.dio` - shared HTTP client
- `constants.apiRoot`, `domain`, `seedColor` - app-wide config
- Responsive breakpoints: `constants.tabletFromWidth` (700), `desktopFromWidth` (1000)

## Domain Model

### Songs & Banks
- **Song**: Immutable data from bank API with `opensong` XML format, transposable via [transpose.dart](lib/data/song/transpose.dart)
- **Bank**: Remote content source (e.g., Sófár Kottatár API). Update flow:
  1. [update.dart](lib/services/bank/update.dart) fetches metadata from `${constants.apiRoot}/banks`
  2. [songs/update.dart](lib/services/songs/update.dart) downloads changed songs per bank (respects `lastUpdated` timestamps)
  3. Assets (PDFs/SVGs) lazy-loaded on demand

### Cue Session State Management (NEW ARCHITECTURE)
The active cue is managed through a single source of truth: `activeCueSessionProvider` in [session_provider.dart](lib/ui/cue/session/session_provider.dart).

**Key concepts:**
- **CueSession**: Immutable state object holding `cue`, `slides`, and `currentSlideUuid`
- **CueSource**: Abstract interface for data source (local DB or future remote). See [cue_source.dart](lib/services/cue/source/cue_source.dart)
- **Slide immutability**: All `Slide` subclasses are immutable with `copyWith()` methods
- **Debounced writes**: Slide changes update UI immediately, DB writes are debounced (300ms)

**Data flow:**
```
User action → ActiveCueSession.updateSlide() → Immediate state update → Debounced DB write
                                              ↓
                               ref.watch() triggers UI rebuild
                                              ↓
                     viewTypeForProvider/transposeStateForProvider derive from session
```

**Song-level providers in cue context:**
- `viewTypeForProvider(song, songSlide)` and `transposeStateForProvider(song, songSlide)` 
- When `songSlide != null`: Derive state FROM `activeCueSessionProvider`, route changes THROUGH it
- When `songSlide == null`: Hold independent local state (standalone song view)

**Adding slides to cues:**
- Use `addSlideToCue(slide, cue, ref: ref)` from [write_cue.dart](lib/services/cue/write_cue.dart)
- Routes through session if cue is active, otherwise writes directly to DB

### Cues (Playlists)
- **Cue**: User-created ordered list of `Slide` objects (see [cue.dart](lib/data/cue/cue.dart))
- **Slide**: Sealed class with type `SongSlide` (reference to Song + view preferences) - extensible for future slide types
- Storage: JSON in `content` column, deserialized via `CueContentConverter`
- Sharing: `importCueFromCompressedData()` in [import_from_link.dart](lib/services/cue/import_from_link.dart) handles base64-compressed cue data from deep links

### View Types & Transposition
- [ui/song/state.dart](lib/ui/song/state.dart): `SongViewType` enum (lyrics, sheet music, PDF, etc.)
- Per-slide view preferences stored in `SongSlide`, fallback to user defaults from preferences
- Transposition state managed via `TransposeStateFor` notifier (semitones + capo)

## Preferences System
Pattern: Abstract `PreferencesParentClass` in [preferences_parent.dart](lib/services/preferences/preferences_parent.dart)
- Subclasses (e.g., `GeneralPreferencesClass`) implement `fromJson`/`toJson`
- Stored in Drift `PreferenceStorage` table as JSON blobs
- Riverpod providers ([providers/general.dart](lib/services/preferences/providers/general.dart)) wrap DB access with reactive updates

## Key Service Patterns

### Async Data Loading
- Use `Stream<T>` providers for reactive DB queries (e.g., `watchAllBanks()`)
- For cue loading, use `activeCueSessionProvider` which handles async loading internally with `AsyncValue`
- In UI, use `.when()` pattern: `ref.watch(provider).when(loading: ..., error: ..., data: ...)`
- Handle `connectionState.waiting`, `hasError`, `requireData` explicitly for FutureBuilder patterns

### Logging
- Global `log` from [logger.dart](lib/data/log/logger.dart) (standard `logging` package)
- Logs stored in-memory via `logMessagesProvider` (future: persist to disk)
- Init with `initLogger(ref)` in [main.dart](lib/main.dart) to wire Riverpod

### Connectivity-Aware Updates
- [connectivity/provider.dart](lib/services/connectivity/provider.dart): `ConnectionType` enum (unlimited/mobile/offline)
- Update flows respect mobile data preferences (not yet fully implemented)

## Flutter-Specific Conventions

### Material Design
- Single `ColorScheme.fromSeed` theme (seed: `constants.seedColor`)
- Adaptive layouts via `LayoutBuilder` - check `constraints.maxWidth` against breakpoints
- Desktop: horizontal layouts, mouse interactions
- Mobile: vertical stacks, touch gestures

### Platform Checks
**Always use `globals.isDesktop`/`isMobile`** instead of direct `Platform.is*` checks (pre-computed for web safety)

### Widget Composition
- Prefer composition over inheritance (lots of small widgets in [ui/song/widgets/](lib/ui/song/widgets/))
- Separate `*Page`, `*Content`, `*Body`, `*AppBar` for readability
- Use `PreferredSizeWidget` for custom app bars

## Common Gotchas
1. **Missing generated files**: Run `dart run build_runner build` - errors about missing `.g.dart` files mean codegen hasn't run
2. **Drift schema changes**: Increment `schemaVersion` in [database.dart](lib/data/database.dart) and write migration (currently v1, no migrations yet)
3. **Part file confusion**: If editing `song_slide.dart`, changes affect `Slide` sealed class behavior - check [slide.dart](lib/data/cue/slide.dart) for context
4. **Riverpod provider families**: Use `.call(arg)` not `(arg)` when reading - e.g., `ref.watch(viewTypeForProvider(song, null))`
5. **App links**: Scheme is `lyric://`, but also handles `https://app.sofarkotta.hu` - see [app_links.dart](lib/services/app_links/app_links.dart) for routing logic

## Planned/Incomplete Features (Comments in Code)
- `// far future todo`: Long-term aspirations (cue collaboration, bank federation)
- `// TODO`: Near-term work (e.g., replace `cached_network_image` which uses sqflite)
- Current schema is v1 - no migrations exist yet (see commented `onUpgrade` in [database.dart](lib/data/database.dart))

## Testing
- Limited tests currently - [test/drift/](test/drift/) for DB schema validation
- No integration tests yet

## External Dependencies
- **OpenSong format**: Handled by `dart_opensong` package
- **Music theory**: `music_notes` for key/transposition, `chord_transposer` (custom fork) for chord rendering
- **PDF/SVG**: `pdfrx` for rendering, assets lazy-loaded from bank API
- **Deep links**: `app_links` package with manifest config in [android/](android/) and [ios/](ios/)

When implementing features, follow existing patterns in [lib/services/](lib/services/) for business logic and [lib/ui/](lib/ui/) for presentation. State flows **down** from providers to widgets; user actions flow **up** via notifier methods.

## Hot reload rule (official Flutter agent rule)

Whenever you edit a `.dart` file under `lib/`:

1. **Skip if**: the edit is outside `lib/` (e.g. `test/**`), or only affects
   comments, docstrings, or whitespace.
2. **Discover & connect**: use the `dtd` tool from the `dart` MCP server to
   find and connect to running app instances.
3. **Reload**: call `hot_reload` after UI/widget or simple method changes;
   call `hot_restart` after changes to `main()`, `initState`, global/static
   state, or fundamental logic.

## AI tooling in this repo

- **Skills**: `.agents/skills/` holds the official Flutter
  (`flutter/agent-plugins`), Dart (`dart-lang/skills`), and Google docs
  (`retrieving-developer-knowledge`) skills. They are also installed globally
  in `~/.agents/skills/`. Update by re-running the `npx skills add` commands
  from the [Flutter AI get-started guide](https://docs.flutter.dev/ai/get-started).
- **dart MCP server** (global): analyzer diagnostics, pub.dev package
  management, Dart Tooling Daemon (hot reload/restart, runtime errors, widget
  tree) — connect it to a running app with the `dtd` tool.
- **google-developer-knowledge MCP server** (global): live search over
  docs.flutter.dev, dart.dev, and API references (`search_documents`,
  `answer_query`, `get_documents`). Requires `GOOGLE_DEVELOPER_KNOWLEDGE_API_KEY`.
- **Package skills**: dependencies can ship their own skills, but they are
  **not installed automatically**. After any change to `pubspec.yaml`
  (`pub get`, `pub upgrade`, adding a package), and occasionally as the
  ecosystem grows, re-run:
  ```bash
  dart run skills@ get
  ```
  Currently none of this project's dependencies ship skills.
