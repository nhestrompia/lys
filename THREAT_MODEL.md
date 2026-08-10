# Threat Model

The public alpha coordinates powerful local developer tools outside the Mac App Sandbox. Isolated worktrees and native permission prompts reduce accidental damage; they are not a security boundary against a malicious local executable running as the user.

## Protected assets

- Original repository contents and uncommitted changes
- Agent and developer credentials
- Keychain secrets and environment values
- Simulator data
- Task evidence integrity
- Local machine availability

## Primary threats and controls

- **Traversal and symlink escape:** ACP paths are normalized, rooted in the task workspace, and checked along existing symlink components.
- **Command injection:** Apple and Git tools receive absolute executable paths and argument arrays. Repository values are never interpolated into a shell command.
- **Original-checkout overwrite:** applies compare mode, symlink target, and SHA-256 against the task baseline. Changed originals and binary conflicts stop for manual resolution.
- **Socket impersonation:** the runtime binds no network interface, uses a mode-0600 Unix socket, and requires a per-task token on every connection.
- **Malicious archives:** optional adapter and WDA archives remain non-executable until exact version, license, checksum, compatibility, and release-signature validation pass.
- **Credential leakage:** the app does not read CLI credential files. BYOK values belong in Keychain and are injected only into the chosen process. Diagnostic export applies literal, token-pattern, and repository-path redaction.
- **Stale or fabricated completion:** the host validates evidence IDs and mutation generations. Agent prose cannot set verification state.
- **Resource exhaustion:** process output is intended to be bounded and persisted; child cancellation interrupts, waits five seconds, then terminates. Additional archive-size and log-buffer limits remain release-gate work.

## Explicit non-goals

The alpha does not defend the user from an already-compromised account, malicious root process, hostile full-trust local CLI, Xcode/toolchain compromise, or a developer explicitly approving dangerous commands. Git push, distribution, device erasure, network access, credentials, and writes outside the task workspace require separate approval surfaces before release.
