# 🦉 TokenOwl

A native macOS **menu-bar app** (with a CLI companion) written in Swift that monitors
Antigravity AI quota and usage limits in real-time.

```
🦉 88%   ← menu-bar status item
```

---

## Features

- **Menu-bar Native & Compact**: Minimalist `MenuBarExtra` popover with a sleek 300px dark translucent card interface. No Dock icon clutter.
- **Glanceable Hero Metric**: Full-width header displaying your selected or lowest quota limit with a glowing circular neon arc gauge, model name, and live reset countdown.
- **Visual Limit Cards**: Distinct rounded cards for Gemini, Claude, and GPT models with smooth emerald-to-gold gradient progress bars and reset times.
- **Standalone Modal Windows**: Separate native macOS modal floating windows for **Settings** (customizable highlight model and period with full-width pickers) and **About TokenOwl**, automatically closing the menu popover and taking priority focus.
- **Copy Stats as Markdown**: Quick copy action in the footer gear menu to format and copy all active quota limits to your clipboard in structured Markdown.
- **Account & Application Transparency**: Displays Google account email, application details, and active credential source.
- **Native AI Editor Selector**: Switch between installed AI editors (Antigravity IDE, Codex) from a native picker in the popover. Antigravity reads Google account quotas. Codex shows Codex quota windows through `codex app-server` (install Codex CLI and run `codex login`). The Keychain and IDE credential providers remain internal authentication mechanisms under Antigravity — they are not tied to the editor dropdown.
- **Cached OAuth Tokens**: Reuses valid access tokens and automatically refreshes them with Google OAuth prior to expiration. Tokens are stored in memory only.
- **Dual Credential Sources**: Resolves credentials from two independent sources:
  1. **macOS Keychain** — the IDE's current active session (account A). Quota matches the IDE's usage panel exactly.
  2. **IDE state database envelope** — can retain a previously signed-in account (account B) whose refresh token still works. Tried only after Keychain.
  TokenOwl prioritizes Keychain first; the IDE envelope is the fallback. Neither source impersonates the other's account.
- **Graceful Lifecycle**: Quick one-click refresh, 5-minute background cadence, and a dedicated **Quit TokenOwl** option.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.0+ toolchain
- Google Antigravity installed and authenticated on your machine

---

## Usage

### Menu-bar app

```bash
swift run TokenOwlApp
```

### Install to /Applications

```bash
./Scripts/install.sh
open /Applications/TokenOwl.app
```

The script compiles the release binary, packages `/Applications/TokenOwl.app` (menu-bar-only, ad-hoc signed), and registers it.

- **Start at login**: System Settings → General → Login Items → `+` → `TokenOwl`.
- **Relaunch / Restart**: `killall TokenOwlApp && open /Applications/TokenOwl.app`
- **Uninstall**: `rm -rf /Applications/TokenOwl.app`

### Build a macOS installer

```bash
bash Scripts/package.sh
```

Creates an unsigned, architecture-specific `.pkg` in `DIST/` that installs
TokenOwl into `/Applications`. The app is ad-hoc signed and the MIT license
is included. See [DIST/README.md](DIST/README.md) for installation requirements.

### CLI diagnostics

```bash
swift run TokenOwl              # fetch and print Antigravity quota
swift run TokenOwl --codex      # verify Codex connection and print quotas
swift run TokenOwl --editors    # read-only editor discovery: installation facts
                                # and quota-adapter availability (no binaries
                                # executed, no credentials read, no network)
```

### Build & test

```bash
swift build
swift test
```

### Debug affordances & Testing (optional)

Honored in debug builds only:

| Variable | Effect |
| --- | --- |
| `TOKENOWL_DEBUG=1` | Redacted debug logging to stderr (scrubs tokens, API keys, and auth headers). |
| `TOKENOWL_REFRESH_INTERVAL=30` | Refresh period in seconds (default is 5 minutes). |
| `TOKENOWL_SIMULATE_FAILURE=stale` | Simulates refresh failures after initial load. |
| `TOKENOWL_SIMULATE_FAILURE=always` | Simulates immediate refresh failure. |
| `TOKENOWL_PREVIEW_EDITOR=codex` | Starts the popover with another editor selected (raw enum value; never persisted). |
| `TOKENOWL_CODEX_LIVE=1` | Opt-in integration test suite run against locally installed Codex CLI. |
| `TOKENOWL_PREVIEW_PATH=/tmp/menu.png` | Renders offscreen snapshot PNG of the menu UI. |
| `TOKENOWL_PREVIEW_LOADING_PATH=/tmp/loading.png` | Renders the first-launch loading state. |
| `TOKENOWL_STATUS_PATH=/tmp/status.png` | Captures the live menu-bar status item. |

---

## Architecture

