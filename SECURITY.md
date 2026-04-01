# Security Policy

## Overview

Claude Pulse is a macOS utility that monitors AI coding agent sessions and API usage. It handles sensitive data including OAuth tokens and inter-process communication. This document describes the threat model, mitigations, and security practices for external review.

## Threat Model

### 1. Unix Socket Communication

**Threat**: A malicious process connects to the Claude Pulse socket and sends crafted messages to manipulate the UI or relay false permission approvals.

**Mitigations**:
- Socket file permissions set to `0600` (owner read/write only)
- Peer credential validation via `getpeereid()` — rejects connections from different UIDs
- Strict JSON schema validation via `Codable` (no dynamic parsing, no `eval()`)
- Maximum message size enforced (64KB) to prevent memory exhaustion
- Buffer overflow protection — accumulated data cleared if it exceeds max size
- No shell command execution from socket input

### 2. API Key / Token Security

**Threat**: OAuth tokens or API keys are leaked through source code, logs, or disk storage.

**Mitigations**:
- **No API keys in source code** — verified by CI (grep for key/secret/token patterns)
- OAuth tokens read exclusively from macOS Keychain at runtime (`OAuthResolver`)
- Tokens are never logged, printed, or written to disk
- Tokens are never included in crash reports or diagnostics
- `.gitignore` excludes all common secret file patterns
- Token refresh happens in-memory only

### 3. Auto-Update Tampering

**Threat**: An attacker compromises the update channel to deliver malicious binaries.

**Mitigations**:
- Updates distributed via GitHub Releases over HTTPS
- Sparkle framework verifies Ed25519 signatures on all updates
- Public key (`SUPublicEDKey`) embedded in the app binary
- Private signing key kept offline, never in the repository
- Appcast XML served over HTTPS

### 4. Hook Script Injection

**Threat**: A malicious hook script is installed that intercepts agent data or executes arbitrary code.

**Mitigations**:
- Hook scripts are plaintext shell scripts — fully inspectable by the user
- `install-hooks.sh` shows the exact changes before modifying `settings.json`
- No obfuscated or minified code in hook scripts
- Hooks only send data TO the socket — they cannot read responses
- Socket server validates all incoming data regardless of source

### 5. Privilege Escalation

**Threat**: The app is used as a vector to gain elevated system privileges.

**Mitigations**:
- App runs as standard user — no `sudo`, no setuid binaries
- Accessibility API requires explicit user grant (System Settings prompt)
- App Sandbox entitlements limit access to:
  - Network client (for API calls only)
  - User-selected files (for log watching)
  - Application Support directory
- Hardened Runtime enabled (required for notarization)
- No use of deprecated or unsafe APIs

### 6. Supply Chain

**Threat**: A compromised dependency introduces malicious code.

**Mitigations**:
- **Zero external runtime dependencies** — all Apple frameworks
- Sparkle is the only third-party dependency, and it is:
  - Widely audited (used by thousands of macOS apps)
  - Pinned to a specific version range in `Package.swift`
  - Verified via SPM's built-in package integrity checks
- No npm, pip, or other package manager dependencies
- No pre-built binaries — everything compiles from source

### 7. Local Data Storage

**Threat**: Sensitive usage data or session information is accessible to other processes.

**Mitigations**:
- SQLite database stored in `~/Library/Application Support/ClaudePulse/` with standard macOS file permissions
- Database uses WAL mode with thread-safe locking
- No sensitive data (tokens, credentials) stored in the database — only usage percentages and timestamps
- Session data is ephemeral (in-memory only, not persisted)
- 30-day automatic pruning of historical data

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public GitHub issue
2. Email the maintainer directly or use GitHub's private vulnerability reporting feature
3. Include: description, reproduction steps, potential impact, and suggested fix if any
4. Allow reasonable time for a fix before public disclosure

## Security Checklist for Contributors

- [ ] No API keys, tokens, or secrets in committed code
- [ ] All socket input validated before processing
- [ ] No shell command execution from untrusted input
- [ ] No `eval()`, `NSTask` with user-controlled arguments, or dynamic code loading
- [ ] File permissions set correctly for sensitive files (sockets, databases)
- [ ] New dependencies justified and audited
- [ ] Error messages do not leak sensitive information
