# Desktop Release Setup Runbook

This runbook covers the remaining manual setup needed to make `.github/workflows/release.yml` publish tagged release builds from GitHub Actions.

Use the exact repository secret and variable names listed here. The workflow already expects them.

## GitHub repository setup

Add secrets and variables in the repository that will run releases:

- `Settings -> Secrets and variables -> Actions`

GitHub documentation:

- Repository secrets: <https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets>
- Repository variables: <https://docs.github.com/en/actions/concepts/workflows-and-actions/variables>

A template script for populating these values with `gh` lives at `tool/configure_desktop_release_github.sh.template`.

## Windows

The Windows release job builds:

- a native installer `.exe`
- a Microsoft Store `.msix`
- a beta flight submission when Store credentials are present

### 1. Create or confirm the Partner Center app

You need a Microsoft Partner Center developer account and a reserved app/product.

Useful docs:

- Getting started with app publishing: <https://learn.microsoft.com/en-us/windows/apps/publish/get-started>
- View app identity details: <https://learn.microsoft.com/en-us/windows/apps/publish/view-app-identity-details>

### 2. Publish one standard Store submission manually

Package flights are only available after the app already has a regular Store submission.

Flight docs:

- <https://learn.microsoft.com/en-us/windows/apps/publish/package-flights>

### 3. Create the beta flight

In Partner Center:

- open the app
- go to `Package flights`
- create a new flight
- create at least one tester audience/group for it

The workflow submits to that flight, not to production.

### 4. Collect the two GitHub variables

Set these repository variables:

- `WINDOWS_STORE_APP_ID`
- `WINDOWS_STORE_BETA_FLIGHT_ID`

Where to get them:

- `WINDOWS_STORE_APP_ID`: the Store product ID / Store ID from the app identity page in Partner Center
- `WINDOWS_STORE_BETA_FLIGHT_ID`: the flight GUID for the beta flight

Relevant docs:

- Product identity: <https://learn.microsoft.com/en-us/windows/apps/publish/view-app-identity-details>
- Flight retrieval API reference: <https://learn.microsoft.com/en-us/windows/uwp/monetize/get-a-flight>

### 5. Collect seller and tenant information

In Partner Center:

- open `Settings -> Account settings`
- copy the `Seller ID`
- note which Microsoft Entra tenant is associated with the account

You will need:

- `WINDOWS_STORE_SELLER_ID`
- `WINDOWS_STORE_TENANT_ID`

Reference:

- <https://learn.microsoft.com/en-us/partner-center/marketplace-offers/manage-account-settings-and-profile>

### 6. Create a Microsoft Entra application for automation

In Partner Center:

- open `Account settings -> User management -> Microsoft Entra applications`
- create a new Entra application for Partner Center automation

After that, in Microsoft Entra / Azure:

- open the app registration
- copy the Application (client) ID
- copy the Directory (tenant) ID

You will need:

- `WINDOWS_STORE_CLIENT_ID`
- `WINDOWS_STORE_TENANT_ID`

Reference:

- <https://learn.microsoft.com/en-us/partner-center/marketplace-offers/manage-account-settings-and-profile>

### 7. Create the client secret

In Microsoft Entra:

- open `App registrations -> your app -> Certificates & secrets`
- create a new client secret
- copy the secret value immediately

You will need:

- `WINDOWS_STORE_CLIENT_SECRET`

Reference:

- <https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal>

### 8. Add the Windows values to GitHub

Repository variables:

- `WINDOWS_STORE_APP_ID`
- `WINDOWS_STORE_BETA_FLIGHT_ID`

Repository secrets:

- `WINDOWS_STORE_TENANT_ID`
- `WINDOWS_STORE_SELLER_ID`
- `WINDOWS_STORE_CLIENT_ID`
- `WINDOWS_STORE_CLIENT_SECRET`

### Windows notes

