# Realtime Translator iOS

## Prototype backend token

Until the installation-token flow is implemented, set `APP_TOKEN` in the active
Xcode scheme environment to the same prototype token configured in the backend
`APP_TOKENS` variable. The token is injected into `LiveBackendClient`; it is not
stored in the repository or printed to logs.

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
