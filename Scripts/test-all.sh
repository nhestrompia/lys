#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
swift_cache="${TMPDIR:-/private/tmp}/lys-swift-module-cache"
npm_cache="${TMPDIR:-/private/tmp}/lys-npm-cache"
contract_output="${TMPDIR:-/private/tmp}/lys-consumer-contract.json"

cd "$root"
./Scripts/test-local.sh
./Scripts/smoke-binaries.sh

CLANG_MODULE_CACHE_PATH="$swift_cache" SWIFTPM_MODULECACHE_OVERRIDE="$swift_cache" \
  swift test --package-path Packages/LysSwift --disable-sandbox
ios_sdk=$(/usr/bin/xcrun --sdk iphonesimulator --show-sdk-path)
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
  -typecheck -module-name Lys -target arm64-apple-ios15.0-simulator -sdk "$ios_sdk" \
  -module-cache-path "${TMPDIR:-/private/tmp}/lys-ios-module-cache" \
  Packages/LysSwift/Sources/Lys/*.swift

tsc_path="${LYS_TSC:-}"
if [ -z "$tsc_path" ] && [ -x "$root/node_modules/.bin/tsc" ]; then
  tsc_path="$root/node_modules/.bin/tsc"
fi
if [ -z "$tsc_path" ]; then
  tsc_path=$(command -v tsc || true)
fi
if [ -z "$tsc_path" ]; then
  echo "TypeScript compiler missing. Run npm install or set LYS_TSC." >&2
  exit 1
fi
"$tsc_path" --project Packages/LysExpo/tsconfig.json --pretty false
node Packages/LysExpo/scripts/check.mjs
node Packages/LysExpo/scripts/test.mjs
npm run check:contract
npm_config_cache="$npm_cache" npm pack --dry-run --json ./Packages/LysExpo >/dev/null

CLANG_MODULE_CACHE_PATH="$swift_cache" SWIFTPM_MODULECACHE_OVERRIDE="$swift_cache" \
  swift run --package-path IntegrationTests/LysSwiftConsumer --disable-sandbox \
  LysSwiftConsumer "$contract_output"
node -e 'const fs=require("node:fs"); const value=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); if(value.flows[0].id!=="flow.finish") process.exit(1)' "$contract_output"

echo "All Lys core, SDK, package, and consumer tests passed"
