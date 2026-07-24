# Codemagic Setup: Trigger GitHub Action on Build Completion

This file contains the configuration needed on the Codemagic side to replace
the 15-minute polling loop with an event-driven `repository_dispatch`.

---

## Step 1 — Create a GitHub Personal Access Token

You need a GitHub token that Codemagic can use to call the GitHub API.

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. Click **Generate new token (classic)**
3. Give it a name like `Codemagic Mobile Dispatch`
4. Set expiration as desired (recommend: 1 year or no expiration)
5. Select scope: **`repo`** (full control of private repositories)
   - Or if using fine-grained tokens: `contents: write` on `reformatus/sofarhangolo`
6. Copy the generated token — you'll add it to Codemagic next

## Step 2 — Add Token to Codemagic

1. Open your Codemagic app: **App settings → Environment variables**
2. Add a new **secure** environment variable:
   - **Variable name**: `GITHUB_API_TOKEN`
   - **Value**: The GitHub PAT from Step 1
   - **Group**: The same group your mobile build workflow uses
3. Save

## Step 3 — Add Post-publish Script

This script runs after the build completes and artifacts are available. It sends a
`repository_dispatch` event to GitHub with the tag and artifact download URLs.

1. Open your mobile build workflow in Codemagic
2. Scroll to the **Post-publish** phase
3. Click the **+** button → **Add custom script**
4. Name it: `Notify GitHub of build completion`
5. Paste the script below:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# Post-publish script: notify GitHub that a Codemagic tag build is
# complete, passing APK and IPA download URLs so the
# release-mobile-assets workflow can attach them to the release.
# ------------------------------------------------------------------

# Only dispatch for tag builds (skip branch / PR builds)
if [[ -z "${CM_TAG:-}" ]]; then
  echo "Not a tag build – skipping GitHub dispatch."
  exit 0
fi

echo "Dispatching codemagic-build-complete for tag: ${CM_TAG}"

# ---- Collect Codemagic artifact URLs ------------------------------------
# CM_ARTIFACT_LINKS is a JSON array provided by Codemagic:
#   [{"name":"app-release.apk","url":"https://...","type":"apk"}, ...]

APK_URL=""
IPA_URL=""

if [[ -n "${CM_ARTIFACT_LINKS:-}" ]]; then
  while IFS= read -r artifact; do
    name="$(echo "${artifact}" | jq -r '.name // empty')"
    url="$(echo  "${artifact}" | jq -r '.url  // empty')"

    case "${name}" in
      *.apk) APK_URL="${url}"; echo "Found APK: ${name}" ;;
      *.ipa) IPA_URL="${url}"; echo "Found IPA: ${name}" ;;
    esac
  done < <(echo "${CM_ARTIFACT_LINKS}" | jq -c '.[]')
fi

if [[ -z "${APK_URL}" && -z "${IPA_URL}" ]]; then
  echo "No APK or IPA artifacts found – skipping dispatch."
  exit 0
fi

# ---- Build the repository_dispatch payload -------------------------------
payload="$(jq -n \
  --arg tag      "${CM_TAG}" \
  --arg apk_url  "${APK_URL}" \
  --arg ipa_url  "${IPA_URL}" \
  '{
    event_type: "codemagic-build-complete",
    client_payload: {
      tag:     $tag,
      apk_url: $apk_url,
      ipa_url: $ipa_url
    }
  }')"

# ---- Send the dispatch to GitHub ----------------------------------------
echo "Sending repository_dispatch to reformatus/sofarhangolo …"

curl -sS -X POST \
  -H "Authorization: token ${GITHUB_API_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/reformatus/sofarhangolo/dispatches" \
  -d "${payload}"

echo "Dispatch sent successfully."
```

6. Click **Save**

> **Note:** If you manage your workflow with `codemagic.yaml` instead of the
> Flutter workflow editor, add the script above under
> `publishing → scripts` in the mobile workflow definition. The same
> environment variable `GITHUB_API_TOKEN` must be present in the workflow's
> environment group.


## Step 4 — Test

1. Push a new tag (e.g., `1.2.2+1020200`) that triggers both the Codemagic mobile build
   and the main GitHub Release workflow
2. Watch Codemagic — the build should start, complete, and the post-publish script should log:
   ```
   Dispatching codemagic-build-complete for tag: 1.2.2+1020200
   Sending repository_dispatch to reformatus/sofarhangolo...
   Dispatch sent successfully.
   ```
3. On GitHub, check **Actions → Release Mobile Assets** — a new run should appear
   triggered by `repository_dispatch` (not `push`)
4. The run should:
   - Resolve the tag and artifact URLs from the payload
   - Wait for the main Release workflow to create the GitHub release
   - Download APK/IPA directly (no Codemagic API polling)
   - Attach to the release
   - Trigger the product page downloads update

## How it works

```
Tag push (e.g. 1.2.1+1020100)
    │
    ├──→ GitHub: release.yml starts
    │       ├── release-context (creates GH release)
    │       ├── verify
    │       ├── build-linux / windows / macos / web
    │       └── upload-release-assets
    │
    └──→ Codemagic: mobile build starts
            │
            └── Build completes
                    │
                    └── Post-publish script runs
                            │
                            └── POST /repos/reformatus/sofarhangolo/dispatches
                                    │
                                    └── GitHub: release-mobile-assets.yml triggered
                                            ├── attach-mobile-assets
                                            │     ├── Reads tag + URLs from payload
                                            │     ├── Waits for release to exist (up to 5 min)
                                            │     ├── Downloads APK/IPA from Codemagic CDN
                                            │     └── Attaches to GitHub release
                                            │
                                            └── trigger-product-page-downloads
                                                  ├── Waits for main Release workflow
                                                  └── Triggers update-product-page-downloads.yml
```

Key benefits:
- **No polling**: Codemagic pushes when ready, instead of GitHub pulling
- **No Codemagic API token on GitHub**: artifact URLs come directly in the payload
- **Quick**: GitHub runner time drops from ~15-20 min to ~1-2 min
- **No tag encoding issues**: tags with `+` are passed as-is in JSON payload
