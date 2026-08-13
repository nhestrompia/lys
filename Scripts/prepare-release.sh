#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version="${1:-}"

case "$version" in
  ''|*[!0-9.]*|.*|*.)
    echo "usage: npm run release:prepare -- X.Y.Z" >&2
    exit 64
    ;;
esac

if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Release version must be stable semver X.Y.Z" >&2
  exit 64
fi

cd "$root"
npm version "$version" --workspace @lys/testkit --no-git-tag-version
npm run release:check -- "v$version"

echo "Prepared v$version. Review and commit the package metadata, then create tag v$version."
