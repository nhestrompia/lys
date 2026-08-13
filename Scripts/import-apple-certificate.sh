#!/bin/sh
set -eu

: "${APPLE_DEVELOPER_ID_CERTIFICATE_BASE64:?Missing certificate secret}"
: "${APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD:?Missing certificate password secret}"
: "${APPLE_KEYCHAIN_PASSWORD:?Missing temporary keychain password secret}"

runner_temp="${RUNNER_TEMP:-${TMPDIR:-/private/tmp}}"
certificate_path="$runner_temp/lys-developer-id.p12"
keychain_path="$runner_temp/lys-signing.keychain-db"

printf '%s' "$APPLE_DEVELOPER_ID_CERTIFICATE_BASE64" | base64 --decode > "$certificate_path"
security create-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$APPLE_KEYCHAIN_PASSWORD" "$keychain_path"
security import "$certificate_path" -P "$APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD" \
  -A -t cert -f pkcs12 -k "$keychain_path"
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$APPLE_KEYCHAIN_PASSWORD" "$keychain_path"
security list-keychains -d user -s "$keychain_path"
security find-identity -v -p codesigning "$keychain_path"

rm -f "$certificate_path"
