# App Store Connect and TestFlight Implementation

Updated: 2026-08-13

This document is the implementation ledger for Lys's Deploy workspace. Checkboxes describe code
that exists in the repository and is covered by tests or a real integration path. The Deploy UI
must never substitute sample releases, builds, testers, screenshots, or feedback when Apple data
is unavailable.

## Product boundary

- Deploy starts from an existing App Store Connect app record that the connected team can access.
- Developer enrollment, agreements, initial bundle-ID registration, certificate/account setup, and
  creation of the first app record stay outside this update-release workflow.
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

- [x] Add a `LocalDistributionTarget` separate from the Simulator-oriented `AppTarget`.
- [x] Run build-settings discovery with the Release configuration and
  `generic/platform=iOS`.
- [x] Run deployment identity discovery directly through the selected Xcode toolchain so Deploy
  does not depend on an active task runtime or agent session.
- [x] Read the Release bundle ID, product name, marketing version, build number, development team,
  signing style and identity, provisioning-profile specifier, and entitlements path.
- [ ] Read the deployment target, device families, resolved Info.plist, local app icon, symbol
  settings, and export-compliance declaration.
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
- [x] Permit an explicit app selection when automatic local identity verification is temporarily
  unavailable; only a successfully discovered, different bundle ID is treated as a mismatch.
- [ ] Persist the repository/scheme/bundle-ID to App Store app-ID binding.

### 3. Signing readiness

- [x] Detect valid local Apple Distribution identities without exposing key material.
- [x] Detect automatic versus manual signing and the selected team from Release build settings.
- [ ] Detect locally available provisioning profiles and their expiration.
- [ ] Probe cloud-managed signing/provisioning permission when a team key is connected.
- [ ] Compare local entitlements with the selected provisioning path.
- [ ] Report missing agreements or developer-account actions as external prerequisites rather than
  claiming a false machine-verified result.
- [x] Block archive when the Release target has no development team or has neither a local
  distribution identity nor explicit approval for Xcode signing updates.
- [x] Present signing blockers separately from warnings, open the selected project directly in
  Xcode, and rerun preflight without closing the upload sheet.
- [x] Present a single ordered signing-readiness checklist with direct recovery actions.
- [x] Present a protected archive/upload review with the exact source, scheme, bundle ID,
  version/build, team, signing style, local distribution identity, and actionable warnings.

### 4. Live Deploy data

- [x] Load App Store versions and submission/release status.
- [x] Load version localizations and What’s New text.
- [x] Load App Store screenshot sets and actual remote screenshots.
- [ ] Load build-upload records and processing diagnostics.
- [x] Load processed build number, marketing version, upload/expiration dates, minimum OS,
  processing state, audience, and encryption state.
- [x] Load the processed build's App Store icon when Apple exposes one and render it in Overview.
- [ ] Load richer build processing diagnostics.
- [ ] Load build bundles and file-size variants.
- [ ] Load beta build details and localized What to Test text.
- [x] Load internal and external beta groups.
- [x] Load tester counts for beta groups.
- [x] Load and display individual TestFlight tester names, email addresses, invite state, and group
  membership.
- [x] Load per-tester TestFlight sessions, crashes, and feedback for selectable 7-day, 30-day,
  90-day, and 1-year periods; keep analytics permission/errors independent from tester membership.
- [x] Load each tester's Apple-reported app devices, OS versions, and tested build versions and
  show them beside usage metrics without inventing device-name mappings.
- [ ] Load aggregate tester usage metrics grouped by beta group and build.
- [x] Load TestFlight screenshot feedback.
- [x] Preserve every image attached to TestFlight screenshot feedback, show a list thumbnail, and
  provide a full-size viewer with Copy and Save actions.
- [x] Start a source-editing task in the selected coding agent from a feedback row, carrying the
  tester comment, app/build/device/OS identifiers, screenshot URLs, and downloaded screenshots as
  ACP image blocks while keeping App Store credentials host-only.
- [x] Load TestFlight crash-feedback metadata.
- [ ] Load and symbolize TestFlight crash logs.
- [ ] Add pagination, sparse-field requests, cancellation, and background refresh.
- [ ] Persist a timestamped read-through cache and render it as stale when offline.
- [x] Never render a Simulator capture as an App Store screenshot.

### 5. Archive and upload

- [ ] Add the persistent deployment-job state machine:
  `preflight -> archiving -> inspecting -> uploading -> processing -> ready`.
- [x] Add the in-memory deployment state machine:
  `preflight -> archiving -> inspecting -> uploading -> processing -> ready`, with explicit
  failure, cancellation, accepted-but-processing, and retry states.
- [x] Archive with `xcodebuild`, Release, a generic iOS destination, and a unique explicit archive
  path under Application Support/Lys/Deployments.
- [x] Pass `-allowProvisioningUpdates` only after user approval.
- [x] Materialize the API key to a mode-0600 temporary file only for the Xcode operation and remove
  it immediately afterward.
