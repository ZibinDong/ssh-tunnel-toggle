# Repository Guidelines

## Project Structure & Module Organization

This is a macOS SwiftUI menu bar app for managing SSH tunnels.

- `SSHTunnelToggle/` contains all app source, entitlements, and `Info.plist`.
- `SSHTunnelToggle/Models/` contains tunnel configuration, persistence, and SSH process management.
- `SSHTunnelToggle/Views/` contains SwiftUI menu bar and configuration sheet UI.
- `SSHTunnelToggle/Assets.xcassets/` stores app icons and color assets.
- `project.yml` is the XcodeGen project definition; `SSHTunnelToggle.xcodeproj/` is generated from it.
- `scripts/generate_xcodeproj.rb` regenerates the Xcode project, preferring `xcodegen` when installed.
- `build/` is generated output and should not be treated as source.

## Build, Test, and Development Commands

- `xcodegen generate` regenerates `SSHTunnelToggle.xcodeproj` from `project.yml`.
- `ruby scripts/generate_xcodeproj.rb` regenerates the project and prints install guidance if `xcodegen` is unavailable.
- `xcodebuild -project SSHTunnelToggle.xcodeproj -scheme SSHTunnelToggle -configuration Debug build` builds the app locally.
- `open SSHTunnelToggle.xcodeproj` opens the project in Xcode for development and manual runs.

There is currently no test target configured in `project.yml`, so `xcodebuild test` is not expected to run until a test target is added.

## Coding Style & Naming Conventions

Use Swift 5.9 conventions with 4-space indentation. Keep types in PascalCase (`TunnelManager`, `TunnelConfig`) and properties/functions in lowerCamelCase (`autoReconnect`, `startTunnel`). Group files by app layer under `Models` and `Views`, and use `// MARK: -` to separate major sections in longer Swift files. Prefer small SwiftUI subviews or helpers when view bodies become hard to scan.

## Testing Guidelines

Add tests under `SSHTunnelToggleTests/` when introducing testable logic. Name test files after the unit under test, for example `TunnelConfigTests.swift`, and name test methods by behavior, such as `testLoadAllReturnsEmptyArrayWhenConfigIsMissing()`. For process-launching code, isolate argument construction or state transitions so tests do not need to start real SSH sessions.

## Commit & Pull Request Guidelines

Recent history uses short, imperative commits such as `feat: initial SwiftUI menu bar app for SSH tunnel management` and `init`. Continue using concise subjects, preferably `type: summary` for feature or fix work.

Pull requests should include a short description, the build or test command run, screenshots or screen recordings for UI changes, and notes for any changes to entitlements, signing, sandboxing, SSH command arguments, or persisted config format.

## Security & Configuration Tips

Do not commit personal SSH hosts, keys, or generated user config. The app reads `~/.ssh/config` and writes runtime config under Application Support, so keep sample data generic and avoid logging secrets.
