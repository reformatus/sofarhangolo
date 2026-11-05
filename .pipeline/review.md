# Review rules for Sófár Hangoló

These add to the root `AGENTS.md`, which holds the binding architecture rules.

- **Text is Hungarian and hard-coded in the widgets.** New or changed user-facing text is
  correct Hungarian (accents: á é í ó ö ő ú ü ű), in the tone of the surrounding screens
  (informal "te" form, as in "Adj hozzá egy listát"). Every new string is a decision for the
  owner (a Text decision in the spec, or "Awaiting your decision").
- **Generated code is not committed** (`*.g.dart` is gitignored). A change to a Drift table,
  a `.drift` file, a `@riverpod` provider or a `@JsonSerializable` class must still build with
  `dart run build_runner build --delete-conflicting-outputs`; no generated file in the diff.
- **Database:** a table or column change bumps `schemaVersion` in `lib/data/database.dart`, adds
  a migration step and a schema snapshot under `drift_schemas/` (that folder is protected for
  pipeline agents: flag the need, don't expect the agent to write it).
- **State:** global state in `@Riverpod(keepAlive: true)` providers under `lib/services/`, page
  state in auto-dispose providers; the active cue only through `activeCueSessionProvider`
  (`lib/ui/cue/session/`), with slide changes going through the session (immutable slides,
  `copyWith`, debounced writes).
- **Platforms:** the app runs on Android, iOS, Windows, macOS, Linux and the web. Code with
  `dart:io` or platform plugins must be guarded for the web (`kIsWeb`, or `platformInfoProvider` in
  `lib/services/platform/platform_provider.dart`).
- **Layout:** the breakpoints in `lib/config/config.dart` (tablet from 700 px, desktop from
  1000 px) decide navigation and panes; a layout change must work below 700 px too.
- **Generated platform files:** `linux/flutter/generated_plugin*`, `windows/flutter/generated_plugin*`,
  `macos/Flutter/GeneratedPluginRegistrant.swift` and the like are rewritten by `flutter pub get`.
  In a change that doesn't touch `pubspec.yaml` they are noise: flag them and ask for them to be
  dropped from the diff.
- CI runs `flutter analyze --no-fatal-warnings` (warnings stay non-fatal on purpose because of
  the deprecated `custom_lint` plugin registration) and `flutter test test`.
