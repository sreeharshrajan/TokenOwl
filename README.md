# 🦉 TokenOwl

A lightweight macOS CLI tool written in Swift to monitor Antigravity AI quota and usage limits directly from your terminal.

---

## Features

- **macOS Keychain Integration**: Securely reads local Antigravity credentials stored in the macOS Keychain.
- **Automatic OAuth Token Refresh**: Refreshes Google OAuth access tokens on the fly using your existing refresh token.
- **Antigravity Quota Checking**: Fetches up-to-date quota details across model groups (Gemini, Claude, GPT, etc.).
- **Summary & Constraints**: Displays remaining quota percentages, rate limit windows (5-hour, weekly), reset times, and highlights the most constrained limit.

---

## Prerequisites

- macOS 12.0 or later
- Swift 6.0+ (Swift toolchain installed via Xcode or swift.org)
- Google Antigravity installed and authenticated on your machine

---

## Usage

### Run directly with SwiftPM

```bash
swift run TokenOwl
```

### Build release binary

```bash
swift build -c release
```

The compiled binary will be located at:
```bash
.build/release/TokenOwl
```

---

## How It Works

1. **Keychain Access**: Retrieves raw stored Antigravity credentials from macOS Keychain (`AntigravityCredentialReader`).
2. **Credential Decoding**: Parses and validates OAuth token data (`AntigravityCredentialDecoder`).
3. **Token Refresh**: Uses the refresh token to request a fresh Google access token (`GoogleOAuthClient`).
4. **Quota Inspection**: Queries the Antigravity backend API to retrieve real-time rate limit buckets and display formatted remaining quotas (`AntigravityQuotaClient`).

---

## License

MIT
