---
version: 1
slug: "sources-iosdevapp-workbenchview-swift"
primary_target: "Sources/IOSDevApp/WorkbenchView.swift"
related_targets: ["Sources/IOSDevApp/AppModel.swift","Sources/IOSDevAppMain/AppMain.swift"]
---

# Workbench surface brief

- Scope and mode: native macOS Operate surface for one complete isolated iOS-development loop.
- Audience and job: an iOS developer delegates a focused change, watches the running app, and decides whether machine-recorded evidence justifies applying it.
- Primary action: Build/Run during work; Review Changes/Apply Changes at the decision boundary.
- Proof: real build, launch, UI, screenshot, log, test, and diff evidence, generation-scoped and visibly stale when code changes.
- Constraints: adjacent Apple Simulator rather than embedded Simulator; WebDriverAgent interaction stays visibly blocked until a pinned compatibility gate passes; never imply agent prose is verification.
- Direction: luminous native studio matching the supplied Operate reference—persistent rail, agent ledger left, phone stage center, verification ledger right, fixed review bar below.
- Memorable moment: the app under test remains physically centered while intent and proof stay adjacent on either side.
- Unresolved: exact promoted WDA build and signed ACP adapter releases remain external feasibility gates.
