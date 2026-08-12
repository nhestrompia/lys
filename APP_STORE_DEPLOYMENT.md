# App Store Connect and TestFlight Implementation

Updated: 2026-08-12

This document is the implementation ledger for Lys's Deploy workspace. Checkboxes describe code
that exists in the repository and is covered by tests or a real integration path. The Deploy UI
must never substitute sample releases, builds, testers, screenshots, or feedback when Apple data
is unavailable.

## Product boundary

- Lys never asks for or stores an Apple Account password, app-specific password, or two-factor
  authentication code.
- Apple Account web authentication remains in App Store Connect and Xcode.
- Lys connects to the App Store Connect API with an imported API private key, Key ID, and Issuer
  ID.
- The private key is stored in Keychain. SQLite contains nonsecret connection metadata only.
- Distribution is host-owned. App Store credentials and deployment mutations are not exposed to
  coding agents, `lysd`, or `lys-mcp`.
- Uploading, assigning testers, submitting for beta review, submitting for App Review, releasing,
  and expiring builds each require an explicit user action at the appropriate boundary.

## Status

### 1. Connection foundation

- [x] Define nonsecret connection and remote-app domain models.
- [x] Store App Store Connect private keys in a dedicated Keychain service.
- [x] Read each account key from Keychain once per Lys process and reuse the validated in-memory
  credential session for refreshes, app switches, and section requests.
- [x] Validate imported PKCS#8/P-256 `.p8` keys before storing them.
- [x] Generate short-lived ES256 App Store Connect JWTs locally.
- [x] Implement a production `URLSession` App Store Connect client.
- [x] Decode Apple JSON:API app records and structured API errors.
- [x] Persist nonsecret connection metadata in SQLite.
- [x] Restore and validate the most recent connection on launch.
- [x] Add a native connection sheet and keep the connected-account entry in Settings; Deploy only
  shows the connection action while disconnected or failed.
- [x] Polish the connection sheet with persistent field labels, a compact `.p8` picker, visible
  Keychain handling, and one clear primary action.
- [x] Add a deterministic disconnected-sheet snapshot route for visual verification.
- [x] Show only live connected, loading, error, no-match, and empty states.
- [ ] Support multiple saved connections and an explicit active-connection picker.
- [ ] Support individual API keys as a read-only/read-mostly connection mode.
- [ ] Add explicit capability probes for app reads, build uploads, TestFlight administration, and
  provisioning access.
- [ ] Add connection rotation, rename, and key-replacement controls in Settings.

### 2. Local distribution discovery

- [ ] Add a `LocalDistributionTarget` separate from the Simulator-oriented `AppTarget`.
- [x] Run build-settings discovery with the Release configuration and
  `generic/platform=iOS`.
- [ ] Read bundle ID, product name, marketing version, build number, development team, signing
  style, deployment target, device families, entitlements, Info.plist, app icon, symbol settings,
  and export-compliance declaration.
- [ ] Discover extensions, App Clips, watch companions, and their bundle IDs.
- [ ] Detect whether the selected scheme has an Archive action and is shared.
- [ ] Let the user explicitly choose the deployment source: original checkout, applied branch, or
  active task worktree.
- [x] Match the local bundle ID to exactly one live App Store Connect app record, with an explicit
  accessible-app picker when automatic discovery cannot establish a unique match.
- [x] Keep a searchable active-app switcher available after selection and clear the prior app's
  data before loading the next app.
- [x] Allow app selection before a repository is open, then invalidate that choice on repository,
  project, or scheme change and rematch the Release bundle ID.
- [x] Prevent an app with a different bundle ID from replacing the project-matched app, and explain
  the mismatch at the attempted selection boundary.
- [ ] Persist the repository/scheme/bundle-ID to App Store app-ID binding.

### 3. Signing readiness

- [ ] Detect valid local Apple Distribution identities without exposing key material.
- [ ] Detect automatic versus manual signing and the selected team.
- [ ] Detect locally available provisioning profiles and their expiration.
- [ ] Probe cloud-managed signing/provisioning permission when a team key is connected.
- [ ] Compare local entitlements with the selected provisioning path.
- [ ] Report missing agreements or developer-account actions as external prerequisites rather than
  claiming a false machine-verified result.
- [ ] Present a single ordered signing-readiness checklist with direct recovery actions.

### 4. Live Deploy data

- [x] Load App Store versions and submission/release status.
- [x] Load version localizations and What’s New text.
- [x] Load App Store screenshot sets and actual remote screenshots.
- [ ] Load build-upload records and processing diagnostics.
- [x] Load processed build number, marketing version, upload/expiration dates, minimum OS,
  processing state, audience, and encryption state.
- [ ] Load processed build icons and richer processing diagnostics.
- [ ] Load build bundles and file-size variants.
- [ ] Load beta build details and localized What to Test text.
- [x] Load internal and external beta groups.
- [x] Load tester counts for beta groups.
- [x] Load and display individual TestFlight tester names, email addresses, invite state, and group
  membership.
