import Foundation

public struct SecretRedactor: Sendable {
  private let literalSecrets: [String]
  private let repositoryRoots: [String]
  public init(literalSecrets: [String] = [], repositoryRoots: [URL] = []) {
    self.literalSecrets = literalSecrets.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    self.repositoryRoots = repositoryRoots.map(\.standardizedFileURL.path).sorted {
      $0.count > $1.count
    }
  }
  public func redact(_ input: String) -> String {
    var output = input
    for root in repositoryRoots {
      output = output.replacingOccurrences(of: root, with: "<repository>")
    }
    for secret in literalSecrets {
      output = output.replacingOccurrences(of: secret, with: "<redacted>")
    }
    let patterns = [
      #"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+\-/=]+"#,
      #"(?i)((?:api[_-]?key|token|secret|password)\s*[=:]\s*)[^\s,;]+"#,
      #"\b(?:sk|ghp|github_pat)_[A-Za-z0-9_\-]{12,}\b"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(output.startIndex..<output.endIndex, in: output)
      if pattern.contains("authorization") || pattern.contains("api") {
        output = regex.stringByReplacingMatches(
          in: output, range: range, withTemplate: "$1<redacted>")
      } else {
        output = regex.stringByReplacingMatches(
          in: output, range: range, withTemplate: "<redacted>")
      }
    }
    return output
  }
}
