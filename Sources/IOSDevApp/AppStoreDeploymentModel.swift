import Foundation
import IOSDevCore

enum AppStoreDataSection: String, CaseIterable, Hashable, Sendable {
  case versions
  case builds
  case testers
  case testerAnalytics
  case screenshots
  case feedback
}

enum AppStoreDeploymentPhase: Equatable, Sendable {
  case idle
  case discoveringTarget
  case needsAppSelection
  case loading
  case loaded
  case partial
  case failed
}

enum AppStoreUploadPhase: String, CaseIterable, Sendable {
  case idle
  case preflighting
  case ready
  case archiving
  case inspecting
  case uploading
  case processing
  case uploaded
  case complete
  case failed
  case cancelled

  var isRunning: Bool {
    switch self {
    case .preflighting, .archiving, .inspecting, .uploading, .processing: true
    default: false
    }
  }
}

struct AppStoreUploadPreflight: Sendable {
  var target: LocalDistributionTarget
  var signingIdentities: [DistributionSigningIdentity]
  var sourceRoot: URL
  var warnings: [String]

  var distributionIdentities: [DistributionSigningIdentity] {
    signingIdentities.filter(\.isDistributionIdentity)
  }
}

struct AppStoreUploadOptions: Equatable, Sendable {
  var allowProvisioningUpdates = false
  var internalTestingOnly = false
  var uploadSymbols = true
}

extension AppModel {
  func prepareAppStoreForProjectIdentityChange() {
    guard appStoreConnectionPhase == .connected else { return }
    if appStoreUploadPhase.isRunning { cancelAppStoreUpload() }
    appStoreDistributionTarget = nil
    appStoreSelectedAppID = nil
    clearLoadedAppStoreData()
    appStoreDeploymentPhase = .idle
  }

  func loadAppStoreConnection() async {
    guard let appStoreMetadataStore else { return }
    do {
      guard let connection = try await appStoreMetadataStore.appStoreConnections().first else {
        appStoreConnectionPhase = .disconnected
        return
      }
      appStoreConnection = connection
      await refreshAppStoreConnection()
    } catch {
      appStoreConnectionPhase = .failed
      appStoreConnectionError = error.localizedDescription
    }
  }

  func connectAppStore(
    label: String, keyID: String, issuerID: String, privateKeyURL: URL
  ) async -> Bool {
    let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedKeyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedIssuerID = issuerID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedLabel.isEmpty else {
      appStoreConnectionError = "Give this connection a name so it is identifiable later."
      appStoreConnectionPhase = .failed
      return false
    }
    guard !normalizedKeyID.isEmpty else {
      appStoreConnectionError =
        "Enter the Key ID shown beside the team API key in App Store Connect."
      appStoreConnectionPhase = .failed
      return false
    }
    guard !normalizedIssuerID.isEmpty else {
      appStoreConnectionError = "Enter the Issuer ID from App Store Connect team keys."
      appStoreConnectionPhase = .failed
      return false
    }
    guard privateKeyURL.pathExtension.caseInsensitiveCompare("p8") == .orderedSame else {
      appStoreConnectionError = "Select the original .p8 private key downloaded from Apple."
      appStoreConnectionPhase = .failed
      return false
    }

    appStoreConnectionPhase = .connecting
    appStoreConnectionError = nil
    do {
      let hasSecurityScope = privateKeyURL.startAccessingSecurityScopedResource()
      defer { if hasSecurityScope { privateKeyURL.stopAccessingSecurityScopedResource() } }
      let privateKey = try Data(contentsOf: privateKeyURL, options: [.mappedIfSafe])
      try AppStoreCredentialStore.validate(privateKeyPEM: privateKey)
      let connection = AppStoreConnection(
        label: normalizedLabel, keyID: normalizedKeyID, issuerID: normalizedIssuerID,
        keyKind: .team)
      let client = try AppStoreConnectClient(
        connection: connection, privateKeyPEM: privateKey)
      let apps = try await client.listApps()

      try AppStoreCredentialStore.write(privateKey, connectionID: connection.id)
      do {
        guard let appStoreMetadataStore else {
          throw AppStoreConnectError.invalidConnection(
            "Lys could not open its local deployment metadata store.")
        }
        let previous = try await appStoreMetadataStore.appStoreConnections()
        try await appStoreMetadataStore.saveAppStoreConnection(connection)
        for old in previous where old.id != connection.id {
          try? AppStoreCredentialStore.delete(connectionID: old.id)
          try? await appStoreMetadataStore.deleteAppStoreConnection(id: old.id)
        }
      } catch {
        try? AppStoreCredentialStore.delete(connectionID: connection.id)
        throw error
      }
      await appStoreCredentialSession.removeAll()
      try await appStoreCredentialSession.cache(privateKey, for: connection.id)

      appStoreConnection = connection
      appStoreApps = apps
      appStoreLastSyncedAt = Date()
      appStoreConnectionPhase = .connected
      appStoreConnectionError = nil
      Task { await self.refreshAppStoreDeploymentData() }
      return true
    } catch {
      appStoreConnectionPhase = .failed
      appStoreConnectionError = error.localizedDescription
      return false
    }
  }

