#!/usr/bin/bash
set -euo pipefail

repo_url=${1:?usage: checkout-private.sh REPO_URL FULL_COMMIT_SHA [DEST]}
commit_sha=${2:?usage: checkout-private.sh REPO_URL FULL_COMMIT_SHA [DEST]}
dest=${3:-src}

if [[ ! "$commit_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "SOURCE_CHECKOUT_FAILURE: commit_sha must be a full 40-character SHA" >&2
  exit 2
fi

if [[ -e "$dest" ]]; then
  echo "SOURCE_CHECKOUT_FAILURE: destination already exists: $dest" >&2
  exit 2
fi

echo "Checking out private source at $commit_sha"
git clone --no-checkout --depth=1 "$repo_url" "$dest"
git -C "$dest" fetch --no-tags --depth=1 origin "$commit_sha"
git -C "$dest" checkout --detach "$commit_sha"

actual_sha=$(git -C "$dest" rev-parse HEAD)
if [[ "$actual_sha" != "${commit_sha,,}" ]]; then
  echo "SOURCE_CHECKOUT_FAILURE: checked out $actual_sha, expected ${commit_sha,,}" >&2
  exit 1
fi

echo "SOURCE_CHECKOUT_OK: $actual_sha"
