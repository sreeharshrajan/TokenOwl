# 🦉 TokenOwl

A native macOS **menu-bar app** (with a CLI companion) written in Swift that monitors
Antigravity AI quota and usage limits.

```
🦉 81%   ← menu-bar status item
```

---

## Features

- **Menu-bar only**: `MenuBarExtra` status item with a compact popover. No Dock icon.
- **Account transparency**: always shows the Google account, plan/tier, and which
  credential source produced the numbers on screen.
- **Real quota**: weekly and 5-hour buckets for Gemini, Claude and GPT, each with its
  own reset countdown (`Resets in 4h 58m`, `Resets in 3d 6h`, `Resetting now`).
- **Honest headline number**: the menu-bar percentage is the *lowest* remaining
  percentage among active quota buckets — buckets are never averaged or combined.
- **Cached OAuth access tokens**: `OAuthTokenManager` reuses a still-valid access
  token and only asks Google for a new one when it is missing or within 5 minutes of
  expiry. Access tokens live in memory only.
- **Conservative refresh**: one launch refresh, one refresh every 5 minutes, one
  manual refresh button. No overlapping requests, no refresh storms.
- **macOS Keychain integration**: reads the local Antigravity credential with native
  Keychain APIs only. Read-only — TokenOwl never writes credentials.

---

## Requirements

- macOS 14.0 or later
- Swift 6.0+ toolchain
- Google Antigravity installed and authenticated on your machine

---

## Usage

### Menu-bar app

```bash
swift run TokenOwlApp
```

The app appears in the menu bar as `🦉 <n>%` and does not appear in the Dock.

### CLI diagnostics

```bash
swift run TokenOwl
```

### Build & test

```bash
swift build
swift test
```

### Debug affordances (optional)

All of these are off by default and only read from the process environment.

| Variable | Effect |
| --- | --- |
| `TOKENOWL_DEBUG=1` | Redacted debug logging to stderr (scrubs `Authorization` headers, `access_token`/`refresh_token` form fields, JSON token fields, and `ya29.` Google tokens). |
| `TOKENOWL_REFRESH_INTERVAL=30` | Refresh period in seconds; product default is 5 minutes. |
| `TOKENOWL_SIMULATE_FAILURE=stale` | Every refresh after the first fails, to exercise stale-data preservation. |
| `TOKENOWL_SIMULATE_FAILURE=always` | Refreshes fail from the start, to exercise the empty-state error card. |
| `TOKENOWL_PREVIEW_PATH=/tmp/menu.png` | Renders the menu UI offscreen and writes a PNG (used for screenshots). |
| `TOKENOWL_PREVIEW_LOADING_PATH=/tmp/loading.png` | Renders the first-launch loading state. |
| `TOKENOWL_STATUS_PATH=/tmp/status.png` | Captures the live menu-bar status item. |

```bash
TOKENOWL_DEBUG=1 swift run TokenOwlApp
```

Offscreen captures go through `NSHostingView` + `cacheDisplay(in:to:)`, the same
drawing path the live UI uses. No screen-recording permission is needed, and
nothing is written outside the paths given above.

---

## Architecture

```
TokenOwlCore            domain + services, no SwiftUI (fully testable)
├── Models/             Account, Quota (+ payload/domain split), Snapshot, dates
├── Providers/          CredentialProvider protocol, KeychainCredentialProvider
├── Security/           Keychain reader, credential decoder, redacting logger
└── Services/           AntigravityService, QuotaClient, GoogleOAuthClient,
                        OAuthTokenManager, ErrorPresentation

TokenOwl                CLI diagnostics (executable)
TokenOwlApp             menu-bar app (executable)
└── App/                TokenOwlApp, QuotaStore (@Observable)
└── Views/              MenuBarView, AccountHeaderView, QuotaGroupView,
                        QuotaBucketView
```

Request pipeline:

```
CredentialProvider → OAuthTokenManager → Account identity → QuotaClient
                                                              ↓
                                              AntigravitySnapshot → QuotaStore → UI
```

---

## Security invariants

- No token or Authorization-header logging (debug logs are redacted).
- No credential or token persistence; refreshed access tokens are memory-only.
- Nothing in UserDefaults, crash messages, or UI state.
- Native Keychain APIs only, read-only.
- Ephemeral `URLSession` only; network traffic limited to Google endpoints.
- No analytics, no telemetry, no external backend.
- No IDE database, IDE state file, or Electron Safe Storage access.

See [`docs/ide-token-access-investigation.md`](docs/ide-token-access-investigation.md)
for the documentation of what was (and was not) established about IDE token access.

---

## License

MIT