- `WINDOWS_STORE_APP_ID` is named as an app ID in the workflow, but the value should be the Partner Center product/store identifier.
- The workflow uses Microsoft Store Developer CLI and the `msix` Flutter package for packaging.

References:

- Microsoft Store Developer CLI overview: <https://learn.microsoft.com/en-us/windows/apps/publish/msstore-dev-cli/overview>
- Flutter Windows deployment: <https://docs.flutter.dev/deployment/windows>
- `msix` package: <https://pub.dev/packages/msix>

## macOS

The macOS release job has two independent publishing paths:

- direct distribution: sign the `.app`, build a `.dmg`, notarize it
- App Store beta: archive/export a signed `.pkg`, upload it to App Store Connect

You can enable either path independently by providing only the required credentials for that path.

## macOS direct distribution

### 1. Confirm Apple Developer Program access

Developer ID signing requires an active Apple Developer Program membership.

Reference:

- <https://developer.apple.com/help/account/certificates/create-developer-id-certificates>

### 2. Create a Developer ID Application certificate

In Apple Developer:

- open `Certificates, Identifiers & Profiles`
- create a new certificate
- choose `Developer ID Application`

Reference:

- <https://developer.apple.com/help/account/certificates/create-developer-id-certificates>

### 3. Install and export the certificate as `.p12`

On a Mac:

- download the generated certificate
- import it into Keychain Access
- confirm the private key is attached to the certificate identity
- export the identity as a `.p12`

You will need:

- the `.p12` file contents encoded as Base64
- the export password used during `.p12` export

References:

- Keychain import/export: <https://support.apple.com/guide/keychain-access/import-and-export-keychain-items-kyca35961/mac>
- Apple certificate export example: <https://developer.apple.com/help/account/configure-app-capabilities/communicate-with-apns-using-a-tls-certificate>

### 4. Find the exact signing identity name

The workflow needs the full certificate common name, typically in this format:

`Developer ID Application: Your Company Name (TEAMID)`

Store that exact value in:

- `MACOS_DEVELOPER_ID_APPLICATION`

### 4a. Keep direct-distribution entitlements aligned

The direct-distribution signing step uses `macos/Runner/DirectDistribution.entitlements`.

If the universal-link host changes, update this file and verify the signed app contains the expected `Associated Domains` entitlement.

### 5. Create an App Store Connect API key for notarization

In App Store Connect:

- confirm API access is enabled for the organization
- open `Users and Access -> Integrations -> Team Keys`
- generate a new API key
- download the `.p8` key file immediately

You will need:

- `MACOS_NOTARY_API_KEY_ID`
- `MACOS_NOTARY_API_ISSUER_ID`
- `MACOS_NOTARY_API_KEY_BASE64`

Reference:

- <https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api>

### 5a. Refresh App Store capabilities if universal-link domains change

The App Store signing path uses `macos/Runner/Release.entitlements`.

If a domain change introduces archive or export signing failures, refresh the app identifier capability and regenerate the provisioning profile before retrying the release workflow.

### 6. Encode the binary files for GitHub secrets

The workflow expects Base64-encoded contents for binary files.

On Linux:

```bash
base64 -w 0 developer-id.p12 > developer-id.p12.base64
base64 -w 0 AuthKey_ABC123XYZ.p8 > AuthKey_ABC123XYZ.p8.base64
```

On macOS:

```bash
base64 < developer-id.p12 | tr -d '\n' > developer-id.p12.base64
base64 < AuthKey_ABC123XYZ.p8 | tr -d '\n' > AuthKey_ABC123XYZ.p8.base64
```

Reference:

- <https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets>

### 7. Add the direct-distribution secrets to GitHub

Repository secrets:

- `MACOS_DEVELOPER_ID_P12_BASE64`
- `MACOS_DEVELOPER_ID_P12_PASSWORD`
- `MACOS_DEVELOPER_ID_APPLICATION`
- `MACOS_NOTARY_API_KEY_ID`
- `MACOS_NOTARY_API_ISSUER_ID`
- `MACOS_NOTARY_API_KEY_BASE64`

