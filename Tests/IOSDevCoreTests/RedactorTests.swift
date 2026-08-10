import Foundation
import Testing

@testable import IOSDevCore

@Test func diagnosticsRedactorRemovesSecretsAndRepositoryPaths() {
  let root = URL(fileURLWithPath: "/Users/example/Private Repo")
  let redactor = SecretRedactor(literalSecrets: ["literal-value"], repositoryRoots: [root])
  let output = redactor.redact(
    "Authorization: Bearer abc.def token=token-value literal-value /Users/example/Private Repo/App.swift"
  )
  #expect(!output.contains("abc.def"))
  #expect(!output.contains("token-value"))
  #expect(!output.contains("literal-value"))
  #expect(output.contains("<repository>/App.swift"))
}
