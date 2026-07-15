# Realtime Translator iOS

## Installation authentication

The app creates an anonymous installation through `POST /v1/installations` when
an authenticated request first receives `INVALID_APP_TOKEN`. The public
installation UUID and opaque app token are stored in Keychain. The token is
device-only, is never stored in source or UserDefaults, and is never logged.

## Environment Setup
This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` file. Do not commit the `.xcodeproj` file to source control.

### Installation

1. Install XcodeGen using Homebrew on macOS:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open RealtimeTranslator.xcodeproj
   ```

### Building and Testing
- Build the app directly from Xcode or via command line:
  ```bash
  xcodebuild -project RealtimeTranslator.xcodeproj -scheme RealtimeTranslator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
  ```
- Run unit tests:
  ```bash
  xcodebuild -project RealtimeTranslator.xcodeproj -scheme RealtimeTranslatorTests -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
  ```

## Physical iPhone reconnect acceptance

After building the current `main` with the Stage configuration on a physical iPhone,
run the repository helper from Terminal on the Mac:

```bash
./scripts/collect_ios_reconnect_acceptance.sh
```

The helper uses Xcode's `xcrun devicectl` to detect a connected iPhone and collect
the device model and iOS version. It also records the Xcode version, exact Git commit,
Stage URL, and a sanitized Stage health result. Audio, reconnect behavior, transcripts,
and stop/close are confirmed interactively as `PASS` or `FAIL` because collecting or
recording conversation content is forbidden. The resulting Markdown report is saved
to the Mac desktop and never includes the device identifier, audio, transcript text,
app token, client secret, or API key.

If several iPhones are connected, the helper asks which one to use. Optional flags:

```bash
./scripts/collect_ios_reconnect_acceptance.sh \
  --stage-url https://backend-api-stage-ee06.up.railway.app \
  --output "$HOME/Desktop/ios12-acceptance.md"
```