## macOS App Store beta

### 1. Create or confirm the app bundle ID

In Apple Developer:

- open `Certificates, Identifiers & Profiles -> Identifiers`
- create an explicit App ID for the macOS app if one does not exist already

You will need:

- `MACOS_APP_BUNDLE_ID`

Reference:

- <https://developer.apple.com/help/account/identifiers/register-an-app-id>

### 2. Create the App Store Connect app record

In App Store Connect:

- open `Apps`
- create a new app
- choose `macOS`
- select the bundle ID created above

Reference:

- <https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app>

### 3. Record the Apple Team ID

You will need the 10-character Apple Team ID for the signing/export configuration.

Store it as:

- `MACOS_APPLE_TEAM_ID`

Reference:

- <https://developer.apple.com/help/glossary/team-id/>

### 4. Create the App Store signing certificate

For App Store distribution, create an Apple distribution certificate and install it on a Mac.

Reference:

- <https://developer.apple.com/help/account/certificates/certificates-overview>

### 5. Export the signing certificate as `.p12`

Using Keychain Access:

- export the certificate identity and private key as `.p12`
- keep the export password

You will need:

- `MACOS_APP_STORE_CERTIFICATES_P12_BASE64`
- `MACOS_APP_STORE_CERTIFICATES_P12_PASSWORD`

### 6. Create the App Store provisioning profile

In Apple Developer:

- open `Certificates, Identifiers & Profiles -> Profiles`
- create a new `Mac App Store Connect` provisioning profile
- select the explicit app ID
- select the distribution certificate
- name the profile
- download the `.provisionprofile`

You will need:

- `MACOS_APP_STORE_PROFILE_NAME`
- `MACOS_APP_STORE_PROVISIONING_PROFILE_BASE64`

Reference:

- <https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile>

### 7. Create or reuse an App Store Connect API key for upload

In App Store Connect:

- open `Users and Access -> Integrations -> Team Keys`
- create or reuse a key with upload permissions
- download the `.p8` key file immediately if creating a new one

You will need:

- `MACOS_APP_STORE_API_KEY_ID`
- `MACOS_APP_STORE_API_ISSUER_ID`
- `MACOS_APP_STORE_API_KEY_BASE64`

Reference:

- <https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api>

### 8. Encode the provisioning profile and API key

On Linux:

```bash
base64 -w 0 AppStore.provisionprofile > AppStore.provisionprofile.base64
base64 -w 0 AuthKey_ABC123XYZ.p8 > AuthKey_ABC123XYZ.p8.base64
```

On macOS:

```bash
base64 < AppStore.provisionprofile | tr -d '\n' > AppStore.provisionprofile.base64
base64 < AuthKey_ABC123XYZ.p8 | tr -d '\n' > AuthKey_ABC123XYZ.p8.base64
```

### 9. Add the App Store values to GitHub

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

### macOS App Store notes

- The workflow uploads the built `.pkg` to App Store Connect.
- The workflow does not yet assign processed builds to TestFlight groups.
- Internal and external tester group management still happens in App Store Connect.
- External TestFlight distribution still requires Apple review for the first external build.

References:

- TestFlight overview: <https://developer.apple.com/testflight>
- Add internal testers: <https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers>
- Invite external testers: <https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers>

## Linux / Flathub

The Linux release job builds:

- a Flatpak bundle attached to the GitHub release
- an automated Flathub beta PR when the Flathub app repository and credentials exist

### 1. Wait for the initial Flathub submission to be accepted

The app-specific Flathub repository does not exist until the submission is approved.

Reference:

- Submission guide: <https://docs.flathub.org/docs/for-app-authors/submission>

Current submission PR:

- `flathub/flathub#8289`

### 2. Accept the Flathub repository invitation

Flathub grants write access to the dedicated app repository after approval.

Make sure:

- your GitHub account has 2FA enabled
- you accept the invite promptly

