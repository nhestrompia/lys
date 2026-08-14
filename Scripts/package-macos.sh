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
mount_point=""
mounted=0
cleanup() {
  if [ "$mounted" -eq 1 ] && [ -n "$mount_point" ]; then
    hdiutil detach "$mount_point" -quiet -force >/dev/null 2>&1 || true
  fi
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
rw_dmg="$stage/Lys-rw.dmg"
mkdir -p "$dmg_stage/.background"
swift_runner=$(xcrun --find swift)
CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
  "$swift_runner" "$root/Scripts/create-installer-background.swift" \
  "$dmg_stage/.background/installer-background.png"
cp "$app/Contents/Resources/Lys.icns" "$dmg_stage/.VolumeIcon.icns"

# Build a writable image first so Finder can persist the icon positions, background, and window
# bounds in the image's .DS_Store before it is compressed for distribution.
hdiutil create -quiet -size 256m -fs HFS+ -volname "Lys" "$rw_dmg"
attach_output=$(hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg")
mounted=1
mount_point=$(printf '%s\n' "$attach_output" | awk -F '\t' '$NF ~ /^\// { print $NF; exit }')
if [ -z "$mount_point" ]; then
  echo "Could not find the mounted Lys volume" >&2
  exit 65
fi
ditto "$app" "$mount_point/Lys.app"
ln -s /Applications "$mount_point/Applications"
mkdir -p "$mount_point/.background"
cp "$dmg_stage/.background/installer-background.png" \
  "$mount_point/.background/installer-background.png"
cp "$dmg_stage/.VolumeIcon.icns" "$mount_point/.VolumeIcon.icns"

osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Lys"
    open
    delay 1
    set installerWindow to container window
    set toolbar visible of installerWindow to false
    set statusbar visible of installerWindow to false
    set bounds of installerWindow to {120, 120, 1020, 720}

    set viewOptions to icon view options of installerWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 16
    set background picture of viewOptions to file ".background:installer-background.png"

    set position of item "Lys.app" to {185, 270}
    set position of item "Applications" to {715, 270}
    close installerWindow
    open
    delay 1
    update without registering applications
    delay 2
    close container window
  end tell
end tell
APPLESCRIPT

hdiutil detach "$mount_point" -quiet
mounted=0
hdiutil convert "$rw_dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$dmg"
if [ "$signing_identity" != "-" ]; then
  codesign --force --timestamp --sign "$signing_identity" "$dmg"
  codesign --verify --verbose=2 "$dmg"
fi

mv "$app" "$final_app"
mv "$dmg" "$final_dmg"
echo "Created $final_app"
echo "Created $final_dmg"
