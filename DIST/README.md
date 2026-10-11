# TokenOwl installer

Double-click the `.pkg` file to install TokenOwl into `/Applications`, then
launch TokenOwl from Applications. The app appears in the menu bar.

Requires macOS 14 or later. Packages marked `arm64` support Apple Silicon;
packages marked `x86_64` support Intel Macs. This package does not include the
Codex CLI or Antigravity IDE; install and sign in to the relevant editor separately.

The installer is unsigned and the app is ad-hoc signed, without Apple notarization.
If macOS blocks opening it, attempt to open it, then use System Settings →
Privacy & Security → Open Anyway when available and you trust the download.
See https://support.apple.com/102445 for Apple's instructions.

Google token refresh requires `GOOGLE_OAUTH_CLIENT_ID` and
`GOOGLE_OAUTH_CLIENT_SECRET` in the app process environment. Finder launches
do not inherit variables exported in a terminal. After exporting compatible
credentials, launch the executable from that terminal:

```bash
/Applications/TokenOwl.app/Contents/MacOS/TokenOwlApp
```

The MIT license is included beside the installer and inside the app bundle.
Verify the download with `shasum -a 256 -c TokenOwl-0.1.0-arm64.pkg.sha256`
(use the matching filename for your architecture).

To rebuild from the repository root, run `bash Scripts/package.sh`.
