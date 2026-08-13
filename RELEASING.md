# Releasing Lys

A stable `vX.Y.Z` tag drives three release paths:

- `@lys/testkit@X.Y.Z` is published to npm with GitHub OIDC trusted publishing.
- The Swift SDK subtree is mirrored to a dedicated repository with the same tag. Consumers resolve
  its `Lys` product and import the `Lys` module.
- An Apple-silicon `Lys-X.Y.Z-arm64.dmg` is Developer ID signed, notarized, stapled, checksummed,
  and attached to a GitHub Release.

Pull requests and `main` run `.github/workflows/ci.yml`. Tags run
`.github/workflows/release.yml`. The npm, Swift, and Mac release jobs are independent after
validation, so an Apple credential problem does not hold back either SDK release.

## One-time npm setup

An npm account must own the `@lys` organization or be granted publish access to it; an account by
itself cannot publish a package in someone else's scope.

Trusted publishing can only be configured after the package exists. Bootstrap the package once
from a trusted local machine:

```sh
npm ci
npm run build:expo-sdk
npm run check:expo-sdk
npm login
npm publish --workspace @lys/testkit --access public
```

Then open the `@lys/testkit` package settings on npm and add a GitHub Actions trusted publisher:

- Organization or user: `nhestrompia`
- Repository: `lys`
- Workflow filename: `release.yml`
- Environment: `npm`
- Allowed action: `npm publish`

Create the `npm` environment in the GitHub repository. The workflow grants only `contents: read`
and `id-token: write`; it does not need an `NPM_TOKEN`. npm trusted publishing requires a
GitHub-hosted runner, Node 22.14 or newer, and npm 11.5.1 or newer. This workflow uses Node 24.

## One-time Swift SDK setup

SwiftPM only resolves a repository's root `Package.swift`. The desktop app's root package targets
macOS 26, while `Packages/LysSwift` supports iOS 15 and macOS 13, so publishing both from the same
root would incorrectly raise the SDK deployment floor. The release flow instead mirrors only the
standalone package subtree.

Create a public target repository such as `nhestrompia/lys-swift`. It can be empty because the
workflow pushes immutable version tags, not a branch. Then create the `swift-release` GitHub
environment in this repository with:

- Repository variable `SWIFT_SDK_REPOSITORY`: `nhestrompia/lys-swift`
- Environment secret `SWIFT_SDK_RELEASE_TOKEN`: a fine-grained GitHub token with Contents read and
  write access to that target repository

`Scripts/publish-swift-sdk.sh` uses `git subtree split` to construct the standalone history and
refuses to replace a tag if it already points somewhere else. A rerun is safe when the existing tag
already points to the expected split commit.

## One-time Apple setup

Directly distributed Mac apps need an Apple Developer Program membership, a `Developer ID
Application` certificate, and App Store Connect API credentials for notarization. Create the
`apple-release` GitHub environment and add these environment secrets:

| Secret | Value |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 of the exported `.p12` certificate and private key |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting that `.p12` |
| `APPLE_KEYCHAIN_PASSWORD` | A strong throwaway password for the CI keychain |
| `APPLE_SIGNING_IDENTITY` | Full identity, such as `Developer ID Application: Name (TEAMID)` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_PRIVATE_KEY_BASE64` | Base64 of the `AuthKey_*.p8` file |

On macOS, encode the two binary/key files without copying their raw contents into the shell
history:

```sh
base64 -i DeveloperID.p12 | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

The release workflow imports the certificate into an ephemeral keychain. It uses Apple's current
`notarytool` flow and staples the accepted ticket to the DMG.

## Cut a release

Prepare the SDK version from a clean working branch:

```sh
npm ci
npm run release:prepare -- 0.4.0
npm run check:expo-sdk
swift test --package-path Packages/LysSwift
git add Packages/LysExpo/package.json package-lock.json
git commit -s -m "chore: Prepare v0.4.0"
git tag -s v0.4.0 -m "Lys v0.4.0"
git push origin main v0.4.0
```

Only stable `X.Y.Z` versions are accepted. The workflow fails before publishing if the tag,
`package.json`, and `package-lock.json` differ. A rerun skips npm publishing when that exact version
already exists, leaves a matching Swift SDK tag alone, and replaces the matching GitHub Release
assets.

## Local Mac packaging

The packaging script builds all three executables, constructs `Lys.app`, embeds SwiftPM resource
bundles and helpers, creates the `.icns`, signs nested code, and produces a compressed DMG:

```sh
LYS_VERSION=0.4.0 ./Scripts/package-macos.sh
```

Without `LYS_SIGNING_IDENTITY`, it uses ad-hoc signing for local smoke testing. For a Developer ID
build, export the full signing identity:

```sh
LYS_VERSION=0.4.0 \
LYS_SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" \
./Scripts/package-macos.sh
```

The script refuses to overwrite `dist/Lys.app` or an existing versioned DMG. Remove or archive old
local artifacts deliberately before rebuilding. To notarize a Developer ID-signed DMG locally, set
`APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and `APPLE_API_KEY_PATH`, then run:

```sh
./Scripts/notarize-macos.sh dist/Lys-0.4.0-arm64.dmg
```