Reference:

- <https://docs.flathub.org/docs/for-app-authors/submission>

### 3. Set the Flathub repository variables

Once the dedicated repository exists, add:

- `FLATHUB_REPO`
- `FLATHUB_REPO_URL`

Expected values:

- `FLATHUB_REPO`: the app repository, for example `flathub/org.lyricapp.sofar`
- `FLATHUB_REPO_URL`: the source repository that the manifest should build from, for example `https://github.com/reformatus/lyric.git`

### 4. Prepare the Flathub beta branch flow

Flathub uses branch-based channels:

- `master` for stable
- `beta` for beta

Follow the maintenance guidance before you begin automating updates to `beta`.

Reference:

- <https://docs.flathub.org/docs/for-app-authors/maintenance>

### 5. Create a deploy key for the Flathub app repository

Generate an SSH key pair dedicated to the automation:

```bash
ssh-keygen -t ed25519 -C "flathub-beta-bot" -f flathub-beta-key
```

Then:

- add `flathub-beta-key.pub` as a write-enabled deploy key on the Flathub app repository
- store the private key contents in GitHub as `FLATHUB_REPO_DEPLOY_KEY`

### 6. Create a token for pull request automation

Create a GitHub token that can open PRs against the Flathub app repository and store it as:

- `FLATHUB_REPO_TOKEN`

### 7. Add the Flathub values to GitHub

Repository variables:

- `FLATHUB_REPO`
- `FLATHUB_REPO_URL`

Repository secrets:

- `FLATHUB_REPO_DEPLOY_KEY`
- `FLATHUB_REPO_TOKEN`

### Linux notes

- The workflow renders the manifest and opens or updates a PR in the Flathub app repository.
- It does not force direct release pushes into Flathub protected branches.
- Native Linux release artifacts are still attached to the GitHub release as `.flatpak` bundles.

References:

- Submission guide: <https://docs.flathub.org/docs/for-app-authors/submission>
- Maintenance guide: <https://docs.flathub.org/docs/for-app-authors/maintenance>
- Linter guide: <https://docs.flathub.org/docs/for-app-authors/linter>
- GitHub Action used for Flatpak builds: <https://github.com/flatpak/flatpak-github-actions>

## Final checklist

Windows variables:

- `WINDOWS_STORE_APP_ID`
- `WINDOWS_STORE_BETA_FLIGHT_ID`

Windows secrets:

- `WINDOWS_STORE_TENANT_ID`
- `WINDOWS_STORE_SELLER_ID`
- `WINDOWS_STORE_CLIENT_ID`
- `WINDOWS_STORE_CLIENT_SECRET`

macOS direct-distribution secrets:

- `MACOS_DEVELOPER_ID_P12_BASE64`
- `MACOS_DEVELOPER_ID_P12_PASSWORD`
- `MACOS_DEVELOPER_ID_APPLICATION`
- `MACOS_NOTARY_API_KEY_ID`
- `MACOS_NOTARY_API_ISSUER_ID`
- `MACOS_NOTARY_API_KEY_BASE64`

macOS App Store variables:

- `MACOS_APP_BUNDLE_ID`
- `MACOS_APPLE_TEAM_ID`
- `MACOS_APP_STORE_PROFILE_NAME`

macOS App Store secrets:

- `MACOS_APP_STORE_CERTIFICATES_P12_BASE64`
- `MACOS_APP_STORE_CERTIFICATES_P12_PASSWORD`
- `MACOS_APP_STORE_PROVISIONING_PROFILE_BASE64`
- `MACOS_APP_STORE_API_KEY_ID`
- `MACOS_APP_STORE_API_ISSUER_ID`
- `MACOS_APP_STORE_API_KEY_BASE64`

Flathub variables:

- `FLATHUB_REPO`
- `FLATHUB_REPO_URL`

Flathub secrets:

- `FLATHUB_REPO_DEPLOY_KEY`
- `FLATHUB_REPO_TOKEN`
