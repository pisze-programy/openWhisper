#!/bin/bash
# Build the DMG and publish it as a GitHub Release so anyone can download it.
# Usage: ./scripts/publish-release.sh <tag>   e.g. ./scripts/publish-release.sh v1.0.0
set -euo pipefail

TAG="${1:?usage: ./scripts/publish-release.sh <tag>   e.g. v1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/make-dmg.sh

DMG="$(ls -t release/OpenWhisper-*.dmg | head -1)"
[ -n "$DMG" ] || { echo "ERROR: no DMG in release/ — make-dmg.sh failed?"; exit 1; }

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "==> Creating tag $TAG"
  git tag "$TAG"
  git push origin "$TAG"
fi

echo "==> Publishing $TAG with $DMG"
gh release create "$TAG" "$DMG" \
  --title "$TAG" \
  --notes "OpenWhisper ${TAG#v} — see the README for setup, permissions and the hotkey." \
  --repo "$REPO"

echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
