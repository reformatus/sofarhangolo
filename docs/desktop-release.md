# Release automation

This repository now contains GitHub Actions based release automation for:

- Windows native installer (`.exe`) plus Microsoft Store submission package (`.msix`)
- macOS native installer (`.dmg`) plus App Store Connect/TestFlight upload path (`.pkg`)
- Linux Flatpak bundle (`.flatpak`)
- mobile sidecar artifact pickup from Codemagic (`.apk`, `.ipa`) when available
- web build plus deployment to `app.sofarhangolo.hu`

## Workflow entrypoint

Use `.github/workflows/release.yml` for desktop and web release work.
Use `.github/workflows/release-mobile-assets.yml` for mobile sidecar artifact pickup from Codemagic.
Use `.github/workflows/update-product-page-downloads.yml` to publish the static downloads config consumed by the `app.sofarhangolo.hu` landing pages.

Primary trigger:

- Git tag push

Manual trigger:

- `workflow_dispatch` with an existing tag

Detailed setup instructions live in `docs/desktop-release-setup.md`.
Repository secret and variable bootstrapping can be done with `tool/configure_desktop_release_github.sh.template`.

## Secrets and variables

### Windows Store beta

Repository variables:

- `WINDOWS_STORE_APP_ID`
- `WINDOWS_STORE_BETA_FLIGHT_ID`

Repository secrets:

- `WINDOWS_STORE_TENANT_ID`
- `WINDOWS_STORE_SELLER_ID`
- `WINDOWS_STORE_CLIENT_ID`
- `WINDOWS_STORE_CLIENT_SECRET`

### macOS direct distribution

Repository secrets:

- `MACOS_DEVELOPER_ID_P12_BASE64`
- `MACOS_DEVELOPER_ID_P12_PASSWORD`
- `MACOS_DEVELOPER_ID_APPLICATION`
- `MACOS_NOTARY_API_KEY_ID`
- `MACOS_NOTARY_API_ISSUER_ID`
- `MACOS_NOTARY_API_KEY_BASE64`

### macOS App Store beta

Repository variables:

- `MACOS_APP_BUNDLE_ID`
- `MACOS_APPLE_TEAM_ID`
- `MACOS_APP_STORE_PROFILE_NAME`

Repository secrets:

- `MACOS_APP_STORE_CERTIFICATES_P12_BASE64`
- `MACOS_APP_STORE_CERTIFICATES_P12_PASSWORD`
- `MACOS_APP_STORE_PROVISIONING_PROFILE_BASE64`
- `MACOS_APP_STORE_API_KEY_ID`
- `MACOS_APP_STORE_API_ISSUER_ID`
- `MACOS_APP_STORE_API_KEY_BASE64`

### Mobile sidecar pickup

Repository variables:

- `CODEMAGIC_APP_ID`
- `CODEMAGIC_MOBILE_WORKFLOW_ID`

Repository secrets:

- `CODEMAGIC_API_TOKEN`

## Store-specific notes

- Windows beta publishing uses Microsoft Store flights via the Microsoft Store Developer CLI.
- macOS beta publishing uploads the exported App Store package to App Store Connect. Processing and tester distribution remain controlled in App Store Connect.
- Mobile release assets are built in Codemagic and attached by GitHub Actions after the matching tagged mobile build finishes.
