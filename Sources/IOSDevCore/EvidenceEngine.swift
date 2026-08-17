import Foundation

public enum VerificationStatus: String, Codable, Sendable {
  case verified, partiallyVerified, failed, blocked
}

public struct VerificationRequirement: Codable, Sendable {
  public var codeChanged: Bool
  public var uiChanged: Bool
  public var testsChanged: Bool
  public var criterionIDs: [String]
  /// When non-empty, UI evidence must exist for every listed Simulator destination.
  /// Empty keeps the original single-destination verification contract.
  public var requiredDestinationUDIDs: [String]
  /// Form-factor requirements remain meaningful before a matching Simulator is active.
  public var requiredDestinationFamilies: [String]

  private enum CodingKeys: String, CodingKey {
    case codeChanged, uiChanged, testsChanged, criterionIDs, requiredDestinationUDIDs,
      requiredDestinationFamilies
  }

  public init(
    codeChanged: Bool, uiChanged: Bool, testsChanged: Bool, criterionIDs: [String] = [],
    requiredDestinationUDIDs: [String] = [], requiredDestinationFamilies: [String] = []
  ) {
    self.codeChanged = codeChanged
    self.uiChanged = uiChanged
    self.testsChanged = testsChanged
    self.criterionIDs = criterionIDs
    self.requiredDestinationUDIDs = requiredDestinationUDIDs
    self.requiredDestinationFamilies = requiredDestinationFamilies
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    codeChanged = try values.decode(Bool.self, forKey: .codeChanged)
    uiChanged = try values.decode(Bool.self, forKey: .uiChanged)
    testsChanged = try values.decode(Bool.self, forKey: .testsChanged)
    criterionIDs = try values.decodeIfPresent([String].self, forKey: .criterionIDs) ?? []
    requiredDestinationUDIDs = try values.decodeIfPresent(
      [String].self, forKey: .requiredDestinationUDIDs) ?? []
    requiredDestinationFamilies = try values.decodeIfPresent(
      [String].self, forKey: .requiredDestinationFamilies) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(codeChanged, forKey: .codeChanged)
    try values.encode(uiChanged, forKey: .uiChanged)
    try values.encode(testsChanged, forKey: .testsChanged)
    try values.encode(criterionIDs, forKey: .criterionIDs)
    try values.encode(requiredDestinationUDIDs, forKey: .requiredDestinationUDIDs)
    try values.encode(requiredDestinationFamilies, forKey: .requiredDestinationFamilies)
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

      for destinationID in requirement.requiredDestinationUDIDs {
        let destinationEvidence = current.filter { $0.destinationUDID == destinationID }
        if !destinationEvidence.contains(where: { $0.kind == .launch && $0.status == .passed }) {
          missing.append("Fresh successful launch on \(destinationID)")
        }
        if requirement.criterionIDs.isEmpty {
          if !destinationEvidence.contains(where: {
            $0.kind == .uiAssertion && $0.status == .passed && $0.deterministic
          }) {
            missing.append("Deterministic UI assertion on \(destinationID)")
          }
        } else {
          let destinationCriteria = Set(
            destinationEvidence.compactMap { item in
              guard item.kind == .uiAssertion, item.status == .passed, item.deterministic
              else { return nil as String? }
              return item.criterionID
            })
          for criterionID in requirement.criterionIDs where !destinationCriteria.contains(criterionID) {
            missing.append("Acceptance criterion \(criterionID) on \(destinationID)")
          }
        }
        if !destinationEvidence.contains(where: { $0.kind == .screenshot && $0.status == .passed }) {
          missing.append("Fresh screenshot on \(destinationID)")
        }
      }

      for family in requirement.requiredDestinationFamilies {
        let familyEvidence = current.filter { evidence in
          let values = [
            evidence.destinationID, evidence.deviceType, evidence.runtime,
          ].compactMap { $0?.lowercased() }.joined(separator: " ")
          return values.contains(family.lowercased())
        }
        if !familyEvidence.contains(where: { $0.kind == .launch && $0.status == .passed }) {
          missing.append("Fresh successful launch on \(family)")
        }
        if requirement.criterionIDs.isEmpty {
          if !familyEvidence.contains(where: {
            $0.kind == .uiAssertion && $0.status == .passed && $0.deterministic
          }) {
            missing.append("Deterministic UI assertion on \(family)")
          }
        } else {
          let familyCriteria = Set(
            familyEvidence.compactMap { item in
              guard item.kind == .uiAssertion, item.status == .passed, item.deterministic
              else { return nil as String? }
              return item.criterionID
            })
          for criterionID in requirement.criterionIDs where !familyCriteria.contains(criterionID) {
            missing.append("Acceptance criterion \(criterionID) on \(family)")
          }
        }
        if !familyEvidence.contains(where: { $0.kind == .screenshot && $0.status == .passed }) {
          missing.append("Fresh screenshot on \(family)")
        }
      }
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
