import Foundation

public enum VerificationStatus: String, Codable, Sendable {
  case verified, partiallyVerified, failed, blocked
}

public struct VerificationRequirement: Codable, Sendable {
  public var codeChanged: Bool
  public var uiChanged: Bool
  public var testsChanged: Bool
  public var criterionIDs: [String]
  public init(codeChanged: Bool, uiChanged: Bool, testsChanged: Bool, criterionIDs: [String] = []) {
    self.codeChanged = codeChanged
    self.uiChanged = uiChanged
    self.testsChanged = testsChanged
    self.criterionIDs = criterionIDs
  }
}

public struct VerificationReport: Codable, Sendable {
  public var status: VerificationStatus
  public var currentEvidence: [Evidence]
  public var staleEvidence: [Evidence]
  public var missing: [String]
  public init(
    status: VerificationStatus, currentEvidence: [Evidence], staleEvidence: [Evidence],
    missing: [String]
  ) {
    self.status = status
    self.currentEvidence = currentEvidence
    self.staleEvidence = staleEvidence
    self.missing = missing
  }
}

public actor EvidenceLedger {
  private(set) public var generation: Int
  private var evidence: [Evidence]
  public init(generation: Int = 0, evidence: [Evidence] = []) {
    self.generation = generation
    self.evidence = evidence
  }
  @discardableResult public func mutate() -> Int {
    generation += 1
    return generation
  }
  public func record(_ item: Evidence) throws {
    guard item.taskGeneration <= generation else {
      throw RPCError(code: -32020, message: "Evidence generation is in the future")
    }
    if item.kind == .uiAssertion, item.status == .passed {
      for index in evidence.indices
      where evidence[index].taskGeneration == item.taskGeneration
        && evidence[index].kind == .uiAssertion && evidence[index].status == .failed
        && evidence[index].criterionID == item.criterionID
      {
        evidence[index].acknowledged = true
      }
    }
    evidence.append(item)
  }
  public func allEvidence() -> [Evidence] { evidence }

  public func verify(_ requirement: VerificationRequirement) -> VerificationReport {
    let current = evidence.filter { $0.taskGeneration == generation }
    let stale = evidence.filter { $0.taskGeneration != generation }
    let passed = Set(
      current.filter { $0.status == .passed && ($0.deterministic || $0.kind != .uiAction) }.map(
        \.kind))
    var missing: [String] = []
    if requirement.codeChanged && !passed.contains(.build) {
      missing.append("Fresh successful build")
    }
    if requirement.uiChanged {
      if !passed.contains(.launch) { missing.append("Fresh successful launch") }
      let passedCriterionIDs = Set(
        current.compactMap { item in
          guard item.kind == .uiAssertion, item.status == .passed, item.deterministic else {
            return nil as String?
          }
          return item.criterionID
        })
      if requirement.criterionIDs.isEmpty,
        !current.contains(where: {
          $0.kind == .uiAssertion && $0.status == .passed && $0.deterministic
        })
      {
        missing.append("Deterministic UI assertion tied to an acceptance criterion")
      } else {
        for criterionID in requirement.criterionIDs where !passedCriterionIDs.contains(criterionID) {
          missing.append("Acceptance criterion \(criterionID)")
        }
      }
      if !passed.contains(.screenshot) { missing.append("Fresh screenshot") }
    }
    let hasRuntimeFailure = current.contains {
      $0.kind == .runtimeLog && $0.status == .failed && !$0.acknowledged
    }
    if hasRuntimeFailure { missing.append("Acknowledge or resolve crash/error log") }
    if requirement.testsChanged && !passed.contains(.test) {
      missing.append("Affected tests passing, or explicit no-relevant-tests evidence")
    }
    let relevantKinds: Set<EvidenceKind> = Set(
      (requirement.codeChanged ? [.build] : [])
        + (requirement.testsChanged ? [.test] : [])
        + (requirement.uiChanged ? [.launch, .uiAssertion, .screenshot, .runtimeLog] : []))
    let hasFailure =
      hasRuntimeFailure
      || current.contains {
        relevantKinds.contains($0.kind) && $0.status == .failed
          && !$0.acknowledged
      }
    let hasBlocker = current.contains {
      relevantKinds.contains($0.kind) && $0.status == .blocked
    }
    let status: VerificationStatus =
      missing.isEmpty && !hasFailure
      ? .verified : (hasFailure ? .failed : (hasBlocker ? .blocked : .partiallyVerified))
    return VerificationReport(
      status: status, currentEvidence: current, staleEvidence: stale, missing: missing)
  }
}