- [ ] Load tester usage metrics for apps, groups, and builds.
- [x] Load TestFlight screenshot feedback.
- [x] Load TestFlight crash-feedback metadata.
- [ ] Load and symbolize TestFlight crash logs.
- [ ] Add pagination, sparse-field requests, cancellation, and background refresh.
- [ ] Persist a timestamped read-through cache and render it as stale when offline.
- [x] Never render a Simulator capture as an App Store screenshot.

### 5. Archive and upload

- [ ] Add the persistent deployment-job state machine:
  `preflight -> archiving -> inspecting -> uploading -> processing -> ready`.
- [ ] Archive with `xcodebuild`, Release, a generic iOS destination, and an explicit archive path.
- [ ] Pass `-allowProvisioningUpdates` only after user approval.
- [ ] Materialize the API key to a mode-0600 temporary file only for the Xcode operation and remove
  it immediately afterward.
- [ ] Inspect the `.xcarchive` for its actual bundle ID, versions, signing authorities,
  entitlements, provisioning profiles, architectures, and dSYMs.
- [ ] Reject local/remote identity mismatches before upload.
- [ ] Upload with `xcodebuild -exportArchive`, `method=app-store-connect`, and
  `destination=upload`.
- [ ] Keep `manageAppVersionAndBuildNumber` disabled so the reviewed identity remains exact.
- [ ] Support the explicit TestFlight Internal Only option.
- [ ] Stream bounded, redacted distribution output into the terminal surface.
- [ ] Persist Xcode distribution logs and structured diagnostics.
- [ ] Poll App Store Connect build uploads and processed builds until completion or failure.
- [ ] Recover an in-progress processing job after Lys restarts.
- [ ] Provide explicit cancellation and retry behavior for safe stages.

### 6. TestFlight distribution

- [x] Add a tester to a selected beta group with an explicit email action.
- [x] Remove a tester from a selected beta group behind destructive confirmation without deleting
  the tester from the entire Apple account.
- [ ] Edit localized What to Test text.
- [ ] Assign a ready build to an internal group with confirmation.
- [ ] Create and manage internal groups when permitted.
- [ ] Assign a ready build to an external group with confirmation.
- [ ] Create and manage external groups when permitted.
- [ ] Submit a build for TestFlight beta review when required.
- [ ] Make tester notification a separate explicit choice.
- [ ] Expire a build behind destructive confirmation.
- [ ] Record every remote mutation as a deployment event.

### 7. App Store release

- [ ] Create and edit App Store version metadata.
- [ ] Manage version localizations.
- [x] Reserve, chunk-upload, checksum, and commit new App Store screenshots to an existing locale
  and display-type set.
- [x] Replace a committed screenshot by uploading its replacement first and deleting the old asset
  only after the new commit succeeds.
- [x] Delete an App Store screenshot behind destructive confirmation.
- [ ] Create new locale/display-type screenshot sets and poll committed assets to terminal
  `COMPLETE` or `FAILED` processing state.
- [ ] Select a processed build for the version.
- [ ] Configure manual, automatic, or scheduled release.
- [ ] Use Review Submissions and Review Submission Items for App Review.
- [ ] Track review, rejection, pending-release, processing, and ready-for-distribution states.
- [ ] Keep TestFlight fully usable when App Store release functionality is unavailable.

## Data ownership

| Data | Owner | Persistence |
| --- | --- | --- |
| API private key | Keychain | `dev.lys.app-store-connect` service only |
| Key ID, Issuer ID, label, key kind | Lys host | SQLite |
| Repository/scheme/app binding | Lys host | SQLite |
| Remote App Store data | App Store Connect | Timestamped SQLite cache |
| Deployment jobs and events | Lys host | SQLite |
| Archives, distribution logs, export artifacts | Lys host | Application Support/Lys/Deployments |
| Apple Account session | Xcode/App Store Connect | Never read or copied by Lys |

## Required automated coverage

- [x] JWT header, claims, lifetime, and signature-shape tests.
- [x] App Store Connect request and decoding fixtures for versions, builds, groups, individual
  testers, screenshots, feedback, tester membership mutations, and screenshot reserve/upload/
  commit/delete mutations.
- [ ] App Store Connect pagination and error fixtures.
- [ ] 401, 403, 409, 422, and 429 behavior.
- [ ] Keychain save/load/delete lifecycle without secret logging.
- [x] Credential-session cache proves repeated section loads perform one Keychain read per account.
- [x] SQLite connection metadata persistence.
- [ ] SQLite deployment-job persistence.
- [ ] Local build-settings normalization.
- [ ] Archive inspection and bundle/version mismatch rejection.
- [ ] Command construction with metacharacter-containing paths.
- [ ] Temporary-key permissions and cleanup on success, failure, and cancellation.
- [ ] Deployment state-machine restart and retry behavior.
- [ ] UI snapshots for disconnected, connecting, connected, forbidden, no matching app, processing,
  failed, and ready states.
- [ ] Redacted diagnostics prove that private keys and JWTs cannot be exported.

## First usable release definition

The first TestFlight-capable release is complete when a user can connect a team API key, see the
matching live App Store app and its remote deployment data, pass a truthful local signing preflight,
archive a reviewed source tree, approve and upload an exact version/build, follow processing across
an app restart, and assign the ready build to an internal TestFlight group without exposing account
credentials to an agent or diagnostic artifact.
