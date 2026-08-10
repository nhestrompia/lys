# Security Policy

This project is pre-release. Please do not file public issues for vulnerabilities that could expose repository data, credentials, or local execution.

Report a vulnerability privately to the repository maintainers with:

- affected revision and macOS/Xcode versions;
- reproduction steps using a disposable repository and simulator;
- impact and whether user approval was involved;
- relevant redacted diagnostics.

Never include real tokens, Keychain values, proprietary source, or unredacted ACP transcripts. Maintainers should acknowledge a complete report within seven days and coordinate disclosure after a fix is available.

Security-sensitive changes require tests for traversal, shell metacharacters, archive validation, redaction, cancellation, and apply conflicts. Release artifacts must be Developer-ID signed and notarized; update appcasts must be EdDSA signed.
