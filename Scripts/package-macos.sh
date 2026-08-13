#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version="${LYS_VERSION:-0.0.0}"
build_number="${LYS_BUILD_NUMBER:-$version}"
bundle_id="${LYS_BUNDLE_ID:-dev.lys.app}"
output_dir="${LYS_OUTPUT_DIR:-$root/dist}"
signing_identity="${LYS_SIGNING_IDENTITY:--}"
module_cache="${TMPDIR:-/private/tmp}/lys-release-module-cache"

if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "LYS_VERSION must be stable semver X.Y.Z" >&2
  exit 64
fi
if [ "$(uname -m)" != "arm64" ]; then
  echo "Lys currently ships for Apple silicon; run this script on an arm64 Mac" >&2
  exit 69
fi

final_app="$output_dir/Lys.app"
final_dmg="$output_dir/Lys-$version-arm64.dmg"
if [ -e "$final_app" ] || [ -e "$final_dmg" ]; then
  echo "Refusing to overwrite an existing release artifact in $output_dir" >&2
  exit 73
fi

stage=$(mktemp -d "${TMPDIR:-/private/tmp}/lys-package.XXXXXX")
cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT INT TERM

app="$stage/Lys.app"
dmg="$stage/Lys-$version-arm64.dmg"
mkdir -p "$output_dir" "$app/Contents/MacOS" "$app/Contents/Resources/bin"

cd "$root"
CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
  swift build -c release --disable-sandbox
bin_path=$(CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
  swift build -c release --show-bin-path --disable-sandbox)

install -m 755 "$bin_path/Lys" "$app/Contents/MacOS/Lys"
install -m 755 "$bin_path/lysd" "$app/Contents/Resources/bin/lysd"
install -m 755 "$bin_path/lys-mcp" "$app/Contents/Resources/bin/lys-mcp"

# Package resources live in the standard sealed app resource directory. Runtime helpers first
# resolve these packaged bundles, then fall back to Bundle.module for `swift run` and tests.
for resource_name in Lys_IOSDevCore.bundle Lys_IOSDevUI.bundle; do
  resource_bundle="$bin_path/$resource_name"
  if [ ! -d "$resource_bundle" ]; then
    echo "Expected SwiftPM resource bundle is missing: $resource_bundle" >&2
    exit 65
  fi
  cp -R "$resource_bundle" "$app/Contents/Resources/"
done

cp "$root/Packaging/Lys-Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

iconset="$stage/Lys.iconset"
mkdir -p "$iconset"
icon_source="$root/Sources/IOSDevApp/Resources/Brand/lys-app-icon.png"
for spec in '16 icon_16x16.png' '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
  size=${spec%% *}
  name=${spec#* }
  sips -z "$size" "$size" "$icon_source" --out "$iconset/$name" >/dev/null
done
node "$root/Scripts/create-icns.mjs" "$iconset" "$app/Contents/Resources/Lys.icns"
iconutil --convert iconset --output "$stage/verified.iconset" \
  "$app/Contents/Resources/Lys.icns"

sign_code() {
  if [ "$signing_identity" = "-" ]; then
    codesign --force --sign - "$1"
  else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$1"
  fi
}

sign_code "$app/Contents/Resources/bin/lysd"
sign_code "$app/Contents/Resources/bin/lys-mcp"
sign_code "$app/Contents/MacOS/Lys"
sign_code "$app"
codesign --verify --deep --strict --verbose=2 "$app"

dmg_stage="$stage/dmg"
mkdir -p "$dmg_stage"
cp -R "$app" "$dmg_stage/Lys.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -quiet -volname "Lys $version" -srcfolder "$dmg_stage" \
  -format UDZO -imagekey zlib-level=9 "$dmg"
if [ "$signing_identity" != "-" ]; then
  codesign --force --timestamp --sign "$signing_identity" "$dmg"
  codesign --verify --verbose=2 "$dmg"
fi

mv "$app" "$final_app"
mv "$dmg" "$final_dmg"
echo "Created $final_app"
echo "Created $final_dmg"
