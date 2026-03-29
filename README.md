# Sófár Hangoló

## [Homepage](https://app.sofarkotta.hu/)

#### How to build

1. Install the latest [Flutter SDK](https://docs.flutter.dev/get-started/install)
1. Clone this repository
1. Run `flutter pub get` to install dependencies
1. Run `dart run build_runner build` for generated code (drift, riverpod)
1. Run `flutter run` to build and run the app

#### Flutter web

1. Run `dart run tool/prepare_web.dart` to generate Drift's web worker and copy `sqlite3.wasm`
1. Run `flutter run -d chrome` for local web development
1. Run `flutter build web --release --base-href /web/` to build the production bundle used by Pages
1. Run `dart run tool/finalize_web_build.dart` to copy Drift's generated runtime files into `build/web`

#### GitHub Pages deployment

The `Deploy Web` workflow in this repository builds the Flutter web app and syncs the output to `reformatus/app.sofarkotta.hu` under `docs/web`.

Required repository secret in `reformatus/lyric`:

1. `APP_SOFARKOTTA_HU_DEPLOY_KEY`

The secret must contain the private SSH deploy key that has write access to `reformatus/app.sofarkotta.hu`.

#### Contributing

As the project and the architecture is still in the early stages, please contact us before starting any contrubutions.
We'd like to make sure you're going in the right direction before you invest time in a PR.

---

**Powered by [Lyric](https://lyricapp.org)**
