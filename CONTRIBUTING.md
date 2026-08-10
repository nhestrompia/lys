# Contributing

1. Use an Apple Silicon Mac with Swift 6.3 and the supported Xcode toolchain.
2. Keep protocol and persisted types Codable, versioned, and backwards-explicit.
3. Add tests for every path, process, verification, or selector rule.
4. Do not add shell-string execution, terminal scraping, credential-file access, automatic bootstrap scripts, or mutable unverified downloads.
5. Keep UI claims honest: queued, blocked, stale, and nondeterministic are first-class states.
6. Run `./Scripts/test-local.sh` and document any Simulator/WDA fixture results with exact Xcode build and runtime.

Use Swift API naming conventions, small actors with explicit ownership, and standard Foundation/AppKit/SwiftUI before adding dependencies. Public changes are licensed under Apache-2.0 and require a Developer Certificate of Origin sign-off in the commit message.
