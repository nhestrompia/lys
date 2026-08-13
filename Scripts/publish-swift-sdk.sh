#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tag="${1:-${GITHUB_REF_NAME:-}}"
source_ref="${GITHUB_SHA:-HEAD}"
repository="${SWIFT_SDK_REPOSITORY:-}"

if ! printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: SWIFT_SDK_REPOSITORY=OWNER/REPO $0 vX.Y.Z" >&2
  exit 64
fi
if ! printf '%s\n' "$repository" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
  echo "SWIFT_SDK_REPOSITORY must be an OWNER/REPO GitHub repository" >&2
  exit 64
fi

cd "$root"
split_sha=$(git subtree split --quiet --prefix=Packages/LysSwift "$source_ref")
remote="https://github.com/$repository.git"
remote_sha=$(git ls-remote --tags "$remote" "refs/tags/$tag" | awk 'NR == 1 { print $1 }')

if [ -n "$remote_sha" ]; then
  if [ "$remote_sha" = "$split_sha" ]; then
    echo "$repository tag $tag already points to the expected SDK commit"
    exit 0
  fi
  echo "$repository tag $tag already exists at a different commit" >&2
  exit 65
fi

git push "$remote" "$split_sha:refs/tags/$tag"
echo "Published Swift SDK $tag to $repository"