  func refreshAppStoreConnection() async {
    guard let connection = appStoreConnection else {
      appStoreConnectionPhase = .disconnected
      appStoreApps = []
      appStoreLastSyncedAt = nil
      return
    }
    appStoreConnectionPhase = .refreshing
    appStoreConnectionError = nil
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(
        connection: connection, privateKeyPEM: privateKey)
      let apps = try await client.listApps()
      guard appStoreConnection?.id == connection.id else { return }
      appStoreApps = apps
      appStoreLastSyncedAt = Date()
      appStoreConnectionPhase = .connected
      await refreshAppStoreDeploymentData()
    } catch {
      guard appStoreConnection?.id == connection.id else { return }
      appStoreConnectionPhase = .failed
      appStoreConnectionError = error.localizedDescription
    }
  }

  func disconnectAppStore() async {
    guard let connection = appStoreConnection else { return }
    do {
      try AppStoreCredentialStore.delete(connectionID: connection.id)
      try await appStoreMetadataStore?.deleteAppStoreConnection(id: connection.id)
      await appStoreCredentialSession.remove(connectionID: connection.id)
      appStoreConnection = nil
      appStoreApps = []
      appStoreLastSyncedAt = nil
      appStoreConnectionError = nil
      appStoreConnectionPhase = .disconnected
      resetAppStoreDeploymentData()
    } catch {
      appStoreConnectionPhase = .failed
      appStoreConnectionError = error.localizedDescription
    }
  }

  @discardableResult
  func selectAppStoreApp(_ appID: String) -> Bool {
    guard !appStoreUploadPhase.isRunning else {
      appStoreUploadError = "Stop the active archive or upload before switching apps."
      return false
    }
    guard let candidate = appStoreApps.first(where: { $0.id == appID }) else { return false }
    if let target = appStoreDistributionTarget, candidate.bundleID != target.bundleID {
      appStoreSelectionWarning =
        "\(candidate.name) uses \(candidate.bundleID), but this repository's Release target uses \(target.bundleID). The project-matched app remains selected."
      return false
    }
    guard appStoreSelectedAppID != appID else { return true }
    appStoreSelectedAppID = appID
    clearLoadedAppStoreData()
    appStoreDeploymentError = nil
    appStoreSelectionWarning = nil
    Task { await refreshAppStoreDeploymentData(discoverTarget: false) }
    return true
  }

  func selectProjectMatchedAppStoreApp() {
    appStoreSelectedAppID = nil
    clearLoadedAppStoreData()
    appStoreDeploymentError = nil
    Task { await refreshAppStoreDeploymentData(discoverTarget: true) }
  }

  func selectAppStoreVersion(_ versionID: String) {
    appStoreSelectedVersionID = versionID
    appStoreLocalizations = []
    appStoreScreenshotSets = []
    appStoreBuildIcon = nil
    appStoreSectionErrors.removeValue(forKey: .screenshots)
    Task { await loadSelectedAppStoreVersionDetails() }
  }

  func selectAppStoreBuild(_ buildID: String) {
    appStoreSelectedBuildID = buildID
    appStoreBuildIcon = nil
    Task { await loadSelectedAppStoreBuildIcon() }
  }

  func refreshAppStoreDeploymentData(discoverTarget: Bool = true) async {
    guard appStoreDeploymentPhase != .discoveringTarget,
      appStoreDeploymentPhase != .loading
    else { return }
    guard appStoreConnectionPhase == .connected, let connection = appStoreConnection else {
      resetAppStoreDeploymentData()
      return
    }

    appStoreDeploymentError = nil
    let hasProjectContext = repository != nil && selectedContainer != nil && !selectedScheme.isEmpty
    if discoverTarget && hasProjectContext {
      appStoreDeploymentPhase = .discoveringTarget
      do {
        let target = try await discoverAppStoreDistributionTarget()
        appStoreDistributionTarget = target
        let matches = appStoreApps.filter { $0.bundleID == target.bundleID }
        if matches.count == 1 {
          if let selected = selectedAppStoreApp, selected.id != matches[0].id {
            appStoreSelectionWarning =
              "Lys changed the App Store app from \(selected.name) to \(matches[0].name) because this repository's Release bundle ID is \(target.bundleID)."
            clearLoadedAppStoreData()
          }
          appStoreSelectedAppID = matches[0].id
        } else if matches.isEmpty {
          appStoreSelectedAppID = nil
          clearLoadedAppStoreData()
          appStoreDeploymentPhase = .needsAppSelection
          appStoreDeploymentError =
            "No connected App Store app matches the Release bundle ID \(target.bundleID). App selection is locked until the account has the matching app."
          return
        } else {
          appStoreSelectedAppID = nil
          clearLoadedAppStoreData()
          appStoreDeploymentPhase = .needsAppSelection
          appStoreDeploymentError =
            "Apple returned more than one app for \(target.bundleID). Choose the intended app explicitly."
          return
        }
      } catch {
        appStoreDistributionTarget = nil
        if appStoreSelectedAppID == nil {
          appStoreDeploymentPhase = .needsAppSelection
          appStoreDeploymentError =
            "Automatic Release bundle-ID matching is unavailable: \(error.localizedDescription) Choose the App Store app manually."
          return
        }
        appStoreDeploymentError =
          "Using the manually selected app because Release bundle-ID verification is unavailable: \(error.localizedDescription)"
      }
    }

    guard let app = selectedAppStoreApp else {
      appStoreDeploymentPhase = .needsAppSelection
      if !hasProjectContext, appStoreApps.count == 1, let onlyApp = appStoreApps.first {
        appStoreSelectedAppID = onlyApp.id
        await refreshAppStoreDeploymentData(discoverTarget: false)
      }
      return
    }

    appStoreDeploymentPhase = .loading
    appStoreSectionErrors = [:]
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      let appID = app.id
      let testerUsagePeriod = appStoreTesterUsagePeriod

      async let versionsResult = captureAppStoreSection {
        try await client.listAppStoreVersions(appID: appID)
      }
      async let buildsResult = captureAppStoreSection {
        try await client.listBuilds(appID: appID)
      }
      async let groupsResult = captureAppStoreSection {
        try await client.listBetaGroups(appID: appID)
      }
      async let testerUsageResult = captureAppStoreSection {
        try await client.listBetaTesterUsages(
          appID: appID, period: testerUsagePeriod)
      }
      async let screenshotFeedbackResult = captureAppStoreSection {
        try await client.listScreenshotFeedback(appID: appID)
      }
      async let crashFeedbackResult = captureAppStoreSection {
        try await client.listCrashFeedback(appID: appID)
      }

      let (versions, builds, groups, testerUsages, screenshotFeedback, crashFeedback) = await (
        versionsResult, buildsResult, groupsResult, testerUsageResult, screenshotFeedbackResult,
        crashFeedbackResult)
      guard selectedAppStoreApp?.id == appID else { return }

      appStoreVersions = versions.value ?? []
      appStoreBuilds = builds.value ?? []
      appStoreBetaGroups = groups.value ?? []
      if appStoreTesterUsagePeriod == testerUsagePeriod {
        appStoreTesterUsages = testerUsages.value ?? [:]
      }
      appStoreFeedback = ((screenshotFeedback.value ?? []) + (crashFeedback.value ?? []))
        .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
      if let error = versions.error { appStoreSectionErrors[.versions] = error }
      if let error = builds.error { appStoreSectionErrors[.builds] = error }
      if let error = groups.error { appStoreSectionErrors[.testers] = error }
      if appStoreTesterUsagePeriod == testerUsagePeriod, let error = testerUsages.error {
        appStoreSectionErrors[.testerAnalytics] = error
      }
      let feedbackErrors = [screenshotFeedback.error, crashFeedback.error].compactMap { $0 }
      if !feedbackErrors.isEmpty {
        appStoreSectionErrors[.feedback] = feedbackErrors.joined(separator: " · ")
      }

      if !appStoreVersions.contains(where: { $0.id == appStoreSelectedVersionID }) {
        appStoreSelectedVersionID = appStoreVersions.first?.id
      }
      if !appStoreBuilds.contains(where: { $0.id == appStoreSelectedBuildID }) {
        appStoreSelectedBuildID = appStoreBuilds.first?.id
      }
      await loadSelectedAppStoreVersionDetails(client: client, expectedAppID: appID)
      appStoreDeploymentLastSyncedAt = Date()
      appStoreDeploymentPhase = appStoreSectionErrors.isEmpty ? .loaded : .partial
    } catch {
      appStoreDeploymentPhase = .failed
      appStoreDeploymentError = error.localizedDescription
    }
  }

  func loadSelectedAppStoreVersionDetails() async {
    guard let connection = appStoreConnection, let appID = selectedAppStoreApp?.id else { return }
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      await loadSelectedAppStoreVersionDetails(client: client, expectedAppID: appID)
      appStoreDeploymentPhase = appStoreSectionErrors.isEmpty ? .loaded : .partial
    } catch {
      appStoreSectionErrors[.screenshots] = error.localizedDescription
      appStoreDeploymentPhase = .partial
    }
  }

  func refreshAppStoreTesterAnalytics() async {
    guard let connection = appStoreConnection, let appID = selectedAppStoreApp?.id else { return }
    let period = appStoreTesterUsagePeriod
    let requestID = UUID()
    appStoreTesterAnalyticsRequestID = requestID
    isAppStoreTesterAnalyticsLoading = true
    appStoreSectionErrors.removeValue(forKey: .testerAnalytics)
    defer {
      if appStoreTesterAnalyticsRequestID == requestID {
        isAppStoreTesterAnalyticsLoading = false
      }
    }
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      let usages = try await client.listBetaTesterUsages(appID: appID, period: period)
      guard appStoreTesterAnalyticsRequestID == requestID, selectedAppStoreApp?.id == appID,
        appStoreTesterUsagePeriod == period
      else { return }
      appStoreTesterUsages = usages
      appStoreDeploymentPhase = appStoreSectionErrors.isEmpty ? .loaded : .partial
    } catch {
      guard appStoreTesterAnalyticsRequestID == requestID, selectedAppStoreApp?.id == appID,
        appStoreTesterUsagePeriod == period
      else { return }
      appStoreTesterUsages = [:]
      appStoreSectionErrors[.testerAnalytics] = error.localizedDescription
      appStoreDeploymentPhase = .partial
    }
  }

  private func loadSelectedAppStoreBuildIcon() async {
    guard let connection = appStoreConnection, let appID = selectedAppStoreApp?.id else { return }
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      await loadSelectedAppStoreBuildIcon(client: client, expectedAppID: appID)
    } catch {
      appStoreBuildIcon = nil
    }
  }

  private func loadSelectedAppStoreBuildIcon(
    client: AppStoreConnectClient, expectedAppID: String
  ) async {
    guard let buildID = selectedAppStoreVersion?.buildID ?? selectedAppStoreBuild?.id else {
      appStoreBuildIcon = nil
      return
    }
    let icon = try? await client.listBuildIcons(buildID: buildID).first
    guard selectedAppStoreApp?.id == expectedAppID,
      buildID == (selectedAppStoreVersion?.buildID ?? selectedAppStoreBuild?.id)
    else { return }
    appStoreBuildIcon = icon
  }

  private func loadSelectedAppStoreVersionDetails(
    client: AppStoreConnectClient, expectedAppID: String
  ) async {
    guard let version = selectedAppStoreVersion else {
      appStoreLocalizations = []
      appStoreScreenshotSets = []
      appStoreBuildIcon = nil
      return
    }
    let versionID = version.id
    let preferredLocale = selectedAppStoreApp?.primaryLocale
    async let localizationResult = captureAppStoreSection {
      try await client.listVersionLocalizations(versionID: versionID)
    }
    async let screenshotResult = captureAppStoreSection {
      try await client.listScreenshotSets(
        versionID: versionID, preferredLocale: preferredLocale)
    }
    let (localizations, screenshots) = await (localizationResult, screenshotResult)
    guard selectedAppStoreApp?.id == expectedAppID, appStoreSelectedVersionID == versionID else {
      return
    }
    appStoreLocalizations = localizations.value ?? []
    appStoreScreenshotSets = screenshots.value ?? []
    await loadSelectedAppStoreBuildIcon(client: client, expectedAppID: expectedAppID)
    let errors = [localizations.error, screenshots.error].compactMap { $0 }
    if errors.isEmpty {
      appStoreSectionErrors.removeValue(forKey: .screenshots)
    } else {
      appStoreSectionErrors[.screenshots] = errors.joined(separator: " · ")
    }
  }

  @discardableResult
  func addAppStoreBetaTester(
    email: String, firstName: String, lastName: String, groupID: String
  ) async -> Bool {
    guard let connection = appStoreConnection, let appID = selectedAppStoreApp?.id else {
      return false
    }
    isAppStoreMutationInProgress = true
    appStoreMutationError = nil
    defer { isAppStoreMutationInProgress = false }
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      _ = try await client.addBetaTester(
        email: email, firstName: firstName, lastName: lastName, groupID: groupID)
      appStoreBetaGroups = try await client.listBetaGroups(appID: appID)
      return true
    } catch {
      appStoreMutationError = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func removeAppStoreBetaTester(_ testerID: String, fromGroup groupID: String) async -> Bool {
    guard let connection = appStoreConnection, let appID = selectedAppStoreApp?.id else {
      return false
    }
    isAppStoreMutationInProgress = true
    appStoreMutationError = nil
    defer { isAppStoreMutationInProgress = false }
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      try await client.removeBetaTester(testerID, fromGroup: groupID)
      appStoreBetaGroups = try await client.listBetaGroups(appID: appID)
      return true
    } catch {
      appStoreMutationError = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func addAppStoreScreenshot(fileURL: URL, toSet setID: String) async -> Bool {
    await mutateAppStoreScreenshot(fileURL: fileURL, toSet: setID, replacing: nil)
  }

  @discardableResult
  func replaceAppStoreScreenshot(
    _ screenshotID: String, with fileURL: URL, inSet setID: String
  ) async -> Bool {
    await mutateAppStoreScreenshot(fileURL: fileURL, toSet: setID, replacing: screenshotID)
  }

  @discardableResult
  func removeAppStoreScreenshot(_ screenshotID: String) async -> Bool {
    guard let connection = appStoreConnection else { return false }
    isAppStoreMutationInProgress = true
    appStoreMutationError = nil
    defer { isAppStoreMutationInProgress = false }
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      try await client.deleteScreenshot(id: screenshotID)
      await loadSelectedAppStoreVersionDetails(client: client, expectedAppID: selectedAppStoreApp?.id ?? "")
      return true
    } catch {
      appStoreMutationError = error.localizedDescription
      return false
    }
  }

  func prepareAppStoreUpload() async {
    guard !appStoreUploadPhase.isRunning else { return }
    appStoreUploadPhase = .preflighting
    appStoreUploadStatus = "Reading Release signing and version settings…"
    appStoreUploadError = nil
    appStoreUploadPreflight = nil
    appStoreUploadArchiveInspection = nil
    appStoreUploadArchiveURL = nil
    do {
      guard let app = selectedAppStoreApp else {
        throw AppStoreConnectError.invalidConnection(
          "Choose the App Store app before preparing an upload.")
      }
      guard let container = appStoreDeploymentContainer(), !selectedScheme.isEmpty else {
        throw AppStoreDistributionError.missingBuildSetting("project and shared scheme")
      }
      let resolvedPreflight: ToolchainPreflight
      if let preflight {
        resolvedPreflight = preflight
      } else {
        resolvedPreflight = await ToolchainDiscovery.preflight(
          developerDirectory: developerDirectory)
      }
      guard let xcodebuildPath = resolvedPreflight.xcodebuildPath,
        let developerPath = resolvedPreflight.developerDirectory
      else {
        throw AppStoreConnectError.invalidConnection(
          "Select a full Xcode installation in Settings before archiving.")
      }
      let sourceRoot = taskWorkspace ?? container.deletingLastPathComponent()
      let coordinator = WorkspaceOperationCoordinator(workspace: sourceRoot)
      let lease = try await coordinator.acquire(.projectDiscovery)
      defer { lease.release() }
      let discoveryRoot = appStoreDeploymentArtifactsRoot.appending(
        path: "Discovery", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(
        at: discoveryRoot, withIntermediateDirectories: true)
      async let targetResult = ToolchainDiscovery.distributionTarget(
        container: container, scheme: selectedScheme,
        xcodebuild: URL(fileURLWithPath: xcodebuildPath),
        developerDirectory: URL(fileURLWithPath: developerPath), derivedData: discoveryRoot)
      async let identitiesResult = ToolchainDiscovery.signingIdentities()
      let (target, identities) = try await (targetResult, identitiesResult)
      guard target.bundleID == app.bundleID else {
        throw AppStoreDistributionError.identityMismatch(
          expected: app.bundleID, actual: target.bundleID)
      }
      var warnings: [String] = []
      if target.developmentTeam == nil {
        warnings.append("The Release target does not declare DEVELOPMENT_TEAM.")
      }
      if identities.contains(where: \.isDistributionIdentity) == false {
        warnings.append(
          "No local Apple Distribution identity was found. Enable Xcode signing updates to let "
            + "Xcode request eligible signing assets.")
      }
      if !appStoreVersions.contains(where: { $0.versionString == target.marketingVersion }) {
        warnings.append(
          "Version \(target.marketingVersion) does not yet have an App Store version record. "
            + "The upload can still be used by TestFlight.")
      }
      if activeWorktree != nil {
        warnings.append("This archive will use the active task worktree shown below.")
      }
      appStoreUploadPreflight = .init(
        target: target, signingIdentities: identities, sourceRoot: sourceRoot, warnings: warnings)
      appStoreUploadStatus = "Review the archive identity and signing options."
      appStoreUploadPhase = .ready
    } catch {
      appStoreUploadError = error.localizedDescription
      appStoreUploadStatus = "Preflight failed"
      appStoreUploadPhase = .failed
    }
  }

  func startAppStoreUpload() {
    guard appStoreUploadPhase == .ready || appStoreUploadPhase == .failed,
      appStoreUploadPreflight != nil, appStoreUploadTask == nil
    else { return }
    let options = appStoreUploadOptions
    appStoreUploadTask = Task { [weak self] in
      guard let self else { return }
      await self.performAppStoreUpload(options: options)
    }
  }

  func cancelAppStoreUpload() {
    appStoreUploadTask?.cancel()
    Task { await cancelAppStoreDistributionCommands() }
  }

  private func performAppStoreUpload(options: AppStoreUploadOptions) async {
    defer { appStoreUploadTask = nil }
    var uploadAccepted = false
    var credentialDirectory: URL?
    do {
      let resolvedPreflight: ToolchainPreflight
      if let preflight {
        resolvedPreflight = preflight
      } else {
        resolvedPreflight = await ToolchainDiscovery.preflight(
          developerDirectory: developerDirectory)
      }
      guard let uploadPreflight = appStoreUploadPreflight,
        let connection = appStoreConnection, let app = selectedAppStoreApp,
        let issuerID = connection.issuerID,
        let xcodebuildPath = resolvedPreflight.xcodebuildPath,
        let developerPath = resolvedPreflight.developerDirectory
      else {
        throw AppStoreConnectError.invalidConnection(
          "The connection, Xcode toolchain, or upload preflight is no longer available.")
      }
      guard uploadPreflight.target.bundleID == app.bundleID else {
        throw AppStoreDistributionError.identityMismatch(
          expected: app.bundleID, actual: uploadPreflight.target.bundleID)
      }
      if uploadPreflight.distributionIdentities.isEmpty && !options.allowProvisioningUpdates {
        throw AppStoreConnectError.invalidConnection(
          "No Apple Distribution identity is installed. Enable Xcode signing updates or add the "
            + "distribution certificate in Xcode.")
      }

      let jobRoot = appStoreDeploymentArtifactsRoot.appending(
        path: UUID().uuidString, directoryHint: .isDirectory)
      let archiveURL = jobRoot.appending(path: "App.xcarchive", directoryHint: .isDirectory)
      let derivedDataURL = jobRoot.appending(path: "DerivedData", directoryHint: .isDirectory)
      let exportURL = jobRoot.appending(path: "Upload", directoryHint: .isDirectory)
      let exportOptionsURL = jobRoot.appending(path: "ExportOptions.plist")
      try FileManager.default.createDirectory(at: jobRoot, withIntermediateDirectories: true)
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let credential = try materializeAppStoreDistributionCredential(
        privateKey, jobRoot: jobRoot, connection: connection, issuerID: issuerID)
      credentialDirectory = credential.privateKeyURL.deletingLastPathComponent()
      let coordinator = WorkspaceOperationCoordinator(workspace: uploadPreflight.sourceRoot)
      let lease = try await coordinator.acquire(.archive, timeout: 60 * 60)
      defer { lease.release() }

      appStoreUploadArchiveURL = archiveURL
      appStoreUploadError = nil
      appStoreUploadPhase = .archiving
      appStoreUploadStatus = "Creating a signed Release archive…"
      let archiveCommand = AppStoreDistributionSupport.archiveCommand(
        xcodebuild: URL(fileURLWithPath: xcodebuildPath), target: uploadPreflight.target,
        archivePath: archiveURL, derivedDataPath: derivedDataURL,
        developerDirectory: URL(fileURLWithPath: developerPath),
        authentication: options.allowProvisioningUpdates ? credential : nil,
        allowProvisioningUpdates: options.allowProvisioningUpdates)
      let archiveOutcome = try await runAppStoreDistributionCommand(
        archiveCommand, credentialPath: credential.privateKeyURL.path)
      guard archiveOutcome.succeeded else {
        throw distributionStageError("Archive", outcome: archiveOutcome)
      }
      try Task.checkCancellation()

      appStoreUploadPhase = .inspecting
      appStoreUploadStatus = "Verifying the archive identity before upload…"
      let inspection = try AppStoreDistributionSupport.inspectArchive(at: archiveURL)
      try verifyArchive(
        inspection, expected: uploadPreflight.target, appBundleID: app.bundleID)
      appStoreUploadArchiveInspection = inspection
      let exportOptions = try AppStoreDistributionSupport.exportOptionsData(
        teamID: inspection.teamID ?? uploadPreflight.target.developmentTeam,
        internalTestingOnly: options.internalTestingOnly, uploadSymbols: options.uploadSymbols)
      try exportOptions.write(to: exportOptionsURL, options: .atomic)
      try Task.checkCancellation()

      appStoreUploadPhase = .uploading
      appStoreUploadStatus = "Uploading the verified archive to App Store Connect…"
      let uploadCommand = AppStoreDistributionSupport.uploadCommand(
        xcodebuild: URL(fileURLWithPath: xcodebuildPath), archivePath: archiveURL,
        exportPath: exportURL, exportOptionsPlist: exportOptionsURL,
        developerDirectory: URL(fileURLWithPath: developerPath), authentication: credential,
        allowProvisioningUpdates: options.allowProvisioningUpdates)
      let uploadOutcome = try await runAppStoreDistributionCommand(
        uploadCommand, credentialPath: credential.privateKeyURL.path)
      guard uploadOutcome.succeeded else {
        throw distributionStageError("Upload", outcome: uploadOutcome)
      }
      uploadAccepted = true
      removeCredentialDirectory(credentialDirectory)
      credentialDirectory = nil
      try Task.checkCancellation()

      appStoreUploadPhase = .processing
      appStoreUploadStatus = "Upload accepted. Waiting for Apple to process the build…"
      await followUploadedBuild(
        target: uploadPreflight.target, connection: connection, expectedAppID: app.id)
    } catch is CancellationError {
      removeCredentialDirectory(credentialDirectory)
      appStoreUploadPhase = uploadAccepted ? .uploaded : .cancelled
      appStoreUploadStatus = uploadAccepted
        ? "Upload accepted; Lys stopped waiting for processing."
        : "Archive or upload cancelled."
    } catch {
      removeCredentialDirectory(credentialDirectory)
      appStoreUploadError = error.localizedDescription
      appStoreUploadStatus = uploadAccepted ? "Upload accepted; processing check failed" : "Upload failed"
      appStoreUploadPhase = uploadAccepted ? .uploaded : .failed
    }
  }

  private func followUploadedBuild(
    target: LocalDistributionTarget, connection: AppStoreConnection, expectedAppID: String
  ) async {
    do {
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      let deadline = Date().addingTimeInterval(10 * 60)
      while !Task.isCancelled, Date() < deadline {
        try await Task.sleep(for: .seconds(15))
        let builds = try await client.listBuilds(appID: expectedAppID)
        guard selectedAppStoreApp?.id == expectedAppID else { throw CancellationError() }
        appStoreBuilds = builds
        if let build = builds.first(where: {
          $0.version == target.buildNumber && $0.marketingVersion == target.marketingVersion
        }) {
          appStoreSelectedBuildID = build.id
          if build.processingState == "VALID" {
            appStoreUploadStatus = "Build \(target.marketingVersion) (\(target.buildNumber)) is ready."
            appStoreUploadPhase = .complete
            appStoreDeploymentLastSyncedAt = Date()
            return
          }
          if ["FAILED", "INVALID"].contains(build.processingState) {
            appStoreUploadError =
              "Apple reported the uploaded build as \(build.processingState.lowercased())."
            appStoreUploadStatus = "Apple could not process the build"
            appStoreUploadPhase = .failed
            return
          }
        }
      }
      if Task.isCancelled { throw CancellationError() }
      appStoreUploadStatus = "Upload accepted; Apple is still processing the build."
      appStoreUploadPhase = .uploaded
    } catch is CancellationError {
      appStoreUploadStatus = "Upload accepted; Lys stopped waiting for processing."
      appStoreUploadPhase = .uploaded
    } catch {
      appStoreUploadError = error.localizedDescription
      appStoreUploadStatus = "Upload accepted; processing status is temporarily unavailable."
      appStoreUploadPhase = .uploaded
    }
  }

  private func materializeAppStoreDistributionCredential(
    _ privateKey: Data, jobRoot: URL, connection: AppStoreConnection, issuerID: String
  ) throws -> AppStoreDistributionAuthentication {
    let credential = try AppStoreTemporaryCredential.create(
      privateKey: privateKey, keyID: connection.keyID, in: jobRoot)
    return .init(
      privateKeyURL: credential.privateKeyURL, keyID: connection.keyID, issuerID: issuerID)
  }

  private func removeCredentialDirectory(_ directory: URL?) {
    guard let directory else { return }
    try? FileManager.default.removeItem(at: directory)
  }

  private func verifyArchive(
    _ inspection: AppStoreArchiveInspection, expected: LocalDistributionTarget,
    appBundleID: String
  ) throws {
    guard inspection.bundleID == appBundleID else {
      throw AppStoreDistributionError.identityMismatch(
        expected: appBundleID, actual: inspection.bundleID)
    }
    guard inspection.marketingVersion == expected.marketingVersion else {
      throw AppStoreDistributionError.invalidArchive(
        "version \(inspection.marketingVersion) does not match reviewed Release version "
          + "\(expected.marketingVersion).")
    }
    guard inspection.buildNumber == expected.buildNumber else {
      throw AppStoreDistributionError.invalidArchive(
        "build \(inspection.buildNumber) does not match reviewed Release build "
          + "\(expected.buildNumber).")
    }
    if let expectedTeam = expected.developmentTeam, let archiveTeam = inspection.teamID,
      expectedTeam != archiveTeam
    {
      throw AppStoreDistributionError.invalidArchive(
        "signing team \(archiveTeam) does not match Release team \(expectedTeam).")
    }
  }

  private func distributionStageError(
    _ stage: String, outcome: ProcessOutcome
  ) -> AppStoreDistributionError {
    let detail = [outcome.stderr, outcome.stdout]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? "xcodebuild exited with status \(outcome.terminationStatus)."
    return .commandFailed(stage: stage, detail: detail)
  }

  private func mutateAppStoreScreenshot(
    fileURL: URL, toSet setID: String, replacing screenshotID: String?
  ) async -> Bool {
    guard let connection = appStoreConnection, let appID = selectedAppStoreApp?.id else {
      return false
    }
    isAppStoreMutationInProgress = true
    appStoreMutationError = nil
    defer { isAppStoreMutationInProgress = false }
    do {
      let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
      defer { if hasSecurityScope { fileURL.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      let privateKey = try await appStoreCredentialSession.privateKey(for: connection.id)
      let client = try AppStoreConnectClient(connection: connection, privateKeyPEM: privateKey)
      _ = try await client.uploadScreenshot(
        data: data, fileName: fileURL.lastPathComponent, screenshotSetID: setID)
      if let screenshotID { try await client.deleteScreenshot(id: screenshotID) }
      await loadSelectedAppStoreVersionDetails(client: client, expectedAppID: appID)
      return true
    } catch {
      appStoreMutationError = error.localizedDescription
      return false
    }
  }

  private func resetAppStoreDeploymentData() {
    appStoreDistributionTarget = nil
    appStoreSelectedAppID = nil
    clearLoadedAppStoreData()
    appStoreDeploymentError = nil
    appStoreSelectionWarning = nil
    appStoreMutationError = nil
    appStoreDeploymentPhase = .idle
  }

  private func clearLoadedAppStoreData() {
    appStoreVersions = []
    appStoreBuilds = []
    appStoreBuildIcon = nil
    appStoreBetaGroups = []
    appStoreTesterUsages = [:]
    appStoreTesterAnalyticsRequestID = UUID()
    isAppStoreTesterAnalyticsLoading = false
    appStoreLocalizations = []
    appStoreScreenshotSets = []
    appStoreFeedback = []
    appStoreSelectedVersionID = nil
    appStoreSelectedBuildID = nil
    appStoreSectionErrors = [:]
    appStoreDeploymentLastSyncedAt = nil
    appStoreDeploymentPhase = .idle
    if !appStoreUploadPhase.isRunning {
      appStoreUploadPhase = .idle
      appStoreUploadPreflight = nil
      appStoreUploadStatus = ""
      appStoreUploadError = nil
      appStoreUploadArchiveInspection = nil
      appStoreUploadArchiveURL = nil
    }
  }
}

private struct AppStoreSectionResult<Value: Sendable>: Sendable {
  var value: Value?
  var error: String?
}

private func captureAppStoreSection<Value: Sendable>(
  _ operation: @escaping @Sendable () async throws -> Value
) async -> AppStoreSectionResult<Value> {
  do {
    return .init(value: try await operation(), error: nil)
  } catch {
    return .init(value: nil, error: error.localizedDescription)
  }
}
