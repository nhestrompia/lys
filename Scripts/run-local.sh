#!/bin/sh
set -eu

sdk="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk"
swiftc="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
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
