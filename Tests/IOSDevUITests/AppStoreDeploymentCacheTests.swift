import Foundation
import Testing

@testable import IOSDevUI

@Test func appStoreDeploymentCacheUsesAShortFreshnessWindow() {
  let now = Date(timeIntervalSince1970: 10_000)

  #expect(!AppStoreDeploymentCachePolicy.isFresh(lastSyncedAt: nil, now: now))
  #expect(
    AppStoreDeploymentCachePolicy.isFresh(
      lastSyncedAt: now.addingTimeInterval(-AppStoreDeploymentCachePolicy.maxAge + 0.1),
      now: now))
  #expect(
    !AppStoreDeploymentCachePolicy.isFresh(
      lastSyncedAt: now.addingTimeInterval(-AppStoreDeploymentCachePolicy.maxAge),
      now: now))
  #expect(
    !AppStoreDeploymentCachePolicy.isFresh(
      lastSyncedAt: now.addingTimeInterval(1), now: now))
}
