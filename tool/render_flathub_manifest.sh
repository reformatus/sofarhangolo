#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <template> <output> <repo-url> <tag>" >&2
  exit 1
fi

TEMPLATE="$1"
OUTPUT="$2"
REPO_URL="$3"
RELEASE_TAG="$4"

sed \
  -e "s|__REPO_URL__|${REPO_URL}|g" \
  -e "s|__RELEASE_TAG__|${RELEASE_TAG}|g" \
  "$TEMPLATE" >"$OUTPUT"