```
TokenOwlCore            domain + services, no SwiftUI (fully testable)
├── Models/             Account, Quota (+ payload/domain split), Snapshot, DateFormatting,
│                       CodexRateLimit (response models + summary + windows)
├── Editors/            AIEditor + status model, EditorDiscoveryService (read-only
│                       installation discovery), AIQuotaProvider protocol with the
│                       AntigravityQuotaProvider and CodexQuotaProvider adapters,
│                       QuotaProviderRegistry, EditorSelection persistence
├── Providers/          CredentialProvider protocol, KeychainCredentialProvider,
│                       IDECredentialProvider, IDETokenStateReader (read-only)
├── Security/           Keychain reader, credential decoder, redacting logger (scrubs
│                       Bearer tokens, ya29, 1//, sk-*, emails, JWTs)
└── Services/           AntigravityService, QuotaClient, GoogleOAuthClient,
                        OAuthTokenManager, CodexProcessClientLive, CodexBinaryResolver,
                        ErrorPresentation

TokenOwl                CLI diagnostics (executable)
TokenOwlApp             menu-bar app (executable)
├── App/                TokenOwlApp, QuotaStore (@Observable),
│                       WindowManager (standalone window manager), MenuPreviewRenderer
└── Views/              MenuBarView, AccountHeaderView, QuotaGroupView,
                        QuotaBucketView, PreferencesView, AboutView
```

### Codex Integration Architecture

TokenOwl communicates with OpenAI Codex via a local child process:
- **Child process transport**: Spawns the official `codex app-server` binary via Swift native `Process` talking JSON-RPC 2.0 over stdio (one JSON object per line). No Node.js runtime or external server required.
- **Protocol Handshake**: Sends `initialize` request, sends `initialized` notification, and requests `account/rateLimits/read`.
- **Zero Token Access Invariant**: TokenOwl **never reads, parses, copies, or logs** `~/.codex/auth.json` or any OAuth/API token. It **never calls** `chatgpt.com/backend-api/*` directly. Codex owns authentication; TokenOwl purely renders presentation.
- **Supported Codex Versions & Limitations**: Targets Codex CLI 0.x. The `codex app-server` protocol is undocumented as a public API and is version-sensitive. API-key-only auth is unsupported by the app-server and surfaced gracefully as `.apiKeyAuthUnsupported` prompting the user to run `codex login`.
- **Process Lifecycle & Cleanup**: Every invocation enforces bounded timeouts, active Swift cancellation termination, SIGPIPE protection, and guaranteed child process reaping with SIGKILL fallback to prevent orphan processes.

---

## Security Invariants

- **No credential logging**: All sensitive credentials, OAuth tokens, API keys (`sk-*`), emails, JWTs, and `Authorization` headers are scrubbed and excluded from logs via regex-based redaction in `RedactedLogger`.
- **Zero Codex token handling**: Codex authentication is completely delegated to the local `codex app-server` process. `~/.codex/auth.json` is never accessed.
- **Memory-only tokens**: Access tokens and refresh tokens are kept in volatile memory by TokenOwl and never persisted to disk, `UserDefaults`, or the Keychain. However, TokenOwl does read credentials from the macOS Keychain and the IDE's SQLite state database (read-only), where the IDE may store refresh tokens outside TokenOwl's control. TokenOwl does not create additional persistent copies of these credentials.
- **Read-only local access**: Reads the macOS Keychain and local IDE SQLite state database using read-only APIs (`SQLITE_OPEN_READONLY`). Electron Safe Storage is never accessed or decrypted.
- **Read-only editor discovery**: Installation detection checks known bundle identifiers, standard application locations, and executable names on PATH. It never executes a discovered binary to identify it, never scans the whole filesystem, and never opens chat histories, workspace files, or authentication databases.
- **Strict Network Scope**: Antigravity requests use official Google endpoints; Codex delegates to its local app-server. No external telemetry or trackers.

---

## Developer

Developed with ❤️ by **Sreeharsh Rajan**

- **Website**: [sreeharsh.vercel.app](https://sreeharsh.vercel.app/)
- **Repository**: [github.com/sreeharshrajan/TokenOwl](https://github.com/sreeharshrajan/TokenOwl)

---

## License

Licensed under the [MIT License](LICENSE).

### Google OAuth configuration

Google token refresh reads the matching OAuth client configuration from the
installed Antigravity IDE. No client credentials are bundled in the source.
Paired `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` environment
variables can override discovery. Finder launches do not inherit terminal
environment variables. Keep credentials out of Git.

### Version 0.2.0

Adds OAuth configuration discovery, bounded HTTP retries, safer credential
file checks, and improved Codex process handling and account identification.
Notification and preferences enhancements are deferred.

### Version 0.3.0

Updates the macOS release package and version metadata while retaining 0.2.0
behavior. Notification and preferences enhancements remain deferred.
