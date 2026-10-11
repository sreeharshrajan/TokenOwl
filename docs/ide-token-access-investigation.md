# IDE Token Access — Investigation Clarification

Status: **documentation only** (phase 0 of the menu-bar implementation phase).
No new reverse engineering was performed. No token was printed, logged, or persisted
while producing this document.

> **Superseded in part by a later phase.** Section 7 records the subsequent,
> explicitly-scoped implementation of `IDECredentialProvider`, including the
> discovery that the stored value is a base64 envelope carrying a **plaintext
> refresh token** — which also corrects the scope claim in 3.2 for this
> artifact. Electron Safe Storage is still never decrypted by TokenOwl.

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

---

## 7. Later phase — plaintext IDE session envelope (implemented)

The phase-0 non-goals above were scoped to that phase. A later phase, explicitly
requested, implemented the plaintext path — and in doing so found that the stored
artifact is richer (and differently shaped) than section 3.1 assumed.

### 7.1 The actual stored format

The value at `antigravityUnifiedStateSync.oauthToken` is **not** a bare bearer
token. It is:

```
base64(  JSON { context, state } … oauthTokenInfoSentinelKey: <nested base64> … )
              └── nested base64 decodes to a small binary blob containing, as
                  plaintext substrings, an access token (ya29.…), a refresh
                  token (1//…), and account/context fields
```

Observed properties (values never printed): outer length ~1 KB, outer decodes to
~800 bytes that are not wholly valid UTF-8 (which is why a naive UTF-8 decode of
the outer layer silently yields nothing), exactly one nested base64 run carrying
both tokens. No expiry field accompanies them, so freshness can only be
established by asking Google.

### 7.2 What is implemented

- `IDETokenStateReader`: read-only SQLite access (`SQLITE_OPEN_READONLY`) to
  `~/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb`,
  key `antigravityUnifiedStateSync.oauthToken`, path overridable via
  `TOKENOWL_IDE_STATE_PATH`. It unwraps the envelope with a bounded (≤3 round),
  de-duplicated base64 walk, extracts both tokens by pattern, accepts a bare
  token as well (the format section 3.1 observed), and reports an unparseable
  value as `tokenNotRecognized` rather than as a token. Binary layers are
  searched lossily: replacement characters cannot match either pattern.
- `IDECredentialProvider`: exposes the recovered pair as
  `ResolvedCredential(source: .ide, accessToken:refreshToken:)` — **refreshable**.
  Both tokens live in memory only and are never persisted, printed, or logged
  (no value, no length, no hash).
- `OAuthTokenManager` renews IDE sessions exactly like Keychain ones (memory-only
  access token, 5-minute expiry margin, coalesced refresh). The first quota
  request may still be sent with the envelope's stale access token; the 401 →
  invalidate → refresh → retry path then renews it once, after which the cached
  token carries Google's `expires_in`.
- Credential priority in `AntigravityService`: **Keychain credential → IDE
  state-database envelope** (see 7.5 for why the envelope cannot be first),
  with silent fallback on credential-shaped failures — including an HTTP
  401/403 from the quota API and a 400/401 from a refresh Google refuses
  (revoked refresh token). A source that hands off a fetch is skipped for
  15 minutes; the last source is never skipped.

### 7.3 What is still not implemented

- Electron Safe Storage decryption — untouched, as before. It remains the path
  to whatever *other* durable material the IDE keeps there; the session envelope
  itself needed only decoding.
- Any write to the IDE's state database — the reader opens it read-only.
- Any persistence of the recovered tokens by TokenOwl.

### 7.4 Corrected findings from the earlier verification

Two conclusions from the first cut of this section were wrong and are retracted:

1. **"The stored value was sent to Google and rejected as stale."** The 401
   (`UNAUTHENTICATED`) was an artifact of submitting the *envelope* as a bearer
   token. Once the envelope is unwrapped, the inner access token is indeed
   stale at the time of testing, but that is a separate, expected fact — access
   tokens live about an hour.
2. **"Refreshing requires material TokenOwl does not have."** The envelope
   carries a plaintext `1//` refresh token, and Google's token endpoint accepts
   it with TokenOwl's installed-app client (HTTP 200 in verification). IDE
   sessions are therefore refreshable by TokenOwl, which makes the IDE source
   durable rather than time-boxed.

This also **corrects the scope claim in 3.2 for this artifact**: long-lived
refresh material from the IDE *is* readable in plaintext from `state.vscdb` —
Safe Storage protects a different (still untouched) blob. What 3.2 says about
the credential blob Electron encrypts remains true; what must no longer be
said is that *all* long-lived IDE credential material requires Safe Storage.

Verified end-to-end after the fix (live run, no secrets printed): IDE session
read → source `Antigravity IDE` → quota received → the IDE's Google account
(distinct from the Keychain account), menu label `🦉 0%` from that account's
real quota, preview and status-item captures regenerated with no render
placeholders. Tests: 98 passing (reader envelope/bare/garbage parsing, provider
credential shapes, stale-session refresh, revoked-refresh fallback, cooldown
expiry).

### 7.5 The envelope is not the active login (priority corrected)

A user-visible mismatch forced the last correction: the IDE was signed into
account A, while TokenOwl showed account B. Verified facts, no secrets printed:

- The envelope's refresh token belongs to account B and still works, so the
  reader and provider were behaving correctly — the *premise* was wrong.
- The Keychain credential belongs to account A, and its quota (64/98/98/95)
  matches the IDE's own Models & Usage panel exactly. The envelope's account B
  quota (0/100/0/100) does not.
- No other key in `state.vscdb` (19k+ keys scanned; names and account
  mentions only) holds a token for the active login. The IDE's live session
  lives in Electron Safe Storage, which remains out of scope.

Conclusion: the Keychain item (`gemini`/`antigravity`) is where the IDE keeps
its **current** session; the state-database envelope can retain a
**previously** signed-in account after a sign-out/switch, because the refresh
token keeps working and nothing clears it. Priority is therefore
**Keychain → envelope**, the opposite of the original phase-2 directive, whose
premise ("the envelope reflects the IDE's signed-in account") is retracted.
The envelope remains useful as a fallback and will automatically become
correct if the IDE ever writes the active account into it.
