#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: deploy_product_page_shared_config.sh <shared-config-js> <target-repo> <target-branch> <target-dir> <commit-message>" >&2
  exit 2
fi

shared_config_js="$1"
target_repo="$2"
target_branch="$3"
target_dir="$4"
commit_message="$5"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

git clone \
  --branch "$target_branch" \
  "git@github.com:${target_repo}.git" \
  "$workdir/pages-repo"

mkdir -p "$workdir/pages-repo/$target_dir"
cp "$shared_config_js" "$workdir/pages-repo/$target_dir/shared-config.js"

cd "$workdir/pages-repo"
if [[ -z "$(git status --short -- "$target_dir")" ]]; then
  echo "No product page shared config changes to deploy."
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "$target_dir/shared-config.js"
git commit -m "$commit_message"
git push origin "$target_branch"
