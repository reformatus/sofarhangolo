# Desktop release automation

This repository now contains GitHub Actions based desktop release automation for:

- Windows native installer (`.exe`) plus Microsoft Store submission package (`.msix`)
- macOS native installer (`.dmg`) plus App Store Connect/TestFlight upload path (`.pkg`)
- Linux Flatpak bundle (`.flatpak`) plus Flathub sync hooks for the beta branch

## Workflow entrypoint

Use `.github/workflows/desktop-release.yml`.

Primary trigger:

- GitHub Release `published` or `prereleased`

Manual trigger:

- `workflow_dispatch` with an existing release tag

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

### Flathub beta sync

Repository variables:

- `FLATHUB_REPO`
- `FLATHUB_REPO_URL`

Repository secrets:

- `FLATHUB_REPO_DEPLOY_KEY`
- `FLATHUB_REPO_TOKEN`

`FLATHUB_REPO` should point at the dedicated Flathub app repository once the submission has been accepted, for example `flathub/org.lyricapp.sofar`. The token must be able to open pull requests in that repository.

## Store-specific notes

- Windows beta publishing uses Microsoft Store flights via the Microsoft Store Developer CLI.
- macOS beta publishing uploads the exported App Store package to App Store Connect. Processing and tester distribution remain controlled in App Store Connect.
- Flathub beta publishing is branch-based. The workflow sync step pushes release metadata into the `beta` branch of the Flathub app repository when that repository and deploy key exist.
