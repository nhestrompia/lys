#!/bin/sh
set -eu

artifact="${1:-}"
: "${artifact:?usage: Scripts/notarize-macos.sh PATH_TO_DMG}"
: "${APPLE_API_KEY_ID:?Missing APPLE_API_KEY_ID}"
: "${APPLE_API_ISSUER_ID:?Missing APPLE_API_ISSUER_ID}"
: "${APPLE_API_KEY_PATH:?Missing APPLE_API_KEY_PATH}"

if [ ! -f "$artifact" ]; then
  echo "Notarization artifact does not exist: $artifact" >&2
  exit 66
fi

xcrun notarytool submit "$artifact" \
  --key "$APPLE_API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait
xcrun stapler staple "$artifact"
xcrun stapler validate "$artifact"
spctl --assess --type open --context context:primary-signature --verbose=2 "$artifact"

echo "Notarized and stapled $artifact"