- [x] Inspect the `.xcarchive` for its actual bundle ID, marketing version, build number, signing
  identity, team, application path, and architectures.
- [ ] Inspect and compare archived entitlements, embedded provisioning profiles, and dSYMs.
- [x] Reject local/archive/remote bundle, version, build, and signing-team mismatches before upload.
- [x] Upload with `xcodebuild -exportArchive`, `method=app-store-connect`, and
  `destination=upload`.
- [x] Keep `manageAppVersionAndBuildNumber` disabled so the reviewed identity remains exact.
- [x] Support the explicit TestFlight Internal Only option and explain its permanent restriction.
- [x] Stream bounded distribution output into the terminal surface while redacting the temporary
  authentication-key path.
- [x] Prefer actionable compiler/signing/provisioning diagnostics over Xcode's terminal
  `ARCHIVE FAILED` summary and expose the full build log from the failure state.
- [ ] Persist Xcode distribution logs and structured diagnostics.
- [x] Poll processed builds by exact marketing version/build number until ready, failed, cancelled,
  or the bounded foreground wait expires.
- [ ] Recover an in-progress processing job after Lys restarts.
- [x] Provide explicit cancellation, stop-waiting, and retry behavior.

### 6. TestFlight distribution

- [x] Add a tester to a selected beta group with an explicit email action.
- [x] Remove a tester from a selected beta group behind destructive confirmation without deleting
  the tester from the entire Apple account.
- [ ] Edit localized What to Test text.
- [x] Assign a ready build to an internal group from the protected update-release flow.
- [ ] Create and manage internal groups when permitted.
- [x] Assign a ready build to an external group from the protected update-release flow.
- [ ] Create and manage external groups when permitted.
- [x] Submit a build for TestFlight beta review as a separate explicit choice.
- [ ] Make tester notification a separate explicit choice.
- [ ] Expire a build behind destructive confirmation.
- [ ] Record every remote mutation as a deployment event.

### 7. App Store release

- [x] Create an iOS App Store update version and edit its release policy.
- [ ] Manage version localizations.
- [x] Create or update the primary-locale What's New text from the release flow.
- [x] Reserve, chunk-upload, checksum, and commit new App Store screenshots to an existing locale
  and display-type set.
- [x] Replace a committed screenshot by uploading its replacement first and deleting the old asset
  only after the new commit succeeds.
- [x] Delete an App Store screenshot behind destructive confirmation.
- [ ] Create new locale/display-type screenshot sets and poll committed assets to terminal
  `COMPLETE` or `FAILED` processing state.
- [x] Select a processed, version-matched build for the version.
- [x] Configure manual, automatic, or scheduled release.
- [x] Use Review Submissions and Review Submission Items for App Review with explicit confirmation.
- [ ] Track review, rejection, pending-release, processing, and ready-for-distribution states.
- [ ] Keep TestFlight fully usable when App Store release functionality is unavailable.

### 8. Product boundary and conditional compliance

- [x] Assume an accessible App Store Connect app already exists; do not present app-record creation
  as part of Deploy.
- [x] Keep enrollment, agreements, initial bundle-ID registration, and first app creation out of the
  update-release workflow.
- [x] Ask the build encryption question only when Apple returns no compliance determination.
- [x] Save the build's `usesNonExemptEncryption` answer through the App Store Connect API.
- [ ] Create, upload, and attach formal App Encryption Declarations when a non-exempt build requires
  supporting documentation; Apple may require legal/compliance material that the user must supply.
- [ ] Load App Review detail validation proactively (contact, demo account, notes, attachments) so
  missing fields can be corrected before Apple rejects the Review Submission request.
- [x] Manually release an approved version in Pending Developer Release from Lys with explicit
  confirmation.

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
  testers, tester usage analytics/devices, screenshots, feedback, tester membership mutations, and
  screenshot reserve/upload/commit/delete mutations.
- [ ] App Store Connect pagination and error fixtures.
- [ ] 401, 403, 409, 422, and 429 behavior.
- [ ] Keychain save/load/delete lifecycle without secret logging.
- [x] Credential-session cache proves repeated section loads perform one Keychain read per account.
- [x] SQLite connection metadata persistence.
- [ ] SQLite deployment-job persistence.
- [ ] Local build-settings normalization.
- [ ] Archive inspection and bundle/version mismatch rejection.
- [ ] Command construction with metacharacter-containing paths.
- [x] Temporary-key owner-only directory/file permissions and idempotent cleanup behavior.
- [x] Command construction preserves paths and schemes containing spaces and shell metacharacters.
- [x] Export-options fixtures verify upload destination, App Store Connect method, fixed build
  number, symbols, team, and internal-only restriction.
- [x] Archive inspection fixtures verify the identity extracted from the actual `.xcarchive`.
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
