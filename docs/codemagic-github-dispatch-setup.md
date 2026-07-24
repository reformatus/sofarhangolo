# Codemagic Setup: GitHub-triggered Mobile Builds

This file describes the configuration needed to integrate Codemagic mobile builds
into the GitHub Actions release pipeline.

**Architecture**: GitHub Actions is the **orchestrator**. When a release tag is
pushed, the `release.yml` workflow first runs analysis and tests (`verify` job).
Only after those pass does it **trigger Codemagic via the REST API**. Codemagic
builds the mobile artifacts, then its post-publish script sends a
`repository_dispatch` back to GitHub, where `release-mobile-assets.yml` attaches
the APK/IPA to the release.

This replaces the old model where Codemagic auto-triggered on every tag push,
independently of whether the GitHub-side verify step passed.

---

## Step 0 — Disable automatic tag trigger in Codemagic

Since GitHub Actions now triggers Codemagic explicitly, you must turn off the
automatic tag trigger in Codemagic so builds don't start twice.

1. Open your Codemagic app → **App settings** → **Build triggers**
2. Under **Trigger on tag**, uncheck the tag trigger (or set it to **Never**)
3. Save

> The webhook URL stays active — it's still used by Codemagic internally.
> We're only disabling the auto-trigger rule that fires on every tag push.

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


## Step 4 — Test the Codemagic → GitHub callback

1. Push a new tag (e.g., `1.2.2+1020200`) — this triggers `release.yml`
2. Watch `release.yml` — after `verify` passes, the `trigger-codemagic` job
   should start a Codemagic build
3. In Codemagic, the build should appear and complete. The post-publish script
   should log:
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

---

## Step 5 — Add Codemagic secrets to GitHub Actions

GitHub Actions needs credentials to call the Codemagic REST API. Add these to
your repository:

1. Go to **GitHub → repo Settings → Secrets and variables → Actions**
2. Add the following **Repository secrets**:

   | Secret name | Value | Where to find it |
   |---|---|---|
   | `CODEMAGIC_API_TOKEN` | Your Codemagic API token | Codemagic → Team → Personal Account → API access |

   > This secret is used by **two** workflows:
   > - `release.yml` (`trigger-codemagic` job) — to start the Codemagic build
   > - `release-mobile-assets.yml` (`Download mobile artifacts` step) — to
   >   download APK/IPA from Codemagic's artifact API

3. Add the following **Repository variables** (under the **Variables** tab):

   | Variable name | Value | Where to find it |
   |---|---|---|
   | `CODEMAGIC_APP_ID` | `6744e0650f756db2c37a8f81` | Codemagic app URL: `.../app/<APP_ID>` |
   | `CODEMAGIC_MOBILE_WORKFLOW_ID` | `6744e0650f756db2c37a8f80` | Workflow key in Codemagic app settings |

> **Note**: If these secrets/variables are not set, the `trigger-codemagic` job
> will skip gracefully (exit 0) so the release pipeline is not blocked.

---

## Architecture

```
Tag push (e.g. 1.2.1+1020100)
    │
    └──→ GitHub: release.yml starts
            │
            ├── release-context (creates GitHub release)
            │
            ├── verify (flutter analyze + flutter test)
            │       │
            │       └── (PASSES)
            │              │
            ├──────────────┤
            │              │
            ├── trigger-codemagic (NEW)
            │       │
            │       └── POST https://api.codemagic.io/builds
            │              (appId + workflowId + tag)
            │
            ├── build-linux / windows / macos / web
            │       (run in parallel with Codemagic)
            │
            └── upload-release-assets
                    (desktop + web artifacts)

Codemagic (no longer auto-triggers on tag)
    │
    └── Receives API call → starts mobile build
            │
            └── Build completes
                    │
                    └── Post-publish script runs
                            │
                            └── POST /repos/reformatus/sofarhangolo/dispatches
                                    (event_type: codemagic-build-complete,
                                     payload: tag + APK URL + IPA URL)
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

Key differences from the old model:
- **Codemagic no longer auto-triggers on tag push** — GitHub Actions is the
  single orchestrator
- **Mobile builds only start after verify passes** — no wasted Codemagic
  build minutes on broken code
- **Desktop/web builds run in parallel with mobile** — no slower overall
- **If Codemagic API token is missing, the job skips gracefully** — the
  desktop/web release still proceeds
- **Everything downstream is unchanged**: post-publish script, repository_dispatch,
  release-mobile-assets.yml all work the same way
