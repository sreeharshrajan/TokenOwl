# IDE Token Access — Investigation Clarification

Status: **documentation only** (phase 0 of the menu-bar implementation phase).
No new reverse engineering was performed. No token was printed, logged, or persisted
while producing this document.

---

## 1. The ambiguity

The previous investigation reported two statements that appear to contradict each other:

- **Statement A (observed):** an IDE access-token candidate could be read from
  `antigravityUnifiedStateSync.oauthToken` and that candidate was accepted by
  Google's quota endpoint (`retrieveUserQuotaSummary`), i.e. it was a live bearer
  token at the time of the test.
- **Statement B (conclusion):** IDE token access requires Electron Safe Storage
  decryption.

## 2. Resolution

Both statements are true, but they are true about **different artifacts**. Statement B,
read as a blanket claim about *any* IDE token access, is incorrect and is contradicted
by Statement A. Statement B is correct only when scoped to **long-lived credential
material**.

| Artifact | Protected by Electron Safe Storage? | Readable in plaintext? | Lifetime |
|---|---|---|---|
| The access token observed at `antigravityUnifiedStateSync.oauthToken` | No (as observed) | Yes, as observed in the prior phase | Short-lived |
| The persisted refresh-token / credential blob the IDE uses to mint new access tokens | Yes (Electron `safeStorage`, Keychain-backed on macOS) | No | Long-lived |

Electron's `safeStorage` encrypts data the application chooses to persist securely
(the credential blob, equivalent to Chrome's `os_crypt` store). It does **not** encrypt
whatever the application chooses to place in its own state-sync structure. The observed
`oauthToken` field fell in the second category: it was already a usable bearer token and
required no decryption step.

So the correct reading is:

- **Safe Storage is required to obtain long-lived credentials from the IDE** — yes.
- **Safe Storage is required to obtain *a* (short-lived) access token from the IDE** —
  no, as demonstrated by the prior observation.

## 3. Direct answers to the three questions

### 3.1 Can a currently valid short-lived access token be extracted without Safe Storage decryption?

**Yes, as observed in the prior phase — for the specific artifact and moment tested.**

The candidate read from `antigravityUnifiedStateSync.oauthToken` was submitted as a
bearer token to Google's quota endpoint and was accepted, which establishes that a live
access token was obtained without any Safe Storage decryption step.

Caveats:

- This was an observation of the state of a specific install at a specific time; it was
  **not re-verified in this phase** and is not re-verified here by design.
- It does not generalise to the credential blob, nor does it imply the field is always
  populated or always fresh.
- No extraction path is implemented, exercised, or documented operationally in
  TokenOwl. `IDECredentialProvider` is explicitly deferred to a later phase.

### 3.2 Does obtaining or refreshing long-lived credentials require Safe Storage?

**Yes.**

The long-lived material (the refresh token / persisted OAuth credential the IDE uses to
mint new access tokens) is the artifact encrypted with Electron Safe Storage. Decrypting
it requires the per-user key held by the macOS Keychain entry Electron creates for that
purpose, i.e. it cannot be read by simply parsing a file.

This is also why the report concluded "IDE token access requires Safe Storage": that
conclusion is valid for the *durable credential*, which is the only thing that gives a
client a repeatable refresh capability.

TokenOwl does not touch this path. It obtains its long-lived refresh token from the
Antigravity **Keychain credential** through `KeychainCredentialProvider`
(`kSecClassGenericPassword`, service `gemini`, account `antigravity`), which is the
supported, user-visible credential source.

### 3.3 Does the extracted access token expire without a supported refresh mechanism?

**Yes.**

Google access tokens are short-lived (on the order of an hour; the lifetime is decided
by Google's token endpoint via `expires_in`). Once expired, the token is rejected by
quota endpoints and there is **no supported refresh mechanism for the token itself** —
refreshing requires the refresh token, i.e. the long-lived material described in 3.2.

Consequences:

- A one-off extracted access token is a **time-boxed** capability, not a durable one.
- Any architecture built on it would still need the refresh token to stay alive past the
  first hour, which reintroduces Safe Storage (3.2) or the Keychain credential path.

## 4. What this means for TokenOwl

- The contradiction is resolved by *scoping*, not by choosing one statement: plaintext
  short-lived access token (observed), encrypted long-lived credential (Safe Storage).
- Therefore the supported TokenOwl path remains: **Keychain credential → refresh token →
  Google OAuth refresh → quota API**, which is what `AntigravityService` +
  `OAuthTokenManager` implement in this phase.
- No IDE state file, IDE database, or Safe Storage key is read, written, or modified by
  TokenOwl.
- No `IDECredentialProvider` is implemented in this phase. The `CredentialSource.ide`
  enum case exists only as a placeholder for a future, explicitly-scoped phase.

## 5. Confidence

| Claim | Basis | Confidence |
|---|---|---|
| The observed `oauthToken` candidate validated against the quota endpoint without decryption | Recorded observation from the prior phase | High (as recorded), not re-tested this phase |
| The long-lived credential blob is Safe Storage protected | Electron/Chrome `safeStorage` behaviour plus the prior report | High |
| Extracted access token expires with no self-refresh | Google OAuth token semantics | High |
| The state-sync field is plaintext in every build/version | Not established | Low — deliberately not asserted |

## 6. Explicit non-goals for this phase

- No IDE credential extraction.
- No Electron Safe Storage decryption.
- No `IDECredentialProvider` implementation.
- No token printing, logging, or persistence during verification of this document.
