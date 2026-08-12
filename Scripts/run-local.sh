#!/bin/sh
set -eu

sdk="${LYS_MACOS_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
swiftc="${LYS_SWIFTC:-$(xcrun --find swiftc)}"
frameworks="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
testing_lib="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

SDKROOT="$sdk" SWIFT_EXEC="$swiftc" CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/lys-module-cache" \
swift build --disable-sandbox \
  -Xswiftc -F -Xswiftc "$frameworks" \
  -Xlinker "-F$frameworks" \
  -Xlinker -rpath -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$testing_lib"

SDKROOT="$sdk" SWIFT_EXEC="$swiftc" CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/lys-module-cache" \
exec swift run --disable-sandbox \
  -Xswiftc -F -Xswiftc "$frameworks" \
  -Xlinker "-F$frameworks" \
  -Xlinker -rpath -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$testing_lib" \
  Lys
