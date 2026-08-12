import Foundation
import IOSDevCore

enum AppStoreDataSection: String, CaseIterable, Hashable, Sendable {
  case versions
  case builds
  case testers
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

extension AppModel {
  func prepareAppStoreForProjectIdentityChange() {
    guard appStoreConnectionPhase == .connected else { return }
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
    guard let candidate = appStoreApps.first(where: { $0.id == appID }) else { return false }
    if let target = appStoreDistributionTarget, candidate.bundleID != target.bundleID {
      appStoreSelectionWarning =
        "\(candidate.name) uses \(candidate.bundleID), but this repository's Release target uses \(target.bundleID). The project-matched app remains selected."
      return false
    }
    if repository != nil, selectedContainer != nil, !selectedScheme.isEmpty,
      appStoreDistributionTarget == nil
    {
      appStoreSelectionWarning =
        "Lys is still resolving this repository's Release bundle ID. Wait for project matching before switching apps."
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
    appStoreSectionErrors.removeValue(forKey: .screenshots)
    Task { await loadSelectedAppStoreVersionDetails() }
  }

  func selectAppStoreBuild(_ buildID: String) {
    appStoreSelectedBuildID = buildID
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
        appStoreSelectedAppID = nil
        clearLoadedAppStoreData()
        appStoreDeploymentPhase = .needsAppSelection
        appStoreDeploymentError =
          "Lys could not verify the repository's Release bundle ID: \(error.localizedDescription) App selection is paused to prevent deploying the wrong app."
        return
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

      async let versionsResult = captureAppStoreSection {
        try await client.listAppStoreVersions(appID: appID)
      }
      async let buildsResult = captureAppStoreSection {
        try await client.listBuilds(appID: appID)
      }
      async let groupsResult = captureAppStoreSection {
        try await client.listBetaGroups(appID: appID)
      }
      async let screenshotFeedbackResult = captureAppStoreSection {
        try await client.listScreenshotFeedback(appID: appID)
      }
      async let crashFeedbackResult = captureAppStoreSection {
        try await client.listCrashFeedback(appID: appID)
      }

      let (versions, builds, groups, screenshotFeedback, crashFeedback) = await (
        versionsResult, buildsResult, groupsResult, screenshotFeedbackResult, crashFeedbackResult)
      guard selectedAppStoreApp?.id == appID else { return }

      appStoreVersions = versions.value ?? []
      appStoreBuilds = builds.value ?? []
      appStoreBetaGroups = groups.value ?? []
      appStoreFeedback = ((screenshotFeedback.value ?? []) + (crashFeedback.value ?? []))
        .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
      if let error = versions.error { appStoreSectionErrors[.versions] = error }
      if let error = builds.error { appStoreSectionErrors[.builds] = error }
      if let error = groups.error { appStoreSectionErrors[.testers] = error }
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

  private func loadSelectedAppStoreVersionDetails(
    client: AppStoreConnectClient, expectedAppID: String
  ) async {
    guard let version = selectedAppStoreVersion else {
      appStoreLocalizations = []
      appStoreScreenshotSets = []
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
    appStoreBetaGroups = []
    appStoreLocalizations = []
    appStoreScreenshotSets = []
    appStoreFeedback = []
    appStoreSelectedVersionID = nil
    appStoreSelectedBuildID = nil
    appStoreSectionErrors = [:]
    appStoreDeploymentLastSyncedAt = nil
    appStoreDeploymentPhase = .idle
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
